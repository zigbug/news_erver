import 'package:flutter/material.dart';

import '../../core/theme/retro_theme.dart';

/// Minimal line chart for the rolling CPU history.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.height = 48,
    this.maxValue = 100,
  });

  /// Samples in 0..[maxValue], oldest first.
  final List<double> values;
  final double height;
  final double maxValue;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          line: palette.primary,
          grid: palette.border,
          fill: palette.primary.withValues(alpha: 0.12),
          maxValue: maxValue,
          glow: context.retro.glowActive,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.values,
    required this.line,
    required this.grid,
    required this.fill,
    required this.maxValue,
    required this.glow,
  });

  final List<double> values;
  final Color line;
  final Color grid;
  final Color fill;
  final double maxValue;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (values.length < 2) return;

    final dx = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = dx * i;
      final y = size.height - (values[i].clamp(0, maxValue) / maxValue) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = fill);

    final linePaint = Paint()
      ..color = line
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    if (glow) {
      linePaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.line != line || old.grid != grid;
}
