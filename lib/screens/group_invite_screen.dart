/// Invite people to a split group, all on one screen: share or copy the invite link,
/// find anyone by name, @username or email, add friends with one tap, and resend or
/// cancel invites that are still waiting.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/app_toast.dart';
import '../widgets/espere_header.dart';
import '../widgets/spring_menu.dart';
import '../widgets/user_avatar.dart';

class GroupInviteScreen extends StatefulWidget {
  final int groupId;
  final String groupName;
  final String inviteToken;
  final String myUsername;

  /// The group's members as the group detail returns them (with `is_accepted`).
  final List<Map<String, dynamic>> members;

  /// Email invites still waiting (`email`, `created_at`).
  final List<Map<String, dynamic>> pendingInvites;

  const GroupInviteScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.inviteToken,
    required this.myUsername,
    required this.members,
    required this.pendingInvites,
  });

  /// Opens the screen. Resolves to true when anyone was invited or an invite changed.
  static Future<bool> open(BuildContext context, GroupInviteScreen screen) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => screen));
    return changed == true;
  }

  @override
  State<GroupInviteScreen> createState() => _GroupInviteScreenState();
}

class _GroupInviteScreenState extends State<GroupInviteScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _changed = false;
  bool _copied = false;

  List<Map<String, dynamic>> _friends = const [];
  bool _friendsLoading = true;
  List<Map<String, dynamic>> _results = const [];
  bool _searching = false;

  /// User ids already in the group (joined or invited) and invited here.
  late final Set<int> _inGroup = {
    for (final m in widget.members)
      if (m['id'] is int) m['id'] as int,
  };
  final Set<int> _busy = {};

  late List<Map<String, dynamic>> _pendingUsers =
      widget.members.where((m) => m['is_accepted'] == false).toList();
  late List<Map<String, dynamic>> _pendingEmails = List.of(widget.pendingInvites);

  String get _link => 'https://espere.in/invite/${widget.inviteToken}?ref=${widget.myUsername}';

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    final r = await ApiService.getFriends();
    if (!mounted) return;
    setState(() {
      _friends = r.isSuccess ? List<Map<String, dynamic>>.from(r.data?['friends'] ?? const []) : const [];
      _friendsLoading = false;
    });
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    setState(() {});
    if (q.trim().length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      final r = await ApiService.searchUsers(q.trim());
      if (!mounted || _search.text.trim() != q.trim()) return;
      setState(() {
        _results = r.data ?? const [];
        _searching = false;
      });
    });
  }

  bool get _queryIsEmail {
    final q = _search.text.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(q);
  }

  Future<void> _share() async {
    AppHaptics.press();
    await Share.share(
      'Join "${widget.groupName}" on Espere to split expenses with me: $_link',
      subject: 'Join ${widget.groupName} on Espere',
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _link));
    AppHaptics.tap();
    if (mounted) setState(() => _copied = true);
  }

  /// Invites an app user (by id) or anyone by email.
  Future<void> _invite({Map<String, dynamic>? user, String? email}) async {
    final id = user?['id'] as int?;
    if (id != null) setState(() => _busy.add(id));
    final r = await ApiService.addSplitMember(
      widget.groupId,
      identifier: email ?? user?['username']?.toString() ?? id.toString(),
    );
    if (!mounted) return;
    setState(() {
      if (id != null) _busy.remove(id);
      if (r.isSuccess) {
        _changed = true;
        if (user != null && id != null) {
          _inGroup.add(id);
          _pendingUsers = [..._pendingUsers, {...user, 'is_accepted': false}];
        } else if (email != null) {
          _pendingEmails = [
            {'email': email, 'created_at': DateTime.now().toUtc().toIso8601String()},
            ..._pendingEmails.where((e) => e['email'] != email),
          ];
          _search.clear();
          _results = const [];
        }
      }
    });
    if (r.isSuccess) {
      AppHaptics.confirm();
      AppToast.success(context, r.data?['message']?.toString() ?? 'Invite sent');
    } else {
      AppToast.error(context, r.error ?? 'Could not send the invite.');
    }
  }

  Future<void> _manage(String action, {String? email, int? userId}) async {
    final r = await ApiService.manageSplitInvite(widget.groupId, action, email: email, userId: userId);
    if (!mounted) return;
    if (!r.isSuccess) {
      AppToast.error(context, r.error ?? 'Something went wrong.');
      return;
    }
    _changed = true;
    if (action == 'cancel') {
      setState(() {
        if (email != null) _pendingEmails = _pendingEmails.where((e) => e['email'] != email).toList();
        if (userId != null) {
          _pendingUsers = _pendingUsers.where((m) => m['id'] != userId).toList();
          _inGroup.remove(userId);
        }
      });
    }
    AppToast.success(context, r.data ?? 'Done');
  }

  @override
  Widget build(BuildContext context) {
    final friends = _friends.where((f) => f['id'] is int).toList();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              EspereHeader(
                title: 'Invite to ${widget.groupName}',
                onBack: () => Navigator.of(context).pop(_changed),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  children: [
                    _linkCard(),
                    const SizedBox(height: 14),
                    _searchField(),
                    if (_search.text.trim().length >= 2) ...[
                      const SizedBox(height: 8),
                      _searchResults(),
                    ],
                    _section('YOUR FRIENDS'),
                    if (_friendsLoading)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.dark)),
                      )
                    else if (friends.isEmpty)
                      _hint('Friends you add in Split show up here for one-tap invites.')
                    else
                      _card([for (final f in friends) _personRow(f)]),
                    if (_pendingUsers.isNotEmpty || _pendingEmails.isNotEmpty) ...[
                      _section('WAITING TO JOIN'),
                      _card([
                        for (final m in _pendingUsers) _pendingUserRow(m),
                        for (final e in _pendingEmails) _pendingEmailRow(e),
                      ]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                child: const Icon(Icons.link_rounded, size: 22, color: AppColors.dark),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Invite link',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                    Text(
                      'Anyone with it can ask to join',
                      style: const TextStyle(fontSize: 12, color: AppColors.darkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SpringPress(
                  haptic: HapticKind.none,
                  onTap: _share,
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(23)),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.share_rounded, size: 18, color: AppColors.dark),
                        SizedBox(width: 6),
                        Text('Share invite',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.dark)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SpringPress(
                  haptic: HapticKind.none,
                  onTap: _copy,
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(color: AppColors.darkCardRaised, borderRadius: BorderRadius.circular(23)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_copied ? Icons.check_rounded : Icons.content_copy_rounded,
                            size: 18, color: _copied ? AppColors.accent : Colors.white),
                        const SizedBox(width: 6),
                        Text(_copied ? 'Copied' : 'Copy link',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.soft,
      ),
      child: TextField(
        controller: _search,
        onChanged: _onSearch,
        textInputAction: TextInputAction.search,
        keyboardType: TextInputType.emailAddress,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text),
        decoration: InputDecoration(
          hintText: 'Name, @username or email',
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.muted),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    _search.clear();
                    _onSearch('');
                  },
                ),
          filled: true,
          fillColor: AppColors.card,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: AppColors.dark, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _searchResults() {
    final q = _search.text.trim();
    final rows = <Widget>[for (final u in _results.where((u) => u['id'] is int)) _personRow(u)];
    if (_queryIsEmail && !_results.any((u) => (u['email'] ?? '').toString().toLowerCase() == q.toLowerCase())) {
      rows.add(_row(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.mutedLight, width: 2),
          ),
          child: const Icon(Icons.mail_rounded, size: 18, color: AppColors.muted),
        ),
        title: q,
        sub: 'Not on Espere yet · we email them an invite',
        trailing: _pillButton('Invite', Icons.send_rounded, dark: true, onTap: () => _invite(email: q)),
      ));
    }
    if (_searching && rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.dark)),
      );
    }
    if (rows.isEmpty) {
      return _hint(_queryIsEmail || q.contains('@')
          ? 'Type their full email to invite them.'
          : 'Nobody found. Try their @username, or type their email to invite them.');
    }
    return _card(rows);
  }

  Widget _personRow(Map<String, dynamic> u) {
    final id = u['id'] as int;
    final invited = _inGroup.contains(id);
    final busy = _busy.contains(id);
    final name = (u['display_name'] ?? u['username'] ?? '').toString();
    return _row(
      leading: UserAvatar(initial: (u['initial'] ?? name).toString(), avatarUrl: u['avatar_url'], size: 40),
      title: name,
      sub: invited ? 'In the group or invited' : '@${u['username'] ?? ''}',
      trailing: invited
          ? _pillButton('Added', Icons.check_rounded, onTap: null)
          : busy
              ? const SizedBox(
                  width: 36, height: 36, child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
              : _pillButton('Add', Icons.add_rounded, dark: true, onTap: () => _invite(user: u)),
    );
  }

  Widget _pendingUserRow(Map<String, dynamic> m) {
    final name = (m['display_name'] ?? m['username'] ?? '').toString();
    return _row(
      leading: UserAvatar(initial: (m['initial'] ?? name).toString(), avatarUrl: m['avatar_url'], size: 40),
      title: name,
      sub: 'Invited · waiting for them to accept',
      trailing: SpringMenuButton<String>(
        items: const [
          SpringMenuItem('resend', Icons.notifications_active_rounded, 'Send again'),
          SpringMenuItem('cancel', Icons.close_rounded, 'Cancel invite', destructive: true),
        ],
        onSelected: (v) => _manage(v, userId: m['id'] as int?),
      ),
    );
  }

  Widget _pendingEmailRow(Map<String, dynamic> e) {
    final email = (e['email'] ?? '').toString();
    return _row(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.mutedLight, width: 2)),
        child: const Icon(Icons.mail_rounded, size: 18, color: AppColors.muted),
      ),
      title: email,
      sub: 'Invited by email · not on Espere yet',
      trailing: SpringMenuButton<String>(
        items: const [
          SpringMenuItem('resend', Icons.send_rounded, 'Email again'),
          SpringMenuItem('cancel', Icons.close_rounded, 'Cancel invite', destructive: true),
        ],
        onSelected: (v) => _manage(v, email: email),
      ),
    );
  }

  Widget _row({required Widget leading, required String title, required String sub, required Widget trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.rowTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 1),
                Text(sub, style: AppText.rowSub, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }

  Widget _pillButton(String label, IconData icon, {bool dark = false, VoidCallback? onTap}) {
    final bg = onTap == null ? AppColors.accent : (dark ? AppColors.dark : AppColors.surface);
    final fg = onTap == null ? AppColors.dark : (dark ? Colors.white : AppColors.text);
    return SpringPress(
      haptic: HapticKind.none,
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: dark && onTap != null ? AppColors.accent : fg),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 18, 6, 6),
        child: Text(title, style: AppText.label),
      );

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
        child: Text(text, style: AppText.rowSub),
      );

  Widget _card(List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppShadows.soft,
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 66, endIndent: 14),
              rows[i],
            ],
          ],
        ),
      );
}
