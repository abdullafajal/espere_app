/// Sync service — processes offline queue and syncs with server.
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'cache_service.dart';
import 'connectivity_service.dart';
import '../models/transaction.dart';
import '../models/category.dart';
import '../models/user.dart';

import 'dart:async';
import 'widget_service.dart';

class SyncService {
  static final _syncController = StreamController<void>.broadcast();

  /// Stream that emits when a sync cycle finishes (queue processed).
  static Stream<void> get onSyncComplete => _syncController.stream;

  /// Process all pending operations and then pull fresh data
  static Future<void>? _syncRun;
  static bool _syncAgain = false;

  static Future<void> syncAll() {
    // Never run two syncs at once (reconnect + resume + pull-to-refresh can
    // all fire together) - that would POST the same queued item twice.
    if (_syncRun != null) {
      _syncAgain = true;
      return _syncRun!;
    }
    final run = _runSync().whenComplete(() => _syncRun = null);
    _syncRun = run;
    return run;
  }

  static Future<void> _runSync() async {
    do {
      _syncAgain = false;
      if (!ConnectivityService.isOnline) return;
      await processSyncQueue();
      await pullData();
    } while (_syncAgain);
  }

  /// Pull all necessary offline data from APIs and update cache
  static Future<void> pullData() async {
    if (!ConnectivityService.isOnline) return;
    debugPrint('[SyncService] Pulling fresh data from APIs...');

    try {
      // Run API fetches concurrently where possible
      await Future.wait([
        _pullProfile(),
        _pullDashboard(),
        _pullCategories(),
        _pullTransactions(),
        _pullBudgets(),
        _pullSavings(),
        _pullReports(),
      ]);
      debugPrint('[SyncService] Successfully pulled all data.');
    } catch (e) {
      debugPrint('[SyncService] Error pulling data: $e');
    }
    
    // Notify UI that cache has been updated
    _syncController.add(null);
  }

  static Future<void> _pullProfile() async {
    if (await hasPending('profile')) return;
    final res = await ApiService.getProfile();
    if (res.isSuccess && res.data != null) {
      await CacheService.cacheUser(res.data!.toJson());
    }
  }

  static Future<void> _pullDashboard() async {
    // Totals depend on transactions; keep the local (optimistic) numbers
    // until every queued change reached the server.
    if (await hasPending('transaction')) return;
    final res = await ApiService.getDashboard();
    if (res.isSuccess && res.data != null) {
      final d = res.data!;
      await CacheService.cacheDashboard(d.toJson());
      WidgetService.updateDashboard(
        totalBalance: double.tryParse(d.totalBalance.replaceAll(',', '')) ?? 0,
        totalIncome: double.tryParse(d.monthlyIncome.replaceAll(',', '')) ?? 0,
        totalExpense: double.tryParse(d.monthlyExpenses.replaceAll(',', '')) ?? 0,
        currencySymbol: d.currencySymbol,
      );
    }
  }

  static Future<void> _pullCategories() async {
    if (await hasPending('category')) return;
    final res = await ApiService.getCategories();
    if (res.isSuccess && res.data != null) {
      final cats = List<CategoryModel>.from(res.data!['categories'] ?? []);
      final catsJson = cats.map((c) => c.toJson()).toList();
      await CacheService.cacheCategories({
        'categories': catsJson,
        'currency_symbol': res.data!['currency_symbol'],
      });
      WidgetService.syncQuickAddCategories(
        cats,
        currencySymbol: res.data!['currency_symbol'] ?? '₹',
      );
    }
  }

  static Future<void> _pullTransactions() async {
    if (await hasPending('transaction')) return;
    final res = await ApiService.getTransactions(showAll: true);
    if (res.isSuccess && res.data != null) {
      final txnsJson = (res.data!['transactions'] as List).map((t) => (t as TransactionModel).toJson()).toList();
      await CacheService.cacheTransactions({
        'transactions': txnsJson,
        'currency_symbol': res.data!['currency_symbol'],
        'total': res.data!['total'],
        'has_next': res.data!['has_next'],
        'total_spend': res.data!['total_spend'],
        'total_income': res.data!['total_income'],
        'today_spend': res.data!['today_spend'],
        'avg_daily': res.data!['avg_daily'],
      });
    }
  }

