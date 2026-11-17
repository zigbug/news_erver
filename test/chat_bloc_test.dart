import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:news_erver/core/models/chat_message.dart';
import 'package:news_erver/data/repositories/chat_repository.dart';
import 'package:news_erver/features/chat/chat_bloc.dart';
import 'package:news_erver/features/chat/chat_event.dart';

class _FakeChatRepository implements ChatRepository {
  int calls = 0;
  int clears = 0;
  int stops = 0;

  /// Simulated past transcript, as the hub would return it.
  List<ChatMessage> past = const [];

  /// When set, the stream fails with this error after the first chunk.
  Object? failWith;

  /// When set, [reply] stays open until this completes — lets a test stop
  /// mid-generation and assert the UI unblocks.
  Completer<void>? hold;

  /// When true, [reply] yields exactly one chunk then waits forever.
  bool hangAfterFirstChunk = false;

  /// When true, [reply] never yields anything and never completes — an agent
  /// that silently swallowed the prompt.
  bool silent = false;

  @override
  String get greeting => 'hello operator';

  @override
  List<String> get suggestions => const ['status'];

  @override
  Future<List<ChatMessage>> history() async => past;

  @override
  Future<void> clear() async {
    clears++;
    past = const [];
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Stream<String> reply(String prompt, {Map<String, String>? model}) async* {
    calls++;
    if (silent) {
      await (hold ??= Completer<void>()).future;
      return;
    }
    var text = 'answer ';
    yield text;
    if (hangAfterFirstChunk) {
      await (hold ??= Completer<void>()).future;
    }
    if (failWith != null) throw failWith!;
    text += 'for $prompt';
    yield text;
  }

  @override
  Future<List<ChatModelOption>> availableModels() async => const [];
}

/// Polls [condition] on the real event loop until it holds or the deadline
/// passes — the reply arrives through stream events, so a plain await is not
/// enough.
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
  test('greets on start with a bot message', () async {
    final bloc = ChatBloc(_FakeChatRepository())..add(const ChatStarted());
    await pumpEventQueue();

    expect(bloc.state.messages.length, 1);
    expect(bloc.state.messages.first.role, ChatRole.bot);
    expect(bloc.state.messages.first.text, 'hello operator');
    expect(bloc.state.suggestions, ['status']);
    await bloc.close();
  });

  test('replays the stored history after the greeting', () async {
    final repository = _FakeChatRepository()
      ..past = [
        ChatMessage(
          id: 'h1',
          role: ChatRole.user,
          text: 'привет',
          timestamp: DateTime(2026),
        ),
        ChatMessage(
          id: 'h2',
          role: ChatRole.bot,
          text: 'здравствуй',
          timestamp: DateTime(2026),
        ),
      ];
    final bloc = ChatBloc(repository)..add(const ChatStarted());
    await pumpEventQueue();

    expect(bloc.state.messages.length, 3);
    expect(bloc.state.messages[1].text, 'привет');
    expect(bloc.state.messages[2].text, 'здравствуй');
    await bloc.close();
  });

  test('answers the prompt and settles on the full bot text', () async {
    final repository = _FakeChatRepository()..hangAfterFirstChunk = true;
    final bloc = ChatBloc(repository)..add(const ChatStarted());
    await pumpEventQueue();

    bloc.add(const ChatPromptSent('status'));
    await _waitUntil(() => bloc.state.busy && repository.hold != null);

    expect(
      bloc.state.messages.any((m) => m.role == ChatRole.user),
      isTrue,
      reason: 'the prompt must appear in the transcript immediately',
    );
    expect(
      bloc.state.busy,
      isTrue,
      reason: 'the chat stays busy while the reply stream is open',
    );

    repository.hold!.complete();
    await _waitUntil(() => !bloc.state.busy && bloc.state.messages.length >= 3);

    final last = bloc.state.messages.last;
    expect(repository.calls, 1);
    expect(last.role, ChatRole.bot);
    expect(last.text, 'answer for status');
    expect(last.pending, isFalse);
    await bloc.close();
  });

