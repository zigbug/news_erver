import 'package:flutter/material.dart';

import 'app_fonts.dart';
import 'retro_palette.dart';
import 'retro_palettes.dart';
import '../models/app_settings.dart';

/// Theme data plus the retro-specific knobs the widgets need.
///
/// Registered as a [ThemeExtension] so any widget can grab it with
/// `context.retro`. Every colour in the app comes from [palette]; every text
/// style goes through [style] so glow is applied consistently.
class RetroTheme extends ThemeExtension<RetroTheme> {
  const RetroTheme({
    required this.palette,
    required this.fontMode,
    this.glow = true,
    this.scanlines = true,
    this.flicker = true,
    this.textScale = 1.0,
  });

  final RetroPalette palette;
  final AppFontMode fontMode;

  /// Master switches for the CRT effects.
  final bool glow;
  final bool scanlines;
  final bool flicker;

  /// User text size multiplier (1.0 = default).
  final double textScale;

  /// Builds the theme extension from persisted [AppSettings].
  factory RetroTheme.fromSettings(AppSettings settings) => RetroTheme(
    palette: RetroPalettes.byId(settings.paletteId),
    fontMode: AppFontMode.byId(settings.fontModeId),
    glow: settings.glow,
    scanlines: settings.scanlines,
    flicker: settings.flicker,
    textScale: settings.textScale,
  );

  bool get glowActive => glow && palette.glowStrength > 0;

  /// Glow layers for [color]. Strength comes from the palette so light themes
  /// can opt out entirely.
  List<Shadow> glowShadows([Color? color, double? strength]) {
    if (!glowActive) return const [];
    final c = color ?? palette.primary;
    final s = (strength ?? palette.glowStrength).clamp(0.0, 1.0);
    if (s <= 0) return const [];
    return [
      Shadow(color: c.withValues(alpha: 0.55 * s), blurRadius: 2),
      Shadow(color: c.withValues(alpha: 0.30 * s), blurRadius: 6),
      Shadow(color: c.withValues(alpha: 0.16 * s), blurRadius: 14),
    ];
  }

  /// The single entry point for text styling.
  TextStyle style({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
    bool glow = true,
    double letterSpacing = 0.6,
    double? height,
    TextDecoration? decoration,
    FontStyle? fontStyle,
  }) {
    final c = color ?? palette.primary;
    return TextStyle(
      fontFamily: fontMode.family,
      fontFamilyFallback: const [AppFonts.fallbackFamily],
      fontSize: size * textScale * fontMode.sizeScale,
      fontWeight: weight,
      color: c,
      letterSpacing: letterSpacing,
      height: height,
      decoration: decoration,
      fontStyle: fontStyle,
      shadows: glow ? glowShadows(c) : null,
      fontVariations: _weightVariations(weight),
    );
  }

  /// JetBrains Mono ships as a variable font; the axis has to be requested
  /// explicitly for weights other than the default. VT323 has a single weight
  /// and ignores the axis.
  List<FontVariation>? _weightVariations(FontWeight weight) {
    if (fontMode != AppFontMode.mono) return null;
    final wght = switch (weight) {
      FontWeight.w300 => 300.0,
      FontWeight.w400 => 400.0,
      FontWeight.w500 => 500.0,
      FontWeight.w600 => 600.0,
      FontWeight.w700 => 700.0,
      _ => null,
    };
    return wght == null ? null : [FontVariation('wght', wght)];
  }

  TextStyle get label => style(size: 11, weight: FontWeight.w700, letterSpacing: 1.4);
  TextStyle get body => style(size: 14);
  TextStyle get title => style(size: 18, weight: FontWeight.w700, letterSpacing: 1.2);

  @override
  RetroTheme copyWith({
    RetroPalette? palette,
    AppFontMode? fontMode,
    bool? glow,
    bool? scanlines,
    bool? flicker,
    double? textScale,
  }) {
    return RetroTheme(
      palette: palette ?? this.palette,
      fontMode: fontMode ?? this.fontMode,
      glow: glow ?? this.glow,
      scanlines: scanlines ?? this.scanlines,
      flicker: flicker ?? this.flicker,
      textScale: textScale ?? this.textScale,
    );
  }

