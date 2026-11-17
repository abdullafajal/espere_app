import 'package:espere_app/services/auto_capture_store.dart';
import 'package:espere_app/services/auto_dedup_engine.dart';
import 'package:espere_app/services/notification_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// In-memory stand-in for "cache + SyncService queue".
class FakeSink implements AutoTxnSink {
  final inserted = <AutoTxn>[];
  final manual = <Map<String, dynamic>>[];
  final filled = <int, AutoTxn>{};
  final removed = <int>[];

  /// Simulated crashes for the next insert: before or after the write lands.
  bool crashBeforeWrite = false;
  bool crashAfterWrite = false;

  @override
  Future<List<Map<String, dynamic>>> cachedTransactions() async => [
        ...manual,
        for (final t in inserted)
          {
            'id': t.localId,
            'amount': t.amount.toStringAsFixed(2),
            'type': t.type,
            'date': t.time.toUtc().toIso8601String(),
            'notes': t.notes,
          },
      ];

  @override
  Future<bool> exists(AutoTxn txn) async => inserted.any((t) => t.localId == txn.localId);

  @override
  Future<void> insert(AutoTxn txn) async {
    if (crashBeforeWrite) {
      crashBeforeWrite = false;
      throw StateError('crash before write');
    }
    inserted.add(txn);
    if (crashAfterWrite) {
      crashAfterWrite = false;
      throw StateError('crash after write');
    }
  }

  @override
  Future<void> fillMissing(int localId, AutoTxn from) async => filled[localId] = from;

  @override
  Future<void> remove(int localId) async {
    removed.add(localId);
    inserted.removeWhere((t) => t.localId == localId);
  }
}

final t0 = DateTime(2026, 11, 16, 12, 0);

/// Parses a notification exactly like the app does.
ParseResult parse(String group, String label, String text,
    {String title = '', DateTime? at}) {
  final r = NotificationParser.parse(RawNotification(
    key: 'k',
    packageName: 'p',
    group: group,
    label: label,
    title: title,
    text: text,
    postTime: at ?? t0,
  ));
  expect(r, isNotNull, reason: 'test notification should parse: $text');
  return r!;
}

