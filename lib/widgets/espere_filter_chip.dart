import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Dropdown-style filter chip used on list screens (same height, shape and active state
/// everywhere). Active = ink with white text.
class EspereFilterChip extends StatelessWidget {
  static const double height = 40;

  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// True when a non-default filter is applied.
  final bool active;

  /// Fill the available width (label on the left, arrow on the right).
  final bool expand;

  /// Show the dropdown arrow (false for plain toggle chips).
  final bool dropdown;

  const EspereFilterChip({
    super.key,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.active = false,
    this.expand = false,
    this.dropdown = true,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active ? AppColors.dark : AppColors.card;
    final fg = active ? Colors.white : AppColors.text;
    return Semantics(
      button: true,
      selected: active,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        onLongPress: onLongPress,
        child: Container(
          height: height,
          width: expand ? double.infinity : null,
          padding: EdgeInsets.only(left: 16, right: dropdown ? 8 : 16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(height / 2),
            boxShadow: active ? null : AppShadows.soft,
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Flexible(
                fit: expand ? FlexFit.tight : FlexFit.loose,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w600, color: fg),
                ),
              ),
              if (dropdown) ...[
                const SizedBox(width: 2),
                Icon(Icons.expand_more_rounded, size: 20, color: active ? AppColors.accent : AppColors.muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
