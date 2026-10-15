import 'package:equatable/equatable.dart';

/// State of a single managed service (nginx, postgres, ...).
enum ServiceState {
  running('RUNNING'),
  degraded('DEGRADED'),
  stopped('STOPPED');

  const ServiceState(this.label);

  final String label;
}

class ServiceInfo extends Equatable {
  const ServiceInfo({
    required this.name,
    required this.state,
    required this.cpuPercent,
    required this.memoryMb,
  });

  final String name;
  final ServiceState state;
  final double cpuPercent;
  final double memoryMb;

  @override
  List<Object?> get props => [name, state, cpuPercent, memoryMb];
}
