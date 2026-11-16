import 'dart:async';

import '../../core/logging/app_logger.dart';
import '../../core/models/chat_message.dart';
import '../repositories/chat_repository.dart';
import 'hub_api.dart';
import 'opencode_event_parser.dart';

/// Chat backed by the headless `opencode serve` instance behind the hub.
///
/// One session (reused by title) keeps the transcript alive across app
/// launches. A reply is produced over SSE: the repository opens
/// `GET /chat/event` first, waits until the link is attached, fires
/// `POST /chat/session/{id}/prompt` (OpenCode v2), then forwards the assistant text as opencode
/// accumulates it and closes once the session reports idle.
class OpencodeChatRepository implements ChatRepository {
  OpencodeChatRepository(
    this._api, {
    this.attachTimeout = const Duration(seconds: 15),
    this.busyTimeout = const Duration(seconds: 60),
    this.generationTimeout = const Duration(minutes: 30),
  });

  /// Title used to recognise this chat's session in `GET /chat/session`.
  static const _sessionTitle = 'hub-chat';

  /// How long to wait for the SSE link before sending the prompt.
  final Duration attachTimeout;

  /// How long the agent may stay silent after the prompt before the client
  /// gives up and reports the failure instead of waiting forever.
  final Duration busyTimeout;

  /// Cap on a single generation — an agent run may be long, but not endless.
  final Duration generationTimeout;

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
          if (attempt < 3 &&
              (msg.contains('404') ||
                  msg.contains('not found') ||
                  msg.contains('создал'))) {
            await Future<void>.delayed(
              Duration(milliseconds: 250 * (attempt + 1)),
            );
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
        // v1 exposes the role as info.role; v2 uses item.type
        // ("user"/"assistant"). Anything else (idle, compaction, tool …) is
        // not part of the transcript.
        final roleStr =
            infoMap?['role'] ??
            infoMap?['type'] ??
            item['role'] ??
            item['type'];
        final isUser = roleStr == 'user';
        final isAssistant = roleStr == 'assistant' || roleStr == 'bot';
        if (!isUser && !isAssistant) continue;

        final text = <String>[];
        // v2 user messages carry the prompt as a plain `text` field.
        final direct = item['text'];
        if (isUser && direct is String && direct.isNotEmpty) text.add(direct);
        // v1 uses parts[], v2 uses content[]. Both keep text chunks in
        // `{type: "text", text: "…"}` entries.
        final parts = item['parts'] ?? item['content'];
        if (parts is List) {
          for (final part in parts) {
            if (part is Map && part['type'] == 'text') {
              final chunk = part['text'];
              if (chunk is String && chunk.isNotEmpty) text.add(chunk);
            }
          }
        }
        if (text.isEmpty) continue;
        final role = isUser ? ChatRole.user : ChatRole.bot;
        final timeMap = (infoMap?['time'] as Map?) ?? (item['time'] as Map?);
        final created = timeMap?['created'];
        out.add(
          ChatMessage(
            id:
                (infoMap?['id'] as String?) ??
                (item['id'] as String?) ??
                'history-${out.length}',
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
    var failed = false;
    var sawBusy = false;
    var sawText = false;
    // Guards against a replayed "execution started" event from a previous
    // turn marking this reply busy before we have even sent the prompt.
    var promptRequested = false;
    // Text parts in first-seen order. The answer arrives two ways: full
    // snapshots (`message.part.updated` in v1, `session.text.ended` in v2)
    // and incremental chunks (`message.part.delta` / `session.text.delta`);
    // whichever holds more characters wins per part.
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
      failed = true;
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
          (frame) {
            if (!attached.isCompleted) {
              talker.info('chat: SSE link attached (first event)');
              attached.complete();
            }
            // The hub may forward opencode v2 events verbatim
            // ({type, data}), wrap them in an SSE envelope ({event, data})
            // or still speak the old v1 dialect ({type, properties}).
            final event = parseOpencodeEvent(frame);
            if (event == null) {
              talker.debug('chat: unparsable event $frame');
              return;
            }
            final props = event.data;
            final eventSession = props['sessionID'] ?? frame['sessionID'];
            if (eventSession != sid) {
              talker.debug(
                'chat: skip event type=${event.type} '
                'session=$eventSession (want $sid)',
              );
              return;
            }

            // v2 identifies a text part by its message id + ordinal.
            String textPartKey() =>
                '${props['assistantMessageID'] ?? ''}:'
                '${props['ordinal'] ?? ''}';

            switch (event.type) {
              // ---- opencode v2 ----
              case 'session.execution.started':
                // A replayed event from the previous turn must not mark
                // this reply busy before the prompt has been sent.
                if (!promptRequested) return;
                // Liveness: the agent is running even if it is still doing
                // tool calls. Disarms the client-side first-chunk fallback.
                if (!sawBusy) emit();
                sawBusy = true;
              case 'session.execution.succeeded':
                if (!sawBusy) return;
                finish();
              case 'session.execution.interrupted':
                if (!sawBusy) return;
                finish();
              case 'session.execution.failed':
                if (!sawBusy) return;
                final error = props['error'];
                final message = error is Map ? error['message'] : null;
                fail(
                  HubApiException(
                    null,
                    'агент завершил ход с ошибкой: ${message ?? 'unknown'}',
                  ),
                );
              case 'session.idle':
                // The whole agent run is over; only now is the answer final.
                if (sawBusy) finish();
              case 'session.text.started':
                // Announces a text part before its first delta. Nothing to
                // render yet, but the part must stay in first-seen order.
                if (!sawBusy) return;
                sawText = true;
                final startedKey = textPartKey();
                if (!textOrder.contains(startedKey)) {
                  textOrder.add(startedKey);
                }
              case 'session.text.delta':
                if (!sawBusy) return;
                final chunk = props['delta'];
                if (chunk is! String || chunk.isEmpty) return;
                sawText = true;
                final deltaKey = textPartKey();
                if (!textOrder.contains(deltaKey)) textOrder.add(deltaKey);
                deltaTexts[deltaKey] = (deltaTexts[deltaKey] ?? '') + chunk;
                emit();
              case 'session.text.ended':
                // Carries the full text of the part — authoritative.
                if (!sawBusy) return;
                sawText = true;
                final endedKey = textPartKey();
                if (!textOrder.contains(endedKey)) textOrder.add(endedKey);
                final text = props['text'];
                if (text is String) {
                  final delta = deltaTexts[endedKey] ?? '';
                  fullTexts[endedKey] = text.length >= delta.length
                      ? text
                      : delta;
                }
                emit();
              case 'session.message.content.updated':
                // Durable fallback: full content of an assistant message.
                // Only used when the live text.* events never arrived, so
                // the same text cannot be appended twice.
                if (!sawBusy) return;
                final messageID = props['messageID'];
                final content = props['content'];
                if (messageID is! String || content is! List) return;
                final prefix = '$messageID:';
                if (textOrder.any((key) => key.startsWith(prefix))) return;
                for (var i = 0; i < content.length; i++) {
                  final contentPart = content[i];
                  if (contentPart is! Map || contentPart['type'] != 'text') {
                    continue;
                  }
                  final contentText = contentPart['text'];
                  if (contentText is! String || contentText.isEmpty) continue;
                  final contentKey = '$messageID:$i';
                  if (!textOrder.contains(contentKey)) {
                    textOrder.add(contentKey);
                  }
                  fullTexts[contentKey] = contentText;
                  sawText = true;
                }
                emit();
              // ---- opencode v1 ----
              case 'session.status':
                final status = props['status'];
                final type = status is Map ? status['type'] : null;
                talker.info('chat: session.status → $type');
                if (type == 'busy') {
                  if (promptRequested && !sawBusy) {
                    // Liveness signal for the client-side fallback.
                    emit();
                  }
                  if (promptRequested) sawBusy = true;
                } else if (type == 'idle' && sawBusy) {
                  // Multi-step runs go busy→…→busy→idle; only the final
                  // idle closes the answer.
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
                talker.debug('chat: unhandled event ${event.type}');
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
        'chat: waiting for SSE attach (timeout ${attachTimeout.inSeconds}s)',
      );
      try {
        await attached.future.timeout(attachTimeout);
      } on TimeoutException {
        final error = HubApiException(
          null,
          'SSE-канал не поднялся за ${attachTimeout.inSeconds}s '
          '(hub: GET /chat/event). Проверь base URL и логи hub.',
        );
        talker.error('chat: $error');
        await subscription.cancel();
        throw error;
      }
      talker.info('chat: sending prompt to session $sid: "$prompt"');
      promptRequested = true;
      try {
        // OpenCode v2.2.1: POST /api/session/{id}/prompt expects {"text": "..."}
        await _api.post(
          '/chat/session/$sid/prompt',
          body: {'text': prompt},
          timeout: const Duration(seconds: 10),
        );
        talker.info('chat: prompt accepted by hub (fast reply)');
      } on HubApiException catch (e) {
        if (e.isTimeout) {
          talker.warning(
            'chat: prompt held open >10s — assuming accepted, '
            'waiting for SSE busy',
          );
        } else {
          // Fallback to old format just in case
          try {
            await _api.post(
              '/chat/session/$sid/prompt',
              body: {
                'parts': [
                  {'type': 'text', 'text': prompt},
                ],
              },
              timeout: const Duration(seconds: 10),
            );
            talker.info('chat: prompt accepted by hub (fallback parts)');
          } catch (e2) {
            if (e2 is HubApiException && e2.isTimeout) {
              talker.warning(
                'chat: prompt held open >10s — assuming accepted, '
                'waiting for SSE busy',
              );
            } else {
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
              } catch (e3) {
                if (e3 is HubApiException && e3.isTimeout) {
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
    final busyWatchdog = Timer(busyTimeout, () {
      if (!sawBusy && !finished) {
        fail(
          HubApiException(
            null,
            'агент не вышел в busy за ${_durationLabel(busyTimeout)} '
            'после prompt — проверь opencode на сервере',
          ),
        );
      }
    });

    final watchdog = Timer(generationTimeout, () {
      fail(
        HubApiException(
          null,
          'агент не ответил за ${_durationLabel(generationTimeout)}',
        ),
      );
    });
    try {
      yield* controller.stream;
    } finally {
      watchdog.cancel();
      busyWatchdog.cancel();
      await subscription.cancel();
      talker.info(
        'chat: reply finished — '
        '${failed
            ? 'failed'
            : finished
            ? 'closed'
            : 'aborted'}',
      );
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
          if (attempt < 2 &&
              (msg.contains('404') || msg.contains('not found'))) {
            await Future<void>.delayed(
              Duration(milliseconds: 200 * (attempt + 1)),
            );
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
    // v2 answers with {data: Session.Info}; older hubs returned the session
    // object directly.
    final createdData = created['data'];
    final createdSession = createdData is Map ? createdData : created;
    final id = createdSession['id'];
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
          await Future<void>.delayed(
            Duration(milliseconds: 200 * (attempt + 1)),
          );
          continue;
        }
        // Don't fail hard - session might exist but endpoint behaves differently
      }
    }
    return _sessionId = id;
  }
}

/// Human-readable duration for error messages: "150ms", "60s", "30 мин".
String _durationLabel(Duration duration) {
  if (duration.inMilliseconds < 1000) return '${duration.inMilliseconds}ms';
  if (duration.inSeconds < 60) return '${duration.inSeconds}s';
  if (duration.inMinutes < 60) return '${duration.inMinutes} мин';
  return '${duration.inHours} ч';
}
