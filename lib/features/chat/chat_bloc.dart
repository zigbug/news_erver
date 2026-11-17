import 'dart:async';
import 'dart:collection';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/logging/app_logger.dart';
import '../../core/models/chat_message.dart';
import '../../data/repositories/chat_repository.dart';
import 'chat_event.dart';
import 'chat_state.dart';

/// Terminal chat with the opencode agent. The repository streams the answer
/// over SSE; this bloc grows the pending bubble as chunks arrive and settles
/// it when the agent goes idle.
///
/// Prompts are processed sequentially. While a run is busy, new prompts are
/// queued (supplement/follow-up) and sent after the current run completes,
/// unless the operator stops the run.
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(
    this._repository, {
    this.firstChunkTimeout = const Duration(seconds: 90),
  }) : super(const ChatState()) {
    on<ChatStarted>(_onStarted);
    on<ChatPromptSent>(_onPromptSent);
    on<ChatStopped>(_onStopped);
    on<ChatCleared>(_onCleared);
    on<ChatModelSelected>(_onModelSelected);
  }

  final ChatRepository _repository;

  /// Hard deadline for the first chunk of a reply.
  final Duration firstChunkTimeout;

  int _seq = 0;

  /// Pending bot bubble for the active run.
  ChatMessage? _pending;
  var _stopping = false;
  var _processing = false;
  final Queue<String> _queue = Queue<String>();

  Future<void> _onStarted(ChatStarted event, Emitter<ChatState> emit) async {
    if (state.messages.isNotEmpty) return;
    emit(
      state.copyWith(
        suggestions: _repository.suggestions,
        messages: [_message(ChatRole.bot, _repository.greeting)],
      ),
    );

    try {
      final history = await _repository.history();
      if (emit.isDone) return;
      if (history.isNotEmpty) {
        emit(state.copyWith(messages: [...state.messages, ...history]));
      }
    } catch (e) {
      talker.error('chat: history load failed: $e');
      if (emit.isDone) return;
      final msg = e.toString();
      if (msg.contains('opencode не создал сессию')) {
        emit(
          state.copyWith(
            messages: [
              ...state.messages,
              _message(ChatRole.system, 'история недоступна: $e'),
            ],
          ),
        );
      }
    }

    // Load available models in background (best-effort).
    if (!emit.isDone) {
      emit(state.copyWith(modelsLoading: true));
      try {
        final models = await _repository.availableModels();
        if (!emit.isDone) {
          var selected = state.selectedModelId;
          if (selected.isNotEmpty &&
              !models.any((m) => m.id == selected)) {
            selected = '';
          }
          emit(state.copyWith(
            models: models,
            selectedModelId: selected,
            modelsLoading: false,
          ));
        }
      } catch (e) {
        talker.warning('chat: models load failed: $e');
        if (!emit.isDone) {
          emit(state.copyWith(modelsLoading: false));
        }
      }
    }
  }

  Future<void> _onModelSelected(
    ChatModelSelected event,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(selectedModelId: event.modelId.trim()));
  }

  Future<void> _onPromptSent(
    ChatPromptSent event,
    Emitter<ChatState> emit,
  ) async {
    final prompt = event.prompt.trim();
    if (prompt.isEmpty) return;

    // Always append the operator message immediately.
    emit(
      state.copyWith(
        messages: [...state.messages, _message(ChatRole.user, prompt)],
      ),
    );

    if (_processing) {
      _queue.add(prompt);
      emit(state.copyWith(queuedCount: _queue.length));
      return;
    }

    await _drainQueue(prompt, emit);
  }

  Future<void> _drainQueue(String? first, Emitter<ChatState> emit) async {
    if (_processing) return;
    _processing = true;
    var next = first;

    try {
      while (next != null && !emit.isDone) {
        await _runPrompt(next, emit);
        if (_stopping) {
          // Operator aborted: drop queued follow-ups (they were supplements
          // to the interrupted run). User can resend explicitly.
          _queue.clear();
          emit(state.copyWith(queuedCount: 0));
          break;
        }
        if (_queue.isEmpty) {
          next = null;
        } else {
          next = _queue.removeFirst();
          emit(state.copyWith(queuedCount: _queue.length));
        }
      }
    } finally {
      _processing = false;
      if (!emit.isDone) {
        emit(state.copyWith(queuedCount: _queue.length));
      }
    }
  }

  Map<String, String>? _selectedModel() {
    final id = state.selectedModelId.trim();
    if (id.isEmpty) return null;
    final parts = id.split('/');
    if (parts.length < 2) return null;
    final providerID = parts.first.trim();
    final modelID = parts.sublist(1).join('/').trim();
    if (providerID.isEmpty || modelID.isEmpty) return null;
    return {'providerID': providerID, 'modelID': modelID};
  }

  Future<void> _runPrompt(String prompt, Emitter<ChatState> emit) async {
    final pending = _message(ChatRole.bot, '', pending: true);
    _pending = pending;
    _stopping = false;
    emit(
      state.copyWith(
        messages: [...state.messages, pending],
        thinking: true,
        typing: false,
      ),
    );

    var reported = false;
    void report(Object error) {
      if (reported || emit.isDone) return;
      reported = true;
      final list = state.messages.toList();
      final index = list.indexWhere((m) => m.id == pending.id);
      final failure = _message(
        ChatRole.system,
        'ошибка чата: $error\nподробности — в логах (кнопка ▤)',
      );
      if (index == -1) {
        list.add(failure);
      } else {
        list[index] = failure;
      }
      emit(state.copyWith(messages: list, thinking: false, typing: false));
    }

    var answered = false;
    final guard = Timer(firstChunkTimeout, () {
      if (answered || reported || emit.isDone) return;
      final error =
          'агент не начал отвечать за ${_secondsLabel(firstChunkTimeout)} — '
          'ожидание прервано';
      talker.error('chat: no first chunk — $error');
      report(error);
      unawaited(_repository.stop());
    });

    try {
      await emit.forEach(
        _repository.reply(prompt, model: _selectedModel()),
        onData: (String text) {
          if (text.isEmpty) {
            answered = true;
            return state.copyWith(thinking: state.thinking);
          }
          answered = true;
          final index = state.messages.indexWhere((m) => m.id == pending.id);
          if (index == -1) return state;
          final list = [...state.messages];
          list[index] = list[index].copyWith(text: text, pending: true);
          return state.copyWith(messages: list, thinking: false, typing: true);
        },
      );
    } catch (e) {
      talker.error('chat: reply stream failed: $e');
      report(e);
    } finally {
      guard.cancel();
      _pending = null;
      if (!emit.isDone) _settle(pending, emit);
    }
  }

  /// Aborts the run in progress.
  Future<void> _onStopped(ChatStopped event, Emitter<ChatState> emit) async {
    if (_stopping) return;
    _stopping = true;
    _queue.clear();
    if (!emit.isDone) emit(state.copyWith(queuedCount: 0));

    final pending = _pending;
    if (pending != null && !emit.isDone) {
      final index = state.messages.indexWhere((m) => m.id == pending.id);
      if (index != -1) {
        final list = [...state.messages];
        final message = list[index];
        list[index] = message.text.isEmpty
            ? message
            : message.copyWith(pending: false);
        emit(state.copyWith(messages: list, thinking: false, typing: false));
      }
    } else if (!emit.isDone) {
      emit(state.copyWith(thinking: false, typing: false));
    }
    try {
      await _repository.stop();
    } catch (e) {
      talker.warning('chat: stop failed: $e');
    }
  }

  /// Clears the pending cursor and flips busy flags.
  void _settle(ChatMessage pending, Emitter<ChatState> emit) {
    final index = state.messages.indexWhere((m) => m.id == pending.id);
    var messages = state.messages;
    if (index != -1) {
      messages = [...messages];
      final message = messages[index];
      if (message.text.isEmpty) {
        messages[index] = _message(
          ChatRole.system,
          _stopping
              ? 'ход прерван оператором'
              : 'агент завершил ход без ответа — см. логи (кнопка ▤)',
        );
      } else {
        messages[index] = message.copyWith(pending: false);
      }
    }
    _stopping = false;
    emit(state.copyWith(messages: messages, thinking: false, typing: false));
  }

  Future<void> _onCleared(ChatCleared event, Emitter<ChatState> emit) async {
    _queue.clear();
    _processing = false;
    _pending = null;
    _stopping = false;
    try {
      await _repository.clear();
    } catch (_) {
      // A failed reset on the hub must not block the local wipe.
    }
    emit(ChatState(
      suggestions: _repository.suggestions,
      models: state.models,
      selectedModelId: state.selectedModelId,
      modelsLoading: state.modelsLoading,
    ));
  }

  ChatMessage _message(ChatRole role, String text, {bool pending = false}) =>
      ChatMessage(
        id: 'msg-${_seq++}',
        role: role,
        text: text,
        timestamp: DateTime.now(),
        pending: pending,
      );
}

/// "150ms", "90s", "2 мин" — compact duration for user-facing messages.
String _secondsLabel(Duration duration) {
  if (duration.inMilliseconds < 1000) return '${duration.inMilliseconds}ms';
  if (duration.inSeconds < 60) return '${duration.inSeconds}s';
  return '${duration.inMinutes} мин';
}
