/// The in-app notification list (daily reminders, split updates, …) that the bell on
/// Home opens. Kept on the phone so it shows offline; refreshed from
/// `/api/notifications/` whenever the app can reach the server.
///
/// Notifications made on the phone (daily reminders, budget alerts) show at once with a
/// negative id, and are saved to the server on the next refresh, so they survive a
/// reinstall and show on other phones. Each has a stable `client_ref` (`local:<id>`), so
/// sending one again never makes a copy. Anything older than 90 days is dropped, here
/// and on the server.
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

  /// Set on notifications the phone made and saved to the server.
  final String? clientRef;

  const InboxItem({
    required this.id,
    required this.title,
    required this.message,
    required this.data,
    required this.isRead,
    required this.createdAt,
    this.clientRef,
  });

  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
    id: (j['id'] as num).toInt(),
    title: j['title']?.toString() ?? '',
    message: j['message']?.toString() ?? '',
    data: j['data'] is Map ? Map<String, dynamic>.from(j['data'] as Map) : const {},
    isRead: j['is_read'] == true,
    createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    clientRef: j['client_ref']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'message': message,
    'data': data,
    'is_read': isRead,
    'created_at': createdAt.toUtc().toIso8601String(),
    if (clientRef != null) 'client_ref': clientRef,
  };

  InboxItem read() => InboxItem(
    id: id,
    title: title,
    message: message,
    data: data,
    isRead: true,
    createdAt: createdAt,
    clientRef: clientRef,
  );

  /// Made on the phone (daily reminders, budget alerts) and not saved to the server yet.
  bool get isLocal => id < 0;

  /// The key the server keeps a phone-made notification under.
  String get localRef => 'local:${id.abs()}';

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

  static const keepDays = 90;

  static Future<void> _store(List<InboxItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final oldest = DateTime.now().subtract(const Duration(days: keepDays));
    final kept = items.where((i) => i.createdAt.isAfter(oldest)).take(100);
    await prefs.setString(_key, jsonEncode(kept.map((i) => i.toJson()).toList()));
    _changes.add(null);
  }

  static Future<int> unreadCount() async => (await cached()).where((i) => !i.isRead).length;

  /// Runs read-change-write steps on the stored list one at a time, so a refresh and a
  /// new notification never overwrite each other.
  static Future<void> _tail = Future.value();
  static Future<T> _locked<T>(Future<T> Function() step) {
    final run = _tail.then((_) => step());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  static Future<List<InboxItem>?>? _running;
  static bool _again = false;

  /// Saves the phone-made notifications to the server, then loads the list from it.
  /// Returns null when the server could not be reached. Asked again while running, it
  /// runs once more after, so nothing new is left unsaved.
  static Future<List<InboxItem>?> refresh() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = () async {
      List<InboxItem>? out;
      do {
        _again = false;
        out = await _refreshOnce();
      } while (_again && out != null);
      return out;
    }();
    _running = run;
    run.whenComplete(() => _running = null);
    return run;
  }

  static Future<List<InboxItem>?> _refreshOnce() async {
    {
      final local = (await cached()).where((i) => i.isLocal).toList();
      if (local.isNotEmpty) {
        // Kept on the phone if this fails; sent again next time (never copied twice).
        await ApiService.saveNotifications([
          for (final i in local)
            {
              'client_ref': i.localRef,
              'title': i.title,
              'message': i.message,
              'data': i.data,
              'is_read': i.isRead,
              'created_at': i.createdAt.toUtc().toIso8601String(),
            },
        ]);
      }
      final r = await ApiService.getNotifications(limit: 100);
      if (!r.isSuccess || r.data == null) return null;
      final server =
          ((r.data!['notifications'] as List?) ?? const [])
              .whereType<Map>()
              .map((m) => InboxItem.fromJson(Map<String, dynamic>.from(m)))
              .toList();
      final onServer = {
        for (final s in server)
          if (s.clientRef != null) s.clientRef!,
      };
      return _locked(() async {
        // Read or removed here while this ran: keep that.
        final now = await cached();
        final readHere = {
          for (final i in now)
            if (i.isRead) i.isLocal ? i.localRef : '${i.id}',
        };
        final stillHere = {for (final i in now) i.isLocal ? i.localRef : '${i.id}'};
        // Saved just now but deleted here meanwhile: delete it on the server too.
        for (final s in server) {
          if (s.clientRef != null && !stillHere.contains(s.clientRef) && local.any((l) => l.localRef == s.clientRef)) {
            ApiService.deleteNotification(s.id);
          }
        }
        final merged = <InboxItem>[
          for (final s in server)
            if (s.clientRef == null || stillHere.contains(s.clientRef) || !local.any((l) => l.localRef == s.clientRef))
              (readHere.contains(s.clientRef) || readHere.contains('${s.id}')) && !s.isRead ? s.read() : s,
          // Not saved yet (offline, or made while this ran).
          for (final i in now)
            if (i.isLocal && !onServer.contains(i.localRef)) i,
        ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await _store(merged);
        return merged;
      });
    }
  }

  /// Marks [ids] read (all when null): at once on the phone, then on the server.
  static Future<void> markRead([List<int>? ids]) async {
    await _locked(() async {
      final items = await cached();
      await _store([for (final i in items) (ids == null || ids.contains(i.id)) ? i.read() : i]);
    });
    final serverIds = ids?.where((id) => id > 0).toList();
    if (serverIds != null && serverIds.isEmpty) return;
    await ApiService.markNotificationsRead(serverIds);
  }

  static Future<void> delete(int id) async {
    await _locked(() async => _store((await cached()).where((i) => i.id != id).toList()));
    if (id > 0) await ApiService.deleteNotification(id);
  }

  /// Adds an item made on this phone (negative id, kept across server refreshes).
  static Future<void> addLocal({
    required String title,
    required String message,
    required String kind,
    String? action,
  }) async {
    await _locked(() async {
      final items = await cached();
      final now = DateTime.now();
      // Milliseconds, and never the same as one already here.
      var id = -now.millisecondsSinceEpoch;
      while (items.any((i) => i.id == id)) {
        id--;
      }
      final item = InboxItem(
        id: id,
        title: title,
        message: message,
        data: {'kind': kind, if (action != null) 'action': action, 'local': 'true'},
        isRead: false,
        createdAt: now,
      );
      await _store([item, ...items]);
    });
    refresh(); // saves it to the server when online
  }

  /// A push arrived: fetch the new list.
  static void pushArrived() => refresh();

  static Future<void> clear() async {
    (await SharedPreferences.getInstance()).remove(_key);
    _changes.add(null);
  }
}
