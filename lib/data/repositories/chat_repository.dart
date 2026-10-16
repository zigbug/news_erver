/// Chat with the status-bot.
/// The concrete backend is [data/api/api_chat_repository.dart].
abstract interface class ChatRepository {
  /// Returns the bot's answer for [prompt]. The presentation layer is free to
  /// render it with a typewriter effect.
  Future<String> reply(String prompt);

  /// Starter line shown when the chat opens.
  String get greeting;

  /// Suggested questions rendered as tappable shortcuts.
  List<String> get suggestions;
}
