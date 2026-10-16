import 'package:equatable/equatable.dart';

import '../../core/models/log_entry.dart';

/// Two faces of the terminal screen: the live server journal, or an interactive
/// read-only shell prompt. The user switches between them.
enum TerminalMode {
  journal('JOURNAL'),
  shell('SHELL');

  const TerminalMode(this.label);

  final String label;
}

class TerminalState extends Equatable {
  const TerminalState({
    this.entries = const [],
    this.hidden = const {},
    this.mode = TerminalMode.journal,
    this.loadingHistory = true,
    this.executing = false,
    this.availableSources = const [],
    this.selectedSources = const {},
  });

  /// Full buffer, oldest first.
  final List<LogEntry> entries;

  /// Levels switched off in the filter bar.
  final Set<LogLevel> hidden;

  /// Which face of the terminal is shown.
  final TerminalMode mode;

  final bool loadingHistory;

  /// A command is currently running.
  final bool executing;

  /// Log sources the hub can serve (chips in the filter bar).
  final List<String> availableSources;

  /// Subset of [availableSources] currently queried for the merged feed.
  final Set<String> selectedSources;

  /// Entries the filter bar lets through (current mode only).
  List<LogEntry> get visible => entries
      .where((e) => _matchesMode(e) && !hidden.contains(e.level))
      .toList(growable: false);

  bool _matchesMode(LogEntry entry) {
    final isShell = entry.source == 'prompt' || entry.source == 'shell';
    return mode == TerminalMode.shell ? isShell : !isShell;
  }

  bool isVisible(LogLevel level) => !hidden.contains(level);

  bool isSourceSelected(String source) => selectedSources.contains(source);

  /// True when every available source is selected.
  bool get allSourcesSelected =>
      availableSources.isNotEmpty &&
      selectedSources.length == availableSources.length;

  TerminalState copyWith({
    List<LogEntry>? entries,
    Set<LogLevel>? hidden,
    TerminalMode? mode,
    bool? loadingHistory,
    bool? executing,
    List<String>? availableSources,
    Set<String>? selectedSources,
  }) {
    return TerminalState(
      entries: entries ?? this.entries,
      hidden: hidden ?? this.hidden,
      mode: mode ?? this.mode,
      loadingHistory: loadingHistory ?? this.loadingHistory,
      executing: executing ?? this.executing,
      availableSources: availableSources ?? this.availableSources,
      selectedSources: selectedSources ?? this.selectedSources,
    );
  }

  @override
  List<Object?> get props => [
    entries,
    hidden,
    mode,
    loadingHistory,
    executing,
    availableSources,
    selectedSources,
  ];
}
