import '../../core/models/chat_message.dart';

/// Chat with the opencode agent running on the hub.
/// The concrete backend is [data/api/opencode_chat_repository.dart].
abstract interface class ChatRepository {
  /// Past transcript of this chat session, oldest first.
  ///
  /// Empty when the conversation just started (or the hub is unreachable —
  /// the bloc turns that into a system line).
  Future<List<ChatMessage>> history();

  /// Sends [prompt] and streams the answer back as it is generated.
  ///
  /// Every event carries the answer accumulated so far; the stream closes when
  /// the agent finishes, and errors when the link dies mid-generation.
  Stream<String> reply(String prompt);

  /// Drops the current session so the next conversation starts fresh.
  Future<void> clear();

  /// Starter line shown when the chat opens.
  String get greeting;

  /// Suggested questions rendered as tappable shortcuts.
  List<String> get suggestions;
}
