import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/retro_theme.dart';
import '../../core/utils/formatters.dart';
import '../../features/control/control_cubit.dart';
import '../../features/control/control_state.dart';
import '../../features/status/status_cubit.dart';
import '../widgets/glow_text.dart';
import '../widgets/retro_button.dart';
import '../widgets/terminal_panel.dart';

/// Panel of operations against the remote server, with confirmation for the
/// destructive ones.
class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  String _service = 'node-agent';

  Future<bool> _confirm(ControlAction action) async {
    final palette = context.palette;
    final result = await showDialog<bool>(
      context: context,
      barrierColor: palette.background.withValues(alpha: 0.85),
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: palette.error, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: GlowText(
                'confirm ${action.label.toLowerCase()}',
                size: 15,
                weight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlowText(
              action == ControlAction.restartService
                  ? 'юнит «$_service» будет перезапущен. сессии на нём оборвутся.'
                  : 'сервер перезагрузится. все активные сессии будут разорваны.',
              size: 12.5,
              color: palette.primaryDim,
              glow: false,
            ),
            const SizedBox(height: 14),
            const RetroRule(),
            const SizedBox(height: 10),
            GlowText('are you sure?  [Y/N]', size: 12, color: palette.warning),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          RetroButton(
            label: 'N · cancel',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          RetroButton(
            label: 'Y · do it',
            destructive: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _run(ControlAction action, {bool needsConfirm = false}) async {
    final cubit = context.read<ControlCubit>();
    if (needsConfirm && !await _confirm(action)) return;
    if (!mounted) return;
    await cubit.run(
      action,
      service: action == ControlAction.restartService ? _service : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final services = context.watch<StatusCubit>().state.status?.services ?? const [];

    return BlocBuilder<ControlCubit, ControlState>(
      builder: (context, state) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: palette.error.withValues(alpha: 0.08),
                  border: Border.all(color: palette.error.withValues(alpha: 0.6)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: palette.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'DESTRUCTIVE OPS: reboot требует подтверждения. демо-режим, команды только имитируются.',
                        style: context.retroStyle(size: 11, color: palette.error, glow: false),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TerminalPanel(
                title: 'link',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: RetroButton(
                            label: 'connect',
                            icon: Icons.link,
                            busy: state.isBusy(ControlAction.connect),
                            onPressed: state.busy == null
                                ? () => _run(ControlAction.connect)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RetroButton(
                            label: 'reconnect',
                            icon: Icons.refresh,
                            busy: state.isBusy(ControlAction.reconnect),
                            onPressed: state.busy == null
                                ? () => _run(ControlAction.reconnect)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RetroButton(
                            label: 'disconnect',
                            icon: Icons.link_off,
                            busy: state.isBusy(ControlAction.disconnect),
                            onPressed: state.busy == null
                                ? () => _run(ControlAction.disconnect)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TerminalPanel(
                title: 'maintenance',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'target unit',
                      style: context.retroStyle(size: 11, color: palette.primaryDim, glow: false),
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final service in services) ...[
                            _UnitChip(
                              name: service.name,
                              selected: service.name == _service,
                              onTap: () => setState(() => _service = service.name),
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: RetroButton(
                            label: 'restart service',
                            icon: Icons.autorenew,
                            subtitle: _service,
                            busy: state.isBusy(ControlAction.restartService),
                            onPressed: state.busy == null
                                ? () => _run(ControlAction.restartService, needsConfirm: true)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RetroButton(
                            label: 'clear cache',
                            icon: Icons.cleaning_services_outlined,
                            busy: state.isBusy(ControlAction.clearCache),
                            onPressed: state.busy == null
                                ? () => _run(ControlAction.clearCache)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TerminalPanel(
                title: 'power',
                accent: true,
                child: RetroButton(
                  label: 'reboot server',
                  icon: Icons.power_settings_new,
                  destructive: true,
                  expand: true,
                  busy: state.isBusy(ControlAction.reboot),
                  onPressed: state.busy == null
                      ? () => _run(ControlAction.reboot, needsConfirm: true)
                      : null,
                ),
              ),
              const SizedBox(height: 10),
              TerminalPanel(
                title: 'operation log',
                trailing: Text(
                  '${state.results.length} records',
                  style: context.retroStyle(size: 10, color: palette.primaryDim, glow: false),
                ),
                child: state.results.isEmpty
                    ? Text(
                        '— пусто —',
                        style: context.retroStyle(size: 12, color: palette.primaryDim, glow: false),
                      )
                    : Column(
                        children: [
                          for (final result in state.results) _ResultRow(result: result),
                        ],
                      ),
              ),
              if (state.lastError != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: palette.error),
                    color: palette.error.withValues(alpha: 0.1),
                  ),
                  child: GlowText('ERR  ${state.lastError}', size: 11, color: palette.error),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _UnitChip extends StatelessWidget {
  const _UnitChip({required this.name, required this.selected, required this.onTap});

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = selected ? palette.accent : palette.primaryDim;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
        ),
        child: Text(
          name,
          style: context.retroStyle(
            size: 11,
            weight: selected ? FontWeight.w700 : FontWeight.w400,
            color: color,
            glow: selected,
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result});

  final ActionResult result;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = result.ok ? palette.success : palette.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              result.ok ? 'OK' : 'FAIL',
              style: context.retroStyle(size: 11, weight: FontWeight.w700, color: color, glow: false),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              clockOf(result.at),
              style: context.retroStyle(size: 11, color: palette.primaryDim, glow: false),
            ),
          ),
          Expanded(
            child: Text(
              '${result.action.label} · ${result.detail}',
              style: context.retroStyle(size: 12),
            ),
          ),
        ],
      ),
    );
  }
}
