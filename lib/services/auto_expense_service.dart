/// Auto-track payments: turns payment notifications into transactions, on device.
///
/// Flow: native listener → encrypted queue → [drain] → [NotificationParser] →
/// [AutoDedupEngine] → same insert path as the manual form (cache + optimistic dashboard +
/// SyncService.queueOperation). High-confidence payments are added; low-confidence ones go
/// to the Review list. Off by default; enabled only after the Prominent Disclosure and the
/// system Notification-access permission.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auto_capture_channel.dart';
import 'auto_capture_store.dart';
import 'auto_category_rules.dart';
import 'auto_dedup_engine.dart';
import 'cache_service.dart';
import 'connectivity_service.dart';
import 'notification_parser.dart';
import 'sync_service.dart';
import 'widget_service.dart';

class AutoTrackSettings {
  final bool enabled;
  final bool consent;
  final bool permissionGranted;
  final bool includeIncome;
  final bool notifyOnAdd;
  final Set<String> disabledSources;

  const AutoTrackSettings({
    required this.enabled,
    required this.consent,
    required this.permissionGranted,
    required this.includeIncome,
    required this.notifyOnAdd,
    required this.disabledSources,
  });
}

/// One item of the Review list (parsed fields only).
class ReviewItem {
  final String id;
  final AutoTxn txn;
  const ReviewItem(this.id, this.txn);
}

class AutoExpenseService {
  AutoExpenseService._();

  static const _kEnabled = 'auto_track_enabled';
  static const _kConsent = 'auto_track_consent';
  static const _kIncome = 'auto_track_income';
  static const _kNotify = 'auto_track_notify';
  static const _kDisabled = 'auto_track_disabled_sources';

  /// Set once the local store was ever created (so hooks don't open it needlessly).
  static const _kUsed = 'auto_track_used';

  static AutoCaptureStore? _store;
  static AutoDedupEngine? _engine;
  static final _sink = _AppSink();
  static StreamSubscription<void>? _eventsSub;
  static Future<void>? _draining;
  static bool _drainAgain = false;

  /// True while auto-capture itself deletes an entry (a reversed payment), so the
  /// SyncService delete hook does not re-enter the dedup lock.
  static bool _removingOwnEntry = false;

  /// Emits whenever entries were added or the Review list changed (for UI refresh).
  static final _changes = StreamController<void>.broadcast();
  static Stream<void> get changes => _changes.stream;

  static bool get isSupported => AutoCaptureChannel.isSupported;

  static bool? _available;

  /// Android build that includes the notification listener. Website (sideloaded) APKs do not,
  /// because Play Protect blocks installing them otherwise; the feature is hidden there.
  static Future<bool> isAvailable() async {
    if (!isSupported) return false;
    return _available ??= await AutoCaptureChannel.isAvailable();
  }

  // ─── Setup ────────────────────────────────────────────────────────────────

  /// Called once at app start. Wires the delete / id-change hooks and, if the feature is
  /// on, starts listening and drains anything queued while the app was closed.
  static Future<void> init() async {
    if (!await isAvailable()) return;
    SyncService.onTransactionDeleted = onTransactionDeleted;
    SyncService.onTransactionIdChanged = onTransactionIdChanged;
    // Always bring the native listener in line with the saved state (self-healing).
    if (await _savedEnabled()) {
      await _start();
    } else {
      await _pushConfig(enabled: false);
    }
  }

