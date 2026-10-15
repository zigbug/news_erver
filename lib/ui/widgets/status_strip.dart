import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/server_status.dart';
import '../../core/theme/retro_palette.dart';
import '../../core/theme/retro_theme.dart';
import '../../core/utils/formatters.dart';
import '../../features/status/status_cubit.dart';

Color linkColor(RetroPalette palette, LinkState link) => switch (link) {
  LinkState.online => palette.success,
  LinkState.degraded => palette.warning,
  LinkState.connecting => palette.accent,
  LinkState.offline => palette.error,
};

/// Boxed status label, e.g. `[ ONLINE ]`.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.blink = false});

  final String label;
  final Color color;
  final bool blink;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        label.toUpperCase(),
        style: context.retroStyle(
          size: 11,
          weight: FontWeight.w700,
          color: color,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Always-visible strip showing link state, host and a running clock.
class StatusStrip extends StatelessWidget {
  const StatusStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return BlocBuilder<StatusCubit, StatusState>(
      builder: (context, state) {
        final status = state.status;
        final link = status?.link ?? LinkState.offline;
        return Container(
          color: palette.surfaceAlt,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Text(
                '▌',
                style: context.retroStyle(size: 14, color: palette.primary, letterSpacing: 0),
              ),
              const SizedBox(width: 6),
              Text(
                status?.hostname.split('.').first ?? 'srv-01',
                style: context.retroStyle(size: 13, weight: FontWeight.w700, letterSpacing: 1.2),
              ),
              const SizedBox(width: 10),
              StatusPill(label: link.label, color: linkColor(palette, link)),
              const Spacer(),
              if (status != null)
                Text(
                  'up ${status.uptimeLabel}',
                  style: context.retroStyle(size: 11, color: palette.primaryDim, glow: false),
                ),
              const SizedBox(width: 12),
              const _Clock(),
            ],
          ),
        );
      },
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      clockOf(_now),
      style: context.retroStyle(size: 12, color: context.palette.accent),
    );
  }
}
