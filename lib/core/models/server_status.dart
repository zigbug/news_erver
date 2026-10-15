import 'package:equatable/equatable.dart';

import 'service_info.dart';

/// Link state between this app and the remote server.
enum LinkState {
  offline('OFFLINE'),
  connecting('CONNECTING'),
  online('ONLINE'),
  degraded('DEGRADED');

  const LinkState(this.label);

  final String label;

  bool get isUp => this == LinkState.online || this == LinkState.degraded;
}

/// Snapshot of the remote machine, refreshed on a timer / stream.
class ServerStatus extends Equatable {
  const ServerStatus({
    required this.hostname,
    required this.os,
    required this.link,
    required this.uptime,
    required this.cpuPercent,
    required this.memoryUsedMb,
    required this.memoryTotalMb,
    required this.diskUsedPercent,
    required this.loadAverage,
    required this.temperature,
    required this.services,
    required this.sampledAt,
  });

  final String hostname;
  final String os;
  final LinkState link;
  final Duration uptime;
  final double cpuPercent;
  final double memoryUsedMb;
  final double memoryTotalMb;
  final double diskUsedPercent;

  /// 1-minute load average.
  final double loadAverage;

  /// SoC/CPU temperature in degrees Celsius.
  final double temperature;

  final List<ServiceInfo> services;
  final DateTime sampledAt;

  double get memoryPercent =>
      memoryTotalMb <= 0 ? 0 : (memoryUsedMb / memoryTotalMb) * 100;

  String get uptimeLabel {
    final d = uptime;
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    if (days > 0) return '${days}d ${hours}h ${minutes}m';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  @override
  List<Object?> get props => [
    hostname,
    os,
    link,
    uptime,
    cpuPercent,
    memoryUsedMb,
    memoryTotalMb,
    diskUsedPercent,
    loadAverage,
    temperature,
    services,
    sampledAt,
  ];
}
