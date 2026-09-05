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
import '../theme/app_theme.dart';
import '../widgets/espere_input.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';
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
  String? _error;

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
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
        _error = result.error;
      });
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: '1057401697979-6vf6j5fu21ufaiqqh5tfj36l4na40a89.apps.googleusercontent.com',
        scopes: ['email', 'profile'],
      );

      final GoogleSignInAccount? account = await googleSignIn.signIn();
      if (account == null) {
        // User canceled
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication auth = await account.authentication;
      final String? idToken = auth.idToken;

      if (idToken == null) {
        setState(() {
          _error = 'Failed to get Google ID token.';
          _isLoading = false;
        });
        return;
      }

      final result = await ApiService.googleLogin(idToken);
      if (!mounted) return;

      if (result.isSuccess) {
        // Successful login/signup, store token and data
        final data = result.data!;
        await AuthService.setToken(data['token']);
        // Fetch full profile and cache it
        await SyncService.pullData();
        
        if (!mounted) return;
        setState(() => _isLoading = false);
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        setState(() {
          _error = result.error;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Google Sign In failed: $e';
        _isLoading = false;
      });
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
      backgroundColor: AppColors.background,
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

                    // Title — text-2xl font-bold
                    const Text(
                      'Welcome back',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Subtitle — text-sm text-[#9E9E9E]
                    const Text(
                      'Sign in to your Espere account',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ─── Form Card ─────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius:
                            BorderRadius.circular(AppRadius.xxxl),
                        boxShadow: AppShadows.card,
                      ),
                      child: Column(
                        children: [
                          // Error message
                          if (_error != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.errorLight,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.xl),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error,
                                      size: 18, color: AppColors.error),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Username
                          EspereInput(
                            label: 'Username or Email',
                            hint: 'Enter username or email',
                            controller: _usernameController,
                            autofocus: true,
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

                          // Submit button — bg-[#1A1A1A] text-[#C8E64A]
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.accent,
                                      ),
                                    )
                                  : const Text('Login'),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Google Sign In button
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: OutlinedButton(
                              onPressed: _isLoading ? null : _loginWithGoogle,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.border),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.xxl),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Simple G icon
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.dark,
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'G',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Continue with Google',
                                    style: TextStyle(color: AppColors.text),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Forgot password
                          TextButton(
                            onPressed: () {
                              // TODO: Forgot password flow
                            },
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Footer — "Don't have an account? Create one"
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Don't have an account? ",
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.muted,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pushReplacementNamed(
                              context, '/register'),
                          child: const Text(
                            'Create one',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
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
