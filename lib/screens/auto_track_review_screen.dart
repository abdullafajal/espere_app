import 'dart:async';
import '../theme/motion.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/auto_expense_service.dart';
import '../services/cache_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/espere_header.dart';

/// Low-confidence payments wait here. One tap adds or discards each one;
/// nothing uncertain is ever added silently.
class AutoTrackReviewScreen extends StatefulWidget {
  const AutoTrackReviewScreen({super.key});

  @override
  State<AutoTrackReviewScreen> createState() => _AutoTrackReviewScreenState();
}

class _AutoTrackReviewScreenState extends State<AutoTrackReviewScreen> {
  List<ReviewItem>? _items;
  final Map<String, int?> _chosenCategory = {};
  final Map<int, String> _categoryNames = {};
  String _symbol = '₹';
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = AutoExpenseService.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await AutoExpenseService.reviewItems();
    final cats = await CacheService.getCachedCategories();
    final names = <int, String>{
      for (final c in List<Map<String, dynamic>>.from(cats?['categories'] ?? const []))
        if (c['id'] is int) c['id'] as int: (c['name'] ?? '').toString(),
    };
    if (!mounted) return;
    setState(() {
      _items = items;
      _categoryNames
        ..clear()
        ..addAll(names);
      _symbol = (cats?['currency_symbol'] ?? '₹').toString();
    });
  }

  Future<void> _add(ReviewItem item) async {
    AppHaptics.confirm();
    await AutoExpenseService.confirmReview(item, categoryId: _chosenCategory[item.id] ?? item.txn.categoryId);
    if (mounted) AppToast.success(context, 'Added');
    await _load();
  }

  Future<void> _discard(ReviewItem item) async {
    AppHaptics.press();
    await AutoExpenseService.discardReview(item);
    await _load();
  }

  Future<void> _pickCategory(ReviewItem item) async {
    final cats = await AutoExpenseService.categoriesFor(item.txn.type);
    if (!mounted) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxxl)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Category', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final c in cats)
              ListTile(
                title: Text((c['name'] ?? '').toString()),
                trailing: (_chosenCategory[item.id] ?? item.txn.categoryId) == c['id']
                    ? const Icon(Icons.check_rounded, color: AppColors.text)
                    : null,
                onTap: () => Navigator.pop(ctx, c['id'] as int?),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _chosenCategory[item.id] = picked);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            EspereHeader(title: 'Review payments', onBack: () => Navigator.pop(context)),
            Expanded(
              child: items == null
                  ? const Center(child: CircularProgressIndicator(color: AppColors.dark))
                  : items.isEmpty
                      ? const _Empty()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _tile(items[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(ReviewItem item) {
    final t = item.txn;
    final amount = t.amount == t.amount.roundToDouble() ? t.amount.toStringAsFixed(0) : t.amount.toStringAsFixed(2);
    final catId = _chosenCategory[item.id] ?? t.categoryId;
    final catName = _categoryNames[catId] ?? 'Choose category';
    final when = DateFormat('MMM d · h:mm a').format(t.time);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.payee ?? 'Unknown payee',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
                    const SizedBox(height: 2),
                    Text('${t.sourceApp} · $when${t.last4 != null ? ' · ••${t.last4}' : ''}',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              Text('${t.type == 'income' ? '+' : '-'}$_symbol$amount',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickCategory(item),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(catName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        const Icon(Icons.expand_more_rounded, color: AppColors.muted),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _discard(item),
                child: const Text('Discard', style: TextStyle(color: AppColors.muted)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.dark,
                  foregroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
                onPressed: () => _add(item),
                child: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 48, color: AppColors.muted),
              SizedBox(height: 12),
              Text('All caught up', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text(
                'Payments that need a quick check show up here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ],
          ),
        ),
      );
}
