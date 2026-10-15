import 'package:flutter/material.dart';

import '../../core/theme/retro_theme.dart';

/// Text rendered with the phosphor glow from the active palette.
class GlowText extends StatelessWidget {
  const GlowText(
    this.text, {
    super.key,
    this.size = 14,
    this.weight = FontWeight.w400,
    this.color,
    this.glow = true,
    this.letterSpacing = 0.6,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.textAlign,
    this.height,
  });

  final String text;
  final double size;
  final FontWeight weight;
  final Color? color;
  final bool glow;
  final double letterSpacing;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: context.retroStyle(
        size: size,
        weight: weight,
        color: color,
        glow: glow,
        letterSpacing: letterSpacing,
        height: height,
      ),
    );
  }
}
