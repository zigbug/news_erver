import 'package:equatable/equatable.dart';

import '../../core/models/chat_message.dart';

class ChatState extends Equatable {
  const ChatState({
    this.messages = const [],
    this.thinking = false,
    this.typing = false,
    this.suggestions = const [],
  });

  final List<ChatMessage> messages;

  /// Waiting for the bot's answer (network delay).
  final bool thinking;

  /// Bot answer is being revealed character by character.
  final bool typing;

  final List<String> suggestions;

  bool get busy => thinking || typing;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? thinking,
    bool? typing,
    List<String>? suggestions,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      thinking: thinking ?? this.thinking,
      typing: typing ?? this.typing,
      suggestions: suggestions ?? this.suggestions,
    );
  }

  @override
  List<Object?> get props => [messages, thinking, typing, suggestions];
}