  static Future<void> _pullBudgets() async {
    if (await hasPending('budget')) return;
    final res = await ApiService.getBudgets();
    if (res.isSuccess && res.data != null) {
      await CacheService.cacheBudgets(res.data!);
    }
  }

  static Future<void> _pullSavings() async {
    if (await hasPending('saving')) return;
    final res = await ApiService.getSavings();
    if (res.isSuccess && res.data != null) {
      await CacheService.cacheSavings(res.data!);
    }
  }

  static Future<void> _pullReports() async {
    if (await hasPending('transaction')) return;
    final res = await ApiService.getReports();
    if (res.isSuccess && res.data != null) {
      await CacheService.cacheReports(res.data!);
    }
  }

  /// Process all pending operations in the sync queue.
  /// Called when device comes back online.
  static bool _processing = false;

  /// Temp (offline-created) ids are millisecond timestamps; real server ids are small.
  static bool _isTempId(int? id) => id != null && id >= 100000000000;

  /// Operations created by the Android home-screen widget are POSTed by the
  /// widget itself right away. Give it a moment before the app retries them.
  static const _widgetGrace = Duration(seconds: 90);
  static const _maxAttempts = 8;

  static Future<void> processSyncQueue() async {
    if (!ConnectivityService.isOnline || _processing) return;
    _processing = true;
    try {
      await _processSyncQueue();
    } finally {
      _processing = false;
    }
  }

