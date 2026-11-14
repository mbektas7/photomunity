import 'dart:ui';

import 'package:flutter/material.dart';

/// "Canlı topluluk" tokenları (design/tokens.json). Web ile aynı adlar.
/// Kartlar `bg` üzerinde `surface` ile ayrılır; gölge yalnızca yüzen öğelerde.
class Palette {
  const Palette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.inkMuted,
    required this.inkSubtle,
    required this.line,
    required this.ringIdle,
    required this.accent,
    required this.accentInk,
    required this.accentText,
    required this.accentTint,
    required this.live,
    required this.liveInk,
    required this.danger,
    required this.scrim,
    required this.shadowFloat,
    required this.shadowAccent,
  });

  /// Uygulama zemini.
  final Color bg;

  /// Kart, panel, menü yüzeyi.
  final Color surface;

  /// Kart içindeki ikincil alan: EXIF çipi, ikincil düğme, geri sayım kutusu.
  final Color surface2;

  /// Ana metin ve etkin simgeler.
  final Color ink;

  /// İkincil metin.
  final Color inkMuted;

  /// Yalnızca etkin olmayan simgeler; metin için kullanılmaz.
  final Color inkSubtle;

  /// Dekoratif ayırıcı.
  final Color line;

  /// Yeni içeriği olmayan hikâye halkası.
  final Color ringIdle;

  /// Birincil eylem dolgusu ve üzerindeki metin.
  final Color accent, accentInk;

  /// Mavi metin/bağlantı ve seçili durum zemini.
  final Color accentText, accentTint;

  /// Yalnızca zamanla ilgili canlı durumlar; üzerindeki metin her zaman koyu.
  final Color live, liveInk;

  final Color danger;

  /// Fotoğraf üzerindeki buzlu cam düğmeler.
  final Color scrim;

  final List<BoxShadow> shadowFloat, shadowAccent;

  static const light = Palette(
    bg: Color(0xFFF2F3F6),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF2F3F6),
    ink: Color(0xFF14161B),
    inkMuted: Color(0xFF5D6270),
    inkSubtle: Color(0xFF8A8F9C),
    line: Color(0xFFE3E5EA),
    ringIdle: Color(0xFFC9CCD4),
    accent: Color(0xFF2E5BFF),
    accentInk: Color(0xFFFFFFFF),
    accentText: Color(0xFF2A55F5),
    accentTint: Color(0xFFE8EDFF),
    live: Color(0xFFFF7A1A),
    liveInk: Color(0xFF14161B),
    danger: Color(0xFFD92D20),
    scrim: Color(0xD1FFFFFF),
    shadowFloat: [
      BoxShadow(
        offset: Offset(0, 12),
        blurRadius: 30,
        spreadRadius: -12,
        color: Color(0x4714161B),
      ),
    ],
    shadowAccent: [
      BoxShadow(
        offset: Offset(0, 10),
        blurRadius: 22,
        spreadRadius: -8,
        color: Color(0x992E5BFF),
      ),
    ],
  );

  static const dark = Palette(
    bg: Color(0xFF0F1115),
    surface: Color(0xFF1A1D23),
    surface2: Color(0xFF232730),
    ink: Color(0xFFF3F4F7),
    inkMuted: Color(0xFFA3A8B5),
    inkSubtle: Color(0xFF7C8291),
    line: Color(0xFF2B2F38),
    ringIdle: Color(0xFF3A3F4A),
    accent: Color(0xFF3D63FF),
    accentInk: Color(0xFFFFFFFF),
    accentText: Color(0xFF8CA5FF),
    accentTint: Color(0xFF1F2A4D),
    live: Color(0xFFFF8A33),
    liveInk: Color(0xFF14161B),
    danger: Color(0xFFFF7A6E),
    scrim: Color(0xB80F1115),
    shadowFloat: [
      BoxShadow(
        offset: Offset(0, 12),
        blurRadius: 30,
        spreadRadius: -12,
        color: Color(0x99000000),
      ),
    ],
    shadowAccent: [
      BoxShadow(
        offset: Offset(0, 10),
        blurRadius: 22,
        spreadRadius: -8,
        color: Color(0x8C3D63FF),
      ),
    ],
  );
}

/// Köşe yarıçapları (tokens.json → radius).
abstract final class Radii {
  static const photo = 14.0;
  static const box = 16.0;
  static const card = 22.0;
  static const sheet = 26.0;
  static const pill = 9999.0;
}

/// Boşluklar (tokens.json → spacing).
abstract final class Space {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
}

/// Simge çizgisi: 1.8, etkin durumda 2.1. (lucide_icons_flutter yazı tipi
/// tek kalınlıkta gelir; etkin durum renk ve LucideIcons500 ile ayrılır.)
abstract final class IconStroke {
  static const normal = 1.8;
  static const active = 2.1;
}

extension PaletteX on BuildContext {
  Palette get palette => Theme.of(this).brightness == Brightness.dark
      ? Palette.dark
      : Palette.light;
}

const _family = 'BricolageGrotesque';

