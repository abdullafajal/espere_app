/// Local, app-private store for auto-captured payments (sqflite).
///
/// Holds only SHA-256 fingerprints plus minimal metadata (amount, type, last-4, time),
/// the parsed Review list and the user's per-payee category choices. Raw notification
/// text is never stored. The database file (espere_auto.db) is excluded from Android
/// backups (res/xml/data_extraction_rules.xml, res/xml/backup_rules.xml).
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

/// Fingerprint row statuses.
class FpStatus {
  /// Being inserted (crash-recovery marker; carries the parsed payload until done).
  static const adding = 'adding';
  static const added = 'added';

  /// Same payment as an existing entry (other source, or a manual entry).
  static const merged = 'merged';

  /// User deleted / discarded it: never recreated.
  static const dismissed = 'dismissed';

  /// Waiting in the Review list (low confidence).
  static const review = 'review';
}

String sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();

/// Serialises async work: only one auto-capture operation runs at a time.
class AsyncLock {
  Future<void> _last = Future.value();

  Future<T> run<T>(Future<T> Function() body) {
    final result = Completer<T>();
    final prev = _last;
    final done = Completer<void>();
    _last = done.future;
    prev.whenComplete(() async {
      try {
        result.complete(await body());
      } catch (e, st) {
        result.completeError(e, st);
      } finally {
        done.complete();
      }
    });
    return result.future;
  }
}

class FingerprintRow {
  final String hash;
  final int? txnLocalId;
  final String status;
  final int createdAt;
  final int? amountCents;
  final String? type;
  final String? last4;
  final int? txnTime;
  final String? reviewId;
  final String? payload;

  /// Parsed payee of an auto entry (used to learn the user's category choice).
  final String? payee;

  FingerprintRow({
    required this.hash,
    required this.status,
    required this.createdAt,
    this.txnLocalId,
    this.amountCents,
    this.type,
    this.last4,
    this.txnTime,
    this.reviewId,
    this.payload,
    this.payee,
  });

  factory FingerprintRow.fromMap(Map<String, Object?> m) => FingerprintRow(
        hash: m['hash'] as String,
        txnLocalId: m['txn_local_id'] as int?,
        status: m['status'] as String,
        createdAt: m['created_at'] as int,
        amountCents: m['amount_cents'] as int?,
        type: m['type'] as String?,
        last4: m['last4'] as String?,
        txnTime: m['txn_time'] as int?,
        reviewId: m['review_id'] as String?,
        payload: m['payload'] as String?,
        payee: m['payee'] as String?,
      );

  Map<String, Object?> toMap() => {
        'hash': hash,
        'txn_local_id': txnLocalId,
        'status': status,
        'created_at': createdAt,
        'amount_cents': amountCents,
        'type': type,
        'last4': last4,
        'txn_time': txnTime,
        'review_id': reviewId,
        'payload': payload,
        'payee': payee,
      };
}

class AutoCaptureStore {
  static const dbName = 'espere_auto.db';

  final Database db;
  final AsyncLock lock = AsyncLock();

  AutoCaptureStore(this.db);

