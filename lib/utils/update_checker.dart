import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../widgets/app_update_dialog.dart';

class UpdateChecker {
  static const String _skippedVersionKey = 'skipped_update_version_code';

  static Future<void> check(BuildContext context) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      final result = await ApiService.checkAppVersion();
      if (result.isSuccess && result.data != null) {
        final data = result.data!;
        final serverVersionCode = data['version_code'] as int? ?? 0;

        if (serverVersionCode > currentBuildNumber) {
          final isRequired = data['is_required'] as bool? ?? false;
          
          if (!isRequired) {
            final prefs = await SharedPreferences.getInstance();
            final skippedVersion = prefs.getInt(_skippedVersionKey) ?? 0;
            if (skippedVersion >= serverVersionCode) {
              return; // User skipped this or a newer optional version
            }
          }

          if (!context.mounted) return;
          
          showDialog(
            context: context,
            barrierDismissible: !isRequired,
            builder: (context) => AppUpdateDialog(
              versionName: data['version_name'] as String? ?? 'Unknown',
              releaseNotes: data['release_notes'] as String? ?? '',
              updateUrl: data['update_url'] as String? ?? '',
              isRequired: isRequired,
              onSkip: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setInt(_skippedVersionKey, serverVersionCode);
              },
            ),
          );
        }
      }
    } catch (e) {
      // Silently ignore update check errors so we don't bother the user
    }
  }
}
