/// Add or edit a group expense, full screen: amount and what it was for on top, then who
/// paid, how to split it and between whom, with everyone's share shown live.
///
/// "Equally" between some people (not all) is saved as an exact split of equal shares,
/// because the server's equal split always covers the whole group.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/motion.dart';
import '../utils/pickers.dart';
import '../widgets/spring_tabs.dart';

class GroupExpenseScreen extends StatefulWidget {
  final int groupId;
  final String groupName;
  final int? myId;
  final String currencySymbol;

  /// Members who joined (not pending invites).
  final List<Map<String, dynamic>> members;

  /// The expense to edit (with `splits`, `paid_by`, `split_type`), or null to add.
  final Map<String, dynamic>? editData;

  const GroupExpenseScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.myId,
    required this.currencySymbol,
    required this.members,
    this.editData,
  });

  /// Opens the screen; resolves to true when the expense was saved.
  static Future<bool> open(BuildContext context, GroupExpenseScreen screen) async {
    final saved = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => screen, fullscreenDialog: true));
    return saved == true;
  }

  @override
  State<GroupExpenseScreen> createState() => _GroupExpenseScreenState();
}

class _GroupExpenseScreenState extends State<GroupExpenseScreen> with SingleTickerProviderStateMixin {
  static const _modeIds = ['equal', 'exact', 'percentage'];
  late final TabController _tabs;
  late final _amount = TextEditingController(text: _initialAmount());
  late final _desc = TextEditingController(text: widget.editData?['description']?.toString() ?? '');
  late DateTime _date = DateTime.tryParse(widget.editData?['date']?.toString() ?? '')?.toLocal() ?? DateTime.now();
  late int? _payer = _initialPayer();
  String _mode = 'equal'; // equal | exact | percentage
  final Set<int> _out = {}; // left out of an equal split
  final Map<int, TextEditingController> _values = {};
  String? _error;
  bool _saving = false;
  /// Picked by hand; otherwise it follows the words.
  late String? _category = (widget.editData?['category'] ?? '').toString().isEmpty
      ? null
      : widget.editData!['category'].toString();

  GroupCategory get _cat =>
      groupCategoryByKey(_category) ?? guessGroupCategory(_desc.text) ?? groupCategories.last;

  List<Map<String, dynamic>> get _people => widget.members;

  String _initialAmount() {
    final v = double.tryParse(widget.editData?['amount']?.toString() ?? '');
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  }

  int? _initialPayer() {
    final paid = widget.editData?['paid_by'];
    if (paid is Map && paid['id'] is int) return paid['id'] as int;
    if (_people.any((m) => m['id'] == widget.myId)) return widget.myId;
    return _people.isNotEmpty ? _people.first['id'] as int? : null;
  }

