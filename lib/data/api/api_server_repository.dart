import 'dart:async';

import '../../core/logging/app_logger.dart';
import '../../core/models/log_entry.dart';
import '../../core/models/server_status.dart';
import '../../core/models/service_info.dart';
import '../../core/utils/formatters.dart';
import '../repositories/server_repository.dart';
import 'hub_api.dart';

/// [ServerRepository] backed by the direct server_hub REST API.
///
/// The hub has no streaming endpoint, so this implementation polls `/status`
/// and `/logs` on timers and pushes the results into long-lived broadcast
/// streams. Destructive operations map onto the hub's action allowlist.
class ApiServerRepository implements ServerRepository {
  ApiServerRepository(this._api);

  /// Default log source for the terminal tail (a systemd unit or container).
  static const String defaultLogSource = 'server_hub';

  /// Built-in source list used when `GET /logs/sources` is unreachable. Kept in
  /// the same order the hub reports them (systemd units, then containers).
  static const List<String> fallbackLogSources = [
    'server_hub',
    'nginx',
    'docker',
    'searxng-mcp',
    'mtprotoproxy',
    'ssh',
    'projects-feed.timer',
    'assistant-backend-1',
    'assistant-mcp-1',
    'ai-server',
    'mtg',
    'ntfy',
    'searxng',
  ];

  /// Sentinel used by [ServerStatus.temperature] when the host exposes no
  /// thermal sensor (a VPS does not). The STATUS screen renders `—` for 0.
  static const double noTemperature = 0;

  /// systemd units that map onto a dedicated hub action.
  static const Map<String, String> _unitActions = {
    'nginx': 'restart_nginx',
    'docker': 'restart_docker',
    'mtprotoproxy': 'restart_mtproto',
    'searxng-mcp': 'restart_searx_mcp',
  };

  /// Docker containers accepted by the `restart_container` action.
  static const List<String> _containers = [
    'assistant-backend-1',
    'assistant-mcp-1',
    'ai-server',
    'mtg',
    'ntfy',
    'searxng',
  ];

  final HubApi _api;

  final _statusController = StreamController<ServerStatus>.broadcast();
  final _logController = StreamController<LogEntry>.broadcast();

  Timer? _statusTimer;
  Timer? _logTimer;
  bool _polling = false;

  LinkState _link = LinkState.offline;
  Map<String, dynamic>? _raw;
  ServerStatus? _last;

  int _lastLogTs = 0;
  final Set<String> _seenLogs = {};

  /// `source|message` keys of the lines served on the previous `/logs` tick.
  /// The hub re-sends the same health-check block every poll with a fresh
  /// timestamp (so a ts-based set never dedupes it), and the lines come from
  /// many services in turn. A line is forwarded only when its `source|message`
  /// was absent from the previous tick's block — i.e. some result changed
  /// (200 → 400) — while an unchanged rotating block is swallowed.
  final Set<String> _tickKeys = {};

  /// True while the log tail is failing, so the outage is reported once
  /// instead of on every tick (the ticks themselves are quiet).
  bool _logPollDown = false;

  @override
  ServerStatus? get lastStatus => _last;

  /// Log sources currently tailed by [logs] (changeable before connecting).
  @override
  List<String> get logSources => List.unmodifiable(_logSources);
  List<String> _logSources = const [defaultLogSource];

  /// Resets the cursor whenever the source set changes so the feed restarts
  /// cleanly (no stale lines from the previous selection).
  @override
  void setLogSources(List<String> sources) {
    final next = <String>[];
    for (final raw in sources) {
      final source = raw.trim();
      if (source.isNotEmpty && !next.contains(source)) next.add(source);
    }
    if (_sameSources(next, _logSources)) return;
    _logSources = next;
    _lastLogTs = 0;
    _seenLogs.clear();
    _tickKeys.clear();
    _logPollDown = false;
  }

  @override
  Future<List<String>> availableLogSources() async {
    try {
      final json = await _api.get('/logs/sources', quiet: true);
      final raw = json['sources'];
      if (raw is List) {
        final names = <String>[];
        for (final item in raw) {
          final name = item is Map ? item['name'] : item;
          if (name is String && name.isNotEmpty) names.add(name);
        }
        if (names.isNotEmpty) return names;
      }
    } catch (e) {
      talker.warning('log sources unavailable → local list: $e');
    }
    return fallbackLogSources;
  }

  @override
  Future<void> registerDevice(String token) async {
    final value = token.trim();
    if (value.isEmpty) return;
    await _api.post('/devices', body: {'token': value, 'platform': 'android'});
  }

