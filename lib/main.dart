import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';

import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/transaction_form_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/profile_screen.dart';
import 'services/notification_service.dart';
import 'services/connectivity_service.dart';
import 'services/sync_service.dart';
import 'package:dynamic_color/dynamic_color.dart';

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

  // Initial sync if online
  if (ConnectivityService.isOnline) {
    SyncService.processSyncQueue();
  }

  // Auto-sync when device comes back online
  ConnectivityService.onReconnect.listen((_) {
    debugPrint('[Sync] Device reconnected — syncing pending operations...');
    SyncService.processSyncQueue();
  });

  // Set status bar style to match the app design
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));

  runApp(const EspereApp());
}

class EspereApp extends StatelessWidget {
  const EspereApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ColorScheme lightColorScheme;
        ColorScheme darkColorScheme;

        if (lightDynamic != null && darkDynamic != null) {
          lightColorScheme = lightDynamic.harmonized();
          darkColorScheme = darkDynamic.harmonized();
        } else {
          lightColorScheme = ColorScheme.fromSeed(
            seedColor: AppColors.accent,
            brightness: Brightness.light,
          );
          darkColorScheme = ColorScheme.fromSeed(
            seedColor: AppColors.accent,
            brightness: Brightness.dark,
          );
        }

        return MaterialApp(
          navigatorKey: rootNavigatorKey,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          title: 'Espere',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme.copyWith(
            colorScheme: lightColorScheme,
            useMaterial3: true,
          ),
          darkTheme: AppTheme.darkTheme.copyWith(
            colorScheme: darkColorScheme,
            useMaterial3: true,
          ),
          themeMode: ThemeMode.system,

          // ─── Named Routes ────────────────────────────────────────
          initialRoute: '/',
          routes: {
            '/': (context) => const SplashScreen(),
            '/login': (context) => const LoginScreen(),
            '/register': (context) => const RegisterScreen(),
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
                  builder: (_) => TransactionFormScreen(presetType: type),
                );

              case '/transaction/edit':
                final id = settings.arguments as int;
                return MaterialPageRoute(
                  builder: (_) => TransactionFormScreen(transactionId: id),
                );

              default:
                return MaterialPageRoute(
                  builder: (_) => const SplashScreen(),
                );
            }
          },
        );
      },
    );
  }
}
