import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:news_erver/core/models/app_settings.dart';
import 'package:news_erver/core/models/chat_message.dart';
import 'package:news_erver/core/theme/retro_theme.dart';
import 'package:news_erver/data/repositories/chat_repository.dart';
import 'package:news_erver/features/chat/chat_bloc.dart';
import 'package:news_erver/features/chat/chat_event.dart';
import 'package:news_erver/ui/screens/chat_screen.dart';

/// Repository whose reply dies after a short delay — the same shape as the
/// 60s busy watchdog firing on the real hub.
class _FailingRepository implements ChatRepository {
  @override
  String get greeting => 'hello operator';

  @override
  List<String> get suggestions => const ['status'];

  @override
  Future<List<ChatMessage>> history() async => const [];

  @override
  Future<void> clear() async {}

  @override
  Future<void> stop() async {}

  @override
  Stream<String> reply(String prompt, {Map<String, String>? model}) async* {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    throw TimeoutException('агент не вышел в busy за 60s');
  }

  @override
  Future<List<ChatModelOption>> availableModels() async => const [];
}

void main() {
  testWidgets('reply failure is shown in chat and clears the busy state', (
    tester,
  ) async {
    final bloc = ChatBloc(_FailingRepository())..add(const ChatStarted());

    await tester.pumpWidget(
      MaterialApp(
        theme: RetroTheme.themeData(
          RetroTheme.fromSettings(const AppSettings()),
        ),
        home: BlocProvider<ChatBloc>.value(
          value: bloc,
          child: const Scaffold(body: ChatScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    bloc.add(const ChatPromptSent('статус'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      bloc.state.busy,
      isFalse,
      reason: 'a failed reply must not leave the input blocked',
    );
    expect(
      find.textContaining('ошибка чата'),
      findsOneWidget,
      reason: 'the operator must see the failure in the transcript',
    );
    expect(find.text('ready'), findsOneWidget);
    expect(find.text('agent is thinking'), findsNothing);
  });
}
