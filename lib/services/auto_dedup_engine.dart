/// Decides, for every parsed payment notification, whether it becomes a new transaction,
/// is merged into one that already exists, waits in the Review list, or is skipped.
///
/// Zero-duplicate rules (see AUTO_TRACKING in PLAY_STORE_NOTES.md):
///  a. Same notification key + same text hash = a re-post: skip.
///  b. A reference (UPI ref / UTR / txn id) seen before = same payment, whatever the app.
///  c. No/new ref: same amount + type (+ compatible account last-4) within ±3 min = same
///     payment: fill in missing fields, never insert a second one.
///  d. A manual entry with the same amount + type within ±10 min: skip and link to it.
///  e. Dismissed (user-deleted) payments are never recreated.
///  f. A refund / reversal carrying the reference of an auto entry removes that entry
///     (a failed payment that was debited and then reversed leaves no expense behind).
///
/// All work runs behind one async lock. A new entry is written in two phases
/// (fingerprints marked "adding" → cache + sync queue → "added"), and [recover] finishes
/// any half-done insert after a crash without ever inserting twice.
library;

import 'dart:convert';

import 'auto_capture_store.dart';
import 'notification_parser.dart';

/// A parsed payment ready to become (or already being) a transaction.
class AutoTxn {
  /// Temp id used for the cache entry and the sync queue (milliseconds, >= 1e11).
  final int localId;
  final double amount;
  final String type;
  final int? categoryId;
  final DateTime time;
  final String? payee;
  final String paymentMethod;
  final String sourceApp;
  final String? refLast4;
  final String? last4;

  const AutoTxn({
    required this.localId,
    required this.amount,
    required this.type,
    required this.time,
    required this.paymentMethod,
    required this.sourceApp,
    this.categoryId,
    this.payee,
    this.refLast4,
    this.last4,
  });

  factory AutoTxn.fromParse(ParseResult r, {required int localId, int? categoryId}) => AutoTxn(
        localId: localId,
        amount: r.amount,
        type: r.type,
        time: r.time,
        paymentMethod: r.paymentMethod,
        sourceApp: r.sourceApp,
        categoryId: categoryId,
        payee: r.payee,
        refLast4: r.refLast4,
        last4: r.accountLast4,
      );

  /// Notes look like a manual entry: just the payee ("Swiggy"), or empty when unknown.
  String get notes => payee ?? '';

  AutoTxn copyWith({int? localId, int? categoryId, String? payee, String? refLast4, String? last4}) =>
      AutoTxn(
        localId: localId ?? this.localId,
        amount: amount,
        type: type,
        time: time,
        paymentMethod: paymentMethod,
        sourceApp: sourceApp,
        categoryId: categoryId ?? this.categoryId,
        payee: payee ?? this.payee,
        refLast4: refLast4 ?? this.refLast4,
        last4: last4 ?? this.last4,
      );

  Map<String, dynamic> toJson() => {
        'local_id': localId,
        'amount': amount,
        'type': type,
        'category_id': categoryId,
        'time': time.millisecondsSinceEpoch,
        'payee': payee,
        'payment_method': paymentMethod,
        'source_app': sourceApp,
        'ref_last4': refLast4,
        'last4': last4,
      };

  factory AutoTxn.fromJson(Map<String, dynamic> j) => AutoTxn(
        localId: (j['local_id'] as num).toInt(),
        amount: (j['amount'] as num).toDouble(),
        type: j['type'] as String,
        categoryId: (j['category_id'] as num?)?.toInt(),
        time: DateTime.fromMillisecondsSinceEpoch((j['time'] as num).toInt()),
        payee: j['payee'] as String?,
        paymentMethod: j['payment_method'] as String? ?? 'upi',
        sourceApp: j['source_app'] as String? ?? '',
        refLast4: j['ref_last4'] as String?,
        last4: j['last4'] as String?,
      );
}

/// Where accepted payments go. The real implementation (AutoExpenseService) writes the
/// cache + SyncService queue exactly like the manual "Add transaction" form.
abstract class AutoTxnSink {
  /// Cached transactions (to detect manual entries, rule d).
  Future<List<Map<String, dynamic>>> cachedTransactions();

  /// True if [txn] already reached the cache or the sync queue (crash recovery).
  Future<bool> exists(AutoTxn txn);

