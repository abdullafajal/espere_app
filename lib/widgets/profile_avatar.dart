/// The signed-in user's photo in a circle (relative paths resolved against the server
/// address), or their initials when they have not added one or it cannot be loaded.
library;

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../utils/avatar_cache.dart';

class ProfileAvatar extends StatefulWidget {
  final String name;

  /// Photo path or URL from the profile ('' = none).
  final String avatar;
  final double size;
  final Color background;
  final Color foreground;

  const ProfileAvatar({
    super.key,
    required this.name,
    required this.avatar,
    required this.size,
    required this.background,
    required this.foreground,
  });

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  static String? _base;

  @override
  void initState() {
    super.initState();
    if (_base == null) {
      AuthService.getBaseUrl().then((b) {
        _base = b;
        if (mounted) setState(() {});
      });
    }
  }

  String get _url {
    final a = widget.avatar.trim();
    if (a.isEmpty) return '';
    if (a.startsWith('http')) return a;
    final base = _base;
    if (base == null) return '';
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$b${a.startsWith('/') ? a : '/$a'}';
  }

  String get _initials {
    final parts = widget.name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        _initials,
        style: TextStyle(color: widget.foreground, fontWeight: FontWeight.w800, fontSize: widget.size * 0.36),
      ),
    );
    final url = _url;
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.background, shape: BoxShape.circle),
      child: url.isEmpty
          ? fallback
          : ClipOval(child: CachedAvatarImage(url: url, size: widget.size, fallback: fallback)),
    );
  }
}
