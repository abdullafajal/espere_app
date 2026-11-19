import 'dart:math' as math;

import 'package:espere_app/theme/motion.dart';
import 'package:espere_app/utils/pickers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('clock hand can be dragged from 1 to 3 on a small screen with a large font', (t) async {
    t.view.devicePixelRatio = 2.6;
    t.view.physicalSize = const Size(360 * 2.6, 720 * 2.6);
    addTearDown(t.view.reset);
    TimeOfDay? picked;
    await t.pumpWidget(MaterialApp(
      scrollBehavior: const EspereScrollBehavior(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                picked = await showTimePicker(
                  context: context,
                  builder: pickerBuilder,
                  initialTime: const TimeOfDay(hour: 13, minute: 0),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    // Drag the hand from "1" round to "3".
    // The dial's numbers are painted, so find their spots from the dial's centre.
    final dial = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Dial');
    expect(dial, findsOneWidget);
    final c = t.getCenter(dial);
    final r = t.getSize(dial).width / 2 * 0.8;
    Offset at(int hour) {
      final a = hour * math.pi / 6;
      return c + Offset(math.sin(a) * r, -math.cos(a) * r);
    }
    final one = at(1);
    final three = at(3);
    final g = await t.startGesture(one);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(one, three, i / 10)!);
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(picked?.hour, 15);
  });
}
