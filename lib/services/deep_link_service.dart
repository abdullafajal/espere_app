import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

class DeepLinkService {
  static final _appLinks = AppLinks();
  static StreamSubscription? _linkSubscription;

  static void init(GlobalKey<NavigatorState> navigatorKey) {
    // 1. Handle links when app is in background/foreground
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri, navigatorKey);
    });

    // 2. Handle link when app is closed (initial link)
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleUri(uri, navigatorKey);
      }
    });
  }

  static void dispose() {
    _linkSubscription?.cancel();
  }

  static void _handleUri(Uri uri, GlobalKey<NavigatorState> navigatorKey) {
    debugPrint('[DeepLink] Handling URI: $uri');
    
    final path = uri.path;
    
    if (path.startsWith('/accounts/verify/')) {
      // Email verification link
      // We can redirect to a screen or just show a message
      // Usually these links are processed by the browser/web first
      // But if the app opens, we might want to tell the user something.
    } else if (path.startsWith('/split/invite/')) {
      // Group invitation link
      // Pattern: /split/invite/<uuid>/
      final segments = uri.pathSegments;
      if (segments.length >= 3) {
        final token = segments[2];
        // Handle special invitation link logic if needed
        // For now, let's just go to invitations list or a special view
        navigatorKey.currentState?.pushNamed('/split/invitations');
      }
    } else if (path.startsWith('/transaction/add')) {
      final type = uri.queryParameters['type'];
      navigatorKey.currentState?.pushNamed('/transaction/add', arguments: type);
    } else if (path.startsWith('/split/invitations')) {
      navigatorKey.currentState?.pushNamed('/split/invitations');
    }
  }
}
