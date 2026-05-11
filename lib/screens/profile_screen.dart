/// Profile Screen — exact match of profile.html.
///
/// Layout: avatar card → personal info form → preferences → logout button
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../widgets/espere_input.dart';
import '../utils/app_toast.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserModel? _user;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  String _currency = 'INR';
  String _theme = 'light';
  bool _emailReminders = true;

  static const _currencies = [
    ('USD', 'US Dollar (\$)'),
    ('EUR', 'Euro (€)'),
    ('GBP', 'British Pound (£)'),
    ('INR', 'Indian Rupee (₹)'),
    ('JPY', 'Japanese Yen (¥)'),
    ('CAD', 'Canadian Dollar (C\$)'),
    ('AUD', 'Australian Dollar (A\$)'),
    ('PKR', 'Pakistani Rupee (Rs)'),
  ];

  static const _themes = [
    ('light', 'Light'),
    ('dark', 'Dark'),
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final result = await ApiService.getProfile();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result.isSuccess) {
        _user = result.data;
        _firstNameController.text = _user!.firstName;
        _lastNameController.text = _user!.lastName;
        _emailController.text = _user!.email;
        _currency = _user!.currency;
        _theme = _user!.theme;
        _emailReminders = _user!.emailReminders;
      } else {
        _error = result.error;
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });

    final result = await ApiService.updateProfile({
      'first_name': _firstNameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'email': _emailController.text.trim(),
      'currency': _currency,
      'theme': _theme,
      'email_reminders': _emailReminders,
    });

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (result.isSuccess) {
        _user = result.data;
        AppToast.success(context, 'Profile updated successfully.');
      } else {
        _error = result.error;
      }
    });
  }

  Future<void> _logout() async {
    await ApiService.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Top Bar ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        boxShadow: AppShadows.soft,
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: AppColors.text),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Profile',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ),

            // ─── Content ───────────────────────────────────
            Expanded(
              child: _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.accent))
                  : _error != null && _user == null
                      ? Center(
                          child: Text(_error!,
                              style:
                                  const TextStyle(color: AppColors.muted)),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // ─── Avatar Card ────────────────────
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.xxl),
                                  boxShadow: AppShadows.card,
                                ),
                                child: Column(
                                  children: [
                                    // Avatar — user-avatar user-avatar-lg
                                    Container(
                                      width: 72,
                                      height: 72,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: AppColors.avatarGradient,
                                      ),
                                      child: _user?.avatar.isNotEmpty == true
                                          ? ClipOval(
                                              child: Image.network(
                                                _user!.avatar,
                                                fit: BoxFit.cover,
                                                width: 72,
                                                height: 72,
                                              ),
                                            )
                                          : Center(
                                              child: Text(
                                                _user?.initials ?? '?',
                                                style: const TextStyle(
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.dark,
                                                ),
                                              ),
                                            ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _user?.displayName ?? '',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.text,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _user?.email ?? '',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 16),

                              // ─── Personal Info Card ─────────────
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.xxl),
                                  boxShadow: AppShadows.card,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.person,
                                            size: 18,
                                            color: AppColors.muted),
                                        SizedBox(width: 8),
                                        Text(
                                          'Personal Info',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.text,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    EspereInput(
                                      label: 'First Name',
                                      hint: 'First name',
                                      controller: _firstNameController,
                                    ),
                                    const SizedBox(height: 16),
                                    EspereInput(
                                      label: 'Last Name',
                                      hint: 'Last name',
                                      controller: _lastNameController,
                                    ),
                                    const SizedBox(height: 16),
                                    EspereInput(
                                      label: 'Email',
                                      hint: 'Email',
                                      controller: _emailController,
                                      keyboardType:
                                          TextInputType.emailAddress,
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 16),

                              // ─── Preferences Card ───────────────
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.xxl),
                                  boxShadow: AppShadows.card,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.settings,
                                            size: 18,
                                            color: AppColors.muted),
                                        SizedBox(width: 8),
                                        Text(
                                          'Preferences',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.text,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // Currency dropdown
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Currency',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.text,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          width: double.infinity,
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 16),
                                          decoration: BoxDecoration(
                                            color: AppColors.surface,
                                            borderRadius:
                                                BorderRadius.circular(
                                                    AppRadius.lg),
                                            border: Border.all(
                                                color: AppColors.border,
                                                width: 1.5),
                                          ),
                                          child:
                                              DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: _currency,
                                              isExpanded: true,
                                              style: const TextStyle(
                                                  fontSize: 14,
                                                  color: AppColors.text),
                                              dropdownColor:
                                                  AppColors.card,
                                              items: _currencies
                                                  .map((c) =>
                                                      DropdownMenuItem(
                                                        value: c.$1,
                                                        child:
                                                            Text(c.$2),
                                                      ))
                                                  .toList(),
                                              onChanged: (v) {
                                                if (v != null) {
                                                  setState(() =>
                                                      _currency = v);
                                                }
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // Theme dropdown
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Theme',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.text,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          width: double.infinity,
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 16),
                                          decoration: BoxDecoration(
                                            color: AppColors.surface,
                                            borderRadius:
                                                BorderRadius.circular(
                                                    AppRadius.lg),
                                            border: Border.all(
                                                color: AppColors.border,
                                                width: 1.5),
                                          ),
                                          child:
                                              DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: _theme,
                                              isExpanded: true,
                                              style: const TextStyle(
                                                  fontSize: 14,
                                                  color: AppColors.text),
                                              dropdownColor:
                                                  AppColors.card,
                                              items: _themes
                                                  .map((t) =>
                                                      DropdownMenuItem(
                                                        value: t.$1,
                                                        child:
                                                            Text(t.$2),
                                                      ))
                                                  .toList(),
                                              onChanged: (v) {
                                                if (v != null) {
                                                  setState(
                                                      () => _theme = v);
                                                }
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // Email reminders toggle
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Daily Reminders',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight:
                                                      FontWeight.w500,
                                                  color: AppColors.text,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              const Text(
                                                'Receive email reminders to log expenses',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.muted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Switch(
                                          value: _emailReminders,
                                          onChanged: (v) => setState(
                                              () =>
                                                  _emailReminders = v),
                                          activeColor: AppColors.accent,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Save button
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                  onPressed: _isSaving ? null : _save,
                                  child: _isSaving
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.accent,
                                          ),
                                        )
                                      : const Text('Save Changes'),
                                ),
                              ),

                              const SizedBox(height: 12),

                              // Logout button
                              SizedBox(
                                width: double.infinity,
                                child: TextButton.icon(
                                  onPressed: _logout,
                                  icon: const Icon(Icons.logout,
                                      size: 18, color: AppColors.error),
                                  label: const Text(
                                    'Log Out',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.error,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    backgroundColor: AppColors.errorLight,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppRadius.xl),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
