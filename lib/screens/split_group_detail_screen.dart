import '../widgets/morph_text.dart';
import 'dart:async';
import '../theme/motion.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/spring_menu.dart';
import '../widgets/spring_tabs.dart';
import 'group_invite_screen.dart';
import 'group_expense_screen.dart';
import 'group_form_screen.dart';
import '../utils/icon_mapper.dart';
import '../utils/avatar_cache.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import '../widgets/thanos_snap_widget.dart';
import '../services/cache_service.dart';
import '../widgets/user_avatar.dart';
import '../widgets/icon_color_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/espere_back_button.dart';
import '../widgets/espere_swipe_action.dart';
import '../widgets/full_offline_alert.dart';

class SplitGroupDetailScreen extends StatefulWidget {
  final int groupId;
  final String groupName;
  const SplitGroupDetailScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });
  @override
  State<SplitGroupDetailScreen> createState() => _S();
}

class _S extends State<SplitGroupDetailScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _g;
  bool _ld = true;
  bool _isPending = false;
  late TabController _tc;
  int? _myId;
  String _currencySymbol = '₹';
  final Map<int, GlobalKey<ThanosSnapWidgetState>> _expenseSnapKeys = {};
  final Map<int, GlobalKey<ThanosSnapWidgetState>> _memberSnapKeys = {};
  /// Scrolls the card and the lists together (the lists must not have their own
  /// controllers, or the card stops scrolling with them).
  final GlobalKey<NestedScrollViewState> _nestedKey = GlobalKey<NestedScrollViewState>();

  /// Bumped on every rebuild so pushed pages (Settle up, Group settings) redraw too.
  final ValueNotifier<int> _rev = ValueNotifier(0);
  int _subPages = 0;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _rev.value++;
  }

  @override
  void initState() {
    super.initState();
    _tc = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tc.dispose();
    _rev.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cached = await CacheService.getCachedUser();
    if (cached != null) {
      _myId = cached['id'];
      _currencySymbol = CacheService.symbolFor(cached);
    }

    // 1. Try to load full detail from cache first
    final cachedDetail = await CacheService.getCachedSplitGroupDetail(
      widget.groupId,
    );
    if (cachedDetail != null && mounted) {
      setState(() {
        _g = Map<String, dynamic>.from(cachedDetail);
        _g!['recent_expenses'] ??= [];
        _g!['balances'] ??= [];
        _g!['settlement_history'] ??= [];
        _g!['members'] ??= [];
        _ld = false;
        _isPending = false;
      });
    }

    // Fallback to basic group info if no detail cache
    if (_g == null) {
      final cachedGroups = await CacheService.getCachedSplitGroups();
      if (cachedGroups != null) {
        final group = cachedGroups.firstWhere(
          (g) => g['id'] == widget.groupId,
          orElse: () => <String, dynamic>{},
        );
        if (group.isNotEmpty) {
          setState(() {
            _g = Map<String, dynamic>.from(group);
            _g!['recent_expenses'] ??= [];
            _g!['balances'] ??= [];
            _g!['settlement_history'] ??= [];
            _g!['members'] ??= [];
            _ld = false;
          });
        }
      }
    }

    if (_g == null && mounted) {
      setState(() => _ld = true);
    }

    // Fetch profile silently
    final pr = await ApiService.getProfile();
    if (pr.isSuccess && mounted) {
      _myId = pr.data?.id;
      final sym = CacheService.symbolFor({'currency': pr.data?.currency, 'currency_symbol': pr.data?.currencySymbol});
      if (sym != _currencySymbol) setState(() => _currencySymbol = sym);
    }

    // 2. Fetch fresh detail from API silently in background
    if (!ConnectivityService.isOnline) return;
    final r = await ApiService.getSplitGroupDetail(widget.groupId);

    if (!mounted) return;

    setState(() {
      if (r.isSuccess) {
        _g = r.data;
        _isPending = false;
        _ld = false;
        // Save to cache for next time
        CacheService.cacheSplitGroupDetail(widget.groupId, r.data!);
        AvatarCache.warmUp(
          ((r.data!['members'] as List?) ?? const [])
              .map((m) => m is Map ? m['avatar_url']?.toString() : null),
        );
      } else if (r.errors != null && r.errors!['is_pending'] == true) {
        _isPending = true;
        _g = null;
        _ld = false;
      } else {
        _isPending = false;
        // Don't nullify _g here, keep cached data if API fails
        if (_g == null) _ld = false;
      }
    });
    if (!r.isSuccess && !_isPending) {
      _showTopMessage(r.error ?? 'Error', isError: true);
    }
  }

  Future<void> _handleInvitation(String action) async {
    setState(() => _ld = true);
    // We need the invitation ID. The backend returns it in SplitGroupListAPIView as 'id'.
    // However, getSplitGroupDetail doesn't return it if it fails with 403.
    // We might need to find it from the list or have the backend include it in the 403 response.
    // For now, we'll try to find it from a generic invitations list if needed,
    // but better to have backend include it.

    final invRes = await ApiService.getSplitInvitations();
    if (invRes.isSuccess) {
      final invitations = List<Map<String, dynamic>>.from(
        invRes.data!['invitations'],
      );
      final inv = invitations.firstWhere(
        (i) => i['group_id'] == widget.groupId,
        orElse: () => {},
      );
      if (inv.isNotEmpty) {
        final res = await ApiService.handleSplitInvitation(inv['id'], action);
        if (res.isSuccess) {
          if (action == 'accept') {
            _load();
          } else {
            if (mounted) Navigator.pop(context);
          }
          return;
        }
      }
    }

    if (mounted) setState(() => _ld = false);
    _showTopMessage('Failed to $action invitation', isError: true);
  }

  void _showTopMessage(
    String message, {
    bool isError = false,
    BuildContext? ctx,
  }) {
    final overlay = Overlay.of(ctx ?? context);
    final entry = OverlayEntry(
      builder:
          (context) => Positioned(
            top: MediaQuery.of(context).padding.top + 20,
            left: 20,
            right: 20,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppColors.text,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      isError
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_outline,
                      color: AppColors.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), () => entry.remove());
  }

  /// Rename the group, change its icon or who may invite (same screen as New group).
  Future<void> _editGroup() async {
    if (_g == null) return;
    final saved = await GroupFormScreen.open(context, group: {..._g!, 'id': _g!['id'] ?? widget.groupId});
    if (saved) _load();
  }

  void _showLoading(BuildContext ctx) {
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder:
          (context) => const Center(
            child: CircularProgressIndicator(color: AppColors.dark),
          ),
    );
  }

  /// Expense detail: what it was, who paid, everyone's part, your part, Edit / Delete.
  void _showExpenseDetail(Map<String, dynamic> e) {
    final hasSplits = (e['splits'] as List?)?.isNotEmpty == true;
    Map<String, dynamic>? detail;
    bool loading = !hasSplits;
    bool fetchStarted = false;
    final members = List<Map<String, dynamic>>.from(_g?['members'] ?? const []);
    String nameOf(dynamic id) {
      if (id == _myId) return 'You';
      final m = members.where((x) => x['id'] == id).firstOrNull;
      return (m?['display_name'] ?? m?['username'] ?? 'Someone').toString();
    }

    Map<String, dynamic>? memberOf(dynamic id) => members.where((x) => x['id'] == id).firstOrNull;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        if (!fetchStarted && !hasSplits) {
          fetchStarted = true;
          ApiService.getSplitExpenseDetail(widget.groupId, e['id']).then((r) {
            if (!ctx.mounted) return;
            ss(() {
              loading = false;
              if (r.isSuccess) detail = r.data;
            });
          });
        }
        final x = detail ?? e;
        final total = double.tryParse('${x['amount']}') ?? 0;
        final paidBy = x['paid_by'] is Map ? Map<String, dynamic>.from(x['paid_by']) : <String, dynamic>{};
        final payerId = paidBy['id'];
        final splits = List<Map<String, dynamic>>.from(x['splits'] ?? const [])
            .where((sp) => (double.tryParse('${sp['amount']}') ?? 0) > 0.009)
            .toList();
        final mine = splits
            .where((sp) => sp['user_id'] == _myId)
            .fold<double>(0, (sum, sp) => sum + (double.tryParse('${sp['amount']}') ?? 0));
        final type = (x['split_type'] ?? 'equal').toString();
        final dt = DateTime.tryParse('${x['date'] ?? ''}')?.toLocal();
        final creatorId = x['created_by_id'];
        final canEdit = _myId != null && (creatorId == _myId || payerId == _myId);
        final String yourPart;
        if (payerId == _myId) {
          yourPart = total - mine > 0.009 ? 'You get back ${_money(total - mine)}' : 'Only your own share';
        } else if (mine > 0.009) {
          yourPart = 'You owe ${_money(mine)}';
        } else {
          yourPart = 'Not part of it';
        }
        final typeLabel = type == 'equal'
            ? 'split equally · ${splits.isEmpty ? members.where((m) => m['is_accepted'] != false).length : splits.length} people'
            : type == 'percentage'
                ? 'split by %'
                : 'split by amount';

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
                      child: Icon(groupExpenseIcon(e), size: 26, color: AppColors.dark),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text((x['description'] ?? '').toString(),
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text)),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (dt != null) DateFormat('d MMM yyyy, h:mm a').format(dt),
                            if (creatorId != null) 'added by ${nameOf(creatorId)}',
                          ].join(' · '),
                          style: AppText.rowSub,
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(22)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                        Expanded(
                          child: Text(_money(total),
                              style: const TextStyle(
                                  fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1, color: Colors.white)),
                        ),
                        Text(typeLabel, style: const TextStyle(fontSize: 12, color: AppColors.darkMuted)),
                      ]),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: AppColors.darkCard, borderRadius: BorderRadius.circular(16)),
                        child: Row(children: [
                          UserAvatar(
                            initial: (paidBy['initial'] ?? nameOf(payerId)).toString(),
                            avatarUrl: paidBy['avatar_url'] ?? memberOf(payerId)?['avatar_url'],
                            size: 32,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('${nameOf(payerId)} paid the bill',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                          ),
                          Text(yourPart,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.accent)),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 6),
                    child: Text('WHO PAYS WHAT', style: AppText.label),
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.dark)),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(children: [
                        for (var k = 0; k < splits.length; k++) ...[
                          if (k > 0) const Divider(height: 1, indent: 54, endIndent: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: splits[k]['user_id'] == _myId ? AppColors.accent : AppColors.surface,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  ((memberOf(splits[k]['user_id'])?['initial']) ?? nameOf(splits[k]['user_id']).characters.first)
                                      .toString(),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.dark),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text.rich(TextSpan(children: [
                                  TextSpan(text: nameOf(splits[k]['user_id']), style: AppText.rowTitle),
                                  if (splits[k]['user_id'] == payerId)
                                    TextSpan(text: ' · paid', style: AppText.rowSub.copyWith(fontSize: 13)),
                                ])),
                              ),
                              Text(_money(double.tryParse('${splits[k]['amount']}') ?? 0), style: AppText.amount),
                            ]),
                          ),
                        ],
                        if (splits.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(14),
                            child: Text('Split equally between everyone in the group.', style: AppText.rowSub),
                          ),
                      ]),
                    ),
                  const SizedBox(height: 16),
                  if (canEdit) ...[
                    Row(children: [
                      Expanded(
                        child: SpringPress(
                          onTap: () {
                            Navigator.pop(ctx);
                            _addExpense(editData: detail ?? e);
                          },
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(25)),
                            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.edit_rounded, size: 20, color: AppColors.dark),
                              SizedBox(width: 6),
                              Text('Edit', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.dark)),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SpringPress(
                          onTap: () => _confirmDeleteExpense(x['id'] as int, fromDetail: true),
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(25)),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.accent),
                              const SizedBox(width: 6),
                              const Text('Delete',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                            ]),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text('Everyone in the group is told about changes.', style: AppText.rowSub),
                    ),
                  ] else
                    Center(
                      child: Text(
                        'Only ${nameOf(creatorId)} (who added it) or the payer can edit it.',
                        style: AppText.rowSub,
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  void _confirmDeleteExpense(int id, {bool fromDetail = false, GlobalKey<ThanosSnapWidgetState>? snapKey}) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Text(
              'Delete Expense?',
              style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: const Text(
              'This will reverse all balance changes in the group ledger. Are you sure?',
              style: TextStyle(color: AppColors.muted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx); // Close dialog
                  if (fromDetail) {
                    Navigator.pop(context); // Close detail modal
                  }
                  if (snapKey != null) {
                    await snapKey.currentState?.startSnap();
                  } else {
                    _showLoading(context);
                  }
                  final r = await ApiService.deleteSplitExpense(
                    widget.groupId,
                    id,
                  );
                  if (!mounted) return;
                  if (snapKey == null) {
                    Navigator.pop(context); // Close loading
                  }
                  if (r.isSuccess) {
                    AppHaptics.confirm();
                    _showTopMessage('Expense deleted');
                    _load();
                  } else {
                    _showTopMessage(
                      r.error ?? 'Failed to delete',
                      isError: true,
                    );
                  }
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  /// Add (or edit) an expense on its own full screen.
  Future<void> _addExpense({Map<String, dynamic>? editData}) async {
    if (_g == null) return;
    final members = List<Map<String, dynamic>>.from(_g!['members'] ?? const [])
        .where((m) => m['is_accepted'] != false)
        .toList();
    final saved = await GroupExpenseScreen.open(
      context,
      GroupExpenseScreen(
        groupId: widget.groupId,
        groupName: (_g!['name'] ?? widget.groupName).toString(),
        myId: _myId,
        currencySymbol: _currencySymbol,
        members: members,
        editData: editData,
      ),
    );
    if (!saved || !mounted) return;
    _load();
    _tc.animateTo(0);
    final nested = _nestedKey.currentState;
    if (nested != null && nested.innerController.hasClients) {
      nested.innerController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  /// Record a payment between two members (you paid, or someone paid you).
  void _settle(Map<String, dynamic> d) {
    final amount = TextEditingController(
        text: (() {
      final v = double.tryParse('${d['amount']}') ?? 0;
      return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
    })());
    bool saving = false;
    final iPay = d['from_user_id'] == _myId;
    final iGet = d['to_user_id'] == _myId;
    final members = List<Map<String, dynamic>>.from(_g?['members'] ?? const []);
    Map<String, dynamic>? member(dynamic id) => members.where((m) => m['id'] == id).firstOrNull;
    final fromName = iPay ? 'You' : (d['from_user'] ?? '').toString();
    final toName = iGet ? 'you' : (d['to_user'] ?? '').toString();

    Widget face(dynamic id, String name) => Column(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: id == _myId ? AppColors.accent : AppColors.surface,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text((member(id)?['initial'] ?? name.characters.first).toString().toUpperCase(),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.dark)),
          ),
          const SizedBox(height: 6),
          Text(name[0].toUpperCase() + name.substring(1), style: AppText.rowTitle),
        ]);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        final v = double.tryParse(amount.text.trim()) ?? 0;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 14),
              Text(iGet ? 'Mark as received' : 'Mark as paid', style: AppText.section),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                face(d['from_user_id'], fromName),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  child: Icon(Icons.arrow_forward_rounded, size: 26, color: AppColors.muted),
                ),
                face(d['to_user_id'], toName),
              ]),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
                Text(_currencySymbol,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.mutedLight)),
                const SizedBox(width: 4),
                IntrinsicWidth(
                  child: TextField(
                    controller: amount,
                    onChanged: (_) => ss(() {}),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1, color: AppColors.text),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.edit_rounded, size: 18, color: AppColors.mutedLight),
              ]),
              const SizedBox(height: 4),
              Text('Paid part of it? Change the amount.', style: AppText.rowSub),
              const SizedBox(height: 18),
              SpringPress(
                haptic: HapticKind.none,
                onTap: saving || v <= 0
                    ? null
                    : () async {
                        ss(() => saving = true);
                        final r = await ApiService.settleDebt(widget.groupId, {
                          'paid_to_id': d['to_user_id'],
                          'paid_by_id': d['from_user_id'],
                          'amount': v.toStringAsFixed(2),
                        });
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (r.isSuccess) {
                          AppHaptics.confirm();
                          _showTopMessage('Payment recorded');
                          _load();
                        } else {
                          _showTopMessage(r.error ?? 'Error', isError: true);
                        }
                      },
                child: Container(
                  height: 54,
                  decoration: BoxDecoration(
                    color: v > 0 ? AppColors.accent : AppColors.surface,
                    borderRadius: BorderRadius.circular(27),
                  ),
                  alignment: Alignment.center,
                  child: saving
                      ? const SizedBox(
                          width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.dark))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                            iPay
                                ? 'Yes, I paid ${d['to_user']} ${_money(v)}'
                                : iGet
                                    ? 'Yes, ${d['from_user']} paid me ${_money(v)}'
                                    : 'Record ${_money(v)} paid',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.dark),
                          ),
                        ]),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FullOfflineAlert(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              // Fixed Header
              _header(),
              Expanded(
                child:
                    _ld && _g == null
                        ? _buildSkeleton()
                        : _isPending
                        ? _buildPendingMask()
                        : _g == null
                        ? const Center(
                          child: Text(
                            'Error loading group',
                            style: TextStyle(color: AppColors.muted),
                          ),
                        )
                        : NestedScrollView(
                          key: _nestedKey,
                          headerSliverBuilder:
                              (context, innerBoxIsScrolled) => [
                                if (_g != null)
                                  SliverToBoxAdapter(child: _buildHero()),
                                SliverPersistentHeader(
                                  pinned: true,
                                  delegate: _SliverAppBarDelegate(
                                    height: 84,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        12,
                                        16,
                                        12,
                                      ),
                                      child: Container(
                                        child: SpringTabs(
                                          controller: _tc,
                                          labels: const ['Activity', 'Balances', 'Members'],
                                          icons: const [
                                            Icons.receipt_long_rounded,
                                            Icons.account_balance_wallet_rounded,
                                            Icons.group_rounded,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                          body: TabBarView(
                            controller: _tc,
                            children: [_expTab(), _setTab(), _membersTab()],
                          ),
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 4,
      itemBuilder:
          (_, __) => Container(
            height: 80,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.card.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
    );
  }

  Widget _buildPendingMask() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(32),
              boxShadow: AppShadows.elevated,
            ),
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.dark,
                    borderRadius: BorderRadius.circular(AppRadius.xxxl),
                  ),
                  child: Icon(
                    Icons.mail_outline_rounded,
                    size: 44,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Group Invitation',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'You have been invited to join "${widget.groupName}". Accept the invitation to view expenses and settle balances.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.muted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surface,
                          foregroundColor: AppColors.muted,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => _handleInvitation('reject'),
                        child: const Text(
                          'Reject',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.dark,
                          foregroundColor: AppColors.accent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => _handleInvitation('accept'),
                        child: const Text(
                          'Accept',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _isOwner => _myId != null && _g?['created_by_id'] == _myId;
  bool get _canInvite => _isOwner || _g?['members_can_invite'] == true;

  Future<void> _openInvite() async {
    if (_g == null) return;
    if (!_canInvite) {
      _showTopMessage('Only the group admin can invite people to this group.', isError: true);
      return;
    }
    final members = List<Map<String, dynamic>>.from(_g!['members'] ?? const []);
    final me = members.firstWhere((m) => m['id'] == _myId, orElse: () => const {'username': ''});
    final changed = await GroupInviteScreen.open(
      context,
      GroupInviteScreen(
        groupId: widget.groupId,
        groupName: (_g!['name'] ?? widget.groupName).toString(),
        inviteToken: (_g!['invite_token'] ?? '').toString(),
        myUsername: (me['username'] ?? '').toString(),
        members: members,
        pendingInvites: List<Map<String, dynamic>>.from(_g!['pending_invites'] ?? const []),
      ),
    );
    if (changed && mounted) _load();
  }

  /// Members: invite, everyone with their balance and a ⋮ menu, people still to join,
  /// and the group's own settings.
  String _signed(double b) => b.abs() < 0.01 ? _money(0) : '${b > 0 ? '+' : '−'}${_money(b.abs())}';

  /// Members: invite, everyone with their balance, and a way to manage the group.
  Widget _membersTab() {
    final joined = _joined;
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.dark,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        children: [
          if (_canInvite) ...[
            _card([
              InkWell(
                onTap: _openInvite,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 64),
                    child: Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                        child: const Icon(Icons.person_add_rounded, size: 22, color: AppColors.dark),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text('Invite people', style: AppText.rowTitle),
                          SizedBox(height: 1),
                          Text('Link, username, email or friends', style: AppText.rowSub),
                        ]),
                      ),
                      const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.muted),
                    ]),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 8),
          ],
          _card([
            for (final m in joined)
              Builder(builder: (_) {
                final me = m['id'] == _myId;
                final b = double.tryParse('${m['net_balance'] ?? 0}') ?? 0;
                final admin = m['is_creator'] == true || m['id'] == _g!['created_by_id'];
                final user = (m['username'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 60),
                    child: Row(children: [
                      _face(m['id'], _nameOf(m), size: 38),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(me ? 'You' : _nameOf(m), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
                          const SizedBox(height: 1),
                          Text(admin ? 'Admin' : (user.isEmpty ? 'Member' : '@$user'), style: AppText.rowSub),
                        ]),
                      ),
                      Text(_signed(b), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.text)),
                    ]),
                  ),
                );
              }),
          ]),
          SpringPress(
            onTap: _openSettings,
            child: const SizedBox(
              height: 44,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Manage members and group',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.dark)),
                SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.dark),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setCanInvite(bool v) async {
    setState(() => _g!['members_can_invite'] = v);
    AppHaptics.tap();
    final r = await ApiService.updateSplitGroup(widget.groupId, {
      'name': _g!['name'] ?? widget.groupName,
      'color': _g!['color'],
      'icon': _g!['icon'],
      'members_can_invite': v,
    });
    if (!mounted) return;
    if (!r.isSuccess) {
      setState(() => _g!['members_can_invite'] = !v);
      _showTopMessage(r.error ?? 'Error', isError: true);
    }
  }

  /// Group settings page: the group, its members, who can invite, leave or delete.
  Widget _settingsBody() {
    final joined = _joined;
    final waiting = List<Map<String, dynamic>>.from(_g!['members'] ?? const [])
        .where((m) => m['is_accepted'] == false)
        .toList();
    final emails = List<Map<String, dynamic>>.from(_g!['pending_invites'] ?? const []);
    final canInvite = _g!['members_can_invite'] != false;

    Widget rowShell(Widget lead, String title, String sub, Widget? trailing) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Row(children: [
              lead,
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
                  const SizedBox(height: 1),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowSub),
                ]),
              ),
              if (trailing != null) trailing,
            ]),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        // The group
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(22)),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(18)),
              child: Icon(IconMapper.map((_g!['icon'] ?? 'groups').toString()), size: 26, color: AppColors.dark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                MorphText(id: 'group', (_g!['name'] ?? widget.groupName).toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 2),
                MorphText(id: 'group', 
                  '${joined.length} ${joined.length == 1 ? 'member' : 'members'}${_isOwner ? ' · you are admin' : ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.darkMuted),
                ),
              ]),
            ),
            if (_isOwner)
              SpringPress(
                onTap: _editGroup,
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.darkCardRaised, borderRadius: BorderRadius.circular(19)),
                  child: const Text('Edit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
          ]),
        ),

        // Members
        _label(
          'MEMBERS · ${joined.length}',
          trailing: _canInvite
              ? SpringPress(
                  onTap: _openInvite,
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.person_add_rounded, size: 18, color: AppColors.dark),
                    SizedBox(width: 4),
                    Text('Invite', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.dark)),
                  ]),
                )
              : null,
        ),
        _card([
          for (final m in joined)
            Builder(builder: (_) {
              final me = m['id'] == _myId;
              final b = double.tryParse('${m['net_balance'] ?? 0}') ?? 0;
              final admin = m['is_creator'] == true || m['id'] == _g!['created_by_id'];
              final money = b.abs() < 0.01
                  ? 'All settled'
                  : me
                      ? (b > 0 ? 'Gets back ${_money(b)}' : 'Owes ${_money(b.abs())}')
                      : (b > 0 ? 'Gets back ${_money(b)}' : 'Owes ${_money(b.abs())}');
              final items = <SpringMenuItem<String>>[
                if (!me && b < -0.009) const SpringMenuItem('remind', Icons.notifications_rounded, 'Remind'),
                if (me) const SpringMenuItem('leave', Icons.logout_rounded, 'Leave group', destructive: true),
                if (!me && _isOwner) const SpringMenuItem('remove', Icons.person_remove_rounded, 'Remove', destructive: true),
              ];
              final snapKey = _memberSnapKeys.putIfAbsent(m['id'] as int, () => GlobalKey<ThanosSnapWidgetState>());
              return ThanosSnapWidget(
                key: snapKey,
                child: rowShell(
                  _face(m['id'], _nameOf(m), size: 38),
                  me ? 'You' : _nameOf(m),
                  '${admin ? 'Admin · ' : ''}$money',
                  items.isEmpty
                      ? null
                      : SpringMenuButton<String>(
                          tooltip: 'Options for ${_nameOf(m)}',
                          items: items,
                          onSelected: (v) {
                            if (v == 'leave') _leaveGroup();
                            if (v == 'remind') _remind(m['id'], b.abs().toStringAsFixed(2));
                            if (v == 'remove') {
                              if (b.abs() >= 0.01) {
                                _showTopMessage('${_nameOf(m)} must settle up before being removed.', isError: true);
                                return;
                              }
                              _removeMember(m);
                            }
                          },
                        ),
                ),
              );
            }),
        ]),
        const Padding(
          padding: EdgeInsets.fromLTRB(6, 6, 6, 0),
          child: Text('Someone with an open balance can be removed only after they settle up.', style: AppText.rowSub),
        ),

        // Waiting to join
        if (waiting.isNotEmpty || emails.isNotEmpty) ...[
          _label('WAITING TO JOIN'),
          _card([
            for (final m in waiting)
              rowShell(
                _face(m['id'], _nameOf(m), size: 38),
                _nameOf(m),
                'Invited · not joined yet',
                _canInvite
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        _pill('Resend', () => _manageInvite('resend', userId: m['id'] as int?)),
                        IconButton(
                          tooltip: 'Cancel invite',
                          onPressed: () => _manageInvite('cancel', userId: m['id'] as int?),
                          icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted),
                        ),
                      ])
                    : null,
              ),
            for (final e in emails)
              rowShell(
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.mutedLight, width: 2)),
                  child: const Icon(Icons.mail_rounded, size: 18, color: AppColors.muted),
                ),
                (e['email'] ?? '').toString(),
                'Invited by email',
                _canInvite
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        _pill('Resend', () => _manageInvite('resend', email: (e['email'] ?? '').toString())),
                        IconButton(
                          tooltip: 'Cancel invite',
                          onPressed: () => _manageInvite('cancel', email: (e['email'] ?? '').toString()),
                          icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.muted),
                        ),
                      ])
                    : null,
              ),
          ]),
        ],

        // Group switches
        if (_isOwner) ...[
          _label('GROUP'),
          _card([
            InkWell(
              onTap: () => _setCanInvite(!canInvite),
              child: Semantics(
                toggled: canInvite,
                child: rowShell(
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.group_add_rounded, size: 21, color: AppColors.dark),
                  ),
                  'Members can invite',
                  'Otherwise only admins can',
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    width: 46,
                    height: 28,
                    padding: const EdgeInsets.all(3),
                    alignment: canInvite ? Alignment.centerRight : Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: canInvite ? AppColors.dark : const Color(0xFFDADDD5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(color: canInvite ? AppColors.accent : Colors.white, shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ],

        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: SpringPress(
              onTap: _leaveGroup,
              child: Container(
                height: 48,
                decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(24), boxShadow: AppShadows.soft),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.logout_rounded, size: 18, color: AppColors.dark),
                  SizedBox(width: 6),
                  Text('Leave group', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dark)),
                ]),
              ),
            ),
          ),
          if (_isOwner) ...[
            const SizedBox(width: 8),
            Expanded(
              child: SpringPress(
                haptic: HapticKind.warn,
                onTap: _deleteGroup,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(24)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.delete_rounded, size: 18, color: AppColors.accent),
                    const SizedBox(width: 6),
                    const Text('Delete group', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ),
            ),
          ],
        ]),
      ],
    );
  }

  Future<void> _manageInvite(String action, {String? email, int? userId}) async {
    final r = await ApiService.manageSplitInvite(widget.groupId, action, email: email, userId: userId);
    if (!mounted) return;
    _showTopMessage(r.isSuccess ? (r.data ?? 'Done') : (r.error ?? 'Error'), isError: !r.isSuccess);
    if (r.isSuccess) _load();
  }

  String _money(dynamic v) {
    final d = double.tryParse(v.toString()) ?? 0;
    final f = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: d == d.roundToDouble() ? 0 : 2);
    return '$_currencySymbol${f.format(d)}';
  }

  /// "Rahul owes you ₹6,000 · you owe Talib ₹1,500" from the simplified debts.
  String _heroSummary() {
    final debts = List<Map<String, dynamic>>.from(_g?['simplified_debts'] ?? const []);
    final parts = <String>[];
    for (final d in debts) {
      if (d['to_user_id'] == _myId) parts.add('${d['from_user']} owes you ${_money(d['amount'])}');
      if (d['from_user_id'] == _myId) parts.add('you owe ${d['to_user']} ${_money(d['amount'])}');
    }
    if (parts.length > 2) return '${parts.take(2).join(' · ')} · +${parts.length - 2} more';
    return parts.join(' · ');
  }

  List<Map<String, dynamic>> get _joined => List<Map<String, dynamic>>.from(_g?['members'] ?? const [])
      .where((x) => x['is_accepted'] != false)
      .toList()
    ..sort((a, b) => (a['id'] == _myId ? 0 : 1).compareTo(b['id'] == _myId ? 0 : 1));

  Map<String, dynamic>? _member(dynamic id) =>
      List<Map<String, dynamic>>.from(_g?['members'] ?? const []).where((m) => m['id'] == id).firstOrNull;

  String _nameOf(Map<String, dynamic>? m) => (m?['display_name'] ?? m?['username'] ?? '').toString();

  /// "RS" for Rahul Sharma, "T" for Talib.
  String _initials(String name, [String? fallback]) {
    final parts = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    if (parts.isNotEmpty) return parts[0][0].toUpperCase();
    return (fallback ?? '?').toUpperCase();
  }

  /// A round face with initials (or the photo): yours in the app colour, others light.
  Widget _face(dynamic id, String name, {double size = 40, Color? border, Color? bg}) {
    final m = _member(id);
    final url = (m?['avatar_url'] ?? '').toString();
    final inner = border == null ? size : size - 4;
    final text = Text(_initials(name, m?['initial']?.toString()),
        style: TextStyle(fontSize: size * 0.33, fontWeight: FontWeight.w800, color: AppColors.dark));
    final face = ClipOval(
      child: Container(
        width: inner,
        height: inner,
        color: bg ?? (id == _myId ? AppColors.accent : AppColors.surface),
        alignment: Alignment.center,
        child: url.isEmpty
            ? text
            : Image.network(url, width: inner, height: inner, fit: BoxFit.cover, errorBuilder: (_, __, ___) => text),
      ),
    );
    if (border == null) return face;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: border, shape: BoxShape.circle),
      child: face,
    );
  }

  /// Your net in this group, from the simplified debts (falls back to the stored balance).
  double get _myNet {
    final debts = List<Map<String, dynamic>>.from(_g?['simplified_debts'] ?? const []);
    if (debts.isEmpty) return double.tryParse('${_g?['my_net_balance'] ?? 0}') ?? 0;
    double n = 0;
    for (final d in debts) {
      final a = double.tryParse('${d['amount']}') ?? 0;
      if (d['to_user_id'] == _myId) n += a;
      if (d['from_user_id'] == _myId) n -= a;
    }
    return n;
  }

  Widget _header() {
    final count = _joined.length;
    final since = DateTime.tryParse('${_g?['created_at'] ?? ''}');
    final sub = _g == null
        ? ''
        : [
            '$count ${count == 1 ? 'member' : 'members'}',
            if (since != null) 'since ${DateFormat('d MMM').format(since.toLocal())}',
          ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: SizedBox(
        height: 48,
        child: Row(children: [
          EspereBackButton(onPressed: () => Navigator.pop(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              MorphText(id: 'group', (_g?['name'] ?? widget.groupName).toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.text)),
              if (sub.isNotEmpty) Text(sub, style: AppText.rowSub),
            ]),
          ),
          if (_g != null)
            Semantics(
              button: true,
              label: 'Group settings',
              child: SpringPress(
                onTap: _openSettings,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle, boxShadow: AppShadows.accent),
                  child: const Icon(Icons.tune_rounded, color: AppColors.dark, size: 22),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  /// Up to four faces with a dark ring, then "+N".
  Widget _faces() {
    final m = _joined;
    final shown = m.take(m.length > 5 ? 4 : 5).toList();
    final extra = m.length - shown.length;
    return SizedBox(
      height: 32,
      child: Stack(children: [
        for (var i = 0; i < shown.length; i++)
          Positioned(left: i * 24.0, child: _face(shown[i]['id'], _nameOf(shown[i]), size: 32, border: AppColors.dark)),
        if (extra > 0)
          Positioned(
            left: shown.length * 24.0,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.dark, width: 2),
              ),
              alignment: Alignment.center,
              child: Text('+$extra', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.dark)),
            ),
          ),
      ]),
    );
  }

  Widget _darkButton(IconData icon, String label, VoidCallback onTap, {bool primary = false, double height = 50}) =>
      SpringPress(
        onTap: onTap,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: primary ? AppColors.accent : AppColors.darkCardRaised,
            borderRadius: BorderRadius.circular(height / 2),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: primary ? 22 : 20, color: primary ? AppColors.dark : AppColors.accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: primary ? FontWeight.w800 : FontWeight.w700,
                      color: primary ? AppColors.dark : Colors.white)),
            ),
          ]),
        ),
      );

  Widget _buildHero() {
    final bal = _myNet;
    final settled = bal.abs() < 0.01;
    final summary = _heroSummary();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MorphText(id: 'group', 
            settled ? 'Overall, you are settled up' : (bal > 0 ? 'Overall, you get back' : 'Overall, you owe'),
            style: const TextStyle(fontSize: 12, color: AppColors.darkMuted),
          ),
          const SizedBox(height: 2),
          MorphText(id: 'group', 
            settled ? _money(0) : '${bal > 0 ? '+' : '−'}${_money(bal.abs())}',
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1, color: AppColors.accent),
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 2),
            MorphText(id: 'group', summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.darkMuted)),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _faces()),
            if (_canInvite)
              SpringPress(
                onTap: _openInvite,
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: AppColors.darkCardRaised, borderRadius: BorderRadius.circular(17)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.person_add_rounded, size: 18, color: AppColors.accent),
                    const SizedBox(width: 6),
                    const Text('Invite', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _darkButton(Icons.add_rounded, 'Add expense', _addExpense, primary: true)),
            const SizedBox(width: 8),
            Expanded(child: _darkButton(Icons.handshake_rounded, 'Settle up', _openSettle)),
          ]),
        ]),
      ),
    );
  }

  /// A full page on top of the group that redraws whenever the group reloads.
  Future<void> _pushPage(String title, Widget Function() body) async {
    _subPages++;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: SizedBox(
                  height: 48,
                  child: Row(children: [
                    EspereBackButton(onPressed: () => Navigator.pop(ctx)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(title,
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text)),
                    ),
                  ]),
                ),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: _rev,
                  builder: (_, __) => _g == null ? const SizedBox() : body(),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    _subPages--;
  }

  void _openSettle() => _pushPage('Settle up', _settleBody);
  void _openSettings() => _pushPage('Group settings', _settingsBody);

  /// Section label like "YOU PAY".
  Widget _label(String t, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
        child: Row(children: [
          Expanded(child: Text(t, style: AppText.label)),
          if (trailing != null) trailing,
        ]),
      );

  /// White rounded card holding rows split by thin lines.
  Widget _card(List<Widget> rows, {EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 14)}) => Container(
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(22), boxShadow: AppShadows.soft),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, indent: 14, endIndent: 14, color: Color(0xFFF0F1EC)),
            rows[i],
          ],
        ]),
      );

  /// Light pill button used in rows (Remind, Pay, Resend...).
  Widget _pill(String label, VoidCallback? onTap, {IconData? icon, bool dark = false, bool lit = false}) => SpringPress(
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: lit ? AppColors.accent : (dark ? AppColors.dark : AppColors.surface),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: dark && !lit ? Colors.white : AppColors.dark),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: dark && !lit ? Colors.white : AppColors.dark)),
          ]),
        ),
      );

  /// How many expenses make up what [from] owes [to].
  int _expenseCount(dynamic from, dynamic to) {
    final l = List<Map<String, dynamic>>.from(_g?['recent_expenses'] ?? const []);
    return l.where((e) {
      final payer = e['paid_by'] is Map ? e['paid_by']['id'] : null;
      final splits = List<Map<String, dynamic>>.from(e['splits'] ?? const []);
      return payer == to && splits.any((x) => x['user_id'] == from && (double.tryParse('${x['amount']}') ?? 0) > 0);
    }).length;
  }

  String _forExpenses(dynamic from, dynamic to, String fallback) {
    final n = _expenseCount(from, to);
    return n == 0 ? fallback : 'For $n ${n == 1 ? 'expense' : 'expenses'}';
  }

  Future<void> _remind(dynamic userId, dynamic amount) async {
    final r = await ApiService.sendSplitReminder(widget.groupId, {'user_id': userId, 'amount': '$amount'});
    if (!mounted) return;
    if (r.isSuccess) {
      AppHaptics.confirm();
      setState(() => _reminded.add(userId as int));
    }
    _showTopMessage(r.isSuccess ? 'Reminder sent' : (r.error ?? 'Error'), isError: !r.isSuccess);
  }

  /// Empty-state block used by all tabs.
  Widget _emptyState(IconData icon, String title, String subtitle) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.dark,
              borderRadius: BorderRadius.circular(AppRadius.xxl),
            ),
            child: Icon(icon, size: 34, color: AppColors.accent),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, height: 1.4),
          ),
        ],
      ),
    ),
  );

  /// Pill showing an amount: lime = receives, dark = pays.
  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'TODAY';
    if (diff == 1) return 'YESTERDAY';
    return DateFormat(d.year == now.year ? 'd MMMM' : 'd MMM yyyy').format(d).toUpperCase();
  }

  Widget _activityRow({
    required IconData icon,
    bool lit = false,
    required String title,
    required String sub,
    required String tag,
    required String amount,
    bool faded = false,
    VoidCallback? onTap,
    Object? id,
  }) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: lit ? AppColors.accent : AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: MorphIcon(icon, id: id, size: 21, color: AppColors.dark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  MorphText(id: id, title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
                  const SizedBox(height: 1),
                  MorphText(id: id, sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowSub),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                MorphText(id: id, tag, style: AppText.rowSub.copyWith(fontSize: 11)),
                const SizedBox(height: 1),
                MorphText(id: id, amount,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800, color: faded ? AppColors.muted : AppColors.text)),
              ]),
            ]),
          ),
        ),
      );

  Widget _expenseRow(Map<String, dynamic> e) {
    final paidById = e['paid_by'] is Map ? e['paid_by']['id'] : null;
    final canEdit = _myId != null && (e['created_by_id'] == _myId || paidById == _myId);
    final payer = e['paid_by'] is Map ? (e['paid_by']['display_name'] ?? e['paid_by']['username']) : null;
    final paidByMe = paidById != null && paidById == _myId;
    final total = double.tryParse(e['amount'].toString()) ?? 0;
    final splits = List<Map<String, dynamic>>.from(e['splits'] ?? const []);
    final mine = splits
        .where((x) => x['user_id'] == _myId)
        .fold<double>(0, (sum, x) => sum + (double.tryParse(x['amount'].toString()) ?? 0));
    final String tag;
    final double shown;
    if (paidByMe) {
      tag = total - mine > 0.009 ? 'you lent' : 'your own';
      shown = total - mine > 0.009 ? total - mine : total;
    } else if (mine > 0.009) {
      tag = 'you owe';
      shown = mine;
    } else {
      tag = 'not involved';
      shown = total;
    }
    final desc = (e['description'] ?? '').toString();
    Widget row = _activityRow(
      icon: groupExpenseIcon(e),
      title: desc,
      sub: payer == null ? _money(total) : '${paidByMe ? 'You' : payer} paid ${_money(total)}',
      tag: tag,
      amount: _money(shown),
      faded: tag == 'not involved',
      onTap: () => _showExpenseDetail(e),
      id: 'e${e['id']}',
    );
    if (canEdit) {
      row = EspereSwipeAction(
        dismissKey: ValueKey('exp_${e['id']}'),
        direction: DismissDirection.horizontal,
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            _confirmDeleteExpense(e['id'], snapKey: _expenseSnapKeys[e['id']]);
          } else if (direction == DismissDirection.endToStart) {
            _showLoading(context);
            final r = await ApiService.getSplitExpenseDetail(widget.groupId, e['id']);
            if (!mounted) return false;
            Navigator.pop(context);
            if (r.isSuccess) {
              _addExpense(editData: r.data);
            } else {
              _showTopMessage(r.error ?? 'Failed to load expense details', isError: true);
            }
          }
          return false;
        },
        bgIcon: Icons.delete_rounded,
        bgColor: AppColors.dark,
        bgIconColor: AppColors.accent,
        bgAlignment: Alignment.centerLeft,
        secBgIcon: Icons.edit_rounded,
        secBgColor: AppColors.accent,
        secBgIconColor: AppColors.dark,
        secBgAlignment: Alignment.centerRight,
        borderRadius: BorderRadius.zero,
        child: Material(color: AppColors.card, child: row),
      );
    }
    final snapKey = _expenseSnapKeys.putIfAbsent(e['id'], () => GlobalKey<ThanosSnapWidgetState>());
    return ThanosSnapWidget(key: snapKey, child: row);
  }

  Widget _settlementRow(Map<String, dynamic> x) {
    final me = _nameOf(_member(_myId));
    final by = '${x['paid_by'] ?? ''}';
    final to = '${x['paid_to'] ?? ''}';
    final byMe = by == me;
    final toMe = to == me;
    return _activityRow(
      icon: Icons.handshake_rounded,
      lit: true,
      title: byMe ? 'You paid $to' : (toMe ? '$by paid you' : '$by paid $to'),
      sub: 'Settlement',
      tag: byMe ? 'paid' : (toMe ? 'received' : 'settled'),
      amount: _money(x['amount']),
      faded: !byMe && !toMe,
      id: 's${x['id']}',
    );
  }

  /// Activity: expenses and payments together, one card per day.
  Widget _expTab() {
    final items = <({DateTime at, Widget row})>[];
    for (final e in List<Map<String, dynamic>>.from(_g!['recent_expenses'] ?? const [])) {
      final at = DateTime.tryParse('${e['date'] ?? ''}')?.toLocal() ?? DateTime(2000);
      items.add((at: at, row: _expenseRow(e)));
    }
    for (final x in List<Map<String, dynamic>>.from(_g!['settlements'] ?? const [])) {
      final at = DateTime.tryParse('${x['date'] ?? ''}')?.toLocal() ?? DateTime(2000);
      items.add((at: at, row: _settlementRow(x)));
    }
    if (items.isEmpty) {
      return _emptyState(Icons.receipt_long_rounded, 'No expenses yet', 'Tap Add expense to log the first one');
    }
    items.sort((a, b) => b.at.compareTo(a.at));
    final days = <String, List<Widget>>{};
    for (final it in items) {
      days.putIfAbsent(_dayLabel(it.at), () => []).add(it.row);
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.dark,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        children: [
          for (final d in days.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              child: Text(d.key, style: AppText.label),
            ),
            _card(d.value, padding: EdgeInsets.zero),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  void _removeMember(Map<String, dynamic> member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Remove Member'),
            content: Text(
              'Are you sure you want to remove ${member['display_name'] ?? member['username']} from the group?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Remove',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      if (_g == null) return;
      final groupId = _g!['id'] as int;
      final userId = member['id'] as int;

      // Group changes are live: remove on the server first, then play the
      // Thanos snap (respects the Delete Animation setting) and refresh.
      final res = await ApiService.removeGroupMember(groupId, userId);

      if (res.isSuccess) {
        await _memberSnapKeys[userId]?.currentState?.startSnap();
        _showTopMessage('Member removed.');
        _load();
      } else {
        _showTopMessage(res.error ?? 'Failed to remove member.', isError: true);
      }
    }
  }

  void _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete Group'),
            content: const Text(
              'Are you sure you want to permanently delete this group? All expenses and balances will be erased. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      _showLoading(context);
      final r = await ApiService.deleteSplitGroup(widget.groupId);
      if (!mounted) return;
      Navigator.pop(context);
      if (r.isSuccess) {
        AppHaptics.confirm();
        for (var i = 0; i < _subPages; i++) {
          Navigator.pop(context);
        }
        Navigator.pop(context, true);
      } else {
        _showTopMessage(r.error ?? 'Error', isError: true);
      }
    }
  }

  void _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Leave Group'),
            content: const Text(
              'Are you sure you want to leave this group? You can only leave if your balance is completely settled.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  'Leave',
                  style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      _showLoading(context);
      final r = await ApiService.leaveSplitGroup(widget.groupId);
      if (!mounted) return;
      Navigator.pop(context);
      if (r.isSuccess) {
        AppHaptics.confirm();
        for (var i = 0; i < _subPages; i++) {
          Navigator.pop(context);
        }
        Navigator.pop(context, true); // Pop back to groups list and refresh
      } else {
        _showTopMessage(r.error ?? 'Error', isError: true);
      }
    }
  }
  final Set<int> _reminded = {};

  /// Balances: who owes whom, with one action each (Remind / Pay).
  Widget _setTab() {
    final debts = List<Map<String, dynamic>>.from(_g!['simplified_debts'] ?? const []);
    if (debts.isEmpty) {
      return _emptyState(Icons.check_circle_outline_rounded, 'All settled up', 'Nobody owes anyone in this group');
    }
    int rank(Map<String, dynamic> x) => x['to_user_id'] == _myId ? 0 : (x['from_user_id'] == _myId ? 1 : 2);
    debts.sort((a, b) => rank(a).compareTo(rank(b)));
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.dark,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(6, 4, 6, 8),
            child: Text('Simplified: the fewest payments to settle everyone.', style: AppText.rowSub),
          ),
          _card([
            for (final x in debts)
              Builder(builder: (_) {
                final getBack = x['to_user_id'] == _myId;
                final iPay = x['from_user_id'] == _myId;
                final other = getBack ? x['from_user_id'] : (iPay ? x['to_user_id'] : x['from_user_id']);
                final otherName = getBack ? '${x['from_user']}' : (iPay ? '${x['to_user']}' : '${x['from_user']}');
                final text = getBack
                    ? '${x['from_user']} owes you ${_money(x['amount'])}'
                    : iPay
                        ? 'You owe ${x['to_user']} ${_money(x['amount'])}'
                        : '${x['from_user']} owes ${x['to_user']} ${_money(x['amount'])}';
                final sent = _reminded.contains(x['from_user_id']);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 68),
                    child: Row(children: [
                      _face(other, otherName),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(text, style: AppText.rowTitle),
                          const SizedBox(height: 1),
                          Text(
                            getBack && sent
                                ? 'Reminder sent just now'
                                : _forExpenses(x['from_user_id'], x['to_user_id'], getBack || iPay ? 'Open balance' : 'Between them'),
                            style: AppText.rowSub,
                          ),
                        ]),
                      ),
                      if (getBack)
                        _pill(sent ? 'Sent' : 'Remind', sent ? null : () => _remind(x['from_user_id'], x['amount']),
                            lit: sent, icon: sent ? Icons.check_rounded : null),
                      if (iPay) _pill('Pay', () => _settle(x), dark: true),
                    ]),
                  ),
                );
              }),
          ]),
        ],
      ),
    );
  }

  /// Settle up page: what you pay, what you get back.
  Widget _settleBody() {
    final debts = List<Map<String, dynamic>>.from(_g!['simplified_debts'] ?? const []);
    final pay = debts.where((x) => x['from_user_id'] == _myId).toList();
    final get = debts.where((x) => x['to_user_id'] == _myId).toList();
    final others = debts.where((x) => x['from_user_id'] != _myId && x['to_user_id'] != _myId).toList();
    final transfers = debts.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (debts.isEmpty)
          SizedBox(
            height: 320,
            child: _emptyState(Icons.check_circle_outline_rounded, 'All settled up', 'Nobody owes anyone in this group'),
          ),
        if (pay.isNotEmpty) ...[
          _label('YOU PAY'),
          for (final x in pay)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(22)),
              child: Column(children: [
                Row(children: [
                  _face(x['to_user_id'], '${x['to_user']}', bg: AppColors.surface),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Pay ${x['to_user']}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                      Text(_forExpenses(_myId, x['to_user_id'], 'Your open balance'),
                          style: const TextStyle(fontSize: 12, color: AppColors.darkMuted)),
                    ]),
                  ),
                  Text(_money(x['amount']),
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.accent)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _darkButton(Icons.share_rounded, 'Ask UPI ID', () {
                      Share.share('Hi ${x['to_user']}, I owe you ${_money(x['amount'])} for '
                          '"${_g!['name'] ?? widget.groupName}" on Espere. Send me your UPI ID and I will pay you.');
                    }, height: 46),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _darkButton(Icons.done_rounded, 'Mark paid', () => _settle(x), primary: true, height: 46)),
                ]),
              ]),
            ),
        ],
        if (get.isNotEmpty) ...[
          _label('YOU GET BACK'),
          _card([
            for (final x in get)
              Builder(builder: (_) {
                final sent = _reminded.contains(x['from_user_id']);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 68),
                    child: Row(children: [
                      _face(x['from_user_id'], '${x['from_user']}'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text('${x['from_user']} · ${_money(x['amount'])}', style: AppText.rowTitle),
                          const SizedBox(height: 1),
                          Text(
                            sent ? 'Reminder sent just now' : _forExpenses(x['from_user_id'], _myId, 'Owes you'),
                            style: AppText.rowSub,
                          ),
                        ]),
                      ),
                      _pill(sent ? 'Sent' : 'Remind', sent ? null : () => _remind(x['from_user_id'], x['amount']),
                          icon: sent ? Icons.check_rounded : Icons.notifications_rounded, lit: sent),
                    ]),
                  ),
                );
              }),
          ]),
          SpringPress(
            onTap: () => _pickPayer(get),
            child: const SizedBox(
              height: 46,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.payments_rounded, size: 18, color: AppColors.dark),
                SizedBox(width: 6),
                Text('Record a payment someone made to you',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.dark)),
              ]),
            ),
          ),
        ],
        if (others.isNotEmpty) ...[
          _label('BETWEEN OTHERS'),
          _card([
            for (final x in others)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Row(children: [
                    _face(x['from_user_id'], '${x['from_user']}'),
                    const SizedBox(width: 12),
                    Expanded(child: Text('${x['from_user']} pays ${x['to_user']}', style: AppText.rowTitle)),
                    Text(_money(x['amount']), style: AppText.amount.copyWith(fontSize: 14)),
                  ]),
                ),
              ),
          ]),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Payments are simplified: everyone settles in $transfers '
                '${transfers == 1 ? 'transfer' : 'transfers'}. Reminders send a notification.',
                style: AppText.rowSub,
              ),
            ),
          ]),
        ),
      ],
    );
  }

  /// Choose who paid you, then record it.
  void _pickPayer(List<Map<String, dynamic>> get) {
    if (get.length == 1) return _settle(get.first);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 14),
            const Text('Who paid you?', style: AppText.section),
            const SizedBox(height: 10),
            for (final x in get)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.pop(ctx);
                  _settle(x);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  child: Row(children: [
                    _face(x['from_user_id'], '${x['from_user']}'),
                    const SizedBox(width: 12),
                    Expanded(child: Text('${x['from_user']}', style: AppText.rowTitle)),
                    Text(_money(x['amount']), style: AppText.amount.copyWith(fontSize: 14)),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }

}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate({required this.child, required this.height});
  final Widget child;
  final double height;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Exactly [height] tall: a pinned header whose child is shorter or taller than its
    // extent breaks the scroll layout.
    return Container(height: height, color: AppColors.background, child: child);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}

