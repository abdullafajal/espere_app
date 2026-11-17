import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Prominent Disclosure shown BEFORE the system Notification-access screen.
/// Returns true only when the user taps "Allow".
Future<bool> showAutoTrackDisclosure(BuildContext context) async {
  final allowed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xxl)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: const Icon(Icons.notifications_active_outlined, size: 22, color: AppColors.dark),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Auto-track payments',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text),
            ),
          ),
        ],
      ),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Espere reads payment notifications from UPI and bank apps on your device to add '
              'your expenses automatically. Notification content is processed only on your '
              'phone and is never uploaded. Only the amount, payee and category of detected '
              'transactions are saved to your account. You can turn this off anytime.',
              style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.text),
            ),
            SizedBox(height: 14),
            _Point(Icons.apps_outlined,
                'Only Google Pay, PhonePe, Paytm, BHIM, Amazon Pay, CRED, WhatsApp Pay, major '
                'bank apps and bank SMS. Other notifications are ignored.'),
            _Point(Icons.sms_outlined, 'Personal SMS and chats are never read.'),
            _Point(Icons.touch_app_outlined,
                'Next, Android will ask you to allow Notification access for Espere.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now', style: TextStyle(color: AppColors.muted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.dark,
            foregroundColor: AppColors.accent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Allow', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return allowed ?? false;
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Point(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted)),
            ),
          ],
        ),
      );
}
