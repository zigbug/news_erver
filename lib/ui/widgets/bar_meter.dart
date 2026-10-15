import 'package:flutter/material.dart';

import '../../core/theme/retro_theme.dart';
import '../../core/utils/formatters.dart';

/// `CPU ▓▓▓▓▓░░░░░ 042%` meter used on the status screen.
class BarMeter extends StatelessWidget {
  const BarMeter({
    super.key,
    required this.label,
    required this.ratio,
    this.valueLabel,
    this.width = 10,
    this.labelWidth = 64,
  });

  final String label;

  /// 0..1
  final double ratio;

  /// Right-hand value; defaults to a percentage.
  final String? valueLabel;

  final int width;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final percent = (ratio * 100).clamp(0, 100).toDouble();
    final color = percent >= 88
        ? palette.error
        : percent >= 70
        ? palette.warning
        : palette.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label.toUpperCase(),
              style: context.retroStyle(size: 11, color: palette.primaryDim, glow: false),
            ),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                blockBar(ratio, width: width),
                maxLines: 1,
                style: context.retroStyle(size: 14, color: color, letterSpacing: 0),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 62,
            child: Text(
              valueLabel ?? percentOf(percent),
              textAlign: TextAlign.right,
              style: context.retroStyle(size: 12, color: color, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
