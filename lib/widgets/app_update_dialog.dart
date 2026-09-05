import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

class AppUpdateDialog extends StatelessWidget {
  final String versionName;
  final String releaseNotes;
  final String updateUrl;
  final bool isRequired;

  const AppUpdateDialog({
    super.key,
    required this.versionName,
    required this.releaseNotes,
    required this.updateUrl,
    required this.isRequired,
  });

  Future<void> _launchUpdateUrl() async {
    final uri = Uri.parse(updateUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    // If it's a required update, wrap with PopScope to prevent back button dismissal
    Widget dialog = Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.system_update_rounded,
              size: 48,
              color: AppColors.accent,
            ),
            const SizedBox(height: 16),
            const Text(
              'Update Available',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Version $versionName is now available. Please update your app to the latest version to enjoy new features and improvements.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.dark),
            ),
            if (releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  releaseNotes,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.text,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _launchUpdateUrl,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.dark,
                  foregroundColor: AppColors.accent,
                  shape: const StadiumBorder(),
                  elevation: 0,
                ),
                child: const Text(
                  'Update Now',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            if (!isRequired) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.dark,
                  shape: const StadiumBorder(),
                ),
                child: const Text(
                  'Later',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (isRequired) {
      return PopScope(canPop: false, child: dialog);
    }

    return dialog;
  }
}
