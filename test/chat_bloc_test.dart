import 'package:flutter_test/flutter_test.dart';
import 'package:news_erver/core/models/chat_message.dart';
import 'package:news_erver/data/repositories/chat_repository.dart';
import 'package:news_erver/features/chat/chat_bloc.dart';
import 'package:news_erver/features/chat/chat_event.dart';

class _FakeChatRepository implements ChatRepository {
  int calls = 0;

  @override
  String get greeting => 'hello operator';

  @override
  List<String> get suggestions => const ['status'];

  @override
  Future<String> reply(String prompt) async {
    calls++;
    return 'answer for $prompt';
  }
}

/// Polls [condition] on the real event loop until it holds or the deadline
/// passes. The typewriter effect runs on timers, so a plain await is not enough.
Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test('greets on start with bot and system messages', () async {
    final bloc = ChatBloc(_FakeChatRepository())..add(const ChatStarted());
    await pumpEventQueue();

    expect(bloc.state.messages.length, 2);
    expect(bloc.state.messages.first.role, ChatRole.bot);
    expect(bloc.state.messages.first.text, 'hello operator');
    expect(bloc.state.suggestions, ['status']);
    await bloc.close();
  });

  test('answers the prompt and settles on the full bot text', () async {
    final repository = _FakeChatRepository();
    final bloc = ChatBloc(repository)..add(const ChatStarted());
    await pumpEventQueue();

    bloc.add(const ChatPromptSent('status'));
    await pumpEventQueue();

    expect(
      bloc.state.messages.any((m) => m.role == ChatRole.user),
      isTrue,
      reason: 'the prompt must appear in the transcript immediately',
    );

    await _waitUntil(
      () => !bloc.state.busy && bloc.state.messages.length >= 4,
    );

    final last = bloc.state.messages.last;
    expect(repository.calls, 1);
    expect(last.role, ChatRole.bot);
    expect(last.text, 'answer for status');
    expect(last.pending, isFalse);
    await bloc.close();
  });

  test('ignores empty prompts', () async {
    final repository = _FakeChatRepository();
    final bloc = ChatBloc(repository)..add(const ChatStarted());
    await pumpEventQueue();

    bloc.add(const ChatPromptSent('   '));
    await pumpEventQueue();

    expect(repository.calls, 0);
    expect(bloc.state.messages.length, 2);
    await bloc.close();
  });
}
