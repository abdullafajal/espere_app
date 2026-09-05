/// Login Screen — pixel-perfect match of login.html.
///
/// Layout: centered card on #F5F5F5 bg
///   - Brand: w-16 h-16 bg-[#1A1A1A] rounded-2xl + wallet icon
///   - Title: "Welcome back" (text-2xl font-bold)
///   - Subtitle: "Sign in to your Espere account" (text-sm text-[#9E9E9E])
///   - Form card: bg-white rounded-[24px] p-6 with shadow
///   - Submit: bg-[#1A1A1A] text-[#C8E64A] rounded-2xl
///   - Footer: "Don't have an account? Create one"
import 'package:flutter/material.dart';
import '../utils/app_toast.dart';
import '../theme/app_theme.dart';
import '../widgets/espere_input.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
import '../utils/update_checker.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateChecker.check(context);
    });
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      AppToast.error(context, 'Please fill in all fields.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final result = await ApiService.login(username, password);

    if (!mounted) return;

    if (result.isSuccess) {
      // Pull initial data before navigating so dashboard isn't empty
      await SyncService.syncAll();
      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      setState(() {
        _isLoading = false;
      });
      AppToast.error(context, result.error ?? 'Login failed');
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
        // Successful login/signup, store token and data
        final data = success.data!;
        await AuthService.setToken(data['token']);
        // Fetch full profile and cache it
        await SyncService.pullData();
        
        if (!mounted) return;
        setState(() => _isLoading = false);
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        setState(() {
          AppToast.error(context, success.error ?? 'Login failed');
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
    _passwordController.dispose();
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

                    // Title
                    const Text(
                      'Welcome back',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Subtitle
                    const Text(
                      'Sign in to your Espere account',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ─── Form Area ─────────────────────────────────
                    Column(
                      children: [
                        

                        // Username
                        EspereInput(
                          label: 'Username or Email',
                          hint: 'Enter username or email',
                          controller: _usernameController,
                          autofocus: false,
                        ),
                        const SizedBox(height: 16),

                        // Password
                        EspereInput(
                          label: 'Password',
                          hint: 'Enter password',
                          controller: _passwordController,
                          obscureText: true,
                        ),
                        const SizedBox(height: 16),

                        // Submit button — App Dark with App Green text
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
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
                                    'Login',
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

                        const SizedBox(height: 12),

                        // Forgot password
                        TextButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/forgot-password');
                          },
                          child: const Text(
                            'Forgot password?',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.dark,
                              fontWeight: FontWeight.w600,
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
                          'Don\'t have an account? ',
                          style: TextStyle(fontSize: 14, color: AppColors.dark),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pushReplacementNamed(
                              context, '/register'),
                          child: const Text(
                            'Sign up',
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
