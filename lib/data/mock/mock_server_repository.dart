import 'dart:async';
import 'dart:math';

import '../../core/models/log_entry.dart';
import '../../core/models/server_status.dart';
import '../../core/models/service_info.dart';
import '../../core/utils/formatters.dart';
import '../repositories/server_repository.dart';

/// Demo [ServerRepository]: no network, but real streams, real timers and real
/// state transitions, so the UI can be built and tested end to end.
class MockServerRepository implements ServerRepository {
  MockServerRepository({
    this.hostname = 'srv-01.remote.lan',
    this.os = 'Ubuntu 24.04 LTS / x86_64',
    Duration uptime = const Duration(days: 3, hours: 4, minutes: 21),
  }) : _bootedAt = DateTime.now().subtract(uptime);

  final String hostname;
  final String os;

  final _random = Random();
  final _logController = StreamController<LogEntry>.broadcast();
  final _statusController = StreamController<ServerStatus>.broadcast();

  final DateTime _bootedAt;

  Timer? _logTimer;
  Timer? _statusTimer;
  int _seq = 0;
  LinkState _link = LinkState.offline;
  ServerStatus? _last;

  double _cpu = 14;
  double _memoryMb = 3120;
  double _disk = 61;
  double _temperature = 48;

  static const double _memoryTotalMb = 8192;
  static const List<String> _sources = [
    'kernel',
    'nginx',
    'systemd',
    'agent',
    'backup',
    'cron',
    'postgres',
    'docker',
  ];

  static const List<(LogLevel, String)> _chatter = [
    (LogLevel.debug, 'heartbeat ok, rtt 12ms'),
    (LogLevel.info, 'health probe answered in 4ms'),
    (LogLevel.info, 'metric batch uploaded (24 samples)'),
    (LogLevel.debug, 'cache hit ratio 0.94'),
    (LogLevel.info, 'session token rotated'),
    (LogLevel.warn, 'retry #2 for upstream 10.0.0.14:8443'),
    (LogLevel.warn, 'disk write latency above 200ms'),
    (LogLevel.info, 'log rotation completed, 2 files archived'),
    (LogLevel.debug, 'gc pause 18ms'),
    (LogLevel.error, 'upstream 10.0.0.31 timed out after 5s'),
    (LogLevel.info, 'backup snapshot verified (sha256 ok)'),
    (LogLevel.warn, 'memory pressure elevated: 81%'),
    (LogLevel.info, 'TLS certificate valid for 42 more days'),
    (LogLevel.trace, 'syscall tracing disabled'),
  ];

  @override
  ServerStatus? get lastStatus => _last;

  @override
  Stream<LogEntry> logs() => _logController.stream;

  @override
  Stream<ServerStatus> status() => _statusController.stream;

  @override
  Future<void> connect() async {
    if (_link == LinkState.online) return;
    _link = LinkState.connecting;
    _emitStatus();
    addLog(
      LogLevel.info,
      'agent',
      'handshake started with $hostname',
    );
    await Future<void>.delayed(const Duration(milliseconds: 900));
    _link = LinkState.online;
    addLog(LogLevel.info, 'agent', 'link established, protocol v2.4');
    _emitStatus();
    _startTimers();
  }

  @override
  Future<void> disconnect() async {
    _stopTimers();
    _link = LinkState.offline;
    addLog(LogLevel.warn, 'agent', 'link closed by operator');
    _emitStatus();
  }

  @override
  Future<void> reconnect() async {
    addLog(LogLevel.info, 'agent', 'reconnect requested');
    await disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await connect();
  }

  @override
  Future<void> rebootServer() async {
    addLog(LogLevel.warn, 'systemd', 'REBOOT requested by operator');
    _stopTimers();
    _link = LinkState.connecting;
    _emitStatus();
    await Future<void>.delayed(const Duration(seconds: 2));
    addLog(LogLevel.info, 'kernel', 'stopping services...');
    await Future<void>.delayed(const Duration(seconds: 2));
    addLog(LogLevel.info, 'kernel', 'booting ...');
    await Future<void>.delayed(const Duration(seconds: 2));
    _cpu = 8;
    _memoryMb = 1800;
    _disk = 60.5;
    _temperature = 41;
    _link = LinkState.online;
    addLog(LogLevel.info, 'kernel', 'boot complete, 1842ms');
    _emitStatus();
    _startTimers();
  }

  @override
  Future<void> restartService(String name) async {
    addLog(LogLevel.warn, 'systemd', 'restarting unit $name');
    await Future<void>.delayed(const Duration(seconds: 1));
    final flaky = name.toLowerCase().contains('upstream');
    addLog(
      flaky ? LogLevel.error : LogLevel.info,
      'systemd',
      flaky ? 'unit $name failed to come up (exit 1)' : 'unit $name is active (running)',
    );
  }

  @override
  Future<void> clearCache() async {
    addLog(LogLevel.info, 'agent', 'cache directory flushed');
    await Future<void>.delayed(const Duration(milliseconds: 700));
    addLog(LogLevel.info, 'agent', 'freed 1.4 GB, index rebuilt');
    _disk = (_disk - 1.4).clamp(0, 100);
    _emitStatus();
  }

