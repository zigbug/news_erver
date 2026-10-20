import 'package:flutter/material.dart';

import '../../core/theme/retro_theme.dart';

/// > prompt field used by the terminal and the chat screen.
class RetroPromptField extends StatelessWidget {
  const RetroPromptField({
    super.key,
    required this.controller,
    required this.onSubmitted,
    this.hint = 'awaiting input',
    this.enabled = true,
    this.busy = false,
    this.actionLabel = 'RUN',
    this.accent = false,
    this.onStop,
    this.stopLabel = 'stop',
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final String hint;
  final bool enabled;
  final bool busy;
  final String actionLabel;
  final bool accent;

  /// When set, the action button turns into a stop control while [busy].
  final VoidCallback? onStop;
  final String stopLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = accent ? palette.accent : palette.primary;

    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '>',
            style: context.retroStyle(
              size: 15,
              weight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              showCursor: true,
              controller: controller,
              enabled: enabled && !busy,
              textInputAction: TextInputAction.send,
              onSubmitted: (value) {
                if (value.trim().isEmpty) return;
                onSubmitted(value);
              },
              style: context.retroStyle(
                size: 14,
                color: palette.primary,
                letterSpacing: 0.4,
              ),
              cursorColor: color,
              cursorWidth: 8,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: hint,
                hintStyle: context.retroStyle(
                  size: 13,
                  color: palette.primaryDim,
                  glow: false,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: busy
                ? onStop
                : enabled
                ? () {
                    final value = controller.text;
                    if (value.trim().isEmpty) return;
                    onSubmitted(value);
                  }
                : null,
            style: TextButton.styleFrom(
              foregroundColor: busy && onStop != null ? palette.warning : color,
              disabledForegroundColor: palette.primaryDim,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: Text(
              (busy && onStop != null ? stopLabel : actionLabel).toUpperCase(),
              style: context.retroStyle(
                size: 12,
                weight: FontWeight.w700,
                color: busy && onStop != null ? palette.warning : color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
