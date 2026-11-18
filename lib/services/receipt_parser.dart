/// Parses a payment receipt the user shared with Espere (text from a UPI app's share
/// button, or text read from a screenshot by on-device OCR).
///
/// Unlike [NotificationParser], the user picked this receipt on purpose and always sees the
/// result in the transaction form before saving. So promo lines on the same screen
/// ("You've won ₹0.6 cashback", "Save 19%") are skipped instead of rejecting the receipt,
/// and anything the parser is unsure about is simply left empty for the user to fill in.
///
/// Pure Dart, no Flutter imports: easy to unit test.
library;

class ReceiptData {
  /// Null when no single payment amount could be found.
  final double? amount;

  /// 'expense' or 'income'.
  final String type;
  final String? payee;

  /// UPI ref / UTR / transaction id, upper-case alphanumeric.
  final String? ref;

  /// Date and time printed on the receipt, or null.
  final DateTime? time;

  /// The receipt says the payment failed / is pending: nothing should be added.
  final bool notCompleted;

  const ReceiptData({
    required this.amount,
    required this.type,
    this.payee,
    this.ref,
    this.time,
    this.notCompleted = false,
  });

  bool get isEmpty => amount == null && payee == null && ref == null;

  /// Fields of [this], with gaps filled from [other] (e.g. shared text + its screenshot).
  ReceiptData orElse(ReceiptData? other) => other == null
      ? this
      : ReceiptData(
          amount: amount ?? other.amount,
          type: amount != null ? type : other.type,
          payee: payee ?? other.payee,
          ref: ref ?? other.ref,
          time: time ?? other.time,
          notCompleted: notCompleted || other.notCompleted,
        );

  @override
  String toString() =>
      'ReceiptData($type $amount payee=$payee ref=$ref time=$time notCompleted=$notCompleted)';
}

/// One line of on-device OCR output with its position (pixels).
class OcrLine {
  final String text;
  final int left, top, right, bottom;
  const OcrLine(this.text, this.left, this.top, this.right, this.bottom);

  int get height => bottom - top;
  double get centerY => (top + bottom) / 2;

  factory OcrLine.fromMap(Map<dynamic, dynamic> m) => OcrLine(
        (m['t'] ?? '').toString(),
        (m['l'] as num?)?.toInt() ?? 0,
        (m['tp'] as num?)?.toInt() ?? 0,
        (m['r'] as num?)?.toInt() ?? 0,
        (m['b'] as num?)?.toInt() ?? 0,
      );
}

/// OCR result of a screenshot (see ReceiptBridge.kt).
class OcrScan {
  final int width, height;
  final List<OcrLine> lines;

  /// How this phone's OCR reads "₹": "keep", "drop", one character (e.g. "7"), or null.
  final String? rupee;

  const OcrScan({required this.width, required this.height, required this.lines, this.rupee});

  factory OcrScan.fromMap(Map<dynamic, dynamic> m) => OcrScan(
        width: (m['w'] as num?)?.toInt() ?? 0,
        height: (m['h'] as num?)?.toInt() ?? 0,
        lines: ((m['lines'] as List?) ?? const [])
            .whereType<Map<dynamic, dynamic>>()
            .map(OcrLine.fromMap)
            .toList(),
        rupee: (m['rupee'] as String?)?.trim().isEmpty ?? true ? null : m['rupee'] as String,
      );

  /// Plain text, top to bottom (for "See text read from receipt").
  String get text {
    final sorted = [...lines]..sort((a, b) => a.top != b.top ? a.top.compareTo(b.top) : a.left.compareTo(b.left));
    return sorted.map((l) => l.text).join('\n');
  }
}

class ReceiptParser {
  ReceiptParser._();

  static const _ci = false;

  // ─── Amount ───────────────────────────────────────────────────────────────

  /// ₹ / Rs / INR + amount. OCR sometimes reads "₹" as "%" or "Z" right before the digits;
  /// those are only accepted inside a payment phrase (see [_phraseAmount]).
  static final _amount = RegExp(
      r'(?:₹|\brs\.?|\binr)\s*\.?\s*(\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)',
      caseSensitive: _ci);

  static const _num = r'(\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)';
  static const _cur = r'(?:₹|rs\.?|inr|[%zZ?])\s*\.?\s*';

