import '../../core/models/chat_message.dart';

class ChatModelOption {
  const ChatModelOption({
    required this.providerID,
    required this.modelID,
    required this.name,
  });

  final String providerID;
  final String modelID;
  final String name;

  String get id => '$providerID/$modelID';
}

/// Chat with the opencode agent running on the hub.
/// The concrete backend is [data/api/opencode_chat_repository.dart].
abstract interface class ChatRepository {
  /// Past transcript of this chat session, oldest first.
  Future<List<ChatMessage>> history();

  /// Sends [prompt] and streams the answer back as it is generated.
  ///
  /// [model] may specify `{providerID, modelID}` for opencode 2.3.x.
  /// Every event carries the answer accumulated so far; the stream closes when
  /// the agent finishes, and errors when the link dies mid-generation.
  Stream<String> reply(String prompt, {Map<String, String>? model});

  /// Asks the agent to stop the run in progress. Safe to call when nothing
  /// is running — a no-op that still resolves.
  Future<void> stop();

  /// Drops the current session so the next conversation starts fresh.
  Future<void> clear();

  /// Available chat models/providers, if the backend exposes them.
  Future<List<ChatModelOption>> availableModels();

  /// Starter line shown when the chat opens.
  String get greeting;

  /// Suggested questions rendered as tappable shortcuts.
  List<String> get suggestions;
}
