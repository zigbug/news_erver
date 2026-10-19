import 'package:flutter/material.dart';

import '../../core/theme/retro_theme.dart';

/// Classic terminal spinner: a stick rotating through | / - \ while the
/// agent's answer is assembled from chunks and we wait for the next one.
class RetroSpinner extends StatefulWidget {
  const RetroSpinner({
    super.key,
    this.glyphs = const ['|', '/', '-', r'\'],
    this.period = const Duration(milliseconds: 400),
  });

  final List<String> glyphs;
  final Duration period;

  @override
  State<RetroSpinner> createState() => _RetroSpinnerState();
}

class _RetroSpinnerState extends State<RetroSpinner>
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
        final index =
            (_controller.value * widget.glyphs.length).floor() %
            widget.glyphs.length;
        return SizedBox(
          width: 10,
          child: Text(
            widget.glyphs[index],
            style: context.retroStyle(
              size: 13,
              color: context.palette.accent,
              letterSpacing: 0,
            ),
          ),
        );
      },
    );
  }
}
