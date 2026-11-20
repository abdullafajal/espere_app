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

  /// Uses [name]'s colour for the launch splash from the next start (Android 13+).
  static Future<void> setSplash(String name) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('setSplash', name);
    } catch (_) {}
  }

  /// The logo picture in a colour, for showing in the app ("Lime" -> assets/icons/app_icon_lime.png).
  static String logoAsset(String name) => 'assets/icons/app_icon_${name.toLowerCase()}.png';

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
