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

/// Toggles every available source: all on if not all selected, all off if they
/// already are (the "ALL" chip).
class TerminalAllSourcesToggled extends TerminalEvent {
  const TerminalAllSourcesToggled();
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
