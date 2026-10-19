import 'dart:async';

import '../../core/models/chat_message.dart';
import '../repositories/chat_repository.dart';
import 'hub_api.dart';

/// Chat backed by the headless `opencode serve` instance behind the hub.
///
/// One session (reused by title) keeps the transcript alive across app
/// launches. A reply is produced over SSE: the repository opens
/// `GET /chat/event` first, waits until the link is attached, fires
/// `POST .../prompt_async`, then forwards the assistant text as opencode
/// accumulates it and closes once the session reports idle.
class OpencodeChatRepository implements ChatRepository {
  OpencodeChatRepository(this._api);

  /// Title used to recognise this chat's session in `GET /chat/session`.
  static const _sessionTitle = 'hub-chat';

  /// Cap on a single generation — an agent run may be long, but not endless.
  static const _generationTimeout = Duration(minutes: 30);

  /// How long to wait for the SSE link before sending the prompt.
  static const _attachTimeout = Duration(seconds: 15);

  final HubApi _api;
  String? _sessionId;

  @override
  String get greeting =>
      'opencode agent online. выполняю задачи прямо на сервере: '
      'команды, файлы, журналы, конфиги.\n'
      'один оператор — одна линия.';

  @override
  List<String> get suggestions => const [
    'статус сервера',
    'что слушает на портах?',
    'последние ошибки в журнале',
  ];

  @override
  Future<void> clear() async {
    final sid = _sessionId;
    _sessionId = null;
    if (sid == null) return;
    try {
      await _api.delete('/chat/session/$sid');
    } catch (_) {
      // A stale session on the server is harmless — the next one replaces it.
    }
  }

  @override
  Future<List<ChatMessage>> history() async {
    try {
      final sid = await ensureSession();
      final raw = await _api.getList(
        '/chat/session/$sid/message',
        query: {'limit': '50'},
      );
      final out = <ChatMessage>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final info = item['info'];
        if (info is! Map) continue;
        final parts = item['parts'];
        final text = <String>[];
        if (parts is List) {
          for (final part in parts) {
            if (part is Map && part['type'] == 'text') {
              final chunk = part['text'];
              if (chunk is String && chunk.isNotEmpty) text.add(chunk);
            }
          }
        }
        if (text.isEmpty) continue;
        final role = info['role'] == 'user' ? ChatRole.user : ChatRole.bot;
        final created = (info['time'] as Map?)?['created'];
        out.add(
          ChatMessage(
            id: (info['id'] as String?) ?? 'history-${out.length}',
            role: role,
            text: text.join('\n'),
            timestamp: created is num
                ? DateTime.fromMillisecondsSinceEpoch(created.toInt())
                : DateTime.now(),
          ),
        );
      }
      return out;
    } catch (_) {
      // The cached session may have been deleted elsewhere — force a re-lookup.
      _sessionId = null;
      rethrow;
    }
  }

  @override
  Stream<String> reply(String prompt) async* {
    final sid = await ensureSession();

    final controller = StreamController<String>();
    final attached = Completer<void>();
    // Swallows the error when nobody is awaiting (the attach timeout fired
    // first); the reply itself still fails through the timeout below.
    attached.future.ignore();
    var finished = false;
    var sawBusy = false;
    var sawText = false;
    var other = '';
    var partId = '';
    var partText = '';

    void finish() {
      if (finished) return;
      finished = true;
      if (!controller.isClosed) controller.close();
    }

    void fail(Object error) {
      if (finished) return;
      finished = true;
      if (!controller.isClosed) {
        controller.addError(error);
        controller.close();
      }
    }

    final subscription = _api
        .stream('/chat/event')
        .listen(
          (event) {
            if (!attached.isCompleted) attached.complete();
            final props = event['properties'];
            if (props is! Map || props['sessionID'] != sid) return;
            switch (event['type']) {
              case 'session.status':
                final status = props['status'];
                final type = status is Map ? status['type'] : null;
                if (type == 'busy') {
                  sawBusy = true;
                } else if (type == 'idle' && (sawBusy || sawText)) {
                  finish();
                }
              case 'message.part.updated':
                final part = props['part'];
                if (part is Map && part['type'] == 'text') {
                  sawText = true;
                  final id = (part['id'] as String?) ?? '';
                  final text = (part['text'] as String?) ?? '';
                  if (id == partId) {
                    partText = text;
                  } else {
                    other += partText;
                    partId = id;
                    partText = text;
                  }
                  if (!controller.isClosed) controller.add(other + partText);
                }
              case 'message.updated':
                final info = props['info'];
                final time = info is Map ? info['time'] : null;
                if (info is Map &&
                    info['role'] == 'assistant' &&
                    time is Map &&
                    time['completed'] != null) {
                  finish();
                }
            }
          },
          onError: (Object error) {
            if (!attached.isCompleted) attached.completeError(error);
            fail(error);
          },
          onDone: () {
            // The hub dropped the stream before the agent finished.
            final error = const HubApiException(null, 'поток событий оборван');
            if (!attached.isCompleted) attached.completeError(error);
            fail(error);
          },
        );

    try {
      // The prompt must not go out before the stream is attached, or the
      // busy/idle handshake would be missed and the reply never settle.
      await attached.future.timeout(_attachTimeout);
      await _api.post(
        '/chat/session/$sid/prompt_async',
        body: {
          'parts': [
            {'type': 'text', 'text': prompt},
          ],
        },
      );
    } catch (_) {
      await subscription.cancel();
      rethrow;
    }

    final watchdog = Timer(_generationTimeout, () {
      fail(const HubApiException(null, 'агент не ответил за 30 минут'));
    });
    try {
      yield* controller.stream;
    } finally {
      watchdog.cancel();
      await subscription.cancel();
    }
  }

  /// Returns this chat's session id, looking it up (or creating it) on the
  /// first call. The title lets the app resume the same conversation later.
  Future<String> ensureSession() async {
    final cached = _sessionId;
    if (cached != null) return cached;

    final sessions = await _api.getList('/chat/session');
    String? newestId;
    var newestUpdated = -1;
    for (final item in sessions) {
      if (item is! Map || item['title'] != _sessionTitle) continue;
      final id = item['id'];
      final updated = (item['time'] as Map?)?['updated'];
      if (id is! String) continue;
      if (updated is num && updated.toInt() > newestUpdated) {
        newestUpdated = updated.toInt();
        newestId = id;
      }
    }

    if (newestId != null) {
      return _sessionId = newestId;
    }
    final created = await _api.post(
      '/chat/session',
      body: {'title': _sessionTitle},
    );
    final id = created['id'];
    if (id is! String || id.isEmpty) {
      throw const HubApiException(null, 'opencode не создал сессию');
    }
    return _sessionId = id;
  }
}