  /// The saved on/off state, read fresh from disk.
  ///
  /// Other parts of the app call `prefs.reload()` often; a reload racing with a write can
  /// briefly hand back the old in-memory value, so never trust a value read right after
  /// writing it. (That race once left the native listener switched off while the app
  /// showed "On".)
  static Future<bool> _savedEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool(_kEnabled) ?? false;
  }

  /// App came back to the foreground (e.g. from the Notification-access screen).
  static Future<void> onResume() async {
    if (!await isAvailable()) return;
    await refreshPermissionState();
    // Self-heal: re-send the saved state to the native listener on every resume.
    final enabled = await _savedEnabled();
    await _pushConfig(enabled: enabled);
    if (enabled) {
      _eventsSub ??= AutoCaptureChannel.newEvents.listen((_) => drain());
    }
    await drain();
  }

  static Future<AutoDedupEngine> _getEngine() async {
    if (_engine != null) return _engine!;
    _store ??= await AutoCaptureStore.open();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUsed, true);
    return _engine = AutoDedupEngine(_store!, _sink);
  }

  static Future<void> _start() async {
    await _pushConfig(enabled: true);
    _eventsSub ??= AutoCaptureChannel.newEvents.listen((_) => drain());
    final engine = await _getEngine();
    final recovered = await engine.recover();
    if (recovered > 0) _afterInsert();
    await drain();
  }

  /// Sends the on/off state and disabled sources to the native listener. Callers pass the
  /// values they just decided on instead of re-reading them (see [_savedEnabled]).
  static Future<void> _pushConfig({required bool enabled, Set<String>? disabledSources}) async {
    final disabled = disabledSources ??
        ((await SharedPreferences.getInstance()).getStringList(_kDisabled) ?? const <String>[])
            .toSet();
    await AutoCaptureChannel.setConfig(enabled: enabled, disabledGroups: disabled.toList());
  }

  // ─── Settings ─────────────────────────────────────────────────────────────

  static Future<AutoTrackSettings> settings() async {
    final prefs = await SharedPreferences.getInstance();
    return AutoTrackSettings(
      enabled: prefs.getBool(_kEnabled) ?? false,
      consent: prefs.getBool(_kConsent) ?? false,
      permissionGranted: await AutoCaptureChannel.isPermissionGranted(),
      includeIncome: prefs.getBool(_kIncome) ?? false,
      notifyOnAdd: prefs.getBool(_kNotify) ?? true,
      disabledSources: (prefs.getStringList(_kDisabled) ?? const []).toSet(),
    );
  }

  /// The user tapped "Allow" in the Prominent Disclosure: remember the consent and open
  /// the system Notification-access screen. The feature turns on when the user returns
  /// with access granted (see [refreshPermissionState]).
  static Future<void> acceptDisclosure() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kConsent, true);
    if (await AutoCaptureChannel.isPermissionGranted()) {
      await refreshPermissionState();
    } else {
      await AutoCaptureChannel.openPermissionSettings();
    }
  }

  /// Enables the feature once consent + permission are both present; pauses native
  /// capture if the permission was revoked.
  static Future<void> refreshPermissionState() async {
    final prefs = await SharedPreferences.getInstance();
    final consent = prefs.getBool(_kConsent) ?? false;
    final enabled = prefs.getBool(_kEnabled) ?? false;
    final granted = await AutoCaptureChannel.isPermissionGranted();
    if (consent && granted && !enabled) {
      await prefs.setBool(_kEnabled, true);
      await _start();
      _changes.add(null);
    }
  }

  static Future<void> setIncludeIncome(bool value) async {
    (await SharedPreferences.getInstance()).setBool(_kIncome, value);
    _changes.add(null);
  }

  static Future<void> setNotifyOnAdd(bool value) async {
    (await SharedPreferences.getInstance()).setBool(_kNotify, value);
  }

  static Future<void> setSourceEnabled(String group, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final set = (prefs.getStringList(_kDisabled) ?? const <String>[]).toSet();
    enabled ? set.remove(group) : set.add(group);
    await prefs.setStringList(_kDisabled, set.toList());
    await _pushConfig(enabled: await _savedEnabled(), disabledSources: set);
    _changes.add(null);
  }

  /// "Turn off & delete local data": stops capture and wipes the native queue, all
  /// fingerprints, the Review list and the per-payee category memory. Transactions that
  /// were already added stay in the account.
  static Future<void> turnOffAndDeleteLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, false);
    await prefs.setBool(_kConsent, false);
    await AutoCaptureChannel.setConfig(enabled: false, disabledGroups: const []);
    await AutoCaptureChannel.clearAll();
    await _eventsSub?.cancel();
    _eventsSub = null;
    final store = await _storeIfUsed();
    await store?.clearAll();
    _changes.add(null);
  }

  static Future<AutoCaptureStore?> _storeIfUsed() async {
    if (_store != null) return _store;
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_kUsed) ?? false)) return null;
    return _store = await AutoCaptureStore.open();
  }

  // ─── Draining the native queue ────────────────────────────────────────────

  /// Processes every pending event. Re-entrant calls are coalesced into one more pass.
  static Future<void> drain() {
    if (_draining != null) {
      _drainAgain = true;
      return _draining!;
    }
    final run = _drainLoop().whenComplete(() => _draining = null);
    _draining = run;
    return run;
  }

  static Future<void> _drainLoop() async {
    do {
      _drainAgain = false;
      await _drainOnce();
    } while (_drainAgain);
  }

  static Future<void> _drainOnce() async {
    if (!await _savedEnabled()) return;
    final s = await settings();

    final events = await AutoCaptureChannel.getPendingEvents();
    if (events.isEmpty) return;

    final engine = await _getEngine();
    final acked = <String>[];
    var added = false;
    var reviewChanged = false;

    for (final ev in events) {
      final id = (ev['id'] ?? '').toString();
      try {
        final raw = RawNotification.fromMap(ev);
        final textHash = AutoDedupEngine.textHashOf(raw.title, raw.text, raw.bigText);
        final r = NotificationParser.parse(raw);
        // Refunds always get a look: they may cancel an auto expense even when only
        // expenses are tracked.
        final wanted = r != null &&
            !s.disabledSources.contains(raw.group) &&
            (r.type == 'expense' || s.includeIncome || r.isReversal);
        if (wanted) {
          final categoryId = await _resolveCategory(r);
          _sink.notifyOnInsert = s.notifyOnAdd;
          final outcome = await engine.process(r,
              notificationKey: raw.key,
              textHash: textHash,
              categoryId: categoryId,
              allowIncome: s.includeIncome);
          _sink.notifyOnInsert = false;
          if (outcome == AutoOutcome.added ||
              outcome == AutoOutcome.promoted ||
              outcome == AutoOutcome.reversed) {
            added = true;
          }
          if (outcome == AutoOutcome.review ||
              outcome == AutoOutcome.promoted ||
              outcome == AutoOutcome.reversed) {
            reviewChanged = true;
          }
        }
        acked.add(id); // processed (or deliberately ignored): drop the raw event now
      } catch (e) {
        // Keep the event for the next pass. Never log notification content.
        _sink.notifyOnInsert = false;
        debugPrint('[AutoExpense] event failed: ${e.runtimeType}');
      }
    }

    await AutoCaptureChannel.ackEvents(acked);
    if (added) _afterInsert();
    if (added || reviewChanged) _changes.add(null);
  }

  static void _afterInsert() {
    WidgetService.refreshAllWidgets();
    if (ConnectivityService.isOnline) SyncService.syncAll();
  }

  // ─── Categories ───────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> _categories() async {
    final cached = await CacheService.getCachedCategories();
    return List<Map<String, dynamic>>.from(cached?['categories'] ?? const []);
  }

  static Future<int?> _resolveCategory(ParseResult r) async {
    final store = await _storeIfUsed();
    final remembered = r.payee == null ? null : await store?.categoryForPayee(r.payee!);
    return AutoCategoryRules.pick(
      payee: r.payee,
      type: r.type,
      categories: await _categories(),
      rememberedId: remembered,
    );
  }

  /// The user edited an entry: if it was auto-tracked, remember its category for the payee.
  static Future<void> learnFromEdit({required int? txnId, required int? categoryId}) async {
    if (txnId == null || categoryId == null) return;
    final store = await _storeIfUsed();
    if (store == null) return;
    final payee = await store.payeeForTxn(txnId);
    if (payee == null || payee.isEmpty) return;
    await store.rememberCategory(payee, categoryId);
  }

  // ─── Review list ──────────────────────────────────────────────────────────

  static Future<List<ReviewItem>> reviewItems() async {
    final store = await _storeIfUsed();
    if (store == null) return const [];
    return (await store.reviews())
        .map((m) => ReviewItem(m['review_id'] as String, AutoTxn.fromJson(m)))
        .toList();
  }

  static Future<int> reviewCount() async => (await reviewItems()).length;

  static Future<void> confirmReview(ReviewItem item, {int? categoryId}) async {
    final engine = await _getEngine();
    final txn = await engine.confirmReview(item.id, categoryId: categoryId);
    if (txn != null && categoryId != null && txn.payee != null) {
      await _store?.rememberCategory(txn.payee!, categoryId);
    }
    _afterInsert();
    _changes.add(null);
  }

  static Future<void> discardReview(ReviewItem item) async {
    final engine = await _getEngine();
    await engine.discardReview(item.id);
    _changes.add(null);
  }

  static Future<List<Map<String, dynamic>>> categoriesFor(String type) async =>
      (await _categories()).where((c) => (c['type'] ?? 'expense') == type).toList();

  // ─── Hooks from SyncService ───────────────────────────────────────────────

  static Future<void> onTransactionDeleted(int id) async {
    if (_removingOwnEntry) return; // the engine already marked it
    if (await _storeIfUsed() == null) return;
    await (await _getEngine()).markDeleted(id);
  }

  static Future<void> onTransactionIdChanged(int oldId, int newId) async {
    if (await _storeIfUsed() == null) return;
    await (await _getEngine()).remap(oldId, newId);
  }
}

