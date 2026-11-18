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

  @override
  String toString() =>
      'ReceiptData($type $amount payee=$payee ref=$ref time=$time notCompleted=$notCompleted)';
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
  /// ("Payment of 60 to", "Payment of *60 to", "Paid R60 to"). The "to/from NAME" that
  /// must follow keeps dates, times and phone numbers out.
  static final _lenientPhraseAmount = RegExp(
      r'\b(?:payment of|paid|you paid|sent|you sent|received|you received)\s*:?\s*'
      r'[^\s\d]{0,2}\s?' '$_num' r'\s+(?:to|from)\s+[A-Za-z]',
      caseSensitive: _ci);

  /// A line that is only an amount, like the big "₹60" header (symbol optional / misread).
  static final _amountOnlyLine =
      RegExp(r'^\s*(?:₹|rs\.?|inr|[^\s\d\w])?\s?' '$_num' r'\s*$', caseSensitive: _ci);

  /// Amounts right after these words are cashback, rewards, offers or balances.
  static final _notPaymentAmount = RegExp(
      r'(cashback|cash back|reward|rewards|won|win|earn|earned|save|saved|savings|off|discount|'
      r'offer|coins?|points|bal|balance|limit|avl|available|upto|up to|min(imum)?|worth)'
      r'\W{0,6}(of\W{0,3}|is\W{0,3}|amt\W{0,3}|flat\W{0,3})?(?:₹|rs\.?|inr)?\s*\.?\s*$',
      caseSensitive: _ci);

  /// Lines that are only promotions; amounts on them are ignored.
  static final _promoLine = RegExp(
      r'\b(cashback|cash back|scratch card|reward|won|congrat|offer|deal|discount|save \d|'
      r'% off|off|flat|book now|t&c|coupon|voucher|earn|coins?)\b',
      caseSensitive: _ci);

  // ─── Status / direction ───────────────────────────────────────────────────

  static final _failed = RegExp(
      r'\b(failed|failure|declined|unsuccessful|not successful|pending|under process|'
      r'in progress|could not be processed)\b',
      caseSensitive: _ci);

  static final _income = RegExp(
      r'\b(received from|you received|sent you|paid you|credited to your|money received|'
      r'received ₹|received rs)\b|\breceived\s+(?:₹|rs|inr)',
      caseSensitive: _ci);
  static final _expense = RegExp(
      r'\b(paid to|payment of|payment to|you paid|sent to|you sent|money sent|debited|paid ₹|'
      r'paid rs|transferred to|payment successful|paid successfully)\b|\bpaid\s+(?:₹|rs|inr)',
      caseSensitive: _ci);

  // ─── Payee ────────────────────────────────────────────────────────────────

  static const _name = r"([A-Za-z0-9][A-Za-z0-9 .&'@_-]{1,40}?)";
  static const _end = r'(?=\s+(?:is|was|has|on|via|using|for|successfully|successful|completed)\b|'
      r'\s*(?:[,;!\n(]|$)|\.\s)';

  static final _payeePatterns = <RegExp>[
    // "Payment of ₹60 to LITE CAFE is successful"
    RegExp('\\bpayment of\\s+\\S+\\s+to\\s+$_name$_end', caseSensitive: _ci),
    // "Paid to LITE CAFE", "Sent to Rahul", "Payment to X", "To: X"
    RegExp('\\b(?:paid to|sent to|payment to|transferred to|money sent to)\\s*:?\\s+$_name$_end',
        caseSensitive: _ci),
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
      r'\b(?:upi\s*(?:transaction|txn|ref(?:erence)?)\s*(?:id|no\.?|number)?|'
      r'(?:transaction|txn)\s*(?:id|no\.?|ref)|ref(?:erence)?\s*(?:no\.?|number|id)|utr(?:\s*no\.?)?|'
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

  /// "1:29 PM" alone (date = today).
  static final _timeOnly = RegExp(r'\b(\d{1,2})[:.](\d{2})\s*([ap]\.?\s?m\.?)', caseSensitive: _ci);

  // ─── Entry point ──────────────────────────────────────────────────────────

  /// [now] is used for receipts that print only a time, and to reject dates in the future.
  static ReceiptData parse(String raw, {DateTime? now}) {
    now ??= DateTime.now();
    final text = _normalise(raw);

    final notCompleted = _failed.hasMatch(text);
    final type = _extractType(text);

    return ReceiptData(
      amount: _extractAmount(text),
      type: type,
      payee: type == 'income' ? _extractPayer(text) : _extractPayee(text),
      ref: _extractRef(text),
      time: _extractTime(text, now),
      notCompleted: notCompleted,
    );
  }

  static String _normalise(String s) => s
      .replaceAll('\r', '')
      .replaceAll(RegExp(r'[\u00A0\u2007\u202F]'), ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      // OCR often reads "₹" as "₹ " or splits "₹60" into "₹ 60"; both are handled by \s*.
      .trim();

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

  /// 1. An amount inside a payment phrase ("Payment of ₹60", "You paid ₹250").
  /// 2. Otherwise the only amount that is not on a promo line / after a cashback word.
  /// 3. Otherwise the amount printed most often (the big "₹60" header + the status line).
  static double? _extractAmount(String s) {
    final lines = s.split('\n');

    final fromPhrases = <double>{};
    for (final line in lines) {
      if (_promoLine.hasMatch(line)) continue;
      for (final re in _phraseAmount) {
        for (final m in re.allMatches(line)) {
          final v = _toAmount(m.group(1)!);
          if (v != null) fromPhrases.add(v);
        }
      }
    }
    if (fromPhrases.length == 1) return fromPhrases.first;

    final counts = <double, int>{};
    for (final line in lines) {
      if (_promoLine.hasMatch(line)) continue;
      for (final m in _amount.allMatches(line)) {
        final before = line.substring(0, m.start);
        final window = before.length > 30 ? before.substring(before.length - 30) : before;
        if (_notPaymentAmount.hasMatch(window)) continue;
        final v = _toAmount(m.group(1)!);
        if (v != null) counts[v] = (counts[v] ?? 0) + 1;
      }
    }
    if (fromPhrases.length > 1) {
      // Several phrase amounts: keep the one also printed elsewhere, if exactly one is.
      final repeated = fromPhrases.where((v) => (counts[v] ?? 0) >= 2).toList();
      return repeated.length == 1 ? repeated.first : null;
    }
    if (counts.length == 1) return counts.keys.first;
    if (counts.isNotEmpty) {
      final top = counts.values.reduce((a, b) => a > b ? a : b);
      final winners = counts.entries.where((e) => e.value == top).toList();
      if (top >= 2 && winners.length == 1) return winners.first.key;
      return null;
    }
    return _ocrFallbackAmount(lines);
  }

  /// No amount with a currency sign at all (OCR often drops or misreads "₹"): accept a
  /// number inside "Payment of … to NAME". If several, keep the one that is also printed
  /// alone on a line (the big amount at the top of the receipt).
  static double? _ocrFallbackAmount(List<String> lines) {
    final phrase = <double>{};
    for (final line in lines) {
      if (_promoLine.hasMatch(line)) continue;
      for (final m in _lenientPhraseAmount.allMatches(line)) {
        final v = _toAmount(m.group(1)!);
        if (v != null) phrase.add(v);
      }
    }
    if (phrase.length == 1) return phrase.first;
    if (phrase.isEmpty) return null;
    final alone = <double>{};
    for (final line in lines) {
      final m = _amountOnlyLine.firstMatch(line);
      final v = m == null ? null : _toAmount(m.group(1)!);
      if (v != null && phrase.contains(v)) alone.add(v);
    }
    return alone.length == 1 ? alone.first : null;
  }

  static String? _extractPayee(String s) {
    for (final re in _payeePatterns) {
      for (final m in re.allMatches(s)) {
        final p = _clean(m.group(1));
        if (p != null) return p;
      }
    }
    return null;
  }

  static String? _extractPayer(String s) {
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
    var p = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    p = p.replaceAll(RegExp(r'^(vpa|upi id|mr\.?|ms\.?|mrs\.?)\s+', caseSensitive: _ci), '');
    p = p.replaceAll(RegExp(r'[\s.,;:-]+$'), '');
    if (p.contains('@')) p = p.split('@').first;
    if (p.length < 2 || p.length > 40) return null;
    if (_notAPayee.hasMatch(p)) return null;
    if (RegExp(r'^[x*\d\s]+$', caseSensitive: _ci).hasMatch(p)) return null;
    return p;
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

    if (found == null) return null;
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
