import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/log_entry.dart';
import '../../data/repositories/server_repository.dart';
import 'terminal_event.dart';
import 'terminal_state.dart';

/// Owns the terminal buffer: live log lines from the repository plus the output
/// of commands typed at the prompt.
class TerminalBloc extends Bloc<TerminalEvent, TerminalState> {
  TerminalBloc(this._repository) : super(const TerminalState()) {
    on<TerminalStarted>(_onStarted);
    on<TerminalLineReceived>(_onLineReceived);
    on<TerminalLevelToggled>(_onLevelToggled);
    on<TerminalSourceToggled>(_onSourceToggled);
    on<TerminalAllSourcesSelected>(_onAllSourcesSelected);
    on<TerminalModeToggled>(_onModeToggled);
    on<TerminalCommandSubmitted>(_onCommandSubmitted);
    on<TerminalCleared>(_onCleared);
  }

  static const int maxEntries = 600;

  final ServerRepository _repository;
  StreamSubscription<LogEntry>? _subscription;

  Future<void> _onStarted(
    TerminalStarted event,
    Emitter<TerminalState> emit,
  ) async {
    _subscription ??= _repository.logs().listen(
      (entry) => add(TerminalLineReceived(entry)),
    );
    final available = await _repository.availableLogSources();
    final selected = available.toSet();
    _repository.setLogSources(available);
    emit(
      state.copyWith(availableSources: available, selectedSources: selected),
    );
    await _reloadHistory(emit, selectedSources: selected);
  }

  void _onLineReceived(
    TerminalLineReceived event,
    Emitter<TerminalState> emit,
  ) {
    emit(state.copyWith(entries: _append(state.entries, [event.entry])));
  }

  void _onLevelToggled(
    TerminalLevelToggled event,
    Emitter<TerminalState> emit,
  ) {
    final hidden = {...state.hidden};
    if (!hidden.remove(event.level)) hidden.add(event.level);
    emit(state.copyWith(hidden: hidden));
  }

  Future<void> _onSourceToggled(
    TerminalSourceToggled event,
    Emitter<TerminalState> emit,
  ) async {
    final selected = {...state.selectedSources};
    if (!selected.remove(event.source)) selected.add(event.source);
    // Never allow an empty feed: the last chip stays on.
    if (selected.isEmpty) return;
    await _applySources(emit, selected);
  }

  Future<void> _onAllSourcesSelected(
    TerminalAllSourcesSelected event,
    Emitter<TerminalState> emit,
  ) async {
    final selected = state.availableSources.toSet();
    if (selected.isEmpty || selected.length == state.selectedSources.length) {
      return;
    }
    await _applySources(emit, selected);
  }

  /// Persists the new selection on the repository and reloads the buffer so the
  /// feed reflects exactly the chosen sources (no stale lines).
  Future<void> _applySources(
    Emitter<TerminalState> emit,
    Set<String> selected,
  ) async {
    final ordered = state.availableSources
        .where(selected.contains)
        .toList(growable: false);
    _repository.setLogSources(ordered);
    emit(
      state.copyWith(
        selectedSources: selected,
        entries: const [],
        loadingHistory: true,
      ),
    );
    await _reloadHistory(emit, selectedSources: selected);
  }

  Future<void> _reloadHistory(
    Emitter<TerminalState> emit, {
    required Set<String> selectedSources,
  }) async {
    List<LogEntry> history;
    try {
      history = await _repository.fetchLogHistory();
    } catch (e) {
      history = [
        _line(LogLevel.error, 'history unavailable: $e', source: 'hub'),
      ];
    }
    emit(
      state.copyWith(
        entries: _append(state.entries, history),
        loadingHistory: false,
        selectedSources: selectedSources,
      ),
    );
  }

  void _onModeToggled(TerminalModeToggled event, Emitter<TerminalState> emit) {
    if (state.mode == event.mode) return;
    emit(state.copyWith(mode: event.mode));
  }

  Future<void> _onCommandSubmitted(
    TerminalCommandSubmitted event,
    Emitter<TerminalState> emit,
  ) async {
    final command = event.command.trim();
    if (command.isEmpty || state.executing) return;

    emit(
      state.copyWith(
        entries: _append(state.entries, [
          _line(LogLevel.info, '\$ $command', source: 'prompt'),
        ]),
        executing: true,
      ),
    );

    final output = await _runCommand(command);

    if (output == '\u0000clear') {
      emit(state.copyWith(entries: const [], executing: false));
      return;
    }

    final lines = output.isEmpty
        ? <LogEntry>[_line(LogLevel.info, '(no output)')]
        : output
              .split('\n')
              .map((l) => _line(LogLevel.trace, l))
              .toList(growable: false);

    emit(
      state.copyWith(entries: _append(state.entries, lines), executing: false),
    );
  }

  void _onCleared(TerminalCleared event, Emitter<TerminalState> emit) {
    emit(state.copyWith(entries: const []));
  }

  Future<String> _runCommand(String command) async {
    try {
      return await _repository.runCommand(command);
    } catch (e) {
      return 'command failed: $e';
    }
  }

  List<LogEntry> _append(List<LogEntry> base, List<LogEntry> extra) {
    final merged = [...base, ...extra];
    if (merged.length <= maxEntries) return merged;
    return merged.sublist(merged.length - maxEntries);
  }

  LogEntry _line(LogLevel level, String message, {String source = 'shell'}) =>
      LogEntry(
        id: 'cmd-${DateTime.now().microsecondsSinceEpoch}-${message.hashCode}',
        timestamp: DateTime.now(),
        level: level,
        source: source,
        message: message,
      );

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
