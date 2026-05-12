/// Home Shell — wraps the main screens with the floating bottom nav bar.
///
/// Manages tab switching between Dashboard, Transactions, Budgets,
/// Savings, and Split Groups tabs.
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav_bar.dart';
import 'dashboard_screen.dart';
import 'transaction_list_screen.dart';
import 'budgets_screen.dart';
import 'savings_screen.dart';
import 'split_groups_screen.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _isBottomNavVisible = true;
  double _lastScrollOffset = 0;

  final _dashboardKey = GlobalKey<DashboardScreenState>();
  final _transactionListKey = GlobalKey<TransactionListScreenState>();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _registerDeviceToken();
    _screens = [
      DashboardScreen(
        key: _dashboardKey,
        onTabChange: (index) {
          setState(() {
            _currentIndex = index;
            _isBottomNavVisible = true;
          });
        },
      ),
      TransactionListScreen(
        key: _transactionListKey,
        onBack: () => setState(() => _currentIndex = 0),
      ),
      BudgetsScreen(onBack: () => setState(() => _currentIndex = 0)),
      SavingsScreen(onBack: () => setState(() => _currentIndex = 0)),
      SplitGroupsScreen(onBack: () => setState(() => _currentIndex = 0)),
    ];
  }

  Future<void> _registerDeviceToken() async {
    final token = await NotificationService.getToken();
    if (token != null) {
      await ApiService.registerDeviceToken(token);
    }
  }

  /// Trigger a data refresh on the given tab index.
  void _refreshTab(int index) {
    if (index == 0) {
      _dashboardKey.currentState?.reload();
    } else if (index == 1) {
      _transactionListKey.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification) {
                final currentOffset = notification.metrics.pixels;
                final velocity = notification.scrollDelta ?? 0;

                if (currentOffset <= 0) {
                  if (!_isBottomNavVisible)
                    setState(() => _isBottomNavVisible = true);
                } else if (velocity > 10 &&
                    _isBottomNavVisible &&
                    currentOffset > 80) {
                  // Scrolling down
                  setState(() => _isBottomNavVisible = false);
                } else if (velocity < -10 && !_isBottomNavVisible) {
                  // Scrolling up
                  setState(() => _isBottomNavVisible = true);
                }
                _lastScrollOffset = currentOffset;
              }
              return false;
            },
            child: SafeArea(
              bottom: false, // Let content flow under floating nav
              child: IndexedStack(index: _currentIndex, children: _screens),
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
                  _isBottomNavVisible = true;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder screen for Budgets/Savings/Split tabs
class _PlaceholderScreen extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PlaceholderScreen({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.xxl),
            ),
            child: Icon(icon, size: 40, color: AppColors.accent),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Coming soon',
            style: TextStyle(fontSize: 14, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
