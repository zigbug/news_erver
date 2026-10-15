import 'package:flutter/material.dart';

import '../../core/theme/retro_theme.dart';
import '../../core/utils/formatters.dart';

/// Fake POST sequence shown while settings are being restored from disk.
class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen>
    with SingleTickerProviderStateMixin {
  static const List<String> _steps = [
    'crt init ................. ok',
    'palette table ............ ok',
    'font rom ................. ok',
    'settings from disk ....... ok',
    'agent link ............... pending',
  ];

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final visible = (_controller.value * (_steps.length + 1)).floor();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'REMOTE CONSOLE v0.9',
                    style: context.retroStyle(size: 22, weight: FontWeight.w700, letterSpacing: 2.4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '(c) retro systems · demo build · no backend attached',
                    style: context.retroStyle(size: 11, color: palette.primaryDim, glow: false),
                  ),
                  const SizedBox(height: 18),
                  for (var i = 0; i < visible && i < _steps.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        _steps[i],
                        style: context.retroStyle(size: 13, letterSpacing: 0.4),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    '${blockBar(_controller.value, width: 24)} ${percentOf(_controller.value * 100)}',
                    style: context.retroStyle(size: 14, letterSpacing: 0),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'BOOTING▉',
                    style: context.retroStyle(size: 13, color: palette.accent, letterSpacing: 2),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