  @override
  void initState() {
    super.initState();
    for (final m in _people) {
      _values[m['id'] as int] = TextEditingController();
    }
    final e = widget.editData;
    if (e != null) {
      final type = (e['split_type'] ?? 'equal').toString();
      final splits = List<Map<String, dynamic>>.from(e['splits'] ?? const []);
      if (type == 'equal') {
        _mode = 'equal';
      } else {
        // An exact split of equal shares between some people reads back as "Equally".
        final amounts = {for (final s in splits) s['user_id']: double.tryParse('${s['amount'] ?? s['value']}') ?? 0};
        final nonZero = amounts.values.where((v) => v > 0.009).toList();
        final equalShares = type == 'exact' &&
            nonZero.isNotEmpty &&
            nonZero.every((v) => (v - nonZero.first).abs() <= 0.011 * nonZero.length);
        if (equalShares) {
          _mode = 'equal';
          for (final m in _people) {
            if ((amounts[m['id']] ?? 0) <= 0.009) _out.add(m['id'] as int);
          }
        } else {
          _mode = type == 'percentage' ? 'percentage' : 'exact';
          for (final s in splits) {
            final c = _values[s['user_id']];
            if (c != null) c.text = '${s['value'] ?? s['amount'] ?? ''}';
          }
        }
      }
    }
    _amount.addListener(() => setState(() {}));
    _tabs = TabController(length: 3, vsync: this, initialIndex: _modeIds.indexOf(_mode));
    _tabs.addListener(() {
      final m = _modeIds[_tabs.index];
      if (m != _mode) {
        setState(() {
          _mode = m;
          _error = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _amount.dispose();
    _desc.dispose();
    for (final c in _values.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _total => double.tryParse(_amount.text.trim()) ?? 0;
  List<Map<String, dynamic>> get _included => _people.where((m) => !_out.contains(m['id'])).toList();

  String _money(double v) {
    final f = NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: v == v.roundToDouble() ? 0 : 2);
    return '${widget.currencySymbol}${f.format(v)}';
  }

  double _valueOf(int id) => double.tryParse(_values[id]?.text.trim() ?? '') ?? 0;

  /// Equal shares in paise, the leftover paise going to the first people.
  Map<int, double> _equalShares() {
    final ids = _included.map((m) => m['id'] as int).toList();
    if (ids.isEmpty) return {};
    final paise = (_total * 100).round();
    final base = paise ~/ ids.length;
    var rest = paise - base * ids.length;
    return {
      for (final id in ids) id: (base + (rest-- > 0 ? 1 : 0)) / 100,
    };
  }

  String get _splitNote {
    if (_mode == 'equal') {
      final n = _included.length;
      return n == 0 ? 'Pick at least one person' : '${_money(_total / n)} each';
    }
    final sum = _people.fold<double>(0, (s, m) => s + _valueOf(m['id'] as int));
    if (_mode == 'exact') {
      final left = _total - sum;
      if (left.abs() < 0.01) return '${_money(sum)} of ${_money(_total)} ✓';
      return left > 0 ? '${_money(left)} left' : '${_money(-left)} too much';
    }
    final left = 100 - sum;
    if (left.abs() < 0.01) return '100% ✓';
    return left > 0 ? '${left.toStringAsFixed(left == left.roundToDouble() ? 0 : 1)}% left' : '${(-left).toStringAsFixed(0)}% too much';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      builder: pickerBuilder,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (day == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      builder: pickerBuilder,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (!mounted) return;
    final time = t ?? TimeOfDay.fromDateTime(_date);
    setState(() => _date = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    if (_saving) return;
    final desc = _desc.text.trim();
    if (_total <= 0) return _fail('Type the amount first.');
    if (desc.isEmpty) return _fail('Say what it was for.');
    if (_payer == null) return _fail('Pick who paid.');

    final body = <String, dynamic>{
      'description': desc,
      'amount': _total.toStringAsFixed(2),
      'date': _date.toUtc().toIso8601String(),
      'paid_by': _payer,
      'category': _cat.key,
    };
    if (_mode == 'equal') {
      if (_included.isEmpty) return _fail('Pick at least one person to split with.');
      if (_out.isEmpty) {
        body['split_type'] = 'equal';
      } else {
        final shares = _equalShares();
        body['split_type'] = 'exact';
        body['splits'] = [
          for (final m in _people)
            {'user_id': m['id'], 'value': (shares[m['id']] ?? 0).toStringAsFixed(2)},
        ];
      }
    } else {
      final sum = _people.fold<double>(0, (s, m) => s + _valueOf(m['id'] as int));
      if (_mode == 'exact' && (sum - _total).abs() > 0.01) {
        return _fail('The shares add up to ${_money(sum)}, but the bill is ${_money(_total)}.');
      }
      if (_mode == 'percentage' && (sum - 100).abs() > 0.01) {
        return _fail('The percentages add up to ${sum.toStringAsFixed(0)}%, they must make 100%.');
      }
      body['split_type'] = _mode;
      body['splits'] = [
        for (final m in _people)
          {'user_id': m['id'], 'value': _valueOf(m['id'] as int).toStringAsFixed(2)},
      ];
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final e = widget.editData;
    final r = e != null
        ? await ApiService.updateSplitExpense(widget.groupId, e['id'] as int, body)
        : await ApiService.addSplitExpense(widget.groupId, body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.isSuccess) {
      AppHaptics.confirm();
      Navigator.of(context).pop(true);
    } else {
      _fail(r.error ?? 'Could not save. Try again.');
    }
  }

  void _fail(String msg) {
    AppHaptics.warn();
    setState(() => _error = msg);
  }

  String get _payerName {
    final p = _people.where((m) => m['id'] == _payer).firstOrNull;
    if (p == null) return 'Someone';
    return p['id'] == widget.myId ? 'You' : (p['display_name'] ?? p['username'] ?? '').toString().split(' ').first;
  }

  // ─── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.dark,
        body: Column(
          children: [
            SafeArea(bottom: false, child: _top()),
            Expanded(child: _sheet()),
          ],
        ),
      ),
    );
  }

  Widget _circle(IconData icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: SpringPress(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: AppColors.darkCard, shape: BoxShape.circle),
            child: Icon(icon, size: 22, color: Colors.white),
          ),
        ),
      );

  Widget _top() {
    final when = DateUtils.isSameDay(_date, DateTime.now())
        ? 'Today, ${DateFormat('h:mm a').format(_date)}'
        : DateFormat('d MMM, h:mm a').format(_date);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
      child: Column(
        children: [
          Row(
            children: [
              _circle(Icons.close_rounded, 'Close', () => Navigator.of(context).pop(false)),
              Expanded(
                child: Text(
                  '${widget.groupName} · ${widget.editData == null ? 'new expense' : 'edit'}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
              const SizedBox(width: 44),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(widget.currencySymbol,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.darkFaint)),
              const SizedBox(width: 6),
              IntrinsicWidth(
                child: TextField(
                  controller: _amount,
                  autofocus: widget.editData == null,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,8}(\.\d{0,2})?'))],
                  cursorColor: AppColors.accent,
                  style: const TextStyle(
                      fontSize: 52, fontWeight: FontWeight.w800, letterSpacing: -2, color: Colors.white, height: 1.1),
                  decoration: const InputDecoration(
                    hintText: '0',
                    hintStyle: TextStyle(color: Color(0xFF5E635A)),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 48,
            decoration: BoxDecoration(color: AppColors.darkCard, borderRadius: BorderRadius.circular(24)),
            child: TextField(
              controller: _desc,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.sentences,
              cursorColor: AppColors.accent,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'What was it for?',
                hintStyle: const TextStyle(color: AppColors.darkFaint),
                prefixIcon: Icon(_cat.icon, size: 20, color: AppColors.accent),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _topChip(_cat.icon, _cat.label, _pickCategory, lit: true),
            const SizedBox(width: 8),
            _topChip(Icons.schedule_rounded, when, _pickDate),
          ]),
        ],
      ),
    );
  }

  Widget _topChip(IconData icon, String label, VoidCallback onTap, {bool lit = false}) => SpringPress(
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.only(left: 12, right: 10),
          decoration: BoxDecoration(
            color: lit ? AppColors.accent : AppColors.darkCard,
            borderRadius: BorderRadius.circular(19),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: lit ? AppColors.dark : Colors.white),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: lit ? AppColors.dark : Colors.white)),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 18, color: lit ? AppColors.dark : AppColors.darkMuted),
          ]),
        ),
      );

  /// All categories in a grid; tap one to pick it.
  void _pickCategory() {
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
            const Text('Category', style: AppText.section),
            const SizedBox(height: 14),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.95,
              children: [
                for (final c in groupCategories)
                  SpringPress(
                    onTap: () {
                      setState(() => _category = c.key);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.key == _cat.key ? AppColors.accent : AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(c.icon, size: 24, color: AppColors.dark),
                        const SizedBox(height: 6),
                        Text(c.label,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dark)),
                      ]),
                    ),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sheet() {
    return Container(
      clipBehavior: Clip.antiAlias, // scrolled content stays inside the rounded top
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxxl)),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
              children: [
                const Text('PAID BY', style: AppText.label),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: _people.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => _payerChip(_people[i]),
                  ),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  const Expanded(child: Text('SPLIT', style: AppText.label)),
                  Text(_splitNote, style: AppText.rowTitle.copyWith(fontSize: 12)),
                ]),
                const SizedBox(height: 8),
                _modes(),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(children: [
                    for (var i = 0; i < _people.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 12, endIndent: 12),
                      _personRow(_people[i]),
                    ],
                  ]),
                ),
                if (_mode == 'equal')
                  const Padding(
                    padding: EdgeInsets.fromLTRB(6, 8, 6, 0),
                    child: Text('Tap someone to leave them out of this bill.', style: AppText.rowSub),
                  ),
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
                child: Center(
                  child: _saving
                      ? const SizedBox(
                          width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.dark))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.check_rounded, size: 22, color: AppColors.dark),
                          const SizedBox(width: 8),
                          Text(
                            '${widget.editData == null ? 'Save' : 'Update'} · $_payerName paid, '
                            '${_included.length} ${_included.length == 1 ? 'person' : 'people'}',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.dark),
                          ),
                        ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _face(Map<String, dynamic> m, {double size = 32, bool on = false, bool chip = false}) {
    final me = m['id'] == widget.myId;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: on || me ? AppColors.accent : (chip ? Colors.white : AppColors.surface),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        (m['initial'] ?? (m['display_name'] ?? '?').toString().characters.first).toString(),
        style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w800, color: AppColors.dark),
      ),
    );
  }

  Widget _payerChip(Map<String, dynamic> m) {
    final on = m['id'] == _payer;
    final name = m['id'] == widget.myId ? 'You' : (m['display_name'] ?? m['username'] ?? '').toString().split(' ').first;
    return SpringPress(
      onTap: () => setState(() => _payer = m['id'] as int?),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 40,
        padding: const EdgeInsets.only(left: 4, right: 12),
        decoration: BoxDecoration(
          color: on ? AppColors.dark : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _face(m, on: on, chip: true),
          const SizedBox(width: 6),
          Text(name,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? Colors.white : AppColors.text)),
        ]),
      ),
    );
  }

  Widget _modes() => SpringTabs(
        controller: _tabs,
        labels: ['Equally', 'Exact ${widget.currencySymbol}', 'By %'],
        background: AppColors.surface,
        height: 46,
      );

  Widget _personRow(Map<String, dynamic> m) {
    final id = m['id'] as int;
    final name = id == widget.myId ? 'You' : (m['display_name'] ?? m['username'] ?? '').toString();
    final included = !_out.contains(id);
    Widget trailing;
    if (_mode == 'equal') {
      final share = _equalShares()[id];
      trailing = Text(share == null ? '—' : _money(share),
          style: AppText.amount.copyWith(color: included ? AppColors.text : AppColors.mutedLight));
    } else {
      trailing = SizedBox(
        width: 96,
        height: 38,
        child: TextField(
          controller: _values[id],
          onChanged: (_) => setState(() => _error = null),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,8}(\.\d{0,2})?'))],
          textAlign: TextAlign.right,
          style: AppText.amount,
          decoration: InputDecoration(
            hintText: '0',
            prefixText: _mode == 'exact' ? widget.currencySymbol : null,
            suffixText: _mode == 'percentage' ? '%' : null,
            filled: true,
            fillColor: AppColors.surface,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.dark, width: 1.5)),
          ),
        ),
      );
    }
    void toggle() => setState(() {
          if (included) {
            _out.add(id);
          } else {
            _out.remove(id);
          }
          _error = null;
        });
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        if (_mode == 'equal') ...[
          Semantics(
            checked: included,
            label: 'Include $name',
            child: SpringPress(
              onTap: toggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: included ? AppColors.dark : AppColors.card,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: included ? AppColors.dark : AppColors.mutedLight, width: 2),
                ),
                child: included ? Icon(Icons.check_rounded, size: 18, color: AppColors.accent) : null,
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        _face(m, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.rowTitle.copyWith(color: included || _mode != 'equal' ? AppColors.text : AppColors.mutedLight)),
        ),
        trailing,
      ]),
    );
    if (_mode != 'equal') return row;
    return InkWell(
      onTap: () {
        AppHaptics.tap();
        toggle();
      },
      child: row,
    );
  }
}

