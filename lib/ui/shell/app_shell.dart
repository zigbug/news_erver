import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/retro_theme.dart';
import '../../data/repositories/server_repository.dart';
import '../../features/settings/settings_cubit.dart';
import '../screens/chat_screen.dart';
import '../screens/control_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/status_screen.dart';
import '../screens/terminal_log_screen.dart';
import '../widgets/status_strip.dart';

/// Frame around the five tabs: status strip on top, tab bar at the bottom.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const List<(String, IconData)> _tabs = [
    ('TERMINAL', Icons.terminal),
    ('STATUS', Icons.memory),
    ('CHAT', Icons.forum_outlined),
    ('CONTROL', Icons.power_settings_new),
    ('SETUP', Icons.tune),
  ];

  int _index = 0;

  @override
  void initState() {
    super.initState();
    final autoConnect = context.read<SettingsCubit>().state.settings.connection.autoConnect;
    if (autoConnect) {
      // Kick the link up once the first frame is on screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<ServerRepository>().connect();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Column(
          children: [
            const StatusStrip(),
            Container(height: 1, color: palette.border),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: const [
                  TerminalLogScreen(),
                  StatusScreen(),
                  ChatScreen(),
                  ControlScreen(),
                  SettingsScreen(),
                ],
              ),
            ),
            Container(height: 1, color: palette.border),
            _TabBar(
              index: _index,
              tabs: _tabs,
              onSelect: (i) => setState(() => _index = i),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.tabs, required this.onSelect});

  final int index;
  final List<(String, IconData)> tabs;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      color: palette.surfaceAlt,
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: _TabButton(
                label: tabs[i].$1,
                icon: tabs[i].$2,
                active: i == index,
                onTap: () => onSelect(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = active ? palette.accent : palette.primaryDim;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? palette.primary.withValues(alpha: 0.1) : null,
          border: Border(top: BorderSide(color: active ? palette.accent : Colors.transparent)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: context.retroStyle(
                  size: 10,
                  weight: FontWeight.w700,
                  color: color,
                  glow: active,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
