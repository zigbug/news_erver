import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/push/push_service.dart';
import 'core/theme/retro_theme.dart';
import 'data/api/api_chat_repository.dart';
import 'data/api/api_server_repository.dart';
import 'data/api/hub_api.dart';
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

/// The console talks to the real server_hub only — no demo backend.
class RetroConsoleApp extends StatelessWidget {
  const RetroConsoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SettingsCubit>(
      create: (_) => SettingsCubit()..init(),
      child: const _ConsoleGraph(),
    );
  }
}

/// Wires the hub client and repositories once, then builds the bloc graph
/// against them. The [HubApi] reads its base URL/key from [SettingsCubit] on
/// every request, so editing the connection in SETUP needs no rewiring.
class _ConsoleGraph extends StatelessWidget {
  const _ConsoleGraph();

  @override
  Widget build(BuildContext context) {
    final settings = context.read<SettingsCubit>();
    return RepositoryProvider<HubApi>(
      create: (_) =>
          HubApi(connection: () => settings.state.settings.connection),
      dispose: (api) => api.close(),
      child: RepositoryProvider<ApiServerRepository>(
        create: (context) => ApiServerRepository(context.read<HubApi>()),
        dispose: (repository) => repository.dispose(),
        child: RepositoryProvider<PushService>(
          create: (context) =>
              PushService(context.read<ApiServerRepository>())..start(),
          dispose: (push) => push.dispose(),
          child: RepositoryProvider<ApiChatRepository>(
            create: (context) => ApiChatRepository(
              context.read<HubApi>(),
              context.read<ApiServerRepository>(),
            ),
            child: MultiBlocProvider(
              providers: [
                BlocProvider(
                  create: (context) =>
                      StatusCubit(context.read<ApiServerRepository>())..start(),
                ),
                BlocProvider(
                  create: (context) =>
                      TerminalBloc(context.read<ApiServerRepository>())
                        ..add(const TerminalStarted()),
                ),
                BlocProvider(
                  create: (context) =>
                      ChatBloc(context.read<ApiChatRepository>())
                        ..add(const ChatStarted()),
                ),
                BlocProvider(
                  create: (context) =>
                      ControlCubit(context.read<ApiServerRepository>()),
                ),
              ],
              child: const _ConfiguredApp(),
            ),
          ),
        ),
      ),
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
