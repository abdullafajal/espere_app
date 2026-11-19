/// Espere — Modern Expense & Income Tracker
///
/// The whole app uses three colours: ink (near-black), white and an accent (Espere lime
/// by default; the user can pick another in Settings → App colour), plus neutral
/// greys for surfaces and secondary text. Nothing else: categories and groups have no
/// colour of their own (icons only), and money in / out is told apart by the "+" / "−"
/// sign, not by colour. Font: Plus Jakarta Sans (bundled, works offline).
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ─── Design tokens ───────────────────────────────────────────────────────

class AppColors {
  AppColors._();

  // Brand
  /// Accent (lime by default): main action, selection, active tab. The user can pick
  /// another one in Settings (see [AppAccent]).
  static Color get accent => AppAccent.current.color;
  static Color get accentHover => Color.lerp(accent, Colors.white, 0.25)!;
  static Color get accentSoft => AppAccent.current.soft; // highlights, "to review"
  static const Color dark = Color(0xFF141414); // ink

  // Light theme
  static const Color background = Color(0xFFF5F6F2); // app ground
  static const Color card = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF141414);
  static const Color muted = Color(0xFF5B6058); // secondary text, 6:1 on white
  static const Color mutedLight = Color(0xFF8E938A); // placeholders, disabled
  static const Color border = Color(0xFFECEEE8);
  static const Color surface = Color(0xFFF2F3EE); // chips, inputs, icon circles

  // Dark surfaces (hero cards, nav bar, keypad panel)
  static const Color darkCard = Color(0xFF222520);
  static const Color darkCardRaised = Color(0xFF2B2E28);
  static const Color darkMuted = Color(0xFFB9BDB5); // secondary text on ink
  static const Color darkFaint = Color(0xFF8E938A);

  // Dark theme (kept for completeness; the app runs in light mode)
  static const Color backgroundDark = Color(0xFF0F0F0F);
  static const Color cardDark = Color(0xFF1A1A1A);
  static const Color textDark = Color(0xFFF0F0F0);
  static const Color mutedDark = Color(0xFF8E938A);
  static const Color borderDark = Color(0xFF2A2A2A);
  static const Color surfaceDark = Color(0xFF151515);

  // Semantic: the same three colours. Amounts are ink; "+" / "−" tells the direction.
  static const Color income = Color(0xFF141414);
  static const Color incomeLight = Color(0xFFF2F3EE);
  static const Color expense = Color(0xFF141414);
  static const Color expenseLight = Color(0xFFF2F3EE);
  static const Color error = Color(0xFF141414);
  static const Color errorLight = Color(0xFFF2F3EE);
  static const Color warning = Color(0xFF141414);
  static const Color warningLight = Color(0xFFF2F3EE);
  static Color get success => accent;
  static Color get successLight => accentSoft;

  /// Every category / group icon sits on this circle, in [categoryInk].
  static const Color categoryFill = surface;
  static const Color categoryInk = dark;

  /// Chart series without category colours: ink, lime, then greys.
  static List<Color> get chart => [
    const Color(0xFF141414),
    accent,
    const Color(0xFF5B6058),
    Color.lerp(accent, const Color(0xFF141414), 0.3)!,
    const Color(0xFF8E938A),
    const Color(0xFFB9BDB5),
    const Color(0xFF3A3D38),
    const Color(0xFFDADDD5),
  ];
  static Color chartAt(int i) => chart[i % chart.length];

  // Kept for code that still references it.
  static const LinearGradient avatarGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF141414), Color(0xFF141414)],
  );
}

/// ─── Accent choices ──────────────────────────────────────────────────────

class AccentOption {
  final String name;
  final Color color;
  final Color soft;
  const AccentOption(this.name, this.color, this.soft);
}

/// The accent colour the user picked in Settings. Only light colours, so ink text and
/// icons on it stay readable.
class AppAccent {
  AppAccent._();

  static const _key = 'accent_colour';