  static bool _sameSources(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (final source in a) {
      if (!b.contains(source)) return false;
    }
    return true;
  }

  @override
  Stream<LogEntry> logs() => _logController.stream;

  @override
  Stream<ServerStatus> status() => _statusController.stream;

  @override
  Future<void> connect() async {
    if (_link == LinkState.online) return;
    _link = LinkState.connecting;
    try {
      await _refreshStatus();
    } catch (e) {
      _link = LinkState.offline;
      _emitOffline();
      talker.warning('connect failed → offline: $e');
      rethrow;
    }
    _link = LinkState.online;
    _emitCurrent();
    _startTimers();
    talker.info('connected · ${_last?.hostname ?? ""}');
  }

  @override
  Future<void> disconnect() async {
    _stopTimers();
    _link = LinkState.offline;
    _emitOffline();
  }

  @override
  Future<void> reconnect() async {
    await disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await connect();
  }

  @override
  Future<void> rebootServer() => _run('reboot');

  @override
  Future<void> restartService(String name) async {
    final unit = _unitActions[name];
    if (unit != null) {
      await _run(unit);
      return;
    }
    if (_containers.contains(name)) {
      await _run('restart_container', body: {'name': name});
      return;
    }
    throw HubApiException(null, 'для «$name» нет действия на хабе');
  }

  @override
  Future<void> clearCache() =>
      throw const HubApiException(null, 'сброс кэша не поддерживается хабом');

  @override
  Future<String> runCommand(String command) async {
    final raw = command.trim();
    if (raw.isEmpty) return '';
    final parts = raw.split(RegExp(r'\s+'));
    switch (parts.first.toLowerCase()) {
      case 'help':
        return [
          'read-only commands proxied to the hub:',
          '  help            this text',
          '  status          one-line snapshot',
          '  uptime          time since boot',
          '  services        docker + systemd units',
          '  logs <n>        tail n lines from /logs',
          '  whoami          session identity',
          '  echo <text>     echo text back',
          '  clear           clear the buffer',
          'destructive actions live on the CONTROL tab.',
        ].join('\n');
      case 'status':
        final s = _last;
        if (s == null) return 'ожидание телеметрии (connect?)';
        return '${s.link.label} cpu=${s.cpuPercent.toStringAsFixed(1)}% '
            'mem=${s.memoryPercent.toStringAsFixed(1)}% '
            'disk=${s.diskUsedPercent.toStringAsFixed(1)}% '
            'load=${s.loadAverage.toStringAsFixed(2)}';
      case 'uptime':
        final s = _last;
        return s == null ? 'нет данных' : uptimeOf(s.uptime);
      case 'services':
        final services = _last?.services ?? const <ServiceInfo>[];
        if (services.isEmpty) return 'нет данных';
        return services
            .map((s) => '${s.state.label.padRight(8)} ${s.name}')
            .join('\n');
      case 'logs':
        final limit = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 20;
        return _tailText(limit);
      case 'whoami':
        return 'operator@hub-console';
      case 'echo':
        return parts.skip(1).join(' ');
      case 'clear':
        return '\u0000clear';
      case 'reboot':
      case 'shutdown':
        return 'refused: destructive commands require the CONTROL tab';
      default:
        return 'command not found: ${parts.first} — try `help`';
    }
  }

  @override
  Future<List<LogEntry>> fetchLogHistory({int limit = 40}) async {
    if (_logSources.isEmpty) return const [];
    final json = await _api.get('/logs', query: _logQuery(limit));
    final lines = _parseLogLines(json);
    _seedLogCursor(lines);
    return lines;
  }

  @override
  void dispose() {
    _stopTimers();
    _statusController.close();
    _logController.close();
  }

  // ------------------------------------------------------------- internals

  Future<void> _run(String action, {Object? body}) =>
      _api.post('/actions/$action', body: body);

  Future<void> _pollStatus() async {
    try {
      await _refreshStatus(quiet: true);
      if (_link != LinkState.online) {
        _link = LinkState.online;
        _emitCurrent();
      }
    } catch (e) {
      if (_link == LinkState.online) {
        _link = LinkState.degraded;
        _emitCurrent();
        talker.warning('status poll failed → degraded: $e');
      }
    }
  }

  Future<String> _tailText(int limit) async {
    if (_logSources.isEmpty) return '(нет выбранных источников)';
    final json = await _api.get('/logs', query: _logQuery(limit));
    final lines = _parseLogLines(json);
    if (lines.isEmpty) return '(пусто)';
    return lines
        .map((e) => '${e.clock} ${e.level.label.padRight(5)} ${e.message}')
        .join('\n');
  }

