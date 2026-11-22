/// Home Shell — wraps the main screens with the floating bottom nav bar.
///
/// Manages tab switching between Dashboard, Transactions, Budgets,
/// Savings, and Split Groups tabs.
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/nav_space.dart';
import '../widgets/split_switcher.dart';
import '../widgets/bottom_nav_bar.dart';
import 'dashboard_screen.dart';
import 'transaction_list_screen.dart';
import 'budgets_screen.dart';
import 'friends_screen.dart';
import 'split_groups_screen.dart';
import 'quick_add_screen.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/cache_service.dart';
import '../services/sync_service.dart';
import '../services/auto_expense_service.dart';
import '../services/receipt_service.dart';
import '../services/app_navigation.dart';
import '../utils/update_checker.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _isBottomNavVisible = true;

  /// Call inside setState: updates the bar and tells the lists (NavBottomSpace).
  void _setNav(bool visible) {
    _isBottomNavVisible = visible;
    AppNavigation.navVisible.value = visible;
  }

  final _dashboardKey = GlobalKey<DashboardScreenState>();
  final _transactionListKey = GlobalKey<TransactionListScreenState>();
  final _budgetsKey = GlobalKey<BudgetsScreenState>();
  final _friendsKey = GlobalKey<FriendsScreenState>();
  final _splitGroupsKey = GlobalKey<SplitGroupsScreenState>();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _registerDeviceToken();
    AppNavigation.requestedTab.addListener(_onTabRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateChecker.check(context);
      _processPendingInvites();
      _onTabRequested(); // a tab may have been requested before this screen existed (cold start)
      ReceiptService.attachHome(context); // opens a receipt shared to Espere, if any
    });
    _screens = [
      DashboardScreen(
        key: _dashboardKey,
        onTabChange: (index) {
          setState(() {
            _currentIndex = index;
            _setNav(true);
          });
          _refreshTab(index);
        },
      ),
      TransactionListScreen(
        key: _transactionListKey,
        onBack: () => setState(() => _currentIndex = 0),
      ),
      BudgetsScreen(
        key: _budgetsKey,
        onBack: () => setState(() => _currentIndex = 0)
      ),
      FriendsScreen(
        key: _friendsKey,
        onBack: () => setState(() => _currentIndex = 0),
      ),
      SplitGroupsScreen(
        key: _splitGroupsKey,
        onBack: () => setState(() => _currentIndex = 0),
      ),
    ];
  }

  /// Switch tab when something outside asks for it (e.g. the widget's list button).
  void _onTabRequested() {
    final index = AppNavigation.requestedTab.value;
    if (index == null || !mounted) return;
    AppNavigation.requestedTab.value = null;
    setState(() {
      _currentIndex = index;
      _setNav(true);
    });
    _refreshTab(index);
  }

  Future<void> _registerDeviceToken() async {
    final token = await NotificationService.getToken();
    if (token != null) {
      await ApiService.registerDeviceToken(token);
    }
  }

  Future<void> _processPendingInvites() async {
    // Process Friend Invite
    final pendingFriend = await CacheService.getPendingFriendInvite();
    if (pendingFriend != null && pendingFriend.isNotEmpty) {
      await ApiService.inviteFriend(pendingFriend);
      await CacheService.clearPendingFriendInvite();
    }

    // Process Group Invite
    final pendingGroup = await CacheService.getPendingGroupInvite();
    if (pendingGroup != null) {
      final token = pendingGroup['token'];
      final ref = pendingGroup['ref'];
      if (token != null && token.isNotEmpty) {
        if (mounted) {
          Navigator.of(context).pushNamed('/invite', arguments: {'token': token, 'ref': ref});
        }
        await CacheService.clearPendingGroupInvite();
      }
    }
  }

  Future<void> _openQuickAdd() async {
    final added = await QuickAddScreen.open(context);
    if (!mounted || !added) return;
    _dashboardKey.currentState?.reload();
    if (_currentIndex != 0) _refreshTab(_currentIndex);
  }

  /// Trigger a data refresh on the given tab index.
  void _refreshTab(int index) {
    switch (index) {
      case 0:
        _dashboardKey.currentState?.reload();
        break;
      case 1:
        _transactionListKey.currentState?.reload();
        break;
      case 2:
        _budgetsKey.currentState?.reload();
        break;
      case 3:
        _friendsKey.currentState?.reload();
        break;
      case 4:
        _splitGroupsKey.currentState?.reload();
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      CacheService.reload().then((_) {
        if (mounted) {
          _refreshTab(_currentIndex);
          SyncService.syncAll();
        }
      });
      // Pick up payments captured while the app was in the background
      // (and finish enabling auto-track after the Notification-access screen).
      AutoExpenseService.onResume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppNavigation.requestedTab.removeListener(_onTabRequested);
    ReceiptService.detachHome(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Drives the Groups | Friends pill's spring while those screens swap.
          const SplitPillDriver(),
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification && notification.metrics.axis == Axis.vertical) {
                final m = notification.metrics;
                final delta = notification.scrollDelta ?? 0;
                // At the top or the end of a list the bar always shows (the list keeps
                // room for it there); it hides only while scrolling down in between.
                final atEdge = m.pixels <= 0 || m.extentAfter < 24;
                if (atEdge || delta < -10) {
                  if (!_isBottomNavVisible) setState(() => _setNav(true));
                } else if (delta > 10 && _isBottomNavVisible && m.pixels > 80) {
                  setState(() => _setNav(false));
                }
              }
              return false;
            },
            child: SafeArea(
              bottom: false, // Let content flow under floating nav
              // Hidden tabs stay alive but do not animate (or vibrate): only the tab on screen
              // ticks. Without this, a hidden tab refreshing after a sync played the edit
              // animation's vibration where nobody could see it.
              child: NavScope(
                child: IndexedStack(
                  index: _currentIndex,
                  children: [
                    for (var i = 0; i < _screens.length; i++)
                      TickerMode(enabled: i == _currentIndex, child: _screens[i]),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: EspereBottomNav(
              currentIndex: _currentIndex,
              isVisible: _isBottomNavVisible,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                  _setNav(true);
                });
                _refreshTab(index);
              },
              onAdd: _openQuickAdd,
            ),
          ),
        ],
      ),
    );
  }
}
