import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/connectivity_service.dart';

class FullOfflineAlert extends StatefulWidget {
  final Widget child;

  const FullOfflineAlert({super.key, required this.child});

  @override
  State<FullOfflineAlert> createState() => _FullOfflineAlertState();
}

class _FullOfflineAlertState extends State<FullOfflineAlert>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: ConnectivityService.onConnectivityChanged,
      initialData: ConnectivityService.isOnline,
      builder: (context, snapshot) {
        final isOnline = snapshot.data ?? false;

        if (!isOnline) {
          _controller.forward(from: 0.0);
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      size: 80,
                      color: AppColors.muted,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'You are offline',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This feature requires an active internet connection.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.muted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => Navigator.maybePop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.card,
                          foregroundColor: AppColors.text,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.xxl),
                            side: const BorderSide(color: AppColors.border),
                          ),
                        ),
                        child: const Text('Go Back'),
                      ),
                    ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return widget.child;
      },
    );
  }
}
