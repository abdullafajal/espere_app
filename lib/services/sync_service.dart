/// Sync service — processes offline queue and syncs with server.
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'cache_service.dart';
import 'connectivity_service.dart';

class SyncService {
  /// Process all pending operations in the sync queue.
  /// Called when device comes back online.
  static Future<void> processSyncQueue() async {
    if (!ConnectivityService.isOnline) return;

    final queue = List<Map<String, dynamic>>.from(await CacheService.getSyncQueue());
    if (queue.isEmpty) return;

    debugPrint('[SyncService] Processing ${queue.length} queued operations...');

    for (int i = 0; i < queue.length; i++) {
      final op = queue[i];
      try {
        final action = op['action'] as String;
        final entity = op['entity'] as String;
        final data = op['data'] as Map<String, dynamic>?;
        final entityId = op['entityId'] as int?;
        final opId = op['id'] as String;

        bool success = false;
        dynamic resultData;

        switch (entity) {
          case 'transaction':
            final res = await _syncTransaction(action, data, entityId);
            success = res.isSuccess;
            break;
          case 'category':
            final res = await _syncCategory(action, data, entityId);
            success = res.isSuccess;
            resultData = res.data; // Capture real ID
            break;
          case 'budget':
            success = (await _syncBudget(action, data, entityId)).isSuccess;
            break;
          case 'saving':
            success = (await _syncSaving(action, data, entityId)).isSuccess;
            break;
          case 'saving_add_money':
            success = await _syncSavingAddMoney(data, entityId);
            break;
        }

        if (success) {
          await CacheService.removeFromSyncQueue(opId);
          debugPrint('[SyncService] ✓ Synced: $action $entity ${entityId ?? ""}');

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
                if (nextData != null && nextData['category_id'] == oldId) {
                  nextData['category_id'] = newId;
                }
              }
            }
          }
        } else {
          debugPrint('[SyncService] ✗ Failed: $action $entity ${entityId ?? ""}');
        }
      } catch (e) {
        debugPrint('[SyncService] Error processing op: $e');
      }
    }
  }

  /// Replace temporary category IDs with real IDs in the sync queue.
  static Future<void> _remapIdsInQueue(int? oldId, int newId) async {
    if (oldId == null) return;
    final queue = await CacheService.getSyncQueue();
    bool changed = false;

    for (final op in queue) {
      if (op['entity'] == 'transaction' && op['action'] == 'create') {
        final data = op['data'] as Map<String, dynamic>?;
        if (data != null && data['category_id'] == oldId) {
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

  static Future<bool> _syncSavingAddMoney(
      Map<String, dynamic>? data, int? entityId) async {
    if (data == null || entityId == null) return false;
    final res = await ApiService.addMoneyToSavingGoal(
      entityId,
      (data['amount'] as num).toDouble(),
      notes: data['notes'] as String?,
    );
    return res.isSuccess;
  }

  /// Queue a pending operation for later sync.
  static Future<void> queueOperation({
    required String action,
    required String entity,
    Map<String, dynamic>? data,
    int? entityId,
  }) async {
    final op = {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'action': action,
      'entity': entity,
      'data': data,
      'entityId': entityId,
      'createdAt': DateTime.now().toIso8601String(),
    };
    await CacheService.addToSyncQueue(op);
    debugPrint('[SyncService] Queued: $action $entity ${entityId ?? "new"}');
  }

  /// Get the count of pending operations.
  static Future<int> pendingCount() async {
    final queue = await CacheService.getSyncQueue();
    return queue.length;
  }
}