/// Categories a group expense can have: key, label, icon, and words that suggest it.
class GroupCategory {
  final String key;
  final String label;
  final IconData icon;
  final List<String> words;
  const GroupCategory(this.key, this.label, this.icon, this.words);
}

const groupCategories = <GroupCategory>[
  GroupCategory('food', 'Food', Icons.restaurant_rounded,
      ['dinner', 'lunch', 'breakfast', 'food', 'restaurant', 'meal', 'pizza', 'biryani', 'snack', 'thali', 'khana', 'zomato', 'swiggy']),
  GroupCategory('cafe', 'Cafe', Icons.local_cafe_rounded, ['coffee', 'tea', 'chai', 'cafe']),
  GroupCategory('groceries', 'Groceries', Icons.local_grocery_store_rounded,
      ['grocery', 'groceries', 'vegetable', 'sabzi', 'milk', 'doodh', 'dahi', 'curd', 'mart', 'ration', 'fruit', 'atta', 'eggs']),
  GroupCategory('travel', 'Travel', Icons.flight_rounded, ['flight', 'plane', 'train', 'rail', 'bus', 'trip', 'ticket']),
  GroupCategory('transport', 'Cab', Icons.local_taxi_rounded,
      ['cab', 'taxi', 'uber', 'ola', 'auto', 'ride', 'scooter', 'bike', 'rapido', 'metro', 'parking', 'toll']),
  GroupCategory('fuel', 'Fuel', Icons.local_gas_station_rounded, ['fuel', 'petrol', 'diesel', 'gas', 'cng']),
  GroupCategory('stay', 'Stay', Icons.hotel_rounded, ['hotel', 'stay', 'room', 'airbnb', 'hostel', 'resort']),
  GroupCategory('fun', 'Fun', Icons.local_activity_rounded,
      ['movie', 'cinema', 'show', 'game', 'party', 'drink', 'beer', 'bar', 'club', 'netflix']),
  GroupCategory('shopping', 'Shopping', Icons.shopping_bag_rounded, ['shop', 'shopping', 'clothes', 'gift', 'amazon', 'flipkart']),
  GroupCategory('home', 'Rent', Icons.home_rounded, ['rent', 'house', 'flat', 'maid', 'cook']),
  GroupCategory('bills', 'Bills', Icons.receipt_rounded,
      ['electric', 'bill', 'wifi', 'internet', 'recharge', 'water', 'cylinder']),
  GroupCategory('health', 'Health', Icons.medical_services_rounded, ['medicine', 'doctor', 'hospital', 'pharmacy']),
  GroupCategory('other', 'Other', Icons.receipt_long_rounded, []),
];

GroupCategory? groupCategoryByKey(String? key) =>
    key == null || key.isEmpty ? null : groupCategories.where((c) => c.key == key).firstOrNull;

/// The category the words suggest, or null.
GroupCategory? guessGroupCategory(String text) {
  final t = text.toLowerCase();
  for (final c in groupCategories) {
    if (c.words.any(t.contains)) return c;
  }
  return null;
}

/// A fitting icon for an expense from its words.
IconData expenseIcon(String text) => guessGroupCategory(text)?.icon ?? Icons.receipt_long_rounded;

/// The icon for a saved expense: its category, else a guess from its words.
IconData groupExpenseIcon(Map<String, dynamic> e) =>
    groupCategoryByKey(e['category']?.toString())?.icon ?? expenseIcon('${e['description'] ?? ''}');
