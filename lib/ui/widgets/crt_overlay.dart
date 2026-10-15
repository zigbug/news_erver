import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/retro_theme.dart';

/// Draws the CRT scanline pattern over the whole app.
class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter({required this.color, required this.opacity});

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 3.0;
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    for (double y = 0; y < size.height; y += step) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) =>
      old.color != color || old.opacity != opacity;
}

/// Adds a soft darkening towards the edges, like a tube with a curved front.
class _VignettePainter extends CustomPainter {
  const _VignettePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = RadialGradient(
        radius: 0.9,
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.35),
        ],
        stops: const [0.6, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_VignettePainter old) => old.color != color;
}

/// Slow, low-amplitude brightness wobble of the whole screen.
class _FlickerLayer extends StatefulWidget {
  const _FlickerLayer({required this.color});

  final Color color;

  @override
  State<_FlickerLayer> createState() => _FlickerLayerState();
}

class _FlickerLayerState extends State<_FlickerLayer>
    with SingleTickerProviderStateMixin {
  static const double _amount = 0.05;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value * 2 * math.pi;
          final wobble = (math.sin(t) + math.sin(t * 2.7 + 1.3)) / 4 + 0.5;
          return ColoredBox(
            color: widget.color.withValues(alpha: _amount * wobble),
          );
        },
      ),
    );
  }
}

/// Wraps app content with the CRT treatment: scanlines, vignette and flicker.
/// Every layer is optional and driven by the active [RetroTheme].
class CrtOverlay extends StatelessWidget {
  const CrtOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final retro = context.retro;
    final palette = retro.palette;
    final showScanlines = retro.scanlines && palette.scanlineOpacity > 0;
    final showFlicker = retro.flicker;
    final showVignette = palette.isDark;

    if (!showScanlines && !showFlicker && !showVignette) return child;

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (showScanlines)
          IgnorePointer(
            child: CustomPaint(
              painter: _ScanlinePainter(
                color: palette.isDark
                    ? const Color(0xFF000000)
                    : palette.primary,
                opacity: palette.scanlineOpacity,
              ),
            ),
          ),
        if (showFlicker)
          Positioned.fill(
            child: _FlickerLayer(color: palette.isDark ? Colors.black : Colors.white),
          ),
        if (showVignette)
          IgnorePointer(
            child: CustomPaint(painter: _VignettePainter(color: Colors.black)),
          ),
      ],
    );
  }
}
