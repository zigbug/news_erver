# Remote Console

**English.** A retro-styled Android console (Flutter) for monitoring and
controlling a remote server: a CRT-and-phosphor look — green-on-black, phosphor
glow, scanlines, tube flicker — wrapped around a properly layered architecture.

Out of the box it talks to a real `server_hub` REST API — there is no mock
backend in the app. If the API base URL is not set yet (or the hub is
unreachable), the tabs stay up and clearly show `OFFLINE` instead of pretending
to be healthy, so a missing setup never hides what actually works. Tabs:
`TERMINAL` (JOURNAL/SHELL mode switch), `STATUS`
(CPU / memory / disk / load / service states, CPU sparkline), `CHAT`
(status-bot), `CONTROL` (connect / reconnect / disconnect, service restart,
reboot with confirmation) and `SETUP` (palette, font, text scale, CRT effects,
hub connection). Stack: Flutter 3.41 / Dart 3.11, `flutter_bloc` + `equatable`,
`shared_preferences`, `http`; fonts VT323 and JetBrains Mono. Run with
`flutter run`, verify with `flutter analyze` and `flutter test`.

---

Ретро-терминал для мониторинга и управления удалённым сервером. Android-приложение
на Flutter: зелёные буквы на чёрном, фосфорное свечение, скан-линии и лёгкое
мерцание ЭЛТ — но с настоящей архитектурой.

> **Подключение.** Приложение всегда работает поверх REST API `server_hub` —
> моков в коде нет. Пока не заданы `api base url` и ключ, линия показывается как
> `OFFLINE`, а не имитирует здоровую телеметрию.

## Подключение к server_hub

1. В `SETUP` → панель `connection · server_hub` укажи:
   - `api base url` — например `https://hub.905911.ru:8448`;
   - `password` — пароль администратора (`ADMIN_PASSWORD` на сервере);
2. нажми `GET KEY` — хаб ответит `POST /auth/token` и отдаст готовый ключ
   (`ADMIN_KEY`); он сохраняется в `shared_preferences` и уходит в `X-API-Key`;
   поле пароля после этого очищается;
3. нажми `PING HUB` — покажет версию сервиса или ошибку;
4. `auto connect on boot` поднимает линию при старте; иначе — кнопка `CONNECT`
   на вкладке `CONTROL`.

Ключ передаётся в заголовке `X-API-Key`. Смена `api base url` на лету меняет
цель запросов `HubApi` на месте, не пересобирая bloc-граф — тема, CRT-эффекты и
фокус ввода в SETUP не рвутся.

## Возможности

- **CRT-эстетика** — палитры, фосфорное свечение текста, скан-линии, виньетка и
  мерцание трубки. Все эффекты отключаются в SETUP.
- **Живой журнал** — поток логов с уровнями (`trace/debug/info/warn/error`),
  фильтр по уровням, автоскролл; источник — `/logs` хаба.
- **Терминал** — переключатель режимов: `JOURNAL` (хвост журнала) и `SHELL`
  (read-only командная строка); деструктив намеренно запрещён.
- **Телеметрия** — CPU, память, диск, load average, состояние сервисов,
  спарклайн истории CPU (температура на VPS недоступна — показывается `—`).
- **Чат с ботом** — статус-бот: отвечает по живым данным `/status` и `/logs`.
- **Панель управления** — connect / reconnect / disconnect, рестарт сервиса,
  перезагрузка и деплой (с подтверждением) через `/actions/*`.
- **Настройки** — палитра, шрифт, масштаб текста, CRT-эффекты, подключение к
  хабу (`api base url`, пароль → ключ), интервал опроса, автоподключение.

## Экраны

| Вкладка | Что показывает |
| --- | --- |
| `TERMINAL` | Режимы `JOURNAL` (хвост логов) и `SHELL` (read-only промпт) |
| `STATUS` | Системная сводка, метры утилизации, список сервисов |
| `CHAT` | Диалог со статус-ботом и подсказки-быстрые вопросы |
| `CONTROL` | Операции с линией, обслуживанием и питанием + журнал операций |
| `SETUP` | Внешний вид и подключение к хабу |

Плюс boot-экран с инициализацией и автоподключением при старте.

## Стек

- Flutter 3.41.7 / Dart 3.11.5 (stable)
- `flutter_bloc` — `Bloc` для терминала и чата, `Cubit` для темы, статуса,
  настроек и панели управления
- `equatable` — модели
- `shared_preferences` — персист настроек (ключ `retro_settings_v1`)
- `http` — REST-клиент к `server_hub`
- Платформа: Android (первый приоритет)

Шрифты: **VT323** (классический CRT, без кириллицы) + **JetBrains Mono**
(variable, fallback для кириллицы). Переключение — в SETUP.

## Запуск

```bash
flutter pub get
flutter run            # Android-устройство или эмулятор
```

Сборка APK:

```bash
flutter build apk --debug
# build/app/outputs/flutter-apk/app-debug.apk
```

Проверки:

```bash
flutter analyze
flutter test
```

## Архитектура

Слои разделены; сеть спрятана за интерфейсами репозиториев.

```
core/      модели, тема, утилиты
  data/
  repositories/  интерфейсы (ServerRepository, ChatRepository)
  api/           HubApi, ApiServerRepository / ApiChatRepository
features/  bloc / cubit
ui/        виджеты, экраны, shell
```