  /// "Payment of ₹60", "Paid ₹60", "You paid ₹60", "Sent ₹60", "Amount: ₹60",
  /// "₹60 paid to", "Received ₹60".
  static final _phraseAmount = <RegExp>[
    RegExp(
        r'\b(?:payment of|paid|you paid|sent|you sent|money sent|amount(?: paid)?|total(?: amount)?|'
        r'received|you received|debited|credited)\s*(?:of|:|-)?\s*'
        '$_cur$_num',
        caseSensitive: _ci),
    RegExp('(?:₹|rs\\.?|inr)\\s*\\.?\\s*$_num\\s+(?:paid|sent|received|debited|credited)\\b',
        caseSensitive: _ci),
  ];

  /// OCR fallback for "Payment of ₹60 to …" when the "₹" was dropped or misread
  /// ("Payment of 60 to", "Payment of *60 to", "Paid R60 to", "Payment of 760 to",
  /// "Payment of 7140 completed"). What must follow ("to/from NAME", "completed", end of
  /// line) keeps dates, times and phone numbers out.
  /// Group 1: what stands where the "₹" should be; group 2: the number.
  static final _lenientPhraseAmount = RegExp(
      r'\b(?:payment of|paid|you paid|sent|you sent|received|you received)\s*:?\s*'
      r'([^\s\d]{0,2})\s?' '$_num'
      r'(?:\s+(?:to|from)\s+[A-Za-z]|\s+(?:is\s+|was\s+|has\s+been\s+)?'
      r'(?:completed|successful|success|done)\b|\s*$)',
      caseSensitive: _ci);

  /// Digits the on-device OCR reads instead of "₹" (its Latin model has no rupee sign):
  /// "₹60" comes back as "760", "₹500" as "2500".
  static const _rupeeAsDigit = {'7', '2'};

  /// A line that is only an amount, like the big "₹60" header (symbol optional / misread).
  static final _amountOnlyLine =
      RegExp(r'^\s*(₹|rs\.?|inr|[^\s\d\w]|[zZR])?\s?' '$_num' r'\s*$', caseSensitive: _ci);

  /// Amounts right after these words are cashback, rewards, offers or balances.
  static final _notPaymentAmount = RegExp(
      r'(cashback|cash back|reward|rewards|won|win|earn|earned|save|saved|savings|off|discount|'
      r'offer|coins?|points|bal|balance|limit|avl|available|upto|up to|min(imum)?|worth)'
      r'\W{0,6}(of\W{0,3}|is\W{0,3}|amt\W{0,3}|flat\W{0,3})?(?:₹|rs\.?|inr)?\s*\.?\s*$',
      caseSensitive: _ci);

  /// Lines that are only promotions; amounts on them are ignored.
  static final _promoLine = RegExp(
      r'\b(cashback|cash back|scratch card|reward|won|congrat|offer|deal|discount|save \d|'
      r'% off|off|flat|book now|t&c|coupon|voucher|earn|coins?|up ?to|enjoy|activate)\b',
      caseSensitive: _ci);

  // ─── Status / direction ───────────────────────────────────────────────────

  static final _failed = RegExp(
      r'\b(failed|failure|declined|unsuccessful|not successful|pending|under process|'
      r'in progress|could not be processed)\b',
      caseSensitive: _ci);

  static final _income = RegExp(
      r'\b(received from|you received|sent you|paid you|credited to your|money received|'
      r'received ₹|received rs|received successfully)\b|\breceived\s+(?:₹|rs|inr)|'
      // Google Pay "From Anita Desai" (not "From: <your bank account>")
      r'^\s*from\s+(?![^\n]*\b(?:bank|a/?c|account|xx+\d*)\b)[A-Za-z]',
      caseSensitive: _ci,
      multiLine: true);
  static final _expense = RegExp(
      r'\b(paid to|payment of|payment to|you paid|sent to|you sent|money sent|debited|paid ₹|'
      r'paid rs|transferred to|payment successful|paid successfully)\b|\bpaid\s+(?:₹|rs|inr)',
      caseSensitive: _ci);

  // ─── Payee ────────────────────────────────────────────────────────────────

  static const _name = r"([A-Za-z0-9][A-Za-z0-9 .&'@_-]{1,40}?)";
  static const _end = r'(?=\s+(?:is|was|has|on|via|using|for|successfully|successful|completed)\b|'
      r'\s+(?:₹|rs\.?\s?|inr\s?|[^\s\w])?\d|\s*(?:[,;!\n(]|$)|\.\s)';