  static Future<void> _processSyncQueue() async {
    var queue = List<Map<String, dynamic>>.from(await CacheService.getSyncQueue());

    // Groups are live-only. Anything queued for them by older versions is
    // set aside (kept, not deleted) instead of being replayed late - members
    // would otherwise get stale notifications.
    final legacy = queue.where((o) => (o['entity'] as String?)?.startsWith('split_') ?? false).toList();
    if (legacy.isNotEmpty) {
      for (final o in legacy) {
        await CacheService.addToFailedItems(o, 'Groups are live-only');
        await CacheService.removeFromSyncQueue(o['id'] as String);
      }
      queue = queue.where((o) => !legacy.contains(o)).toList();
      debugPrint('[SyncService] Set aside ${legacy.length} legacy split operations.');
    }
    if (queue.isEmpty) {
      _retryStep = 0;
      return;
    }

    debugPrint('[SyncService] Processing ${queue.length} queued operations...');

    var needsRetry = false;

    for (int i = 0; i < queue.length; i++) {
      final op = queue[i];

      if (op['source'] == 'widget') {
        final created = DateTime.tryParse(op['createdAt']?.toString() ?? '');
        if (created != null && DateTime.now().toUtc().difference(created.toUtc()) < _widgetGrace) {
          needsRetry = true;
          continue; // widget's own background sync may still be running
        }
      }

      try {
        final action = op['action'] as String;
        final entity = op['entity'] as String;
        final data = op['data'] as Map<String, dynamic>?;
        final entityId = op['entityId'] as int?;
        final opId = op['id'] as String;

        bool success = false;
        dynamic resultData;

        final probed = await ApiService.probed<void>(() async {
        switch (entity) {
          case 'transaction':
            final res = await _syncTransaction(action, data, entityId);
            success = res.isSuccess;
            resultData = res.data;
            break;
          case 'category':
            final res = await _syncCategory(action, data, entityId);
            success = res.isSuccess;
            resultData = res.data; // Capture real ID
            break;
          case 'budget':
            final res = await _syncBudget(action, data, entityId);
            success = res.isSuccess;
            resultData = res.data;
            break;
          case 'saving':
            final res = await _syncSaving(action, data, entityId);
            success = res.isSuccess;
            resultData = res.data;
            break;
          case 'saving_add_money':
            final res = await _syncSavingAddMoney(data, entityId);
            success = res.isSuccess;
            resultData = res.data;
            break;
          case 'profile':
            final res = await ApiService.updateProfile(data ?? {});
            success = res.isSuccess;
            resultData = res.data;
            break;
        }
        });
        final probe = probed.probe;

        // Deleting something that is already gone on the server is a success.
        if (!success && action == 'delete' && probe.status == 404) {
          success = true;
          resultData = null;
        }

        if (!success && probe.permanent) {
          // Server rejected it for good: keep the data aside, never delete it,
          // and don't block everything queued behind it.
          await CacheService.addToFailedItems(op, 'Rejected by server (HTTP ${probe.status})');
          await CacheService.removeFromSyncQueue(opId);
          debugPrint('[SyncService] Set aside rejected $action $entity (HTTP ${probe.status})');
          continue;
        }

        if (!success && (probe.networkError || probe.status != null)) {
          // Slow / unreachable network or temporary server trouble. Keep
          // everything, keep the order (later ops may depend on this one) and
          // try again shortly.
          needsRetry = true;
          debugPrint('[SyncService] Network not ready, will retry (${probe.status ?? "no response"})');
          break;
        }

        if (success) {
          await CacheService.removeFromSyncQueue(opId);
          debugPrint('[SyncService] ✓ Synced: $action $entity ${entityId ?? ""}');

          // ─── Cache Sync (Immediate) ───────────────────────────────
          // This prevents background refreshes from wiping optimistic data 
          // before the sync queue is fully processed.
          if (resultData != null) {
            if (entity == 'transaction') {
              if (action == 'create' || action == 'update') {
                final txnJson = (resultData as TransactionModel).toJson();
                await CacheService.updateTransactionInCache(
                  txnJson['id'], 
                  txnJson, 
                  oldId: action == 'create' ? entityId : null
                );
                await CacheService.updateTransactionInDashboardCache(
                  txnJson['id'], 
                  txnJson, 
                  oldId: action == 'create' ? entityId : null
                );
              }
            } else if (entity == 'category') {
              if (action == 'create' || action == 'update') {
                final catJson = (resultData as CategoryModel).toJson();
                await CacheService.updateCategoryInCache(
                  catJson['id'], 
                  catJson, 
                  oldId: action == 'create' ? entityId : null
                );
              }
            } else if (entity == 'budget') {
              if (action == 'create' || action == 'update') {
                await CacheService.updateBudgetInCache(
                  resultData['id'], 
                  resultData, 
                  oldId: action == 'create' ? entityId : null
                );
              }
            } else if (entity == 'saving') {
              if (action == 'create' || action == 'update') {
                await CacheService.updateSavingInCache(
                  resultData['id'] as int, 
                  resultData, 
                  oldId: action == 'create' ? entityId : null
                );
              }
            } else if (entity == 'saving_add_money') {
              await CacheService.updateSavingInCache(
                resultData['id'] as int, 
                resultData
              );
            }
          }


          // ─── ID Remapping ──────────────────────────────────────────
          if (entity == 'category' && action == 'create' && resultData != null) {
            final oldId = entityId;
            final newId = resultData.id as int;
            
            // 1. Update Storage
            await _remapIdsInQueue(oldId, newId);
            
            // 2. Update local loop queue so subsequent items have the real ID
            for (int j = i + 1; j < queue.length; j++) {
              final nextOp = queue[j];
              if (nextOp['entity'] == 'transaction' && nextOp['action'] == 'create') {
                final nextData = nextOp['data'] as Map<String, dynamic>?;
                if (nextData != null && nextData['category_id']?.toString() == oldId?.toString()) {
                  nextData['category_id'] = newId;
                }
              }
            }
          } else if (entity == 'saving' && action == 'create' && resultData != null) {
            final oldId = entityId;
            final newId = resultData['id'] as int;
            
            // 1. Update Storage
            await _remapSavingIdsInQueue(oldId, newId);
            
            // 2. Update local loop queue so subsequent items have the real ID
            for (int j = i + 1; j < queue.length; j++) {
              final nextOp = queue[j];
              if ((nextOp['entity'] == 'saving_add_money' || nextOp['entity'] == 'saving') && 
                  nextOp['entityId']?.toString() == oldId?.toString()) {
                nextOp['entityId'] = newId;
              }
            }
          } else if (entity == 'transaction' && action == 'create' && resultData != null) {
            final oldId = entityId;
            final newId = resultData.id as int;
            
            // 1. Update Storage
            await _remapTransactionIdsInQueue(oldId, newId);
            
            // 2. Update local loop queue so subsequent items have the real ID
            for (int j = i + 1; j < queue.length; j++) {
              final nextOp = queue[j];
              if (nextOp['entityId']?.toString() == oldId?.toString()) {
                nextOp['entityId'] = newId;
              }
            }
          } else if (entity == 'budget' && action == 'create' && resultData != null) {
            final oldId = entityId;
            final newId = resultData['id'] as int;
            
            // 1. Update Storage
            await _remapBudgetIdsInQueue(oldId, newId);
            
            // 2. Update local loop queue so subsequent items have the real ID
            for (int j = i + 1; j < queue.length; j++) {
              final nextOp = queue[j];
              if (nextOp['entityId']?.toString() == oldId?.toString()) {
                nextOp['entityId'] = newId;
              }
            }
          }
        } else {
          debugPrint('[SyncService] ✗ Failed: $action $entity ${entityId ?? ""}');
          await _markFailed(op);
        }
      } catch (e) {
        debugPrint('[SyncService] Error processing op: $e');
        await _markFailed(op);
      }
    }
    if (needsRetry) {
      _scheduleRetry();
    } else {
      _retryStep = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  // ─── Retry with backoff (slow / flaky connections) ───────────────────

  static Timer? _retryTimer;
  static int _retryStep = 0;

  /// Try again after 10s, 20s, 40s ... up to 5 minutes. Nothing is dropped
  /// meanwhile; the queue simply waits for a usable connection.
  static void _scheduleRetry() {
    if (_retryTimer?.isActive ?? false) return;
    final secs = (10 * (1 << (_retryStep > 5 ? 5 : _retryStep))).clamp(10, 300);
    _retryStep++;
    _retryTimer = Timer(Duration(seconds: secs), () {
      _retryTimer = null;
      syncAll();
    });
  }

  /// True while any queued (not yet synced) operation exists for [entity].
  /// Server data must not overwrite local data while this is true.
  static Future<bool> hasPending(String entity) async {
    final q = await CacheService.getSyncQueue();
    return q.any((o) =>
        o['entity'] == entity ||
        (entity == 'saving' && o['entity'] == 'saving_add_money'));
  }

  /// Replace temporary category IDs with real IDs in the sync queue.
  static Future<void> _remapIdsInQueue(int? oldId, int newId) async {
    if (oldId == null) return;
    final queue = await CacheService.getSyncQueue();
    bool changed = false;

    for (final op in queue) {
      if (op['entity'] == 'transaction' && op['action'] == 'create') {
        final data = op['data'] as Map<String, dynamic>?;
        if (data != null && data['category_id']?.toString() == oldId?.toString()) {
          data['category_id'] = newId;
          changed = true;
          debugPrint('[SyncService] Remapped category ID $oldId to $newId in queued transaction');
        }
      }
    }

    if (changed) {
      await CacheService.saveSyncQueue(queue);
    }
  }

  /// Replace temporary saving IDs with real IDs in the sync queue.
  static Future<void> _remapSavingIdsInQueue(int? oldId, int newId) async {
    if (oldId == null) return;
    final queue = await CacheService.getSyncQueue();
    bool changed = false;

    for (final op in queue) {
      if ((op['entity'] == 'saving_add_money' || op['entity'] == 'saving') && 
          op['entityId']?.toString() == oldId?.toString()) {
        op['entityId'] = newId;
        changed = true;
        debugPrint('[SyncService] Remapped saving ID $oldId to $newId in queued operation');
      }
    }

    if (changed) {
      await CacheService.saveSyncQueue(queue);
    }
  }

  /// Replace temporary transaction IDs with real IDs in the sync queue.
  static Future<void> _remapTransactionIdsInQueue(int? oldId, int newId) async {
    if (oldId == null) return;
    final queue = await CacheService.getSyncQueue();
    bool changed = false;

    for (final op in queue) {
      if (op['entityId']?.toString() == oldId.toString()) {
        op['entityId'] = newId;
        changed = true;
        debugPrint('[SyncService] Remapped transaction ID $oldId to $newId in queued operation');
      }
    }

    if (changed) {
      await CacheService.saveSyncQueue(queue);
    }
  }

  /// Replace temporary budget IDs with real IDs in the sync queue.
  static Future<void> _remapBudgetIdsInQueue(int? oldId, int newId) async {
    if (oldId == null) return;
    final queue = await CacheService.getSyncQueue();
    bool changed = false;

    for (final op in queue) {
      if (op['entityId']?.toString() == oldId.toString()) {
        op['entityId'] = newId;
        changed = true;
        debugPrint('[SyncService] Remapped budget ID $oldId to $newId in queued operation');
      }
    }

    if (changed) {
      await CacheService.saveSyncQueue(queue);
    }
  }

  // ─── Entity Sync Handlers ────────────────────────────────────────────

  static Future<ApiResult<dynamic>> _syncTransaction(
      String action, Map<String, dynamic>? data, int? entityId) async {
    switch (action) {
      case 'create':
        if (data == null) return ApiResult(error: 'Missing data');
        return await ApiService.createTransaction(data);
      case 'update':
        if (data == null || entityId == null) return ApiResult(error: 'Missing data/ID');
        return await ApiService.updateTransaction(entityId, data);
      case 'delete':
        if (entityId == null) return ApiResult(error: 'Missing ID');
        final res = await ApiService.deleteTransaction(entityId);
        return ApiResult(data: null, error: res.error);
      default:
        return ApiResult(error: 'Unknown action');
    }
  }

  static Future<ApiResult<dynamic>> _syncCategory(
      String action, Map<String, dynamic>? data, int? entityId) async {
    switch (action) {
      case 'create':
        if (data == null) return ApiResult(error: 'Missing data');
        return await ApiService.createCategory(data);
      case 'update':
        if (data == null || entityId == null) return ApiResult(error: 'Missing data/ID');
        return await ApiService.updateCategory(entityId, data);
      case 'delete':
        if (entityId == null) return ApiResult(error: 'Missing ID');
        final res = await ApiService.deleteCategory(entityId);
        return ApiResult(data: null, error: res.error);
      default:
        return ApiResult(error: 'Unknown action');
    }
  }

  static Future<ApiResult<dynamic>> _syncBudget(
      String action, Map<String, dynamic>? data, int? entityId) async {
    switch (action) {
      case 'create':
        if (data == null) return ApiResult(error: 'Missing data');
        return await ApiService.createBudget(data);
      case 'delete':
        if (entityId == null) return ApiResult(error: 'Missing ID');
        return await ApiService.deleteBudget(entityId);
      default:
        return ApiResult(error: 'Unknown action');
    }
  }

  static Future<ApiResult<dynamic>> _syncSaving(
      String action, Map<String, dynamic>? data, int? entityId) async {
    switch (action) {
      case 'create':
        if (data == null) return ApiResult(error: 'Missing data');
        return await ApiService.createSavingGoal(data);
      case 'update':
        if (data == null || entityId == null) return ApiResult(error: 'Missing data/ID');
        return await ApiService.updateSavingGoal(entityId, data);
      case 'delete':
        if (entityId == null) return ApiResult(error: 'Missing ID');
        final res = await ApiService.deleteSavingGoal(entityId);
        return ApiResult(data: null, error: res.error);
      default:
        return ApiResult(error: 'Unknown action');
    }
  }

  static Future<ApiResult<dynamic>> _syncSavingAddMoney(
      Map<String, dynamic>? data, int? entityId) async {
    if (data == null || entityId == null) return ApiResult(error: 'Missing data/ID');
    return await ApiService.addMoneyToSavingGoal(
      entityId,
      (data['amount'] as num).toDouble(),
      notes: data['notes'] as String?,
    );
  }

  /// Count a failed attempt for an operation that failed for an unexpected
  /// (non-network) reason. After several attempts it is set aside in the
  /// failed-items store - kept, never deleted - so it can't block forever.
  static Future<void> _markFailed(Map<String, dynamic> op) async {
    if (!ConnectivityService.isOnline) return; // network drop, not a bad request
    try {
      final queue = await CacheService.getSyncQueue();
      final i = queue.indexWhere((o) => o['id'] == op['id']);
      if (i < 0) return;
      final attempts = ((queue[i]['attempts'] as int?) ?? 0) + 1;
      if (attempts >= _maxAttempts) {
        final removed = queue.removeAt(i);
        await CacheService.addToFailedItems(removed, 'Failed $attempts times');
        debugPrint('[SyncService] Set aside ${op['action']} ${op['entity']} after $attempts attempts');
      } else {
        queue[i]['attempts'] = attempts;
      }
      await CacheService.saveSyncQueue(queue);
    } catch (_) {}
  }

  /// Queue a pending operation for later sync.
  ///
  /// Offline-created items (temp ids) that are edited or deleted before they
  /// ever reached the server are merged / cancelled locally instead of being
  /// sent as an update/delete for an id the server has never seen.
  static Future<void> queueOperation({
    required String action,
    required String entity,
    Map<String, dynamic>? data,
    int? entityId,
  }) async {
    if (_isTempId(entityId) && !_processing && (action == 'delete' || action == 'update')) {
      final queue = await CacheService.getSyncQueue();
      final createIdx = queue.indexWhere((o) =>
          o['entity'] == entity && o['action'] == 'create' && o['entityId']?.toString() == entityId.toString());
      if (createIdx >= 0) {
        if (action == 'delete') {
          queue.removeWhere((o) =>
              o['entityId']?.toString() == entityId.toString() &&
              (o['entity'] == entity || (entity == 'saving' && o['entity'] == 'saving_add_money')));
          await CacheService.saveSyncQueue(queue);
          debugPrint('[SyncService] Cancelled offline-created $entity $entityId (deleted before sync)');
          return;
        }
        if (data != null) {
          final createData = Map<String, dynamic>.from((queue[createIdx]['data'] as Map?) ?? {});
          createData.addAll(data);
          queue[createIdx]['data'] = createData;
          await CacheService.saveSyncQueue(queue);
          debugPrint('[SyncService] Merged update into queued create of $entity $entityId');
          return;
        }
      }
    }

    final op = {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'action': action,
      'entity': entity,
      'data': data,
      'entityId': entityId,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    await CacheService.addToSyncQueue(op);
    debugPrint('[SyncService] Queued: $action $entity ${entityId ?? "new"}');

    // Sync quietly in the background; if the connection is offline or slow the
    // operation just stays queued and is retried automatically.
    if (ConnectivityService.isOnline) {
      Future.delayed(const Duration(seconds: 1), syncAll);
    }
  }

  /// Get the count of pending operations.
  static Future<int> pendingCount() async {
    final queue = await CacheService.getSyncQueue();
    return queue.length;
  }
}
