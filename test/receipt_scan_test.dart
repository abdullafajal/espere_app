import 'package:flutter_test/flutter_test.dart';
import 'package:espere_app/services/receipt_parser.dart';

/// Screenshot tests with OCR layout (line boxes in pixels).
///
/// The first three fixtures are the real line boxes an OCR engine returned for real
/// Amazon Pay, Google Pay and PhonePe success screens (1080x2340). Every "₹amount" is written
/// as {amount} and replaced per test by what different OCR models make of the rupee sign:
/// "₹60" (reads it), "60" (drops it), "760" / "260" (reads it as a digit), "Z60".
///
/// The other fixtures are app layouts written for Espere (own names and numbers), with
/// realistic font sizes.
void main() {
  final now = DateTime(2026, 11, 18, 16, 0);

  OcrLine l(String t, int left, int top, int right, int bottom) => OcrLine(t, left, top, right, bottom);

  /// What an OCR model writes for "₹" in each mode.
  const modes = {'keep': '₹', 'drop': '', '7': '7', '2': '2', 'Z': 'Z'};

  OcrScan scan(List<OcrLine> lines, String mode, {bool calibrated = true}) => OcrScan(
        width: 1080,
        height: 2340,
        rupee: calibrated ? mode : null,
        lines: [
          for (final x in lines)
            OcrLine(x.text.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (m) => '${modes[mode]}${m[1]}'),
                x.left, x.top, x.right, x.bottom),
        ],
      );

  /// Builds a layout top to bottom: (text, font height in px).
  List<OcrLine> stack(List<(String, int)> rows) {
    var y = 200; // below the status bar
    return [
      for (final (t, h) in rows) l(t, 60, y, 60 + t.length * h ~/ 2, (y += h + 30) - 30),
    ];
  }

  final amazon = [
    l('1.93', 808, 35, 856, 57), l('50', 865, 34, 905, 65), l('1:30', 48, 39, 130, 74),
    l('82', 965, 37, 1012, 73), l('K/s', 811, 53, 852, 76),
    l('amazon pay', 384, 134, 689, 188), l('Thank You', 50, 294, 357, 346),
    l('LITE CAFE', 230, 466, 452, 500), l('{60}', 871, 479, 1021, 548), l('LC', 86, 489, 153, 536),
    l('MAB0450840A0327515@Yesbank', 227, 531, 790, 562),
    l('Banking name:', 51, 668, 289, 698), l('LITE CAFE', 346, 665, 511, 695),
    l('Payment of {60} to LITE CAFE is', 48, 815, 750, 861), l('successful', 44, 875, 276, 921),
    l('18 Nov 2026, 1:29 PM', 50, 968, 412, 1003),
    l('View Details', 105, 1111, 347, 1148), l('Pay Again', 494, 1107, 695, 1157),
    l('Congratulations!', 51, 1281, 320, 1314), l("You've won {0.6} cashback", 52, 1340, 558, 1373),
    l('View rewards details at Amazon Pay > Rewards', 48, 1394, 811, 1426),
    l("You've won a Scratch Card", 51, 1484, 566, 1520),
    l('IMPOSSIBLETRAVELDEALS', 146, 1734, 388, 1751), l('Congrats!', 77, 1784, 237, 1821),
    l('Youunlockedflightoffers', 77, 1838, 395, 1864), l('Save19%*', 77, 1873, 212, 1900),
    l('Includesflat9%instantdiscount', 144, 1926, 449, 1949), l('Booknow>', 74, 1996, 222, 2026),
    l('Home', 75, 2240, 162, 2271), l('Transactions', 665, 2242, 838, 2269),
  ];

  final gpay = [
    l('4:19', 54, 36, 137, 73), l('21.61', 790, 33, 848, 58), l('W Shree Renuka', 168, 42, 407, 68),
    l('60', 977, 38, 1019, 71), l('K/s', 799, 52, 842, 78),
    l('To TALIB', 444, 494, 635, 535), l('{140}', 423, 623, 707, 764),
    l('Pay again', 440, 914, 639, 965), l('Completed', 461, 1091, 687, 1134),
    l('3 Nov 2026, 1:35 pm', 345, 1223, 734, 1269),
    l('Punjab National Bank', 313, 1409, 794, 1455), l('9025', 311, 1479, 429, 1525),
    l('Payment of {140} completed', 238, 1626, 877, 1675),
    l("Receiver's bank has confirmed", 242, 1722, 845, 1758),
    l("deposit of money to TALIB's bank", 239, 1779, 902, 1824), l('account', 239, 1845, 406, 1879),
    l('UP transaction ID', 122, 2022, 482, 2059),
    l('Share', 648, 2158, 776, 2207), l('Having issues?', 183, 2161, 480, 2204),
  ];

  final phonepe = [
    l('177.1', 792, 33, 850, 58), l('4:22', 56, 39, 143, 74), l('59', 976, 37, 1019, 73),
    l('Transaction Successful', 219, 146, 769, 185), l('08:18 pm on 14 0ct 2026', 217, 201, 644, 234),
    l('Paid to', 70, 342, 221, 383),
    l('Flipkart Payments', 241, 456, 646, 506), l('{1,232}', 850, 455, 1010, 505), l('FP', 100, 474, 164, 521),
    l('paytm-56505013@ptybl', 238, 524, 725, 571), l('Transfer Details', 195, 686, 504, 722),
    l('PhonePe Transaction iD', 74, 793, 476, 823), l('T2610142018372270123469', 76, 857, 633, 891),
    l('Debited from', 73, 951, 293, 987),
    l('XXXXXX9025', 244, 1039, 553, 1076), l('{1,232}', 857, 1035, 1010, 1083),
    l('UTR: 234372128842', 241, 1138, 676, 1176),
    l('View History', 119, 1463, 336, 1503), l('Share Receipt', 734, 1467, 971, 1503),
    l('Contact PhonePe Support', 240, 1654, 759, 1696),
    l('Pay securely with fingerp...', 94, 1860, 655, 1907), l('Enjoy seamless and safer', 96, 1924, 529, 1960),
    l('payments up to {10,000}.', 95, 1973, 512, 2011), l('Activate Now', 131, 2090, 368, 2126),
  ];

  group('real screenshots, every rupee-sign reading', () {
    for (final mode in modes.keys) {
      for (final calibrated in [true, false]) {
        final tag = '$mode${calibrated ? '' : ', not calibrated'}';

        test('Amazon Pay ($tag)', () {
          final r = ReceiptParser.parseScan(scan(amazon, mode, calibrated: calibrated), now: now);
          expect(r.amount, 60);
          expect(r.type, 'expense');
          expect(r.payee, 'LITE CAFE');
          expect(r.time, DateTime(2026, 11, 18, 13, 29));
          expect(r.notCompleted, isFalse);
        });

        test('Google Pay ($tag)', () {
          final r = ReceiptParser.parseScan(scan(gpay, mode, calibrated: calibrated), now: now);
          expect(r.amount, 140);
          expect(r.type, 'expense');
          expect(r.payee, 'TALIB');
          expect(r.time, DateTime(2026, 11, 3, 13, 35));
        });

        test('PhonePe ($tag)', () {
          final r = ReceiptParser.parseScan(scan(phonepe, mode, calibrated: calibrated), now: now);
          expect(r.amount, 1232);
          expect(r.type, 'expense');
          expect(r.payee, 'Flipkart Payments');
          expect(r.time, DateTime(2026, 10, 14, 20, 18));
          expect(r.ref, 'T2610142018372270123469');
        });
      }
    }
  });

  group('amounts that start with 7 or 2', () {
    // With the measured reading, "₹250" read as "250" (drop) and "2250" (2) both work.
    for (final mode in modes.keys) {
      test('₹250 / ₹750, OCR mode $mode', () {
        for (final amount in ['250', '750']) {
          final lines = stack([
            ('Paid to', 40), ('Sharma Kirana', 50), ('{$amount}', 140),
            ('Payment of {$amount} completed', 48), ('5 Nov 2026, 9:10 am', 44),
          ]);
          final r = ReceiptParser.parseScan(scan(lines, mode), now: now);
          expect(r.amount, double.parse(amount), reason: '$amount in mode $mode');
          expect(r.payee, 'Sharma Kirana');
        }
      });
    }
  });

  group('other apps (layouts written for Espere)', () {
    test('Paytm', () {
      final lines = stack([
        ('Paid Successfully to', 44), ('Meera Medicals', 52), ('{1,045}', 120),
        ('UPI Ref. No: 615432198765', 36), ('From: State Bank of India - 4410', 36),
        ('12 Nov 2026, 07:42 PM', 36), ('Cashback of {25} credited', 36),
      ]);
      for (final mode in modes.keys) {
        final r = ReceiptParser.parseScan(scan(lines, mode), now: now);
        expect(r.amount, 1045, reason: mode);
        expect(r.payee, 'Meera Medicals', reason: mode);
        expect(r.ref, '615432198765', reason: mode);
        expect(r.time, DateTime(2026, 11, 12, 19, 42), reason: mode);
        expect(r.type, 'expense', reason: mode);
      }
    });

    test('BHIM', () {
      final lines = stack([
        ('Transaction Successful', 48), ('{2,400.00}', 110), ('Paid to', 36),
        ('Gupta Electricals', 44), ('UPI Ref No 618899001122', 36), ('09-11-2026 11:05', 36),
      ]);
      for (final mode in modes.keys) {
        final r = ReceiptParser.parseScan(scan(lines, mode), now: now);
        expect(r.amount, 2400, reason: mode);
        expect(r.payee, 'Gupta Electricals', reason: mode);
        expect(r.time, DateTime(2026, 11, 9, 11, 5), reason: mode);
      }
    });

    test('CRED', () {
      final lines = stack([
        ('payment successful', 46), ('{399}', 130), ('paid to Brew Bay Cafe', 40),
        ('on 16 Nov 2026 at 9:41 pm', 36), ('you earned 399 CRED coins', 36),
      ]);
      for (final mode in modes.keys) {
        final r = ReceiptParser.parseScan(scan(lines, mode), now: now);
        expect(r.amount, 399, reason: mode);
        expect(r.payee, 'Brew Bay Cafe', reason: mode);
        expect(r.time, DateTime(2026, 11, 16, 21, 41), reason: mode);
      }
    });

    test('WhatsApp Pay', () {
      final lines = stack([
        ('Payment to Imran', 44), ('{500}', 120), ('Completed', 40),
        ('17 Nov 2026, 6:02 pm', 36), ('UPI transaction ID', 34), ('431877665544', 36),
      ]);
      for (final mode in modes.keys) {
        final r = ReceiptParser.parseScan(scan(lines, mode), now: now);
        expect(r.amount, 500, reason: mode);
        expect(r.payee, 'Imran', reason: mode);
        expect(r.ref, '431877665544', reason: mode);
      }
    });

    test('bank app (Amount label, balance must be ignored)', () {
      final lines = stack([
        ('Transaction Successful', 48), ('Amount', 36), ('{3,500.00}', 70),
        ('Beneficiary Name: Ravi Kumar', 36), ('Available Balance: {41,210.55}', 36),
        ('Ref No: 432100998877', 36), ('15/11/2026 10:20', 36),
      ]);
      for (final mode in modes.keys) {
        final r = ReceiptParser.parseScan(scan(lines, mode), now: now);
        expect(r.amount, 3500, reason: mode);
        expect(r.payee, 'Ravi Kumar', reason: mode);
        expect(r.time, DateTime(2026, 11, 15, 10, 20), reason: mode);
      }
    });

    test('money received (Google Pay)', () {
      final lines = stack([
        ('From Anita Desai', 44), ('{1,500}', 140), ('Completed', 40),
        ('10 Nov 2026, 8:15 am', 36), ('UPI transaction ID', 34), ('431800112233', 36),
      ]);
      for (final mode in modes.keys) {
        final r = ReceiptParser.parseScan(scan(lines, mode), now: now);
        expect(r.amount, 1500, reason: mode);
        expect(r.type, 'income', reason: mode);
        expect(r.payee, 'Anita Desai', reason: mode);
      }
    });

    test('money received (PhonePe)', () {
      final lines = stack([
        ('Received from', 40), ('Karan Mehta', 48), ('{820}', 70), ('Credited to', 36),
        ('XXXXXX9025 {820}', 40), ('11:30 am on 2 Nov 2026', 36),
      ]);
      for (final mode in modes.keys) {
        final r = ReceiptParser.parseScan(scan(lines, mode), now: now);
        expect(r.amount, 820, reason: mode);
        expect(r.type, 'income', reason: mode);
        expect(r.payee, 'Karan Mehta', reason: mode);
        expect(r.time, DateTime(2026, 11, 2, 11, 30), reason: mode);
      }
    });

    test('measured "keep" but this app\'s font reads ₹ as 7', () {
      final lines = stack([('Paid to', 40), ('Asha Bakery', 48), ('760', 130), ('Payment of 760 completed', 44)]);
      final r = ReceiptParser.parseScan(
          OcrScan(width: 1080, height: 2340, lines: lines, rupee: 'keep'), now: now);
      expect(r.amount, 60);
    });

    test('failed payment is flagged', () {
      final lines = stack([('Payment Failed', 48), ('{300}', 120), ('To Sunil', 40)]);
      final r = ReceiptParser.parseScan(scan(lines, 'keep'), now: now);
      expect(r.notCompleted, isTrue);
    });

    test('two different big amounts: amount left empty', () {
      final lines = stack([('{300}', 120), ('{450}', 120), ('Completed', 40)]);
      final r = ReceiptParser.parseScan(scan(lines, 'keep'), now: now);
      expect(r.amount, isNull);
    });
  });
}
