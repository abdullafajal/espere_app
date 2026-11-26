/// One budget: how much of it is used this month, how last month compared, and every
/// entry that went into it (tap one to edit it). Opened by tapping a budget.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/transaction.dart';
import '../services/budget_service.dart';
import '../services/cache_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/icon_mapper.dart';
import '../widgets/espere_header.dart';
import '../widgets/morph_text.dart';
import '../widgets/transaction_tile.dart';
import 'quick_add_screen.dart';
import 'dart:async';

class BudgetDetailScreen extends StatefulWidget {
  final Map<String, dynamic> budget;
  final DateTime month;
  final String currencySymbol;
  final VoidCallback? onEdit;

  const BudgetDetailScreen({
    super.key,
    required this.budget,
    required this.month,
    required this.currencySymbol,
    this.onEdit,
  });

  @override
  State<BudgetDetailScreen> createState() => _BudgetDetailScreenState();
}

class _BudgetDetailScreenState extends State<BudgetDetailScreen> {
  List<TransactionModel> _entries = [];
  double _lastMonth = 0;
  BudgetInfo? _info;
  StreamSubscription<void>? _sync;

  int? get _catId {
    final cat = widget.budget['category'];
    return int.tryParse(((cat is Map ? cat['id'] : null) ?? widget.budget['category_id'])?.toString() ?? '');
  }

  String get _name {
    final cat = widget.budget['category'];
    return (cat is Map ? cat['name'] : null)?.toString() ?? 'Budget';
  }

  String get _icon {
    final cat = widget.budget['category'];
    return (cat is Map ? cat['icon'] : null)?.toString() ?? 'category';
  }

  @override
  void initState() {
    super.initState();
    _load();
    _sync = SyncService.onSyncComplete.listen((_) => _load());
  }

  @override
  void dispose() {
    _sync?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final id = _catId;
    final cached = await CacheService.getCachedTransactions();
    final all = ((cached?['transactions'] as List?) ?? const []).whereType<Map>();
    final prev = DateTime(widget.month.year, widget.month.month - 1);
    final entries = <TransactionModel>[];
    var last = 0.0;
    for (final t in all) {
      if (t['type'] != 'expense') continue;
      final cat = t['category'];
      if (cat is! Map || cat['id']?.toString() != id?.toString()) continue;
      final at = DateTime.tryParse(t['date']?.toString() ?? '')?.toLocal();
      if (at == null) continue;
      if (at.year == widget.month.year && at.month == widget.month.month) {
        try {
          entries.add(TransactionModel.fromJson(Map<String, dynamic>.from(t)));
        } catch (_) {}
      } else if (at.year == prev.year && at.month == prev.month) {
        last += double.tryParse(t['amount']?.toString() ?? '') ?? 0;
      }
    }
    entries.sort((a, b) => b.date.compareTo(a.date));
    final info = id == null ? null : (await BudgetService.byCategory(widget.month))[id];
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _lastMonth = last;
      _info = info;
    });
  }

  String _m(double v) =>
      '${widget.currencySymbol}${NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0).format(v.round())}';

  @override
  Widget build(BuildContext context) {
    final limit = _info?.limit ?? (double.tryParse(widget.budget['amount'].toString()) ?? 0);
    final spent = _info?.spent ?? (double.tryParse(widget.budget['spent']?.toString() ?? '') ?? 0);
    final fraction = limit <= 0 ? 0.0 : (spent / limit).clamp(0.0, 1.0);
    final repeat = widget.budget['repeat'] != false;
    final carried = double.tryParse(widget.budget['carried']?.toString() ?? '') ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            EspereHeader(title: _name, onBack: () => Navigator.pop(context)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
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
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(color: AppColors.darkCardRaised, shape: BoxShape.circle),
                              child: Icon(IconMapper.map(_icon), size: 19, color: AppColors.accent),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                [
                                  DateFormat('MMMM').format(widget.month),
                                  repeat ? 'Every month' : 'This month only',
                                  if (carried > 0) '+${_m(carried)} carried',
                                ].join(' · '),
                                style: const TextStyle(fontSize: 12, color: AppColors.darkMuted),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              MorphText(id: 'bd', _m(spent),
                                  style: AppText.hero.copyWith(color: Colors.white, fontSize: 30, letterSpacing: -1)),
                              const SizedBox(width: 8),
                              MorphText(id: 'bd', 'of ${_m(limit)}',
                                  style: const TextStyle(fontSize: 13, color: AppColors.darkMuted)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: fraction,
                            minHeight: 10,
                            backgroundColor: AppColors.darkCardRaised,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                spent > limit ? '${_m(spent - limit)} over' : '${_m(limit - spent)} left',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                            ),
                            Text('Last month ${_m(_lastMonth)}',
                                style: const TextStyle(fontSize: 12, color: AppColors.darkMuted)),
                          ],
                        ),
                        if (widget.onEdit != null) ...[
                          const SizedBox(height: 14),
                          SpringPress(
                            haptic: HapticKind.tap,
                            onTap: () {
                              Navigator.pop(context);
                              widget.onEdit!();
                            },
                            child: Container(
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.darkCardRaised,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit_rounded, size: 17, color: AppColors.accent),
                                  const SizedBox(width: 6),
                                  const Text('Edit budget',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 20, 6, 8),
                    child: Text(
                      'THIS MONTH · ${_entries.length} ${_entries.length == 1 ? 'ENTRY' : 'ENTRIES'}',
                      style: AppText.label,
                    ),
                  ),
                  if (_entries.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(AppRadius.xxl)),
                      child: Text('Nothing spent on $_name this month yet.',
                          textAlign: TextAlign.center, style: AppText.rowSub),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(AppRadius.xxl),
                        boxShadow: AppShadows.soft,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < _entries.length; i++) ...[
                            if (i > 0) const Divider(height: 1, indent: 68, color: AppColors.border),
                            TransactionTile(
                              transaction: _entries[i],
                              currencySymbol: widget.currencySymbol,
                              card: false,
                              onTap: () async {
                                if (await QuickAddScreen.edit(context, _entries[i].id)) _load();
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
