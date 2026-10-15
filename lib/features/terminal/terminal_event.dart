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
