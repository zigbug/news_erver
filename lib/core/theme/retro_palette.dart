import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Immutable description of a retro screen palette.
///
/// A palette owns every colour the UI is allowed to use. Widgets must read
/// colours from [Theme] / [RetroTheme] instead of hardcoding values, so that
/// switching the palette repaints the whole app.
class RetroPalette extends Equatable {
  const RetroPalette({
    required this.id,
    required this.name,
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.primary,
    required this.primaryDim,
    required this.accent,
    required this.success,
    required this.warning,
    required this.error,
    this.glowStrength = 0.7,
    this.scanlineOpacity = 0.14,
  });

  /// Stable identifier persisted in settings.
  final String id;

  /// Human readable name shown in the settings screen.
  final String name;

  final Brightness brightness;

  /// Screen background ("the glass").
  final Color background;

  /// Panel fill sitting on top of [background].
  final Color surface;

  /// Slightly different fill used for headers / alternating rows.
  final Color surfaceAlt;

  /// Frame and separator colour.
  final Color border;

  /// Main phosphor colour: text, focus, selection.
  final Color primary;

  /// Dimmed variant of [primary] for hints and secondary text.
  final Color primaryDim;

  /// Complementary highlight colour (cursor, active markers, accents).
  final Color accent;

  final Color success;
  final Color warning;
  final Color error;

  /// 0..1 multiplier for text glow intensity.
  final double glowStrength;

  /// Opacity of the CRT scanline overlay.
  final double scanlineOpacity;

  bool get isDark => brightness == Brightness.dark;

  @override
  List<Object?> get props => [id];
}
