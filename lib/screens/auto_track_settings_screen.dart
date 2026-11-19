import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auto_capture_channel.dart';
import '../services/auto_expense_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/auto_track_disclosure.dart';
import '../widgets/espere_header.dart';
import 'auto_track_review_screen.dart';

/// Profile → Auto-track payments.
class AutoTrackSettingsScreen extends StatefulWidget {
  const AutoTrackSettingsScreen({super.key});

  /// Turn-on flow: Prominent Disclosure first; the system screen opens only on "Allow".
  static Future<void> startEnableFlow(BuildContext context) async {
    final allowed = await showAutoTrackDisclosure(context);
    if (!allowed) return;
    await AutoExpenseService.acceptDisclosure();
  }

  @override
  State<AutoTrackSettingsScreen> createState() => _AutoTrackSettingsScreenState();
}

class _AutoTrackSettingsScreenState extends State<AutoTrackSettingsScreen>
    with WidgetsBindingObserver {
  AutoTrackSettings? _s;
  List<AutoCaptureSource> _sources = const [];
  int _reviewCount = 0;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = AutoExpenseService.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the Notification-access screen.
    if (state == AppLifecycleState.resumed) {
      AutoExpenseService.refreshPermissionState().then((_) => _load());
    }
  }

  Future<void> _load() async {
    final s = await AutoExpenseService.settings();
    final sources = _sources.isEmpty ? await AutoCaptureChannel.getSources() : _sources;
    final count = await AutoExpenseService.reviewCount();
    if (!mounted) return;
    setState(() {
      _s = s;
      _sources = sources;
      _reviewCount = count;
    });
  }

  Future<void> _turnOn() async {
    await AutoTrackSettingsScreen.startEnableFlow(context);
    await _load();
  }

  Future<void> _turnOff() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xxl)),
        title: const Text('Turn off & delete local data?'),
        content: const Text(
          'Auto-tracking stops and everything it keeps on this phone is deleted: pending '
          'notifications, duplicate-check fingerprints, the Review list and remembered '
          'categories. Transactions already added stay in your account.\n\n'
          'To fully revoke access, also switch off Notification access for Espere in '
          'Android settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Turn off', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AutoExpenseService.turnOffAndDeleteLocalData();
    if (mounted) AppToast.success(context, 'Auto-tracking turned off. Local data deleted.');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            EspereHeader(title: 'Auto-track payments', onBack: () => Navigator.pop(context)),
            Expanded(
              child: s == null
                  ? const Center(child: CircularProgressIndicator(color: AppColors.dark))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                      children: [
                        _statusCard(s),
                        if (s.enabled) ...[
                          _header('WHAT TO TRACK'),
                          _card([_typeChoice(s)]),
                          _header('APPS'),
                          _card([
                            for (var i = 0; i < _sources.length; i++)
                              _switchRow(
                                title: _sources[i].label,
                                value: !s.disabledSources.contains(_sources[i].id),
                                onChanged: (v) async {
                                  await AutoExpenseService.setSourceEnabled(_sources[i].id, v);
                                  await _load();
                                },
                                divider: i < _sources.length - 1,
                              ),
                          ]),
                          _header('REVIEW'),
                          _card([
                            _navRow(
                              icon: Icons.fact_check_outlined,
                              title: 'Review list',
                              subtitle: _reviewCount == 0
                                  ? 'Nothing to review'
                                  : '$_reviewCount payment${_reviewCount == 1 ? '' : 's'} need a quick check',
                              badge: _reviewCount,
                              onTap: () async {
                                await Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => const AutoTrackReviewScreen()));
                                await _load();
                              },
                            ),
                            _switchRow(
                              title: 'Notify me when a payment is added',
                              value: s.notifyOnAdd,
                              onChanged: (v) async {
                                await AutoExpenseService.setNotifyOnAdd(v);
                                await _load();
                              },
                              divider: false,
                            ),
                          ]),
                        ],
                        _header('PRIVACY'),
                        _card([
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Notification content is processed only on this phone and is never '
                              'uploaded. Only the amount, payee, category, date and payment method of '
                              'detected payments are saved to your account.',
                              style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.muted.withValues(alpha: 0.9)),
                            ),
                          ),
                          _navRow(
                            icon: Icons.settings_outlined,
                            title: 'Notification access',
                            subtitle: s.permissionGranted ? 'Allowed' : 'Not allowed',
                            onTap: () async {
                              await AutoCaptureChannel.openPermissionSettings();
                            },
                          ),
                          if (s.enabled || s.consent)
                            _navRow(
                              icon: Icons.delete_outline,
                              title: 'Turn off & delete local data',
                              onTap: _turnOff,
                              divider: false,
                            ),
                        ]),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(AutoTrackSettings s) {
    final String title;
    final String body;
    Widget? action;
    if (s.enabled && s.permissionGranted) {
      title = 'On';
      body = 'Payments from your UPI and bank apps are added automatically. '
          'Uncertain ones wait in the Review list.';
    } else if (s.consent && !s.permissionGranted) {
      title = 'Notification access needed';
      body = 'Allow Notification access for Espere so it can see payment notifications.';
      action = _button('Open settings', AutoCaptureChannel.openPermissionSettings);
    } else {
      title = 'Off';
      body = 'Add expenses automatically from UPI and bank payment notifications. '
          'Everything is processed on your phone.';
      action = _button('Turn on', _turnOn);
    }
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: const Icon(Icons.bolt, size: 20, color: AppColors.dark),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
              ),
              if (s.enabled)
                Switch(
                  value: true,
                  activeThumbColor: AppColors.accent,
                  activeTrackColor: AppColors.dark,
                  onChanged: (_) => _turnOff(),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(body, style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.muted)),
          if (action != null) ...[const SizedBox(height: 14), action],
        ],
      ),
    );
  }

  Widget _typeChoice(AutoTrackSettings s) => Padding(
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: AppColors.dark,
            selectedForegroundColor: AppColors.accent,
            foregroundColor: AppColors.text,
          ),
          segments: const [
            ButtonSegment(value: false, label: Text('Expenses only')),
            ButtonSegment(value: true, label: Text('Expenses + Income')),
          ],
          selected: {s.includeIncome},
          onSelectionChanged: (v) async {
            await AutoExpenseService.setIncludeIncome(v.first);
            await _load();
          },
        ),
      );

  Widget _button(String label, Future<void> Function() onTap) => SizedBox(
        width: double.infinity,
        height: 46,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.dark,
            foregroundColor: AppColors.accent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
          ),
          onPressed: () => onTap(),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 24),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2, color: AppColors.muted)),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          boxShadow: AppShadows.card,
        ),
        child: Column(children: children),
      );

  Widget _switchRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool divider = true,
  }) =>
      Column(
        children: [
          SwitchListTile(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.accent,
            activeTrackColor: AppColors.dark,
            title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
          ),
          if (divider) const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.border),
        ],
      );

  Widget _navRow({
    required IconData icon,
    required String title,
    String? subtitle,
    int badge = 0,
    required VoidCallback onTap,
    bool divider = true,
  }) =>
      Column(
        children: [
          ListTile(
            onTap: onTap,
            leading: Icon(icon, color: AppColors.text),
            title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
            subtitle: subtitle == null
                ? null
                : Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Text('$badge',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dark)),
                  ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.text, size: 20),
              ],
            ),
          ),
          if (divider) const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.border),
        ],
      );
}
