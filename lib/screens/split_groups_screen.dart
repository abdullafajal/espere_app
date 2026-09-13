import 'package:flutter/material.dart';
import '../widgets/espere_header.dart';
import '../widgets/espere_swipe_action.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../widgets/espere_back_button.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';
import '../widgets/thanos_snap_widget.dart';
import '../widgets/user_avatar.dart';
import 'split_group_detail_screen.dart';
import 'friends_screen.dart';
import '../widgets/icon_color_picker.dart';
import '../utils/icon_mapper.dart';
import '../widgets/full_offline_alert.dart';

class SplitGroupsScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const SplitGroupsScreen({super.key, this.onBack});

  @override
  State<SplitGroupsScreen> createState() => SplitGroupsScreenState();
}

class SplitGroupsScreenState extends State<SplitGroupsScreen> {
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _groupInvitations = [];
  List<Map<String, dynamic>> _pendingReceived = [];
  bool _isLoading = true;
  int? _myId;
  String _currencySymbol = '₹';
  final Map<int, GlobalKey<ThanosSnapWidgetState>> _groupSnapKeys = {};

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  void reload() => _loadGroups();

  Future<void> _loadGroups() async {
    final cachedUser = await CacheService.getCachedUser();
    if (cachedUser != null && mounted) {
      setState(() {
        _myId = cachedUser['id'];
        _currencySymbol = cachedUser['currency_symbol'] as String? ?? '₹';
      });
    }

    // 1. Always check cache first
    final cached = await CacheService.getCachedSplitGroups();
    if (cached != null && mounted) {
      setState(() {
        _groups = cached;
        _isLoading = false;
      });
    }

    // 2. Fetch fresh from API ONLY IF ONLINE
    if (ConnectivityService.isOnline) {
      // Fetch profile for ownership check
      ApiService.getProfile().then((pr) {
        if (pr.isSuccess && mounted) setState(() => _myId = pr.data?.id);
      });

      ApiService.getSplitGroups().then((result) {
        if (result.isSuccess && mounted) {
          setState(() {
            _isLoading = false;
            _groups = result.data!;
          });
          CacheService.cacheSplitGroups(_groups);
        } else if (_groups.isEmpty && mounted) {
          setState(() {
            _isLoading = false;
          });
          AppToast.error(context, result.error ?? 'Failed to load groups');
        }
      });
      
      ApiService.getFriends().then((res) {
        if (res.isSuccess && mounted) {
          setState(() {
            _pendingReceived = List<Map<String, dynamic>>.from(res.data!['pending_received'] ?? []);
          });
        }
      });
      
      ApiService.getGroupInvitations().then((res) {
        if (res.isSuccess && mounted) {
          setState(() => _groupInvitations = res.data!);
        }
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleFriendAction(dynamic id, String action) async {
    final r = await ApiService.handleFriendRequest(id, action);
    if (r.isSuccess) {
      HapticFeedback.lightImpact();
      _loadGroups();
    } else {
      if (mounted) AppToast.error(context, r.error ?? 'Error');
    }
  }

  Future<void> _handleGroupAction(int id, String action) async {
    final r = await ApiService.handleGroupInvitation(id, action);
    if (r.isSuccess) {
      HapticFeedback.lightImpact();
      _loadGroups();
    } else {
      if (mounted) AppToast.error(context, r.error ?? 'Error');
    }
  }

  Widget _buildInviteCard(Map<String, dynamic> inv, bool isReceived) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card, border: Border.all(color: AppColors.accent.withOpacity(0.3))),
      child: Column(
        children: [
          Row(
            children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.2), shape: BoxShape.circle), child: const Icon(Icons.groups, color: AppColors.accent, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(inv['group_name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text)),
                    Text('Invited by ${inv['invited_by']}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _handleGroupAction(inv['id'], 'reject'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Decline', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _handleGroupAction(inv['id'], 'accept'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.dark,
                    foregroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Accept', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFriendRequestCard(Map<String, dynamic> req, bool isReceived) {
    final u = isReceived ? req['sender'] : req['receiver'];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
      child: Row(
        children: [
          UserAvatar(
            initial: u['initial'] ?? '?',
            avatarUrl: u['avatar_url'],
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(u['display_name'] ?? u['username'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text))),
          if (isReceived) ...[
            IconButton(onPressed: () => _handleFriendAction(req['id'], 'reject'), icon: const Icon(Icons.close, color: AppColors.error, size: 20)),
            IconButton(onPressed: () => _handleFriendAction(req['id'], 'accept'), icon: const Icon(Icons.check, color: AppColors.success, size: 20)),
          ] else
            TextButton(onPressed: () => _handleFriendAction(req['id'], 'cancel'), child: const Text('Cancel', style: TextStyle(color: AppColors.muted, fontSize: 12))),
        ],
      ),
    );
  }

  void _showRequestsPopup() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) {
          final hasGroupInvites = _groupInvitations.isNotEmpty;
          final hasFriendRequests = _pendingReceived.isNotEmpty;
          
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
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
                const SizedBox(height: 16),
                const Center(
                  child: Text('Pending Requests', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text)),
                ),
                const SizedBox(height: 24),
                
                if (!hasGroupInvites && !hasFriendRequests)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: Text('No pending requests.', style: TextStyle(color: AppColors.muted))),
                  )
                else ...[
                  if (hasGroupInvites) ...[
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8), 
                      child: Text('Group Invitations', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text))
                    ),
                    ..._groupInvitations.map((inv) => _buildInviteCard(inv, true)),
                    const SizedBox(height: 16),
                  ],
                  if (hasFriendRequests) ...[
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8), 
                      child: Text('Friend Requests', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text))
                    ),
                    ..._pendingReceived.map((req) => _buildFriendRequestCard(req, true)),
                    const SizedBox(height: 16),
                  ],
                ],
              ],
            ),
          );
        }
      ),
    );
  }

  void _showCreateGroupSheet() async {
    final nameCtrl = TextEditingController();
    List<Map<String, dynamic>> friends = [];
    List<int> selectedIds = [];
    bool loadingFriends = true;
    bool isSaving = false;
    String selectedColor = '#C8E64A';
    String selectedIcon = 'groups';

    final res = await ApiService.getFriends();
    if (res.isSuccess) {
      friends = List<Map<String, dynamic>>.from(res.data!['friends']);
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
                  child: Text('Create Group', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text)),
                ),
                const SizedBox(height: 32),
                const Text('Group Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.muted)),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  onChanged: (v) => ss(() {}),
                  style: const TextStyle(fontSize: 15, color: AppColors.text),
                  decoration: _inputDeco('e.g. Trip to Goa'),
                ),
                const SizedBox(height: 24),
                IconColorPicker(
                  currentName: nameCtrl.text,
                  onSelected: (color, icon) {
                    selectedColor = color;
                    selectedIcon = icon;
                  },
                ),
                const SizedBox(height: 32),
                const Text('Add Members', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.muted)),
                const SizedBox(height: 12),
                if (loadingFriends)
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppColors.accent)))
                else if (friends.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    width: double.infinity,
                    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                    child: const Text('No friends yet. You can add them later.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  )
                else
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
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.dark, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: isSaving ? null : () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      ss(() => isSaving = true);
                      final body = {'name': nameCtrl.text.trim(), 'members': selectedIds, 'color': selectedColor, 'icon': selectedIcon};
                      final r = await ApiService.createSplitGroup(body);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (r.isSuccess) {
                        HapticFeedback.lightImpact();
                        _loadGroups();
                      } else {
                        _showTopMessage(r.error ?? 'Error', isError: true);
                      }
                    },
                    child: isSaving 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
                        : const Text('Create Group', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint,
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

  @override
  Widget build(BuildContext context) {
    return FullOfflineAlert(
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              EspereHeader(
                title: 'Split Groups',
                onBack: () {
                  if (widget.onBack != null) {
                    widget.onBack?.call();
                  } else {
                    Navigator.maybePop(context);
                  }
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_groupInvitations.isNotEmpty || _pendingReceived.isNotEmpty) ...[
                      GestureDetector(
                        onTap: _showRequestsPopup,
                        child: Stack(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                boxShadow: AppShadows.soft,
                              ),
                              child: const Icon(Icons.notifications_none, color: AppColors.text),
                            ),
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    GestureDetector(
                      onTap: _showCreateGroupSheet,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          boxShadow: AppShadows.soft,
                        ),
                        child: const Icon(Icons.add, color: AppColors.dark, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

        // Content
        Expanded(
          child:
              _isLoading && _groups.isEmpty
                  ? _buildSkeleton()
                  : _groups.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                    onRefresh: _loadGroups,
                    color: AppColors.accent,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                      itemCount: _groups.length,
                      itemBuilder: (_, i) => _buildGroupCard(i),
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      itemCount: 4,
      itemBuilder: (_, __) => Container(
        height: 100,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.card.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  Widget _buildEmptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 1, 1, 1).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppRadius.xxl),
          ),
          child: const Icon(Icons.groups, size: 40, color: AppColors.accent),
        ),
        const SizedBox(height: 16),
        const Text(
          'No groups yet',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Create a group to start splitting expenses',
          style: TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );

  Widget _buildGroupCard(int index) {
    final group = _groups[index];
    final netBalance = double.tryParse(group['net_balance'].toString()) ?? 0;
    final memberCount = group['total_members'] ?? 0;
    final groupColor = Color(int.parse((group['color'] ?? '#C8E64A').replaceFirst('#', '0xFF')));

    final canEditDelete = group['is_accepted'] == true && group['created_by_id'] == _myId;

    final snapKey = _groupSnapKeys.putIfAbsent(group['id'], () => GlobalKey<ThanosSnapWidgetState>());

    return ThanosSnapWidget(
      key: snapKey,
      child: _GroupTile(
        group: group,
        canEditDelete: canEditDelete,
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SplitGroupDetailScreen(
                groupId: group['id'] as int,
                groupName: group['name'] as String,
              ),
            ),
          );
          _loadGroups();
        },
        onEdit: () => _editGroupSheet(group),
        onDelete: () => _deleteGroup(snapKey, group),
        child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: groupColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Icon(
                      _getIconData(group['icon'] ?? 'groups'),
                      color: AppColors.dark,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group['name'] ?? 'Group',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text),
                      ),
                      const SizedBox(height: 6),
                      if (group['is_accepted'] == false)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.muted.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('Invitation Pending', style: TextStyle(fontSize: 10, color: AppColors.muted, fontWeight: FontWeight.bold)),
                        )
                      else
                        _buildBalanceText(netBalance),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (group['is_accepted'] == false)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.muted.withOpacity(0.05),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => _handleCardAction(group['id'], 'reject'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.muted),
                      child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _handleCardAction(group['id'], 'accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.dark,
                        foregroundColor: AppColors.accent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                border: Border(top: BorderSide(color: AppColors.border.withOpacity(0.1))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Created ${group['created_at'].toString().split('T')[0]}',
                    style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600),
                  ),
                  Row(
                    children: [
                      const Text(
                        'View Details',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_ios, size: 10, color: AppColors.muted),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
    );
  }

  Widget _buildBalanceText(double balance) {
    String label;
    String amount = '$_currencySymbol${balance.abs().toStringAsFixed(0)}';

    if (balance > 0) {
      label = 'Gets back $amount';
    } else if (balance < 0) {
      label = 'To pay $amount';
    } else {
      label = 'Settled up';
    }

    return Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.text),
    );
  }

  void _editGroupSheet(Map<String, dynamic> group) {
    final nameCtrl = TextEditingController(text: group['name']);
    String selectedColor = group['color'] ?? '#C8E64A';
    String selectedIcon = group['icon'] ?? 'groups';
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
                controller: nameCtrl,
                onChanged: (v) => ss(() {}),
                style: const TextStyle(fontSize: 15, color: AppColors.text),
                decoration: _inputDeco('e.g. Trip to Goa'),
              ),
              const SizedBox(height: 24),
              IconColorPicker(
                initialColor: selectedColor,
                initialIcon: selectedIcon,
                currentName: nameCtrl.text,
                onSelected: (color, icon) {
                  selectedColor = color;
                  selectedIcon = icon;
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.dark, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: isSaving ? null : () async {
                    if (nameCtrl.text.trim().isEmpty) return;
                    ss(() => isSaving = true);
                    final body = {'name': nameCtrl.text.trim(), 'color': selectedColor, 'icon': selectedIcon};
                    final res = await ApiService.updateSplitGroup(group['id'] as int, body);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (res.isSuccess) {
                      HapticFeedback.lightImpact();
                      _loadGroups();
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

  void _deleteGroup(GlobalKey<ThanosSnapWidgetState> snapKey, Map<String, dynamic> group) async {
    final netBalance = double.tryParse(group['net_balance'].toString()) ?? 0;
    
    if (netBalance.abs() >= 0.01) {
      HapticFeedback.vibrate();
      _showTopMessage('Settle all balances before deleting group.', isError: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Group'),
        content: const Text('Are you sure you want to delete this group?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );

    if (confirm == true) {
      await snapKey.currentState?.startSnap();
      final res = await ApiService.deleteSplitGroup(group['id'] as int);
      if (res.isSuccess) {
        HapticFeedback.lightImpact();
        _showTopMessage('Group deleted.');
        _loadGroups();
      } else {
        _showTopMessage(res.error ?? 'Failed to delete', isError: true);
      }
    }
  }

  Future<void> _handleCardAction(int groupId, String action) async {
    setState(() => _isLoading = true);
    
    final invRes = await ApiService.getSplitInvitations();
    if (invRes.isSuccess) {
      final invitations = List<Map<String, dynamic>>.from(invRes.data!['invitations']);
      final inv = invitations.firstWhere((i) => i['group_id'] == groupId, orElse: () => {});
      if (inv.isNotEmpty) {
        final res = await ApiService.handleSplitInvitation(inv['id'], action);
        if (res.isSuccess) {
          HapticFeedback.mediumImpact();
          _loadGroups();
          return;
        }
      }
    }
    
    if (mounted) setState(() => _isLoading = false);
    _showTopMessage('Failed to $action invitation', isError: true);
  }

  void _showTopMessage(String message, {bool isError = false}) {
    final overlay = Overlay.of(context);
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
    Future.delayed(const Duration(seconds: 3), () => entry.remove());
  }

  IconData _getIconData(String name) => IconMapper.map(name);
}

class _GroupTile extends StatefulWidget {
  final Map<String, dynamic> group;
  final bool canEditDelete;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Widget child;

  const _GroupTile({
    required this.group,
    required this.canEditDelete,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.child,
  });

  @override
  State<_GroupTile> createState() => _GroupTileState();
}

class _GroupTileState extends State<_GroupTile> {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: EspereSwipeAction(
          dismissKey: ValueKey('group_${widget.group['id']}'),
          direction: DismissDirection.horizontal,
          bgIcon: Icons.delete,
          bgColor: AppColors.dark,
          bgIconColor: AppColors.accent,
          secBgIcon: Icons.edit,
          secBgColor: AppColors.accent,
          secBgIconColor: AppColors.dark,
          borderRadius: BorderRadius.circular(24),
          confirmDismiss: (direction) async {
            if (!widget.canEditDelete) {
              HapticFeedback.vibrate();
              AppToast.error(context, 'Only the group creator can edit or delete the group.');
              return false;
            }
            if (direction == DismissDirection.startToEnd) {
              widget.onDelete();
              return false; // we handle deletion through the callback
            } else if (direction == DismissDirection.endToStart) {
              widget.onEdit();
              return false; // we handle edit through the callback
            }
            return false;
          },
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: AppColors.border.withOpacity(0.1)),
            ),
            child: InkWell(
              onTap: widget.onTap,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
