/// Profile Screen — exact match of profile.html.
///
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';
import '../widgets/espere_input.dart';
import '../utils/app_toast.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserModel? _user;
  String? _baseUrl;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  String _currency = 'INR';
  String _theme = 'light';
  bool _emailReminders = true;

  static final _currencies = const [
    ('USD', '\$', 'US Dollar (USD)'),
    ('EUR', '€', 'Euro (EUR)'),
    ('GBP', '£', 'British Pound (GBP)'),
    ('INR', '₹', 'Indian Rupee (INR)'),
    ('PKR', 'Rs', 'Pakistani Rupee (PKR)'),
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
    _baseUrl = await AuthService.getBaseUrl();
    // 1. Load from cache first
    final cached = await CacheService.getCachedUser();
    if (cached != null && mounted) {
      setState(() {
        _user = UserModel.fromJson(cached);
        _firstNameController.text = _user!.firstName;
        _lastNameController.text = _user!.lastName;
        _emailController.text = _user!.email;
        _currency = _user!.currency;
        _theme = _user!.theme;
        _emailReminders = _user!.emailReminders;
        _isLoading = false;
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });

    final data = {
      'first_name': _firstNameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'email': _emailController.text.trim(),
      'currency': _currency,
      'theme': _theme,
      'email_reminders': _emailReminders,
    };

    ApiResult result;
    if (ConnectivityService.isOnline) {
      result = await ApiService.updateProfile(data);
    } else {
      // Offline mode: queue operation
      await SyncService.queueOperation(
        action: 'update',
        entity: 'profile',
        data: data,
        entityId: _user?.id ?? 0,
      );

      // Optimistic Update
      if (_user != null) {
        final newUserJson = _user!.toJson();
        newUserJson['first_name'] = data['first_name'];
        newUserJson['last_name'] = data['last_name'];
        newUserJson['email'] = data['email'];
        newUserJson['currency'] = data['currency'];
        newUserJson['theme'] = data['theme'];
        newUserJson['email_reminders'] = data['email_reminders'];
        
        await CacheService.cacheUser(newUserJson);
        result = ApiResult(data: UserModel.fromJson(newUserJson));
      } else {
        result = ApiResult(data: null);
      }
    }

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (result.isSuccess && result.data != null) {
        _user = result.data;
        AppToast.success(context, 'Profile updated successfully.');
      } else if (!ConnectivityService.isOnline) {
        AppToast.success(context, 'Profile update queued.');
      } else {
        _error = result.error;
      }
    });
  }

  Future<void> _logout() async {
    await ApiService.logout();
    await CacheService.clearAll();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked != null) {
        // Interactive crop to square
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: picked.path,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          maxWidth: 500,
          maxHeight: 500,
          compressFormat: ImageCompressFormat.jpg,
          compressQuality: 70,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Avatar',
              toolbarColor: Colors.white,
              toolbarWidgetColor: AppColors.text,
              activeControlsWidgetColor: AppColors.accent,
              statusBarColor: Colors.white,
              backgroundColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
              hideBottomControls: false,
            ),
            IOSUiSettings(
              title: 'Crop Avatar',
              aspectRatioLockEnabled: true,
              resetAspectRatioEnabled: false,
            ),
          ],
        );

        if (croppedFile != null && croppedFile.path.isNotEmpty) {
          setState(() => _isLoading = true);
          
          final result = await ApiService.uploadAvatar(croppedFile.path);
          if (result.isSuccess && mounted) {
            setState(() {
              _user = result.data;
              _isLoading = false;
            });
            AppToast.success(context, 'Avatar updated successfully.');
            CacheService.cacheUser(_user!.toJson());
          } else {
            if (mounted) {
              setState(() => _isLoading = false);
              AppToast.error(context, result.error ?? 'Failed to upload avatar.');
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, "Failed to pick/crop image: '$e'.");
      }
    }
  }

  void _showCurrencyPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final maxHeight = MediaQuery.of(context).size.height * 0.85;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select Currency',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 24),
                
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _currencies.length,
                    itemBuilder: (_, i) {
                      final c = _currencies[i];
                      final isSelected = _currency == c.$1;

                      return GestureDetector(
                        onTap: () {
                          setState(() => _currency = c.$1);
                          Navigator.pop(ctx);
                          _save();
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.accent.withOpacity(0.15)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            border: Border.all(
                              color: isSelected ? AppColors.accent : AppColors.border,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  c.$2,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.dark,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  c.$3,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                    color: AppColors.text,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check, color: AppColors.accent, size: 20),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showChangePasswordDialog() {
    final oldPasswordCtrl = TextEditingController();
    final newPasswordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();
    bool isChanging = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Container(
          padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text('Change Password', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text)),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EspereInput(
                      controller: oldPasswordCtrl,
                      label: 'Current Password',
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    EspereInput(
                      controller: newPasswordCtrl,
                      label: 'New Password',
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    EspereInput(
                      controller: confirmPasswordCtrl,
                      label: 'Confirm New Password',
                      obscureText: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isChanging
                      ? null
                      : () async {
                          if (newPasswordCtrl.text != confirmPasswordCtrl.text) {
                            AppToast.error(context, 'Passwords do not match');
                            return;
                          }
                          ss(() => isChanging = true);
                          final res = await ApiService.changePassword(
                            oldPasswordCtrl.text,
                            newPasswordCtrl.text,
                          );
                          ss(() => isChanging = false);
                          
                          if (res.isSuccess) {
                            if (mounted) Navigator.pop(context);
                            AppToast.success(context, res.data ?? 'Password updated');
                          } else {
                            AppToast.error(context, res.error ?? 'Error');
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.dark,
                    foregroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: isChanging
                      ? const CircularProgressIndicator(color: AppColors.accent)
                      : const Text('Update Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String _getAvatarUrl() {
    final avatar = _user?.avatar ?? '';
    if (avatar.isEmpty) return '';
    if (avatar.startsWith('http')) return avatar;
    
    final base = _baseUrl ?? 'http://10.0.2.2:8000';
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final a = avatar.startsWith('/') ? avatar : '/$avatar';
    
    return '$b$a';
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 24),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
          color: AppColors.muted,
        ),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildRow({
    IconData? icon,
    Widget? customIcon,
    required String title,
    String? value,
    String? subtitle,
    Widget? trailing,
    bool showDivider = true,
    Color? iconColor,
    Color? textColor,
    Color? backgroundColor,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xxl),
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor ?? Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  if (customIcon != null) ...[
                    customIcon,
                    const SizedBox(width: 16),
                  ] else if (icon != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Icon(icon, size: 20, color: AppColors.dark),
                    ),
                    const SizedBox(width: 16),
                  ] else ...[
                    const SizedBox(width: 52), // Matches icon size + spacing
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textColor ?? AppColors.text,
                          ),
                        ),
                        if (value != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            value,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: textColor ?? AppColors.text,
                            ),
                          ),
                        ],
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) trailing,
                ],
              ),
            ),
            if (showDivider)
              const Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: AppColors.border),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Current currency symbol for custom icon
    final currentCurrency = _currencies.firstWhere((c) => c.$1 == _currency, orElse: () => _currencies.first);

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFB), // Very light background to match screenshot
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : _error != null && _user == null
                ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.muted)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Back button (Optional, floating left)
                        Align(
                          alignment: Alignment.centerLeft,
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
                        
                        // ─── Avatar Section ────────────────────
                        GestureDetector(
                          onTap: _pickImage,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 88,
                                height: 88,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: AppColors.avatarGradient,
                                ),
                                child: _getAvatarUrl().isNotEmpty
                                    ? ClipOval(
                                        child: Image.network(
                                          _getAvatarUrl(),
                                          fit: BoxFit.cover,
                                          width: 88,
                                          height: 88,
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          _user?.initials ?? '?',
                                          style: const TextStyle(
                                            fontSize: 32,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.dark,
                                          ),
                                        ),
                                      ),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppColors.accent,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(
                                    Icons.edit,
                                    size: 14,
                                    color: AppColors.dark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _user?.displayName ?? '',
                          style: const TextStyle(
                            fontSize: 22,
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
                        
                        const SizedBox(height: 24),
                        
                        // ─── Sections ────────────────────
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _buildSectionHeader('PERSONAL INFORMATION'),
                        ),
                        _buildCard(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                children: [
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
                                ],
                              ),
                            ),
                          ],
                        ),

                        Align(
                          alignment: Alignment.centerLeft,
                          child: _buildSectionHeader('PREFERENCES'),
                        ),
                        _buildCard(
                          children: [
                            _buildRow(
                              icon: Icons.payments_outlined,
                              title: 'Currency',
                              subtitle: currentCurrency.$3,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _currency,
                                    style: const TextStyle(fontSize: 14, color: AppColors.text, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chevron_right, color: AppColors.text, size: 20),
                                ],
                              ),
                              onTap: _showCurrencyPicker,
                            ),
                            _buildRow(
                              icon: Icons.notifications_none,
                              title: 'Daily Reminders',
                              subtitle: 'Alerts for tracking limits',
                              showDivider: false,
                              trailing: GestureDetector(
                                onTap: () {
                                  setState(() => _emailReminders = !_emailReminders);
                                  _save();
                                },
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: _emailReminders ? AppColors.dark : Colors.transparent,
                                    border: Border.all(
                                      color: _emailReminders ? AppColors.dark : AppColors.muted,
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: _emailReminders
                                      ? const Icon(Icons.check, size: 18, color: AppColors.accent)
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),

                        Align(
                          alignment: Alignment.centerLeft,
                          child: _buildSectionHeader('SECURITY'),
                        ),
                        _buildCard(
                          children: [
                            _buildRow(
                              icon: Icons.lock_outline,
                              title: 'Change Password',
                              trailing: const Icon(Icons.chevron_right, color: AppColors.text, size: 20),
                              onTap: _showChangePasswordDialog,
                            ),
                            _buildRow(
                              icon: Icons.logout,
                              iconColor: AppColors.error,
                              textColor: AppColors.error,
                              title: 'Log Out',
                              showDivider: false,
                              onTap: _logout,
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 40),
                        
                        // Save button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.dark,
                              foregroundColor: AppColors.accent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadius.xl),
                              ),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.accent,
                                    ),
                                  )
                                : const Text(
                                    'Save Changes',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
      ),
    );
  }
}
