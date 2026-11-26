/// Home: greeting + notifications bell → spend hero card (pick a month; last 7 days for
/// this month, weeks for an earlier one; average per day) → Add expense / Scan →
/// one-tap repeats → payments to review + recent.
import '../widgets/morph_text.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../theme/app_theme.dart';
import '../widgets/nav_space.dart';
import '../theme/motion.dart';
import '../models/dashboard.dart';
import '../services/cache_service.dart';
import '../widgets/transaction_tile.dart';
import '../widgets/thanos_snap_widget.dart';
import '../utils/icon_mapper.dart';
import '../utils/app_toast.dart';
import '../services/sync_service.dart';
import '../services/widget_service.dart';
import 'transaction_form_screen.dart';
import 'quick_add_screen.dart';
import 'auto_track_review_screen.dart';
import 'notifications_screen.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/home_insights.dart';
import '../services/notification_inbox.dart';
import '../services/api_service.dart';
import '../models/transaction.dart';
import '../models/category.dart';
import '../services/auto_expense_service.dart';
import '../services/receipt_service.dart';
import '../services/transaction_store.dart';
import '../services/budget_service.dart';
import '../widgets/budget_watch.dart';
import 'package:image_picker/image_picker.dart';

class DashboardScreen extends StatefulWidget {
  final Function(int)? onTabChange;

  const DashboardScreen({super.key, this.onTabChange});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  DashboardData? _data;
  bool _isLoading = true;
  StreamSubscription<void>? _syncSub;
  final Map<int, GlobalKey<ThanosSnapWidgetState>> _snapKeys = {};

  /// Spending of the last 7 days (oldest first) and their weekday letters.
  List<double> _week = List.filled(7, 0);
  List<String> _weekDays = List.filled(7, '');

  /// Full day names of the last 7 days ("Tuesday"), for the ring's caption.
  List<String> _weekNames = List.filled(7, '');

  /// The bar picked in the Home card (null: today / the default one).
  int? _selBar;

  /// Everything saved on the phone (for the category and month charts).
  List<TransactionModel> _txns = const [];

  /// Frequent expenses offered as one-tap repeats.
  List<_Again> _again = const [];

  /// This month's category budgets that are 80% used or more.
  List<BudgetInfo> _nearLimit = const [];
  int _budgetCount = -1; // this month's budgets (-1 until loaded)
  int _reviewCount = 0;
  StreamSubscription<void>? _autoSub;

  /// Unread notifications (daily reminders, split updates).
  int _unread = 0;
  StreamSubscription<void>? _inboxSub;

  /// Month shown in the hero card; [_past] holds its numbers when it is not this month.
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  _MonthView? _past;

  bool get _isThisMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _loadUnread();
    NotificationInbox.refresh();
    _inboxSub = NotificationInbox.changes.listen((_) => _loadUnread());
    WidgetsBinding.instance.addObserver(this);

    // Listen for background sync completions to refresh UI immediately
    _syncSub = SyncService.onSyncComplete.listen((_) {
      debugPrint('[Dashboard] Background sync detected — refreshing data...');
      _loadDashboard();
    });
    _autoSub = AutoExpenseService.changes.listen((_) => _loadExtras());
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _autoSub?.cancel();
    _inboxSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Public method for parent to trigger a data reload.
  void reload() {
    _loadDashboard();
    if (!_isThisMonth) _loadMonth(_month);
  }