  @override
  RetroTheme lerp(ThemeExtension<RetroTheme>? other, double t) {
    if (other is! RetroTheme) return this;
    return RetroTheme(
      palette: t < 0.5 ? palette : other.palette,
      fontMode: t < 0.5 ? fontMode : other.fontMode,
      glow: t < 0.5 ? glow : other.glow,
      scanlines: t < 0.5 ? scanlines : other.scanlines,
      flicker: t < 0.5 ? flicker : other.flicker,
      textScale: _lerpDouble(textScale, other.textScale, t),
    );
  }

  /// Builds the [ThemeData] wrapper around this extension.
  static ThemeData themeData(RetroTheme retro) {
    final p = retro.palette;
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.primary,
      onPrimary: p.background,
      secondary: p.accent,
      onSecondary: p.background,
      error: p.error,
      onError: p.background,
      surface: p.surface,
      onSurface: p.primary,
      surfaceContainerHighest: p.surfaceAlt,
      outline: p.border,
    );

    final textTheme = TextTheme(
      displayLarge: retro.style(size: 40, weight: FontWeight.w700),
      displayMedium: retro.style(size: 32, weight: FontWeight.w700),
      displaySmall: retro.style(size: 26, weight: FontWeight.w700),
      headlineMedium: retro.style(size: 22, weight: FontWeight.w700),
      titleLarge: retro.style(size: 18, weight: FontWeight.w700, letterSpacing: 1.2),
      titleMedium: retro.style(size: 16, weight: FontWeight.w700, letterSpacing: 1.0),
      bodyLarge: retro.style(size: 15),
      bodyMedium: retro.style(size: 14),
      bodySmall: retro.style(size: 12, color: p.primaryDim),
      labelLarge: retro.style(size: 13, weight: FontWeight.w700, letterSpacing: 1.4),
      labelSmall: retro.style(size: 10, letterSpacing: 1.2, color: p.primaryDim),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      dividerColor: p.border,
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      hoverColor: p.primary.withValues(alpha: 0.08),
      textTheme: textTheme,
      iconTheme: IconThemeData(color: p.primary, size: 20),
      extensions: [retro],
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.primary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: retro.style(size: 16, weight: FontWeight.w700, letterSpacing: 1.6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: p.surfaceAlt,
        hintStyle: retro.style(size: 13, color: p.primaryDim, glow: false),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: p.accent),
        ),
        border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        titleTextStyle: retro.style(size: 16, weight: FontWeight.w700, letterSpacing: 1.6),
        contentTextStyle: retro.style(size: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceAlt,
        contentTextStyle: retro.style(size: 13, glow: false),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.surfaceAlt,
          border: Border.all(color: p.border),
        ),
        textStyle: retro.style(size: 12, glow: false),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent,
        selectionColor: p.primary.withValues(alpha: 0.28),
        selectionHandleColor: p.accent,
      ),
      listTileTheme: ListTileThemeData(
        textColor: p.primary,
        iconColor: p.primary,
        selectedColor: p.accent,
      ),
    );
  }
}

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

/// Convenience accessor: `context.retro.palette.primary`.
extension RetroThemeX on BuildContext {
  RetroTheme get retro =>
      Theme.of(this).extension<RetroTheme>() ?? fallbackRetroTheme;

  RetroPalette get palette => retro.palette;

  TextStyle retroStyle({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
    bool glow = true,
    double letterSpacing = 0.6,
    double? height,
    TextDecoration? decoration,
    FontStyle? fontStyle,
  }) => retro.style(
    size: size,
    weight: weight,
    color: color,
    glow: glow,
    letterSpacing: letterSpacing,
    height: height,
    decoration: decoration,
    fontStyle: fontStyle,
  );
}

/// Used only if [ThemeData] somehow lost the extension (e.g. in widget tests
/// that build a bare theme).
final RetroTheme fallbackRetroTheme = RetroTheme(
  palette: RetroPalettes.phosphorGreen,
  fontMode: AppFontMode.crt,
);
