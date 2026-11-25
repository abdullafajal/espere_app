import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../screens/split_group_detail_screen.dart';
import '../theme/app_theme.dart';
import 'app_navigation.dart';
import 'notification_inbox.dart';

/// Handles background messages (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message: ${message.messageId}');
}

class NotificationService {
  /// Completes once Firebase is set up (it now starts after the first screen), so a
  /// token request made earlier waits for it instead of failing.
  static final Completer<void> _ready = Completer<void>();
  static void markReady() {
    if (!_ready.isCompleted) _ready.complete();
  }

  static GlobalKey<NavigatorState>? _navigatorKey;

  /// Opens what a notification is about (from a push or the Notifications screen).
  static void openAction(Map<String, dynamic> data) {
    final nav = _navigatorKey?.currentState;
    if (nav == null) return;
    final id = int.tryParse(data['notification_id']?.toString() ?? '');
    if (id != null) NotificationInbox.markRead([id]);
    switch (data['action']) {
      case 'open_split_group':
        final groupId = int.tryParse(data['group_id']?.toString() ?? '');
        if (groupId == null) return;
        nav.push(MaterialPageRoute(
          builder: (_) => SplitGroupDetailScreen(
            groupId: groupId,
            groupName: data['group_name']?.toString() ?? 'Group',
          ),
        ));
      case 'open_quick_add':
        nav.popUntil((r) => r.isFirst);
        nav.pushNamed('/transaction/add');
      case 'open_friends':
        nav.popUntil((r) => r.isFirst);
        AppNavigation.openTab(3);
      case 'open_split_invitations':
        nav.popUntil((r) => r.isFirst);
        AppNavigation.openTab(4);
      default:
        nav.popUntil((r) => r.isFirst);
    }
  }

  /// Initialize FCM — safe to call even if Firebase config is missing/invalid.
  static Future<void> init(GlobalKey<ScaffoldMessengerState>? messengerKey, GlobalKey<NavigatorState>? navigatorKey) async {
    try {
      final fcm = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Request permission
      await fcm.requestPermission(alert: true, badge: true, sound: true);

      _navigatorKey = navigatorKey;
      void handleMessageAction(Map<String, dynamic> data) => openAction(data);

      // Foreground messages
      FirebaseMessaging.onMessage.listen((msg) {
        debugPrint('[FCM] Foreground: ${msg.notification?.title}');
        NotificationInbox.pushArrived();
        if (msg.notification != null && messengerKey != null) {
          messengerKey.currentState?.showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(msg.notification!.title ?? 'Notification', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(msg.notification!.body ?? '', style: const TextStyle(fontSize: 12)),
                ],
              ),
              action: SnackBarAction(
                label: 'View',
                textColor: AppColors.accent,
                onPressed: () {
                  handleMessageAction(msg.data);
                },
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
              backgroundColor: AppColors.dark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          );
        }
      });

      // Tap to open
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        debugPrint('[FCM] Opened: ${msg.data}');
        NotificationInbox.pushArrived();
        handleMessageAction(msg.data);
      });

      // Handle message when app is completely closed
      final initialMsg = await fcm.getInitialMessage();
      if (initialMsg != null) {
        debugPrint('[FCM] Initial: ${initialMsg.data}');
        Future.delayed(const Duration(milliseconds: 500), () {
          handleMessageAction(initialMsg.data);
        });
      }

    } catch (e) {
      debugPrint('[FCM] Init skipped: $e');
    }
  }

  /// Get current FCM token safely
  static Future<String?> getToken() async {
    try {
      await _ready.future.timeout(const Duration(seconds: 20), onTimeout: () {});
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('[FCM] getToken error: $e');
      return null;
    }
  }
}
