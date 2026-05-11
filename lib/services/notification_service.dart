import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../screens/split_group_detail_screen.dart';

/// Handles background messages (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message: ${message.messageId}');
}

class NotificationService {
  /// Initialize FCM — safe to call even if Firebase config is missing/invalid.
  static Future<void> init(GlobalKey<ScaffoldMessengerState>? messengerKey, GlobalKey<NavigatorState>? navigatorKey) async {
    try {
      final fcm = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Request permission
      await fcm.requestPermission(alert: true, badge: true, sound: true);

      void handleMessageAction(Map<String, dynamic> data) {
        if (data['action'] == 'open_split_group' && data['group_id'] != null && navigatorKey?.currentContext != null) {
          navigatorKey!.currentState?.push(
            MaterialPageRoute(
              builder: (_) => SplitGroupDetailScreen(
                groupId: int.parse(data['group_id'].toString()),
                groupName: data['group_name']?.toString() ?? 'Group',
              ),
            ),
          );
        }
      }

      // Foreground messages
      FirebaseMessaging.onMessage.listen((msg) {
        debugPrint('[FCM] Foreground: ${msg.notification?.title}');
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
                textColor: const Color(0xFF00C853), // AppColors.accent
                onPressed: () {
                  handleMessageAction(msg.data);
                },
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
              backgroundColor: const Color(0xFF1E1E1E), // AppColors.dark surface
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      });

      // Tap to open
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        debugPrint('[FCM] Opened: ${msg.data}');
        handleMessageAction(msg.data);
      });

      // Try to get token (will fail with placeholder google-services.json)
      try {
        final token = await fcm.getToken();
        if (token != null) debugPrint('[FCM] Token: $token');
      } catch (_) {
        debugPrint('[FCM] Token unavailable — replace google-services.json with real file');
      }
    } catch (e) {
      debugPrint('[FCM] Init skipped: $e');
    }
  }

  /// Get current FCM token safely
  static Future<String?> getToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('[FCM] getToken error: $e');
      return null;
    }
  }
}
