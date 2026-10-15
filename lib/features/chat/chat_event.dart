import 'package:equatable/equatable.dart';

sealed class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => [];
}

class ChatStarted extends ChatEvent {
  const ChatStarted();
}

class ChatPromptSent extends ChatEvent {
  const ChatPromptSent(this.prompt);

  final String prompt;

  @override
  List<Object?> get props => [prompt];
}

class ChatCleared extends ChatEvent {
  const ChatCleared();
}
