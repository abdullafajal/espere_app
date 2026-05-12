import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import 'package:share_plus/share_plus.dart';

class SplitGroupDetailScreen extends StatefulWidget {
  final int groupId;
  final String groupName;
  const SplitGroupDetailScreen({super.key, required this.groupId, required this.groupName});
  @override
  State<SplitGroupDetailScreen> createState() => _S();
}

class _S extends State<SplitGroupDetailScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _g;
  bool _ld = true;
  late TabController _tc;

  @override
  void initState() { super.initState(); _tc = TabController(length: 3, vsync: this); _load(); }
  @override
  void dispose() { _tc.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _ld = true);
    final r = await ApiService.getSplitGroupDetail(widget.groupId);
    if (!mounted) return;
    setState(() { _ld = false; if (r.isSuccess) { _g = r.data; } });
  }

  InputDecoration _d(String h) => InputDecoration(hintText: h, filled: true, fillColor: AppColors.surface,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14));

  void _addMember() {
    final ctrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    Timer? debounce;
    showModalBottomSheet(context: context, backgroundColor: AppColors.card, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Center(child: Text('Add Member', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text))),
          const SizedBox(height: 20),
          const Text('Username or Email', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text)),
          const SizedBox(height: 6),
          TextField(controller: ctrl, style: const TextStyle(fontSize: 14, color: AppColors.text), decoration: _d('Enter username or email...'),
            onChanged: (v) { debounce?.cancel(); debounce = Timer(const Duration(milliseconds: 300), () async {
              if (v.trim().length < 2) { ss(() => results = []); return; }
              final r = await ApiService.searchUsers(v.trim());
              if (r.isSuccess) { ss(() => results = r.data!); }
            }); }),
          if (results.isNotEmpty) Container(margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
            child: Column(children: results.map((u) => InkWell(
              onTap: () => ctrl.text = u['username'] as String,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Container(width: 32, height: 32, decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                    child: Center(child: Text(u['initial'] as String, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.dark, fontSize: 12)))),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(u['username'] as String, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
                    Text(u['email'] as String, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                  ]),
                ])),
            )).toList())),
          const SizedBox(height: 8),
          const Text('Enter a registered username or email.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, height: 52, child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.dark),
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              final r = await ApiService.addSplitMember(widget.groupId, ctrl.text.trim());
              if (!ctx.mounted) return; Navigator.pop(ctx);
              if (r.isSuccess) {
                HapticFeedback.mediumImpact();
                _load();
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Member added!')));
              } else {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(r.error ?? 'Error')));
              }
            },
            child: const Text('Add Member', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)))),
        ]))));
  }

  void _editGroup() {
    final nc = TextEditingController(text: widget.groupName);
    showModalBottomSheet(context: context, backgroundColor: AppColors.card, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Edit Group', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text)),
          const SizedBox(height: 20),
          TextField(controller: nc, style: const TextStyle(fontSize: 14, color: AppColors.text), decoration: _d('Group name')),
          const SizedBox(height: 20),
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Row(children: [Icon(Icons.info_outline, size: 14, color: AppColors.muted), SizedBox(width: 6),
              Expanded(child: Text('Group editing is managed from the web app.', style: TextStyle(fontSize: 12, color: AppColors.muted)))])),
        ])));
  }

  void _addExpense() {
    final dc = TextEditingController(), ac = TextEditingController();
    final members = List<Map<String, dynamic>>.from(_g!['members']);
    int? pid; String splitType = 'equal';
    final splitCtrls = <int, TextEditingController>{};
    for (final m in members) { splitCtrls[m['id'] as int] = TextEditingController(); }
    showModalBottomSheet(context: context, backgroundColor: AppColors.card, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Center(child: Text('Add Expense', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text))),
          const SizedBox(height: 20),
          const Text('Description', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text)),
          const SizedBox(height: 6),
          TextField(controller: dc, style: const TextStyle(fontSize: 14, color: AppColors.text), decoration: _d('e.g. Dinner, Groceries')),
          const SizedBox(height: 16),
          const Text('Amount', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text)),
          const SizedBox(height: 6),
          TextField(controller: ac, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(fontSize: 14, color: AppColors.text), decoration: _d('0.00')),
          const SizedBox(height: 16),
          const Text('Paid by', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text)),
          const SizedBox(height: 6),
          Container(padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border, width: 1.5)),
            child: DropdownButtonHideUnderline(child: DropdownButton<int>(value: pid, isExpanded: true, hint: const Text('Select who paid'),
              dropdownColor: AppColors.card, borderRadius: BorderRadius.circular(12),
              items: members.map((m) => DropdownMenuItem<int>(value: m['id'] as int, child: Text(m['username'] as String))).toList(),
              onChanged: (v) => ss(() => pid = v)))),
          const SizedBox(height: 16),
          const Text('Split Type', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text)),
          const SizedBox(height: 6),
          Row(children: ['equal', 'exact', 'percentage'].map((t) => Expanded(child: Padding(
            padding: EdgeInsets.only(right: t != 'percentage' ? 8 : 0),
            child: GestureDetector(onTap: () => ss(() => splitType = t),
              child: Container(height: 40,
                decoration: BoxDecoration(color: splitType == t ? AppColors.accent : AppColors.surface,
                  borderRadius: BorderRadius.circular(10), border: Border.all(color: splitType == t ? AppColors.accent : AppColors.border)),
                child: Center(child: Text(t[0].toUpperCase() + t.substring(1),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: splitType == t ? AppColors.dark : AppColors.muted)))))))).toList()),
          const SizedBox(height: 8),
          // Equal info
          if (splitType == 'equal')
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [const Icon(Icons.info_outline, size: 14, color: AppColors.muted), const SizedBox(width: 6),
                Text('Split equally among ${members.length} members', style: const TextStyle(fontSize: 12, color: AppColors.muted))]))
          else
            // Per-member inputs for exact/percentage
            ...members.map((m) {
              final uid = m['id'] as int;
              final label = splitType == 'percentage' ? '%' : '₹';
              return Padding(padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Container(width: 32, height: 32, decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.person, size: 16, color: AppColors.dark)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(m['username'] as String, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.text))),
                  SizedBox(width: 100, child: TextField(
                    controller: splitCtrls[uid],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 13, color: AppColors.text),
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(hintText: '0', suffixText: label, filled: true, fillColor: AppColors.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  )),
                ]));
            }),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, height: 52, child: ElevatedButton(
            onPressed: () async {
              if (dc.text.trim().isEmpty || ac.text.trim().isEmpty) return;
              final body = <String, dynamic>{'description': dc.text.trim(), 'amount': ac.text.trim(), 'split_type': splitType};
              if (pid != null) body['paid_by_id'] = pid;
              if (splitType != 'equal') {
                body['splits'] = members.map((m) {
                  final uid = m['id'] as int;
                  return {'user_id': uid, 'value': splitCtrls[uid]?.text.trim() ?? '0'};
                }).toList();
              }
              final r = await ApiService.addSplitExpense(widget.groupId, body);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (r.isSuccess) {
                HapticFeedback.mediumImpact();
                _load();
              } else {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(r.error ?? 'Error')));
              }
            }, child: const Text('Add Expense'))),
        ])))));
  }

  void _settle(Map<String, dynamic> d) {
    final ac = TextEditingController(text: d['amount'].toString());
    showModalBottomSheet(context: context, backgroundColor: AppColors.card, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Settle Up', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text)),
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.person, size: 22, color: AppColors.dark)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d['from_user'] as String, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.text)),
                Text('to pay ${d['to_user']}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ])),
              Text('₹${d['amount']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.text)),
            ])),
          const SizedBox(height: 16),
          TextField(controller: ac, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(fontSize: 14, color: AppColors.text), decoration: _d('Settlement amount')),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, height: 52, child: ElevatedButton(
            onPressed: () async {
              final r = await ApiService.settleDebt(widget.groupId, {'paid_to_id': d['to_user_id'], 'amount': ac.text.trim()});
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (r.isSuccess) {
                HapticFeedback.mediumImpact();
                _load();
              }
            }, child: const Text('Mark as Settled'))),
        ])));
  }

  @override
  Widget build(BuildContext context) {
    final bal = double.tryParse(_g?['my_net_balance'] ?? '0') ?? 0;
    return Scaffold(backgroundColor: AppColors.background, body: SafeArea(child: Column(children: [
      // Header: back + title + edit + person_add (matching Django)
      Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 0), child: Row(children: [
        GestureDetector(onTap: () => Navigator.pop(context),
          child: Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), boxShadow: AppShadows.soft),
            child: const Icon(Icons.arrow_back, color: AppColors.text, size: 20))),
        const SizedBox(width: 12),
        Expanded(child: Text(widget.groupName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text), overflow: TextOverflow.ellipsis)),
        // Edit button (dark bg, accent icon — matching Django)
        GestureDetector(onTap: _editGroup,
          child: Container(width: 40, height: 40, margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(12), boxShadow: AppShadows.soft),
            child: const Icon(Icons.edit, color: AppColors.accent, size: 18))),
        // Add member button (accent bg — matching Django)
        GestureDetector(onTap: _g != null ? _addMember : null,
          child: Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12), boxShadow: AppShadows.soft),
            child: const Icon(Icons.person_add, color: AppColors.dark, size: 20))),
      ])),
      // Balance card
      if (_g != null) Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: Container(
        width: double.infinity, padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1A1A1A), Color(0xFF333333)]),
          borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.elevated, border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Your Net Balance', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0x99FFFFFF))),
          const SizedBox(height: 4),
          Text('${bal > 0 ? "+" : ""}₹${bal.abs().toStringAsFixed(2)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.accent)),
          const SizedBox(height: 12),
          Row(children: [
            _sc(Icons.arrow_upward, 'Paid: ₹0'), const SizedBox(width: 12), _sc(Icons.pie_chart, 'Share: ₹0'),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: GestureDetector(onTap: _addExpense,
              child: Container(height: 44, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add, size: 18, color: AppColors.accent), SizedBox(width: 6),
                  Text('Expense', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white))])))),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(onTap: () => _tc.animateTo(2),
              child: Container(height: 44, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.handshake, size: 18, color: AppColors.accent), SizedBox(width: 6),
                  Text('Settle Up', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white))])))),
          ]),
        ]))),
      // Tabs
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Container(
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.soft), padding: const EdgeInsets.all(3),
        child: TabBar(controller: _tc,
          indicator: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: AppColors.text, unselectedLabelColor: AppColors.muted,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), dividerHeight: 0,
          tabs: const [Tab(text: 'Expenses'), Tab(text: 'Balances'), Tab(text: 'Settle Up')]))),
      Expanded(child: _ld ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
        : TabBarView(controller: _tc, children: [_expTab(), _balTab(), _setTab()])),
    ])));
  }

  Widget _sc(IconData i, String t) => Row(children: [
    Container(width: 24, height: 24, decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.2), shape: BoxShape.circle),
      child: Icon(i, size: 14, color: AppColors.accent)),
    const SizedBox(width: 6), Text(t, style: const TextStyle(fontSize: 12, color: Color(0xB3FFFFFF)))]);

  Widget _expTab() {
    final l = List<Map<String, dynamic>>.from(_g!['recent_expenses'] ?? []);
    if (l.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.receipt_long, size: 48, color: AppColors.muted), const SizedBox(height: 8),
      const Text('No expenses yet. Start adding!', style: TextStyle(color: AppColors.muted))]));
    return RefreshIndicator(onRefresh: _load, color: AppColors.accent, child: ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80), itemCount: l.length,
      itemBuilder: (_, i) { final e = l[i]; final dt = DateTime.tryParse(e['date'] ?? ''); final f = dt != null ? DateFormat('MMM d').format(dt.toLocal()) : '';
        return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.receipt_long, size: 22, color: AppColors.dark)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e['description'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text.rich(TextSpan(children: [const TextSpan(text: 'Paid by '), TextSpan(text: '${e['paid_by']}', style: const TextStyle(fontWeight: FontWeight.w600)), TextSpan(text: ' on $f')]),
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ])),
            Text('₹${e['amount']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text)),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
          ])); }));
  }

  Widget _balTab() {
    final m = List<Map<String, dynamic>>.from(_g!['members'] ?? []);
    return RefreshIndicator(onRefresh: _load, color: AppColors.accent, child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80), children: [
        const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Text('Member Balances', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text))),
        ...m.map((x) { final b = double.tryParse(x['net_balance'].toString()) ?? 0;
          return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
            child: Row(children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.person, size: 22, color: AppColors.dark)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(x['username'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
                if (b > 0) Text('Gets back ₹${b.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success))
                else if (b < 0) Text('To pay ₹${b.abs().toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.error))
                else const Text('Settled up', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ])),
            ])); }),
      ]));
  }

  Widget _setTab() {
    final d = List<Map<String, dynamic>>.from(_g!['simplified_debts'] ?? []);
    final s = List<Map<String, dynamic>>.from(_g!['settlements'] ?? []);
    return RefreshIndicator(onRefresh: _load, color: AppColors.accent, child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80), children: [
        const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Text('Suggested Settlements', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text))),
        if (d.isEmpty) Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(children: [const Icon(Icons.sentiment_satisfied, size: 48, color: AppColors.muted), const SizedBox(height: 8),
            const Text('All members are settled up!', style: TextStyle(color: AppColors.muted))])))
        else ...d.map((x) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
          child: Column(children: [
            Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.person, size: 20, color: AppColors.dark)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(x['from_user'] as String, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.text)),
                Text('to pay ${x['to_user']}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ])),
              Text('₹${x['amount']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.text)),
            ]),
            const SizedBox(height: 10), const Divider(color: AppColors.border, height: 1), const SizedBox(height: 10),
            Row(children: [
              Expanded(child: ElevatedButton(
                onPressed: () async {
                  final msg = "Hi ${x['from_user']},\n\nJust a quick reminder regarding your balance of ₹${x['amount']} in '${widget.groupName}'.\n\nPlease settle up when you can!";
                  await Share.share(msg, subject: "Friendly Reminder: Action needed in '${widget.groupName}'");
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Share', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.text)))),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton(
                onPressed: () async {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sending reminder...')));
                  final res = await ApiService.sendSplitReminder(widget.groupId, {'user_id': x['from_user_id'], 'amount': x['amount']});
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.isSuccess ? 'Reminder sent!' : (res.error ?? 'Error'))));
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Remind', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.accent)))),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton(
                onPressed: () => _settle(x),
                style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Settle', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)))),
            ]),
          ]))),
        if (s.isNotEmpty) ...[const SizedBox(height: 16),
          const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Text('Settlement History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.text))),
          ...s.map((x) { final dt = DateTime.tryParse(x['date'] ?? ''); final f = dt != null ? DateFormat('MMM d, yyyy').format(dt.toLocal()) : '';
            return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
              child: Row(children: [
                Container(width: 36, height: 36, decoration: const BoxDecoration(color: AppColors.successLight, shape: BoxShape.circle),
                  child: const Icon(Icons.handshake, size: 18, color: AppColors.success)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${x['paid_by']} → ${x['paid_to']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
                  Text(f, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ])),
                Text('₹${x['amount']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.success)),
              ])); }),
        ],
      ]));
  }
}