class _UserPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> users;
  final int? selectedId;
  final ValueChanged<Map<String, dynamic>> onSelected;

  const _UserPickerSheet({
    required this.users,
    this.selectedId,
    required this.onSelected,
  });

  @override
  State<_UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends State<_UserPickerSheet> {
  List<Map<String, dynamic>> _filtered = [];
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = List.from(widget.users);
  }

  void _filter(String q) {
    if (q.isEmpty) {
      setState(() => _filtered = List.from(widget.users));
      return;
    }
    final query = q.toLowerCase();
    setState(() {
      _filtered =
          widget.users.where((u) {
            final name =
                (u['display_name'] ?? u['username'] ?? '')
                    .toString()
                    .toLowerCase();
            return name.contains(query);
          }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          16,
          24,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            const Text(
              'Select User',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 12),

            // Search bar
            TextField(
              controller: _searchCtrl,
              onChanged: _filter,
              style: const TextStyle(fontSize: 14, color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Search user...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: AppColors.muted,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 12),

            // User list
            Flexible(
              child:
                  _filtered.isEmpty
                      ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Text(
                            'No user found',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                      : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _filtered.length,
                        itemBuilder: (ctx, i) {
                          final u = _filtered[i];
                          final isSelected = u['id'] == widget.selectedId;

                          return GestureDetector(
                            onTap: () {
                              widget.onSelected(u);
                              Navigator.pop(context);
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    isSelected
                                        ? AppColors.accent.withValues(
                                          alpha: 0.15,
                                        )
                                        : AppColors.surface,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.lg,
                                ),
                                border: Border.all(
                                  color:
                                      isSelected
                                          ? AppColors.accent
                                          : AppColors.border,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // User Avatar
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      shape: BoxShape.circle,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child:
                                          u['avatar_url'] != null
                                              ? CachedAvatarImage(
                                                url: u['avatar_url'],
                                                size: 40,
                                                fallback: const SizedBox(),
                                              )
                                              : Center(
                                                child: Text(
                                                  (u['initial'] ?? '?')
                                                      .toString()
                                                      .toUpperCase(),
                                                  style: const TextStyle(
                                                    color: AppColors.dark,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Name
                                  Expanded(
                                    child: Text(
                                      u['display_name'] ?? u['username'] ?? '',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight:
                                            isSelected
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                        color: AppColors.text,
                                      ),
                                    ),
                                  ),

                                  // Check mark
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      size: 20,
                                      color: AppColors.dark,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
