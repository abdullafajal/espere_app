import 'package:flutter/material.dart';
import 'theme/motion.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';

import 'theme/app_theme.dart';
import 'widgets/morph_text.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/otp_verification_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/home_screen.dart';
import 'screens/quick_add_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/invite_screen.dart';
import 'services/app_icon_service.dart';
import 'services/notification_service.dart';
import 'services/connectivity_service.dart';
import 'services/sync_service.dart';
import 'services/deep_link_service.dart';
import 'services/auto_expense_service.dart';
import 'services/receipt_service.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (graceful failure if config is missing)
  try {
    await Firebase.initializeApp();
    await NotificationService.init(rootScaffoldMessengerKey, rootNavigatorKey);
  } catch (e) {
    debugPrint('[Firebase] Init failed: $e');
  }

  // Initialize connectivity monitoring
  await ConnectivityService.init();

  // Initialize Deep Linking
  DeepLinkService.init(rootNavigatorKey);

  // Auto-track payments (no-op unless the user turned it on)
  AutoExpenseService.init();

  // Payment receipts shared to Espere (Share -> Espere) open the Add Transaction form
  ReceiptService.init();

  // Initial sync if online
  if (ConnectivityService.isOnline) {
    SyncService.syncAll();
  }

  // Auto-sync when device comes back online
  ConnectivityService.onReconnect.listen((_) {
    debugPrint('[Sync] Device reconnected — syncing pending operations and pulling data...');
    SyncService.syncAll();
  });

  // Set status bar style to match the app design
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));

  await AppAccent.load();
  await EditAnimation.load();
  // Keep the start-up splash in the chosen app colour (Android 13+; takes effect next start).
  AppIconService.setSplash(AppAccent.current.name);
  runApp(const EspereApp());
}

class EspereApp extends StatefulWidget {
  const EspereApp({super.key});

  @override
  State<EspereApp> createState() => _EspereAppState();
}

class _EspereAppState extends State<EspereApp> {
  // Use Stopwatch instead of DateTime to prevent GC allocation lag on low-end devices
  final Stopwatch _throttleStopwatch = Stopwatch()..start();
  bool _atEdge = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      title: 'Espere',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      scrollBehavior: const EspereScrollBehavior(),

      builder: (context, child) {
        return NotificationListener<ScrollNotification>(
          // One light tick when a list reaches its end (it then bounces on the app's
          // spring, see EspereScrollPhysics). Not again until it is back in range.
          onNotification: (notification) {
            if (notification.metrics.axis != Axis.vertical) return false;
            final out = notification.metrics.outOfRange || notification is OverscrollNotification;
            if (out && !_atEdge && _throttleStopwatch.elapsedMilliseconds > 700) {
              AppHaptics.land();
              _throttleStopwatch.reset();
            }
            _atEdge = out;
            return false;
          },
          child: child ?? const SizedBox.shrink(),
        );
      },


      // ─── Named Routes ────────────────────────────────────────
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/verify-otp': (context) => const OtpVerificationScreen(),
        '/forgot-password': (context) => const ForgotPasswordScreen(),
        '/reset-password': (context) => const ResetPasswordScreen(),
        '/home': (context) => const HomeScreen(),
        '/categories': (context) => const CategoriesScreen(),
        '/profile': (context) => const ProfileScreen(),
      },

      // ─── Dynamic Routes (for passing arguments) ──────────────
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/transaction/add':
            final type = settings.arguments as String?;
            return MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => QuickAddScreen(type: type == 'income' ? 'income' : 'expense'),
            );

          case '/transaction/edit':
            final id = settings.arguments as int;
            return MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => QuickAddScreen(editId: id),
            );

          case '/invite':
            String token = '';
            String ref = '';
            if (settings.arguments is String) {
              token = settings.arguments as String;
            } else if (settings.arguments is Map) {
              final map = settings.arguments as Map;
              token = map['token'] ?? '';
              ref = map['ref'] ?? '';
            }
            return MaterialPageRoute(
              builder: (_) => InviteScreen(token: token, refUsername: ref),
            );

          default:
            return MaterialPageRoute(
              builder: (_) => const SplashScreen(),
            );
        }
      },
    );
  }
}