  @override
  Future<String> runCommand(String command) async {
    final raw = command.trim();
    if (raw.isEmpty) return '';
    final parts = raw.split(RegExp(r'\s+'));
    final head = parts.first.toLowerCase();
    await Future<void>.delayed(const Duration(milliseconds: 260));
    addLog(LogLevel.debug, 'shell', 'exec: $raw');

    switch (head) {
      case 'help':
        return [
          'available commands:',
          '  help              this text',
          '  status            one-line link summary',
          '  uptime            time since last boot',
          '  services          unit list with states',
          '  logs <n>          tail n lines from the buffer',
          '  whoami            current session identity',
          '  echo <text>       echo text back',
          '  clear             clear the terminal buffer',
          'destructive actions live on the CONTROL tab.',
        ].join('\n');
      case 'status':
        final s = _last;
        if (s == null) return 'no snapshot yet';
        return '${s.link.label} cpu=${s.cpuPercent.toStringAsFixed(1)}% '
            'mem=${s.memoryPercent.toStringAsFixed(1)}% '
            'disk=${s.diskUsedPercent.toStringAsFixed(1)}% '
            'load=${s.loadAverage.toStringAsFixed(2)}';
      case 'uptime':
        return uptimeOf(_last?.uptime ?? DateTime.now().difference(_bootedAt));
      case 'services':
        return (_last?.services ?? const <ServiceInfo>[])
            .map(
              (s) => '${s.state.label.padRight(8)} ${s.name.padRight(12)} '
                  'cpu=${s.cpuPercent.toStringAsFixed(1)}% mem=${s.memoryMb.round()}MB',
            )
            .join('\n');
      case 'logs':
        return 'use the terminal buffer, or `logs <n>` in a real agent';
      case 'whoami':
        return 'operator@retro-console (uid=1000)';
      case 'echo':
        return parts.skip(1).join(' ');
      case 'clear':
        return '\u0000clear';
      case 'reboot':
      case 'shutdown':
        return 'refused: destructive commands require the CONTROL tab';
      default:
        return 'command not found: $head — try `help`';
    }
  }

  @override
  Future<List<LogEntry>> fetchLogHistory({int limit = 40}) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final now = DateTime.now();
    return List.generate(limit, (i) {
      final (level, message) = _chatter[i % _chatter.length];
      return LogEntry(
        id: 'hist-${_seq++}',
        timestamp: now.subtract(Duration(seconds: (limit - i) * 3)),
        level: level,
        source: _sources[i % _sources.length],
        message: message,
      );
    });
  }

  /// Appends a line to the live log stream (also used by control actions).
  void addLog(LogLevel level, String source, String message) {
    if (_logController.isClosed) return;
    _logController.add(
      LogEntry(
        id: 'log-${_seq++}',
        timestamp: DateTime.now(),
        level: level,
        source: source,
        message: message,
      ),
    );
  }

  void _startTimers() {
    _stopTimers();
    _logTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      final (level, message) = _chatter[_random.nextInt(_chatter.length)];
      addLog(level, _sources[_random.nextInt(_sources.length)], message);
    });
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  void _stopTimers() {
    _logTimer?.cancel();
    _logTimer = null;
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  void _tick() {
    _cpu = (_cpu + _random.nextDouble() * 16 - 8).clamp(2, 97);
    _memoryMb = (_memoryMb + _random.nextDouble() * 240 - 120).clamp(900, _memoryTotalMb - 200);
    _disk = (_disk + _random.nextDouble() * 0.2 - 0.05).clamp(5, 99);
    _temperature = (_temperature + _random.nextDouble() * 3 - 1.5).clamp(35, 82);
    if (_random.nextDouble() < 0.06 && _link == LinkState.online) {
      _link = LinkState.degraded;
      addLog(LogLevel.warn, 'agent', 'link degraded: packet loss 4.2%');
    } else if (_link == LinkState.degraded && _random.nextDouble() < 0.5) {
      _link = LinkState.online;
      addLog(LogLevel.info, 'agent', 'link recovered');
    }
    _emitStatus();
  }

  void _emitStatus() {
    if (_statusController.isClosed) return;
    final status = ServerStatus(
      hostname: hostname,
      os: os,
      link: _link,
      uptime: DateTime.now().difference(_bootedAt),
      cpuPercent: _cpu,
      memoryUsedMb: _memoryMb,
      memoryTotalMb: _memoryTotalMb,
      diskUsedPercent: _disk,
      loadAverage: double.parse((_cpu / 100 * 4).toStringAsFixed(2)),
      temperature: _temperature,
      services: _services(),
      sampledAt: DateTime.now(),
    );
    _last = status;
    _statusController.add(status);
  }

  List<ServiceInfo> _services() {
    final down = _link == LinkState.offline;
    ServiceState stateFor(double failureChance) {
      if (down) return ServiceState.stopped;
      if (_random.nextDouble() < failureChance) return ServiceState.degraded;
      return ServiceState.running;
    }

    return [
      ServiceInfo(
        name: 'node-agent',
        state: down ? ServiceState.stopped : ServiceState.running,
        cpuPercent: down ? 0 : _cpu * 0.35,
        memoryMb: 184,
      ),
      ServiceInfo(
        name: 'nginx',
        state: stateFor(0.02),
        cpuPercent: down ? 0 : _cpu * 0.2,
        memoryMb: 96,
      ),
      ServiceInfo(
        name: 'postgresql',
        state: stateFor(0.02),
        cpuPercent: down ? 0 : _cpu * 0.3,
        memoryMb: 512,
      ),
      ServiceInfo(
        name: 'redis',
        state: stateFor(0.03),
        cpuPercent: down ? 0 : _cpu * 0.1,
        memoryMb: 128,
      ),
      ServiceInfo(
        name: 'upstream-sync',
        state: stateFor(0.18),
        cpuPercent: down ? 0 : _cpu * 0.05,
        memoryMb: 64,
      ),
      ServiceInfo(
        name: 'sshd',
        state: down ? ServiceState.stopped : ServiceState.running,
        cpuPercent: down ? 0 : 0.6,
        memoryMb: 12,
      ),
    ];
  }

  @override
  void dispose() {
    _stopTimers();
    _logController.close();
    _statusController.close();
  }
}
