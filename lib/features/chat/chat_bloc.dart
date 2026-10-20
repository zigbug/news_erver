import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/logging/app_logger.dart';
import '../../core/models/chat_message.dart';
import '../../data/repositories/chat_repository.dart';
import 'chat_event.dart';
import 'chat_state.dart';

/// Terminal chat with the opencode agent. The repository streams the answer
/// over SSE; this bloc grows the pending bubble as chunks arrive and settles
/// it when the agent goes idle.
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(this._repository) : super(const ChatState()) {
    on<ChatStarted>(_onStarted);
    on<ChatPromptSent>(_onPromptSent);
    on<ChatStopped>(_onStopped);
    on<ChatCleared>(_onCleared);
  }

  final ChatRepository _repository;
  int _seq = 0;

  /// Set while a reply is streaming so [ChatStopped] knows there is a run to
  /// abort and which bubble to settle once the stream closes.
  ChatMessage? _pending;
  var _stopping = false;

  Future<void> _onStarted(ChatStarted event, Emitter<ChatState> emit) async {
    if (state.messages.isNotEmpty) return;
    emit(
      state.copyWith(
        suggestions: _repository.suggestions,
        messages: [
          _message(ChatRole.bot, _repository.greeting),
          _message(ChatRole.system, 'session started · protocol v1.0'),
        ],
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

  Future<void> _onPromptSent(
    ChatPromptSent event,
    Emitter<ChatState> emit,
  ) async {
    final prompt = event.prompt.trim();
    if (prompt.isEmpty || state.busy) return;

    final pending = _message(ChatRole.bot, '', pending: true);
    _pending = pending;
    _stopping = false;
    emit(
      state.copyWith(
        messages: [...state.messages, _message(ChatRole.user, prompt), pending],
        thinking: true,
      ),
    );

    try {
      await emit.forEach(
        _repository.reply(prompt),
        onData: (String text) {
          final index = state.messages.indexWhere((m) => m.id == pending.id);
          if (index == -1) return state;
          final list = [...state.messages];
          list[index] = list[index].copyWith(text: text, pending: true);
          return state.copyWith(messages: list, thinking: false, typing: true);
        },
      );
    } catch (e) {
      talker.error('chat: reply stream failed: $e');
      if (!emit.isDone) {
        // Drop the pending bubble here — _settle would otherwise replace
        // it with a second "no answer" note on top of this error message.
        final list = state.messages.toList();
        list.removeWhere((m) => m.id == pending.id);
        emit(
          state.copyWith(
            messages: [...list, _message(ChatRole.system, 'ошибка чата: $e')],
          ),
        );
      }
    } finally {
      _pending = null;
      if (!emit.isDone) _settle(pending, emit);
    }
  }

  /// Aborts the run in progress. The server answers the abort with an idle
  /// status, which closes the reply stream and settles the bubble; this only
  /// fires the request and flips the UI out of its busy state promptly, so a
  /// slow abort cannot leave the operator locked out.
  Future<void> _onStopped(ChatStopped event, Emitter<ChatState> emit) async {
    if (_stopping) return;
    _stopping = true;
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

  /// Clears the pending cursor and flips both busy flags — called when the
  /// stream ends, whether the agent finished or the link died.
  void _settle(ChatMessage pending, Emitter<ChatState> emit) {
    final index = state.messages.indexWhere((m) => m.id == pending.id);
    var messages = state.messages;
    if (index != -1) {
      messages = [...messages];
      final message = messages[index];
      if (message.text.isEmpty) {
        // No answer ever arrived — replace the bubble with a visible note
        // instead of dropping it silently.
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
    try {
      await _repository.clear();
    } catch (_) {
      // A failed reset on the hub must not block the local wipe.
    }
    emit(ChatState(suggestions: _repository.suggestions));
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
