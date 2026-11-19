/// Morning and night reminders, scheduled on the phone (Android AlarmManager, see
/// `reminders/DailyReminder.kt`). They need no server and work offline. The message is
/// built from the transactions saved on the phone, and each one is also added to the
/// in-app Notifications list.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReminderSlot { morning, night }

class ReminderSetting {
  final bool on;

  /// Minutes after midnight.
  final int minutes;
  const ReminderSetting(this.on, this.minutes);
}

class DailyReminders {
  DailyReminders._();

  static const _channel = MethodChannel('com.example.espere_app/reminders');

  static const defaults = {ReminderSlot.morning: 9 * 60, ReminderSlot.night: 21 * 60};

  /// Read by the Android side: minutes after midnight, -1 = off.
  static String _key(ReminderSlot s) => 'reminder_${s.name}';

  /// The time to come back to when a reminder is switched on again.
  static String _lastKey(ReminderSlot s) => 'reminder_${s.name}_time';

  static Future<ReminderSetting> get(ReminderSlot slot) async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_key(slot));
    final last = prefs.getInt(_lastKey(slot)) ?? defaults[slot]!;
    if (v == null) return ReminderSetting(true, defaults[slot]!);
    return v < 0 ? ReminderSetting(false, last) : ReminderSetting(true, v);
  }

  static Future<void> set(ReminderSlot slot, ReminderSetting s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastKey(slot), s.minutes);
    await prefs.setInt(_key(slot), s.on ? s.minutes : -1);
    if (s.on) await askPermission();
    await reschedule();
  }

  static Future<void> reschedule() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('reschedule');
    } catch (_) {}
  }

  /// Android 13+: notifications need the user's OK.
  static Future<void> askPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      if (await Permission.notification.isDenied) await Permission.notification.request();
    } catch (_) {}
  }

  static String label(int minutes) {
    final h = minutes ~/ 60, m = minutes % 60;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }
}