  static const options = [
    AccentOption('Lime', Color(0xFFC8E64A), Color(0xFFEFF7CF)),
    AccentOption('Mint', Color(0xFF8FE3B8), Color(0xFFDDF6E9)),
    AccentOption('Sky', Color(0xFF9CCBFF), Color(0xFFE3F0FF)),
    AccentOption('Lavender', Color(0xFFC3B3FF), Color(0xFFEDE8FF)),
    AccentOption('Pink', Color(0xFFFFA8C8), Color(0xFFFFE5EF)),
    AccentOption('Peach', Color(0xFFFFB68C), Color(0xFFFFE9DC)),
    AccentOption('Sun', Color(0xFFF7D64A), Color(0xFFFCF3CC)),
  ];

  static int _index = 0;
  static AccentOption get current => options[_index];
  static int get index => _index;

  /// Previews and tests: switch without saving.
  @visibleForTesting
  static set debugIndex(int i) => _index = i;

  /// Reads the saved choice (call before runApp).
  static Future<void> load() async {
    try {
      final i = (await SharedPreferences.getInstance()).getInt(_key) ?? 0;
      _index = (i >= 0 && i < options.length) ? i : 0;
    } catch (_) {
      _index = 0;
    }
  }

  /// Saves [i] and redraws every screen in the new colour.
  static Future<void> set(int i) async {
    if (i < 0 || i >= options.length || i == _index) return;
    _index = i;
    (await SharedPreferences.getInstance()).setInt(_key, i);
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }
    root.visitChildren(rebuild);
  }
}

/// ─── Radii ───────────────────────────────────────────────────────────────

class AppRadius {
  AppRadius._();

  static const double sm = 10;
  static const double md = 14;
  static const double lg = 16; // inputs
  static const double xl = 20; // buttons
  static const double xxl = 24; // cards
  static const double xxxl = 28; // hero cards, sheets
  static const double pill = 34; // nav bar, full-round
}

/// ─── Shadows ─────────────────────────────────────────────────────────────

class AppShadows {
  AppShadows._();