/// Değişken yazı tipinde ağırlık wght, optik boyut opsz ekseniyle verilir.
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
  fontVariations: [
    FontVariation.weight(weight.toDouble()),
    FontVariation('opsz', size.clamp(12, 96).toDouble()),
  ],
  fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
);

/// Tipografi stilleri (tokens.json → type).
abstract final class AppText {
  static TextStyle display(Color c) =>
      font(34, weight: 700, height: 36 / 34, spacing: -0.035 * 34, color: c);
  static TextStyle title(Color c) =>
      font(25, weight: 700, height: 30 / 25, spacing: -0.03 * 25, color: c);
  static TextStyle heading(Color c) =>
      font(18, weight: 700, height: 24 / 18, color: c);
  static TextStyle bodyStrong(Color c) =>
      font(15, weight: 600, height: 21 / 15, color: c);
  static TextStyle body(Color c) => font(15, height: 22 / 15, color: c);
  static TextStyle caption(Color c) =>
      font(12.5, weight: 500, height: 16 / 12.5, color: c);
  static TextStyle numeral(Color c) => font(
    30,
    weight: 700,
    height: 1,
    spacing: -0.03 * 30,
    color: c,
    tabular: true,
  );
}

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.accent,
    onPrimary: p.accentInk,
    primaryContainer: p.accentTint,
    onPrimaryContainer: p.accentText,
    secondary: p.accent,
    onSecondary: p.accentInk,
    tertiary: p.live,
    onTertiary: p.liveInk,
    error: p.danger,
    onError: p.surface,
    surface: p.bg,
    onSurface: p.ink,
    onSurfaceVariant: p.inkMuted,
    surfaceContainerLowest: p.surface,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surface,
    surfaceContainerHighest: p.surface2,
    outline: p.ringIdle,
    outlineVariant: p.line,
  );

  final text = TextTheme(
    displaySmall: AppText.display(p.ink),
    headlineMedium: AppText.display(p.ink),
    headlineSmall: AppText.title(p.ink),
    titleLarge: AppText.heading(p.ink),
    titleMedium: font(16, weight: 600, color: p.ink),
    titleSmall: font(14, weight: 600, color: p.ink),
    bodyLarge: font(16, height: 1.45, color: p.ink),
    bodyMedium: AppText.body(p.ink),
    bodySmall: font(13, height: 1.4, color: p.inkMuted),
    labelLarge: AppText.bodyStrong(p.ink),
    labelMedium: AppText.caption(p.inkMuted),
    labelSmall: font(11, weight: 500, color: p.inkMuted),
  );

  final boxRadius = BorderRadius.circular(Radii.box);
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: boxRadius,
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
    scaffoldBackgroundColor: p.bg,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppText.title(p.ink),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
      ),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border(p.ringIdle),
      enabledBorder: border(p.ringIdle),
      focusedBorder: border(p.accent, 1.6),
      errorBorder: border(p.danger),
      focusedErrorBorder: border(p.danger, 1.6),
      labelStyle: font(15, color: p.inkMuted),
      floatingLabelStyle: font(14, weight: 500, color: p.ink),
      hintStyle: font(15, color: p.inkMuted),
      helperStyle: font(13, color: p.inkMuted),
      errorStyle: font(13, color: p.danger),
      helperMaxLines: 3,
      errorMaxLines: 3,
    ),
    // primary: accent dolgu (Takip et, Yükle)
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.accentInk,
        disabledBackgroundColor: p.accent.withValues(alpha: 0.4),
        disabledForegroundColor: p.accentInk,
        minimumSize: buttonSize,
        shape: pill,
        textStyle: font(15, weight: 600),
        padding: const EdgeInsets.symmetric(horizontal: 22),
      ),
    ),
    // outline: listede tekrarlanan eylemler
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.ink, width: 1.5),
        minimumSize: buttonSize,
        shape: pill,
        textStyle: font(15, weight: 600),
        padding: const EdgeInsets.symmetric(horizontal: 22),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accentText,
        textStyle: font(15, weight: 600),
        shape: pill,
        minimumSize: const Size(0, 44),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(44, 44),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.accentTint,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: font(14, weight: 600, color: p.ink),
      secondaryLabelStyle: font(14, weight: 600, color: p.accentText),
      checkmarkColor: p.accentText,
      showCheckmark: false,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.ringIdle,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? p.accentTint : p.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? p.accentText : p.inkMuted,
        ),
        side: const WidgetStatePropertyAll(BorderSide.none),
        textStyle: WidgetStatePropertyAll(font(15, weight: 600)),
        minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: p.ink,
      unselectedLabelColor: p.inkMuted,
      labelStyle: font(16, weight: 700),
      unselectedLabelStyle: font(16, weight: 500),
      indicatorColor: p.ink,
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.label,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: 64,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? p.ink : p.inkSubtle,
          size: 24,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: boxRadius),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.ink,
      contentTextStyle: font(15, color: p.bg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: boxRadius),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.accent,
      linearTrackColor: p.surface2,
    ),
  );
}
