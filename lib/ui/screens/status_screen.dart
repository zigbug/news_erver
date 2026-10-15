import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/server_status.dart';
import '../../core/models/service_info.dart';
import '../../core/theme/retro_theme.dart';
import '../../core/utils/formatters.dart';
import '../../features/status/status_cubit.dart';
import '../widgets/bar_meter.dart';
import '../widgets/blinking_cursor.dart';
import '../widgets/glow_text.dart';
import '../widgets/sparkline.dart';
import '../widgets/status_strip.dart';
import '../widgets/terminal_panel.dart';

/// Telemetry: link, utilisation, services.
class StatusScreen extends StatelessWidget {
  const StatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StatusCubit, StatusState>(
      builder: (context, state) {
        final status = state.status;
        if (status == null) {
          return const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlowText('waiting for telemetry ', size: 13),
                BlinkingCursor(),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(status: status),
              const SizedBox(height: 10),
              TerminalPanel(
                title: 'system',
                child: Column(
                  children: [
                    RetroKeyValue(label: 'host', value: status.hostname),
                    RetroKeyValue(label: 'os', value: status.os),
                    RetroKeyValue(label: 'uptime', value: status.uptimeLabel),
                    RetroKeyValue(
                      label: 'link',
                      value: status.link.label,
                      valueColor: linkColor(context.palette, status.link),
                    ),
                    RetroKeyValue(
                      label: 'load avg',
                      value: status.loadAverage.toStringAsFixed(2),
                    ),
                    RetroKeyValue(
                      label: 'temp',
                      value: '${status.temperature.toStringAsFixed(1)} °C',
                      valueColor: status.temperature > 75 ? context.palette.warning : null,
                    ),
                    RetroKeyValue(
                      label: 'sampled',
                      value: clockOf(status.sampledAt),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TerminalPanel(
                title: 'utilisation',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BarMeter(label: 'cpu', ratio: status.cpuPercent / 100, width: 14),
                    BarMeter(
                      label: 'memory',
                      ratio: status.memoryPercent / 100,
                      width: 14,
                      valueLabel: megabytes(status.memoryUsedMb),
                    ),
                    BarMeter(
                      label: 'disk',
                      ratio: status.diskUsedPercent / 100,
                      width: 14,
                    ),
                    const SizedBox(height: 10),
                    RetroKeyValue(label: 'cpu history', value: 'last ${state.cpuHistory.length} samples'),
                    const SizedBox(height: 6),
                    Sparkline(values: state.cpuHistory),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TerminalPanel(
                title: 'services',
                trailing: Text(
                  '${status.services.where((s) => s.state == ServiceState.running).length}/${status.services.length} up',
                  style: context.retroStyle(size: 10, color: context.palette.primaryDim, glow: false),
                ),
                child: Column(
                  children: [
                    for (final service in status.services) _ServiceRow(service),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.status});

  final ServerStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlowText(
                status.hostname,
                size: 18,
                weight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
              const SizedBox(height: 4),
              GlowText(
                'cpu ${percentOf(status.cpuPercent)}  mem ${percentOf(status.memoryPercent)}  disk ${percentOf(status.diskUsedPercent)}',
                size: 11,
                color: palette.primaryDim,
                glow: false,
              ),
            ],
          ),
          const Spacer(),
          StatusPill(label: status.link.label, color: linkColor(palette, status.link)),
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow(this.service);

  final ServiceInfo service;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (service.state) {
      ServiceState.running => palette.success,
      ServiceState.degraded => palette.warning,
      ServiceState.stopped => palette.error,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 8, height: 8, color: color),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              service.name,
              overflow: TextOverflow.ellipsis,
              style: context.retroStyle(size: 12),
            ),
          ),
          SizedBox(
            width: 76,
            child: Text(
              service.state.label,
              style: context.retroStyle(size: 10, weight: FontWeight.w700, color: color, glow: false, letterSpacing: 0.8),
            ),
          ),
          Expanded(
            child: Text(
              'cpu ${percentOf(service.cpuPercent)}   mem ${megabytes(service.memoryMb)}',
              textAlign: TextAlign.right,
              style: context.retroStyle(size: 11, color: palette.primaryDim, glow: false),
            ),
          ),
        ],
      ),
    );
  }
}