  static final _payeePatterns = <RegExp>[
    // "Payment of ₹60 to LITE CAFE is successful"
    RegExp('\\bpayment of\\s+\\S+\\s+to\\s+$_name$_end', caseSensitive: _ci),
    // "Paid to LITE CAFE", "Sent to Rahul", "Payment to X", "To: X"
    RegExp('\\b(?:paid to|sent to|payment to|transferred to|money sent to|'
        '(?:paid|sent|payment) successfully to)\\s*:?[ \\t]+$_name$_end',
        caseSensitive: _ci),
    // Bank apps: "Beneficiary Name: Ravi Kumar", "Payee: X"
    RegExp('\\b(?:beneficiary|payee)(?:\\s+name)?\\s*:?[ \\t]+$_name$_end', caseSensitive: _ci),
    RegExp('^\\s*to\\s*:?\\s+$_name\\s*\$', caseSensitive: _ci, multiLine: true),
    // "You paid ₹250 to Swiggy"
    RegExp('\\b(?:paid|sent)\\s+(?:₹|rs\\.?|inr)\\s*[\\d,.]+\\s+to\\s+$_name$_end',
        caseSensitive: _ci),
  ];

  static final _payerPatterns = <RegExp>[
    RegExp('\\b(?:received from|from)\\s*:?\\s+$_name$_end', caseSensitive: _ci),
    RegExp('^\\s*$_name\\s+(?:has\\s+)?(?:sent|paid) you\\b', caseSensitive: _ci, multiLine: true),
  ];

  static final _notAPayee = RegExp(
      r'^(your|you|a/?c|acct|account|card|bank|wallet|the|upi|vpa|rs|inr|my|self|me|'
      r'view details|pay again|share|done|home|banking name|\d[\d\s:/,-]*)$',
      caseSensitive: _ci);

  // ─── Reference ────────────────────────────────────────────────────────────

  static final _ref = RegExp(
      r'\b(?:upi\s*(?:transaction|txn|ref(?:erence)?)\.?\s*(?:id|no\.?|number)?|'
      r'(?:transaction|txn)\s*(?:id|no\.?|ref)|ref(?:erence)?\.?\s*(?:no\.?|number|id)|utr(?:\s*no\.?)?|'
      r'rrn|order id|google transaction id)'
      r'\s*[:.#-]?\s*\n?\s*([A-Za-z0-9]{8,35})\b',
      caseSensitive: _ci);

  // ─── Date / time ──────────────────────────────────────────────────────────

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static const _time = r'(?:[,\s]*(?:at|,)?\s*(\d{1,2})[:.](\d{2})(?:[:.]\d{2})?\s*([ap]\.?\s?m\.?)?)?';

  /// "18 Nov 2026, 1:29 PM", "18 November 2026 at 01:29 pm"
  static final _dmy = RegExp(
      r'\b(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,9})\.?,?\s+(\d{4})' + _time,
      caseSensitive: _ci);

  /// "Nov 18, 2026 1:29 PM"
  static final _mdy = RegExp(
      r'\b([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})' + _time,
      caseSensitive: _ci);

