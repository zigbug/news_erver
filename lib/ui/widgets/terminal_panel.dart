import 'package:flutter/material.dart';

import '../../core/theme/retro_theme.dart';

/// Boxed, framed content area — the building block every screen is made of.
class TerminalPanel extends StatelessWidget {
  const TerminalPanel({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(12),
    this.accent = false,
    this.expand = false,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  /// Highlights the header with the accent colour.
  final bool accent;

  /// When true the body takes all remaining height — required for scrollables,
  /// because a [Column] hands its children unbounded main-axis constraints.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final accentColor = accent ? palette.accent : palette.primary;
    final body = Padding(padding: padding, child: child);

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Container(
            color: palette.surfaceAlt,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Text('▚', style: context.retroStyle(size: 14, color: accentColor)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: context.retroStyle(
                      size: 13,
                      weight: FontWeight.w700,
                      color: accentColor,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Container(height: 1, color: palette.border),
          if (expand) Expanded(child: body) else body,
        ],
      ),
    );
  }
}

/// Small key/value line used across the status screen.
class RetroKeyValue extends StatelessWidget {
  const RetroKeyValue({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.glow = true,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              '$label:',
              style: context.retroStyle(size: 12, color: palette.primaryDim, glow: false),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: context.retroStyle(size: 12, color: valueColor, glow: glow),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dotted separator, in the spirit of a text-mode UI.
class RetroRule extends StatelessWidget {
  const RetroRule({super.key, this.dashed = true});

  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Text(
      (dashed ? '· ' * 120 : '─' * 120),
      maxLines: 1,
      overflow: TextOverflow.clip,
      softWrap: false,
      style: context.retroStyle(size: 11, color: palette.border, glow: false),
    );
  }
}
