import 'dart:async';

import '../../core/logging/app_logger.dart';
import '../../core/models/chat_message.dart';
import '../repositories/chat_repository.dart';
import 'hub_api.dart';

/// Chat backed by the headless `opencode serve` instance behind the hub.
///
/// One session (reused by title) keeps the transcript alive across app
/// launches. A reply is produced over SSE: the repository opens
/// `GET /chat/event` first, waits until the link is attached, fires
/// `POST /chat/session/{id}/prompt` (OpenCode v2), then forwards the assistant text as opencode
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
  Future<void> stop() async {
    final sid = _sessionId;
    if (sid == null) {
      talker.info('chat: stop requested with no session — nothing to abort');
      return;
    }
    talker.info('chat: aborting run in session $sid');
    try {
      await _api.post('/chat/session/$sid/abort');
      talker.info('chat: abort acknowledged by opencode');
    } on HubApiException catch (e) {
      // A run may already be gone — the abort is best-effort, the local
      // stream is what actually unblocks the operator.
      talker.warning('chat: abort session $sid failed: $e');
    } catch (e) {
      talker.warning('chat: abort session $sid failed: $e');
    }
  }

  @override
  Future<void> clear() async {
    final sid = _sessionId;
    _sessionId = null;
    if (sid == null) return;
    talker.info('chat: clear session $sid');
    try {
      await _api.delete('/chat/session/$sid');
    } catch (e) {
      talker.warning('chat: clear session $sid failed: $e');
      // A stale session on the server is harmless — the next one replaces it.
    }
  }

  @override
  Future<List<ChatMessage>> history() async {
    try {
      final sid = await ensureSessionWithRetry();
      // Try to fetch history with small retries in case session is not fully ready
      // in opencode v2 (race condition).
      List<dynamic> raw = const [];
      for (var attempt = 0; attempt < 4; attempt++) {
        try {
          raw = await _api.getList(
            '/chat/session/$sid/message',
            query: {'limit': '50'},
          );
          break;
        } catch (e) {
          final msg = e.toString();
          if (attempt < 3 && (msg.contains('404') || msg.contains('not found') || msg.contains('создал'))) {
            await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
            continue;
          }
          rethrow;
        }
      }
      final out = <ChatMessage>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final info = item['info'];
        final infoMap = info is Map ? info : null;
        final parts = item['parts'] ?? item['content'];
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
        final roleStr = infoMap?['role'] ?? item['role'] ?? item['type'];
        final role = roleStr == 'user' ? ChatRole.user : ChatRole.bot;
        final timeMap = (infoMap?['time'] as Map?) ?? (item['time'] as Map?);
        final created = timeMap?['created'];
        out.add(
          ChatMessage(
            id: (infoMap?['id'] as String?) ?? (item['id'] as String?) ?? 'history-${out.length}',
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
    // Text parts in first-seen order. The answer arrives two ways: full
    // snapshots over `message.part.updated` and incremental chunks over
    // `message.part.delta`; whichever holds more characters wins per part.
    final textOrder = <String>[];
    final fullTexts = <String, String>{};
    final deltaTexts = <String, String>{};

    String compose() {
      final buffer = StringBuffer();
      for (final id in textOrder) {
        final full = fullTexts[id] ?? '';
        final delta = deltaTexts[id] ?? '';
        buffer.write(full.length >= delta.length ? full : delta);
      }
      return buffer.toString();
    }

    void emit() {
      if (controller.isClosed) return;
      controller.add(compose());
    }

    void finish() {
      if (finished) return;
      finished = true;
      talker.info(
        'chat: finish — sawBusy=$sawBusy sawText=$sawText '
        'parts=${textOrder.length} totalLen=${compose().length}',
      );
      if (!controller.isClosed) controller.close();
    }

    void fail(Object error) {
      if (finished) return;
      finished = true;
      talker.error('chat: fail — $error');
      if (!controller.isClosed) {
        controller.addError(error);
        controller.close();
      }
    }

    final stopwatch = Stopwatch()..start();
    final subscription = _api
        .stream(
          '/chat/event',
          onOpen: () {
            // The SSE link is up — hub answered 200. Events may still take a
            // moment, but the channel itself is alive, so the prompt can go.
            if (!attached.isCompleted) {
              talker.info(
                'chat: SSE link established after '
                '${stopwatch.elapsedMilliseconds}ms',
              );
              attached.complete();
            }
          },
        )
        .listen(
          (event) {
            if (!attached.isCompleted) {
              talker.info('chat: SSE link attached (first event)');
              attached.complete();
            }
            final props = event['properties'];
            if (props is! Map) return;
            final eventSession = props['sessionID'];
            if (eventSession != sid) {
              talker.debug(
                'chat: skip event type=${event['type']} '
                'session=$eventSession (want $sid)',
              );
              return;
            }
            switch (event['type']) {
              case 'session.status':
                final status = props['status'];
                final type = status is Map ? status['type'] : null;
                talker.info('chat: session.status → $type');
                if (type == 'busy') {
                  sawBusy = true;
                } else if (type == 'idle' && sawBusy) {
                  // The whole agent run is over (multi-step runs go
                  // busy→…→busy→idle); only now is the answer final.
                  finish();
                }
              case 'message.part.updated':
                // The SSE backlog replays old parts on connect — ignore
                // everything until our own run reports busy, or stale text
                // from previous turns leaks into this answer.
                if (!sawBusy) return;
                final part = props['part'];
                if (part is Map && part['type'] == 'text') {
                  sawText = true;
                  final id = (part['id'] as String?) ?? '';
                  final text = (part['text'] as String?) ?? '';
                  if (!textOrder.contains(id)) textOrder.add(id);
                  fullTexts[id] = text;
                  talker.debug('chat: part.updated id=$id len=${text.length}');
                  emit();
                }
              case 'message.part.delta':
                // Incremental chunk of a part's text — the primary way the
                // final answer streams (the full part.updated often only
                // arrives len=0 at part creation, or at the very end).
                // Deltas for reasoning/tool parts never get a text
                // part.updated, so they must stay invisible: accumulate
                // unconditionally, but surface only known-text parts.
                if (!sawBusy) return;
                if (props['field'] != 'text') return;
                final deltaId = (props['partID'] as String?) ?? '';
                final deltaChunk = (props['delta'] as String?) ?? '';
                if (deltaId.isEmpty || deltaChunk.isEmpty) return;
                deltaTexts[deltaId] = (deltaTexts[deltaId] ?? '') + deltaChunk;
                // Visible only once the part has been announced as text —
                // until then the chunk sits in the map, never composed.
                if (fullTexts.containsKey(deltaId)) {
                  sawText = true;
                  emit();
                }
              case 'message.updated':
                final info = props['info'];
                final time = info is Map ? info['time'] : null;
                final role = info is Map ? info['role'] : null;
                final completed = time is Map ? time['completed'] : null;
                final finishReason = info is Map ? info['finish'] : null;
                // A step that ends in tool-calls is NOT the final answer —
                // the agent continues with another busy round. Do not close.
                talker.debug(
                  'chat: message.updated role=$role completed=$completed '
                  'finish=$finishReason',
                );
              default:
                talker.debug('chat: unhandled event ${event['type']}');
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
      talker.info(
        'chat: waiting for SSE attach (timeout ${_attachTimeout.inSeconds}s)',
      );
      try {
        await attached.future.timeout(_attachTimeout);
      } on TimeoutException {
        final error = HubApiException(
          null,
          'SSE-канал не поднялся за ${_attachTimeout.inSeconds}s '
          '(hub: GET /chat/event). Проверь base URL и логи hub.',
        );
        talker.error('chat: $error');
        await subscription.cancel();
        throw error;
      }
      talker.info('chat: sending prompt to session $sid: "$prompt"');
      try {
        // OpenCode v2 uses POST /session/{id}/prompt. Hub proxies /chat/* and
        // rewrites paths; send to /chat/session/$sid/prompt for compatibility.
        await _api.post(
          '/chat/session/$sid/prompt',
          body: {
            'parts': [
              {'type': 'text', 'text': prompt},
            ],
          },
          timeout: const Duration(seconds: 10),
        );
        talker.info('chat: prompt accepted by hub (fast reply)');
      } on HubApiException catch (e) {
        if (e.isTimeout) {
          // The hub may hold the prompt open until the agent finishes —
          // the prompt is already queued; keep listening over SSE.
          talker.warning(
            'chat: prompt held open >10s — assuming accepted, '
            'waiting for SSE busy',
          );
        } else {
          // Fallback to old endpoint if hub hasn't been updated in some env
          try {
            await _api.post(
              '/chat/session/$sid/prompt_async',
              body: {
                'parts': [
                  {'type': 'text', 'text': prompt},
                ],
              },
              timeout: const Duration(seconds: 10),
            );
            talker.info('chat: prompt_async accepted by hub (fallback)');
          } catch (e2) {
            if (e2 is HubApiException && e2.isTimeout) {
              talker.warning(
                'chat: prompt_async held open >10s — assuming accepted, '
                'waiting for SSE busy',
              );
            } else {
              rethrow;
            }
          }
        }
      }
    } catch (e) {
      talker.error('chat: prompt send failed: $e');
      await subscription.cancel();
      rethrow;
    }

    // The hub may hold the prompt open for the whole agent run, so a
    // timeout there is normal. If the agent never reports busy, though,
    // something is wrong — surface it instead of hanging forever.
    final busyWatchdog = Timer(const Duration(seconds: 60), () {
      if (!sawBusy && !finished) {
        fail(
          const HubApiException(
            null,
            'агент не вышел в busy за 60s после prompt — '
            'проверь opencode на сервере',
          ),
        );
      }
    });

    final watchdog = Timer(_generationTimeout, () {
      fail(const HubApiException(null, 'агент не ответил за 30 минут'));
    });
    try {
      yield* controller.stream;
    } finally {
      watchdog.cancel();
      busyWatchdog.cancel();
      await subscription.cancel();
    }
  }

  /// Returns this chat's session id, looking it up (or creating it) on the
  /// first call. The title lets the app resume the same conversation later.
  Future<String> ensureSession() => ensureSessionWithRetry();

  Future<String> ensureSessionWithRetry() async {
    final cached = _sessionId;
    if (cached != null) {
      // Verify session still exists (helps with race conditions)
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await _api.get('/chat/session/$cached');
          return cached;
        } catch (e) {
          final msg = e.toString();
          if (attempt < 2 && (msg.contains('404') || msg.contains('not found'))) {
            await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
            continue;
          }
          break;
        }
      }
      _sessionId = null;
    }

    talker.info('chat: ensureSession — looking for title "$_sessionTitle"');
    try {
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
        talker.info('chat: ensureSession — resume existing session $newestId');
        // Give session a moment to be fully ready
        await Future<void>.delayed(const Duration(milliseconds: 150));
        return _sessionId = newestId;
      }
    } catch (e) {
      talker.warning('chat: ensureSession — list failed: $e');
    }

    talker.info('chat: ensureSession — no existing session, creating new');
    final created = await _api.post(
      '/chat/session',
      body: {'title': _sessionTitle},
    );
    final id = created['id'];
    if (id is! String || id.isEmpty) {
      talker.error('chat: ensureSession — hub returned no id: $created');
      throw const HubApiException(null, 'opencode не создал сессию');
    }
    talker.info('chat: ensureSession — created session $id');
    // Small delay to avoid race when immediately fetching history
    await Future<void>.delayed(const Duration(milliseconds: 250));
    // Verify session is accessible
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _api.get('/chat/session/$id');
        break;
      } catch (e) {
        if (attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
          continue;
        }
        // Don't fail hard - session might exist but endpoint behaves differently
      }
    }
    return _sessionId = id;
  }
}
