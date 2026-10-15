import '../repositories/chat_repository.dart';

/// Keyword-driven stand-in for the real bot. Replace with a repository backed
/// by the server API / Firebase Functions when the backend is ready.
class MockChatRepository implements ChatRepository {
  @override
  String get greeting =>
      'agent bot v0.9 ready. ask about load, services, logs or backups.\n'
      'type `help` for the command overview.';

  @override
  List<String> get suggestions => [
    'как дела?',
    'status',
    'почему выросла нагрузка?',
    'когда последний бэкап?',
  ];

  @override
  Future<String> reply(String prompt) async {
    final q = prompt.toLowerCase().trim();
    await Future<void>.delayed(
      Duration(milliseconds: 350 + q.length * 12),
    );

    bool has(List<String> keys) => keys.any(q.contains);

    if (q == 'help' || has(['команд', 'help', 'что умеешь'])) {
      return 'я умею: `status`, `services`, `uptime`, `logs`, `backup`, `reboot`.\n'
          'всё, что меняет состояние, подтверждается на вкладке CONTROL.';
    }
    if (has(['как дела', 'как оно', 'health', 'состояние', 'статус', 'status'])) {
      return 'нагрузка в норме: cpu ~14%, память ~38%, диск 61%.\n'
          'один сервис помечен degraded: upstream-sync, ошибка деградации сети.';
    }
    if (has(['нагрузк', 'cpu', 'память', 'load', 'тормоз', 'лаг'])) {
      return 'пик cpu был 3 часа назад (78%). причина: `postgres` autovacuum '
          'совпал с ночным бэкапом. сейчас автовакуум отложен до 04:00.';
    }
    if (has(['бэкап', 'backup', 'копия'])) {
      return 'последний бэкап: сегодня 03:12, размер 4.6 GB, sha256 проверен.\n'
          'следующий по расписанию в 03:00.';
    }
    if (has(['сервис', 'service', 'nginx', 'postgres', 'redis'])) {
      return 'nginx: running, 96MB\n'
          'postgresql: running, 512MB\n'
          'redis: running, 128MB\n'
          'upstream-sync: degraded, retry #2';
    }
    if (has(['лог', 'log', 'ошибк', 'error'])) {
      return 'за 15 минут: 1 error (upstream timeout 10.0.0.31), 3 warn, 41 info.\n'
          'полный поток — на вкладке TERMINAL.';
    }
    if (has(['перезагруз', 'reboot', 'restart', 'рестарт'])) {
      return 'это деструктивная операция. открой CONTROL и подтверди действие — '
          'я не выполняю перезагрузки из чата.';
    }
    if (has(['привет', 'hello', 'hi', 'здравств'])) {
      return 'привет, оператор. линия активна, жду команды.';
    }
    if (has(['погод'])) {
      return 'в серверной 21°C, влажность 42%. cpu 48°C — в пределах нормы.';
    }
    return 'не распознал запрос. попробуй: `status`, `services`, `logs`, `backup`.';
  }
}
