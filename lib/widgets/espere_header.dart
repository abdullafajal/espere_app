import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'espere_back_button.dart';

class EspereHeader extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final VoidCallback? onBack;

  const EspereHeader({
    super.key,
    this.title,
    this.trailing,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Standardized padding across the app
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          EspereBackButton(
            onPressed: onBack,
          ),
          if (title != null) ...[
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title!,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else ...[
            const Spacer(),
          ],
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