**Точка подключения** — `lib/app.dart`. Там создаётся один общий `HubApi`
(читает base URL и ключ из `SettingsCubit` на каждом запросе), поверх него —
`ApiServerRepository` и `ApiChatRepository`. Bloc-граф строится один раз и живёт
всю сессию: правка темы, CRT-эффектов или адреса хаба не пересобирает его, а
значит не рвёт линию и не теряет фокус в SETUP.

### Контракты репозиториев

```dart
abstract interface class ServerRepository {
  Stream<LogEntry> logs();
  Stream<ServerStatus> status();
  ServerStatus? get lastStatus;
  Future<void> connect();
  Future<void> disconnect();
  Future<void> reconnect();
  Future<void> rebootServer();
  Future<void> restartService(String name);
  Future<void> clearCache();
  Future<String> runCommand(String command);      // только чтение
  Future<List<LogEntry>> fetchLogHistory({int limit = 40});
  void dispose();
}

abstract interface class ChatRepository {
  Future<String> reply(String prompt);
  String get greeting;
  List<String> get suggestions;
}
```

Реализации: `ApiServerRepository` / `ApiChatRepository` (REST к `server_hub`) —
единственные бэкенды приложения, демо-репозиториев нет. API-чат — статус-бот:
отвечает по `/status` и `/logs`, ничего не меняет.

### Параметры подключения

`ConnectionSettings` (персистится в `shared_preferences`):

- `apiBaseUrl` — адрес хаба, например `https://hub.905911.ru:8448`;
- `apiToken` — ключ хаба, уходит в `X-API-Key`; выдаётся кнопкой `GET KEY`
  через `POST /auth/token` (пароль вводится в SETUP, поле очищается после выдачи);
- `pollIntervalSeconds`, `autoConnect`.

Поля `serverId` / `firebase*` сохранены в модели для обратной совместимости
формата хранения, но в UI и логике больше не используются.

Маппинг на API хаба: `login()` → `POST /auth/token`, `status()` → `GET /status`,
`logs()` → `GET /logs?source=…&since_ms=…`, `fetchLogHistory()` → `GET /logs?limit=…`,
`restartService(name)` → `POST /actions/restart_{nginx,docker,mtproto,searx_mcp}`
либо `POST /actions/restart_container {name}`, `rebootServer()` →
`POST /actions/reboot`. `clearCache()` на хабе не поддерживается и возвращает
ошибку (показывается в журнале операций).

## Тема и CRT-эффекты

Палитры (`RetroPalettes.all`), по умолчанию — `phosphor_green`:

| id | Название | Яркость | Glow |
| --- | --- | --- | --- |
| `phosphor_green` | PHOSPHOR P1 | dark | 0.85 |
| `amber_p3` | AMBER P3 | dark | 0.85 |
| `ice_cyan` | ICE CGA | dark | 0.80 |
| `gray_crt` | MONO CRT | dark | 0.50 |
| `paper` | PAPER READER | light | 0.00 |

Реализовано через `ThemeExtension` (`RetroTheme`) с доступом `context.palette`
и `context.retro`. Тумблеры: скан-линии, фосфорное свечение, мерцание трубки,
масштаб текста. Светлая палитра `paper` автоматически гасит свечение.

## Read-only команды терминала

```
help              список команд
status            однострочная сводка о линии
uptime            время с последней загрузки
services          список docker-контейнеров и systemd-юнитов
logs <n>          хвост n строк из /logs
whoami            идентичность сессии
echo <text>       эхо
clear             очистить буфер
```

`reboot` / `shutdown` из терминала отклоняются намеренно — деструктивные
операции доступны только на вкладке `CONTROL` с подтверждением.

## Тесты

```bash
flutter test
```

- `test/theme_test.dart` — палитры и построение темы
- `test/formatters_test.dart` — утилиты форматирования
- `test/settings_cubit_test.dart` — настройки и персист
- `test/chat_bloc_test.dart` — логика чата
- `test/app_smoke_test.dart` — поднимает всё приложение, проходит по всем
  вкладкам, переключает CRT-эффекты и шрифт, падая на первой же исключительной
  ситуации (ловит layout-регрессии вроде unbounded viewport)

## Roadmap

- [x] `ApiServerRepository` — REST к серверному агенту (`server_hub`)
- [x] Статус-бот поверх живых данных
- [x] Моки удалены: только реальный API, честный `OFFLINE` без настроек
- [x] Вход по паролю: `GET KEY` → `POST /auth/token` → `X-API-Key`
- [ ] Хранение ключа в защищённом хранилище (сейчас ключ лежит в
      `shared_preferences` открытым текстом)
- [ ] Push-уведомления об инцидентах (FCM)
- [ ] iOS-таргет

## Заметки

- Android-метка приложения — **Remote Console** (`android/app/src/main/AndroidManifest.xml`).
- `applicationId` — `com.example.news_erver`.
- Персист настроек — `<shared_preferences>/retro_settings_v1` (JSON).
- При сборке APK возможен warning Kotlin-daemon (pub-cache на `C:`, проект на
  `D:`). На результат не влияет; при желании — `kotlin.incremental=false` в
  `android/gradle.properties`.