  /// Adds [txn] to the cache and queues it for sync.
  Future<void> insert(AutoTxn txn);

  /// Copies fields the existing entry [localId] is missing (e.g. payee) from [from].
  Future<void> fillMissing(int localId, AutoTxn from);

  /// Deletes entry [localId] (cache + sync queue), e.g. when its payment was reversed.
  Future<void> remove(int localId);
}

enum AutoOutcome {
  /// New transaction inserted (high confidence).
  added,

  /// Low-confidence payment confirmed by a second source → inserted.
  promoted,

  /// Same payment as an existing auto entry; missing fields filled in.
  merged,

  /// Same payment as a manual entry; linked, nothing inserted.
  linkedToManual,

  /// Exact re-post or an already-processed reference.
  duplicate,

  /// The user deleted/discarded this payment before.
  dismissed,

  /// Low confidence: waiting in the Review list.
  review,

  /// A refund / reversal removed the auto entry (or Review item) it belongs to.
  reversed,

  /// Not wanted (e.g. an unmatched refund while only expenses are tracked).
  ignored,
}

class AutoDedupEngine {
  static const crossSourceWindow = Duration(minutes: 3);
  static const manualWindow = Duration(minutes: 10);
  static const retention = Duration(days: 60);

  final AutoCaptureStore store;
  final AutoTxnSink sink;
  final DateTime Function() _now;
  int _lastId = 0;

