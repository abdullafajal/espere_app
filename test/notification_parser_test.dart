import 'package:espere_app/services/notification_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Expected outcome of one parser case. `amount == null` means "must be rejected".
class _Case {
  final String name;
  final String group;
  final String label;
  final String title;
  final String text;
  final double? amount;
  final String? type;
  final String? payee;
  final String? ref;
  final String? last4;
  final String? method;
  final ParseConfidence? confidence;
  final bool? reversal;

  const _Case(
    this.name, {
    required this.group,
    required this.label,
    this.title = '',
    required this.text,
    this.amount,
    this.type,
    this.payee,
    this.ref,
    this.last4,
    this.method,
    this.confidence,
    this.reversal,
  });

  bool get rejected => amount == null;
}

const _gpay = ('gpay', 'Google Pay');
const _phonepe = ('phonepe', 'PhonePe');
const _paytm = ('paytm', 'Paytm');
const _bhim = ('bhim', 'BHIM');
const _amazon = ('amazonpay', 'Amazon Pay');
const _cred = ('cred', 'CRED');
const _whatsapp = ('whatsapp', 'WhatsApp');
const _bank = ('banks', 'HDFC Bank');
const _sms = ('sms', 'SMS');

_Case _c(
  String name,
  (String, String) src, {
  String title = '',
  required String text,
  double? amount,
  String? type,
  String? payee,
  String? ref,
  String? last4,
  String? method,
  ParseConfidence? confidence,
  bool? reversal,
}) =>
    _Case(name,
        group: src.$1,
        label: src.$2,
        title: title,
        text: text,
        amount: amount,
        type: type,
        payee: payee,
        ref: ref,
        last4: last4,
        method: method,
        confidence: confidence,
        reversal: reversal);

