import 'package:equatable/equatable.dart';

import '../../core/models/log_entry.dart';
import 'terminal_state.dart';

sealed class TerminalEvent extends Equatable {
  const TerminalEvent();

  @override
  List<Object?> get props => [];
}

/// Subscribe to the repository log stream and load recent history.
class TerminalStarted extends TerminalEvent {
  const TerminalStarted();
}

class TerminalLineReceived extends TerminalEvent {
  const TerminalLineReceived(this.entry);

  final LogEntry entry;

  @override
  List<Object?> get props => [entry];
}

class TerminalLevelToggled extends TerminalEvent {
  const TerminalLevelToggled(this.level);

  final LogLevel level;

  @override
  List<Object?> get props => [level];
}

/// Adds or removes one log source from the merged feed.
class TerminalSourceToggled extends TerminalEvent {
  const TerminalSourceToggled(this.source);

  final String source;

  @override
  List<Object?> get props => [source];
}

/// Re-selects every available source (the "ALL" chip).
class TerminalAllSourcesSelected extends TerminalEvent {
  const TerminalAllSourcesSelected();
}

class TerminalModeToggled extends TerminalEvent {
  const TerminalModeToggled(this.mode);

  final TerminalMode mode;

  @override
  List<Object?> get props => [mode];
}

class TerminalCommandSubmitted extends TerminalEvent {
  const TerminalCommandSubmitted(this.command);

  final String command;

  @override
  List<Object?> get props => [command];
}

class TerminalCleared extends TerminalEvent {
  const TerminalCleared();
}
