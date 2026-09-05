import 'package:flutter/material.dart';
import '../utils/app_toast.dart';
import '../theme/app_theme.dart';
import '../widgets/espere_input.dart';
import '../services/api_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isLoading = false;
  String? _email;
  String? _otp;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_email == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _email = args['email'];
        _otp = args['otp'];
      }
    }
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (password.isEmpty || confirmPassword.isEmpty) {
      AppToast.error(context, 'Please fill out both fields.');
      return;
    }

    if (password != confirmPassword) {
      AppToast.error(context, 'Passwords do not match.');
      return;
    }

    if (password.length < 6) {
      AppToast.error(context, 'Password must be at least 6 characters.');
      return;
    }

    if (_email == null || _otp == null) {
      AppToast.error(context, 'Missing email or OTP. Please start over.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final result = await ApiService.resetPassword(_email!, _otp!, password);

    if (!mounted) return;

    if (result.isSuccess) {
      setState(() => _isLoading = false);
      AppToast.success(context, 'Password reset successfully. Please log in.');
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } else {
      setState(() {
        AppToast.error(context, result.error ?? 'Unknown error');
          _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      child: Image.asset(
                        'assets/logo.png',
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Set New Password',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please enter your new password below.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 32),

                    

                    EspereInput(
                      label: 'New Password',
                      hint: 'Enter your new password',
                      controller: _passwordController,
                      obscureText: true,
                      autofocus: false,
                    ),
                    const SizedBox(height: 16),
                    EspereInput(
                      label: 'Confirm Password',
                      hint: 'Re-enter your new password',
                      controller: _confirmPasswordController,
                      obscureText: true,
                      autofocus: false,
                    ),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.dark,
                          foregroundColor: AppColors.accent,
                          shape: const StadiumBorder(),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accent,
                                ),
                              )
                            : const Text(
                                'Reset Password',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppShadows.soft,
                  ),
                  child: const Icon(Icons.arrow_back, color: AppColors.text, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
