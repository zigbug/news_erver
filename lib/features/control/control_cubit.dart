import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/server_repository.dart';
import 'control_state.dart';

/// Runs destructive and link operations one at a time and keeps a small result
/// log for the CONTROL tab.
class ControlCubit extends Cubit<ControlState> {
  ControlCubit(this._repository) : super(const ControlState());

  final ServerRepository _repository;

  Future<void> run(ControlAction action, {String? service}) {
    return _run(
      action,
      detail: switch (action) {
        ControlAction.restartService => service ?? 'node-agent',
        ControlAction.reboot => 'power cycle requested',
        ControlAction.clearCache => 'flush caches',
        ControlAction.connect => 'link up',
        ControlAction.disconnect => 'link down',
        ControlAction.reconnect => 'link bounce',
      },
      body: () => switch (action) {
        ControlAction.connect => _repository.connect(),
        ControlAction.disconnect => _repository.disconnect(),
        ControlAction.reconnect => _repository.reconnect(),
        ControlAction.reboot => _repository.rebootServer(),
        ControlAction.restartService => _repository.restartService(service ?? 'node-agent'),
        ControlAction.clearCache => _repository.clearCache(),
      },
    );
  }

  Future<void> _run(
    ControlAction action, {
    required String detail,
    required Future<void> Function() body,
  }) async {
    if (state.busy != null) return;
    emit(ControlState(busy: action, results: state.results, lastError: null));
    try {
      await body();
      emit(
        ControlState(
          results: [
            ActionResult(
              action: action,
              detail: detail,
              ok: true,
              at: DateTime.now(),
            ),
            ...state.results,
          ].take(12).toList(growable: false),
        ),
      );
    } catch (e) {
      emit(
        ControlState(
          results: state.results,
          lastError: '${action.label}: $e',
        ),
      );
    }
  }
}
