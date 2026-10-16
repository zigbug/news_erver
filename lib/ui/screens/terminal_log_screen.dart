import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/log_entry.dart';
import '../../core/theme/retro_theme.dart';
import '../../features/terminal/terminal_bloc.dart';
import '../../features/terminal/terminal_event.dart';
import '../../features/terminal/terminal_state.dart';
import '../widgets/glow_text.dart';
import '../widgets/level_tag.dart';
import '../widgets/retro_prompt_field.dart';
import '../widgets/terminal_panel.dart';

/// Main screen: live server log with a command prompt.
class TerminalLogScreen extends StatefulWidget {
  const TerminalLogScreen({super.key});

  @override
  State<TerminalLogScreen> createState() => _TerminalLogScreenState();
}

class _TerminalLogScreenState extends State<TerminalLogScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: BlocBuilder<TerminalBloc, TerminalState>(
        buildWhen: (a, b) => a.mode != b.mode,
        builder: (context, state) {
          final shell = state.mode == TerminalMode.shell;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ModeBar(),
              const SizedBox(height: 8),
              Expanded(
                child: BlocConsumer<TerminalBloc, TerminalState>(
                  listenWhen: (a, b) => a.entries.length != b.entries.length,
                  listener: (_, _) => _scrollToBottom(),
                  builder: (context, state) {
                    final lines = state.visible;
                    return TerminalPanel(
                      title: shell ? 'shell · read-only' : 'live log · tail -f',
                      expand: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      trailing: Text(
                        '${lines.length} lines',
                        style: context.retroStyle(
                          size: 10,
                          color: palette.primaryDim,
                          glow: false,
                        ),
                      ),
                      child: state.loadingHistory && lines.isEmpty
                          ? const _Waiting(text: 'reading log buffer…')
                          : ListView.builder(
                              controller: _scroll,
                              itemCount: lines.length,
                              itemBuilder: (context, i) =>
                                  _LogLineView(lines[i]),
                            ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              if (shell)
                BlocBuilder<TerminalBloc, TerminalState>(
                  buildWhen: (a, b) => a.executing != b.executing,
                  builder: (context, state) => RetroPromptField(
                    controller: _input,
                    busy: state.executing,
                    hint: 'команда… (help)',
                    onSubmitted: (value) {
                      context.read<TerminalBloc>().add(
                        TerminalCommandSubmitted(value),
                      );
                      _input.clear();
                      _scrollToBottom();
                    },
                  ),
                )
              else
                Text(
                  'journal · только чтение. переключитесь в SHELL, чтобы ввести команду.',
                  style: context.retroStyle(
                    size: 10,
                    color: palette.primaryDim,
                    glow: false,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Switches between the read-only server journal and the read-only shell prompt.
class _ModeBar extends StatelessWidget {
  const _ModeBar();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TerminalBloc, TerminalState>(
      buildWhen: (a, b) => a.mode != b.mode,
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (final mode in TerminalMode.values) ...[
                  Expanded(
                    child: _ModeTab(
                      mode: mode,
                      active: state.mode == mode,
                      onTap: () => context.read<TerminalBloc>().add(
                        TerminalModeToggled(mode),
                      ),
                    ),
                  ),
                  if (mode != TerminalMode.values.last)
                    const SizedBox(width: 8),
                ],
              ],
            ),
            if (state.mode == TerminalMode.journal) ...[
              const SizedBox(height: 8),
              const _SourceFilterBar(),
              const SizedBox(height: 6),
              const _LevelFilterBar(),
            ],
          ],
        );
      },
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.mode,
    required this.active,
    required this.onTap,
  });

  final TerminalMode mode;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: active ? palette.accent : palette.border),
          color: active
              ? palette.accent.withValues(alpha: 0.12)
              : Colors.transparent,
        ),
        child: Text(
          mode.label,
          style: context.retroStyle(
            size: 11,
            weight: FontWeight.w700,
            color: active ? palette.accent : palette.primaryDim,
            glow: active,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }
}

class _LogLineView extends StatelessWidget {
  const _LogLineView(this.entry);

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isPrompt = entry.source == 'prompt';
    final dim = context.retroStyle(
      size: 11,
      color: palette.primaryDim,
      glow: false,
      letterSpacing: 0,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 64, child: Text(entry.clock, style: dim)),
          LevelTag(entry.level),
          SizedBox(
            width: 80,
            child: Text(
              entry.source,
              overflow: TextOverflow.ellipsis,
              style: dim.copyWith(
                color: isPrompt ? palette.accent : palette.primaryDim,
              ),
            ),
          ),
          Expanded(
            child: GlowText(
              entry.message,
              size: 12.5,
              letterSpacing: 0.2,
              glow:
                  entry.level == LogLevel.error || entry.level == LogLevel.warn,
              color: isPrompt
                  ? palette.accent
                  : logLevelColor(palette, entry.level),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelFilterBar extends StatelessWidget {
  const _LevelFilterBar();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return BlocBuilder<TerminalBloc, TerminalState>(
      buildWhen: (a, b) => a.hidden != b.hidden,
      builder: (context, state) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text(
                'filter:',
                style: context.retroStyle(
                  size: 11,
                  color: palette.primaryDim,
                  glow: false,
                ),
              ),
              const SizedBox(width: 8),
              for (final level in LogLevel.values) ...[
                _LevelChip(
                  level: level,
                  visible: state.isVisible(level),
                  onTap: () => context.read<TerminalBloc>().add(
                    TerminalLevelToggled(level),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              const SizedBox(width: 4),
              _LevelChip(
                level: LogLevel.info,
                visible: true,
                label: 'CLEAR',
                onTap: () =>
                    context.read<TerminalBloc>().add(const TerminalCleared()),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.level,
    required this.visible,
    required this.onTap,
    this.label,
  });

  final LogLevel level;
  final bool visible;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = visible ? logLevelColor(palette, level) : palette.primaryDim;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: visible ? color : palette.border),
          color: visible ? color.withValues(alpha: 0.12) : Colors.transparent,
        ),
        child: Text(
          label ?? level.label,
          style: context.retroStyle(
            size: 10,
            weight: FontWeight.w700,
            color: color,
            glow: false,
            letterSpacing: 1.0,
            decoration: visible ? null : TextDecoration.lineThrough,
          ),
        ),
      ),
    );
  }
}

/// Horizontal chip bar selecting which log sources feed the merged journal.
class _SourceFilterBar extends StatelessWidget {
  const _SourceFilterBar();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return BlocBuilder<TerminalBloc, TerminalState>(
      buildWhen: (a, b) =>
          a.availableSources != b.availableSources ||
          a.selectedSources != b.selectedSources,
      builder: (context, state) {
        if (state.availableSources.isEmpty) return const SizedBox.shrink();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text(
                'sources:',
                style: context.retroStyle(
                  size: 11,
                  color: palette.primaryDim,
                  glow: false,
                ),
              ),
              const SizedBox(width: 8),
              _SourceChip(
                label: 'ALL',
                active: state.allSourcesSelected,
                onTap: () => context.read<TerminalBloc>().add(
                  const TerminalAllSourcesSelected(),
                ),
              ),
              const SizedBox(width: 6),
              for (final source in state.availableSources) ...[
                _SourceChip(
                  label: source,
                  active: state.isSourceSelected(source),
                  onTap: () => context.read<TerminalBloc>().add(
                    TerminalSourceToggled(source),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = active ? palette.accent : palette.primaryDim;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: active ? color : palette.border),
          color: active ? color.withValues(alpha: 0.12) : Colors.transparent,
        ),
        child: Text(
          label,
          style: context.retroStyle(
            size: 10,
            weight: FontWeight.w700,
            color: color,
            glow: false,
            letterSpacing: 1.0,
            decoration: active ? null : TextDecoration.lineThrough,
          ),
        ),
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlowText(text, size: 12, color: context.palette.primaryDim),
    );
  }
}