/// Writes auto entries exactly like transaction_form_screen.dart does for a new entry.
class _AppSink implements AutoTxnSink {
  bool notifyOnInsert = false;

  static const _methodDisplay = {
    'upi': 'UPI / Mobile Payment',
    'card': 'Credit/Debit Card',
    'bank': 'Bank Transfer',
  };

  @override
  Future<List<Map<String, dynamic>>> cachedTransactions() async {
    final cached = await CacheService.getCachedTransactions();
    return List<Map<String, dynamic>>.from(cached?['transactions'] ?? const []);
  }

  bool _isSame(Map<String, dynamic> t, AutoTxn txn) =>
      t['id'] == txn.localId ||
      ((t['notes'] ?? '').toString() == txn.notes &&
          t['type'] == txn.type &&
          DateTime.tryParse(t['date']?.toString() ?? '')?.millisecondsSinceEpoch ==
              txn.time.millisecondsSinceEpoch);

  @override
  Future<bool> exists(AutoTxn txn) async {
    if ((await cachedTransactions()).any((t) => _isSame(t, txn))) return true;
    final queue = await CacheService.getSyncQueue();
    return queue.any((op) => op['entity'] == 'transaction' && op['entityId'] == txn.localId);
  }

  Future<Map<String, dynamic>> _categoryJson(int? id) async {
    final cached = await CacheService.getCachedCategories();
    final cats = List<Map<String, dynamic>>.from(cached?['categories'] ?? const []);
    return cats.firstWhere((c) => c['id'] == id,
        orElse: () => {'id': id, 'name': 'Other', 'icon': 'category', 'color': '#C8E64A'});
  }