  /// A reminder may have arrived while the app was in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadUnread();
  }

  Future<void> _loadUnread() async {
    final n = await NotificationInbox.unreadCount();
    if (mounted && n != _unread) setState(() => _unread = n);
  }

  Future<void> _openNotifications() async {
    AppHaptics.tap();
    await NotificationsScreen.open(context);
    _loadUnread();
    _loadExtras();
  }

  /// Month picker: this month and the 11 before it.
  Future<void> _pickMonth() async {
    AppHaptics.tap();
    final now = DateTime.now();
    final months = List.generate(12, (i) => DateTime(now.year, now.month - i));
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: AppColors.card,
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Show month', style: AppText.section),
                  const SizedBox(height: 14),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.4,
                    children: [
                      for (final m in months)
                        Builder(
                          builder: (_) {
                            final on = m.year == _month.year && m.month == _month.month;
                            return Material(
                              color: on ? AppColors.dark : AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => Navigator.pop(ctx, m),
                                child: Center(
                                  child: Text(
                                    m.year == now.year
                                        ? DateFormat('MMMM').format(m)
                                        : DateFormat('MMM yyyy').format(m),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: on ? Colors.white : AppColors.text,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
    if (picked == null || !mounted) return;
    _selectMonth(picked);
  }

  void _selectMonth(DateTime m) {
    setState(() {
      _month = DateTime(m.year, m.month);
      _past = null;
      _selBar = null;
    });
    if (!_isThisMonth) _loadMonth(_month);
  }

  /// Numbers for an earlier month: from the transactions on this phone first, then from
  /// the server (which also knows the budget and older entries).
  Future<void> _loadMonth(DateTime month) async {
    final key = DateFormat('yyyy-MM').format(month);
    final cached = await CacheService.getCachedTransactions();
    final txns =
        ((cached?['transactions'] as List?) ?? const [])
            .whereType<Map>()
            .map((t) => TransactionModel.fromJson(Map<String, dynamic>.from(t)))
            .where((t) => DateFormat('yyyy-MM').format(t.date.toLocal()) == key)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    final local = _MonthView.fromTransactions(month, txns);
    if (!mounted || month != _month) return;
    setState(() => _past = local);

    final r = await ApiService.getDashboard(month: key);
    if (!mounted || month != _month || !r.isSuccess || r.data == null) return;
    final d = r.data!;
    if (d.month != key) return; // older server ignores ?month: keep the phone's numbers
    setState(() => _past = _MonthView.fromServer(month, d, local));
  }

  Future<void> _loadDashboard() async {
    final cached = await CacheService.getCachedDashboard();
    final cachedUser = await CacheService.getCachedUser();

    if (cached != null && mounted) {
      if (cachedUser != null) {
        cached['user'] = cachedUser;
      }
      final d = DashboardData.fromJson(cached);
      setState(() {
        _data = d;
        _isLoading = false;
      });

      _loadExtras();

      // Update home screen widget
      WidgetService.updateDashboard(
        totalBalance: double.tryParse(d.totalBalance.replaceAll(',', '')) ?? 0,
        totalIncome: double.tryParse(d.monthlyIncome.replaceAll(',', '')) ?? 0,
        totalExpense: double.tryParse(d.monthlyExpenses.replaceAll(',', '')) ?? 0,
        currencySymbol: d.currencySymbol,
      );
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Week bars, one-tap repeats and the review count, all from local data.
  Future<void> _loadExtras() async {
    final cached = await CacheService.getCachedTransactions();
    final txns = ((cached?['transactions'] as List?) ?? const []).whereType<Map>().toList();
    final today = DateUtils.dateOnly(DateTime.now());
    final week = List<double>.filled(7, 0);
    final days = List.generate(7, (i) => DateFormat('E').format(today.subtract(Duration(days: 6 - i)))[0]);
    final names = List.generate(7, (i) => DateFormat('EEEE').format(today.subtract(Duration(days: 6 - i))));
    final counts = <String, _Again>{};
    for (final t in txns) {
      if (t['type'] != 'expense') continue;
      final date = DateTime.tryParse(t['date']?.toString() ?? '')?.toLocal();
      final amount = double.tryParse(t['amount']?.toString() ?? '') ?? 0;
      if (date == null || amount <= 0) continue;
      final age = today.difference(DateUtils.dateOnly(date)).inDays;
      if (age >= 0 && age < 7) week[6 - age] += amount;
      if (age < 0 || age > 60) continue;
      final cat = t['category'] is Map ? Map<String, dynamic>.from(t['category'] as Map) : null;
      final note = (t['notes'] ?? '').toString().trim();
      final key = '${note.toLowerCase()}|${cat?['id']}|${amount.toStringAsFixed(2)}';
      final prev = counts[key];
      counts[key] = _Again(
        label: note.isNotEmpty ? note : (cat?['name']?.toString() ?? 'Other'),
        amount: amount,
        note: note,
        category: cat == null ? null : CategoryModel.fromJson(cat),
        count: (prev?.count ?? 0) + 1,
      );
    }
    final again = counts.values.where((a) => a.count >= 2).toList()..sort((a, b) => b.count.compareTo(a.count));
    var review = 0;
    if (await AutoExpenseService.isAvailable()) review = await AutoExpenseService.reviewCount();
    if (!mounted) return;
    final all =
        txns
            .map((t) {
              try {
                return TransactionModel.fromJson(Map<String, dynamic>.from(t));
              } catch (_) {
                return null;
              }
            })
            .whereType<TransactionModel>()
            .toList();
    final budgets = await BudgetService.byCategory();
    // Up to five budgets: over or close ones are never left out, the rest by use; then
    // shown with the most entries first.
    final set = budgets.values.where((b) => b.limit > 0).toList()..sort(BudgetInfo.byUse);
    final near = [
      ...set.where((b) => b.fraction >= 0.8),
      ...set.where((b) => b.fraction < 0.8),
    ].take(5).toList()
      ..sort(BudgetInfo.byUse);
    if (!mounted) return;
    setState(() {
      _nearLimit = near;
      _budgetCount = budgets.length;
      _txns = all;
      _week = week;
      _weekDays = days;
      _weekNames = names;
      _again = again.take(4).toList();
      _reviewCount = review;
    });
  }

  String _money(num v, String symbol) {
    final whole = v == v.roundToDouble();
    final f = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: whole ? 0 : 2);
    return '${v < 0 ? '−' : ''}$symbol${f.format(v.abs())}';
  }

  double _num(String s) => double.tryParse(s.replaceAll(',', '')) ?? 0;

  Future<void> _openQuickAdd({String type = 'expense'}) async {
    final added = await QuickAddScreen.open(context, type: type);
    if (added && mounted) _loadDashboard();
  }

  Future<void> _scanReceipt() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final scan = await ReceiptService.recognize(picked.path);
    if (!mounted) return;
    if (scan == null) {
      AppToast.error(context, 'Could not read text from this image.');
      return;
    }
    await ReceiptService.openForm(context, scan: scan);
    if (mounted) _loadDashboard();
  }

  Future<void> _addAgain(_Again a, String symbol) async {
    AppHaptics.confirm();
    final id = await TransactionStore.create(amount: a.amount, type: 'expense', category: a.category, notes: a.note);
    if (!mounted) return;
    await _loadDashboard();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('−${_money(a.amount, symbol)} added · ${a.label}'),
          duration: const Duration(seconds: 4),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await TransactionStore.remove(id);
              if (mounted) _loadDashboard();
            },
          ),
        ),
      );
  }

  Future<void> _openReview() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AutoTrackReviewScreen()));
    if (mounted) _loadDashboard();
  }

  // ─── Home: top part ──────────────────────────────────────────────────────

  Widget _header(DashboardData d) {
    final parts = d.user.displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final firstName = parts.isEmpty ? '' : parts.first;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 16),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Semantics(
              button: true,
              label: 'Profile and settings',
              excludeSemantics: true,
              child: SpringPress(
                onTap: () async {
                  await Navigator.pushNamed(context, '/profile');
                  if (mounted) _loadDashboard();
                },
                child: ProfileAvatar(
                  name: d.user.displayName,
                  avatar: d.user.avatar,
                  size: 44,
                  background: AppColors.dark,
                  foreground: AppColors.accent,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Good ${d.greeting.toLowerCase()}', style: AppText.rowSub),
                  MorphText(
                    id: 'home-name',
                    d.user.displayName.trim().isEmpty ? firstName : d.user.displayName.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text),
                  ),
                ],
              ),
            ),
            Semantics(
              button: true,
              label: _unread + _reviewCount > 0 ? 'Notifications, ${_unread + _reviewCount} new' : 'Notifications',
              excludeSemantics: true,
              child: SpringPress(
                haptic: HapticKind.none,
                onTap: _openNotifications,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    boxShadow: AppShadows.accent,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(Icons.notifications_rounded, size: 22, color: AppColors.dark),
                      if (_unread + _reviewCount > 0)
                        Positioned(
                          top: 9,
                          right: 10,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: AppColors.dark,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.accent, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(DashboardData d) {
    final past = _isThisMonth ? null : _past;
    final now = DateTime.now();
    final spent = past?.spent ?? _num(d.monthlyExpenses);
    final income = past?.income ?? _num(d.monthlyIncome);
    final limit = past?.limit ?? d.monthlyBudgetLimit;
    final avgDaily = past?.avgDaily ?? spent / now.day;
    final bars = past?.bars ?? _week;
    final labels = past?.barLabels ?? _weekDays;
    final highlight = past?.highlight ?? 6;
    final loading = !_isThisMonth && past == null;
    final title = _isThisMonth ? 'Spent this month' : 'Spent in ${DateFormat('MMMM').format(_month)}';
    final chip =
        _isThisMonth || _month.year == now.year
            ? DateFormat('MMMM').format(_month)
            : DateFormat('MMM yyyy').format(_month);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: AppShadows.elevated,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 13, color: AppColors.darkMuted))),
              Semantics(
                button: true,
                label: 'Month: $chip. Change month',
                excludeSemantics: true,
                child: SpringPress(
                  haptic: HapticKind.none,
                  onTap: _pickMonth,
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    decoration: BoxDecoration(color: AppColors.darkCardRaised, borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          chip,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        const Icon(Icons.expand_more_rounded, size: 18, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: loading ? 0.4 : 1,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  MorphText(
                    id: 'home-spent',
                    _money(spent, d.currencySymbol),
                    style: AppText.hero.copyWith(color: Colors.white, fontSize: 34, letterSpacing: -1),
                  ),
                  if (limit > 0) ...[
                    const SizedBox(width: 8),
                    MorphText(
                      id: 'home-spent',
                      'of ${_money(limit, d.currencySymbol)}',
                      style: const TextStyle(fontSize: 13, color: AppColors.darkMuted),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _dayRing(
            bars: bars,
            labels: labels,
            highlight: highlight,
            avg: _isThisMonth ? avgDaily : (bars.isEmpty ? 0 : bars.fold<double>(0, (a, b) => a + b) / bars.length),
            symbol: d.currencySymbol,
            limit: _isThisMonth ? limit : 0,
            monthSpent: spent,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _heroStat('Avg / day', _money(avgDaily.roundToDouble(), d.currencySymbol), Colors.white)),
              const SizedBox(width: 8),
              Expanded(
                child:
                    _isThisMonth
                        ? _heroStat(
                          limit > 0 ? 'Left to spend' : 'Balance',
                          limit > 0
                              ? _money(math.max(0, limit - spent), d.currencySymbol)
                              : _money(_num(d.totalBalance), d.currencySymbol),
                          Colors.white,
                        )
                        : _heroStat(
                          income >= spent ? 'Saved' : 'Overspent',
                          _money((income - spent).abs(), d.currencySymbol),
                          Colors.white,
                        ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _heroStat('Money in', '+${_money(income, d.currencySymbol)}', AppColors.accent)),
            ],
          ),
        ],
      ),
    );
  }

  /// The ring (always in the app colour): the picked day's spending (today by default)
  /// against the daily average,
  /// with a message beside it and the week's bars below the message. Tap a bar to see that
  /// day in the ring. For an earlier month the bars are weeks, against the weekly average.
  Widget _dayRing({
    required List<double> bars,
    required List<String> labels,
    required int highlight,
    required double avg,
    required String symbol,
    double limit = 0,
    double monthSpent = 0,
  }) {
    if (bars.isEmpty) return const SizedBox(height: 8);
    final sel = (_selBar ?? highlight).clamp(0, bars.length - 1);
    final value = bars[sel];
    // With a monthly budget, today is measured against what is safe to spend today:
    // the budget left at the start of today spread over the days left (today included).
    final isToday = _isThisMonth && sel == bars.length - 1;
    final now = DateTime.now();
    final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day + 1;
    final safe = isToday && limit > 0 ? math.max(0.0, (limit - (monthSpent - value)) / daysLeft) : 0.0;
    final useSafe = isToday && limit > 0;
    if (useSafe) avg = safe;
    final over = avg > 0 && value > avg;
    final fraction = avg <= 0 ? (value > 0 ? 1.0 : 0.0) : (value / avg).clamp(0.0, 1.0);
    // Always the app colour, even over the average (only the message says so).
    final color = AppColors.accent;
    final maxBar = bars.fold<double>(0, math.max);
    final String caption;
    if (_isThisMonth) {
      caption =
          sel == bars.length - 1
              ? 'TODAY'
              : sel == bars.length - 2
              ? 'YESTERDAY'
              : (sel < _weekNames.length && _weekNames[sel].isNotEmpty ? _weekNames[sel] : labels[sel]).toUpperCase();
    } else {
      caption = '${sel < labels.length ? labels[sel] : ''} ${DateFormat('MMM').format(_month)}'.toUpperCase();
    }
    final unit = _isThisMonth ? 'daily' : 'weekly';
    final diff = (avg - value).abs();
    final String message;
    if (useSafe) {
      message =
          safe <= 0
              ? 'The month\'s budget is used up.'
              : over
              ? '${_money(diff.roundToDouble(), symbol)} over what is safe for today.'
              : 'You can still spend ${_money(diff.roundToDouble(), symbol)} today and stay on budget.';
    } else if (value <= 0) {
      message = _isThisMonth && sel == bars.length - 1 ? 'Nothing spent yet today.' : 'Nothing spent.';
    } else if (avg <= 0) {
      message = 'Spent ${_money(value.roundToDouble(), symbol)}.';
    } else if (over) {
      message = '${_money(diff.roundToDouble(), symbol)} more than your $unit average.';
    } else {
      message = '${_money(diff.roundToDouble(), symbol)} less than your $unit average. Nice!';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 116,
          height: 116,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: fraction),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutBack,
            builder:
                (context, f, child) => CustomPaint(
                  painter: _RingPainter(fraction: f.clamp(0.0, 1.0), color: color, track: AppColors.darkCardRaised),
                  child: child,
                ),
            child: Padding(
              // Keeps the text inside the ring; long amounts shrink to fit.
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      caption,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.darkMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: MorphText(
                      id: 'home-ring-$sel',
                      _money(value.roundToDouble(), symbol),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (avg > 0)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'of ${_money(avg.roundToDouble(), symbol)} ${useSafe ? 'safe' : 'avg'}',
                        maxLines: 1,
                        style: const TextStyle(fontSize: 10, color: AppColors.darkFaint),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  message,
                  key: ValueKey(message),
                  maxLines: 2,
                  style: TextStyle(fontSize: 12, height: 1.35, fontWeight: FontWeight.w600, color: AppColors.darkMuted),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 54,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(bars.length, (i) {
                    final on = i == sel;
                    final h = maxBar <= 0 ? 6.0 : math.max(6.0, 36 * (bars[i] / maxBar));
                    final barColor = on ? AppColors.accent : AppColors.darkCardRaised;
                    return Expanded(
                      child: Semantics(
                        button: true,
                        selected: on,
                        label: '${i < labels.length ? labels[i] : ''}: ${_money(bars[i], symbol)}',
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (i == sel) return;
                            AppHaptics.tap();
                            setState(() => _selBar = i);
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 450),
                                curve: Curves.easeOutBack,
                                width: on ? 10 : 8,
                                height: h,
                                decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(5)),
                              ),
                              const SizedBox(height: 4),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  i < labels.length ? labels[i] : '',
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: on ? barColor : AppColors.darkFaint,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroStat(String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(color: AppColors.darkCard, borderRadius: BorderRadius.circular(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: AppColors.darkMuted),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        ),
      ],
    ),
  );

  Widget _actions() {
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Add expense',
            excludeSemantics: true,
            child: SpringPress(
              haptic: HapticKind.confirm,
              onTap: _openQuickAdd,
              child: Container(
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: AppShadows.accent,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(color: AppColors.dark, shape: BoxShape.circle),
                      child: Icon(Icons.add_rounded, size: 20, color: AppColors.accent),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Add expense',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.dark),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Semantics(
          button: true,
          label: 'Scan receipt',
          excludeSemantics: true,
          child: SpringPress(
            onTap: _scanReceipt,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                boxShadow: AppShadows.soft,
              ),
              child: const Icon(Icons.document_scanner_rounded, size: 24, color: AppColors.dark),
            ),
          ),
        ),
      ],
    );
  }

  Widget _againRow(DashboardData d) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add again in one tap',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children:
                  _again.map((a) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Semantics(
                        button: true,
                        label: 'Add ${a.label} ${_money(a.amount, d.currencySymbol)} again',
                        excludeSemantics: true,
                        child: SpringPress(
                          haptic: HapticKind.none,
                          onTap: () => _addAgain(a, d.currencySymbol),
                          child: Container(
                            height: 42,
                            padding: const EdgeInsets.only(left: 6, right: 14),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(21),
                              boxShadow: AppShadows.soft,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: const BoxDecoration(
                                    color: AppColors.categoryFill,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    IconMapper.map(a.category?.icon ?? 'category'),
                                    size: 17,
                                    color: AppColors.categoryInk,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 120),
                                  child: Text(
                                    a.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.text,
                                    ),
                                  ),
                                ),
                                Text(
                                  ' ${_money(a.amount, d.currencySymbol)}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _edit(TransactionModel txn) => TransactionFormScreen.show(
    context,
    transactionId: txn.id,
    onSaved: () {
      _loadDashboard();
      if (!_isThisMonth) _loadMonth(_month);
    },
  );

  Future<void> _delete(TransactionModel txn, GlobalKey<ThanosSnapWidgetState> snapKey) async {
    final sign = txn.isIncome ? '+' : '−';
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete this entry?'),
            content: Text(
              '${txn.notes.trim().isNotEmpty ? txn.notes.trim() : txn.category.name} '
              '($sign${_data?.currencySymbol ?? '₹'}${txn.amount}) will be removed.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
            ],
          ),
    );
    if (ok != true || !mounted) return;
    AppHaptics.confirm();
    await snapKey.currentState?.startSnap();
    await TransactionStore.remove(txn.id);
    if (!mounted) return;
    await _loadDashboard();
    if (!_isThisMonth) _loadMonth(_month);
    if (mounted) AppToast.success(context, 'Deleted');
  }

  /// One white card: payments to review, then "Recent" with the latest entries.
  /// Up to five budgets (over or close ones always among them), as a deck of money-left charts to swipe
  /// through. Sits under "Month by month". Tap a card (or "All") to open Budgets.
  Widget _watchCard(String symbol) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                Expanded(child: Text('Budgets', style: AppText.section)),
                if (_budgetCount > 0)
                  SpringPress(
                    haptic: HapticKind.tap,
                    onTap: () => widget.onTabChange?.call(2),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'All budgets',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_nearLimit.isEmpty)
            BudgetWatchEmpty(budgets: _budgetCount, onSet: () => widget.onTabChange?.call(2))
          else
            BudgetWatchDeck(
              items: _nearLimit,
              symbol: symbol,
              today: DateTime.now(),
              onOpen: () => widget.onTabChange?.call(2),
            ),
        ],
      ),
    );
  }

  Widget _recentCard(DashboardData d) {
    final past = _isThisMonth ? null : _past;
    final list = (past?.recent ?? d.recentTransactions).take(4).toList();
    final title = _isThisMonth ? 'Recent' : 'In ${DateFormat('MMMM').format(_month)}';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          boxShadow: AppShadows.soft,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_reviewCount > 0 && _isThisMonth) ...[
              InkWell(
                onTap: _openReview,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                        child: const Icon(Icons.bolt_rounded, size: 22, color: AppColors.dark),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _reviewCount == 1 ? '1 payment to review' : '$_reviewCount payments to review',
                              style: AppText.rowTitle,
                            ),
                            const Text('Found in your UPI notifications', style: AppText.rowSub),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: AppText.section)),
                  TextButton(
                    onPressed: () => widget.onTabChange?.call(1),
                    child: const Text(
                      'See all',
                      style: TextStyle(decoration: TextDecoration.underline, decorationThickness: 2),
                    ),
                  ),
                ],
              ),
            ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: Text(
                  _isThisMonth
                      ? 'No transactions yet. Tap “Add expense” to log your first one.'
                      : 'Nothing was logged in ${DateFormat('MMMM').format(_month)}.',
                  style: AppText.rowSub,
                ),
              )
            else
              for (final txn in list)
                Builder(
                  builder: (_) {
                    final snapKey = _snapKeys.putIfAbsent(txn.id, () => GlobalKey<ThanosSnapWidgetState>());
                    return ThanosSnapWidget(
                      key: snapKey,
                      child: TransactionTile(
                        transaction: txn,
                        currencySymbol: d.currencySymbol,
                        card: false,
                        showActions: true,
                        onTap: () => _edit(txn),
                        onEdit: () => _edit(txn),
                        onDelete: () => _delete(txn, snapKey),
                      ),
                    );
                  },
                ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Future<void> _handleRefresh() async {
    await SyncService.syncAll();
    await _loadDashboard();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildSkeleton();
    if (_data == null) return _buildEmpty();

    final d = _data!;

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: AppColors.dark,
      child: SingleChildScrollView(
        physics: const EspereScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(d),
            _hero(d),
            const SizedBox(height: 16),
            _actions(),
            if (_again.isNotEmpty) _againRow(d),
            _recentCard(d),
            CategoryBreakdownCard(
              key: ValueKey('cat${_month.year}-${_month.month}'),
              month: _month,
              transactions: _txns,
              symbol: d.currencySymbol,
            ),
            MonthlyTrendCard(selected: _month, transactions: _txns, symbol: d.currencySymbol, onSelect: _selectMonth),
            if (_isThisMonth && _budgetCount >= 0) _watchCard(d.currencySymbol),
            const NavBottomSpace(),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [_shimmer(96, 12), const SizedBox(height: 8), _shimmer(192, 32)],
              ),
              _shimmer(48, 48, radius: AppRadius.xl),
            ],
          ),
          const SizedBox(height: 16),
          _shimmer(double.infinity, 200, radius: AppRadius.xxxl),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _shimmer(double.infinity, 100, radius: AppRadius.xxl)),
              const SizedBox(width: 12),
              Expanded(child: _shimmer(double.infinity, 100, radius: AppRadius.xxl)),
              const SizedBox(width: 12),
              Expanded(child: _shimmer(double.infinity, 100, radius: AppRadius.xxl)),
            ],
          ),
          const SizedBox(height: 16),
          _shimmer(double.infinity, 220, radius: AppRadius.xxl),
          const SizedBox(height: 16),
          _shimmer(double.infinity, 200, radius: AppRadius.xxl),
          const SizedBox(height: 16),
          ...List.generate(
            3,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _shimmer(double.infinity, 72, radius: AppRadius.xxl),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shimmer(double width, double height, {double radius = 8}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(radius)),
    );
  }

  Widget _buildEmpty() {
    return const Center(child: Text('No data available', style: TextStyle(color: AppColors.muted)));
  }
}

