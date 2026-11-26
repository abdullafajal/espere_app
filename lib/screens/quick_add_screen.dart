/// Quick add: type the amount on the keypad, tap a category, done.
///
/// Tapping a category saves at once (no separate Save button) and shows "Added · Undo".
/// Time, payment method and note have sensible defaults (now, the last method used, empty)
/// and can be changed with the chips under the amount. "Scan" reads a receipt screenshot;
/// "New" opens Categories.
///
/// The same screen edits a transaction ([QuickAddScreen.edit]) and checks what was read
/// from a receipt ([QuickAddScreen.prefilled]): then tapping a category only selects it,
/// and the lime Save button stores the change.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/category.dart';
import '../models/transaction.dart';
import '../services/cache_service.dart';
import '../services/receipt_service.dart';
import '../services/transaction_store.dart';
import '../theme/app_theme.dart';
import '../utils/pickers.dart';
import '../theme/motion.dart';
import '../utils/app_toast.dart';
import '../utils/icon_mapper.dart';
import '../services/budget_service.dart';

class QuickAddScreen extends StatefulWidget {
  /// 'expense' (default) or 'income'.
  final String type;

  /// Transaction being edited (by id; looked up in the cache).
  final int? editId;

  /// Values read from a receipt, to check and save.
  final TransactionPrefill? prefill;

  const QuickAddScreen({super.key, this.type = 'expense', this.editId, this.prefill});

