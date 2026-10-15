import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/chat_message.dart';
import '../../data/repositories/chat_repository.dart';
import 'chat_event.dart';
import 'chat_state.dart';

/// Terminal chat with the server bot. The repository returns the full answer;
/// this bloc reveals it with a typewriter effect so replies feel like a real
/// terminal session.
class ChatBloc extends Bloc<ChatEvent, ChatState> {
  ChatBloc(this._repository) : super(const ChatState()) {
    on<ChatStarted>(_onStarted);
    on<ChatPromptSent>(_onPromptSent);
    on<ChatCleared>(_onCleared);
  }

  static const Duration _revealInterval = Duration(milliseconds: 16);
  static const int _charsPerTick = 2;

  final ChatRepository _repository;
  Timer? _typingTimer;
  int _seq = 0;

  void _onStarted(ChatStarted event, Emitter<ChatState> emit) {
    if (state.messages.isNotEmpty) return;
    emit(
      state.copyWith(
        suggestions: _repository.suggestions,
        messages: [
          _message(ChatRole.bot, _repository.greeting),
          _message(ChatRole.system, 'session started · protocol v0.9'),
        ],
      ),
    );
  }

  Future<void> _onPromptSent(
    ChatPromptSent event,
    Emitter<ChatState> emit,
  ) async {
    final prompt = event.prompt.trim();
    if (prompt.isEmpty || state.busy) return;

    emit(
      state.copyWith(
        messages: [...state.messages, _message(ChatRole.user, prompt)],
        thinking: true,
      ),
    );

    final answer = await _repository.reply(prompt);

    final pending = _message(ChatRole.bot, '', pending: true);
    emit(
      state.copyWith(
        messages: [...state.messages, pending],
        thinking: false,
        typing: true,
      ),
    );

    await _reveal(answer, pending, emit);
  }

  Future<void> _reveal(
    String full,
    ChatMessage pending,
    Emitter<ChatState> emit,
  ) async {
    _typingTimer?.cancel();
    final completer = Completer<void>();
    var revealed = 0;

    void publish({required bool done}) {
      final index = state.messages.indexWhere((m) => m.id == pending.id);
      if (index == -1) return;
      final updated = state.messages[index].copyWith(
        text: done ? full : full.substring(0, revealed),
        pending: !done,
      );
      final list = [...state.messages]..[index] = updated;
      emit(state.copyWith(messages: list, typing: !done));
    }

    _typingTimer = Timer.periodic(_revealInterval, (timer) {
      revealed = (revealed + _charsPerTick).clamp(0, full.length);
      final done = revealed >= full.length;
      publish(done: done);
      if (done) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });

    return completer.future;
  }

  void _onCleared(ChatCleared event, Emitter<ChatState> emit) {
    _typingTimer?.cancel();
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

  @override
  Future<void> close() async {
    _typingTimer?.cancel();
    return super.close();
  }
}
