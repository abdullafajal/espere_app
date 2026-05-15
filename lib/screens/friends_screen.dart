import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/sync_service.dart';
import '../widgets/user_avatar.dart';
import 'split_group_detail_screen.dart';
import '../widgets/icon_color_picker.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _pendingReceived = [];
  List<Map<String, dynamic>> _pendingSent = [];
  List<Map<String, dynamic>> _groupInvitations = [];
  List<int> _selectedFriendIds = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    final friendsResult = await ApiService.getFriends();
    final invitationsResult = await ApiService.getGroupInvitations();
    
    if (!mounted) return;
    
    setState(() {
      _isLoading = false;
      if (friendsResult.isSuccess) {
        _friends = List<Map<String, dynamic>>.from(friendsResult.data!['friends']);
        _pendingReceived = List<Map<String, dynamic>>.from(friendsResult.data!['pending_received']);
        _pendingSent = List<Map<String, dynamic>>.from(friendsResult.data!['pending_sent']);
      }
      if (invitationsResult.isSuccess) {
        _groupInvitations = invitationsResult.data!;
      }
    });
  }

  void _inviteFriend() {
    final emailController = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Center(child: Text('Invite Friend', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text))),
            const SizedBox(height: 20),
            const Text('Email or Username', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text)),
            const SizedBox(height: 6),
            TextField(
              controller: emailController,
              decoration: InputDecoration(
                hintText: 'Enter email or username...',
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () async {
                  final email = emailController.text.trim();
                  if (email.isEmpty) return;
                  
                  final r = await ApiService.inviteFriend(email);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  
                  if (r.isSuccess) {
                    HapticFeedback.mediumImpact();
                    _loadData();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Friend request sent!')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.error ?? 'Error')));
                  }
                },
                child: const Text('Send Request'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _createGroupWithSelected() {
    if (_selectedFriendIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one friend')));
      return;
    }
    
    final nameCtrl = TextEditingController();
    bool isSaving = false;
    String selectedColor = '#C8E64A';
    String selectedIcon = 'category';
    String? nameError;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Center(child: Text('New Group', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.text))),
              const SizedBox(height: 20),
              const Text('Group Name', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text)),
              const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  onChanged: (v) => ss(() {}),
                  style: const TextStyle(fontSize: 14, color: AppColors.text),
                  decoration: InputDecoration(
                    hintText: 'e.g. Goa Trip',
                    errorText: nameError,
                    errorStyle: const TextStyle(color: AppColors.text, fontSize: 12),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      borderSide: const BorderSide(color: AppColors.border, width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      borderSide: const BorderSide(color: AppColors.border, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 20),
                IconColorPicker(
                  currentName: nameCtrl.text,
                  onSelected: (color, icon) {
                    selectedColor = color;
                    selectedIcon = icon;
                  },
                ),
                const SizedBox(height: 20),
                Text('Selected: ${_selectedFriendIds.length} friends', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: isSaving ? null : () async {
                    if (nameCtrl.text.trim().isEmpty) {
                      ss(() => nameError = 'Group name is required');
                      return;
                    }
                    ss(() => isSaving = true);
                    
                    final body = {
                      'name': nameCtrl.text.trim(),
                      'members': _selectedFriendIds,
                      'color': selectedColor,
                      'icon': selectedIcon,
                    };

                    if (ConnectivityService.isOnline) {
                      final res = await ApiService.createSplitGroup(body);
                      
                      if (!ctx.mounted) return;
                      
                      if (res.isSuccess) {
                        HapticFeedback.mediumImpact();
                        final groupData = res.data!;
                        setState(() => _selectedFriendIds = []);
                        Navigator.pop(ctx); // Close sheet
                        Navigator.pop(ctx); // Close friends screen
                        
                        if (!context.mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SplitGroupDetailScreen(
                              groupId: groupData['id'] as int,
                              groupName: groupData['name'] as String,
                            ),
                          ),
                        );
                      } else {
                        ss(() => isSaving = false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.error ?? 'Error')));
                      }
                    } else {
                      // Offline: Queue and optimistic update
                      final tempId = DateTime.now().millisecondsSinceEpoch;
                      await SyncService.queueOperation(
                        action: 'create',
                        entity: 'split_group',
                        data: body,
                      );
                      
                      final optGroup = {
                        'id': tempId,
                        'name': body['name'],
                        'net_balance': '0.00',
                        'total_members': _selectedFriendIds.length + 1,
                        'created_at': DateTime.now().toIso8601String(),
                        'color': selectedColor,
                        'icon': selectedIcon,
                        'is_temp': true,
                      };
                      
                      await CacheService.addSplitGroupToCache(optGroup);
                      
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      setState(() => _selectedFriendIds = []);
                      HapticFeedback.mediumImpact();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Created offline. Will sync when online.')));
                    }
                  },
                  child: isSaving 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
                    : const Text('Create Group'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleFriendAction(int id, String action) async {
    final r = await ApiService.handleFriendRequest(id, action);
    if (r.isSuccess) {
      HapticFeedback.lightImpact();
      _loadData();
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.error ?? 'Error')));
    }
  }

  Future<void> _handleGroupAction(int id, String action) async {
    final r = await ApiService.handleGroupInvitation(id, action);
    if (r.isSuccess) {
      HapticFeedback.lightImpact();
      _loadData();
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.error ?? 'Error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabs(),
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildFriendsTab(),
                      _buildRequestsTab(),
                    ],
                  ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _inviteFriend,
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.dark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.person_add_alt_1),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), boxShadow: AppShadows.soft),
              child: const Icon(Icons.arrow_back, color: AppColors.text, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Text('Friends', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text))),
          GestureDetector(
            onTap: _loadData,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), boxShadow: AppShadows.soft),
              child: const Icon(Icons.refresh, color: AppColors.text, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.soft),
        padding: const EdgeInsets.all(4),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: AppColors.text,
          unselectedLabelColor: AppColors.muted,
          dividerHeight: 0,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'My Friends'),
            Tab(text: 'Requests'),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendsTab() {
    if (_friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: AppColors.muted.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text('No friends yet.', style: TextStyle(fontSize: 16, color: AppColors.muted, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            const Text('Invite someone to start splitting expenses!', style: TextStyle(fontSize: 13, color: AppColors.muted)),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (_friends.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _selectedFriendIds.isEmpty ? null : _createGroupWithSelected,
                    icon: const Icon(Icons.group_add, size: 18),
                    label: Text(_selectedFriendIds.isEmpty ? 'Select friends to create group' : 'Create Group with ${_selectedFriendIds.length}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.dark, // This is the 'selected' state bg
                      foregroundColor: AppColors.accent, // This is the 'selected' state text
                      disabledBackgroundColor: AppColors.accent, // This is the 'no selection' state bg
                      disabledForegroundColor: AppColors.dark, // This is the 'no selection' state text
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
            itemCount: _friends.length,
            itemBuilder: (ctx, i) {
              final f = _friends[i];
              final fid = f['id'] as int;
              final isSelected = _selectedFriendIds.contains(fid);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) _selectedFriendIds.remove(fid);
                    else _selectedFriendIds.add(fid);
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.card, 
                    borderRadius: BorderRadius.circular(20), 
                    boxShadow: AppShadows.card,
                    border: Border.all(color: isSelected ? AppColors.accent : Colors.transparent, width: 2),
                  ),
                  child: Row(
                    children: [
                      UserAvatar(
                        initial: f['initial'] ?? '?', 
                        avatarUrl: f['avatar_url'],
                        size: 48,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f['display_name'] ?? f['username'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.text)),
                            Text(f['email'] ?? '', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                          ],
                        ),
                      ),
                      Checkbox(
                        value: isSelected,
                        onChanged: (v) {
                          setState(() {
                            if (v!) _selectedFriendIds.add(fid);
                            else _selectedFriendIds.remove(fid);
                          });
                        },
                        activeColor: AppColors.accent,
                        checkColor: AppColors.dark,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRequestsTab() {
    final hasGroupInvites = _groupInvitations.isNotEmpty;
    final hasFriendRequests = _pendingReceived.isNotEmpty;
    final hasSentRequests = _pendingSent.isNotEmpty;

    if (!hasGroupInvites && !hasFriendRequests && !hasSentRequests) {
      return const Center(child: Text('No pending requests', style: TextStyle(color: AppColors.muted)));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      children: [
        if (hasGroupInvites) ...[
          const Padding(padding: EdgeInsets.only(left: 4, bottom: 8, top: 8), child: Text('Group Invitations', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text))),
          ..._groupInvitations.map((inv) => _buildInviteCard(inv, true)),
          const SizedBox(height: 16),
        ],
        if (hasFriendRequests) ...[
          const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Text('Friend Requests', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text))),
          ..._pendingReceived.map((req) => _buildFriendRequestCard(req, true)),
          const SizedBox(height: 16),
        ],
        if (hasSentRequests) ...[
          const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Text('Sent Requests', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.text))),
          ..._pendingSent.map((req) => _buildFriendRequestCard(req, false)),
        ],
      ],
    );
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
}
