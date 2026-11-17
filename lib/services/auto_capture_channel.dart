/// Thin wrapper around the native auto-capture channels (Android only).
/// See android/.../autocapture/AutoCaptureBridge.kt.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AutoCaptureSource {
  final String id;
  final String label;
  const AutoCaptureSource(this.id, this.label);
}

class AutoCaptureChannel {
  AutoCaptureChannel._();

  static const _method = MethodChannel('com.example.espere_app/auto_capture');
  static const _events = EventChannel('com.example.espere_app/auto_capture_events');

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Fires when the listener queued new candidate events.
  static Stream<void> get newEvents => isSupported
      ? _events.receiveBroadcastStream().map((_) {})
      : const Stream<void>.empty();

  static Future<T?> _call<T>(String method, [Map<String, dynamic>? args]) async {
    if (!isSupported) return null;
    try {
      return await _method.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('[AutoCapture] $method failed: ${e.code}');
      return null;
    }
  }

  /// False when this build does not include the notification listener (website APK).
  static Future<bool> isAvailable() async => (await _call<bool>('isAvailable')) ?? false;

  static Future<bool> isPermissionGranted() async =>
      (await _call<bool>('isPermissionGranted')) ?? false;

  static Future<void> openPermissionSettings() => _call<void>('openPermissionSettings');

  static Future<List<Map<dynamic, dynamic>>> getPendingEvents() async {
    final list = await _call<List<dynamic>>('getPendingEvents');
    return (list ?? const []).whereType<Map<dynamic, dynamic>>().toList();
  }

  static Future<void> ackEvents(List<String> ids) async {
    if (ids.isEmpty) return;
    await _call<void>('ackEvents', {'ids': ids});
  }

  static Future<void> clearAll() => _call<void>('clearAll');

  static Future<void> setConfig({required bool enabled, required List<String> disabledGroups}) =>
      _call<void>('setConfig', {'enabled': enabled, 'disabledGroups': disabledGroups});

  static Future<List<AutoCaptureSource>> getSources() async {
    final list = await _call<List<dynamic>>('getSources') ?? const [];
    return list
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => AutoCaptureSource(m['id'].toString(), m['label'].toString()))
        .toList();
  }

  static Future<void> showAddedNotification({required String title, required String body}) =>
      _call<void>('showAddedNotification', {'title': title, 'body': body});
}
