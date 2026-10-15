/// Which monospace font the UI renders with.
enum AppFontMode {
  /// VT323: the classic bitmap CRT look. Lacks Cyrillic glyphs, so the
  /// fallback family supplies them per-glyph.
  crt('crt', 'CRT', 'VT323'),

  /// JetBrains Mono: full Cyrillic coverage, coding look.
  mono('mono', 'MONO', 'JetBrainsMono');

  const AppFontMode(this.id, this.label, this.family);

  final String id;
  final String label;
  final String family;

  /// VT323 is drawn on a tall bitmap grid; it needs a larger nominal size than
  /// JetBrains Mono to reach the same visual height.
  double get sizeScale => this == AppFontMode.crt ? 1.3 : 1.0;

  static AppFontMode byId(String? id) =>
      values.firstWhere((m) => m.id == id, orElse: () => AppFontMode.crt);
}

/// Font helpers shared by the theme and ad-hoc text styles.
abstract final class AppFonts {
  /// Kept as a literal so it can be used in const contexts. Matches
  /// [AppFontMode.mono]'s family.
  static const String fallbackFamily = 'JetBrainsMono';

  /// Family list passed to Flutter. The primary family is listed first so it
  /// wins for every glyph it contains; the fallback covers the rest.
  static List<String> families(AppFontMode mode) => [
    mode.family,
    if (mode != AppFontMode.mono) fallbackFamily,
  ];

  static String? fontFamily(AppFontMode mode) => mode.family;
}
