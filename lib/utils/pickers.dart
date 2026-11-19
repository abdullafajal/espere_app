/// Builder for showDatePicker / showTimePicker: the dialogs ignore a large system font
/// size, so they always fit the screen. If they do not fit they turn into a scroll view,
/// and then dragging the clock's hand scrolls the dialog instead of moving the hand.
library;

import 'package:flutter/widgets.dart';

Widget pickerBuilder(BuildContext context, Widget? child) =>
    MediaQuery.withClampedTextScaling(maxScaleFactor: 1.0, child: child ?? const SizedBox.shrink());