final _cases = <_Case>[
  // ─── UPI apps: expenses ─────────────────────────────────────────────────
  _c('GPay paid with ref', _gpay,
      title: 'Paid to Swiggy',
      text: 'You paid ₹250 to Swiggy. UPI Ref No. 431234567890',
      amount: 250, type: 'expense', payee: 'Swiggy', ref: '431234567890', method: 'upi',
      confidence: ParseConfidence.high),
  _c('GPay paid without ref is LOW', _gpay,
      title: 'Payment successful', text: '₹1,299.50 paid to Myntra',
      amount: 1299.5, type: 'expense', payee: 'Myntra', method: 'upi',
      confidence: ParseConfidence.low),
  _c('PhonePe paid successfully', _phonepe,
      text: 'Paid ₹349 to Zomato successfully. UTR: 431298765432',
      amount: 349, type: 'expense', payee: 'Zomato', ref: '431298765432',
      confidence: ParseConfidence.high),
  _c('Paytm paid with txn id', _paytm,
      text: 'Rs.150 paid to Uber India. Txn ID: 26111612345678',
      amount: 150, type: 'expense', payee: 'Uber India', ref: '26111612345678'),
  _c('BHIM sent to VPA', _bhim,
      text: 'You have sent Rs 500.00 to rahul.k@oksbi. UPI Ref: 431211112222',
      amount: 500, type: 'expense', payee: 'rahul.k', ref: '431211112222'),
  _c('Amazon Pay payment of', _amazon,
      text: 'Payment of ₹2,499 to Amazon Seller Services successful. Ref 431277778888',
      amount: 2499, type: 'expense', payee: 'Amazon Seller Services', ref: '431277778888'),
  _c('CRED credit-card bill payment is not spending (double count)', _cred,
      text: 'Paid ₹12,450 to HDFC Credit Card. Transaction ID: CRED26111698765432'),
  _c('WhatsApp Pay sent', _whatsapp,
      text: 'You sent ₹200 to Ankit. UPI transaction ID 431255556666',
      amount: 200, type: 'expense', payee: 'Ankit', ref: '431255556666'),

  // ─── UPI apps: income ───────────────────────────────────────────────────
  _c('GPay sent you', _gpay,
      text: 'Rahul Sharma sent you ₹500. UPI Ref No. 431233334444',
      amount: 500, type: 'income', payee: 'Rahul Sharma', ref: '431233334444',
      confidence: ParseConfidence.high),
  _c('PhonePe received from', _phonepe,
      text: 'Received ₹1,000 from Priya. UTR 431244445555',
      amount: 1000, type: 'income', payee: 'Priya', ref: '431244445555'),
  _c('Paytm cashback received', _paytm,
      text: '₹25 cashback received in your Paytm Wallet',
      amount: 25, type: 'income', confidence: ParseConfidence.low),
  _c('Refund credited', _amazon,
      text: 'Refund of ₹799 credited to your Amazon Pay balance',
      amount: 799, type: 'income'),

  // ─── Bank apps and bank SMS ─────────────────────────────────────────────
  _c('HDFC app money sent', _bank,
      title: 'Money Sent!',
      text: 'Rs.250.00 from HDFC Bank A/c **1234 to SWIGGY on 16-11-26 Ref 431234567890',
      amount: 250, type: 'expense', payee: 'SWIGGY', ref: '431234567890', last4: '1234'),
  _c('HDFC SMS credit from VPA', _sms,
      title: 'VM-HDFCBK',
      text: 'Rs. 1,500.00 credited to HDFC Bank A/c XX1234 on 16-11-26 from VPA '
          'rahul@okicici (UPI 431298765432)',
      amount: 1500, type: 'income', payee: 'rahul', ref: '431298765432', last4: '1234',
      method: 'upi'),
  _c('SBI SMS debited by (no currency sign)', _sms,
      title: 'AD-SBIINB',
      text: 'Dear UPI user A/C X1234 debited by 250.0 on date 16Nov26 trf to SWIGGY '
          'Refno 431212345678. If not u? call 1800111109. -SBI',
      amount: 250, type: 'expense', payee: 'SWIGGY', ref: '431212345678', last4: '1234',
      confidence: ParseConfidence.high),
  _c('ICICI SMS debited; X credited', _sms,
      title: 'VM-ICICIT',
      text: 'ICICI Bank Acct XX123 debited for Rs 250.00 on 16-Nov-26; SWIGGY credited. '
          'UPI:431234567890. Call 18002662 for dispute.',
      amount: 250, type: 'expense', payee: 'SWIGGY', ref: '431234567890'),
  _c('Axis SMS UPI/P2M path', _sms,
      title: 'JD-AXISBK-S',
      text: 'INR 500.00 debited A/c no. XX1234 16-11-26 12:30:11 UPI/P2M/431234567890/ZOMATO '
          'Not you? SMS BLOCKALL to 919951860002',
      amount: 500, type: 'expense', payee: 'ZOMATO', ref: '431234567890', last4: '1234'),
  _c('Kotak SMS sent from', _sms,
      title: 'AX-KOTAKB',
      text: 'Sent Rs.250.00 from Kotak Bank AC X1234 to swiggy@icici on 16-11-26.UPI Ref '
          '431234567890. Not you, https://kotak.com/KBANKT/Fraud',
      amount: 250, type: 'expense', payee: 'swiggy', ref: '431234567890', last4: '1234'),
  _c('Card spend SMS (no ref -> LOW)', _sms,
      title: 'VM-HDFCBK',
      text: 'Rs.1,299.00 spent on HDFC Bank Card x4321 at AMAZON on 2026-11-16:12:30:11. '
          'Not You? To Block+Reissue Call 18002586161',
      amount: 1299, type: 'expense', payee: 'AMAZON', last4: '4321', method: 'card',
      confidence: ParseConfidence.low),
  _c('ATM withdrawal', _sms,
      title: 'AD-SBIINB',
      text: 'Rs 2000 withdrawn from A/c XX5678 at SBI ATM on 16Nov26. Avl Bal Rs 12,345.67',
      amount: 2000, type: 'expense', last4: '5678', method: 'bank'),
  _c('Debit with balance in same SMS', _sms,
      title: 'VM-HDFCBK',
      text: 'INR 3,450.00 debited from A/c XX9999 on 16-11-26 to ELECTRICITY BOARD. '
          'Avl Bal: INR 22,100.50. UTR 431200001111',
      amount: 3450, type: 'expense', ref: '431200001111', last4: '9999'),
  _c('Salary credited', _sms,
      title: 'VM-HDFCBK',
      text: 'Rs. 45,000.00 credited to A/c XX1234 on 01-11-26 by NEFT from ACME PVT LTD. '
          'Ref NEFT12345678',
      amount: 45000, type: 'income', last4: '1234', ref: 'NEFT12345678'),

  // ─── Rejections ─────────────────────────────────────────────────────────
  _c('OTP', _sms,
      title: 'VM-HDFCBK',
      text: 'OTP for txn of Rs 2,500 at AMAZON is 123456. Do not share it with anyone.'),
  _c('Collect request', _gpay, text: 'Rahul has requested ₹500 from you'),
  _c('Payment request', _phonepe, text: 'Payment request of ₹1,200 from Electricity Board'),
  _c('Reminder / due', _cred, text: 'Reminder: ₹12,450 is due on your HDFC credit card by 20 Nov'),
  _c('Failed payment', _gpay, text: 'Payment of ₹250 to Swiggy failed. Money will be refunded'),
  _c('Pending payment', _phonepe, text: '₹500 payment to Ankit is pending'),
  _c('Offer / ad', _paytm, text: 'Get flat ₹100 cashback on your next recharge! Hurry'),
  _c('Cashback up to ad', _amazon, text: 'Shop now and get cashback up to ₹500 on electronics'),
  _c('Balance-only alert', _sms,
      title: 'VM-HDFCBK', text: 'Available balance in A/c XX1234 is Rs 25,000.00 as on 16-11-26'),
  _c('Mandate setup', _gpay, text: 'UPI AutoPay mandate of ₹199 for Netflix set up successfully'),
  _c('Future autopay debit notice', _sms,
      title: 'VM-ICICIT', text: 'Rs 499 will be debited from A/c XX1234 on 20-11-26 for Netflix mandate'),
  _c('Personal SMS ignored', _sms, title: 'Mom', text: 'I paid ₹500 for the groceries'),
  _c('Personal number ignored', _sms, title: '+919876543210', text: 'Sent you ₹200 on GPay'),
  _c('Two different amounts is ambiguous', _paytm,
      text: 'You paid ₹500 and ₹300 was paid by Ravi'),
  _c('No amount', _gpay, text: 'Your payment to Swiggy was successful'),
  _c('No direction word', _bank, text: 'Your A/c XX1234: transaction of Rs 300'),
  _c('Promotional SMS from non-bank sender', _sms,
      title: 'AD-SWIGGY', text: 'Order now and get ₹100 off. Paid users only'),

  // ─── R&D: wordings seen across Indian banks (own sample values) ────────
  _c('UPI debit with a "Use UPI Lite" tagline is still a payment', _sms,
      title: 'JD-FEDBK-S',
      text: 'Rs 320.00 debited via UPI on 02-11-26 to VPA chaiwala@oksbi.Ref No 431266660001.'
          'Small txns?Use UPI Lite!-Federal Bank',
      amount: 320, type: 'expense', payee: 'chaiwala', ref: '431266660001',
      confidence: ParseConfidence.high),
  _c('"DEBIT:Rs" with the amount glued to the colon', _sms,
      title: 'AD-SIBANK',
      text: 'A/c X5521 DEBIT:Rs.640.50 CAFE NOIR Bal:Rs.9,210.00 -South Indian Bank',
      amount: 640.5, type: 'expense', last4: '5521'),
  _c('"Dr INR" short form', _sms,
      title: 'AX-AUBANK', text: 'Dr INR 1,200.00 from A/c X9012 on 03-NOV-2026',
      amount: 1200, type: 'expense'),
  _c('"Cr. to" short form with balance and ref', _sms,
      title: 'VM-BOBTXN',
      text: 'Rs.750.00 Cr. to rahul@ybl A/c XX4455 on 04-11-2026. AvlBal:Rs8,000.00. '
          'Ref:431299991111 -Bank of Baroda',
      amount: 750, type: 'income', ref: '431299991111'),
  _c('"Avlbl Amt" and "Total Bal" are not the payment', _sms,
      title: 'VM-BOBTXN',
      text: 'Rs.900 transferred from A/c ...6677 to:Meera Iyer. Total Bal:Rs.5,400.00CR. '
          'Avlbl Amt:Rs.5,400.00(05-11-2026 10:00:00) - Bank of Baroda',
      amount: 900, type: 'expense'),
  _c('Multi-line card spend with "Avl Lmt"', _sms,
      title: 'JD-AXISBK-S',
      text: 'Spent\nCard no. XX3344\nINR 845\n05-11-26 19:20:11\nPIZZA PALACE\nAvl Lmt INR 41,155.00',
      amount: 845, type: 'expense', method: 'card', confidence: ParseConfidence.low),
  _c('Card spend "@UPI_" merchant with "Avl Lmt"', _sms,
      title: 'AD-YESBNK',
      text: 'INR 130.00 spent on YES BANK Card X8899 @UPI_RAM KIRANA 05-11-2026 08:10:00 am. '
          'Avl Lmt INR 90,000.00',
      amount: 130, type: 'expense'),
  _c('"Your txn of ₹ at <merchant>" card spend', _sms,
      title: 'VM-FEDBK',
      text: 'Your txn of ₹1,150.00 at Urban Bistro on your Federal credit card was successful.',
      amount: 1150, type: 'expense'),
  _c('NetBanking "Payment Successful!"', _sms,
      title: 'VM-HDFCBK',
      text: 'Payment Successful! Rs. 4,500.00 from A/c ****7788 to CITY GAS via HDFC Bank NetBanking.',
      amount: 4500, type: 'expense', last4: '7788'),
  _c('Amount glued to the verb ("2500credited")', _sms,
      title: 'VM-FEDBK',
      text: 'Rs.2500credited in your A/c XX3344 on 06NOV2026 using cash deposit machine. '
          'Current Bal: Rs.9,000.00',
      amount: 2500, type: 'income'),
  _c('"Transaction Reversed!" is a refund (Review / cancels the original)', _sms,
      title: 'VM-HDFCBK',
      text: 'Transaction Reversed! On HDFC Bank Credit Card xx2233 Amt: Rs.640.00 By MOVIEHOUSE On 2026-11-06',
      amount: 640, type: 'income', reversal: true, confidence: ParseConfidence.low),
  _c('Refund credited to a credit card is a reversal, not a bill payment', _sms,
      title: 'AD-INDUSB',
      text: 'Refund of INR 320 from Pizza Hut has been credited to your IndusInd Bank Credit Card '
          'XX5566 on 06-Nov-26',
      amount: 320, type: 'income', reversal: true, confidence: ParseConfidence.low),
  _c('"credited to the beneficiary" means the user paid', _sms,
      title: 'VM-ICICIT',
      text: 'ICICI BANK NEFT Transaction with reference number N12345678901 for Rs. 15000.00 has been '
          'credited to the beneficiary account on 06-11-2026',
      amount: 15000, type: 'expense'),
  _c('"X has received ... from your A/c" means the user paid', _sms,
      title: 'VM-FEDBK',
      text: 'Anil Kumar has received Rs 3000.00 from your A/c XX4411 via IMPS on 06-11-2026. '
          'Ref no. 431233330009 - Federal Bank',
      amount: 3000, type: 'expense', ref: '431233330009'),
  _c('Two own accounts debited/credited goes to Review (maybe a self-transfer)', _sms,
      title: 'VM-ICICIT',
      text: 'ICICI Bank Acct XX101 debited with Rs 5000 on 06-Nov-26 & Acct XX202 credited. IMPS:431244440001.',
      amount: 5000, type: 'expense', confidence: ParseConfidence.low),
  _c('NACH / SIP debit goes to Review, never added silently', _sms,
      title: 'VM-ICICIT',
      text: 'ICICI Bank Acc XX303 debited Rs. 3,000.00 on 06-Nov-26 InfoNACH*ACME MUTUAL FUND. '
          'Avl Bal Rs. 50,000.00. Ref 431255551234',
      amount: 3000, type: 'expense', confidence: ParseConfidence.low),
  _c('ATM withdrawal with a ref still goes to Review', _sms,
      title: 'AD-SBIINB',
      text: 'Rs 5000 withdrawn at SBI ATM from A/c XX1122 on 06Nov26. RRN 431266661234',
      amount: 5000, type: 'expense', confidence: ParseConfidence.low),

  // ─── R&D: things that must never become an entry ───────────────────────
  _c('Card bill "payment received" for a card brand name', _sms,
      title: 'VM-BOBCRD', text: 'Payment of Rs 4,210.50 received for your BOBCARD ending 7711 on 2026-11-06.'),
  _c('Card bill credited to the credit card', _sms,
      title: 'AD-SBICRD', text: 'Your payment of Rs.2,345.60 has been credited to your SBI Credit Card ending with 8899.'),
  _c('Card bill received towards the card', _sms,
      title: 'VM-PNBSMS',
      text: 'Thank you Rs.1,000.00 has been received as payment towards your PNB credit card XX7788 via Online Payment.'),
  _c('Interest on a deposit', _sms,
      title: 'AD-INDUSB', text: 'Net interest INR 182.40 paid on your IndusInd Deposit No 300***4567 on 30/10/26.'),
  _c('Fixed deposit opened', _sms,
      title: 'VM-HDFCBK',
      text: 'Fixed Deposit of Rs.50,000.00 opened successfully from A/c XX1234. Maturity on 06-11-2027.'),
  _c('Card statement / amount due', _sms,
      title: 'VM-HDFCBK',
      text: 'HDFC Bank Credit Card XX1234 statement: Total Amount Due Rs.12,400.00, '
          'Minimum Amount Due Rs.620.00, pay by 25-11-26.'),
  _c('Wallet top-up is moving own money', _paytm,
      text: 'Rs.500 added to your Paytm Wallet from HDFC Bank. Txn ID 26110612345678'),
  _c('UPI Lite top-up is moving own money', _gpay, text: '₹2,000 loaded to UPI Lite from your SBI account'),
  _c('Refund only initiated', _sms,
      title: 'VM-HDFCBK', text: 'Refund initiated: Amt: Rs.1,250.00 on HDFC Bank Credit Card 4321.'),
  _c('Refund promised for later', _amazon, text: 'Refund of ₹1,499 will be credited to your account in 5-7 days'),
  _c('Foreign currency (rupee amount unknown)', _sms,
      title: 'VM-ICICIT',
      text: 'USD 20.00 spent using ICICI Bank Card XX9090 on 06-Nov-26 on CLOUD HOST. Avl Limit: INR 1,20,000.00'),
  _c('Self transfer wording', _phonepe, text: 'Self transfer of ₹10,000 to your Kotak account successful'),
  _c('AutoPay activated (with a test debit)', _sms,
      title: 'VM-PNBSMS',
      text: 'Dear Customer, auto pay facility has been successfully activated on your PNB Card XX4356 for '
          'Rs. 5000.00 from Music App. An initial amount of Rs. 2.00 has been debited.'),
  _c('New bill fetched, due later', _sms,
      title: 'AD-SBICRD', text: 'Dear Cardholder, you have a new Jio Postpaid bill for Rs. 499.00 due by 25-Nov-2026.'),
];

