import 'package:flutter_test/flutter_test.dart';
import 'package:espere_app/services/receipt_parser.dart';

/// All samples were written for Espere (own names, amounts and ids), modelled on the layout
/// of UPI apps' success screens and share texts.
void main() {
  final now = DateTime(2026, 11, 18, 14, 0);

  group('Amazon Pay success screen (OCR text)', () {
    const ocr = '''
1:30
amazon pay
Thank You
LC
LITE CAFE
MAB0450840A0327515@Yesbank
₹60
Banking name: LITE CAFE
Payment of ₹60 to LITE CAFE is
successful
18 Nov 2026, 1:29 PM
View Details
Pay Again
Congratulations!
You've won ₹0.6 cashback
View rewards details at Amazon Pay > Rewards
You've won a Scratch Card
IMPOSSIBLE TRAVEL DEALS
Congrats!
You unlocked flight offers
Save 19%*
Includes flat 9% instant discount
with Amazon Pay UPI
Book now
*T&C apply
Home Account Transactions Rewards''';

    test('amount, payee, time; cashback ignored', () {
      final r = ReceiptParser.parse(ocr, now: now);
      expect(r.amount, 60);
      expect(r.type, 'expense');
      expect(r.payee, 'LITE CAFE');
      expect(r.time, DateTime(2026, 11, 18, 13, 29));
      expect(r.notCompleted, isFalse);
    });

    test('OCR misreading ₹ as % inside the status line still works', () {
      final r = ReceiptParser.parse(
          'LITE CAFE\nPayment of %60 to LITE CAFE is successful\nYou\'ve won ₹0.6 cashback',
          now: now);
      expect(r.amount, 60);
      expect(r.payee, 'LITE CAFE');
    });
  });

  group('OCR that drops or misreads the rupee sign', () {
    const base = '''amazon pay
Thank You
LITE CAFE
MAB0450840A0327515@Yesbank
AMOUNT
Banking name: LITE CAFE
Payment of STATUS to LITE CAFE is
successful
18 Nov 2026, 1:29 PM
You've won ₹0.6 cashback
Save 19%*''';

    for (final (header, status) in [
      ('60', '60'),
      ('*60', '*60'),
      ('R60', 'R60'),
      ('{60', '{60'),
    ]) {
      test('header "$header", status "$status"', () {
        final r = ReceiptParser.parse(
            base.replaceFirst('AMOUNT', header).replaceFirst('STATUS', status),
            now: now);
        expect(r.amount, 60);
        expect(r.payee, 'LITE CAFE');
      });
    }

    for (final (ocr, expected) in [
      ('760', 60.0), // what this phone's OCR returns for "₹60"
      ('7760', 760.0),
      ('71,200', 1200.0),
      ('2500', 500.0),
      ('7120.50', 120.5),
    ]) {
      test('"₹" read as a digit: "$ocr" -> $expected', () {
        final r = ReceiptParser.parse(
            base.replaceFirst('AMOUNT', ocr).replaceFirst('STATUS', ocr),
            now: now);
        expect(r.amount, expected);
      });
    }

    test('a digit is not dropped when a symbol was read', () {
      final r = ReceiptParser.parse(base.replaceFirst('AMOUNT', '*760').replaceFirst('STATUS', '*760'),
          now: now);
      expect(r.amount, 760);
    });

    test('battery level, time and date are never taken as the amount', () {
      final r = ReceiptParser.parse('1:30\n82\nThank You\nLITE CAFE\n18 Nov 2026, 1:29 PM', now: now);
      expect(r.amount, isNull);
    });
  });

  group('Google Pay detail screen (OCR text)', () {
    String screen(String amount) => '''4:19
To TALIB
$amount
Pay again
Completed
3 Nov 2026, 1:35 pm
Punjab National Bank
9025
Payment of $amount completed
Receiver's bank has confirmed
deposit of money to TALIB's bank
account
UPI transaction ID
Having issues? Share Split expense''';

    for (final (ocr, expected) in [
      ('₹140', 140.0),
      ('140', 140.0),
      ('7140', 140.0),
      ('Z140', 140.0),
    ]) {
      test('"$ocr" -> $expected, payee TALIB', () {
        final r = ReceiptParser.parse(screen(ocr), now: now);
        expect(r.amount, expected);
        expect(r.type, 'expense');
        expect(r.payee, 'TALIB');
        expect(r.time, DateTime(2026, 11, 3, 13, 35));
      });
    }
  });

  group('share texts', () {
    test('UPI app share: paid with transaction id', () {
      final r = ReceiptParser.parse(
          'Paid ₹250 to Annapurna Tiffins\nUPI transaction ID: 431298765012\n17 Nov 2026, 8:05 pm',
          now: now);
      expect(r.amount, 250);
      expect(r.type, 'expense');
      expect(r.payee, 'Annapurna Tiffins');
      expect(r.ref, '431298765012');
      expect(r.time, DateTime(2026, 11, 17, 20, 5));
    });

    test('label on one line, value on the next', () {
      final r = ReceiptParser.parse(
          'Paid to\nRahul Verma\n₹1,200\nTransaction ID\nT2611181329004455667788\nNov 18, 2026 11:10 AM',
          now: now);
      expect(r.amount, 1200);
      expect(r.payee, 'Rahul Verma');
      expect(r.ref, 'T2611181329004455667788');
      expect(r.time, DateTime(2026, 11, 18, 11, 10));
    });

    test('money received', () {
      final r = ReceiptParser.parse(
          'Received ₹500 from Neha Kapoor\nUPI Ref No: 612345678901\n18/11/2026 09:15',
          now: now);
      expect(r.amount, 500);
      expect(r.type, 'income');
      expect(r.payee, 'Neha Kapoor');
      expect(r.time, DateTime(2026, 11, 18, 9, 15));
    });

    test('VPA payee shows the handle', () {
      final r = ReceiptParser.parse('You paid Rs. 99 to chaiwala@okaxis', now: now);
      expect(r.amount, 99);
      expect(r.payee, 'chaiwala');
    });
  });

  group('safety', () {
    test('failed payment is flagged', () {
      final r = ReceiptParser.parse('Payment of ₹60 to LITE CAFE failed\nMoney will be refunded',
          now: now);
      expect(r.notCompleted, isTrue);
    });

    test('pending payment is flagged', () {
      final r = ReceiptParser.parse('Payment pending\n₹300 to Gupta Stores', now: now);
      expect(r.notCompleted, isTrue);
    });

    test('two different payment amounts: amount left empty', () {
      final r = ReceiptParser.parse('Paid ₹100 to A\nPaid ₹200 to B', now: now);
      expect(r.amount, isNull);
    });

    test('only promo amounts: no amount', () {
      final r = ReceiptParser.parse('You\'ve won ₹10 cashback\nGet flat ₹50 off', now: now);
      expect(r.amount, isNull);
      expect(r.isEmpty, isTrue);
    });

    test('future date is not used', () {
      final r = ReceiptParser.parse('Paid ₹40 to Tea Point\n20 Dec 2026, 1:00 PM', now: now);
      expect(r.time, isNull);
    });

    test('time only means today', () {
      final r = ReceiptParser.parse('Paid ₹40 to Tea Point\n1:29 PM', now: now);
      expect(r.time, DateTime(2026, 11, 18, 13, 29));
    });
  });
}
