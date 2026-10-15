import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/server_status.dart';
import '../../data/repositories/server_repository.dart';

class StatusState extends Equatable {
  const StatusState({
    this.status,
    this.cpuHistory = const [],
    this.connected = false,
  });

  final ServerStatus? status;

  /// Rolling CPU samples (0..100) for the sparkline, oldest first.
  final List<double> cpuHistory;

  /// Whether the repository stream has produced at least one snapshot.
  final bool connected;

  @override
  List<Object?> get props => [status, cpuHistory, connected];
}

/// Mirrors the repository status stream into UI state and keeps a short CPU
/// history for the sparkline.
class StatusCubit extends Cubit<StatusState> {
  StatusCubit(this._repository) : super(const StatusState());

  static const int historyLength = 48;

  final ServerRepository _repository;
  StreamSubscription<ServerStatus>? _subscription;

  void start() {
    _subscription ??= _repository.status().listen(_onStatus);
    if (_repository.lastStatus case final last?) {
      _onStatus(last);
    }
  }

  void _onStatus(ServerStatus status) {
    final history = [...state.cpuHistory, status.cpuPercent];
    emit(
      StatusState(
        status: status,
        cpuHistory: history.length > historyLength
            ? history.sublist(history.length - historyLength)
            : history,
        connected: true,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
