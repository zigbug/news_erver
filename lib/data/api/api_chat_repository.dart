import '../../core/models/log_entry.dart';
import '../../core/models/server_status.dart';
import '../../core/utils/formatters.dart';
import '../repositories/chat_repository.dart';
import '../repositories/server_repository.dart';
import 'hub_api.dart';

/// Status-bot backed by the hub: it answers questions by reading live
/// telemetry (`/status`, `/logs`) rather than a language model. Read-only — any
/// state change is deferred to the CONTROL tab.
class ApiChatRepository implements ChatRepository {
  ApiChatRepository(this._api, this._server);

  final HubApi _api;
  final ServerRepository _server;

  @override
  String get greeting =>
      'status-bot online. спрашиваю хаб вживую: status, services, logs, load.\n'
      'всё, что меняет состояние — на вкладке CONTROL.';

  @override
  List<String> get suggestions => ['как дела?', 'status', 'services', 'logs'];

  @override
  Future<String> reply(String prompt) async {
    final q = prompt.toLowerCase().trim();
    bool has(List<String> keys) => keys.any(q.contains);

    try {
      if (has([
        'как дела',
        'состояние',
        'статус',
        'status',
        'нагрузк',
        'cpu',
      ])) {
        return _describe(await _fetchStatus());
      }
      if (has(['сервис', 'service', 'nginx', 'docker', 'unit', 'контейнер'])) {
        return _services(await _fetchStatus());
      }
      if (has(['лог', 'log', 'ошибк', 'error'])) {
        return _logs();
      }
      if (has(['аптайм', 'uptime', 'работает'])) {
        final s = await _fetchStatus();
        return 'uptime: ${uptimeOf(s.uptime)}\nlink: ${s.link.label}';
      }
      if (has(['перезагруз', 'reboot', 'restart', 'рестарт'])) {
        return 'это деструктивная операция. открой CONTROL и подтверди действие — '
            'из чата я её не выполняю.';
      }
      if (has(['help', 'команд', 'что умеешь'])) {
        return 'я читаю хаб. спроси про: status, services, logs, uptime.';
      }
      if (has(['привет', 'hello', 'hi', 'здравств'])) {
        return 'привет, оператор. линия до хаба активна.';
      }
    } on HubApiException catch (e) {
      return 'хаб недоступен: $e';
    }

    return 'не распознал запрос. попробуй: status, services, logs, uptime.';
  }

  Future<ServerStatus> _fetchStatus() async {
    final json = await _api.get('/status');
    final memory =
        (json['memory'] as Map?)?.cast<String, dynamic>() ?? const {};
    final disk = (json['disk'] as Map?)?.cast<String, dynamic>() ?? const {};
    final load = (json['load'] as List?) ?? const [];
    return ServerStatus(
      hostname: (json['host'] as String?) ?? 'unknown',
      os: (json['os'] as String?) ?? '',
      link: _server.lastStatus?.link ?? LinkState.online,
      uptime: Duration(seconds: (json['uptimeSec'] as num?)?.toInt() ?? 0),
      cpuPercent: (json['cpuPct'] as num?)?.toDouble() ?? 0,
      memoryUsedMb: (memory['usedMb'] as num?)?.toDouble() ?? 0,
      memoryTotalMb: (memory['totalMb'] as num?)?.toDouble() ?? 0,
      diskUsedPercent: (disk['usedPct'] as num?)?.toDouble() ?? 0,
      loadAverage: load.isNotEmpty ? (load.first as num).toDouble() : 0,
      temperature: 0,
      services: const [],
      sampledAt: DateTime.now(),
    );
  }

  String _describe(ServerStatus s) {
    final buf = StringBuffer()
      ..writeln('${s.hostname} · ${s.link.label}')
      ..writeln(
        'cpu ${percentOf(s.cpuPercent)}  '
        'mem ${percentOf(s.memoryPercent)}  '
        'disk ${percentOf(s.diskUsedPercent)}',
      )
      ..writeln(
        'load ${s.loadAverage.toStringAsFixed(2)}  '
        'uptime ${uptimeOf(s.uptime)}',
      );
    return buf.toString().trimRight();
  }

  String _services(ServerStatus s) {
    if (s.services.isEmpty) return 'в /status нет сервисов';
    final up = s.services.where((x) => x.state.label == 'RUNNING').length;
    final buf = StringBuffer('$up/${s.services.length} up:');
    for (final service in s.services) {
      buf.write('\n  ${service.state.label.padRight(8)} ${service.name}');
    }
    return buf.toString();
  }

  Future<String> _logs() async {
    final json = await _api.get(
      '/logs',
      query: {'source': 'server_hub', 'limit': '100'},
    );
    final raw = json['lines'];
    if (raw is! List || raw.isEmpty) return 'в журнале пусто';
    var error = 0;
    var warn = 0;
    var info = 0;
    for (final item in raw) {
      if (item is! Map) continue;
      final level = LogLevel.byName(item['level'] as String?);
      if (level == LogLevel.error) {
        error++;
      } else if (level == LogLevel.warn) {
        warn++;
      } else {
        info++;
      }
    }
    return 'за последние ${raw.length} строк server_hub:\n'
        '  $error error · $warn warn · $info info/debug\n'
        'полный поток — на вкладке TERMINAL (режим JOURNAL).';
  }
}