  /// Cards on the grey ground: barely there.
  static List<BoxShadow> get soft => [
        BoxShadow(
          color: const Color(0xFF141414).withValues(alpha: 0.05),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get card => soft;

  /// Hero cards and floating sheets.
  static List<BoxShadow> get elevated => [
        BoxShadow(
          color: const Color(0xFF141414).withValues(alpha: 0.16),
          blurRadius: 36,
          offset: const Offset(0, 16),
        ),
      ];

  /// The lime "Add expense" button.
  static List<BoxShadow> get accent => [
        BoxShadow(
          color: Color.lerp(AppColors.accent, const Color(0xFF141414), 0.25)!.withValues(alpha: 0.30),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  /// The floating navigation bar.
  static List<BoxShadow> get nav => [
        BoxShadow(
          color: const Color(0xFF141414).withValues(alpha: 0.28),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ];
}

/// ─── Theme ───────────────────────────────────────────────────────────────

class AppTheme {
  AppTheme._();

  static const String fontFamily = 'PlusJakartaSans';

  static ThemeData get lightTheme {
    final scheme = ColorScheme.light(
      primary: AppColors.dark,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: AppColors.dark,
      surface: AppColors.card,
      onSurface: AppColors.text,
      onSurfaceVariant: AppColors.muted,
      outline: AppColors.border,
      error: AppColors.dark,
      onError: Colors.white,
    );

    final roundedButton = RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl));
    const buttonText = TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 15);

    final base = ThemeData(useMaterial3: true, fontFamily: fontFamily, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
      iconTheme: const IconThemeData(color: AppColors.text, size: 22),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppColors.text,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xxl)),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: const BorderSide(color: AppColors.dark, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: const BorderSide(color: AppColors.dark, width: 1.5),
        ),
        hintStyle: const TextStyle(color: AppColors.mutedLight, fontSize: 15),
        labelStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
        prefixIconColor: AppColors.muted,
        suffixIconColor: AppColors.muted,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.dark,
          foregroundColor: AppColors.accent,
          disabledBackgroundColor: AppColors.surface,
          disabledForegroundColor: AppColors.mutedLight,
          minimumSize: const Size(double.infinity, 54),
          shape: roundedButton,
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.dark,
          minimumSize: const Size(64, 54),
          shape: roundedButton,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.dark,
          minimumSize: const Size(64, 54),
          side: const BorderSide(color: AppColors.dark, width: 1.5),
          shape: roundedButton,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.dark,
          minimumSize: const Size(48, 44),
          textStyle: buttonText.copyWith(fontSize: 14),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.dark, minimumSize: const Size(44, 44)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.dark,
        foregroundColor: AppColors.accent,
        elevation: 4,
        shape: StadiumBorder(),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.card,
        selectedColor: AppColors.dark,
        disabledColor: AppColors.surface,
        labelStyle: const TextStyle(fontFamily: fontFamily, fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text),
        secondaryLabelStyle: const TextStyle(fontFamily: fontFamily, fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        checkmarkColor: AppColors.accent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.accent : Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.dark : const Color(0xFFDADDD5)),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.dark : Colors.transparent),
        checkColor: WidgetStateProperty.all(AppColors.accent),
        side: const BorderSide(color: AppColors.muted, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.dark : AppColors.muted),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.dark,
        linearTrackColor: AppColors.surface,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.dark,
        inactiveTrackColor: AppColors.surface,
        thumbColor: AppColors.dark,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.dark,
        unselectedLabelColor: AppColors.muted,
        indicatorColor: AppColors.dark,
        dividerColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xxxl)),
        titleTextStyle: const TextStyle(
            fontFamily: fontFamily, fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text),
        contentTextStyle: const TextStyle(
            fontFamily: fontFamily, fontSize: 14, height: 1.45, color: AppColors.muted),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.card,
        showDragHandle: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxxl))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.dark,
        contentTextStyle: const TextStyle(fontFamily: fontFamily, color: Colors.white, fontWeight: FontWeight.w600),
        actionTextColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),
      // The calendar's ink-and-white parts (header, chosen day, today when chosen, chosen
      // year) use the app colour with ink text; everything else stays as it is.
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.card,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.accent,
        headerForegroundColor: AppColors.dark,
        todayBorder: const BorderSide(color: AppColors.dark),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.accent : null),
        dayForegroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.dark : null),
        todayBackgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.accent : null),
        todayForegroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.dark : AppColors.text),
        yearBackgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.accent : null),
        yearForegroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.dark : null),
      ),
      // Selected hour / minute / AM-PM: ink box with accent text (like the app's main
      // buttons); the rest grey with ink text, so the choice is always readable.
      timePickerTheme: TimePickerThemeData(
        backgroundColor: AppColors.card,
        helpTextStyle: AppText.label,
        hourMinuteShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        hourMinuteColor: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.dark : AppColors.surface),
        hourMinuteTextColor: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.accent : AppColors.text),
        dayPeriodShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        dayPeriodBorderSide: const BorderSide(color: AppColors.border),
        dayPeriodColor: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.dark : AppColors.card),
        dayPeriodTextColor: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.accent : AppColors.muted),
        dialBackgroundColor: AppColors.surface,
        dialHandColor: AppColors.dark,
        dialTextColor: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.accent : AppColors.text),
        entryModeIconColor: AppColors.dark,
        timeSelectorSeparatorColor: const WidgetStatePropertyAll(AppColors.text),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.dark,
        selectionColor: AppColors.accentSoft,
        selectionHandleColor: AppColors.dark,
      ),
    );
  }

  /// The app runs in light mode; dark returns the same look.
  static ThemeData get darkTheme => lightTheme;
}

/// Text styles used across screens.
class AppText {
  AppText._();

  static const TextStyle hero = TextStyle(fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -1.5, height: 1.05);
  static const TextStyle screenTitle = TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.text);
  static const TextStyle section = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text);
  static const TextStyle label = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.muted);
  static const TextStyle rowTitle = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text);
  static const TextStyle rowSub = TextStyle(fontSize: 12, color: AppColors.muted);
  static const TextStyle amount = TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text);
}
