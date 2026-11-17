/// Picks a category for an auto-captured payment (pure Dart, unit-testable).
///
/// Order: the user's own past choice for this payee → payee keywords → a fallback
/// ("Other" of the right type, else the first category of that type).
library;

class AutoCategoryRules {
  AutoCategoryRules._();

  /// Payee keyword → words to look for in the user's category names.
  static final _rules = <(RegExp, List<String>)>[
    (RegExp(r'swiggy|zomato|domino|pizza|kfc|mcdonald|burger|starbucks|cafe|coffee|restaurant|eats|dine|biryani|chai|tea ?stall|bakery', caseSensitive: false),
        ['food', 'dining', 'restaurant']),
    (RegExp(r'bigbasket|big basket|blinkit|zepto|instamart|dmart|jiomart|grocer|kirana|supermarket|more retail', caseSensitive: false),
        ['grocer', 'food']),
    (RegExp(r'uber|ola\b|olacabs|rapido|metro|irctc|redbus|railway|cab|taxi|auto rickshaw|fastag|petrol|fuel|indianoil|hpcl|bpcl|shell', caseSensitive: false),
        ['transport', 'travel', 'fuel', 'commute']),
    (RegExp(r'amazon|flipkart|myntra|ajio|meesho|nykaa|tata cliq|snapdeal|croma|reliance digital|decathlon', caseSensitive: false),
        ['shopping']),
    (RegExp(r'recharge|electricity|bescom|tneb|msedcl|power|airtel|jio\b|vodafone|\bvi\b|bsnl|broadband|wifi|gas|water|bill|dth|tata play|credit card', caseSensitive: false),
        ['bill', 'utilit', 'recharge']),
    (RegExp(r'netflix|hotstar|spotify|prime video|bookmyshow|pvr|inox|youtube|zee5|sonyliv', caseSensitive: false),
        ['entertain', 'subscription', 'movie']),
    (RegExp(r'pharm|apollo|medplus|1mg|netmeds|hospital|clinic|diagnostic|lab', caseSensitive: false),
        ['health', 'medical']),
  ];

  /// Category-name words suggested by the payee, or empty.
  static List<String> keywordsFor(String? payee) {
    if (payee == null || payee.trim().isEmpty) return const [];
    for (final (re, words) in _rules) {
      if (re.hasMatch(payee)) return words;
    }
    return const [];
  }

  /// [categories]: maps with id, name, type (as cached by the app).
  static int? pick({
    required String? payee,
    required String type,
    required List<Map<String, dynamic>> categories,
    int? rememberedId,
  }) {
    final ofType = categories.where((c) => (c['type'] ?? 'expense') == type).toList();
    if (ofType.isEmpty) return null;

    if (rememberedId != null && ofType.any((c) => c['id'] == rememberedId)) return rememberedId;

    for (final word in keywordsFor(payee)) {
      for (final c in ofType) {
        if ((c['name'] ?? '').toString().toLowerCase().contains(word)) return c['id'] as int?;
      }
    }

    for (final c in ofType) {
      if ((c['name'] ?? '').toString().toLowerCase().contains('other')) return c['id'] as int?;
    }
    return ofType.first['id'] as int?;
  }
}
