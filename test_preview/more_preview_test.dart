import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:espere_app/screens/profile_screen.dart';
import 'package:espere_app/screens/auto_track_settings_screen.dart';
import 'package:espere_app/screens/auto_track_review_screen.dart';
import 'package:espere_app/screens/login_screen.dart';
import 'package:espere_app/screens/register_screen.dart';
import 'package:espere_app/screens/otp_verification_screen.dart';
import 'package:espere_app/screens/forgot_password_screen.dart';
import 'package:espere_app/screens/reset_password_screen.dart';
import 'package:espere_app/screens/invite_screen.dart';
import 'package:espere_app/screens/splash_screen.dart';

import 'preview_harness.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
    silencePlugins();
  });

  testWidgets('settings', (t) => shot(t, 'settings', const ProfileScreen(), scaffold: false, size: const Size(390, 1900)));
  testWidgets('settings_colour', (t) => shot(t, 'settings_colour', const ProfileScreen(), scaffold: false, act: (t) async {
        await t.tap(find.text('App colour'));
        await t.pumpAndSettle();
        await t.tap(find.text('Mint'));
        await t.pumpAndSettle();
      }));
  testWidgets('icon_prompt', (t) => shot(t, 'icon_prompt', const ProfileScreen(), scaffold: false, act: (t) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('com.example.espere_app/app_icon'), (c) async => c.method == 'current' ? 'Lime' : true);
        await t.tap(find.text('App colour'));
        await t.pumpAndSettle();
        await t.tap(find.text('Pink'));
        await t.pumpAndSettle();
        await t.tap(find.text('Done'));
        await t.pumpAndSettle();
        await t.tap(find.text('App icon'));
        for (var k = 0; k < 12; k++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.runAsync(() async {
          for (final e in find.byType(Image).evaluate()) {
            await precacheImage((e.widget as Image).image, e);
          }
        });
        await t.pump();
      }));
  testWidgets('auto_track', (t) => shot(t, 'auto_track', const AutoTrackSettingsScreen(), scaffold: false));
  testWidgets('auto_review', (t) => shot(t, 'auto_review', const AutoTrackReviewScreen(), scaffold: false));
  testWidgets('login', (t) => shot(t, 'login', const LoginScreen(), scaffold: false));
  testWidgets('register', (t) => shot(t, 'register', const RegisterScreen(), scaffold: false));
  testWidgets('otp', (t) => shot(t, 'otp', const OtpVerificationScreen(), scaffold: false));
  testWidgets('forgot', (t) => shot(t, 'forgot', const ForgotPasswordScreen(), scaffold: false));
  testWidgets('reset', (t) => shot(t, 'reset', const ResetPasswordScreen(), scaffold: false));
  testWidgets('invite', (t) => shot(t, 'invite', const InviteScreen(token: 'abc', refUsername: 'talib'), scaffold: false));
  testWidgets('splash', (t) => shot(t, 'splash', const SplashScreen(), scaffold: false));
}