  /// Opens (and creates) the store. [factory] / [path] are injectable for tests.
  static Future<AutoCaptureStore> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final p = path ?? '${await f.getDatabasesPath()}/$dbName';
    final db = await f.openDatabase(p,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) => _create(db),
          onUpgrade: (db, oldVersion, _) async {
            if (oldVersion < 2) {
              await db.execute('ALTER TABLE processed_fingerprints ADD COLUMN payee TEXT');
            }
          },
        ));
    return AutoCaptureStore(db);
  }

  static Future<void> _create(Database db) async {
    await db.execute('''
      CREATE TABLE processed_fingerprints (
        hash TEXT PRIMARY KEY,
        txn_local_id INTEGER,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        amount_cents INTEGER,
        type TEXT,
        last4 TEXT,
        txn_time INTEGER,
        review_id TEXT,
        payload TEXT,
        payee TEXT
      )''');
    await db.execute('CREATE INDEX idx_fp_payment ON processed_fingerprints(type, amount_cents, txn_time)');
    await db.execute('CREATE INDEX idx_fp_txn ON processed_fingerprints(txn_local_id)');
    await db.execute('''
      CREATE TABLE pending_review (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE payee_categories (
        payee TEXT PRIMARY KEY,
        category_id INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )''');
  }

  // ─── Fingerprints ─────────────────────────────────────────────────────────

  Future<FingerprintRow?> get(String hash, {DatabaseExecutor? tx}) async {
    final rows = await (tx ?? db)
        .query('processed_fingerprints', where: 'hash = ?', whereArgs: [hash], limit: 1);
    return rows.isEmpty ? null : FingerprintRow.fromMap(rows.first);
  }

  Future<void> put(FingerprintRow row, {DatabaseExecutor? tx}) => (tx ?? db)
      .insert('processed_fingerprints', row.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  /// A recorded payment of the same amount and type within ±[window], whose account
  /// last-4 does not contradict [last4] (either side may be unknown).
  Future<FingerprintRow?> findPayment({
    required int amountCents,
    required String type,
    required String? last4,
    required int time,
    required Duration window,
  }) async {
    final rows = await db.query(
      'processed_fingerprints',
      where: 'type = ? AND amount_cents = ? AND txn_time BETWEEN ? AND ?',
      whereArgs: [type, amountCents, time - window.inMilliseconds, time + window.inMilliseconds],
      orderBy: 'ABS(txn_time - $time) ASC',
    );
    for (final r in rows.map(FingerprintRow.fromMap)) {
      if (last4 == null || r.last4 == null || r.last4 == last4) return r;
    }
    return null;
  }

  Future<List<FingerprintRow>> byStatus(String status) async =>
      (await db.query('processed_fingerprints', where: 'status = ?', whereArgs: [status]))
          .map(FingerprintRow.fromMap)
          .toList();

  Future<void> setStatusForTxn(int txnLocalId, String status, {DatabaseExecutor? tx}) =>
      (tx ?? db).update('processed_fingerprints', {'status': status, 'payload': null},
          where: 'txn_local_id = ?', whereArgs: [txnLocalId]);

  Future<void> setStatusForReview(String reviewId, String status,
          {int? txnLocalId, DatabaseExecutor? tx}) =>
      (tx ?? db).update(
          'processed_fingerprints',
          {
            'status': status,
            'payload': null,
            if (txnLocalId != null) 'txn_local_id': txnLocalId,
          },
          where: 'review_id = ?',
          whereArgs: [reviewId]);

  /// Payee recorded for an auto entry, if any.
  Future<String?> payeeForTxn(int txnLocalId) async {
    final rows = await db.query('processed_fingerprints',
        columns: ['payee'],
        where: 'txn_local_id = ? AND payee IS NOT NULL',
        whereArgs: [txnLocalId],
        limit: 1);
    return rows.isEmpty ? null : rows.first['payee'] as String?;
  }

  Future<void> remapTxn(int oldId, int newId) => db.update(
      'processed_fingerprints', {'txn_local_id': newId},
      where: 'txn_local_id = ?', whereArgs: [oldId]);

  Future<int> prune(Duration maxAge, {DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(maxAge).millisecondsSinceEpoch;
    final n = await db.delete('processed_fingerprints',
        where: 'created_at < ? AND status != ?', whereArgs: [cutoff, FpStatus.adding]);
    await db.delete('pending_review', where: 'created_at < ?', whereArgs: [cutoff]);
    return n;
  }

  // ─── Review list ──────────────────────────────────────────────────────────

  Future<void> putReview(String id, Map<String, dynamic> data, int createdAt,
          {DatabaseExecutor? tx}) =>
      (tx ?? db).insert('pending_review', {'id': id, 'data': jsonEncode(data), 'created_at': createdAt},
          conflictAlgorithm: ConflictAlgorithm.replace);

  Future<Map<String, dynamic>?> getReview(String id) async {
    final rows = await db.query('pending_review', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : jsonDecode(rows.first['data'] as String) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> reviews() async {
    final rows = await db.query('pending_review', orderBy: 'created_at DESC');
    return rows.map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>).toList();
  }

  Future<void> deleteReview(String id, {DatabaseExecutor? tx}) =>
      (tx ?? db).delete('pending_review', where: 'id = ?', whereArgs: [id]);

  // ─── Per-payee category memory ────────────────────────────────────────────

  Future<int?> categoryForPayee(String payee) async {
    final rows = await db.query('payee_categories',
        where: 'payee = ?', whereArgs: [normalizePayee(payee)], limit: 1);
    return rows.isEmpty ? null : rows.first['category_id'] as int;
  }

  Future<void> rememberCategory(String payee, int categoryId) => db.insert(
      'payee_categories',
      {
        'payee': normalizePayee(payee),
        'category_id': categoryId,
        'updated_at': DateTime.now().millisecondsSinceEpoch
      },
      conflictAlgorithm: ConflictAlgorithm.replace);

  static String normalizePayee(String p) =>
      p.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  // ─── Wipe ─────────────────────────────────────────────────────────────────

  Future<void> clearAll() async {
    await db.transaction((tx) async {
      await tx.delete('processed_fingerprints');
      await tx.delete('pending_review');
      await tx.delete('payee_categories');
    });
  }
}
