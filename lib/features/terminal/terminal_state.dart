import 'package:equatable/equatable.dart';

import '../../core/models/log_entry.dart';

class TerminalState extends Equatable {
  const TerminalState({
    this.entries = const [],
    this.hidden = const {},
    this.loadingHistory = true,
    this.executing = false,
  });

  /// Full buffer, oldest first.
  final List<LogEntry> entries;

  /// Levels switched off in the filter bar.
  final Set<LogLevel> hidden;

  final bool loadingHistory;

  /// A command is currently running.
  final bool executing;

  /// Entries the filter bar lets through.
  List<LogEntry> get visible =>
      entries.where((e) => !hidden.contains(e.level)).toList(growable: false);

  bool isVisible(LogLevel level) => !hidden.contains(level);

  TerminalState copyWith({
    List<LogEntry>? entries,
    Set<LogLevel>? hidden,
    bool? loadingHistory,
    bool? executing,
  }) {
    return TerminalState(
      entries: entries ?? this.entries,
      hidden: hidden ?? this.hidden,
      loadingHistory: loadingHistory ?? this.loadingHistory,
      executing: executing ?? this.executing,
    );
  }

  @override
  List<Object?> get props => [entries, hidden, loadingHistory, executing];
}
