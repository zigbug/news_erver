# TODO

## Shell: реальный shell на сервере

Сейчас shell-вкладка — симуляция на клиенте: `runCommand` в
`lib/data/api/api_server_repository.dart` — switch из 8 команд
(help, status, uptime, services, logs, whoami, echo, clear).
На сервер уходит только `logs` (`GET /logs`). Хаба в этом репо нет,
транспорт — REST (`GET`/`POST` + `X-API-Key`), без WebSocket/SSH.

Идея: дать оператору настоящие read-only команды сервера
(`df -h`, `docker ps`, `systemctl status …`), а не только телеметрию.

### Вариант B — endpoint на хабе (нужен доступ к коду хаба, отдельный репо)

- [ ] Спроектировать API-контракт: `POST /shell/exec {cmd, args}` → `{stdout, stderr, exitCode}`
- [ ] На хабе: белый список безопасных read-only команд
      (docker ps, df -h, systemctl status, uptime, free -m, …);
      без shell-интерпретации (exec напрямую, без `sh -c`)
- [ ] На хабе: таймаут, лимит размера вывода, аудит-лог вызовов
- [ ] Клиент: в `runCommand` ветка для неизвестных команд → `/shell/exec`
- [ ] Клиент: парсинг exitCode, показ stderr/кода ошибки в терминале

### Вариант A — расширить клиентские команды (можно уже сейчас, в этом репо)

- [ ] `sources` — список источников логов (`/logs/sources`)
- [ ] `df` — диск из кэша `/status`
- [ ] `ps` / `top` — сервисы + cpu/mem из кэша `/status`
- [ ] `tail -f <source>` — следить за конкретным источником
- [ ] `history` — последние введённые команды
