import 'package:espere_app/services/auto_category_rules.dart';
import 'package:flutter_test/flutter_test.dart';

final _cats = <Map<String, dynamic>>[
  {'id': 1, 'name': 'Food & Dining', 'type': 'expense'},
  {'id': 2, 'name': 'Transportation', 'type': 'expense'},
  {'id': 3, 'name': 'Shopping', 'type': 'expense'},
  {'id': 4, 'name': 'Bills & Utilities', 'type': 'expense'},
  {'id': 5, 'name': 'Other', 'type': 'expense'},
  {'id': 6, 'name': 'Salary', 'type': 'income'},
  {'id': 7, 'name': 'Other Income', 'type': 'income'},
];

int? pick(String? payee, {String type = 'expense', int? remembered}) =>
    AutoCategoryRules.pick(payee: payee, type: type, categories: _cats, rememberedId: remembered);

void main() {
  test('keywords map payees to categories', () {
    expect(pick('Swiggy'), 1);
    expect(pick('ZOMATO'), 1);
    expect(pick('Uber India'), 2);
    expect(pick('Ola'), 2);
    expect(pick('Amazon Seller Services'), 3);
    expect(pick('Flipkart'), 3);
    expect(pick('Airtel recharge'), 4);
    expect(pick('ELECTRICITY BOARD'), 4);
    expect(pick('teastall'), 1);
    expect(pick('Tea Stall'), 1);
  });

  test("the user's remembered choice wins over keywords", () {
    expect(pick('Swiggy', remembered: 3), 3);
  });

  test('a remembered category of the wrong type is ignored', () {
    expect(pick('Swiggy', remembered: 6), 1);
  });

  test('falls back to Other of the right type', () {
    expect(pick('Ramesh Kumar'), 5);
    expect(pick(null), 5);
    expect(pick('Priya', type: 'income'), 7);
  });

  test('no categories of that type gives null', () {
    expect(
      AutoCategoryRules.pick(payee: 'x', type: 'income', categories: const []),
      isNull,
    );
  });
}
