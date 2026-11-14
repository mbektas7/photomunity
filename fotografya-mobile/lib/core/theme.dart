import 'dart:ui';

import 'package:flutter/material.dart';

/// Web ile aynı token'lar: açık tema galeri duvarı, koyu tema karanlık oda.
class Palette {
  const Palette({
    required this.wall,
    required this.mat,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.accentInk,
    required this.danger,
  });

  final Color wall, mat, ink, muted, line, accent, accentInk, danger;

  static const light = Palette(
    wall: Color(0xFFE6E6E3),
    mat: Color(0xFFFBFBF9),
    ink: Color(0xFF1A1B1E),
    muted: Color(0xFF626368),
    line: Color(0xFFD0D0CC),
    accent: Color(0xFF4A3FCF),
    accentInk: Color(0xFFFFFFFF),
    danger: Color(0xFFB42318),
  );

  static const dark = Palette(
    wall: Color(0xFF121315),
    mat: Color(0xFF1C1D20),
    ink: Color(0xFFECECE8),
    muted: Color(0xFF9A9B9F),
    line: Color(0xFF2E2F33),
    accent: Color(0xFF9C93FF),
    accentInk: Color(0xFF121315),
    danger: Color(0xFFFF8A7A),
  );
}

extension PaletteX on BuildContext {
  Palette get palette => Theme.of(this).brightness == Brightness.dark
      ? Palette.dark
      : Palette.light;
}

const _family = 'SchibstedGrotesk';

/// Değişken yazı tipinde ağırlık, wght ekseniyle verilir.
TextStyle font(
  double size, {
  int weight = 400,
  double? height,
  double? spacing,
  Color? color,
  bool tabular = false,
}) => TextStyle(
  fontFamily: _family,
  fontSize: size,
  height: height,
  letterSpacing: spacing,
  color: color,
  fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
  fontVariations: [FontVariation.weight(weight.toDouble())],
  // Bu yazı tipinin tabularFigures seti daktilo tarzı; düz rakamlar kullanılır (web ile aynı karar)
  fontFeatures: tabular ? const [FontFeature.liningFigures()] : null,
);

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.ink,
    onPrimary: p.mat,
    secondary: p.accent,
    onSecondary: p.accentInk,
    error: p.danger,
    onError: p.mat,
    surface: p.wall,
    onSurface: p.ink,
    surfaceContainer: p.mat,
    surfaceContainerHigh: p.mat,
    surfaceContainerHighest: p.mat,
    outline: p.line,
    outlineVariant: p.line,
  );

  final text = TextTheme(
    displaySmall: font(
      40,
      weight: 700,
      height: 0.98,
      spacing: -1.6,
      color: p.ink,
    ),
    headlineMedium: font(
      30,
      weight: 700,
      height: 1.05,
      spacing: -1.0,
      color: p.ink,
    ),
    headlineSmall: font(
      24,
      weight: 600,
      height: 1.15,
      spacing: -0.5,
      color: p.ink,
    ),
    titleLarge: font(20, weight: 600, spacing: -0.3, color: p.ink),
    titleMedium: font(16, weight: 600, color: p.ink),
    titleSmall: font(14, weight: 600, color: p.ink),
    bodyLarge: font(16, height: 1.5, color: p.ink),
    bodyMedium: font(15, height: 1.45, color: p.ink),
    bodySmall: font(13, height: 1.4, color: p.muted),
    labelLarge: font(15, weight: 600, color: p.ink),
    labelMedium: font(13, weight: 500, color: p.muted),
    labelSmall: font(11, weight: 500, color: p.muted),
  );

  final radius = BorderRadius.circular(10);
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: c, width: w),
  );
  const pill = StadiumBorder();
  const buttonSize = Size(0, 46);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: _family,
    textTheme: text,
    scaffoldBackgroundColor: p.wall,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: p.wall,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: font(21, weight: 700, spacing: -0.7, color: p.ink),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.mat,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: border(p.line),
      enabledBorder: border(p.line),
      focusedBorder: border(p.ink, 1.4),
      errorBorder: border(p.danger),
      focusedErrorBorder: border(p.danger, 1.4),
      labelStyle: font(15, color: p.muted),
      floatingLabelStyle: font(14, weight: 500, color: p.ink),
      helperStyle: font(13, color: p.muted),
      errorStyle: font(13, color: p.danger),
      helperMaxLines: 3,
      errorMaxLines: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.mat,
        disabledBackgroundColor: p.ink.withValues(alpha: 0.35),
        disabledForegroundColor: p.mat,
        minimumSize: buttonSize,
        shape: pill,
        textStyle: font(15, weight: 600),
        padding: const EdgeInsets.symmetric(horizontal: 22),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        backgroundColor: p.mat,
        side: BorderSide(color: p.line),
        minimumSize: buttonSize,
        shape: pill,
        textStyle: font(15, weight: 600),
        padding: const EdgeInsets.symmetric(horizontal: 22),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.ink,
        textStyle: font(15, weight: 600),
        shape: pill,
        minimumSize: const Size(0, 44),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.mat,
      selectedColor: p.ink,
      side: BorderSide(color: p.line),
      shape: const StadiumBorder(),
      labelStyle: font(14, color: p.ink),
      secondaryLabelStyle: font(14, color: p.mat),
      checkmarkColor: p.mat,
      showCheckmark: false,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(p.mat),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.line,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.wall,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => font(
          11,
          weight: 500,
          color: s.contains(WidgetState.selected) ? p.ink : p.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? p.ink : p.muted,
          size: 24,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.mat,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.ink,
      contentTextStyle: font(15, color: p.mat),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.accent,
      linearTrackColor: p.line,
    ),
  );
}
