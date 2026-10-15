import 'package:equatable/equatable.dart';

/// Operations offered by the CONTROL tab.
enum ControlAction {
  connect('CONNECT', false, 'установить линию'),
  disconnect('DISCONNECT', false, 'разорвать линию'),
  reconnect('RECONNECT', false, 'переустановить линию'),
  restartService('RESTART SERVICE', false, 'рестарт одного юнита'),
  clearCache('CLEAR CACHE', false, 'сбросить кэш'),
  reboot('REBOOT', true, 'перезагрузка сервера');

  const ControlAction(this.label, this.destructive, this.hint);

  final String label;
  final bool destructive;
  final String hint;
}

class ActionResult extends Equatable {
  const ActionResult({
    required this.action,
    required this.detail,
    required this.ok,
    required this.at,
  });

  final ControlAction action;
  final String detail;
  final bool ok;
  final DateTime at;

  @override
  List<Object?> get props => [action, detail, ok, at];
}

class ControlState extends Equatable {
  const ControlState({
    this.busy,
    this.results = const [],
    this.lastError,
  });

  /// Action currently running, if any.
  final ControlAction? busy;

  /// Recent history, newest first.
  final List<ActionResult> results;

  final String? lastError;

  bool isBusy(ControlAction action) => busy == action;

  @override
  List<Object?> get props => [busy, results, lastError];
}