  /// Query params for `/logs`. Always sends the whole selection as a
  /// comma-separated `sources` list; the hub returns the merged feed (or a
  /// single-source payload when only one is selected).
  Map<String, String> _logQuery(int limit) => {
    'sources': _logSources.join(','),
    'limit': '$limit',
  };

  /// [quiet] keeps the routine status poll out of the Talker history; the
  /// caller logs its own transition instead (see [connect], [_pollStatus]).
  Future<void> _refreshStatus({bool quiet = false}) async {
    final json = await _api.get('/status', quiet: quiet);
    _raw = json;
    _emitCurrent();
  }

  void _emitCurrent() {
    final raw = _raw;
    if (raw == null || _statusController.isClosed) return;
    final status = _parseStatus(raw);
    _last = status;
    _statusController.add(status);
  }

  /// Publishes a placeholder snapshot so the UI visibly drops to OFFLINE.
  void _emitOffline() {
    if (_statusController.isClosed) return;
    final status = ServerStatus(
      hostname: _last?.hostname ?? 'unknown',
      os: _last?.os ?? '',
      link: LinkState.offline,
      uptime: Duration.zero,
      cpuPercent: 0,
      memoryUsedMb: 0,
      memoryTotalMb: 0,
      diskUsedPercent: 0,
      loadAverage: 0,
      temperature: noTemperature,
      services: const [],
      sampledAt: DateTime.now(),
    );
    _last = status;
    _statusController.add(status);
  }

  void _startTimers() {
    _stopTimers();
    _polling = true;
    _scheduleStatusPoll();
    _scheduleLogPoll();
  }

  /// Schedules the next `/status` poll from the *current* connection settings,
  /// so editing the interval in SETUP takes effect without rebuilding the repo.
  void _scheduleStatusPoll() {
    _statusTimer?.cancel();
    final seconds = _api.connection.pollIntervalSeconds.clamp(1, 3600);
    _statusTimer = Timer(Duration(seconds: seconds), () async {
      await _pollStatus();
      if (_polling) _scheduleStatusPoll();
    });
  }

  /// Same as [_scheduleStatusPoll] but for the (heavier) merged log feed: it
  /// queries every selected source per tick, so it has its own interval.
  void _scheduleLogPoll() {
    _logTimer?.cancel();
    final seconds = _api.connection.logIntervalSeconds.clamp(2, 3600);
    _logTimer = Timer(Duration(seconds: seconds), () async {
      await _pollLogs();
      if (_polling) _scheduleLogPoll();
    });
  }

  void _stopTimers() {
    _polling = false;
    _statusTimer?.cancel();
    _statusTimer = null;
    _logTimer?.cancel();
    _logTimer = null;
  }

  Future<void> _pollLogs() async {
    if (_logController.isClosed || _logSources.isEmpty) return;
    try {
      final json = await _api.get(
        '/logs',
        quiet: true,
        query: {
          ..._logQuery(200),
          if (_lastLogTs > 0) 'since_ms': '$_lastLogTs',
        },
      );
      final lines = _parseLogLines(json);
      final tick = <String>{};
      for (final entry in lines) {
        final tickKey = _logSignature(entry);
        tick.add(tickKey);
        if (_tickKeys.contains(tickKey)) {
          // Unchanged since the previous poll — part of the rotating
          // health-check block the hub re-sends every tick.
          continue;
        }
        if (_seenLogs.add(_logKey(entry))) {
          _logController.add(entry);
          if (entry.timestamp.millisecondsSinceEpoch > _lastLogTs) {
            _lastLogTs = entry.timestamp.millisecondsSinceEpoch;
          }
        }
      }
      _tickKeys
        ..clear()
        ..addAll(tick);
      if (_seenLogs.length > 2000) {
        // The tick-set, not this ts-set, carries the dedupe across polls;
        // dropping it only loses exact-duplicate protection within a poll.
        _seenLogs.clear();
      }
      _logPollDown = false;
    } catch (e) {
      // Ticks are quiet (they'd flood the history), so report the outage once.
      // The next tick retries; recovery clears the flag.
      if (!_logPollDown) {
        _logPollDown = true;
        talker.warning('log poll failed → tail paused: $e');
      }
    }
  }

