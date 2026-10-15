import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/retro_theme.dart';
import 'data/mock/mock_chat_repository.dart';
import 'data/mock/mock_server_repository.dart';
import 'data/repositories/chat_repository.dart';
import 'data/repositories/server_repository.dart';
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
    return RepositoryProvider<ServerRepository>(
      create: (_) => MockServerRepository(),
      dispose: (repository) => repository.dispose(),
      child: RepositoryProvider<ChatRepository>(
        create: (_) => MockChatRepository(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => SettingsCubit()..init()),
            BlocProvider(
              create: (context) =>
                  StatusCubit(context.read<ServerRepository>())..start(),
            ),
            BlocProvider(
              create: (context) =>
                  TerminalBloc(context.read<ServerRepository>())
                    ..add(const TerminalStarted()),
            ),
            BlocProvider(
              create: (context) => ChatBloc(context.read<ChatRepository>())
                ..add(const ChatStarted()),
            ),
            BlocProvider(
              create: (context) =>
                  ControlCubit(context.read<ServerRepository>()),
            ),
          ],
          child: BlocBuilder<SettingsCubit, SettingsState>(
            builder: (context, settingsState) {
              final retro = RetroTheme.fromSettings(settingsState.settings);
              return MaterialApp(
                title: 'Remote Console',
                debugShowCheckedModeBanner: false,
                theme: RetroTheme.themeData(retro),
                builder: (context, child) => CrtOverlay(child: child ?? const SizedBox.shrink()),
                home: settingsState.restored ? const AppShell() : const BootScreen(),
              );
            },
          ),
        ),
      ),
    );
  }
}
