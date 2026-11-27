import 'dart:convert';

import 'package:espere_app/services/notification_inbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A tiny stand-in for /api/notifications/: keeps what's saved, one per client_ref.
http.Response _json(Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

class FakeServer {
  final saved = <Map<String, dynamic>>[];
  var nextId = 1;
  var posts = 0;

  Future<http.Response> handle(http.Request r) async {
    if (r.url.path.endsWith('/api/notifications/') && r.method == 'POST') {
      posts++;
      for (final n in (jsonDecode(r.body)['notifications'] as List).cast<Map<String, dynamic>>()) {
        final had = saved.where((s) => s['client_ref'] == n['client_ref']).firstOrNull;
        if (had == null) {
          saved.add({...n, 'id': nextId++});
        } else if (n['is_read'] == true) {
          had['is_read'] = true;
        }
      }
      return _json({'notifications': saved});
    }
    if (r.url.path.endsWith('/api/notifications/') && r.method == 'GET') {
      return _json({'notifications': saved, 'unread_count': 0});
    }
    return http.Response('{}', 404);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('phone-made notifications are saved to the server once and kept read', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 't'});
    final server = FakeServer();
    await http.runWithClient(() async {
      await NotificationInbox.addLocal(title: 'Food at 80%', message: '₹2,000 left', kind: 'budget');
      await NotificationInbox.addLocal(title: 'Travel over', message: '₹120 over', kind: 'budget');
      // addLocal also refreshes in the background; wait for it.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await NotificationInbox.refresh();

      expect(server.saved.length, 2, reason: 'both saved, each once');
      final list = await NotificationInbox.cached();
      expect(list.length, 2);
      expect(list.every((i) => !i.isLocal), isTrue, reason: 'now the server copies');

      // Sending again (another refresh) never makes copies.
      await NotificationInbox.refresh();
      expect(server.saved.length, 2);
      expect((await NotificationInbox.cached()).length, 2);
    }, () => MockClient(server.handle));
  });

  test('offline: the notification stays on the phone until it can be saved', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 't'});
    await http.runWithClient(() async {
      await NotificationInbox.addLocal(title: 'Daily reminder', message: 'Add today', kind: 'daily_reminder');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await NotificationInbox.refresh(), isNull);
    }, () => MockClient((_) async => throw http.ClientException('offline')));
    final list = await NotificationInbox.cached();
    expect(list.single.isLocal, isTrue);
    expect(list.single.title, 'Daily reminder');
  });
}
