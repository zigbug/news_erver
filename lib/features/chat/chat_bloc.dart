import 'package:flutter_bloc/flutter_bloc.dart';

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
    on<ChatCleared>(_onCleared);
  }

  final ChatRepository _repository;
  int _seq = 0;

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
      if (!emit.isDone) {
        emit(
          state.copyWith(
            messages: [
              ...state.messages,
              _message(ChatRole.system, 'ошибка чата: $e'),
            ],
          ),
        );
      }
    } finally {
      if (!emit.isDone) _settle(pending, emit);
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
        messages.removeAt(index); // no answer ever arrived — drop the bubble
      } else {
        messages[index] = message.copyWith(pending: false);
      }
    }
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
