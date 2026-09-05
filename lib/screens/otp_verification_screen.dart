import 'package:flutter/material.dart';
import '../utils/app_toast.dart';
import 'dart:async';
import '../theme/app_theme.dart';
import '../widgets/espere_input.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import 'package:pinput/pinput.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({super.key});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;
  String? _email;
  
  int _resendCooldown = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _resendCooldown = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        timer.cancel();
      }
    });
  }

  String? _type; // 'registration' or 'password_reset'

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_email == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String) {
        _email = args;
        _type = 'registration';
      } else if (args is Map<String, dynamic>) {
        _email = args['email'];
        _type = args['type'] ?? 'registration';
      }
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();

    if (otp.isEmpty || otp.length < 6 || _email == null) {
      AppToast.error(context, 'Please enter the 6-digit OTP.');
      return;
    }

    setState(() {
      _isLoading = true;
      
    });

    if (_type == 'password_reset') {
      final result = await ApiService.verifyPasswordResetOtp(_email!, otp);
      if (!mounted) return;
      if (result.isSuccess) {
        setState(() => _isLoading = false);
        Navigator.pushReplacementNamed(
          context, 
          '/reset-password', 
          arguments: {'email': _email, 'otp': otp},
        );
      } else {
        setState(() {
          _isLoading = false;
        });
        AppToast.error(context, result.error ?? 'Error');
        _otpController.clear();
      }
    } else {
      final result = await ApiService.verifyOtp(_email!, otp);
      if (!mounted) return;

      if (result.isSuccess) {
        await SyncService.syncAll();
        if (!mounted) return;
        setState(() => _isLoading = false);
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      } else {
        setState(() {
          _isLoading = false;
        });
        AppToast.error(context, result.error ?? 'Error');
        _otpController.clear();
      }
    }
  }

  Future<void> _resendOtp() async {
    if (_email == null) return;
    setState(() {
      _isResending = true;
      
    });

    ApiResult<Map<String, dynamic>> result;
    if (_type == 'password_reset') {
      result = await ApiService.forgotPassword(_email!);
    } else {
      result = await ApiService.resendOtp(_email!);
    }

    if (!mounted) return;
    setState(() => _isResending = false);

    if (result.isSuccess) {
      AppToast.success(context, 'OTP resent successfully.');
      _startTimer();
    } else {
      AppToast.error(context, result.error ?? 'Unknown error');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
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
                    Text(
                      _type == 'password_reset' ? 'Reset Password' : 'Verify Email',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Enter the 6-digit OTP sent to\n${_email ?? "your email"}\n(Please also check your spam folder)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: AppColors.dark),
                    ),
                    const SizedBox(height: 32),

                    // ─── Form Area ─────────────────────────────────
                    Column(
                      children: [
                        

                        Pinput(
                          length: 6,
                          controller: _otpController,
                          autofocus: false,
                          defaultPinTheme: PinTheme(
                            width: 48,
                            height: 56,
                            textStyle: const TextStyle(
                              fontSize: 22,
                              color: AppColors.dark,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              border: Border.all(color: AppColors.dark),
                            ),
                          ),
                          focusedPinTheme: PinTheme(
                            width: 48,
                            height: 56,
                            textStyle: const TextStyle(
                              fontSize: 22,
                              color: AppColors.dark,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                              border: Border.all(color: AppColors.accent, width: 2),
                            ),
                          ),
                          onCompleted: (pin) {
                            _verifyOtp();
                          },
                        ),
                        const SizedBox(height: 32),

                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _verifyOtp,
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
                                    'Verify',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _resendCooldown == 0 && !_isResending ? _resendOtp : null,
                          child: _isResending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.dark),
                                )
                              : Text(
                                  _resendCooldown > 0
                                      ? 'Resend OTP in ${_resendCooldown}s'
                                      : 'Resend OTP',
                                  style: TextStyle(
                                    color: _resendCooldown == 0 ? AppColors.dark : AppColors.dark.withOpacity(0.5),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ],
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