/// A frequent expense offered as a one-tap repeat on Home.
class _Again {
  final String label;
  final double amount;
  final String note;
  final CategoryModel? category;
  final int count;
  const _Again({
    required this.label,
    required this.amount,
    required this.note,
    required this.category,
    required this.count,
  });
}

/// Hero numbers for a month other than this one.
class _MonthView {
  final double spent;
  final double income;
  final double limit;
  final double avgDaily;
  final List<double> bars;
  final List<String> barLabels;
  final int highlight;
  final List<TransactionModel> recent;

  const _MonthView({
    required this.spent,
    required this.income,
    required this.limit,
    required this.avgDaily,
    required this.bars,
    required this.barLabels,
    required this.highlight,
    required this.recent,
  });

  static int _days(DateTime m) => DateTime(m.year, m.month + 1, 0).day;

  static (List<double>, List<String>) _weeks(DateTime m, List<double> daily) {
    final days = _days(m);
    final values = <double>[];
    final labels = <String>[];
    for (var start = 1; start <= days; start += 7) {
      final end = math.min(start + 6, days);
      var sum = 0.0;
      for (var d = start; d <= end; d++) {
        sum += daily[d - 1];
      }
      values.add(sum);
      labels.add('$start–$end');
    }
    return (values, labels);
  }