  void _seedLogCursor(List<LogEntry> lines) {
    for (final entry in lines) {
      _seenLogs.add(_logKey(entry));
      final ts = entry.timestamp.millisecondsSinceEpoch;
      if (ts > _lastLogTs) _lastLogTs = ts;
    }
  }

  String _logKey(LogEntry entry) =>
      '${entry.timestamp.millisecondsSinceEpoch}|${entry.source}|${entry.message}';

  /// Volatile bits the hub bakes into every log line: an ISO timestamp and a
  /// `h:mm:ss.ffffff` request duration. They differ on every poll even when the
  /// result is identical, so they are blanked before comparison.
  static final RegExp _volatileIso = RegExp(
    r'\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?',
  );
  static final RegExp _volatileDuration = RegExp(r'\d+:\d{2}:\d{2}(?:\.\d+)?');
  static final RegExp _volatileMillis = RegExp(r'\d+(?:\.\d+)?\s?(?:ms|µs|us)\b');

  /// Signature used to detect that a source's result actually changed between
  /// polls: the message with volatile timestamps/durations stripped, so
  /// `... [200] /health` stays stable while `[200]` → `[400]` does not.
  String _logSignature(LogEntry entry) {
    final normalized = entry.message
        .replaceAll(_volatileIso, 'TS')
        .replaceAll(_volatileDuration, 'DUR')
        .replaceAll(_volatileMillis, 'DUR');
    return '${entry.source}|${entry.level.name}|$normalized';
  }

  List<LogEntry> _parseLogLines(Map<String, dynamic> json) {
    final raw = json['lines'];
    if (raw is! List) return const [];
    final out = <LogEntry>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) continue;
      final line = item.cast<String, dynamic>();
      final ts = (line['ts'] as num?)?.toInt();
      final time = line['time'] as String?;
      final timestamp = ts != null
          ? DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true).toLocal()
          : (time != null ? DateTime.parse(time).toLocal() : DateTime.now());
      out.add(
        LogEntry(
          id: 'hub-$ts-$i',
          timestamp: timestamp,
          level: LogLevel.byName(line['level'] as String?),
          source:
              (line['source'] as String?) ??
              (_logSources.isNotEmpty ? _logSources.first : defaultLogSource),
          message: (line['message'] as String?) ?? '',
        ),
      );
    }
    return out;
  }

  ServerStatus _parseStatus(Map<String, dynamic> json) {
    final memory =
        (json['memory'] as Map?)?.cast<String, dynamic>() ?? const {};
    final disk = (json['disk'] as Map?)?.cast<String, dynamic>() ?? const {};
    final load = (json['load'] as List?) ?? const [];
    final sampledAt = json['time'] is String
        ? DateTime.parse(json['time'] as String).toLocal()
        : DateTime.now();

    return ServerStatus(
      hostname: (json['host'] as String?) ?? 'unknown',
      os: (json['os'] as String?) ?? '',
      link: _link,
      uptime: Duration(seconds: (json['uptimeSec'] as num?)?.toInt() ?? 0),
      cpuPercent: (json['cpuPct'] as num?)?.toDouble() ?? 0,
      memoryUsedMb: (memory['usedMb'] as num?)?.toDouble() ?? 0,
      memoryTotalMb: (memory['totalMb'] as num?)?.toDouble() ?? 0,
      diskUsedPercent: (disk['usedPct'] as num?)?.toDouble() ?? 0,
      loadAverage: load.isNotEmpty ? (load.first as num).toDouble() : 0,
      temperature: noTemperature,
      services: _parseServices(json),
      sampledAt: sampledAt,
    );
  }

  List<ServiceInfo> _parseServices(Map<String, dynamic> json) {
    final out = <ServiceInfo>[];
    final docker = (json['docker'] as List?) ?? const [];
    for (final item in docker) {
      if (item is! Map) continue;
      final c = item.cast<String, dynamic>();
      out.add(
        ServiceInfo(
          name: (c['name'] as String?) ?? 'container',
          state: c['running'] == true
              ? ServiceState.running
              : ServiceState.stopped,
          cpuPercent: 0,
          memoryMb: 0,
        ),
      );
    }
    final systemd = (json['systemd'] as List?) ?? const [];
    for (final item in systemd) {
      if (item is! Map) continue;
      final u = item.cast<String, dynamic>();
      out.add(
        ServiceInfo(
          name: (u['unit'] as String?) ?? 'unit',
          state: u['active'] == true
              ? ServiceState.running
              : ServiceState.stopped,
          cpuPercent: 0,
          memoryMb: 0,
        ),
      );
    }
    return out;
  }
}
