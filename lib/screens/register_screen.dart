/// Register Screen — pixel-perfect match of register.html.
///
/// Same layout as login but with 4 fields: username, email, password, confirm
import 'package:flutter/material.dart';
import '../utils/app_toast.dart';
import '../theme/app_theme.dart';
import '../widgets/espere_input.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import 'package:google_sign_in/google_sign_in.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _password2Controller = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _fieldErrors;

  Future<void> _register() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final password2 = _password2Controller.text;

    if (username.isEmpty || email.isEmpty || password.isEmpty) {
      AppToast.error(context, 'Please fill in all fields.');
      return;
    }
    if (password != password2) {
      AppToast.error(context, 'Passwords do not match.');
      return;
    }

    setState(() {
      _isLoading = true;
      _fieldErrors = null;
    });

    final result =
        await ApiService.register(username, email, password, password2);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.isSuccess) {
      Navigator.pushReplacementNamed(
        context, 
        '/verify-otp',
        arguments: email,
      );
    } else if (result.errors != null) {
      setState(() => _fieldErrors = result.errors);
      AppToast.error(context, result.error ?? 'Registration failed');
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize(
        serverClientId: '1057401697979-6vf6j5fu21ufaiqqh5tfj36l4na40a89.apps.googleusercontent.com',
      );

      // Listen for the result of authenticate()
      final futureEvent = googleSignIn.authenticationEvents.firstWhere(
        (e) => e is GoogleSignInAuthenticationEventSignIn || e is GoogleSignInAuthenticationEventSignOut
      );

      await googleSignIn.authenticate();

      final event = await futureEvent;
      if (event is GoogleSignInAuthenticationEventSignOut) {
        setState(() {
          _isLoading = false;
        });
        AppToast.info(context, 'Google Sign In was canceled.');
        return;
      }

      final signInEvent = event as GoogleSignInAuthenticationEventSignIn;
      final googleUser = signInEvent.user;
      
      // authentication might be synchronous or Future depending on platform
      final dynamic userAuth = googleUser.authentication;
      final googleAuth = userAuth is Future ? await userAuth : userAuth;

      final success = await ApiService.googleLogin(
        googleAuth.idToken ?? '',
      );

      if (success.isSuccess) {
        final data = success.data!;
        await AuthService.setToken(data['token']);
        await SyncService.pullData();
        
        if (!mounted) return;
        setState(() => _isLoading = false);
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        setState(() {
          AppToast.error(context, success.error ?? 'Registration failed');
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (e.toString().toLowerCase().contains('cancel')) {
        AppToast.info(context, 'Google Sign-In canceled.');
      } else {
        AppToast.error(context, 'Google Sign In failed: $e');
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _password2Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  children: [
                    // Logo
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
                      'Create Account',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Start tracking with Espere today',
                      style: TextStyle(fontSize: 14, color: AppColors.dark),
                    ),
                    const SizedBox(height: 32),

                    // ─── Form Area ─────────────────────────────────
                    Column(
                      children: [
                        // Errors
                        if (_fieldErrors != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.error),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.xl),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.error,
                                    size: 18, color: AppColors.error),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _fieldErrors!.values
                                        .map((v) => v.toString())
                                        .join('\n'),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        EspereInput(
                          label: 'Username',
                          hint: 'Choose a username',
                          controller: _usernameController,
                          autofocus: false,
                        ),
                        const SizedBox(height: 16),

                        EspereInput(
                          label: 'Email',
                          hint: 'your@email.com',
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),

                        EspereInput(
                          label: 'Password',
                          hint: 'Create a password',
                          controller: _passwordController,
                          obscureText: true,
                        ),
                        const SizedBox(height: 16),

                        EspereInput(
                          label: 'Confirm Password',
                          hint: 'Confirm your password',
                          controller: _password2Controller,
                          obscureText: true,
                        ),
                        const SizedBox(height: 16),

                        // Submit button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _register,
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
                                    'Create Account',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // OR Divider
                        Row(
                          children: [
                            const Expanded(child: Divider(color: AppColors.border, thickness: 1)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text('OR', style: TextStyle(color: AppColors.muted, fontSize: 14)),
                            ),
                            const Expanded(child: Divider(color: AppColors.border, thickness: 1)),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Google Sign In button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            onPressed: _isLoading ? null : _loginWithGoogle,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: AppColors.dark),
                              shape: const StadiumBorder(),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset(
                                  'assets/icons/google.png',
                                  height: 24,
                                  width: 24,
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Continue with Google',
                                  style: TextStyle(
                                    color: AppColors.dark,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Already have an account? ',
                          style: TextStyle(fontSize: 14, color: AppColors.dark),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pushReplacementNamed(
                              context, '/login'),
                          child: const Text(
                            'Sign in',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.dark,
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
      ),
    );
  }
}
