import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';
import '../services/cache_service.dart';
import '../widgets/user_avatar.dart';
import '../widgets/espere_input.dart';
import 'package:share_plus/share_plus.dart';

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

  @override
  void initState() {
    super.initState();
    _tc = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _ld = true);
    
    // Fetch profile to know who "I" am
    final pr = await ApiService.getProfile();
    if (pr.isSuccess) {
      _myId = pr.data?.id;
    }

    final r = await ApiService.getSplitGroupDetail(widget.groupId);
    if (!mounted) return;
    setState(() {
      _ld = false;
      if (r.isSuccess) {
        _g = r.data;
        _isPending = false;
      } else if (r.errors != null && r.errors!['is_pending'] == true) {
        _isPending = true;
        _g = null;
      } else {
        _isPending = false;
        _g = null;
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
      final invitations = List<Map<String, dynamic>>.from(invRes.data!['invitations']);
      final inv = invitations.firstWhere((i) => i['group_id'] == widget.groupId, orElse: () => {});
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

  void _showTopMessage(String message, {bool isError = false, BuildContext? ctx}) {
    final overlay = Overlay.of(ctx ?? context);
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 20,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
                  isError ? Icons.error_outline : Icons.check_circle_outline,
                  color: AppColors.accent,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
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

  InputDecoration _inputDeco(String h) => InputDecoration(
    hintText: h,
    hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.border, width: 1.5),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.border, width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.dark, width: 1.5),
    ),
  );

  void _addMember() async {
    List<Map<String, dynamic>> friends = [];
    List<int> selectedIds = [];
    bool loadingFriends = true;
    final emailCtrl = TextEditingController();
    bool isInviting = false;
    String? emailError;

    final res = await ApiService.getFriends();
    if (res.isSuccess) {
      final allFriends = List<Map<String, dynamic>>.from(res.data!['friends']);
      final existingIds = (_g!['members'] as List).map((m) => m['id'] as int).toSet();
      friends = allFriends.where((f) => !existingIds.contains(f['id'])).toList();
    }
    loadingFriends = false;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Container(
          padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.muted.withOpacity(0.2), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 24),
                const Center(
                  child: Text('Add Members', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text)),
                ),
                const SizedBox(height: 32),
                const Text('Invite by Email', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.muted)),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: emailCtrl,
                        onChanged: (v) { if (emailError != null) ss(() => emailError = null); },
                        decoration: _inputDeco('Friend\'s email address...').copyWith(errorText: emailError),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: isInviting ? null : () async {
                        final email = emailCtrl.text.trim();
                        if (email.isEmpty) {
                          ss(() => emailError = 'Please enter an email');
                          return;
                        }
                        if (!email.contains('@')) {
                          ss(() => emailError = 'Invalid email format');
                          return;
                        }
                        
                        ss(() => isInviting = true);
                        final r = await ApiService.addSplitMember(widget.groupId, identifier: email);
                        ss(() => isInviting = false);
                        
                        if (r.isSuccess) {
                          emailCtrl.clear();
                          HapticFeedback.mediumImpact();
                          _showTopMessage('Invitation sent to $email');
                        } else {
                          _showTopMessage(r.error ?? 'Error', isError: true);
                        }
                      },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.dark,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: isInviting 
                          ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2)))
                          : const Icon(Icons.send, color: AppColors.accent, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                const Text('Select Friends', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.muted)),
                const SizedBox(height: 12),
                if (loadingFriends)
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppColors.accent)))
                else if (friends.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    width: double.infinity,
                    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                    child: const Text('No other friends to add.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  )
                else ...[
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.3),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: friends.length,
                      itemBuilder: (ctx, i) {
                        final f = friends[i];
                        final fid = f['id'] as int;
                        final isSelected = selectedIds.contains(fid);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.accent.withOpacity(0.05) : AppColors.card,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isSelected ? AppColors.accent : AppColors.border),
                            ),
                            child: CheckboxListTile(
                              value: isSelected,
                              onChanged: (v) => ss(() { if (v!) selectedIds.add(fid); else selectedIds.remove(fid); }),
                              title: Text(f['display_name'] ?? f['username'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
                              subtitle: Text(f['email'] ?? '', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                              secondary: UserAvatar(initial: f['initial'] ?? '?', avatarUrl: f['avatar_url'], size: 36),
                              activeColor: AppColors.accent,
                              checkColor: AppColors.dark,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.dark,
                      disabledBackgroundColor: AppColors.accent.withOpacity(0.3),
                      disabledForegroundColor: AppColors.dark.withOpacity(0.3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: selectedIds.isEmpty ? null : () async {
                      bool allSuccess = true;
                      for (final id in selectedIds) {
                        final r = await ApiService.addSplitMember(widget.groupId, identifier: id.toString());
                        if (!r.isSuccess) allSuccess = false;
                      }
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (allSuccess) {
                        HapticFeedback.heavyImpact();
                        _load();
                        _showTopMessage('Members added!');
                      } else {
                        _showTopMessage('Some members could not be added.', isError: true);
                      }
                    },
                    child: Text('Add ${selectedIds.length} Selected', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _editGroup() {
    final nc = TextEditingController(text: widget.groupName);
    bool isSaving = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Container(
          padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.muted.withOpacity(0.2), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 24),
              const Center(
                child: Text('Edit Group', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text)),
              ),
              const SizedBox(height: 32),
              const Text('Group Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.muted)),
              const SizedBox(height: 8),
              TextField(
                controller: nc,
                autofocus: true,
                style: const TextStyle(fontSize: 15, color: AppColors.text),
                decoration: _inputDeco('Group name'),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.dark, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: isSaving ? null : () async {
                    if (nc.text.trim().isEmpty) return;
                    ss(() => isSaving = true);
                    final r = await ApiService.updateSplitGroup(widget.groupId, {'name': nc.text.trim()});
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (r.isSuccess) {
                      HapticFeedback.heavyImpact();
                      _load();
                    }
                  },
                  child: isSaving
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
                      : const Text('Save Changes', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLoading(BuildContext ctx) {
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
    );
  }

  void _showExpenseDetail(Map<String, dynamic> e) async {
    _showLoading(context);
    final r = await ApiService.getSplitExpenseDetail(widget.groupId, e['id']);
    if (!mounted) return;
    Navigator.pop(context); // Close loading

    if (!r.isSuccess) {
      _showTopMessage(r.error ?? 'Failed to load details', isError: true);
      return;
    }

    final detail = r.data!;
    final splits = List<Map<String, dynamic>>.from(detail['splits'] ?? []);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.muted.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail['description'] ?? '',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Paid by ${detail['paid_by']['display_name']} • ${DateFormat('MMM d, yyyy').format(DateTime.parse(detail['date']).toLocal())}',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₹${detail['amount']}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.text),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const Text(
                'Splits',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              ...splits.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                     UserAvatar(
                       initial: s['display_name'],
                       size: 28,
                       borderRadius: 8,
                     ),
                     const SizedBox(width: 12),
                     Expanded(
                       child: Text(s['display_name'], style: const TextStyle(fontSize: 14, color: AppColors.text)),
                     ),
                     Text('₹${s['amount']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
                  ],
                ),
              )).toList(),
              if (_myId == detail['created_by_id']) ...[
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.text,
                          foregroundColor: AppColors.accent,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _addExpense(editData: detail);
                        },
                        child: const Text('Edit', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.dark,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => _confirmDeleteExpense(detail['id']),
                        child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteExpense(int id) {
     showDialog(
       context: context,
       builder: (ctx) => AlertDialog(
         backgroundColor: AppColors.card,
         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
         title: const Text('Delete Expense?', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
         content: const Text('This will reverse all balance changes in the group ledger. Are you sure?', style: TextStyle(color: AppColors.muted)),
         actions: [
           TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.muted))),
           TextButton(
             onPressed: () async {
               Navigator.pop(ctx); // Close dialog
               Navigator.pop(context); // Close detail modal
               _showLoading(context);
               final r = await ApiService.deleteSplitExpense(widget.groupId, id);
               if (!mounted) return;
               Navigator.pop(context); // Close loading
               if (r.isSuccess) {
                 HapticFeedback.heavyImpact();
                 _showTopMessage('Expense deleted');
                 _load();
               } else {
                 _showTopMessage(r.error ?? 'Failed to delete', isError: true);
               }
             },
             child: const Text('Delete', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
           ),
         ],
       ),
     );
  }

  void _addExpense({Map<String, dynamic>? editData}) {
    final dc = TextEditingController(text: editData?['description']);
    final ac = TextEditingController(text: editData?['amount']);
    final members = List<Map<String, dynamic>>.from(_g!['members']);
    String splitType = editData?['split_type'] ?? 'equal';
    bool isSaving = false;
    final splitCtrls = <int, TextEditingController>{};
    for (final m in members) {
      splitCtrls[m['id'] as int] = TextEditingController();
    }

    if (editData != null && editData['splits'] != null) {
      final oldSplits = List<Map<String, dynamic>>.from(editData['splits']);
      for (var os in oldSplits) {
        final uid = os['user_id'] as int;
        if (splitCtrls.containsKey(uid)) {
          splitCtrls[uid]!.text = os['value'].toString();
        }
      }
    }

    String? amountErr;
    String? descErr;
    String? splitErr;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Container(
          padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.muted.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(editData != null ? 'Edit Expense' : 'Add Expense', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text)),
                ),
                const SizedBox(height: 32),
                // Amount
                EspereInput(
                  label: 'Amount',
                  hint: '0.00',
                  controller: ac,
                  prefixText: '₹',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: editData == null,
                  errorText: amountErr,
                  onChanged: (_) { if (amountErr != null) ss(() => amountErr = null); },
                ),
                const SizedBox(height: 16),
                // Description
                EspereInput(
                  label: 'Description',
                  hint: 'What was this for?',
                  controller: dc,
                  errorText: descErr,
                  onChanged: (_) { if (descErr != null) ss(() => descErr = null); },
                ),
                const SizedBox(height: 24),
                const Text(
                  'Split Between',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                Row(
                  children: ['equal', 'exact', 'percentage'].map((t) {
                    final isSel = splitType == t;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: t != 'percentage' ? 8 : 0),
                        child: GestureDetector(
                          onTap: () => ss(() => splitType = t),
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: isSel ? AppColors.accent : AppColors.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: isSel ? AppColors.accent : AppColors.border),
                              boxShadow: isSel ? [BoxShadow(color: AppColors.accent.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))] : null,
                            ),
                            child: Center(
                              child: Text(
                                t[0].toUpperCase() + t.substring(1),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isSel ? AppColors.dark : AppColors.muted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                if (splitType == 'equal')
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.group_outlined, size: 20, color: AppColors.accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'This will be split equally among all ${members.length} members.',
                            style: const TextStyle(fontSize: 13, color: AppColors.muted),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...members.map((m) {
                    final uid = m['id'] as int;
                    final label = splitType == 'percentage' ? '%' : '₹';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            UserAvatar(initial: m['initial'] ?? '?', avatarUrl: m['avatar_url'], size: 36),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                m['display_name'] ?? m['username'] as String,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text),
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: TextField(
                                controller: splitCtrls[uid],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text),
                                decoration: InputDecoration(
                                  hintText: '0',
                                  hintStyle: const TextStyle(color: AppColors.muted),
                                  suffixText: ' $label',
                                  suffixStyle: const TextStyle(color: AppColors.muted, fontSize: 12),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onChanged: (_) { if (splitErr != null) ss(() => splitErr = null); },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                
                if (splitErr != null)
                  Container(
                    margin: const EdgeInsets.only(top: 24),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.text,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppShadows.soft,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 18, color: AppColors.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            splitErr!,
                            style: const TextStyle(fontSize: 13, color: AppColors.accent, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.dark,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: isSaving ? null : () async {
                      final amountStr = ac.text.trim();
                      final descStr = dc.text.trim();
                      bool hasErr = false;

                      if (descStr.isEmpty) {
                        ss(() => descErr = 'Required');
                        hasErr = true;
                      }
                      if (amountStr.isEmpty) {
                        ss(() => amountErr = 'Required');
                        hasErr = true;
                      }
                      if (hasErr) return;

                      final totalAmount = double.tryParse(amountStr) ?? 0;

                      if (splitType == 'exact') {
                        double sum = 0;
                        for (var m in members) {
                          final uid = m['id'] as int;
                          final val = double.tryParse(splitCtrls[uid]?.text.trim() ?? '') ?? 0;
                          sum += val;
                        }
                        if ((sum - totalAmount).abs() > 0.01) {
                          ss(() => splitErr = 'Total split (₹${sum.toStringAsFixed(2)}) must match expense (₹${totalAmount.toStringAsFixed(2)})');
                          return;
                        }
                      } else if (splitType == 'percentage') {
                        double sum = 0;
                        for (var m in members) {
                          final uid = m['id'] as int;
                          final val = double.tryParse(splitCtrls[uid]?.text.trim() ?? '') ?? 0;
                          sum += val;
                        }
                        if ((sum - 100).abs() > 0.01) {
                          ss(() => splitErr = 'Total percentage (${sum.toStringAsFixed(0)}%) must equal 100%');
                          return;
                        }
                      }

                      ss(() => splitErr = null);
                      ss(() => isSaving = true);
                      final body = <String, dynamic>{
                        'description': descStr,
                        'amount': amountStr,
                        'split_type': splitType,
                      };
                      if (splitType != 'equal') {
                        body['splits'] = members.map((m) {
                          final uid = m['id'] as int;
                          return {'user_id': uid, 'value': splitCtrls[uid]?.text.trim() ?? '0'};
                        }).toList();
                      }

                      ApiResult r;
                      if (editData != null) {
                         r = await ApiService.updateSplitExpense(widget.groupId, editData['id'], body);
                      } else {
                         r = await ApiService.addSplitExpense(widget.groupId, body);
                      }

                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (r.isSuccess) {
                        HapticFeedback.heavyImpact();
                        _load();
                      } else {
                        _showTopMessage(r.error ?? 'Error', isError: true);
                      }
                    },
                    child: isSaving
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
                        : Text(editData != null ? 'Update Expense' : 'Add Expense', style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _settle(Map<String, dynamic> d) {
    final ac = TextEditingController(text: d['amount'].toString());
    bool isConfirmed = false;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Container(
          padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.muted.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text('Settle Up', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text)),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppShadows.soft,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person, color: AppColors.accent, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d['from_user'] as String,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text),
                          ),
                          Text(
                            'to pay ${d['to_user']}',
                            style: const TextStyle(fontSize: 12, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${d['amount']}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.text),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              EspereInput(
                label: 'Amount Paid',
                hint: '0.00',
                controller: ac,
                prefixText: '₹',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: CheckboxListTile(
                  value: isConfirmed,
                  onChanged: (v) => ss(() => isConfirmed = v ?? false),
                  title: const Text(
                    'Both parties have confirmed this payment',
                    style: TextStyle(fontSize: 12, color: AppColors.text, fontWeight: FontWeight.w500),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppColors.accent,
                  checkColor: AppColors.dark,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.dark,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: (!isConfirmed || isSaving)
                      ? null
                      : () async {
                          ss(() => isSaving = true);
                          final body = {
                            'paid_to_id': d['to_user_id'],
                            'amount': ac.text.trim(),
                          };

                          if (ConnectivityService.isOnline) {
                            final r = await ApiService.settleDebt(widget.groupId, body);
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            if (r.isSuccess) {
                              HapticFeedback.heavyImpact();
                              _load();
                            } else {
                              _showTopMessage(r.error ?? 'Error', isError: true);
                            }
                          } else {
                            await SyncService.queueOperation(action: 'create', entity: 'split_settle', data: body, entityId: widget.groupId);
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            HapticFeedback.heavyImpact();
                            _showTopMessage('Settlement queued offline.');
                          }
                        },
                  child: isSaving
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
                      : const Text('Confirm Settlement', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final bal = double.tryParse(_g?['my_net_balance'] ?? '0') ?? 0;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Fixed Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: AppShadows.soft,
                      ),
                      child: const Icon(Icons.arrow_back, color: AppColors.text, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.groupName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_g != null && _g!['created_by_id'] == _myId)
                    GestureDetector(
                      onTap: _editGroup,
                      child: Container(
                        width: 40,
                        height: 40,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: AppColors.dark,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: AppShadows.soft,
                        ),
                        child: const Icon(Icons.edit, color: AppColors.accent, size: 18),
                      ),
                    ),
                  GestureDetector(
                    onTap: _g != null ? _addMember : null,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: AppShadows.soft,
                      ),
                      child: const Icon(Icons.person_add, color: AppColors.dark, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _ld 
                  ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                  : _isPending 
                      ? _buildPendingMask()
                      : _g == null
                          ? const Center(child: Text('Error loading group', style: TextStyle(color: AppColors.muted)))
                          : NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  if (_g != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppColors.text,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: AppShadows.elevated,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    gradient: RadialGradient(
                                      center: Alignment.topRight,
                                      radius: 0.6,
                                      colors: [AppColors.accent.withValues(alpha: 0.04), Colors.transparent],
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Your Net Balance', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0x99FFFFFF))),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${bal > 0 ? "+" : ""}₹${bal.abs().toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.accent),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        _sc(Icons.arrow_upward, 'Paid: ₹0'),
                                        const SizedBox(width: 12),
                                        _sc(Icons.pie_chart, 'Share: ₹0'),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: _addExpense,
                                            child: Container(
                                              height: 44,
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(16),
                                              ),
                                              child: const Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.add, size: 18, color: AppColors.accent),
                                                  SizedBox(width: 6),
                                                  Text('Expense', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () => _tc.animateTo(2),
                                            child: Container(
                                              height: 44,
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(16),
                                              ),
                                              child: const Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.handshake, size: 18, color: AppColors.accent),
                                                  SizedBox(width: 6),
                                                  Text('Settle Up', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                                                ],
                                              ),
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
                        ),
                      ),
                    ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                height: 64,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: AppShadows.soft,
                    ),
                    padding: const EdgeInsets.all(3),
                    child: TabBar(
                      controller: _tc,
                      indicator: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: AppColors.text,
                      unselectedLabelColor: AppColors.muted,
                      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      dividerHeight: 0,
                      tabs: const [Tab(text: 'Expenses'), Tab(text: 'Balances'), Tab(text: 'Settle Up')],
                    ),
                    ),
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tc,
              children: [_expTab(), _balTab(), _setTab()],
            ),
          ),
        ),
      ],
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
                const Icon(Icons.mail_outline, size: 64, color: AppColors.accent),
                const SizedBox(height: 24),
                Text(
                  'Group Invitation',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.text),
                ),
                const SizedBox(height: 12),
                Text(
                  'You have been invited to join "${widget.groupName}". Accept the invitation to view expenses and settle balances.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: AppColors.muted, height: 1.5),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => _handleInvitation('reject'),
                        child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.dark,
                          foregroundColor: AppColors.accent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => _handleInvitation('accept'),
                        child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _sc(IconData i, String t) => Row(
    children: [
      Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(i, size: 14, color: AppColors.accent),
      ),
      const SizedBox(width: 6),
      Text(t, style: const TextStyle(fontSize: 12, color: Color(0xB3FFFFFF))),
    ],
  );

  Widget _expTab() {
    final l = List<Map<String, dynamic>>.from(_g!['recent_expenses'] ?? []);
    if (l.isEmpty)
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.receipt_long, size: 48, color: AppColors.muted),
            const SizedBox(height: 8),
            const Text(
              'No expenses yet. Start adding!',
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      );
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        itemCount: l.length,
        itemBuilder: (_, i) {
          final e = l[i];
          final dt = DateTime.tryParse(e['date'] ?? '');
          final f = dt != null ? DateFormat('MMM d').format(dt.toLocal()) : '';
          return GestureDetector(
            onTap: () => _showExpenseDetail(e),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppShadows.card,
              ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.receipt_long,
                    size: 22,
                    color: AppColors.dark,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e['description'] ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        f,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '₹${e['amount']}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text,
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

  Widget _balTab() {
    final m = List<Map<String, dynamic>>.from(_g!['members'] ?? []);
    final allSettled = m.every(
      (x) => (double.tryParse(x['net_balance'].toString()) ?? 0).abs() < 0.01,
    );

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  'Member Balances',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...m.map((x) {
            final b = double.tryParse(x['net_balance'].toString()) ?? 0;
            final isSettled = b.abs() < 0.01;
            final isOwner = _myId != null && _myId == _g!['created_by_id'];
            final isSelf = _myId != null && _myId == x['id'];
            final canRemove = isSettled && (isOwner || isSelf);

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppShadows.card,
              ),
              child: Row(
                children: [
                  UserAvatar(
                    initial: x['initial'] ?? '?',
                    avatarUrl: x['avatar_url'],
                    size: 44,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          x['display_name'] ?? x['username'] as String,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        if (b > 0)
                          Text(
                            'Gets back ₹${b.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.text,
                            ),
                          )
                        else if (b < 0)
                          Text(
                            'To pay ₹${b.abs().toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.text,
                            ),
                          )
                        else
                          const Text(
                            'Settled up',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Member specific actions
                  if (canRemove)
                    IconButton(
                      onPressed: () => _removeMember(x),
                      icon: const Icon(
                        Icons.person_remove_outlined,
                        size: 18,
                        color: AppColors.muted,
                      ),
                    )
                  else if (!isSettled)
                     Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: AppColors.muted.withOpacity(0.3),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _editMember(Map<String, dynamic> member) {
    // Logic for editing a member (e.g. changing display name or role)
    _showTopMessage('Member details can be edited from their profile.');
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
      // API call to remove member
      _showTopMessage('Member removed.');
      _load();
    }
  }

  void _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete Group'),
            content: const Text(
              'This will permanently delete the group and all its data. This action cannot be undone.',
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
      final r = await ApiService.deleteSplitGroup(widget.groupId);
      if (r.isSuccess) {
        HapticFeedback.heavyImpact();
        Navigator.pop(context); // Go back to groups list
        _showTopMessage('Group deleted.');
      } else {
        _showTopMessage(r.error ?? 'Failed to delete', isError: true);
      }
    }
  }

  Widget _setTab() {
    final d = List<Map<String, dynamic>>.from(_g!['simplified_debts'] ?? []);
    final s = List<Map<String, dynamic>>.from(_g!['settlements'] ?? []);
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Suggested Settlements',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.text,
              ),
            ),
          ),
          if (d.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    const Icon(
                      Icons.sentiment_satisfied,
                      size: 48,
                      color: AppColors.muted,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'All members are settled up!',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            )
          else
            ...d.map(
              (x) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppShadows.card,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.person,
                            size: 20,
                            color: AppColors.dark,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                x['from_user'] as String,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.text,
                                ),
                              ),
                              Text(
                                'to pay ${x['to_user']}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '₹${x['amount']}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: AppColors.text,
                          ),
                        ),
                      ],
                    ),
                    if (_myId == x['to_user_id']) ...[
                      const SizedBox(height: 10),
                      const Divider(color: AppColors.border, height: 1),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                final msg =
                                    "Hi ${x['from_user']},\n\nJust a quick reminder regarding your balance of ₹${x['amount']} in '${widget.groupName}'.\n\nPlease settle up when you can!";
                                await Share.share(
                                  msg,
                                  subject:
                                      "Friendly Reminder: Action needed in '${widget.groupName}'",
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.surface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Share',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.text,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                _showTopMessage('Sending reminder...');
                                final res = await ApiService.sendSplitReminder(
                                  widget.groupId,
                                  {
                                    'user_id': x['from_user_id'],
                                    'amount': x['amount'],
                                  },
                                );
                                if (!mounted) return;
                                _showTopMessage(
                                  res.isSuccess
                                      ? 'Reminder sent!'
                                      : (res.error ?? 'Error'),
                                  isError: !res.isSuccess,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.surface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Remind',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.accent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _settle(x),
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Settle',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (s.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                'Settlement History',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
            ),
            ...s.map((x) {
              final dt = DateTime.tryParse(x['date'] ?? '');
              final f =
                  dt != null
                      ? DateFormat('MMM d, yyyy').format(dt.toLocal())
                      : '';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: AppShadows.card,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: AppColors.successLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.handshake,
                        size: 18,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${x['paid_by']} → ${x['paid_to']}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text,
                            ),
                          ),
                          Text(
                            f,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${x['amount']}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
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
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: AppColors.background, child: child);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}
