import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:news_erver/core/models/app_settings.dart';
import 'package:news_erver/core/models/chat_message.dart';
import 'package:news_erver/data/api/hub_api.dart';
import 'package:news_erver/data/api/opencode_chat_repository.dart';

class _FakeHubApi extends HubApi {
  _FakeHubApi({required this.messages})
    : super(
        connection: () =>
            const ConnectionSettings(apiBaseUrl: 'http://hub.test'),
      );

  final List<dynamic> messages;
  final events = StreamController<Map<String, dynamic>>.broadcast();
  var promptSent = false;

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
    if (path == '/chat/session/s1/message') return messages;
    return const [];
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Duration? timeout,
  }) async {
    if (path.endsWith('/prompt')) promptSent = true;
    return const {};
  }

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

Map<String, dynamic> _v2(String type, Map<String, dynamic> data) => {
  'id': 'evt_$type',
  'created': 1770000000000,
  'type': type,
  'data': {'sessionID': 's1', ...data},
};

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
  test('history reads opencode v2 user and assistant messages', () async {
    final api = _FakeHubApi(
      messages: [
        {
          'id': 'u1',
          'type': 'user',
          'time': {'created': 1000},
          'text': 'статус сервера',
        },
        {
          'id': 'a1',
          'type': 'assistant',
          'time': {'created': 2000},
          'content': [
            {'type': 'reasoning', 'text': 'thinking…'},
            {'type': 'text', 'text': 'всё в порядке'},
          ],
        },
        {
          'id': 'i1',
          'type': 'idle',
          'time': {'created': 3000},
        },
      ],
    );

    final history = await OpencodeChatRepository(api).history();

    expect(history, hasLength(2));
    expect(history[0].role, ChatRole.user);
    expect(history[0].text, 'статус сервера');
    expect(history[1].role, ChatRole.bot);
    expect(history[1].text, 'всё в порядке');
  });

  test('history still reads the opencode v1 {info, parts} shape', () async {
    final api = _FakeHubApi(
      messages: [
        {
          'info': {
            'id': 'u1',
            'role': 'user',
            'time': {'created': 1000},
          },
          'parts': [
            {'type': 'text', 'text': 'статус'},
          ],
        },
        {
          'info': {
            'id': 'a1',
            'role': 'assistant',
            'time': {'created': 2000},
          },
          'parts': [
            {'type': 'text', 'text': 'ок'},
          ],
        },
      ],
    );

    final history = await OpencodeChatRepository(api).history();

    expect(history, hasLength(2));
    expect(history[0].role, ChatRole.user);
    expect(history[1].role, ChatRole.bot);
  });

  test('reply streams opencode v2 text events and settles on idle', () async {
    final api = _FakeHubApi(messages: const []);
    final repository = OpencodeChatRepository(api);
    final chunks = <String>[];
    final done = Completer<void>();

    repository
        .reply('статус')
        .listen(chunks.add, onError: done.completeError, onDone: done.complete);
    await _waitUntil(() => api.promptSent);

    api.events
      ..add(_v2('session.execution.started', const {}))
      ..add(
        _v2('session.text.started', const {
          'assistantMessageID': 'm1',
          'ordinal': 0,
        }),
      )
      ..add(
        _v2('session.text.delta', const {
          'assistantMessageID': 'm1',
          'ordinal': 0,
          'delta': 'всё ',
        }),
      )
      ..add(
        _v2('session.text.delta', const {
          'assistantMessageID': 'm1',
          'ordinal': 0,
          'delta': 'хорошо',
        }),
      )
      ..add(
        _v2('session.text.ended', const {
          'assistantMessageID': 'm1',
          'ordinal': 0,
          'text': 'всё хорошо',
        }),
      )
      ..add(_v2('session.execution.succeeded', const {}));

    await done.future.timeout(const Duration(seconds: 5));

    expect(chunks, isNotEmpty);
    expect(chunks.last, 'всё хорошо');
  });
}