  static int _maxIndex(List<double> v) {
    var best = -1;
    var max = 0.0;
    for (var i = 0; i < v.length; i++) {
      if (v[i] > max) {
        max = v[i];
        best = i;
      }
    }
    return best;
  }

  /// From the transactions saved on this phone.
  factory _MonthView.fromTransactions(DateTime month, List<TransactionModel> txns) {
    final daily = List<double>.filled(_days(month), 0);
    var spent = 0.0, income = 0.0;
    for (final t in txns) {
      final v = double.tryParse(t.amount) ?? 0;
      if (t.isIncome) {
        income += v;
      } else {
        spent += v;
        daily[t.date.toLocal().day - 1] += v;
      }
    }
    final (bars, labels) = _weeks(month, daily);
    return _MonthView(
      spent: spent,
      income: income,
      limit: 0,
      avgDaily: spent / _days(month),
      bars: bars,
      barLabels: labels,
      highlight: _maxIndex(bars),
      recent: txns.take(5).toList(),
    );
  }

  /// From `/api/dashboard/?month=`, falling back to [local] for what the server leaves out.
  factory _MonthView.fromServer(DateTime month, DashboardData d, _MonthView local) {
    final spent = double.tryParse(d.monthlyExpenses.replaceAll(',', '')) ?? local.spent;
    final bars = d.weekValues.isNotEmpty ? d.weekValues : local.bars;
    return _MonthView(
      spent: spent,
      income: double.tryParse(d.monthlyIncome.replaceAll(',', '')) ?? local.income,
      limit: d.monthlyBudgetLimit,
      avgDaily: d.avgDaily ?? spent / _days(month),
      bars: bars,
      barLabels: d.weekLabels.length == bars.length ? d.weekLabels : local.barLabels,
      highlight: _maxIndex(bars),
      recent: d.recentTransactions.isNotEmpty ? d.recentTransactions : local.recent,
    );
  }
}

/// A ring that fills clockwise from the top.
class _RingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color track;

  const _RingPainter({required this.fraction, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - stroke / 2);
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    if (fraction > 0) {
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * fraction, false, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.color != color || old.track != track;
}
