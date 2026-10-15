import 'package:equatable/equatable.dart';

/// Severity of a single terminal log line.
enum LogLevel {
  trace('TRACE', 0),
  debug('DEBUG', 1),
  info('INFO', 2),
  warn('WARN', 3),
  error('ERROR', 4);

  const LogLevel(this.label, this.severity);

  final String label;
  final int severity;

  static LogLevel byName(String? name) => values.firstWhere(
    (l) => l.name == name,
    orElse: () => LogLevel.info,
  );
}

/// One line in the server log stream.
class LogEntry extends Equatable {
  const LogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
  });

  final String id;
  final DateTime timestamp;
  final LogLevel level;
  final String source;
  final String message;

  /// `HH:mm:ss` used by the terminal view.
  String get clock {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(timestamp.hour)}:${two(timestamp.minute)}:${two(timestamp.second)}';
  }

  @override
  List<Object?> get props => [id, timestamp, level, source, message];
}
