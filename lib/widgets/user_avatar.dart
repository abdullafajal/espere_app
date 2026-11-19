import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/avatar_cache.dart';

class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initial;
  final double size;
  final double borderRadius;

  const UserAvatar({
    super.key,
    this.avatarUrl,
    required this.initial,
    this.size = 40,
    this.borderRadius = 999, // round
  });

  @override
  Widget build(BuildContext context) {
    final fallback = _initialBox();

    // If we have an avatar URL, show the cached image
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CachedAvatarImage(
          url: avatarUrl!,
          size: size,
          fallback: fallback,
        ),
      );
    }

    return fallback;
  }

  // Fallback: first letter in lime on an ink circle
  Widget _initialBox() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: Text(
          initial.isEmpty ? '?' : initial[0].toUpperCase(),
          style: TextStyle(
            color: AppColors.accent,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.4,
          ),
        ),
      ),
    );
  }
}
