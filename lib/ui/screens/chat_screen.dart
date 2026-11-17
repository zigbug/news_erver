import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/chat_message.dart';
import '../../core/theme/retro_theme.dart';
import '../../data/repositories/chat_repository.dart';
import '../../features/chat/chat_bloc.dart';
import '../../features/chat/chat_event.dart';
import '../../features/chat/chat_state.dart';
import '../widgets/blinking_cursor.dart';
import '../widgets/glow_text.dart';
import '../widgets/retro_prompt_field.dart';
import '../widgets/retro_spinner.dart';
import '../widgets/terminal_panel.dart';

/// Terminal-style chat with the server bot.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  /// Scrolls to the newest line, but only when the transcript is already
  /// near the bottom — during an SSE stream events arrive several times a
  /// second and must not yank the view away from a message the operator
  /// scrolled up to read.
  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      final nearBottom = position.maxScrollExtent - position.pixels < 120;
      if (!force && !nearBottom) return;
      _scroll.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: BlocConsumer<ChatBloc, ChatState>(
              listenWhen: (a, b) => a != b,
              listener: (_, _) => _scrollToBottom(),
              builder: (context, state) {
                final status = state.busy
                    ? (state.queuedCount > 0
                        ? 'busy · queued ${state.queuedCount}'
                        : 'busy')
                    : (state.queuedCount > 0
                        ? 'queued ${state.queuedCount}'
                        : 'ready');
                return TerminalPanel(
                  title: 'opencode · agent session',
                  expand: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  trailing: Text(
                    status,
                    style: context.retroStyle(
                      size: 10,
                      color: state.busy ? palette.warning : palette.success,
                      glow: false,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ModelSelector(state: state),
                      const SizedBox(height: 4),
                      Expanded(
                        child: ListView.builder(
                          controller: _scroll,
                          itemCount:
                              state.messages.length + (state.thinking ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i >= state.messages.length) {
                              return const _ThinkingRow();
                            }
                            return _MessageRow(state.messages[i]);
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          BlocBuilder<ChatBloc, ChatState>(
            buildWhen: (a, b) => a.suggestions != b.suggestions,
            builder: (context, state) {
              if (state.suggestions.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final suggestion in state.suggestions)
                      _SuggestionChip(
                        text: suggestion,
                        onTap: () {
                          context.read<ChatBloc>().add(
                                ChatPromptSent(suggestion),
                              );
                          _scrollToBottom();
                        },
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          BlocBuilder<ChatBloc, ChatState>(
            buildWhen: (a, b) =>
                a.busy != b.busy || a.queuedCount != b.queuedCount,
            builder: (context, state) => RetroPromptField(
              controller: _input,
              accent: true,
              busy: state.busy,
              allowSendWhileBusy: true,
              actionLabel: state.busy ? 'queue' : 'send',
              hint: state.busy
                  ? 'дополните задачу или отправьте следом…'
                  : 'спросите агента…',
              onStop: () => context.read<ChatBloc>().add(const ChatStopped()),
              onSubmitted: (value) {
                context.read<ChatBloc>().add(ChatPromptSent(value));
                _input.clear();
                _scrollToBottom(force: true);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow(this.message);

  final ChatMessage message;

  bool get _isError =>
      message.role == ChatRole.system && message.text.startsWith('ошибка');

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (message.role) {
      ChatRole.user => palette.accent,
      ChatRole.bot => palette.primary,
      ChatRole.system => _isError ? palette.warning : palette.primaryDim,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 14,
            child: Text(
              message.role.prompt,
              style: context.retroStyle(
                size: 13,
                weight: FontWeight.w700,
                color: color,
                letterSpacing: 0,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              message.role.label,
              style: context.retroStyle(
                size: 10,
                color: palette.primaryDim,
                glow: false,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Expanded(
            child: message.role == ChatRole.system
                ? Text(
                    message.text,
                    style: context.retroStyle(
                      size: _isError ? 12 : 11,
                      weight: _isError ? FontWeight.w600 : FontWeight.w400,
                      color: color,
                      glow: false,
                      fontStyle: _isError ? null : FontStyle.italic,
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: GlowText(
                          message.text,
                          size: 13,
                          color: color,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (message.pending) ...[
                        const SizedBox(width: 2),
                        const RetroSpinner(),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingRow extends StatelessWidget {
  const _ThinkingRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const SizedBox(width: 14, child: BlinkingCursor(glyph: '·')),
          GlowText(
            'agent is thinking',
            size: 11,
            color: context.palette.primaryDim,
            glow: false,
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(
            color: enabled
                ? palette.border
                : palette.border.withValues(alpha: 0.4),
          ),
          color: palette.surfaceAlt,
        ),
        child: Text(
          text,
          style: context.retroStyle(
            size: 11,
            color: enabled ? palette.primary : palette.primaryDim,
            glow: false,
          ),
        ),
      ),
    );
  }
}

class _ModelSelector extends StatelessWidget {
  const _ModelSelector({required this.state});

  final ChatState state;

  String _label(ChatState state) {
    if (state.selectedModelId.isEmpty) return 'model: auto (backend default)';
    for (final m in state.models) {
      if (m.id == state.selectedModelId) return 'model: ${m.name}';
    }
    return 'model: ${state.selectedModelId}';
  }

  Future<void> _openPicker(BuildContext context) async {
    final palette = context.palette;

    // Group flat model list by provider for drill-down: providers -> models.
    final grouped = <String, List<ChatModelOption>>{};
    for (final m in state.models) {
      grouped.putIfAbsent(m.providerID, () => <ChatModelOption>[]).add(m);
    }
    final providerIds = grouped.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final id in providerIds) {
      grouped[id]!.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        String? providerId; // null = providers list
        return StatefulBuilder(
          builder: (context, setState) {
            final inProvider = providerId != null;
            final title = inProvider ? 'provider: $providerId' : 'select model';

            Widget content;
            if (state.models.isEmpty && !state.modelsLoading) {
              content = Text(
                'список моделей недоступен.\n'
                'будет использована модель по умолчанию на бэкенде.',
                style: context.retroStyle(
                  size: 12,
                  color: palette.primaryDim,
                  glow: false,
                ),
              );
            } else if (!inProvider) {
              content = ListView(
                shrinkWrap: true,
                children: [
                  _ModelOptionTile(
                    title: 'auto (backend default)',
                    subtitle: 'не передавать model в запросе',
                    selected: state.selectedModelId.isEmpty,
                    onTap: () => Navigator.of(dialogContext).pop(''),
                  ),
                  for (final pid in providerIds)
                    _ModelOptionTile(
                      title: pid,
                      subtitle:
                          '${grouped[pid]!.length} models · открыть →',
                      selected: state.selectedModelId.startsWith('$pid/'),
                      onTap: () => setState(() => providerId = pid),
                    ),
                  if (state.modelsLoading)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'loading models…',
                        style: context.retroStyle(
                          size: 11,
                          color: palette.primaryDim,
                          glow: false,
                        ),
                      ),
                    ),
                ],
              );
            } else {
              final models = grouped[providerId] ?? const <ChatModelOption>[];
              content = ListView(
                shrinkWrap: true,
                children: [
                  _ModelOptionTile(
                    title: '← назад к провайдерам',
                    subtitle: 'выбор провайдера',
                    selected: false,
                    onTap: () => setState(() => providerId = null),
                  ),
                  for (final m in models)
                    _ModelOptionTile(
                      title: _modelDisplayName(m),
                      subtitle: m.id,
                      selected: m.id == state.selectedModelId,
                      onTap: () => Navigator.of(dialogContext).pop(m.id),
                    ),
                ],
              );
            }

            return AlertDialog(
              backgroundColor: palette.surface,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              title: GlowText(
                title,
                size: 14,
                weight: FontWeight.w700,
              ),
              content: SizedBox(
                width: 520,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: content,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.primaryDim,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  child: Text(
                    'CLOSE',
                    style: context.retroStyle(
                      size: 11,
                      weight: FontWeight.w700,
                      color: palette.primaryDim,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (selected != null && context.mounted) {
      context.read<ChatBloc>().add(ChatModelSelected(selected));
    }
  }

  static String _modelDisplayName(ChatModelOption m) {
    final name = m.name.trim();
    final prefix = '${m.providerID} / ';
    if (name.toLowerCase().startsWith(prefix.toLowerCase())) {
      final stripped = name.substring(prefix.length).trim();
      if (stripped.isNotEmpty) return stripped;
    }
    return name.isEmpty ? m.modelID : name;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final loading = state.modelsLoading && state.models.isEmpty;
    return InkWell(
      onTap: loading ? null : () => _openPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: palette.border.withValues(alpha: 0.7)),
          color: palette.surfaceAlt,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                loading ? 'model: loading…' : _label(state),
                overflow: TextOverflow.ellipsis,
                style: context.retroStyle(
                  size: 10,
                  color: palette.primary,
                  glow: false,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              loading ? '…' : 'SELECT',
              style: context.retroStyle(
                size: 10,
                weight: FontWeight.w700,
                color: palette.accent,
                glow: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelOptionTile extends StatelessWidget {
  const _ModelOptionTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? palette.accent : palette.border,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? palette.accent.withValues(alpha: 0.08)
              : palette.surfaceAlt,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selected ? '▸' : ' ',
              style: context.retroStyle(
                size: 12,
                weight: FontWeight.w700,
                color: selected ? palette.accent : palette.primaryDim,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.retroStyle(
                      size: 12,
                      weight: FontWeight.w700,
                      color: selected ? palette.accent : palette.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: context.retroStyle(
                      size: 10,
                      color: palette.primaryDim,
                      glow: false,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
