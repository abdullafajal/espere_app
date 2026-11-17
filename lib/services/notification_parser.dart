/// On-device parser for payment notifications (UPI apps, bank apps, bank SMS).
///
/// Pure Dart, no Flutter imports: easy to unit test. It never guesses: if the amount is
/// ambiguous, or the message is an OTP / request / reminder / failure / offer / balance
/// alert / mandate setup, [NotificationParser.parse] returns null.
library;

enum ParseConfidence { high, low }

/// The handful of fields auto-capture keeps from a notification (in memory only).
class RawNotification {
  final String key;
  final String packageName;

  /// Source group from the native allow-list: gpay, phonepe, paytm, bhim, amazonpay,
  /// cred, whatsapp, banks, sms.
  final String group;

  /// Human label of the source app, e.g. "Google Pay", "HDFC Bank", "SMS".
  final String label;
  final String title;
  final String text;
  final String bigText;
  final DateTime postTime;

  const RawNotification({
    required this.key,
    required this.packageName,
    required this.group,
    required this.label,
    this.title = '',
    this.text = '',
    this.bigText = '',
    required this.postTime,
  });

  /// The message body: the expanded text when present, else the short text.
  String get body => bigText.trim().isNotEmpty ? bigText : text;

  factory RawNotification.fromMap(Map<dynamic, dynamic> m) => RawNotification(
        key: (m['key'] ?? '').toString(),
        packageName: (m['packageName'] ?? '').toString(),
        group: (m['group'] ?? '').toString(),
        label: (m['label'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        text: (m['text'] ?? '').toString(),
        bigText: (m['bigText'] ?? '').toString(),
        postTime: DateTime.fromMillisecondsSinceEpoch(
          (m['postTime'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        ),
      );
}

class ParseResult {
  final double amount;

  /// 'expense' or 'income'
  final String type;
  final String? payee;

  /// UPI ref / UTR / transaction id, normalised (upper-case, alphanumeric only).
  final String? ref;

  /// Last 4 digits of the account or card, when the message names one.
  final String? accountLast4;

  /// Label of the app the notification came from, e.g. "Google Pay".
  final String sourceApp;

  /// 'upi', 'card' or 'bank' (matches the app's payment_method values).
  final String paymentMethod;
  final ParseConfidence confidence;
  final DateTime time;

  /// A refund / reversal of an earlier payment ("reversed", "credited back", "refund").
  final bool isReversal;

  const ParseResult({
    required this.amount,
    required this.type,
    required this.sourceApp,
    required this.paymentMethod,
    required this.confidence,
    required this.time,
    this.payee,
    this.ref,
    this.accountLast4,
    this.isReversal = false,
  });

  /// Only the last 4 characters of the reference are ever stored or shown.
  String? get refLast4 =>
      ref == null ? null : (ref!.length <= 4 ? ref : ref!.substring(ref!.length - 4));

  @override
  String toString() =>
      'ParseResult($type $amount payee=$payee ref=${refLast4 == null ? '-' : '…$refLast4'} '
      'last4=$accountLast4 via=$sourceApp method=$paymentMethod ${confidence.name})';
}

class NotificationParser {
  NotificationParser._();

  static const _ci = false; // readability: RegExp(caseSensitive: _ci)

  // ─── Things that are not a completed payment ──────────────────────────────

  static final _reject = <RegExp>[
    // OTPs / security codes
    RegExp(r'\b(otp|one[\s-]?time[\s-]?password|verification code|security code)\b',
        caseSensitive: _ci),
    // Payment / collect requests
    RegExp(
        r'\b(has requested|is requesting|requested (you|money|payment|for|₹|rs|inr)|'
        r'payment request|money request|collect request|request(ed)? to pay|'
        r'sent you a request|wants you to pay)\b',
        caseSensitive: _ci),
    // Reminders, bills due, future debits
    RegExp(
        r'\b(reminder|remind|is due|are due|due (on|by|date|today|tomorrow|in)|bill due|'
        r'overdue|pay (by|before)|upcoming (payment|debit|autopay|emi)|'
        r'will be (debited|deducted|charged|auto-?debited)|scheduled)\b',
        caseSensitive: _ci),
    // Failed / pending / declined
    RegExp(
        r'\b(failed|failure|declined|unsuccessful|not successful|could not|couldn.t|'
        r'pending|processing|in progress|on hold|insufficient|timed out|expired)\b',
        caseSensitive: _ci),
    // Offers / ads
    RegExp(
        r'\b(offer|offers|win|won|cashback (up ?to|of up)|get (up ?to|flat)|flat ₹|'
        r'\d+ ?% off|discount|coupon|voucher code|limited (time|period)|hurry|apply now|'
        r'pre-?approved|instant loan|loan (offer|of up)|credit limit (increase|upgrade)|'
        r'exclusive|congratulations)\b',
        caseSensitive: _ci),
    // Mandate / autopay setup (an executed autopay debit is still a real expense)
    RegExp(
        r'\b(e-?mandate|mandate|autopay|auto-pay|standing instruction)\b(?:[^.\n]|\.(?=\d)){0,80}?\b'
        r'(set ?up|created|registered|activated|approved|authori[sz]ed|successfully (set|created))',
        caseSensitive: _ci),
    RegExp(r'\b(set ?up|create|activate|approve) (an? |your )?(upi )?(autopay|auto-pay|mandate)\b',
        caseSensitive: _ci),
    RegExp(r'\b(auto ?pay|autopay) (facility )?(has been )?(successfully )?(activated|registered|enabled)\b',
        caseSensitive: _ci),
    // Credit-card bill payments: the purchases were already counted when the card was used,
    // so counting the bill again would double the spend.
    RegExp(
        r'\b(payment|paid|repayment|bill pay(ment)?)\b(?:[^.\n]|\.(?=\d)){0,60}?\b(towards|to|for|on|into)\b(?:[^.\n]|\.(?=\d)){0,30}?'
        r'\bcredit\s*card\b',
        caseSensitive: _ci),
    RegExp(
        r'^(?!.*\brefund).*\b(received|credited)\b(?:[^.\n]|\.(?=\d)){0,40}?\b(towards|to|on|in|into)\s+(your\s+)?(?:[^.\n]|\.(?=\d)){0,30}?'
        r'\b(credit\s*card|card account)\b',
        caseSensitive: _ci),
    RegExp(r'\bpayment\b(?:[^.\n]|\.(?=\d)){0,40}\breceived\b(?:[^.\n]|\.(?=\d)){0,40}card\b', caseSensitive: _ci),
    // Moving money between the user's own accounts / wallets is not spending
    RegExp(r'\b(self[\s-]?transfer|own account|to self|between (your|own) accounts)\b',
        caseSensitive: _ci),
    RegExp(r'\b(added|loaded|top[\s-]?up|topped up)\b(?:[^.\n]|\.(?=\d)){0,40}\b(wallet|upi lite|gift card)\b',
        caseSensitive: _ci),
    // Interest, deposits, statements
    RegExp(r'\b(net interest|interest (paid|credited|earned) (on|for)|tds (deducted|on interest))\b',
        caseSensitive: _ci),
    RegExp(
        r'\b(fixed deposit|term deposit|recurring deposit)\b(?:[^.\n]|\.(?=\d)){0,40}\b'
        r'(opened|booked|created|renewed|closed|matured|maturity)\b',
        caseSensitive: _ci),
    RegExp(
        r'\b(statement|e-?statement|total amount due|minimum amount due|min\.? amt due|'
        r'bill (is )?generated)\b',
        caseSensitive: _ci),
    // A refund that has not happened yet
    RegExp(r'\bwill be (refunded|reversed|credited|processed|initiated)\b', caseSensitive: _ci),
    RegExp(r'\brefund (has been |is )?initiated\b', caseSensitive: _ci),
  ];

  /// Amounts in a foreign currency: the rupee amount is unknown, so never guess it.
  static final _foreign = RegExp(
      r'\b(USD|EUR|GBP|AED|SGD|AUD|CAD|JPY|CHF|SAR|QAR|KWD|OMR|BHD|MYR|THB|HKD|NZD|CNY)\s*\.?\s*\d');

  /// Real payments that should still be confirmed by the user (never added silently):
  /// loan EMIs, SIPs, insurance, NACH/ACH debits, cash withdrawals.
  static final _reviewOnly = RegExp(
      r'\b(?:info)?(nach|ach|ecs|enach)\b|\b(standing instruction|sip|mutual fund|insurance|premium|'
      r'emi|loan|atm|cash withdrawal|withdrawn|withdrawal|cardless cash)\b',
      caseSensitive: _ci);

  /// Refunds / reversals of an earlier payment.
  static final _reversal = RegExp(
      r'\b(reversed|reversal|credited back|refunded|refund)\b|\brev[\s:-]', caseSensitive: _ci);

  /// Masked account / card numbers ("A/c XX1234", "Acct XX123", "Card x4321", "A/c ...5494").
  static final _maskedAccount = RegExp(
      r'\b(?:a/?c|acct|account|ac|card)\.?\s*(?:no\.?\s*)?(?:ending\s*(?:with|in)?\s*)?'
      r'[x*•.]+\s*(\d{3,6})\b',
      caseSensitive: _ci);

  // ─── Amount ───────────────────────────────────────────────────────────────

  /// ₹ / Rs / INR followed by an amount with optional Indian/western commas and decimals.
  static final _amount = RegExp(
      r'(?:₹|\brs\.?|\binr)\s*\.?\s*(\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)',
      caseSensitive: _ci);

  /// SBI-style "debited by 250.0" (no currency sign but an unambiguous structure).
  static final _amountBy =
      RegExp(r'\b(?:debited|credited)\s+by\s+(\d+(?:\.\d{1,2})?)\b', caseSensitive: _ci);

  /// Amounts right after these words are balances / limits, not the payment.
  static final _notPaymentAmount = RegExp(
      r'(bal|balance|limit|lmt|avl|avlbl|avbl|aval|available|outstanding|total due|'
      r'min(imum)? due|reward|points|emi of|o/s)\W{0,6}(is\W{0,3}|amt\W{0,3})?'
      r'(?:₹|rs\.?|inr)?\s*\.?\s*$',
      caseSensitive: _ci);

  // ─── Direction ────────────────────────────────────────────────────────────

  static final _incomeWords = RegExp(
      r'(?<![a-z])(sent you|paid you|received|credited|credit(?=:)|upi credit|refund(ed)?|reversed|'
      r'reversal|cashback|deposited|added to your|cr\.?)(?![a-z])',
      caseSensitive: _ci);
  static final _expenseWords = RegExp(
      r'(?<![a-z])(paid|sent|debited|debit(?=:)|upi debit|debit of|spent|withdrawn|withdrawal|'
      r'purchased?|deducted|transferred|payment of|payment to|payment successful|money sent|'
      r'dr\.?|done at)(?![a-z])|(?<![a-z])(txn|transaction) of (?:[^.\n]|\.(?=\d)){0,40}? at (?![0-9])',
      caseSensitive: _ci);

  /// Wordings where the "income" word describes the other side of a payment the user made.
  static final _outflowOverride = RegExp(
      r'\b(has|have) received\b(?:[^.\n]|\.(?=\d)){0,40}\bfrom your\b|\bcredited to (the )?(beneficiary|payee)\b',
      caseSensitive: _ci);

  // ─── Details ──────────────────────────────────────────────────────────────

  static final _ref = RegExp(
      r'\b(?:upi\s*(?:transaction|txn)\s*(?:id|no)|upi\s*ref(?:erence)?(?:\s*(?:no|number|id))?|'
      r'ref(?:erence)?\s*(?:no|number|id)|'
      r'refno|ref|utr(?:\s*no)?|rrn|txn\s*(?:id|no)|transaction\s*(?:id|no|ref)|upi)'
      r'\s*[:.#-]?\s*(?:is\s*)?([A-Za-z0-9]{6,30})\b',
      caseSensitive: _ci);
  static final _refSlash = RegExp(r'\bUPI/(?:P2[AM]|[A-Z]{2,4})/(\d{6,30})/', caseSensitive: _ci);

  static final _last4 = RegExp(
      r'\b(?:a/?c|acct|account|card)\s*(?:no\.?|number)?\s*(?:ending\s*(?:with|in)?\s*)?'
      r'[x*•.\s]*(\d{4})\b',
      caseSensitive: _ci);
  static final _endingIn = RegExp(r'\bending\s*(?:with|in)?\s*[x*]*(\d{4})\b', caseSensitive: _ci);

  static const _stop =
      r'(?=\s+(?:on|via|thru|through|towards|using|for|ref|refno|upi|from|at|to|successfully|is|was|with|has|has been|'
      r'avl|available|not you|info|dated|successful|successfully|completed|done)\b|'
      r'\s*(?:[,;:(\n]|\.(?:\s|$|(?=(?:ref|rs|upi|avl|bal|info|not)\b)))|\s*-\s|\s*$)';
  static final _payeeIncomeName =
      RegExp(r'(?:^|[.!\n]\s*)([A-Za-z][A-Za-z0-9 .&' "'" r'-]{1,40}?)\s+(?:has\s+)?(?:sent|paid) you\b',
          caseSensitive: _ci);
  static final _payeeFrom = RegExp(
      r'\b(?:from|by)\s+(?:vpa\s+|upi\s+id\s+)?([A-Za-z0-9@._&' "'" r' -]{2,40}?)' '$_stop',
      caseSensitive: _ci);
  static final _payeeTo = RegExp(
      r'\b(?:trf to|transfer to|paid to|sent to|payment to|to)\s+(?:vpa\s+|upi\s+id\s+)?'
      r'([A-Za-z0-9@._&' "'" r' -]{2,40}?)' '$_stop',
      caseSensitive: _ci);
  static final _payeeAt =
      RegExp(r'\b(?:at|on)\s+([A-Za-z0-9@._&' "'" r' -]{2,40}?)' '$_stop', caseSensitive: _ci);
  static final _payeeIciciCredited =
      RegExp(r';\s*([A-Za-z0-9@._&' "'" r' -]{2,40}?)\s+credited\b', caseSensitive: _ci);
  static final _payeeSlash =
      RegExp(r'\bUPI/(?:P2[AM]|[A-Z]{2,4})/\d{6,30}/([A-Za-z0-9 ._&-]{2,40}?)(?:/|\s|$)',
          caseSensitive: _ci);

  /// Words that look like a name but are not a payee.
  static final _notAPayee = RegExp(
      r'^(your|you|a/?c|acct|account|card|bank|wallet|the|upi|vpa|rs|inr|my|self|mobile|'
      r'hdfc bank|sbi|icici bank|axis bank|kotak bank|.*\bbank a/?c\b.*|.*\bbank card\b.*|'
      r'\d[\d\s:/-]*)$',
      caseSensitive: _ci);

  static final _cardWord = RegExp(r'\b(credit card|debit card|card)\b', caseSensitive: _ci);
  static final _upiWord = RegExp(r'\b(upi|vpa|bhim)\b|@[a-z]{2,}', caseSensitive: _ci);

  /// DLT sender IDs from banks / UPI apps ("VM-HDFCBK", "AD-SBIINB", "JD-ICICIT-S").
  static final _dltHeader = RegExp(r'^(?:[A-Z]{2}-)?([A-Z0-9]{5,9})(?:-[A-Z])?$');
  static const _bankTokens = [
    'HDFC', 'SBI', 'ICICI', 'AXIS', 'KOTAK', 'KMB', 'PAYTM', 'PNB', 'BOB', 'BARODA', 'CANARA',
    'CNRB', 'UNION', 'UBOI', 'IDFC', 'YESB', 'INDUS', 'FEDBK', 'FEDERAL', 'AUBANK', 'RBL', 'CITI',
    'AMEX', 'SCB', 'HSBC', 'BOI', 'CBOI', 'IOB', 'UCO', 'PHONEPE', 'GPAY', 'AMAZON', 'CRED', 'NPCI',
    'BHIM', 'JUPITER', 'SLICE', 'ONECARD', 'IPPB', 'DBS', 'BANK',
  ];

  static const _upiGroups = {'gpay', 'phonepe', 'paytm', 'bhim', 'amazonpay', 'cred', 'whatsapp'};

  /// Same rule the native listener applies; repeated here as a second line of defence.
  static bool isBankSender(String sender) {
    final m = _dltHeader.firstMatch(sender.trim().toUpperCase());
    if (m == null) return false;
    final body = m.group(1)!;
    return _bankTokens.any(body.contains);
  }

  // ─── Entry point ──────────────────────────────────────────────────────────

  static ParseResult? parse(RawNotification n) {
    if (n.group == 'sms' && !isBankSender(n.title)) return null;

    // SMS titles are just the sender ID; for apps the title often carries the payment line.
    final body = n.body.trim();
    final full = (n.group == 'sms' ? body : '${n.title.trim()}\n$body').trim();
    if (full.isEmpty) return null;

    for (final r in _reject) {
      if (r.hasMatch(full)) return null;
    }
    if (_foreign.hasMatch(full)) return null;

    final amount = _extractAmount(full);
    if (amount == null || amount <= 0) return null;

    final type = _extractType(full);
    if (type == null) return null;

    // Two masked accounts, one debited and one credited: often a transfer between the user's
    // own accounts (not spending), sometimes to someone else. Never added silently.
    final accounts = _maskedAccount.allMatches(full).map((m) => m.group(1)).toSet();
    final maybeSelfTransfer =
        accounts.length >= 2 && _incomeWords.hasMatch(full) && _expenseWords.hasMatch(full);

    final isReversal = type == 'income' && _reversal.hasMatch(full);
    final reviewOnly = _reviewOnly.hasMatch(full) || isReversal || maybeSelfTransfer;

    final ref = _extractRef(full);
    final last4 = _extractLast4(full);
    final payee = _extractPayee(full, type);

    final String method;
    if (_cardWord.hasMatch(full) && !_upiWord.hasMatch(full)) {
      method = 'card';
    } else if (_upiWord.hasMatch(full) || _upiGroups.contains(n.group)) {
      method = 'upi';
    } else {
      method = 'bank';
    }

    return ParseResult(
      amount: amount,
      type: type,
      payee: payee,
      ref: ref,
      accountLast4: last4,
      sourceApp: n.label.isNotEmpty ? n.label : n.packageName,
      paymentMethod: method,
      confidence: ref != null && !reviewOnly ? ParseConfidence.high : ParseConfidence.low,
      time: n.postTime,
      isReversal: isReversal,
    );
  }

  /// Exactly one distinct payment amount, or null (never guesses).
  static double? _extractAmount(String s) {
    final values = <double>{};
    for (final m in _amount.allMatches(s)) {
      final before = s.substring(0, m.start);
      final window = before.length > 30 ? before.substring(before.length - 30) : before;
      if (_notPaymentAmount.hasMatch(window)) continue;
      final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (v != null) values.add((v * 100).roundToDouble() / 100);
    }
    for (final m in _amountBy.allMatches(s)) {
      final v = double.tryParse(m.group(1)!);
      if (v != null) values.add((v * 100).roundToDouble() / 100);
    }
    return values.length == 1 ? values.first : null;
  }

  /// The first direction word wins ("debited ... credited to X" is an expense);
  /// "sent you" / "paid you" count as income even though they contain "sent"/"paid".
  static String? _extractType(String s) {
    if (_outflowOverride.hasMatch(s)) return 'expense';
    final inc = _incomeWords.firstMatch(s);
    final exp = _expenseWords.firstMatch(s);
    if (inc == null && exp == null) return null;
    if (inc == null) return 'expense';
    if (exp == null) return 'income';
    return inc.start <= exp.start ? 'income' : 'expense';
  }

  static String? _extractRef(String s) {
    final slash = _refSlash.firstMatch(s);
    if (slash != null) return _normRef(slash.group(1)!);
    for (final m in _ref.allMatches(s)) {
      final v = m.group(1)!;
      if (RegExp(r'\d').allMatches(v).length >= 6) return _normRef(v);
    }
    return null;
  }

  static String _normRef(String v) => v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static String? _extractLast4(String s) =>
      _last4.firstMatch(s)?.group(1) ?? _endingIn.firstMatch(s)?.group(1);

  static String? _extractPayee(String s, String type) {
    final candidates = <RegExpMatch?>[
      _payeeSlash.firstMatch(s),
      if (type == 'income') ...[
        _payeeIncomeName.firstMatch(s),
        _payeeFrom.firstMatch(s),
      ] else ...[
        _payeeIciciCredited.firstMatch(s),
        ..._payeeTo.allMatches(s),
        ..._payeeAt.allMatches(s),
      ],
    ];
    for (final m in candidates) {
      final p = _cleanPayee(m?.group(1));
      if (p != null) return p;
    }
    return null;
  }

  static String? _cleanPayee(String? raw) {
    if (raw == null) return null;
    var p = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    p = p.replaceAll(RegExp(r'^(vpa|upi id|mr\.?|ms\.?|mrs\.?)\s+', caseSensitive: _ci), '');
    p = p.replaceAll(RegExp(r'[\s.,;:-]+$'), '');
    if (p.contains('@')) {
      // VPA: show the handle part ("swiggy@icici" -> "swiggy")
      p = p.split('@').first;
    }
    if (p.length < 2 || p.length > 40) return null;
    if (_notAPayee.hasMatch(p)) return null;
    if (RegExp(r'^[x*\d\s]+$', caseSensitive: _ci).hasMatch(p)) return null;
    return p;
  }
}
