/// New group / edit group: a big name on a dark top with the group's icon, then the
/// kind of group, who to add (new groups) and who may invite. Same look as Add expense.
library;

import '../widgets/morph_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/icon_mapper.dart';

class GroupFormScreen extends StatefulWidget {
  /// The group to edit (id, name, icon, color, members_can_invite), or null to create.
  final Map<String, dynamic>? group;

  const GroupFormScreen({super.key, this.group});

  /// Opens the form; true when something was saved.
  static Future<bool> open(BuildContext context, {Map<String, dynamic>? group}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => GroupFormScreen(group: group), fullscreenDialog: true),
    );
    return saved == true;
  }

  @override
  State<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends State<GroupFormScreen> {
  static const _kinds = <(String, String, List<String>)>[
    ('flight', 'Trip', ['trip', 'travel', 'tour', 'goa', 'manali', 'vacation', 'holiday', 'flight']),
    ('home', 'Home', ['home', 'flat', 'room', 'house', 'pg', 'hostel', 'roommate']),
    ('favorite', 'Couple', ['couple', 'love', 'wife', 'husband', 'partner']),
    ('restaurant', 'Food', ['food', 'dinner', 'lunch', 'party', 'canteen', 'tiffin']),
    ('celebration', 'Event', ['event', 'wedding', 'birthday', 'shaadi', 'fest']),
    ('work', 'Work', ['work', 'office', 'team', 'project']),
    ('school', 'College', ['school', 'college', 'class', 'batch']),
    ('sports_soccer', 'Sports', ['sport', 'cricket', 'football', 'gym', 'turf']),
    ('directions_car', 'Ride', ['car', 'ride', 'cab', 'pool', 'bike']),
    ('movie', 'Movies', ['movie', 'cinema', 'netflix']),
    ('pets', 'Pets', ['pet', 'dog', 'cat']),
    ('groups', 'Friends', ['friend', 'gang', 'squad', 'dost', 'boys', 'girls']),
  ];

  late final _name = TextEditingController(text: widget.group?['name']?.toString() ?? '');
  late String? _icon = widget.group?['icon']?.toString();
  late bool _canInvite = widget.group?['members_can_invite'] != false;
  final Set<int> _picked = {};
  List<Map<String, dynamic>> _friends = [];
  bool _loadingFriends = true;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.group != null;

  /// The icon shown: the one picked, else a guess from the name, else Friends.
  String get _shownIcon {
    if (_icon != null && _icon!.isNotEmpty) return _icon!;
    final t = _name.text.toLowerCase();
    for (final k in _kinds) {
      if (k.$3.any(t.contains)) return k.$1;
    }
    return 'groups';
  }

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    if (_editing) {
      _loadingFriends = false;
    } else {
      _loadFriends();
    }
  }

  Future<void> _loadFriends() async {
    final r = await ApiService.getFriends();
    if (!mounted) return;
    setState(() {
      _loadingFriends = false;
      if (r.isSuccess) _friends = List<Map<String, dynamic>>.from(r.data?['friends'] ?? const []);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      AppHaptics.warn();
      setState(() => _error = 'Give your group a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = <String, dynamic>{
      'name': name,
      'icon': _shownIcon,
      'color': widget.group?['color'] ?? '#C8E64A',
      'members_can_invite': _canInvite,
    };
    if (_editing) EditAnimation.arm();
    final r = _editing
        ? await ApiService.updateSplitGroup(widget.group!['id'] as int, body)
        : await ApiService.createSplitGroup({...body, 'members': _picked.toList()});
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.isSuccess) {
      AppHaptics.confirm();
      Navigator.of(context).pop(true);
    } else {
      AppHaptics.warn();
      setState(() => _error = r.error ?? 'Could not save. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.dark,
        body: Column(children: [
          SafeArea(bottom: false, child: _top()),
          Expanded(child: _sheet()),
        ]),
      ),
    );
  }

  Widget _top() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 22),
      child: Column(children: [
        Row(children: [
          Semantics(
            button: true,
            label: 'Close',
            excludeSemantics: true,
            child: SpringPress(
              onTap: () => Navigator.of(context).pop(false),
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: AppColors.darkCard, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, size: 22, color: Colors.white),
              ),
            ),
          ),
          Expanded(
            child: Text(_editing ? 'Edit group' : 'New group',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(width: 44),
        ]),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: Container(
            key: ValueKey(_shownIcon),
            width: 76,
            height: 76,
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(26)),
            child: Icon(IconMapper.map(_shownIcon), size: 38, color: AppColors.dark),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _name,
          autofocus: !_editing,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.words,
          cursorColor: AppColors.accent,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Name your group',
            hintStyle: TextStyle(color: Color(0xFF5E635A)),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 4),
        Text(_name.text.trim().isEmpty ? 'e.g. Goa Trip, Flat 302, Office lunch' : 'Tap the name to change it',
            style: const TextStyle(fontSize: 12, color: AppColors.darkMuted)),
      ]),
    );
  }

  Widget _sheet() {
    final count = _picked.length + 1;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxxl)),
      ),
      child: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
            children: [
              const Text('WHAT KIND OF GROUP', style: AppText.label),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final k in _kinds) _kindChip(k.$1, k.$2)]),
              if (!_editing) ...[
                const SizedBox(height: 20),
                Row(children: [
                  const Expanded(child: Text('ADD FRIENDS', style: AppText.label)),
                  if (_picked.isNotEmpty)
                    Text('${_picked.length} picked', style: AppText.rowTitle.copyWith(fontSize: 12)),
                ]),
                const SizedBox(height: 8),
                _friendsBox(),
              ],
              const SizedBox(height: 20),
              const Text('GROUP', style: AppText.label),
              const SizedBox(height: 8),
              _inviteSwitch(),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.info_rounded, size: 18, color: AppColors.dark),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: AppText.rowTitle.copyWith(fontSize: 13))),
                  ]),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12 + MediaQuery.of(context).padding.bottom),
          child: SpringPress(
            haptic: HapticKind.none,
            onTap: _save,
            child: Container(
              height: 54,
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(27)),
              alignment: Alignment.center,
              child: _saving
                  ? const SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.dark))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!_editing) ...[
                        const Icon(Icons.group_add_rounded, size: 22, color: AppColors.dark),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _editing ? 'Save changes' : (count == 1 ? 'Create group' : 'Create group · $count people'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.dark),
                      ),
                    ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _kindChip(String icon, String label) {
    final on = _shownIcon == icon;
    return SpringPress(
      onTap: () => setState(() => _icon = icon),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 40,
        padding: const EdgeInsets.only(left: 10, right: 14),
        decoration: BoxDecoration(
          color: on ? AppColors.dark : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(IconMapper.map(icon), size: 18, color: on ? AppColors.accent : AppColors.dark),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? Colors.white : AppColors.text)),
        ]),
      ),
    );
  }

  Widget _friendsBox() {
    if (_loadingFriends) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.dark)),
      );
    }
    if (_friends.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
        child: const Row(children: [
          Icon(Icons.link_rounded, size: 20, color: AppColors.dark),
          SizedBox(width: 10),
          Expanded(
            child: Text('No friends yet. After creating, share the invite link from the group.',
                style: AppText.rowSub),
          ),
        ]),
      );
    }
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < _friends.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 12, endIndent: 12),
          _friendRow(_friends[i]),
        ],
      ]),
    );
  }

  Widget _friendRow(Map<String, dynamic> f) {
    final id = f['id'] as int;
    final on = _picked.contains(id);
    final name = (f['display_name'] ?? f['username'] ?? '').toString();
    final user = (f['username'] ?? '').toString();
    return InkWell(
      onTap: () {
        AppHaptics.tap();
        setState(() => on ? _picked.remove(id) : _picked.add(id));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: on ? AppColors.accent : AppColors.surface, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text((f['initial'] ?? (name.isEmpty ? '?' : name[0])).toString().toUpperCase(),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.dark)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.rowTitle),
              if (user.isNotEmpty) Text('@$user', style: AppText.rowSub),
            ]),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: on ? AppColors.accent : AppColors.dark,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(on ? Icons.check_rounded : Icons.add_rounded, size: 16, color: on ? AppColors.dark : Colors.white),
              const SizedBox(width: 4),
              Text(on ? 'Added' : 'Add',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? AppColors.dark : Colors.white)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _inviteSwitch() => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          AppHaptics.tap();
          setState(() => _canInvite = !_canInvite);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(20)),
          child: Semantics(
            toggled: _canInvite,
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.group_add_rounded, size: 21, color: AppColors.dark),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Members can invite', style: AppText.rowTitle),
                  Text('Otherwise only you can add people', style: AppText.rowSub),
                ]),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                width: 46,
                height: 28,
                padding: const EdgeInsets.all(3),
                alignment: _canInvite ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: _canInvite ? AppColors.dark : const Color(0xFFDADDD5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: _canInvite ? AppColors.accent : Colors.white, shape: BoxShape.circle),
                ),
              ),
            ]),
          ),
        ),
      );
}
