/// The app's progress bar: ten blocks of 10% each, filled to the exact share (61% is
/// six blocks and a tenth of the seventh). Used for every budget and limit, so progress
/// reads the same everywhere.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class BlockBar extends StatelessWidget {
  /// How much is used: 0-1 (more than 1 fills every block).
  final double value;
  final Color? color;
  final Color? track;
  final double height;

  const BlockBar({super.key, required this.value, this.color, this.track, this.height = 7});

  @override
  Widget build(BuildContext context) {
    final tenths = (value * 10).clamp(0.0, 10.0);
    final fill = color ?? (value >= 0.8 ? AppColors.dark : AppColors.accent);
    final bg = track ?? AppColors.surface;
    return Row(
      children: [
        for (var k = 0; k < 10; k++) ...[
          if (k > 0) const SizedBox(width: 2.5),
          Expanded(
            child: Container(
              height: height,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3)),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (tenths - k).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
