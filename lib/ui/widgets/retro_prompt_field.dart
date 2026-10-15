import 'package:flutter/material.dart';

import '../../core/theme/retro_theme.dart';
import 'blinking_cursor.dart';

/// `>` prompt field used by the terminal and the chat screen.
class RetroPromptField extends StatelessWidget {
  const RetroPromptField({
    super.key,
    required this.controller,
    required this.onSubmitted,
    this.hint = 'введите команду…',
    this.enabled = true,
    this.busy = false,
    this.actionLabel = 'RUN',
    this.accent = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final String hint;
  final bool enabled;
  final bool busy;
  final String actionLabel;
  final bool accent;

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
          Text('>', style: context.retroStyle(size: 15, weight: FontWeight.w700, color: color)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled && !busy,
              textInputAction: TextInputAction.send,
              onSubmitted: (value) {
                if (value.trim().isEmpty) return;
                onSubmitted(value);
              },
              style: context.retroStyle(size: 14, color: palette.primary, letterSpacing: 0.4),
              cursorColor: palette.accent,
              cursorWidth: 8,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: hint,
                hintStyle: context.retroStyle(size: 13, color: palette.primaryDim, glow: false),
                suffixIcon: busy
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: Center(
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: color,
                            ),
                          ),
                        ),
                      )
                    : const BlinkingCursor(),
                suffixIconConstraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: enabled && !busy
                ? () {
                    final value = controller.text;
                    if (value.trim().isEmpty) return;
                    onSubmitted(value);
                  }
                : null,
            style: TextButton.styleFrom(
              foregroundColor: color,
              disabledForegroundColor: palette.primaryDim,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: Text(
              actionLabel.toUpperCase(),
              style: context.retroStyle(size: 12, weight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