void main() {
  sqfliteFfiInit();

  late AutoCaptureStore store;
  late FakeSink sink;
  late AutoDedupEngine engine;
  var clock = t0;
  var dbCounter = 0;

  setUp(() async {
    clock = t0;
    store = await AutoCaptureStore.open(
      factory: databaseFactoryFfi,
      path: 'file:auto_test_${dbCounter++}?mode=memory&cache=shared',
    );
    sink = FakeSink();
    engine = AutoDedupEngine(store, sink, now: () => clock);
  });

  tearDown(() => store.db.close());

  Future<AutoOutcome> feed(ParseResult r, {required String key, String text = ''}) =>
      engine.process(r,
          notificationKey: key, textHash: AutoDedupEngine.textHashOf('', text.isEmpty ? key : text, ''));

  test('GPay + bank app + SMS for the same payment produce 1 entry', () async {
    final gpay = parse('gpay', 'Google Pay', 'You paid ₹250 to Swiggy. UPI Ref No. 431234567890');
    final bankApp = parse('banks', 'HDFC Bank',
        'Rs.250.00 from HDFC Bank A/c **1234 to SWIGGY on 16-11-26 Ref 431234567890',
        title: 'Money Sent!', at: t0.add(const Duration(seconds: 20)));
    final sms = parse('sms', 'SMS',
        'Dear UPI user A/C X1234 debited by 250.0 on date 16Nov26 trf to SWIGGY Refno 431234567890.',
        title: 'AD-SBIINB', at: t0.add(const Duration(seconds: 40)));

    expect(await feed(gpay, key: 'gpay#1'), AutoOutcome.added);
    expect(await feed(bankApp, key: 'hdfc#1'), AutoOutcome.duplicate);
    expect(await feed(sms, key: 'sms#1'), AutoOutcome.duplicate);
    expect(sink.inserted, hasLength(1));
  });

  test('a source without a ref (within 3 min) merges instead of inserting', () async {
    final gpay = parse('gpay', 'Google Pay', 'You paid ₹250 to Swiggy. UPI Ref No. 431234567890');
    final card = parse('sms', 'SMS', 'Rs.250.00 spent on HDFC Bank Card x4321 at SWIGGY on 16-11-26',
        title: 'VM-HDFCBK', at: t0.add(const Duration(minutes: 2)));

    expect(await feed(gpay, key: 'gpay#1'), AutoOutcome.added);
    expect(await feed(card, key: 'sms#2'), AutoOutcome.merged);
    expect(sink.inserted, hasLength(1));
    expect(sink.filled.keys, [sink.inserted.single.localId]);
  });

  test('a re-posted notification produces 1 entry', () async {
    final r = parse('phonepe', 'PhonePe', 'Paid ₹349 to Zomato successfully. UTR: 431298765432');
    expect(await feed(r, key: 'pp#1', text: 'same'), AutoOutcome.added);
    expect(await feed(r, key: 'pp#1', text: 'same'), AutoOutcome.duplicate);
    expect(sink.inserted, hasLength(1));
  });

  test('two real ₹100 payments 10 min apart produce 2 entries', () async {
    final a = parse('gpay', 'Google Pay', 'You paid ₹100 to Tea Stall. UPI Ref No. 431200000001');
    final b = parse('gpay', 'Google Pay', 'You paid ₹100 to Tea Stall. UPI Ref No. 431200000002',
        at: t0.add(const Duration(minutes: 10)));
    expect(await feed(a, key: 'g#1'), AutoOutcome.added);
    clock = t0.add(const Duration(minutes: 10));
    expect(await feed(b, key: 'g#2'), AutoOutcome.added);
    expect(sink.inserted, hasLength(2));
  });

  test('two ₹100 payments without refs 10 min apart stay 2 separate review items', () async {
    final a = parse('gpay', 'Google Pay', '₹100 paid to Tea Stall');
    final b = parse('gpay', 'Google Pay', '₹100 paid to Tea Stall', at: t0.add(const Duration(minutes: 10)));
    expect(await feed(a, key: 'g#1'), AutoOutcome.review);
    expect(await feed(b, key: 'g#2'), AutoOutcome.review);
    expect(await store.reviews(), hasLength(2));
    expect(sink.inserted, isEmpty);
  });

  test('a crash after the write lands produces no duplicate', () async {
    final r = parse('gpay', 'Google Pay', 'You paid ₹250 to Swiggy. UPI Ref No. 431234567890');
    sink.crashAfterWrite = true;
    await expectLater(feed(r, key: 'g#1'), throwsStateError);

    // "Restart": new engine over the same store; the native event was never acked.
    final restarted = AutoDedupEngine(store, sink, now: () => clock);
    expect(await restarted.recover(), 0);
    expect(
        await restarted.process(r,
            notificationKey: 'g#1', textHash: AutoDedupEngine.textHashOf('', 'g#1', '')),
        AutoOutcome.duplicate);
    expect(sink.inserted, hasLength(1));
  });

  test('a crash before the write lands is completed exactly once', () async {
    final r = parse('gpay', 'Google Pay', 'You paid ₹250 to Swiggy. UPI Ref No. 431234567890');
    sink.crashBeforeWrite = true;
    await expectLater(feed(r, key: 'g#1'), throwsStateError);
    expect(sink.inserted, isEmpty);

    final restarted = AutoDedupEngine(store, sink, now: () => clock);
    expect(await restarted.recover(), 1);
    expect(await restarted.recover(), 0); // idempotent
    expect(
        await restarted.process(r,
            notificationKey: 'g#1', textHash: AutoDedupEngine.textHashOf('', 'g#1', '')),
        AutoOutcome.duplicate);
    expect(sink.inserted, hasLength(1));
  });

  test('a deleted entry stays deleted', () async {
    final gpay = parse('gpay', 'Google Pay', 'You paid ₹250 to Swiggy. UPI Ref No. 431234567890');
    expect(await feed(gpay, key: 'g#1'), AutoOutcome.added);
    await engine.markDeleted(sink.inserted.single.localId);

    final bankSameRef = parse('banks', 'HDFC Bank',
        'Rs.250.00 from HDFC Bank A/c **1234 to SWIGGY on 16-11-26 Ref 431234567890',
        title: 'Money Sent!', at: t0.add(const Duration(minutes: 1)));
    final smsNoRef = parse('sms', 'SMS', 'Rs.250.00 spent on HDFC Bank Card x1234 at SWIGGY',
        title: 'VM-HDFCBK', at: t0.add(const Duration(minutes: 2)));
    expect(await feed(bankSameRef, key: 'hdfc#1'), AutoOutcome.dismissed);
    expect(await feed(smsNoRef, key: 'sms#1'), AutoOutcome.dismissed);
    expect(await feed(gpay, key: 'g#1-repost', text: 'other'), AutoOutcome.dismissed);
    expect(sink.inserted, hasLength(1)); // only the original, nothing recreated
  });

  test('deletion after the server assigned a real id still sticks', () async {
    final r = parse('gpay', 'Google Pay', 'You paid ₹250 to Swiggy. UPI Ref No. 431234567890');
    await feed(r, key: 'g#1');
    await engine.remap(sink.inserted.single.localId, 671);
    await engine.markDeleted(671);
    final again = parse('banks', 'HDFC Bank', 'Rs.250.00 paid to SWIGGY Ref 431234567890');
    expect(await feed(again, key: 'b#1'), AutoOutcome.dismissed);
  });

  test('a manual entry within 10 min is linked, not duplicated', () async {
    sink.manual.add({
      'id': 555,
      'amount': '250.00',
      'type': 'expense',
      'date': t0.subtract(const Duration(minutes: 6)).toUtc().toIso8601String(),
      'notes': 'Lunch',
    });
    final r = parse('gpay', 'Google Pay', 'You paid ₹250 to Swiggy. UPI Ref No. 431234567890');
    expect(await feed(r, key: 'g#1'), AutoOutcome.linkedToManual);
    expect(sink.inserted, isEmpty);

    // The manual entry stands in for one payment only: a second real ₹250 is added.
    final second = parse('gpay', 'Google Pay', 'You paid ₹250 to Swiggy. UPI Ref No. 431234567899',
        at: t0.add(const Duration(minutes: 3, seconds: 30)));
    expect(await feed(second, key: 'g#2'), AutoOutcome.added);
    expect(sink.inserted, hasLength(1));
  });

  test('low confidence waits for review; a second source promotes it once', () async {
    final card = parse('sms', 'SMS', 'Rs.1,299.00 spent on HDFC Bank Card x4321 at AMAZON',
        title: 'VM-HDFCBK');
    expect(card.confidence, ParseConfidence.low);
    expect(await feed(card, key: 'sms#1'), AutoOutcome.review);
    expect(await store.reviews(), hasLength(1));

    final app = parse('banks', 'HDFC Bank', 'Rs.1,299.00 spent on Card x4321 at AMAZON',
        at: t0.add(const Duration(minutes: 1)));
    expect(await feed(app, key: 'app#1'), AutoOutcome.promoted);
    expect(sink.inserted, hasLength(1));
    expect(sink.inserted.single.payee, 'AMAZON');
    expect(await store.reviews(), isEmpty);

    final third = parse('sms', 'SMS', 'Rs.1,299.00 spent on HDFC Bank Card x4321 at AMAZON',
        title: 'VM-HDFCBK', at: t0.add(const Duration(minutes: 2)));
    expect(await feed(third, key: 'sms#2'), AutoOutcome.merged);
    expect(sink.inserted, hasLength(1));
  });

  test('confirming a review item adds it once; a discarded one never returns', () async {
    final a = parse('paytm', 'Paytm', '₹25 cashback received in your Paytm Wallet');
    expect(await feed(a, key: 'p#1'), AutoOutcome.review);
    final id = (await store.reviews()).single['review_id'] as String;
    final txn = await engine.confirmReview(id, categoryId: 9);
    expect(txn!.categoryId, 9);
    expect(await engine.confirmReview(id), isNull); // second tap does nothing
    expect(sink.inserted, hasLength(1));

    final b = parse('gpay', 'Google Pay', '₹80 paid to Auto Rickshaw',
        at: t0.add(const Duration(minutes: 30)));
    expect(await feed(b, key: 'g#9'), AutoOutcome.review);
    final id2 = (await store.reviews()).single['review_id'] as String;
    await engine.discardReview(id2);
    expect(await store.reviews(), isEmpty);
    expect(await feed(b, key: 'g#9-again', text: 'x'), AutoOutcome.dismissed);
    expect(sink.inserted, hasLength(1));
  });

  test('fingerprints older than 60 days are pruned', () async {
    final r = parse('gpay', 'Google Pay', 'You paid ₹250 to Swiggy. UPI Ref No. 431234567890');
    await feed(r, key: 'g#1');
    clock = t0.add(const Duration(days: 61));
    await engine.recover();
    final rows = await store.db.query('processed_fingerprints');
    expect(rows, isEmpty);
  });

  test('concurrent events for the same payment are serialized (1 entry)', () async {
    final a = parse('gpay', 'Google Pay', 'You paid ₹250 to Swiggy. UPI Ref No. 431234567890');
    final b = parse('banks', 'HDFC Bank', 'Rs.250.00 paid to SWIGGY Ref 431234567890');
    final c = parse('sms', 'SMS', 'A/C X1234 debited by 250.0 trf to SWIGGY Refno 431234567890',
        title: 'AD-SBIINB');
    final outcomes = await Future.wait([
      feed(a, key: 'a'),
      feed(b, key: 'b'),
      feed(c, key: 'c'),
    ]);
    expect(outcomes.where((o) => o == AutoOutcome.added), hasLength(1));
    expect(sink.inserted, hasLength(1));
  });

  test('stored data contains no raw text or full reference', () async {
    final r = parse('gpay', 'Google Pay', 'You paid ₹250 to Swiggy. UPI Ref No. 431234567890');
    await feed(r, key: 'g#1', text: 'You paid ₹250 to Swiggy. UPI Ref No. 431234567890');
    final dump = (await store.db.query('processed_fingerprints')).toString() +
        (await store.db.query('pending_review')).toString();
    expect(dump, isNot(contains('431234567890')));
    expect(dump, isNot(contains('You paid')));
    // Notes look like a manual entry: just the payee, never the reference.
    expect(sink.inserted.single.notes, 'Swiggy');
  });

  test('a reversal with the same ref removes the auto expense (no wrong entry left)', () async {
    final debit = parse('sms', 'SMS',
        'Rs.499.00 debited from A/c XX2211 to VPA shop@okhdfc. UPI Ref No 431255550001',
        title: 'VM-HDFCBK');
    expect(await feed(debit, key: 'sms#1'), AutoOutcome.added);
    final id = sink.inserted.single.localId;

    final reversal = parse('sms', 'SMS',
        'UPI reversal: Rs.499.00 credited back to A/c XX2211. UPI Ref No 431255550001',
        title: 'VM-HDFCBK', at: t0.add(const Duration(hours: 5)));
    expect(reversal.isReversal, isTrue);
    expect(await feed(reversal, key: 'sms#2'), AutoOutcome.reversed, reason: 'only expenses tracked');
    expect(sink.removed, [id]);
    expect(sink.inserted, isEmpty);

    // The same payment never comes back afterwards.
    expect(await feed(debit, key: 'app#1', text: 'other'), AutoOutcome.dismissed);
  });

  test('a reversal of a payment still in Review removes the Review item', () async {
    final nach = parse('sms', 'SMS',
        'Rs. 2,000.00 debited from A/c XX7788 towards NACH-ACME MF SIP. Ref 431277770001',
        title: 'VM-ICICIT');
    expect(nach.confidence, ParseConfidence.low); // NACH is never added silently
    expect(await feed(nach, key: 'sms#1'), AutoOutcome.review);
    final reversal = parse('sms', 'SMS',
        'Rs. 2,000.00 reversed to A/c XX7788. Ref 431277770001', title: 'VM-ICICIT');
    expect(await feed(reversal, key: 'sms#2'), AutoOutcome.reversed);
    expect(await store.reviews(), isEmpty);
  });

  test('an unmatched refund is ignored when only expenses are tracked', () async {
    final refund = parse('amazonpay', 'Amazon Pay', 'Refund of ₹799 credited to your Amazon Pay balance');
    expect(
        await engine.process(refund,
            notificationKey: 'a#1',
            textHash: AutoDedupEngine.textHashOf('', 'a#1', ''),
            allowIncome: false),
        AutoOutcome.ignored);
    expect(await store.reviews(), isEmpty);
    // With income tracking on it waits in Review (refunds are never added silently).
    expect(await feed(refund, key: 'a#2'), AutoOutcome.review);
  });

  test('the payee of an auto entry is remembered for category learning', () async {
    final r = parse('gpay', 'Google Pay', 'You paid ₹250 to Swiggy. UPI Ref No. 431234567890');
    await feed(r, key: 'g#1');
    expect(await engine.payeeForTxn(sink.inserted.single.localId), 'Swiggy');
    expect(await engine.payeeForTxn(424242), isNull);
  });
}
