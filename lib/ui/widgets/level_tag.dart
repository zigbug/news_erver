import 'package:flutter/material.dart';

import '../../core/models/log_entry.dart';
import '../../core/theme/retro_palette.dart';
import '../../core/theme/retro_theme.dart';

/// Palette colour for a log severity.
Color logLevelColor(RetroPalette palette, LogLevel level) => switch (level) {
  LogLevel.trace => palette.primaryDim,
  LogLevel.debug => palette.primaryDim,
  LogLevel.info => palette.primary,
  LogLevel.warn => palette.warning,
  LogLevel.error => palette.error,
};

/// Fixed-width severity tag so log columns stay aligned.
class LevelTag extends StatelessWidget {
  const LevelTag(this.level, {super.key});

  final LogLevel level;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      child: Text(
        level.label,
        style: context.retroStyle(
          size: 12,
          weight: logLevelColor(context.palette, level) == context.palette.primary
              ? FontWeight.w400
              : FontWeight.w700,
          color: logLevelColor(context.palette, level),
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
