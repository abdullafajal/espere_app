import 'package:espere_app/widgets/category_carousel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('swipe moves the pick, a side card comes to the middle, the middle opens the list', (t) async {
    final items = [
      for (final n in ['Food', 'Travel', 'Shopping', 'Bills', 'Fun'])
        CarouselCategory(label: n, icon: Icons.circle, note: n == 'Food' ? '₹500 left' : null, used: n == 'Food' ? .5 : null),
    ];
    var index = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 380,
            child: StatefulBuilder(
              builder: (context, set) => CategoryCarousel(items: items, index: index, onChanged: (i) => set(() => index = i)),
            ),
          ),
        ),
      ),
    ));
    final centre = t.getCenter(find.byType(CategoryCarousel)) - const Offset(0, 14);

    // It goes round: the last category is to the left of the first.
    await t.dragFrom(centre, const Offset(130, 0));
    await t.pumpAndSettle();
    expect(index, 4);
    await t.dragFrom(centre, const Offset(-130, 0));
    await t.pumpAndSettle();
    expect(index, 0);

    await t.dragFrom(centre, const Offset(-130, 0));
    await t.pumpAndSettle();
    expect(index, 1);

    // Tap the card to the right of the middle one.
    await t.tapAt(centre + const Offset(108, 0));
    await t.pumpAndSettle();
    expect(index, 2);

    // Tap the middle card: the list opens; pick "Fun".
    await t.tapAt(centre);
    await t.pumpAndSettle();
    expect(find.text('Search categories'), findsOneWidget);
    await t.tap(find.text('Fun').last);
    await t.pumpAndSettle();
    expect(index, 4);
  });
}
