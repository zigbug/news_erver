import 'package:equatable/equatable.dart';

enum ChatRole {
  user('USER', '>'),
  bot('BOT', '<'),
  system('SYS', '*');

  const ChatRole(this.label, this.prompt);

  final String label;
  final String prompt;
}

/// One bubble in the terminal-style chat with the server bot.
class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
    this.pending = false,
  });

  final String id;
  final ChatRole role;
  final String text;
  final DateTime timestamp;

  /// Bot is still "typing" this message.
  final bool pending;

  ChatMessage copyWith({String? text, bool? pending}) => ChatMessage(
    id: id,
    role: role,
    text: text ?? this.text,
    timestamp: timestamp,
    pending: pending ?? this.pending,
  );

  @override
  List<Object?> get props => [id, role, text, timestamp, pending];
}
