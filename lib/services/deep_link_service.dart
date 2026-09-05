import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../utils/app_toast.dart';

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

  static Future<void> _handleUri(Uri uri, GlobalKey<NavigatorState> navigatorKey) async {
    debugPrint('[DeepLink] Handling URI: $uri');
    
    final path = uri.path;
    
    if (path.startsWith('/accounts/verify/')) {
      // Email verification link
    } else if (path.startsWith('/accounts/register/')) {
      navigatorKey.currentState?.pushNamed('/register');
    } else if (path.startsWith('/invite/')) {
      // Group invitation link
      final segments = uri.pathSegments;
      if (segments.length >= 2) {
        final token = segments[1];
        final ref = uri.queryParameters['ref'];
        
        final isAuthenticated = await AuthService.isAuthenticated();
        if (!isAuthenticated) {
          await CacheService.savePendingGroupInvite(token, ref: ref);
          navigatorKey.currentState?.pushNamed('/register');
          return;
        }
        
        navigatorKey.currentState?.pushNamed('/invite', arguments: {'token': token, 'ref': ref});
      }
        } else if (path.startsWith('/add_friend/')) {
      final segments = uri.pathSegments;
      if (segments.length >= 2) {
        final username = segments[1];
        final isAuthenticated = await AuthService.isAuthenticated();
        if (isAuthenticated) {
          final res = await ApiService.inviteFriend(username);
          if (navigatorKey.currentContext != null) {
            if (res.isSuccess) {
              AppToast.success(navigatorKey.currentContext!, 'Friend request sent to $username!');
            } else {
              AppToast.error(navigatorKey.currentContext!, res.error ?? 'Error');
            }
          }
        } else {
          await CacheService.savePendingFriendInvite(username);
          navigatorKey.currentState?.pushNamed('/register');
        }
      }
    } else if (path.startsWith('/transaction/add')) {
      final type = uri.queryParameters['type'];
      navigatorKey.currentState?.pushNamed('/transaction/add', arguments: type);
    } else if (path.startsWith('/split/invitations')) {
      navigatorKey.currentState?.pushNamed('/split/invitations');
    }
  }
}
