/// The in-app notification list (daily reminders, split updates, …) that the bell on
/// Home opens. Kept on the phone so it shows offline; refreshed from
/// `/api/notifications/` whenever the app can reach the server.
library;

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class InboxItem {
  final int id;
  final String title;
  final String message;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime createdAt;

  const InboxItem({
    required this.id,
    required this.title,
    required this.message,
    required this.data,
    required this.isRead,
    required this.createdAt,
  });

  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
        id: (j['id'] as num).toInt(),
        title: j['title']?.toString() ?? '',
        message: j['message']?.toString() ?? '',
        data: j['data'] is Map ? Map<String, dynamic>.from(j['data'] as Map) : const {},
        isRead: j['is_read'] == true,
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'message': message,
        'data': data,
        'is_read': isRead,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  InboxItem read() => InboxItem(
        id: id,
        title: title,
        message: message,
        data: data,
        isRead: true,
        createdAt: createdAt,
      );

  /// Made on the phone (daily reminders), not by the server.
  bool get isLocal => id < 0;

  String get kind => data['kind']?.toString() ?? data['action']?.toString() ?? '';
}

class NotificationInbox {
  NotificationInbox._();

  static const _key = 'cache_notifications';
  static final _changes = StreamController<void>.broadcast();

  /// Fires when the list or the unread count changes.
  static Stream<void> get changes => _changes.stream;

  static Future<List<InboxItem>> cached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // reminders are added by the Android side
      final raw = prefs.getString(_key);
      if (raw == null) return const [];
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => InboxItem.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _store(List<InboxItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items.map((i) => i.toJson()).toList()));
    _changes.add(null);
  }

  static Future<int> unreadCount() async => (await cached()).where((i) => !i.isRead).length;

  /// Loads the list from the server. Returns null when it could not be reached.
  static Future<List<InboxItem>?> refresh() async {
    final r = await ApiService.getNotifications();
    if (!r.isSuccess || r.data == null) return null;
    final server = ((r.data!['notifications'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => InboxItem.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    final local = (await cached()).where((i) => i.isLocal);
    final items = [...server, ...local]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _store(items.take(100).toList());
    return items;
  }

  /// Marks [ids] read (all when null): at once on the phone, then on the server.
  static Future<void> markRead([List<int>? ids]) async {
    final items = await cached();
    await _store([
      for (final i in items) (ids == null || ids.contains(i.id)) ? i.read() : i,
    ]);
    final serverIds = ids?.where((id) => id > 0).toList();
    if (serverIds != null && serverIds.isEmpty) return;
    await ApiService.markNotificationsRead(serverIds);
  }

  static Future<void> delete(int id) async {
    final items = await cached();
    await _store(items.where((i) => i.id != id).toList());
    if (id > 0) await ApiService.deleteNotification(id);
  }

  /// Adds an item made on this phone (negative id, kept across server refreshes).
  static Future<void> addLocal({
    required String title,
    required String message,
    required String kind,
    String? action,
  }) async {
    final items = await cached();
    final now = DateTime.now();
    final item = InboxItem(
      id: -(now.millisecondsSinceEpoch ~/ 1000),
      title: title,
      message: message,
      data: {'kind': kind, if (action != null) 'action': action, 'local': 'true'},
      isRead: false,
      createdAt: now,
    );
    await _store([item, ...items].take(100).toList());
  }

  /// A push arrived: fetch the new list.
  static void pushArrived() => refresh();

  static Future<void> clear() async {
    (await SharedPreferences.getInstance()).remove(_key);
    _changes.add(null);
  }
}
