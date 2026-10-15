import 'package:flutter/material.dart';

import '../../core/theme/retro_theme.dart';

/// Text-mode switch: `SCANLINES ......... [X]`.
class RetroSwitchRow extends StatelessWidget {
  const RetroSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = value ? palette.success : palette.primaryDim;

    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: context.retroStyle(size: 12, color: palette.primary, glow: false),
                  ),
                  if (hint != null)
                    Text(
                      hint!,
                      style: context.retroStyle(size: 10, color: palette.primaryDim, glow: false),
                    ),
                ],
              ),
            ),
            Text(
              '[${value ? 'X' : ' '}]',
              style: context.retroStyle(
                size: 14,
                weight: FontWeight.w700,
                color: color,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