  /// Opens Quick add full screen. Resolves to true when something was added.
  static Future<bool> open(BuildContext context, {String type = 'expense'}) async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => QuickAddScreen(type: type), fullscreenDialog: true),
    );
    return added == true;
  }

  /// Opens the transaction [id] for editing. Resolves to true when it was saved or deleted.
  static Future<bool> edit(BuildContext context, int id) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => QuickAddScreen(editId: id), fullscreenDialog: true),
    );
    return saved == true;
  }

  /// Opens with values read from a receipt. Resolves to true when it was saved.
  static Future<bool> prefilled(BuildContext context, TransactionPrefill prefill) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => QuickAddScreen(type: prefill.type, prefill: prefill),
        fullscreenDialog: true,
      ),
    );
    return saved == true;
  }

  @override
  State<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends State<QuickAddScreen> {
  static const _kMethod = 'quick_add_payment_method';
  static const _methods = [
    ('upi', 'UPI', Icons.account_balance_wallet_rounded),
    ('cash', 'Cash', Icons.payments_rounded),
    ('card', 'Card', Icons.credit_card_rounded),
    ('bank', 'Bank', Icons.account_balance_rounded),
    ('other', 'Other', Icons.more_horiz_rounded),
  ];

  late String _type = widget.type;
  String _amount = '';
  DateTime? _date; // null = now
  String _method = 'upi';
  String _note = '';
  String _symbol = '₹';

  List<CategoryModel> _categories = const [];

  /// This month's category budgets, to show what is left under each category.
  Map<int, BudgetInfo> _budgets = const {};
  bool _loading = true;

  _Saved? _saved;
  Timer? _savedTimer;
  bool _addedAny = false;
  bool _busy = false;

  /// Edit / receipt mode: a category tap selects, Save stores.
  bool get _formMode => widget.editId != null || widget.prefill != null;
  bool get _isEdit => widget.editId != null;
  static const bool _pickThenSave = true;
  TransactionModel? _old;
  int? _categoryId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _savedTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = await CacheService.getCachedCategories();
    TransactionModel? old;
    if (_isEdit) {
      old = await TransactionStore.find(widget.editId!);
      if (old != null) _type = old.type;
    }
    final cats = await TransactionStore.categoriesByUse(_type);
    if (!mounted) return;
    if (_isEdit && old == null) {
      AppToast.error(context, 'This transaction is not on this phone yet. Pull to refresh and try again.');
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _method = prefs.getString(_kMethod) ?? 'upi';
      final p = widget.prefill;
      if (old != null) {
        _old = old;
        _amount = _trim(double.tryParse(old.amount) ?? 0);
        _date = old.date.toLocal();
        _method = old.paymentMethod;
        _note = old.notes;
        _categoryId = old.category.id == 0 ? null : old.category.id;
      } else if (p != null) {
        if (p.amount != null) _amount = _trim(p.amount!);
        _date = p.date;
        _method = p.paymentMethod;
        _note = p.notes ?? '';
        _categoryId = p.categoryId;
      }
      _symbol = cached?['currency_symbol'] as String? ?? '₹';
      _categories = cats;
      _loading = false;
    });
    final budgets = await BudgetService.byCategory();
    if (mounted) setState(() => _budgets = budgets);
  }

  /// How full [categoryId]'s budget would be with this entry (counting an edited entry once).
  /// Null when the category has no budget or this is income.
  BudgetInfo? _after(int? categoryId) {
    if (_type != 'expense' || categoryId == null) return null;
    final b = _budgets[categoryId];
    if (b == null || b.limit <= 0) return null;
    final old = _old;
    var spent = b.spent;
    if (old != null && !old.isIncome && old.category.id == categoryId && old.date.toLocal().month == DateTime.now().month) {
      spent -= double.tryParse(old.amount) ?? 0;
    }
    return BudgetInfo(name: b.name, limit: b.limit, spent: spent + _value);
  }

  Future<void> _setType(String type) async {
    if (type == _type) return;
    AppHaptics.tap();
    setState(() {
      _type = type;
      _categoryId = null;
    });
    final cats = await TransactionStore.categoriesByUse(type);
    if (mounted) setState(() => _categories = cats);
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  double get _value => double.tryParse(_amount) ?? 0;
  bool get _hasAmount => _value > 0;

  void _press(String key) {
    AppHaptics.press();
    var a = _amount;
    if (key == 'back') {
      if (a.isEmpty) return;
      a = a.substring(0, a.length - 1);
    } else if (key == '.') {
      if (a.contains('.')) return;
      a = a.isEmpty ? '0.' : '$a.';
    } else {
      if (a.contains('.') && a.split('.')[1].length >= 2) return;
      if (a.replaceAll('.', '').length >= 8) return;
      a = (a == '0' ? '' : a) + key;
    }
    setState(() {
      _amount = a;
      if (_saved != null) _dismissSaved();
    });
  }

  String get _amountLabel {
    if (_amount.isEmpty) return '0';
    final parts = _amount.split('.');
    final whole = NumberFormat.decimalPattern('en_IN').format(int.tryParse(parts[0]) ?? 0);
    return parts.length > 1 ? '$whole.${parts[1]}' : whole;
  }

  Future<void> _save(CategoryModel? category) async {
    // New entries work like edit too: tap a category to pick it, then the Add button saves.
    if (_formMode || _pickThenSave) {
      final after = _after(category?.id);
      if (after != null && after.fraction >= 0.8) {
        AppHaptics.warn();
      } else {
        AppHaptics.tap();
      }
      setState(() => _categoryId = category?.id);
      return;
    }
    if (_busy) return;
    if (!_hasAmount) {
      AppHaptics.warn();
      AppToast.info(context, 'Type the amount first');
      return;
    }
    _busy = true;
    AppHaptics.confirm();
    final amount = _value;
    try {
      final id = await TransactionStore.create(
        amount: amount,
        type: _type,
        category: category,
        date: _date,
        paymentMethod: _method,
        notes: _note.trim(),
      );
      (await SharedPreferences.getInstance()).setString(_kMethod, _method);
      _addedAny = true;
      if (!mounted) return;
      final sign = _type == 'income' ? '+' : '−';
      setState(() {
        _saved = _Saved(
          id: id,
          amount: _amount,
          text: '$sign$_symbol$_amountLabel added to ${category?.name ?? 'Other'}',
        );
        _amount = '';
        _note = '';
        _date = null;
      });
      _savedTimer?.cancel();
      _savedTimer = Timer(const Duration(seconds: 5), _dismissSaved);
    } finally {
      _busy = false;
    }
  }

  /// Edit / receipt mode: store the values.
  Future<void> _commit() async {
    if (_busy) return;
    if (!_hasAmount) {
      AppHaptics.warn();
      AppToast.info(context, 'Type the amount first');
      return;
    }
    _busy = true;
    AppHaptics.confirm();
    final category = _categories.where((c) => c.id == _categoryId).firstOrNull;
    try {
      if (_old != null) {
        await TransactionStore.update(
          old: _old!,
          amount: _value,
          type: _type,
          category: category,
          date: _date ?? DateTime.now(),
          paymentMethod: _method,
          notes: _note.trim(),
        );
      } else {
        await TransactionStore.create(
          amount: _value,
          type: _type,
          category: category,
          date: _date,
          paymentMethod: _method,
          notes: _note.trim(),
        );
        (await SharedPreferences.getInstance()).setString(_kMethod, _method);
      }
      if (!mounted) return;
      AppToast.success(context, _old != null ? 'Saved' : 'Added');
      Navigator.of(context).pop(true);
    } finally {
      _busy = false;
    }
  }

  Future<void> _delete() async {
    final old = _old;
    if (old == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text('${old.isIncome ? '+' : '−'}$_symbol$_amountLabel will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    AppHaptics.confirm();
    await TransactionStore.remove(old.id);
    if (!mounted) return;
    AppToast.success(context, 'Deleted');
    Navigator.of(context).pop(true);
  }

  void _dismissSaved() {
    _savedTimer?.cancel();
    if (mounted && _saved != null) setState(() => _saved = null);
  }

  Future<void> _undo() async {
    final s = _saved;
    if (s == null) return;
    AppHaptics.confirm();
    _savedTimer?.cancel();
    setState(() {
      _saved = null;
      _amount = s.amount;
    });
    await TransactionStore.remove(s.id);
  }

  /// Date, then time (the two standard pickers).
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final base = _date ?? now;
    final day = await showDatePicker(
      context: context,
      builder: pickerBuilder,
      initialDate: base,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      builder: pickerBuilder,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (!mounted) return;
    final t = time ?? TimeOfDay.fromDateTime(base);
    setState(() => _date = DateTime(day.year, day.month, day.day, t.hour, t.minute));
  }

  Future<void> _pickMethod() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Paid with', style: AppText.section),
              const SizedBox(height: 8),
              for (final m in _methods)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                    child: Icon(m.$3, size: 20, color: AppColors.dark),
                  ),
                  title: Text(m.$2, style: AppText.rowTitle),
                  trailing: m.$1 == _method ? const Icon(Icons.check_rounded, color: AppColors.dark) : null,
                  onTap: () => Navigator.pop(ctx, m.$1),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _method = picked);
  }

  Future<void> _editNote() async {
    final controller = TextEditingController(text: _note);
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Lunch with team'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Done')),
        ],
      ),
    );
    if (note != null && mounted) setState(() => _note = note);
  }

  Future<void> _scan() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final scan = await ReceiptService.recognize(picked.path);
    if (!mounted) return;
    if (scan == null) {
      AppToast.error(context, 'Could not read text from this image.');
      return;
    }
    await ReceiptService.openForm(context, scan: scan);
  }

  Future<void> _newCategory() async {
    await Navigator.of(context).pushNamed('/categories');
    final cats = await TransactionStore.categoriesByUse(_type);
    if (mounted) setState(() => _categories = cats);
  }

  void _close() => Navigator.of(context).pop(_formMode ? false : _addedAny);

  // ─── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: AppColors.dark,
          body: Stack(
            children: [
              Column(
                children: [
                  SafeArea(bottom: false, child: _top()),
                  Expanded(child: _sheet()),
                ],
              ),
              if (_saved != null) _savedBanner(_saved!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _circle(IconData icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
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

  Widget _typeButton(String type, String label) {
    final on = _type == type;
    return Semantics(
      selected: on,
      button: true,
      child: SpringPress(
        haptic: HapticKind.none,
        onTap: () => _setType(type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? AppColors.dark : AppColors.darkMuted),
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, VoidCallback onTap) => SpringPress(
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.only(left: 10, right: 12),
          decoration: BoxDecoration(color: AppColors.darkCard, borderRadius: BorderRadius.circular(18)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: Colors.white),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _top() {
    final method = _methods.firstWhere((m) => m.$1 == _method, orElse: () => _methods.first);
    final dateLabel = _date == null
        ? 'Now'
        : (DateUtils.isSameDay(_date, DateTime.now())
            ? DateFormat('h:mm a').format(_date!)
            : DateFormat('d MMM, h:mm a').format(_date!));
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
      child: Column(
        children: [
          Row(
            children: [
              _circle(Icons.close_rounded, 'Close', _close),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: AppColors.darkCard, borderRadius: BorderRadius.circular(22)),
                child: Row(children: [_typeButton('expense', 'Expense'), _typeButton('income', 'Income')]),
              ),
              const Spacer(),
              if (_isEdit)
                _circle(Icons.delete_outline_rounded, 'Delete', _delete)
              else if (_formMode)
                const SizedBox(width: 44)
              else
                _circle(Icons.document_scanner_rounded, 'Scan receipt', _scan),
            ],
          ),
          const SizedBox(height: 18),
          Semantics(
            liveRegion: true,
            label: 'Amount $_symbol$_amountLabel',
            excludeSemantics: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(_symbol, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.darkFaint)),
                  const SizedBox(width: 6),
                  Text(
                    _amountLabel,
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -2,
                      height: 1.05,
                      color: _amount.isEmpty ? const Color(0xFF5E635A) : Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const _Cursor(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formMode
                ? (_isEdit ? 'Change anything, then Save' : 'Check the details, then Save')
                : (_hasAmount ? 'Pick a category, then Add' : 'Type the amount'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _hasAmount ? AppColors.accent : AppColors.darkFaint,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(Icons.schedule_rounded, dateLabel, _pickDate),
              _chip(method.$3, method.$2, _pickMethod),
              _chip(Icons.edit_note_rounded, _note.trim().isEmpty ? 'Note' : _note.trim(), _editNote),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sheet() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxxl)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 6),
            child: Row(
              children: [
                Expanded(
                  child: const Text('Category', style: AppText.section),
                ),
                Text(
                  _categories.length > 8 ? '${_categories.length} · scroll' : '${_categories.length}',
                  style: AppText.rowSub,
                ),
              ],
            ),
          ),
          Expanded(child: _grid()),
          _budgetNote(),
          _saveBar(),
          _keypad(),
        ],
      ),
    );
  }

  Widget _grid() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final tiles = <Widget>[
      for (final c in _categories)
        _categoryTile(c.name, IconMapper.map(c.icon), () => _save(c),
            selected: c.id == _categoryId, budget: _type == 'expense' ? _budgets[c.id] : null),
      _categoryTile('New', Icons.add_rounded, _newCategory, dashed: true),
    ];
    if (_categories.isEmpty) {
      tiles.insert(0, _categoryTile('Other', Icons.more_horiz_rounded, () => _save(null)));
    }
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: _hasAmount || _formMode ? 1 : 0.5,
      child: GridView.count(
        crossAxisCount: 4,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        // Taller tiles when they also show a budget line.
        childAspectRatio: _type == 'expense' && _budgets.isNotEmpty ? 0.78 : 0.92,
        children: tiles,
      ),
    );
  }

  Widget _categoryTile(String label, IconData icon, VoidCallback onTap,
      {bool dashed = false, bool selected = false, BudgetInfo? budget}) {
    return Semantics(
      button: true,
      selected: selected,
      label: dashed ? 'New category' : label,
      excludeSemantics: true,
      child: SpringPress(
        haptic: dashed ? HapticKind.tap : HapticKind.none,
        scale: 0.9,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: dashed ? Colors.transparent : (selected ? AppColors.dark : AppColors.categoryFill),
                borderRadius: BorderRadius.circular(18),
                border: dashed ? Border.all(color: AppColors.mutedLight, width: 1.5) : null,
              ),
              child: Icon(icon, size: 24, color: selected ? AppColors.accent : AppColors.categoryInk),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.text),
            ),
            if (budget != null && budget.limit > 0) ...[
              const SizedBox(height: 4),
              Container(
                width: 40,
                height: 3,
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(2)),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: budget.fraction.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected ? AppColors.accent : AppColors.dark,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                budget.spent > budget.limit ? '${_moneyShort(budget.spent - budget.limit)} over' : '${_moneyShort(budget.left)} left',
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _moneyShort(double v) =>
      '$_symbol${NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0).format(v.round())}';

  /// Above the Add button: how full the picked category's budget gets with this entry,
  /// once that reaches 80%.
  Widget _budgetNote() {
    final after = _after(_categoryId);
    if (after == null || after.fraction < 0.8 || !_hasAmount) return const SizedBox.shrink();
    final over = after.spent > after.limit;
    final text = over
        ? 'After this, ${after.name} will be ${_moneyShort(after.spent - after.limit)} over budget'
        : 'After this, ${after.name} will be ${after.percent}% used · ${_moneyShort(after.left)} left';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  maxLines: 2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _saveBar() {
    final cat = _categories.where((c) => c.id == _categoryId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton.icon(
          onPressed: _commit,
          icon: const Icon(Icons.check_rounded),
          label: Text(
            '${_isEdit ? 'Save' : 'Add'} ${_type == 'income' ? '+' : '−'}$_symbol$_amountLabel'
            '${cat != null ? ' · ${cat.name}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _keypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', 'back'];
    return Container(
      color: AppColors.background,
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        // Without this the grid adds the status-bar and gesture-bar insets again, which
        // left a large gap between the Save button and the keys.
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.3,
        children: [
          for (final k in keys)
            Semantics(
              button: true,
              label: k == 'back' ? 'Delete digit' : k,
              excludeSemantics: true,
              child: SpringPress(
                haptic: HapticKind.none, // _press gives the key tick
                scale: 0.92,
                onTap: () => _press(k),
                onLongPress: k == 'back' ? () => setState(() => _amount = '') : null,
                child: Container(
                  decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
                  alignment: Alignment.center,
                  child: k == 'back'
                      ? const Icon(Icons.backspace_outlined, size: 24, color: AppColors.dark)
                      : Text(k, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.dark)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _savedBanner(_Saved s) {
    return Positioned(
      left: 16,
      right: 16,
      top: MediaQuery.of(context).padding.top + 236,
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: AppShadows.elevated,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(color: AppColors.dark, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded, size: 20, color: AppColors.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dark),
                ),
              ),
              const SizedBox(width: 8),
              SpringPress(
                haptic: HapticKind.none,
                onTap: _undo,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.dark, borderRadius: BorderRadius.circular(18)),
                  child: const Text('Undo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Saved {
  final int id;
  final String amount;
  final String text;
  const _Saved({required this.id, required this.amount, required this.text});
}

/// Blinking lime caret next to the amount.
class _Cursor extends StatefulWidget {
  const _Cursor();

  @override
  State<_Cursor> createState() => _CursorState();
}

class _CursorState extends State<_Cursor> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(
        width: 3,
        height: 46,
        decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2)),
      ),
    );
  }
}
