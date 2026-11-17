import 'package:equatable/equatable.dart';

import '../../core/models/chat_message.dart';
import '../../data/repositories/chat_repository.dart';

class ChatState extends Equatable {
  const ChatState({
    this.messages = const [],
    this.thinking = false,
    this.typing = false,
    this.suggestions = const [],
    this.models = const [],
    this.selectedModelId = '',
    this.modelsLoading = false,
    this.queuedCount = 0,
  });

  final List<ChatMessage> messages;

  /// Waiting for the bot's answer (network delay).
  final bool thinking;

  /// Bot answer is being revealed character by character.
  final bool typing;

  final List<String> suggestions;

  /// Available model options for opencode (provider/model).
  final List<ChatModelOption> models;

  /// Selected model id in form `providerID/modelID`, or empty for backend default.
  final String selectedModelId;

  final bool modelsLoading;

  /// Number of prompts waiting to be processed after the current run.
  final int queuedCount;

  bool get busy => thinking || typing;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? thinking,
    bool? typing,
    List<String>? suggestions,
    List<ChatModelOption>? models,
    String? selectedModelId,
    bool? modelsLoading,
    int? queuedCount,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      thinking: thinking ?? this.thinking,
      typing: typing ?? this.typing,
      suggestions: suggestions ?? this.suggestions,
      models: models ?? this.models,
      selectedModelId: selectedModelId ?? this.selectedModelId,
      modelsLoading: modelsLoading ?? this.modelsLoading,
      queuedCount: queuedCount ?? this.queuedCount,
    );
  }

  @override
  List<Object?> get props => [
        messages,
        thinking,
        typing,
        suggestions,
        models,
        selectedModelId,
        modelsLoading,
        queuedCount,
      ];
}
