/// Notifications (the bell on Home): payments to review, then the daily reminders and
/// split updates the server sent. Tap opens what it is about; swipe removes it.
library;

import 'dart:async';
import '../theme/motion.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/auto_expense_service.dart';
import '../services/notification_inbox.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/espere_header.dart';
import '../widgets/thanos_snap_widget.dart';
import 'auto_track_review_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<InboxItem> _items = const [];
  int _review = 0;
  bool _loading = true;
  bool _offline = false;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = NotificationInbox.changes.listen((_) => _loadCached());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadCached() async {
    final items = await NotificationInbox.cached();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _load() async {
    await _loadCached();
    var review = 0;
    if (await AutoExpenseService.isAvailable()) review = await AutoExpenseService.reviewCount();
    if (mounted) setState(() => _review = review);
    final fresh = await NotificationInbox.refresh();
    if (!mounted) return;
    setState(() {
      if (fresh != null) _items = fresh;
      _offline = fresh == null;
      _loading = false;
    });
  }

  Future<void> _openItem(InboxItem item) async {
    AppHaptics.tap();
    if (!item.isRead) NotificationInbox.markRead([item.id]);
    final data = item.data;
    if (data['action'] == null || data['action'] == 'open_dashboard') {
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      return;
    }
    NotificationService.openAction(data);
  }

  final Map<int, GlobalKey<ThanosSnapWidgetState>> _snapKeys = {};

  Future<void> _delete(InboxItem i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete this notification?'),
            content: Text('"${i.title}" will be removed from this list.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
            ],
          ),
    );
    if (ok != true || !mounted) return;
    AppHaptics.confirm();
    // Let the dialog close so the card is fully visible before it breaks apart.
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await _snapKeys[i.id]?.currentState?.startSnap();
    if (!mounted) return;
    setState(() => _items = _items.where((x) => x.id != i.id).toList());
    _snapKeys.remove(i.id);
    await NotificationInbox.delete(i.id);
  }

  Future<void> _openReview() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AutoTrackReviewScreen()));
    _load();
  }

  IconData _icon(InboxItem i) {
    final kind = i.kind;
    if (kind.contains('reminder')) return Icons.edit_note_rounded;
    if (kind.contains('friend')) return Icons.person_add_alt_1_rounded;
    if (kind.contains('invitation')) return Icons.mail_rounded;
    if (kind.contains('split')) return Icons.group_rounded;
    if (kind.contains('budget')) return Icons.donut_large_rounded;
    return Icons.notifications_rounded;
  }

  String _when(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (DateUtils.isSameDay(t, now)) return DateFormat('h:mm a').format(t);
    if (diff.inDays < 7) return DateFormat('EEE, h:mm a').format(t);
    return DateFormat('d MMM').format(t);
  }

  String _section(DateTime t) {
    final today = DateUtils.dateOnly(DateTime.now());
    final d = DateUtils.dateOnly(t);
    if (d == today) return 'TODAY';
    if (today.difference(d).inDays == 1) return 'YESTERDAY';
    if (today.difference(d).inDays < 7) return 'THIS WEEK';
    return 'EARLIER';
  }

  @override
  Widget build(BuildContext context) {
    final unread = _items.where((i) => !i.isRead).length;
    final sections = <String, List<InboxItem>>{};
    for (final i in _items) {
      sections.putIfAbsent(_section(i.createdAt), () => []).add(i);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            EspereHeader(
              title: 'Notifications',
              onBack: () => Navigator.pop(context),
              trailing:
                  unread == 0
                      ? null
                      : TextButton(onPressed: () => NotificationInbox.markRead(), child: const Text('Mark all read')),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.dark,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  children: [
                    if (_review > 0) ...[_reviewCard(), const SizedBox(height: 16)],
                    if (_offline && _items.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Icon(Icons.cloud_off_rounded, size: 16, color: AppColors.muted),
                            SizedBox(width: 6),
                            Text('Offline: showing what was saved on this phone', style: AppText.rowSub),
                          ],
                        ),
                      ),
                    if (_loading && _items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 80),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.dark)),
                      )
                    else if (_items.isEmpty && _review == 0)
                      _empty()
                    else
                      for (final e in sections.entries) _sectionCard(e.key, e.value),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewCard() {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: _openReview,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                child: const Icon(Icons.bolt_rounded, size: 22, color: AppColors.dark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_review == 1 ? '1 payment to review' : '$_review payments to review', style: AppText.rowTitle),
                    const Text('Found in your UPI notifications', style: AppText.rowSub),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard(String title, List<InboxItem> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(6, 0, 6, 6), child: Text(title, style: AppText.label)),
          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppShadows.soft,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var k = 0; k < items.length; k++) ...[
                  if (k > 0) const Divider(height: 1, indent: 68, endIndent: 14),
                  _row(items[k]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(InboxItem i) {
    return Dismissible(
      key: ValueKey('n${i.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppColors.dark,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline_rounded, color: AppColors.accent),
      ),
      // Ask first, then play the delete animation (if it is on) instead of sliding away.
      // The card slides back first, then the confirmation and the delete animation run
      // on the card itself (not on the dark swipe background).
      confirmDismiss: (_) async {
        Future.delayed(const Duration(milliseconds: 280), () => _delete(i));
        return false;
      },
      child: ThanosSnapWidget(
        key: _snapKeys.putIfAbsent(i.id, () => GlobalKey<ThanosSnapWidgetState>()),
        child: Material(
          color: i.isRead ? AppColors.card : AppColors.accentSoft,
          child: InkWell(
            onTap: () => _openItem(i),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: i.isRead ? AppColors.surface : AppColors.card,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_icon(i), size: 21, color: AppColors.dark),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                i.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.rowTitle.copyWith(
                                  fontWeight: i.isRead ? FontWeight.w600 : FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(_when(i.createdAt), style: AppText.rowSub.copyWith(fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(i.message, style: AppText.rowSub, maxLines: 3, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (!i.isRead) ...[
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(color: AppColors.dark, shape: BoxShape.circle),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(color: AppColors.card, shape: BoxShape.circle),
            child: const Icon(Icons.notifications_none_rounded, size: 34, color: AppColors.dark),
          ),
          const SizedBox(height: 16),
          const Text('You are all caught up', style: AppText.section),
          const SizedBox(height: 4),
          Text(
            _offline
                ? 'Connect to the internet to check for new ones.'
                : 'Daily reminders and split updates show up here.',
            style: AppText.rowSub,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