void main() {
  test('has at least 30 table-driven cases', () {
    expect(_cases.length, greaterThanOrEqualTo(30));
  });

  for (final tc in _cases) {
    test(tc.name, () {
      final r = NotificationParser.parse(RawNotification(
        key: 'k',
        packageName: 'pkg',
        group: tc.group,
        label: tc.label,
        title: tc.title,
        text: tc.text,
        postTime: DateTime(2026, 11, 16, 12, 30),
      ));
      if (tc.rejected) {
        expect(r, isNull, reason: 'should be rejected but got $r');
        return;
      }
      expect(r, isNotNull, reason: 'should parse');
      expect(r!.amount, tc.amount);
      expect(r.type, tc.type);
      if (tc.payee != null) expect(r.payee, tc.payee);
      if (tc.ref != null) expect(r.ref, tc.ref);
      if (tc.last4 != null) expect(r.accountLast4, tc.last4);
      if (tc.method != null) expect(r.paymentMethod, tc.method);
      if (tc.confidence != null) expect(r.confidence, tc.confidence);
      if (tc.reversal != null) expect(r.isReversal, tc.reversal);
      expect(r.sourceApp, tc.label);
      // HIGH needs amount + type + ref (and is never given to review-only payments).
      if (r.confidence == ParseConfidence.high) expect(r.ref, isNotNull);
    });
  }

  test('refLast4 exposes only the last 4 characters', () {
    final r = NotificationParser.parse(RawNotification(
      key: 'k',
      packageName: 'p',
      group: 'gpay',
      label: 'Google Pay',
      text: 'You paid ₹10 to Tea Stall. UPI Ref No. 431234567890',
      postTime: DateTime(2026),
    ))!;
    expect(r.refLast4, '7890');
    expect(r.toString(), isNot(contains('431234567890')));
  });

  test('isBankSender', () {
    expect(NotificationParser.isBankSender('VM-HDFCBK'), isTrue);
    expect(NotificationParser.isBankSender('JD-ICICIT-S'), isTrue);
    expect(NotificationParser.isBankSender('AX-PAYTMB'), isTrue);
    expect(NotificationParser.isBankSender('HDFCBK'), isTrue);
    expect(NotificationParser.isBankSender('AD-SWIGGY'), isFalse);
    expect(NotificationParser.isBankSender('Mom'), isFalse);
    expect(NotificationParser.isBankSender('+919876543210'), isFalse);
  });
}