  Map<String, dynamic> _apiData(AutoTxn txn) => {
        'amount': txn.amount.toStringAsFixed(2),
        'type': txn.type,
        'category_id': txn.categoryId,
        'date': txn.time.toUtc().toIso8601String(),
        'payment_method': txn.paymentMethod,
        'notes': txn.notes,
      };

  @override
  Future<void> insert(AutoTxn txn) async {
    final category = await _categoryJson(txn.categoryId);
    final fullTxnJson = {
      'id': txn.localId,
      'amount': txn.amount.toStringAsFixed(2),
      'type': txn.type,
      'category': category,
      'date': txn.time.toUtc().toIso8601String(),
      'payment_method': txn.paymentMethod,
      'payment_method_display': _methodDisplay[txn.paymentMethod] ?? 'Other',
      'notes': txn.notes,
    };

    // Each step checks first, so a retry after a crash never writes twice.
    if (!(await cachedTransactions()).any((t) => t['id'] == txn.localId)) {
      await CacheService.addTransactionToCache(fullTxnJson);
      await CacheService.updateDashboardOptimistically(txn.type, txn.amount, fullTxnJson);
      if (txn.type == 'expense' && txn.categoryId != null) {
        await CacheService.updateBudgetOptimistically(txn.categoryId!, txn.amount);
      }
    }
    final queue = await CacheService.getSyncQueue();
    final queued = queue.any((op) =>
        op['entity'] == 'transaction' && op['action'] == 'create' && op['entityId'] == txn.localId);
    if (!queued) {
      await SyncService.queueOperation(
        action: 'create',
        entity: 'transaction',
        data: _apiData(txn),
        entityId: txn.localId,
      );
    }

    if (notifyOnInsert) {
      final symbol = (await CacheService.getCachedCategories())?['currency_symbol'] ?? '₹';
      final amount = txn.amount == txn.amount.roundToDouble()
          ? txn.amount.toStringAsFixed(0)
          : txn.amount.toStringAsFixed(2);
      final verb = txn.type == 'income' ? 'received' : 'added to ${category['name']}';
      await AutoCaptureChannel.showAddedNotification(
        title: '$symbol$amount $verb',
        body: '${txn.payee ?? txn.sourceApp} · Tap to edit',
      );
    }
  }

