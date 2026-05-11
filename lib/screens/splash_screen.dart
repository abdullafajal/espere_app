import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';

/// Initializing screen that handles auth-routing.
/// UI is kept black to match the native splash screen for a seamless handoff.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _handleAuth();
  }

  Future<void> _handleAuth() async {
    // Check authentication state
    final isAuth = await AuthService.isAuthenticated();
    
    if (!mounted) return;
    
    // Remove native splash and navigate immediately
    FlutterNativeSplash.remove();
    
    Navigator.pushReplacementNamed(
      context,
      isAuth ? '/home' : '/login',
    );
  }

  @override
  Widget build(BuildContext context) {
    // Return a solid black screen to maintain visual continuity with the native splash
    return const Scaffold(
      backgroundColor: AppColors.dark,
      body: SizedBox.expand(),
    );
  }
}