  AutoDedupEngine(this.store, this.sink, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  static String postHash(String key, String textHash) => sha256Hex('post|$key|$textHash');
  static String refHash(String ref) => sha256Hex('ref|$ref');
  static String textHashOf(String title, String text, String bigText) =>
      sha256Hex('$title\u0000$text\u0000$bigText');

  /// Unique temp id (>= 1e11, like the rest of the app's offline-created entries).
  int _newLocalId() {
    var id = _now().millisecondsSinceEpoch;
    if (id <= _lastId) id = _lastId + 1;
    _lastId = id;
    return id;
  }

  /// [allowIncome]: false when only expenses are tracked; a refund then only cancels the
  /// auto entry it belongs to and is otherwise ignored.
  Future<AutoOutcome> process(
    ParseResult r, {
    required String notificationKey,
    required String textHash,
    int? categoryId,
    bool allowIncome = true,
  }) =>
      store.lock.run(() => _process(r, notificationKey, textHash, categoryId, allowIncome));

  Future<AutoOutcome> _process(
      ParseResult r, String key, String textHash, int? categoryId, bool allowIncome) async {
    final nowMs = _now().millisecondsSinceEpoch;
    final post = postHash(key, textHash);
    final ref = r.ref == null ? null : refHash(r.ref!);

    // a. re-post of the very same notification
    if (await store.get(post) != null) return AutoOutcome.duplicate;

    // f. refund / reversal of an auto entry with the same reference: remove that entry
    if (r.isReversal) {
      final original = ref == null ? null : await store.get(ref);
      if (original != null && original.status == FpStatus.added && original.txnLocalId != null) {
        final id = original.txnLocalId!;
        await sink.remove(id);
        await store.setStatusForTxn(id, FpStatus.dismissed);
        await _link([post], FpStatus.dismissed, id, nowMs);
        return AutoOutcome.reversed;
      }
      if (original != null && original.status == FpStatus.review && original.reviewId != null) {
        await store.db.transaction((tx) async {
          await store.setStatusForReview(original.reviewId!, FpStatus.dismissed, tx: tx);
          await store.deleteReview(original.reviewId!, tx: tx);
        });
        await _link([post], FpStatus.dismissed, null, nowMs);
        return AutoOutcome.reversed;
      }
      if (!allowIncome) return AutoOutcome.ignored;
      // Otherwise a refund we cannot tie to an entry: it waits in Review (it is LOW).
    }

    // b. reference already seen (any app)
    if (ref != null) {
      final seen = await store.get(ref);
      if (seen != null) {
        await _link([post], seen.status, seen.txnLocalId, nowMs, reviewId: seen.reviewId);
        return seen.status == FpStatus.dismissed ? AutoOutcome.dismissed : AutoOutcome.duplicate;
      }
    }

    // c. same payment from another source (amount + type + last-4 within ±3 min)
    final match = await store.findPayment(
      amountCents: (r.amount * 100).round(),
      type: r.type,
      last4: r.accountLast4,
      time: r.time.millisecondsSinceEpoch,
      window: crossSourceWindow,
    );
    if (match != null) {
      final linkHashes = [post, if (ref != null) ref];
      switch (match.status) {
        case FpStatus.dismissed:
          await _link(linkHashes, FpStatus.dismissed, match.txnLocalId, nowMs);
          return AutoOutcome.dismissed;
        case FpStatus.review:
          // Two sources agree → confident enough to add.
          final pending = await store.getReview(match.reviewId!);
          final base = pending == null
              ? AutoTxn.fromParse(r, localId: 0, categoryId: categoryId)
              : AutoTxn.fromJson(pending);
          final txn = base.copyWith(
            localId: _newLocalId(),
            payee: base.payee ?? r.payee,
            refLast4: base.refLast4 ?? r.refLast4,
            last4: base.last4 ?? r.accountLast4,
            categoryId: base.categoryId ?? categoryId,
          );
          await _insertNew(txn, linkHashes, nowMs, fromReviewId: match.reviewId);
          return AutoOutcome.promoted;
        default:
          final id = match.txnLocalId;
          // Payment rows with status "merged" only exist for links to manual entries.
          final isAuto = match.status != FpStatus.merged;
          if (id != null && isAuto) {
            await sink.fillMissing(id, AutoTxn.fromParse(r, localId: id, categoryId: categoryId));
          }
          await _link(linkHashes, FpStatus.merged, id, nowMs);
          return id != null && !isAuto ? AutoOutcome.linkedToManual : AutoOutcome.merged;
      }
    }

    // d. the user already added it by hand
    final manualId = await _findManualEntry(r);
    if (manualId != null) {
      await store.put(FingerprintRow(
        hash: sha256Hex('pay|manual|$manualId|$post'),
        txnLocalId: manualId,
        status: FpStatus.merged,
        createdAt: nowMs,
        amountCents: (r.amount * 100).round(),
        type: r.type,
        last4: r.accountLast4,
        txnTime: r.time.millisecondsSinceEpoch,
      ));
      await _link([post, if (ref != null) ref], FpStatus.merged, manualId, nowMs);
      return AutoOutcome.linkedToManual;
    }

    // New payment
    if (r.confidence == ParseConfidence.high) {
      final txn = AutoTxn.fromParse(r, localId: _newLocalId(), categoryId: categoryId);
      await _insertNew(txn, [post, if (ref != null) ref], nowMs);
      return AutoOutcome.added;
    }

    final reviewId = 'r${_newLocalId()}';
    final data = {
      ...AutoTxn.fromParse(r, localId: 0, categoryId: categoryId).toJson(),
      'review_id': reviewId,
    };
    await store.db.transaction((tx) async {
      await store.putReview(reviewId, data, nowMs, tx: tx);
      await store.put(
          FingerprintRow(
            hash: sha256Hex('pay|$reviewId'),
            status: FpStatus.review,
            createdAt: nowMs,
            reviewId: reviewId,
            amountCents: (r.amount * 100).round(),
            type: r.type,
            last4: r.accountLast4,
            txnTime: r.time.millisecondsSinceEpoch,
          ),
          tx: tx);
      for (final h in [post, if (ref != null) ref]) {
        await store.put(
            FingerprintRow(hash: h, status: FpStatus.review, createdAt: nowMs, reviewId: reviewId),
            tx: tx);
      }
    });
    return AutoOutcome.review;
  }

  /// Phase 1: fingerprints (+ payload) committed as "adding"; phase 2: cache + sync queue;
  /// phase 3: "added". A crash between phases is completed by [recover].
  Future<void> _insertNew(AutoTxn txn, List<String> hashes, int nowMs, {String? fromReviewId}) async {
    await store.db.transaction((tx) async {
      await store.put(
          FingerprintRow(
            hash: sha256Hex('pay|${txn.localId}'),
            txnLocalId: txn.localId,
            status: FpStatus.adding,
            createdAt: nowMs,
            amountCents: (txn.amount * 100).round(),
            type: txn.type,
            last4: txn.last4,
            txnTime: txn.time.millisecondsSinceEpoch,
            payload: _encode(txn),
            payee: txn.payee,
          ),
          tx: tx);
      for (final h in hashes) {
        await store.put(
            FingerprintRow(hash: h, txnLocalId: txn.localId, status: FpStatus.adding, createdAt: nowMs),
            tx: tx);
      }
      if (fromReviewId != null) {
        await store.setStatusForReview(fromReviewId, FpStatus.adding, txnLocalId: txn.localId, tx: tx);
        await store.deleteReview(fromReviewId, tx: tx);
      }
    });
    await sink.insert(txn);
    await store.setStatusForTxn(txn.localId, FpStatus.added);
  }

  Future<void> _link(List<String> hashes, String status, int? txnId, int nowMs, {String? reviewId}) async {
    for (final h in hashes) {
      await store.put(FingerprintRow(
          hash: h, txnLocalId: txnId, status: status, createdAt: nowMs, reviewId: reviewId));
    }
  }

  Future<int?> _findManualEntry(ParseResult r) async {
    final cents = (r.amount * 100).round();
    for (final t in await sink.cachedTransactions()) {
      if (t['type'] != r.type) continue;
      final amt = double.tryParse(t['amount'].toString());
      if (amt == null || (amt * 100).round() != cents) continue;
      final date = DateTime.tryParse(t['date']?.toString() ?? '');
      if (date == null || date.difference(r.time).abs() > manualWindow) continue;
      final id = (t['id'] as num?)?.toInt();
      if (id == null) continue;
      // A manual entry can stand in for one payment only.
      final linked = await store.db.query('processed_fingerprints',
          where: 'txn_local_id = ? AND amount_cents IS NOT NULL', whereArgs: [id], limit: 1);
      if (linked.isNotEmpty) continue;
      return id;
    }
    return null;
  }

  static String _encode(AutoTxn t) => jsonEncode(t.toJson());

  static AutoTxn _decode(String s) => AutoTxn.fromJson(jsonDecode(s) as Map<String, dynamic>);

  // ─── Lifecycle hooks ──────────────────────────────────────────────────────

  /// Finish inserts interrupted by a crash; then prune old fingerprints.
  Future<int> recover() => store.lock.run(() async {
        var fixed = 0;
        for (final row in await store.byStatus(FpStatus.adding)) {
          if (row.payload == null || row.txnLocalId == null) continue;
          final txn = _decode(row.payload!);
          if (!await sink.exists(txn)) {
            await sink.insert(txn);
            fixed++;
          }
          await store.setStatusForTxn(txn.localId, FpStatus.added);
        }
        await store.prune(retention, now: _now());
        return fixed;
      });

  /// User confirmed a Review item (optionally with another category).
  Future<AutoTxn?> confirmReview(String reviewId, {int? categoryId}) => store.lock.run(() async {
        final data = await store.getReview(reviewId);
        if (data == null) return null;
        final base = AutoTxn.fromJson(data);
        final txn = base.copyWith(localId: _newLocalId(), categoryId: categoryId ?? base.categoryId);
        await _insertNew(txn, const [], _now().millisecondsSinceEpoch, fromReviewId: reviewId);
        return txn;
      });

  /// User discarded a Review item: never shown or added again.
  Future<void> discardReview(String reviewId) => store.lock.run(() async {
        await store.db.transaction((tx) async {
          await store.setStatusForReview(reviewId, FpStatus.dismissed, tx: tx);
          await store.deleteReview(reviewId, tx: tx);
        });
      });

  /// A transaction was deleted by the user: its payment must never come back.
  Future<void> markDeleted(int txnId) =>
      store.lock.run(() => store.setStatusForTxn(txnId, FpStatus.dismissed));

  /// Payee of an auto entry (null for manual entries).
  Future<String?> payeeForTxn(int txnId) => store.payeeForTxn(txnId);

  /// The server assigned a real id to an offline-created entry.
  Future<void> remap(int oldId, int newId) => store.lock.run(() async {
        await store.remapTxn(oldId, newId);
        // Reached the server, so a pending "adding" is certainly done.
        await store.db.update('processed_fingerprints', {'status': FpStatus.added, 'payload': null},
            where: 'txn_local_id = ? AND status = ?', whereArgs: [newId, FpStatus.adding]);
      });
}
