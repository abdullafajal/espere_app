import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'espere_back_button.dart';

/// Screen header: round back button, bold title, optional trailing actions.
class EspereHeader extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final VoidCallback? onBack;

  /// Hide the back button (top-level tabs).
  final bool showBack;

  const EspereHeader({
    super.key,
    this.title,
    this.trailing,
    this.onBack,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            if (showBack) ...[
              EspereBackButton(onPressed: onBack),
              const SizedBox(width: 12),
            ],
            if (title != null)
              Expanded(
                child: Text(
                  title!,
                  style: showBack
                      ? const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text)
                      : AppText.screenTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              const Spacer(),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
