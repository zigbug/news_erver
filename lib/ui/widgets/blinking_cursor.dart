import 'package:flutter/material.dart';

import '../../core/theme/retro_theme.dart';

/// Block cursor that blinks like a real terminal caret.
class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({super.key, this.glyph = '█', this.period = const Duration(milliseconds: 900)});

  final String glyph;
  final Duration period;

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final on = _controller.value < 0.6;
        return Opacity(
          opacity: on ? 1 : 0,
          child: Text(
            widget.glyph,
            style: context.retroStyle(
              size: 14,
              color: context.palette.accent,
              letterSpacing: 0,
            ),
          ),
        );
      },
    );
  }
}