  test('grows the pending bubble while chunks arrive', () async {
    final repository = _FakeChatRepository()..hangAfterFirstChunk = true;
    final bloc = ChatBloc(repository)..add(const ChatStarted());
    await pumpEventQueue();

    bloc.add(const ChatPromptSent('status'));

    await _waitUntil(
      () => bloc.state.messages.length >= 3 && repository.hold != null,
    );
    final first = bloc.state.messages.last;
    expect(first.pending, isTrue);
    expect(first.text, 'answer ', reason: 'first chunk renders immediately');

    repository.hold!.complete();
    await _waitUntil(() => !bloc.state.busy);
    expect(bloc.state.messages.last.text, 'answer for status');
    await bloc.close();
  });

  test('surfaces a stream failure as a system line', () async {
    final repository = _FakeChatRepository()..failWith = StateError('boom');
    final bloc = ChatBloc(repository)..add(const ChatStarted());
    await pumpEventQueue();

    bloc.add(const ChatPromptSent('status'));
    await _waitUntil(
      () =>
          !bloc.state.busy &&
          bloc.state.messages.any(
            (m) => m.role == ChatRole.system && m.text.contains('boom'),
          ),
    );

    expect(bloc.state.busy, isFalse);
    await bloc.close();
  });

  test(
    'first-chunk watchdog unblocks the UI when the agent stays silent',
    () async {
      final repository = _FakeChatRepository()..silent = true;
      final bloc = ChatBloc(
        repository,
        firstChunkTimeout: const Duration(milliseconds: 80),
      )..add(const ChatStarted());
      await pumpEventQueue();

      bloc.add(const ChatPromptSent('status'));
      await _waitUntil(() => bloc.state.busy);

      await _waitUntil(() => !bloc.state.busy);
      final system = bloc.state.messages.where(
        (m) => m.role == ChatRole.system,
      );
      expect(system, isNotEmpty);
      expect(system.last.text, contains('не начал отвечать'));
      expect(
        bloc.state.messages.any((m) => m.pending),
        isFalse,
        reason: 'the spinner must be replaced by the error line',
      );
      expect(repository.stops, 1, reason: 'the stuck server run is aborted');

      // Release the fake stream so the bloc can be closed cleanly.
      repository.hold?.complete();
      await pumpEventQueue();
      await bloc.close();
    },
  );

  test('ignores empty prompts', () async {
    final repository = _FakeChatRepository();
    final bloc = ChatBloc(repository)..add(const ChatStarted());
    await pumpEventQueue();

    bloc.add(const ChatPromptSent('   '));
    await pumpEventQueue();

    expect(repository.calls, 0);
    expect(bloc.state.messages.length, 1);
    await bloc.close();
  });

  test('ChatStopped aborts the run and unblocks the input', () async {
    final repository = _FakeChatRepository()..hangAfterFirstChunk = true;
    final bloc = ChatBloc(repository)..add(const ChatStarted());
    await pumpEventQueue();

    bloc.add(const ChatPromptSent('status'));
    await _waitUntil(() => bloc.state.busy);

    bloc.add(const ChatStopped());
    await _waitUntil(() => !bloc.state.busy);

    expect(repository.stops, 1, reason: 'the hub must be asked to abort');
    expect(bloc.state.busy, isFalse);

    // Let the held stream finish so the bloc can settle cleanly.
    repository.hold?.complete();
    await pumpEventQueue();
    await bloc.close();
  });

  test('ChatStopped with no run is a harmless no-op', () async {
    final repository = _FakeChatRepository();
    final bloc = ChatBloc(repository)..add(const ChatStarted());
    await pumpEventQueue();

    bloc.add(const ChatStopped());
    await pumpEventQueue();

    expect(repository.stops, 1);
    expect(bloc.state.busy, isFalse);
    await bloc.close();
  });
}
