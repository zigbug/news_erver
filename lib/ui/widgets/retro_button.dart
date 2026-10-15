import 'package:flutter/material.dart';

import '../../core/theme/retro_theme.dart';

/// Text-mode button: `[ LABEL ]`. Destructive variants are outlined in the
/// palette error colour and require an explicit tap.
class RetroButton extends StatefulWidget {
  const RetroButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.destructive = false,
    this.busy = false,
    this.dense = false,
    this.expand = false,
    this.subtitle,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool destructive;
  final bool busy;
  final bool dense;
  final bool expand;
  final String? subtitle;

  @override
  State<RetroButton> createState() => _RetroButtonState();
}

class _RetroButtonState extends State<RetroButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = widget.onPressed != null && !widget.busy;

    final Color base = widget.destructive ? palette.error : palette.primary;
    final Color foreground = enabled ? base : palette.primaryDim;
    final bool active = enabled && (_hovered || _pressed);

    final child = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.busy) ...[
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          ),
          const SizedBox(width: 8),
        ] else if (widget.icon != null) ...[
          Icon(widget.icon, size: widget.dense ? 14 : 16, color: foreground),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '[ ${widget.label.toUpperCase()} ]',
                overflow: TextOverflow.ellipsis,
                style: context.retroStyle(
                  size: widget.dense ? 12 : 14,
                  weight: FontWeight.w700,
                  color: foreground,
                  glow: active,
                  letterSpacing: 1.0,
                ),
              ),
              if (widget.subtitle != null)
                Text(
                  widget.subtitle!,
                  overflow: TextOverflow.ellipsis,
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
    );

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: EdgeInsets.symmetric(
            horizontal: widget.dense ? 10 : 14,
            vertical: widget.dense ? 8 : 12,
          ),
          decoration: BoxDecoration(
            color: active ? base.withValues(alpha: 0.14) : palette.surfaceAlt,
            border: Border.all(color: foreground, width: active ? 1.5 : 1),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: base.withValues(alpha: 0.35),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