  @override
  Future<void> fillMissing(int localId, AutoTxn from) async {
    final list = await cachedTransactions();
    final idx = list.indexWhere((t) => t['id'] == localId);
    if (idx < 0 || from.payee == null) return;
    final t = Map<String, dynamic>.from(list[idx]);
    if ((t['notes'] ?? '').toString().trim().isNotEmpty) return; // nothing missing
    t['notes'] = from.payee;
    await CacheService.updateTransactionInCache(localId, t);
    await SyncService.queueOperation(
      action: 'update',
      entity: 'transaction',
      entityId: localId,
      data: {
        'amount': t['amount'],
        'type': t['type'],
        'category_id': (t['category'] as Map?)?['id'],
        'date': t['date'],
        'payment_method': t['payment_method'],
        'notes': t['notes'],
      },
    );
  }

  /// Same steps as deleting a transaction from the list screen.
  @override
  Future<void> remove(int localId) async {
    final cached = await CacheService.getCachedTransactions();
    final list = List<Map<String, dynamic>>.from(cached?['transactions'] ?? const []);
    final idx = list.indexWhere((t) => t['id'] == localId);
    if (idx >= 0) {
      final t = list[idx];
      final amount = double.tryParse(t['amount'].toString()) ?? 0.0;
      final category = t['category'] as Map?;
      await CacheService.reverseDashboardImpact(
        (t['type'] ?? 'expense').toString(),
        amount,
        localId,
        categoryName: category?['name']?.toString(),
      );
      if (t['type'] == 'expense' && category?['id'] is int) {
        await CacheService.updateBudgetOptimistically(category!['id'] as int, amount, isDelete: true);
      }
      list.removeAt(idx);
      await CacheService.cacheTransactions(
        {'transactions': list, 'currency_symbol': cached?['currency_symbol']},
        preserveUnsynced: false,
      );
    }
    AutoExpenseService._removingOwnEntry = true;
    try {
      await SyncService.queueOperation(action: 'delete', entity: 'transaction', entityId: localId);
    } finally {
      AutoExpenseService._removingOwnEntry = false;
    }
  }
}
