import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:news_erver/core/models/app_settings.dart';
import 'package:news_erver/core/models/chat_message.dart';
import 'package:news_erver/data/api/hub_api.dart';
import 'package:news_erver/data/api/opencode_chat_repository.dart';
import 'package:news_erver/features/chat/chat_bloc.dart';
import 'package:news_erver/features/chat/chat_event.dart';

/// Hub that attaches the event stream and accepts the prompt, but never
/// reports that the agent went busy — the failure mode behind the 60s
/// "агент не вышел в busy" watchdog.
class _SilentHubApi extends HubApi {
  _SilentHubApi()
    : super(
        connection: () =>
            const ConnectionSettings(apiBaseUrl: 'http://hub.test'),
      );

  final events = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Future<List<dynamic>> getList(
    String path, {
    Map<String, String>? query,
    bool quiet = false,
  }) async {
    if (path == '/chat/session') {
      return [
        {
          'id': 's1',
          'title': 'hub-chat',
          'time': {'created': 1, 'updated': 1},
        },
      ];
    }
    return const [];
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Duration? timeout,
  }) async => const {};

  @override
  Stream<Map<String, dynamic>> stream(
    String path, {
    Duration attachTimeout = const Duration(seconds: 15),
    void Function()? onOpen,
  }) async* {
    onOpen?.call();
    yield* events.stream;
  }
}

/// Hub whose SSE link dies immediately after the prompt goes out.
class _BrokenStreamHubApi extends _SilentHubApi {
  @override
  Stream<Map<String, dynamic>> stream(
    String path, {
    Duration attachTimeout = const Duration(seconds: 15),
    void Function()? onOpen,
  }) async* {
    onOpen?.call();
    throw const HubApiException(null, 'поток событий оборван');
  }
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test(
    'watchdog failure reaches the chat transcript and clears busy',
    () async {
      final api = _SilentHubApi();
      final repository = OpencodeChatRepository(
        api,
        busyTimeout: const Duration(milliseconds: 150),
      );
      addTearDown(api.events.close);
      addTearDown(api.close);

      final bloc = ChatBloc(repository)..add(const ChatStarted());
      addTearDown(bloc.close);
      await pumpEventQueue();

      bloc.add(const ChatPromptSent('статус'));
      await _waitUntil(() => bloc.state.busy);

      await _waitUntil(() => !bloc.state.busy);

      final system = bloc.state.messages.where(
        (m) => m.role == ChatRole.system,
      );
      expect(system, isNotEmpty, reason: 'the failure must be visible in chat');
      expect(system.last.text, contains('busy'));
      expect(
        bloc.state.messages.any((m) => m.pending),
        isFalse,
        reason: 'no spinner may be left behind',
      );
    },
  );

  test('broken SSE link reaches the chat transcript', () async {
    final api = _BrokenStreamHubApi();
    final repository = OpencodeChatRepository(api);
    addTearDown(api.events.close);

    final bloc = ChatBloc(repository)..add(const ChatStarted());
    addTearDown(bloc.close);
    await pumpEventQueue();

    bloc.add(const ChatPromptSent('статус'));
    await _waitUntil(
      () =>
          !bloc.state.busy &&
          bloc.state.messages.any((m) => m.role == ChatRole.system),
    );

    expect(bloc.state.messages.last.role, ChatRole.system);
    expect(bloc.state.messages.last.text, contains('оборван'));
  });
}