  /// "18/11/2026 13:29", "18-11-26"
  static final _numeric = RegExp(r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})' + _time, caseSensitive: _ci);

  /// "08:18 pm on 14 Oct 2026" (PhonePe)
  static final _timeThenDate = RegExp(
      r'\b(\d{1,2})[:.](\d{2})\s*([ap]\.?\s?m\.?)?\s*(?:on|,)?\s+(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,9})\.?,?\s+(\d{4})\b',
      caseSensitive: _ci);

  /// "1:29 PM" alone (date = today).
  static final _timeOnly = RegExp(r'\b(\d{1,2})[:.](\d{2})\s*([ap]\.?\s?m\.?)', caseSensitive: _ci);

  // ─── Entry point ──────────────────────────────────────────────────────────

  /// [now] is used for receipts that print only a time, and to reject dates in the future.
  /// [rupee] and [heroAmounts] come from [parseScan]; plain shared text has neither.
  static ReceiptData parse(String raw,
      {DateTime? now, String? rupee, List<double> heroAmounts = const []}) {
    now ??= DateTime.now();
    final text = _normalise(raw);

    final notCompleted = _failed.hasMatch(text);
    final type = _extractType(text);

    return ReceiptData(
      amount: _extractAmount(text, rupee, heroAmounts),
      type: type,
      payee: type == 'income' ? _extractPayer(text) : _extractPayee(text),
      ref: _extractRef(text),
      time: _extractTime(text, now),
      notCompleted: notCompleted,
    );
  }

  static String _normalise(String s) {
    var t = s
        .replaceAll('\r', '')
        .replaceAll(RegExp(r'[\u00A0\u2007\u202F]'), ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
    // OCR letter/digit mix-ups inside numbers: "1,2O0" -> "1,200", "l00" -> "100".
    t = t.replaceAllMapped(RegExp(r'(?<=\d[\d,.]*)[Oo](?=[\d,.]*\b)'), (_) => '0');
    t = t.replaceAllMapped(RegExp(r'(?<=[\d,])[lI|](?=\d)'), (_) => '1');
    // ...and inside month names: "14 0ct 2026" -> "14 Oct 2026", "N0v" -> "Nov".
    t = t.replaceAllMapped(RegExp(r'\b[A-Za-z0-9]{3,9}\b'), (m) {
      final w = m.group(0)!;
      if (!RegExp(r'[015]').hasMatch(w) || !RegExp(r'[A-Za-z]').hasMatch(w)) return w;
      final fixed = w.replaceAll('0', 'o').replaceAll('1', 'l').replaceAll('5', 's');
      if (_month(fixed) == null) return w;
      return fixed[0].toUpperCase() + fixed.substring(1).toLowerCase();
    });
    // "UP transaction ID" (the I is lost) -> "UPI transaction ID"
    t = t.replaceAll(RegExp(r'\bUP (?=transaction|txn|ref)', caseSensitive: false), 'UPI ');
    return t;
  }

  /// Parses an OCR result with layout: drops the phone's status bar, puts words that sit
  /// on one row back on one line, and finds the amount printed in the biggest font.
  static ReceiptData parseScan(OcrScan scan, {DateTime? now}) {
    final lines = scan.lines
        .where((l) => l.text.trim().isNotEmpty)
        // Status bar (clock, battery "60", network speed) is never part of the receipt.
        .where((l) => scan.height <= 0 || (l.top + l.bottom) / 2 > scan.height * 0.035)
        .toList()
      ..sort((a, b) => a.centerY.compareTo(b.centerY));

    // Rows: lines whose vertical extents overlap by half of the smaller one.
    final rows = <List<OcrLine>>[];
    for (final l in lines) {
      final row = rows.isEmpty ? null : rows.last;
      if (row != null && row.any((o) => _overlap(o, l) >= 0.5 * (o.height < l.height ? o.height : l.height))) {
        row.add(l);
      } else {
        rows.add([l]);
      }
    }
    final text = rows
        .map((r) => (r..sort((a, b) => a.left.compareTo(b.left))).map((l) => l.text.trim()).join(' '))
        .join('\n');

    // Hero amount: an amount-only line clearly taller than the usual text line.
    final heights = lines.map((l) => l.height).where((h) => h > 0).toList()..sort();
    final hero = <double>[];
    if (heights.isNotEmpty) {
      final median = heights[heights.length ~/ 2];
      OcrLine? tallest;
      for (final l in lines) {
        final m = _amountOnlyLine.firstMatch(_normalise(l.text));
        if (m == null) continue;
        if (tallest == null || l.height > tallest.height) tallest = l;
      }
      if (tallest != null && tallest.height >= median * 1.35) {
        final m = _amountOnlyLine.firstMatch(_normalise(tallest.text))!;
        final v = _toAmount(_dropMisreadRupee(m.group(1) ?? '', m.group(2)!, scan.rupee));
        if (v != null) hero.add(v);
      }
    }
    return parse(text, now: now, rupee: _rupeeFor(text, scan.rupee), heroAmounts: hero);
  }

  /// The rupee reading was measured on Android's own font; an app's font can differ. If
  /// this screenshot contradicts the measurement, fall back to "unknown".
  static String? _rupeeFor(String text, String? measured) {
    final sawRupee = text.contains('₹');
    if (measured == 'keep' && !sawRupee) return null; // this app's ₹ was not read
    if (measured != null && measured != 'keep' && sawRupee) return 'keep';
    return measured;
  }

  static double _overlap(OcrLine a, OcrLine b) {
    final top = a.top > b.top ? a.top : b.top;
    final bottom = a.bottom < b.bottom ? a.bottom : b.bottom;
    return (bottom - top).toDouble();
  }

  static String _extractType(String s) {
    final inc = _income.firstMatch(s);
    final exp = _expense.firstMatch(s);
    if (inc == null) return 'expense';
    if (exp == null) return 'income';
    return inc.start < exp.start ? 'income' : 'expense';
  }

  static double? _toAmount(String v) {
    final d = double.tryParse(v.replaceAll(',', ''));
    if (d == null || d <= 0) return null;
    return (d * 100).roundToDouble() / 100;
  }

  /// Every number that could be the payment gets points for each sign that it is one;
  /// the clear winner is the amount. A tie or a weak winner leaves the amount empty
  /// (the user types it) rather than guessing.
  ///
  /// | Sign | Points |
  /// |---|---|
  /// | in a payment sentence ("Payment of ₹60 to", "Paid ₹250", "Payment of 140 completed") | 4 |
  /// | printed in the biggest font on the screenshot ([heroAmounts]) | 4 |
  /// | written with ₹ / Rs / INR | 3 per line |
  /// | after an "Amount" / "Total" label | 3 |
  /// | alone at the end of a line | 1, +1 with a separator or symbol |
  /// | printed on two or more lines | +2 |
  ///
  /// Promo lines (cashback, offers, "up to ₹10,000"), balances, ids, clock times and years
  /// never count.
  static double? _extractAmount(String s, String? rupee, List<double> heroAmounts) {
    final lines = s.split('\n');
    final score = <double, int>{};
    final seenOn = <double, Set<int>>{};
    void add(double? v, int points, int line) {
      if (v == null) return;
      score[v] = (score[v] ?? 0) + points;
      (seenOn[v] ??= <int>{}).add(line);
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_promoLine.hasMatch(line)) continue;

      for (final re in _phraseAmount) {
        for (final m in re.allMatches(line)) {
          add(_toAmount(m.group(1)!), 4, i);
        }
      }
      for (final m in _lenientPhraseAmount.allMatches(line)) {
        // Already counted above when the ₹ was read properly.
        if (_hasCurrency(m.group(1)!)) continue;
        add(_toAmount(_dropMisreadRupee(m.group(1)!, m.group(2)!, rupee)), 4, i);
      }
      for (final m in _amount.allMatches(line)) {
        final before = line.substring(0, m.start);
        final window = before.length > 30 ? before.substring(before.length - 30) : before;
        if (_notPaymentAmount.hasMatch(window)) continue;
        add(_toAmount(m.group(1)!), 3, i);
      }
      final label = _labelAmount.firstMatch(line);
      if (label != null) {
        final rest = label.group(1)!.trim();
        final value = rest.isNotEmpty
            ? rest
            : (i + 1 < lines.length ? lines[i + 1].trim() : '');
        final m = _amountOnlyLine.firstMatch(value);
        if (m != null) add(_toAmount(_dropMisreadRupee(m.group(1) ?? '', m.group(2)!, rupee)), 3, i);
      }
      final end = _lineEndAmount.firstMatch(line);
      if (end != null && !_notAmountLine.hasMatch(line.substring(0, end.start))) {
        final symbol = end.group(1) ?? '';
        final number = _dropMisreadRupee(symbol, end.group(2)!, rupee);
        final formatted = symbol.isNotEmpty || number.contains(',') || number.contains('.');
        add(_toAmount(number), formatted ? 2 : 1, i);
      }
    }
    for (final v in heroAmounts) {
      add(v, 4, -1);
    }
    for (final e in seenOn.entries) {
      if (e.value.where((i) => i >= 0).length >= 2) score[e.key] = score[e.key]! + 2;
    }

    if (score.isEmpty) return null;
    final ranked = score.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final best = ranked.first;
    if (best.value < 3) return null;
    if (ranked.length > 1 && best.value - ranked[1].value < 2) return null;
    return best.key;
  }

  static bool _hasCurrency(String prefix) =>
      RegExp(r'₹|rs|inr', caseSensitive: _ci).hasMatch(prefix);

  /// "Amount: ₹500", "Total Amount", "Amount Paid ₹1,232" (value on this or the next line).
  static final _labelAmount = RegExp(
      r'^\s*(?:total\s+)?(?:amount|amt)(?:\s+(?:paid|debited|sent|received|transferred))?\s*[:\-]?\s*(.*)$',
      caseSensitive: _ci);

  /// An amount at the end of a line or alone on it, with or without a (misread) "₹":
  /// "₹1,232", "71,232", "Flipkart Payments 71,232". Group 1: the symbol, group 2: number.
  static final _lineEndAmount = RegExp(
      r'(?:^|\s)(₹|[^\s\w/.:@#+-]|[zZR])?\s?(\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d{1,6}\.\d{2}|\d{1,6})\s*$');

  /// Lines whose numbers are ids, accounts, balances or clock times, never the payment.
  static final _notAmountLine = RegExp(
      r'\b(id|utr|ref|rrn|a/?c|account|acct|bal|balance|limit|txn|transaction|order|mobile|phone|'
      r'otp|pin|ifsc|upi|call|contact|helpline|whatsapp)\b|\d[:]\d|%|k/s|https?://|www\.|\+91|'
      // a year right after a month ("14 Oct 2026")
      r'\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?,?\s*$',
      caseSensitive: _ci);

  /// "Payment of 760 to X": nothing was read where the "₹" belongs, and the number starts
  /// with the digit this phone's OCR writes for "₹", so that digit is the rupee sign
  /// ("760" -> "60", "71,200" -> "1,200"). [rupee] is what the phone's OCR was measured to
  /// do with "₹" (see ReceiptBridge.kt): "keep" / "drop" (no digit is removed), a digit
  /// (only that digit), or null when unknown (7 and 2, the usual misreadings).
  static String _dropMisreadRupee(String prefix, String number, String? rupee) {
    if (prefix.isNotEmpty || number.length < 2) return number;
    final digits = rupee == null
        ? _rupeeAsDigit
        : (RegExp(r'^\d$').hasMatch(rupee) ? {rupee} : const <String>{});
    if (!digits.contains(number[0])) return number;
    var rest = number.substring(1);
    if (rest.startsWith(',')) return number; // "7,760": a real thousands separator
    final intPart = rest.split('.').first.replaceAll(',', '');
    if (intPart.isEmpty || intPart.startsWith('0')) return number; // "70.6", "705"
    return rest;
  }

  static final _payeeLabelLine =
      RegExp(r'^\s*(?:paid to|sent to|paying|to|payment to|transferred to|beneficiary(?: name)?|payee(?: name)?|'
          r'(?:paid|sent|payment) successfully to)\s*:?\s*$', caseSensitive: _ci);
  static final _payerLabelLine =
      RegExp(r'^\s*(?:received from|from|sender)\s*:?\s*$', caseSensitive: _ci);

  /// "Paid to" on its own line: the payee is the next line that has a name, skipping
  /// amount-only lines and avatar initials ("FP"); a trailing amount is cut off.
  static String? _payeeAfterLabel(String s, RegExp label) {
    final lines = s.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!label.hasMatch(lines[i])) continue;
      for (var j = i + 1; j < lines.length && j <= i + 4; j++) {
        var line = lines[j].trim();
        if (!RegExp(r'[A-Za-z]{2,}').hasMatch(line)) continue; // amount / empty
        if (RegExp(r'^[A-Z]{1,3}$').hasMatch(line)) continue; // avatar initials
        final amount = _lineEndAmount.firstMatch(line);
        if (amount != null && amount.start > 0) line = line.substring(0, amount.start).trim();
        final p = _clean(line);
        if (p != null) return p;
        break;
      }
    }
    return null;
  }

  static String? _extractPayee(String s) {
    final labelled = _payeeAfterLabel(s, _payeeLabelLine);
    if (labelled != null) return labelled;
    for (final re in _payeePatterns) {
      for (final m in re.allMatches(s)) {
        final p = _clean(m.group(1));
        if (p != null) return p;
      }
    }
    return null;
  }

  static String? _extractPayer(String s) {
    final labelled = _payeeAfterLabel(s, _payerLabelLine);
    if (labelled != null) return labelled;
    for (final re in _payerPatterns) {
      for (final m in re.allMatches(s)) {
        final p = _clean(m.group(1));
        if (p != null) return p;
      }
    }
    return null;
  }

  static String? _clean(String? raw) {
    if (raw == null) return null;
    var p = _stripAvatarInitials(raw.trim().replaceAll(RegExp(r'\s+'), ' '));
    p = p.replaceAll(RegExp(r'^(vpa|upi id|mr\.?|ms\.?|mrs\.?)\s+', caseSensitive: _ci), '');
    p = p.replaceAll(RegExp(r'[\s.,;:-]+$'), '');
    if (p.contains('@')) p = p.split('@').first;
    if (p.length < 2 || p.length > 40) return null;
    if (_notAPayee.hasMatch(p)) return null;
    if (RegExp(r'^[x*\d\s]+$', caseSensitive: _ci).hasMatch(p)) return null;
    return p;
  }

  /// "FP Flipkart Payments" -> "Flipkart Payments": the round avatar with initials sits on
  /// the same row as the name.
  static String _stripAvatarInitials(String p) {
    final m = RegExp(r'^([A-Z]{1,3})\s+(.+)$').firstMatch(p);
    if (m == null) return p;
    final initials = m.group(1)!;
    final words = m.group(2)!.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length < initials.length) return p;
    final firsts = words.take(initials.length).map((w) => w[0].toUpperCase()).join();
    return firsts == initials ? m.group(2)! : p;
  }

  static String? _extractRef(String s) {
    for (final m in _ref.allMatches(s)) {
      final v = m.group(1)!.toUpperCase();
      if (RegExp(r'\d').allMatches(v).length >= 6) return v;
    }
    return null;
  }

  static DateTime? _extractTime(String s, DateTime now) {
    DateTime? found;

    final tFirst = _timeThenDate.firstMatch(s);
    if (tFirst != null) {
      final month = _month(tFirst.group(5)!);
      if (month != null) {
        found = _build(int.parse(tFirst.group(6)!), month, int.parse(tFirst.group(4)!),
            tFirst.group(1), tFirst.group(2), tFirst.group(3));
      }
    }
    if (found != null) return _plausible(found, now);

    final dmy = _dmy.firstMatch(s);
    if (dmy != null) {
      final month = _month(dmy.group(2)!);
      if (month != null) {
        found = _build(int.parse(dmy.group(3)!), month, int.parse(dmy.group(1)!), dmy.group(4),
            dmy.group(5), dmy.group(6));
      }
    }
    if (found == null) {
      final mdy = _mdy.firstMatch(s);
      if (mdy != null) {
        final month = _month(mdy.group(1)!);
        if (month != null) {
          found = _build(int.parse(mdy.group(3)!), month, int.parse(mdy.group(2)!), mdy.group(4),
              mdy.group(5), mdy.group(6));
        }
      }
    }
    if (found == null) {
      final n = _numeric.firstMatch(s);
      if (n != null) {
        var year = int.parse(n.group(3)!);
        if (year < 100) year += 2000;
        found = _build(year, int.parse(n.group(2)!), int.parse(n.group(1)!), n.group(4), n.group(5),
            n.group(6));
      }
    }
    if (found == null) {
      final t = _timeOnly.firstMatch(s);
      if (t != null) {
        found = _build(now.year, now.month, now.day, t.group(1), t.group(2), t.group(3));
      }
    }

    return found == null ? null : _plausible(found, now);
  }

  static DateTime? _plausible(DateTime found, DateTime now) {
    // A receipt is never from the future (allow a little clock skew).
    if (found.isAfter(now.add(const Duration(minutes: 10)))) return null;
    // Nor older than a year (most likely a misread).
    if (found.isBefore(now.subtract(const Duration(days: 366)))) return null;
    return found;
  }

  static int? _month(String name) {
    final key = name.toLowerCase();
    if (key.length < 3) return null;
    final m = _months[key.substring(0, 3)];
    if (m == null) return null;
    // "Nov", "November", "Sept" are fine; random words starting with "mar…" are not.
    const full = [
      'january', 'february', 'march', 'april', 'may', 'june', 'july', 'august',
      'september', 'october', 'november', 'december', 'sept',
    ];
    if (key.length > 3 && !full.contains(key)) return null;
    return m;
  }

  static DateTime? _build(int y, int mo, int d, String? hh, String? mm, String? ampm) {
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    var hour = hh == null ? 12 : int.parse(hh);
    final minute = mm == null ? 0 : int.parse(mm);
    if (ampm != null) {
      final pm = ampm.toLowerCase().startsWith('p');
      if (hour < 1 || hour > 12) return null;
      if (pm && hour != 12) hour += 12;
      if (!pm && hour == 12) hour = 0;
    }
    if (hour > 23 || minute > 59) return null;
    final dt = DateTime(y, mo, d, hour, minute);
    if (dt.month != mo || dt.day != d) return null; // e.g. 31 Feb
    return dt;
  }
}
