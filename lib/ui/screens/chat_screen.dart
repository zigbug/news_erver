import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/chat_message.dart';
import '../../core/theme/retro_theme.dart';
import '../../features/chat/chat_bloc.dart';
import '../../features/chat/chat_event.dart';
import '../../features/chat/chat_state.dart';
import '../widgets/blinking_cursor.dart';
import '../widgets/glow_text.dart';
import '../widgets/retro_prompt_field.dart';
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
                return TerminalPanel(
                  title: 'opencode · agent session',
                  expand: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  trailing: Text(
                    state.busy ? 'busy' : 'ready',
                    style: context.retroStyle(
                      size: 10,
                      color: state.busy ? palette.warning : palette.success,
                      glow: false,
                    ),
                  ),
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: state.messages.length + (state.thinking ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= state.messages.length) {
                        return const _ThinkingRow();
                      }
                      return _MessageRow(state.messages[i]);
                    },
                  ),
                );
              },
            ),
          ),
          BlocBuilder<ChatBloc, ChatState>(
            buildWhen: (a, b) =>
                a.suggestions != b.suggestions ||
                a.messages.length != b.messages.length,
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
                        onTap: state.busy
                            ? null
                            : () {
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
            buildWhen: (a, b) => a.busy != b.busy,
            builder: (context, state) => RetroPromptField(
              controller: _input,
              accent: true,
              busy: state.busy,
              actionLabel: 'send',
              hint: 'спросите агента…',
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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = switch (message.role) {
      ChatRole.user => palette.accent,
      ChatRole.bot => palette.primary,
      ChatRole.system => palette.primaryDim,
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
                      size: 11,
                      color: palette.primaryDim,
                      glow: false,
                      fontStyle: FontStyle.italic,
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
                        const BlinkingCursor(glyph: '▌'),
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
