import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/retro_theme.dart';
import 'data/api/adaptive_repositories.dart';
import 'features/chat/chat_bloc.dart';
import 'features/chat/chat_event.dart';
import 'features/control/control_cubit.dart';
import 'features/settings/settings_cubit.dart';
import 'features/settings/settings_state.dart';
import 'features/status/status_cubit.dart';
import 'features/terminal/terminal_bloc.dart';
import 'features/terminal/terminal_event.dart';
import 'ui/screens/boot_screen.dart';
import 'ui/shell/app_shell.dart';
import 'ui/widgets/crt_overlay.dart';

class RetroConsoleApp extends StatelessWidget {
  const RetroConsoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SettingsCubit>(
      create: (_) => SettingsCubit()..init(),
      child: RepositoryProvider<AdaptiveServerRepository>(
        create: (_) => AdaptiveServerRepository(),
        dispose: (repository) => repository.dispose(),
        child: RepositoryProvider<AdaptiveChatRepository>(
          create: (context) {
            final server = context.read<AdaptiveServerRepository>();
            return AdaptiveChatRepository(server, server.api);
          },
          child: BlocListener<SettingsCubit, SettingsState>(
            listenWhen: (a, b) =>
                a.settings.connection != b.settings.connection,
            listener: (context, state) {
              final connection = state.settings.connection;
              unawaited(
                context.read<AdaptiveServerRepository>().configure(connection),
              );
              context.read<AdaptiveChatRepository>().configure(connection);
            },
            child: const _ConsoleGraph(),
          ),
        ),
      ),
    );
  }
}

/// Blocs wired against the adaptive repositories. Built once and kept alive for
/// the whole session, regardless of connection edits.
class _ConsoleGraph extends StatelessWidget {
  const _ConsoleGraph();

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) =>
              StatusCubit(context.read<AdaptiveServerRepository>())..start(),
        ),
        BlocProvider(
          create: (context) =>
              TerminalBloc(context.read<AdaptiveServerRepository>())
                ..add(const TerminalStarted()),
        ),
        BlocProvider(
          create: (context) => ChatBloc(context.read<AdaptiveChatRepository>())
            ..add(const ChatStarted()),
        ),
        BlocProvider(
          create: (context) =>
              ControlCubit(context.read<AdaptiveServerRepository>()),
        ),
      ],
      child: const _ConfiguredApp(),
    );
  }
}

class _ConfiguredApp extends StatelessWidget {
  const _ConfiguredApp();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, settingsState) {
        final retro = RetroTheme.fromSettings(settingsState.settings);
        return MaterialApp(
          title: 'Remote Console',
          debugShowCheckedModeBanner: false,
          theme: RetroTheme.themeData(retro),
          builder: (context, child) =>
              CrtOverlay(child: child ?? const SizedBox.shrink()),
          home: settingsState.restored ? const AppShell() : const BootScreen(),
        );
      },
    );
  }
}
