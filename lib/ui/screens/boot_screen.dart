import 'package:flutter/material.dart';
import '../../core/theme/retro_theme.dart';

class BootScreen extends StatelessWidget {
  const BootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/splash_icon_256.png',
              width: 128,
              height: 128,
              filterQuality: FilterQuality.high,
            ),
            const SizedBox(height: 24),
            Text(
              'REMOTE CONSOLE',
              style: context.retroStyle(
                size: 22,
                weight: FontWeight.w700,
                letterSpacing: 3,
                color: palette.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'booting...',
              style: context.retroStyle(
                size: 12,
                color: palette.primaryDim,
                glow: false,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
