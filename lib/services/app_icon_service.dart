/// Switches the launcher icon to match the app colour (Android only).
///
/// Each colour has its own launcher entry (an activity-alias) in AndroidManifest.xml;
/// the native side (AppIcon.kt) enables exactly one of them.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppIconService {
  AppIconService._();

  static const _channel = MethodChannel('com.example.espere_app/app_icon');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// The colour name of the icon shown now ("Lime", "Mint", ...), or null if unknown.
  static Future<String?> current() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>('current');
    } catch (_) {
      return null;
    }
  }

  /// Shows the icon in [name]'s colour. Returns false if the phone did not allow it.
  static Future<bool> set(String name) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('set', name) ?? false;
    } catch (_) {
      return false;
    }
  }
}
