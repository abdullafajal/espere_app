/// Settings: profile card (Edit opens name and photo), then MONEY, REMINDERS and
/// SECURITY rows, and Log out.
library;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/motion.dart';
import '../widgets/espere_header.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';
import '../utils/pickers.dart';
import '../utils/avatar_cache.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';
import '../services/widget_service.dart';
import '../services/auto_expense_service.dart';
import 'auto_track_settings_screen.dart';
import 'reports_screen.dart';
import '../services/daily_reminders.dart';
import '../widgets/espere_input.dart';
import '../utils/app_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  String _currency = 'INR';
  String _theme = 'light';
  bool _emailReminders = true;
  bool _shredderAnimation = true;
  bool _autoTrackOn = false;
  bool _autoTrackAvailable = false;

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
    _loadCounts();
    _loadReminders();
    _loadAutoTrack();
  }

  Future<void> _loadAutoTrack() async {
    if (!await AutoExpenseService.isAvailable()) return;
    final s = await AutoExpenseService.settings();
    if (mounted) {
      setState(() {
        _autoTrackAvailable = true;
        _autoTrackOn = s.enabled;
      });
    }
  }

  Future<void> _openAutoTrack() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AutoTrackSettingsScreen()),
    );
    await _loadAutoTrack();
  }

  Future<void> _toggleAutoTrack() async {
    if (_autoTrackOn) {
      // Turning off deletes local data: confirm on the settings screen.
      await _openAutoTrack();
      return;
    }
    await AutoTrackSettingsScreen.startEnableFlow(context);
    await _loadAutoTrack();
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
    
    // Load local settings
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _shredderAnimation = prefs.getBool('enable_shredder_anim') ?? true;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
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
    var savedLocally = false;
    ApiProbe? probe;
    result = ApiResult(error: 'offline');

    if (ConnectivityService.isOnline) {
      final probed = await ApiService.probed(() => ApiService.updateProfile(data));
      result = probed.result;
      probe = probed.probe;
    }

    // No usable connection (offline, slow or server hiccup): save locally and
    // sync in the background - the user should not notice any difference.
    final unreachable = !ConnectivityService.isOnline ||
        (!result.isSuccess && probe != null && !probe.permanent);
    if (unreachable) {
      await SyncService.queueOperation(
        action: 'update',
        entity: 'profile',
        data: data,
        entityId: _user?.id ?? 0,
      );

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
        savedLocally = true;
      }
    } else if (result.isSuccess && result.data != null) {
      await CacheService.cacheUser((result.data as UserModel).toJson());
    }

    // New currency symbol everywhere (app screens, home widget, quick-add popup).
    if (result.isSuccess || savedLocally) {
      final symbol = _currencies
          .firstWhere((c) => c.$1 == _currency, orElse: () => _currencies.first)
          .$2;
      await CacheService.setCurrencySymbol(symbol);
      await WidgetService.setCurrencySymbol(symbol);
      SyncService.syncAll(); // pulls fresh numbers formatted by the server (when online)
    }

    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (result.isSuccess && result.data != null) {
        _user = result.data;
        AppToast.success(context, 'Profile updated successfully.');
      } else if (savedLocally) {
        AppToast.success(context, 'Profile updated successfully.');
      } else {
        AppToast.error(context, result.error ?? 'Error updating profile');
      }
    });
  }

  Future<void> _logout() async {
    // Auto-track data belongs to this account and this device only.
    await AutoExpenseService.turnOffAndDeleteLocalData();
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
          
          final oldAvatarUrl = _getAvatarUrl();
          final result = await ApiService.uploadAvatar(croppedFile.path);
          if (result.isSuccess) {
            // Same URL may now point to a new image: drop the stale cached copy.
            await AvatarCache.evict(oldAvatarUrl);
          }
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
                                ? AppColors.accentSoft
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
                                  color: AppColors.surface,
                                  shape: BoxShape.circle,
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
                                const Icon(Icons.check_rounded, color: AppColors.dark, size: 20),
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
                      ? const CircularProgressIndicator(color: AppColors.dark)
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

  final Map<ReminderSlot, ReminderSetting> _reminders = {
    for (final s in ReminderSlot.values) s: ReminderSetting(true, DailyReminders.defaults[s]!),
  };

  Future<void> _loadReminders() async {
    for (final s in ReminderSlot.values) {
      final v = await DailyReminders.get(s);
      if (mounted) setState(() => _reminders[s] = v);
    }
  }

  Future<void> _setReminder(ReminderSlot slot, ReminderSetting v) async {
    AppHaptics.tap();
    setState(() => _reminders[slot] = v);
    await DailyReminders.set(slot, v);
    if (!mounted) return;
    final name = slot == ReminderSlot.morning ? 'Morning' : 'Night';
    AppToast.success(context, v.on ? '$name reminder at ${DailyReminders.label(v.minutes)}' : '$name reminder off');
  }

  Future<void> _pickReminderTime(ReminderSlot slot) async {
    final cur = _reminders[slot]!;
    final t = await showTimePicker(
      builder: pickerBuilder,
      context: context,
      initialTime: TimeOfDay(hour: cur.minutes ~/ 60, minute: cur.minutes % 60),
      helpText: slot == ReminderSlot.morning ? 'Morning reminder' : 'Night reminder',
    );
    if (t == null || !mounted) return;
    await _setReminder(slot, ReminderSetting(true, t.hour * 60 + t.minute));
  }

  int _categoryCount = 0;
  int _pending = 0;

  Future<void> _loadCounts() async {
    final cats = await CacheService.getCachedCategories();
    final pending = await SyncService.pendingCount();
    if (!mounted) return;
    setState(() {
      _categoryCount = ((cats?['categories'] as List?) ?? const []).length;
      _pending = pending;
    });
  }

  /// "MONEY" etc. above a white group card.
  Widget _group(String title, List<Widget> rows) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) children.add(const Divider(height: 1, thickness: 1, color: Color(0xFFF0F1EC)));
      children.add(rows[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            child: Text(title, style: AppText.label.copyWith(letterSpacing: 0.6)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppShadows.soft,
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  /// One settings row: grey rounded icon, label + hint, then a value and chevron or a
  /// switch.
  Widget _row({
    required IconData icon,
    required String label,
    String? hint,
    String? value,
    bool? on,
    VoidCallback? onToggle,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: on == null,
      toggled: on,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, size: 21, color: AppColors.dark),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppText.rowTitle),
                      if (hint != null) ...[
                        const SizedBox(height: 1),
                        Text(hint, style: AppText.rowSub),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (on != null) ...[
                  if (value != null) ...[
                    Text(value,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: on ? AppColors.text : AppColors.mutedLight,
                        )),
                    const SizedBox(width: 10),
                  ],
                  GestureDetector(onTap: onToggle ?? onTap, child: _switch(on)),
                ] else ...[
                  if (value != null)
                    Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.muted)),
                  const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.muted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(double size) {
    final initials = _user?.initials ?? '?';
    final fallback = Center(
      child: Text(initials,
          style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w800, color: AppColors.dark)),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
      child: _getAvatarUrl().isNotEmpty
          ? ClipOval(child: CachedAvatarImage(url: _getAvatarUrl(), size: size, fallback: fallback))
          : fallback,
    );
  }

  Widget _profileCard() {
    final synced = _pending == 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(24)),
      child: Row(
        children: [
          _avatar(56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _user?.displayName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(synced ? Icons.cloud_done_rounded : Icons.cloud_upload_rounded,
                        size: 15, color: AppColors.accent),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        synced ? 'Synced' : '$_pending change${_pending == 1 ? '' : 's'} waiting to sync',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.darkMuted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SpringPress(
            onTap: _editProfile,
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFF262924), borderRadius: BorderRadius.circular(19)),
              child: const Text('Edit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  /// Accent colour picker: a few light colours that keep ink text readable.
  Future<void> _pickAccent() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('App colour', style: AppText.section),
                const SizedBox(height: 4),
                const Text('Used for buttons, the selected tab and highlights.', style: AppText.rowSub),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 14,
                  runSpacing: 16,
                  children: [
                    for (var i = 0; i < AppAccent.options.length; i++)
                      Semantics(
                        button: true,
                        selected: i == AppAccent.index,
                        label: AppAccent.options[i].name,
                        excludeSemantics: true,
                        child: GestureDetector(
                          onTap: () async {
                            AppHaptics.tap();
                            await AppAccent.set(i);
                            ss(() {});
                            if (mounted) setState(() {});
                          },
                          child: SizedBox(
                            width: 64,
                            child: Column(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  width: 52,
                                  height: 52,
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: i == AppAccent.index ? AppColors.dark : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(color: AppAccent.options[i].color, shape: BoxShape.circle),
                                    child: i == AppAccent.index
                                        ? const Icon(Icons.check_rounded, size: 22, color: AppColors.dark)
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  AppAccent.options[i].name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: i == AppAccent.index ? FontWeight.w700 : FontWeight.w500,
                                    color: AppColors.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Shares the app's download page, with the user's username as the referrer.
  Future<void> _shareApp() async {
    final ref = (_user?.username ?? '').trim();
    final link = ref.isEmpty ? 'https://espere.in' : 'https://espere.in/?ref=$ref';
    await Share.share(
      'I track my spending and split bills with friends on Espere. It works offline and '
      'adds expenses in a tap. Get it here: $link',
      subject: 'Try Espere',
    );
  }

  /// Name and photo.
  Future<void> _editProfile() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Edit profile', style: AppText.section),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickImage();
                  },
                  child: Stack(
                    children: [
                      _avatar(80),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.dark,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(Icons.photo_camera_rounded, size: 14, color: AppColors.accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Center(child: Text('Tap to change photo', style: AppText.rowSub)),
              const SizedBox(height: 16),
              EspereInput(label: 'First name', hint: 'First name', controller: _firstNameController),
              const SizedBox(height: 12),
              EspereInput(label: 'Last name', hint: 'Last name', controller: _lastNameController),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true) {
      await _save();
    } else if (_user != null) {
      _firstNameController.text = _user!.firstName;
      _lastNameController.text = _user!.lastName;
    }
  }

  /// On/off switch drawn like the app's switches (ink track, lime knob).
  Widget _switch(bool on) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 46,
        height: 28,
        padding: const EdgeInsets.all(3),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: on ? AppColors.dark : const Color(0xFFDADDD5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: on ? AppColors.accent : Colors.white, shape: BoxShape.circle),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final currentCurrency = _currencies.firstWhere((c) => c.$1 == _currency, orElse: () => _currencies.first);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.dark))
            : Column(
                children: [
                  EspereHeader(title: 'Settings', onBack: () => Navigator.pop(context)),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                      children: [
                        _profileCard(),
                        _group('MONEY', [
                          _row(
                            icon: Icons.currency_rupee_rounded,
                            label: 'Currency',
                            hint: currentCurrency.$3,
                            value: _currency,
                            onTap: _showCurrencyPicker,
                          ),
                          _row(
                            icon: Icons.category_rounded,
                            label: 'Categories',
                            hint: 'Names and icons',
                            value: _categoryCount > 0 ? '$_categoryCount' : null,
                            onTap: () async {
                              await Navigator.pushNamed(context, '/categories');
                              _loadCounts();
                            },
                          ),
                          _row(
                            icon: Icons.pie_chart_rounded,
                            label: 'Reports',
                            hint: 'Where your money goes',
                            onTap: () => Navigator.push(
                                context, MaterialPageRoute(builder: (_) => const ReportsScreen())),
                          ),
                          if (_autoTrackAvailable)
                            _row(
                              icon: Icons.bolt_rounded,
                              label: 'Auto-track payments',
                              hint: 'From UPI & bank notifications',
                              on: _autoTrackOn,
                              onTap: _toggleAutoTrack,
                            ),
                        ]),
                        _group('LOOK', [
                          _row(
                            icon: Icons.palette_rounded,
                            label: 'App colour',
                            hint: 'Buttons and highlights',
                            value: AppAccent.current.name,
                            onTap: _pickAccent,
                          ),
                          _row(
                            icon: Icons.auto_awesome_rounded,
                            label: 'Delete animation',
                            hint: 'Entries fade away when deleted',
                            on: _shredderAnimation,
                            onTap: () async {
                              setState(() => _shredderAnimation = !_shredderAnimation);
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setBool('enable_shredder_anim', _shredderAnimation);
                            },
                          ),
                        ]),
                        _group('REMINDERS', [
                          for (final slot in ReminderSlot.values)
                            _row(
                              icon: slot == ReminderSlot.morning ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                              label: slot == ReminderSlot.morning ? 'Morning reminder' : 'Night reminder',
                              hint: _reminders[slot]!.on
                                  ? 'At ${DailyReminders.label(_reminders[slot]!.minutes)} · tap to change'
                                  : 'Off',
                              on: _reminders[slot]!.on,
                              onTap: () => _pickReminderTime(slot),
                              onToggle: () => _setReminder(
                                slot,
                                ReminderSetting(!_reminders[slot]!.on, _reminders[slot]!.minutes),
                              ),
                            ),
                        ]),
                        _group('SPREAD THE WORD', [
                          _row(
                            icon: Icons.share_rounded,
                            label: 'Share Espere',
                            hint: 'Invite friends to track and split together',
                            onTap: _shareApp,
                          ),
                        ]),
                        _group('SECURITY', [
                          _row(
                            icon: Icons.lock_rounded,
                            label: 'Change password',
                            hint: _user?.email,
                            onTap: _showChangePasswordDialog,
                          ),
                        ]),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 48,
                          child: TextButton.icon(
                            onPressed: _isSaving ? null : _logout,
                            icon: const Icon(Icons.logout_rounded, size: 20),
                            label: const Text('Log out', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            style: TextButton.styleFrom(foregroundColor: AppColors.dark),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
