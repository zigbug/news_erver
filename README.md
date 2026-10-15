# Remote Console

**English.** A retro-styled Android console (Flutter) for monitoring and
controlling a remote server: a CRT-and-phosphor look — green-on-black, phosphor
glow, scanlines, tube flicker — wrapped around a properly layered architecture
built for a future Firebase + server-API integration.

This is a **demo build**: data comes from mocks (`MockServerRepository` /
`MockChatRepository`), while the UI, streams, timers and state transitions are
real, so the whole interface runs and is tested end to end. Tabs: `TERMINAL`
(live log + command prompt), `STATUS` (CPU / memory / disk / load / temperature,
service states, CPU sparkline), `CHAT` (server bot), `CONTROL`
(connect / reconnect / disconnect, service restart, cache flush, reboot with
confirmation) and `SETUP` (palette, font, text scale, CRT effects, connection
settings). Stack: Flutter 3.41 / Dart 3.11, `flutter_bloc` + `equatable`,
`shared_preferences`; fonts VT323 and JetBrains Mono. Run with `flutter run`,
verify with `flutter analyze` and `flutter test`. Swap the mocks for real
implementations in `lib/app.dart` — the single wiring point.

---

Ретро-терминал для мониторинга и управления удалённым сервером. Android-приложение
на Flutter: зелёные буквы на чёрном, фосфорное свечение, скан-линии и лёгкое
мерцание ЭЛТ — но с настоящей архитектурой под будущую интеграцию с Firebase и
API сервера.

> **Статус: демо.** Данные моковые (`MockServerRepository` / `MockChatRepository`),
> реальных сетевых вызовов пока нет. UI, стримы, таймеры и переходы состояний —
> настоящие, поэтому интерфейс собирается и тестируется end-to-end.

## Возможности

- **CRT-эстетика** — палитры, фосфорное свечение текста, скан-линии, виньетка и
  мерцание трубки. Все эффекты отключаются в SETUP.
- **Живой журнал** — поток логов с уровнями (`trace/debug/info/warn/error`),
  фильтр по уровням, автоскролл.
- **Телеметрия** — CPU, память, диск, load average, температура, состояние
  сервисов, спарклайн истории CPU.
- **Терминал** — командная строка с демо-командами; деструктив намеренно запрещён.
- **Чат с ботом** — keyword-движок отвечает по состоянию сервера.
- **Панель управления** — connect / reconnect / disconnect, рестарт сервиса,
  очистка кэша, перезагрузка (с подтверждением).
- **Настройки** — палитра, шрифт, масштаб текста, CRT-эффекты, параметры
  подключения (Firebase + API), интервал опроса, автоподключение.

## Экраны

| Вкладка | Что показывает |
| --- | --- |
| `TERMINAL` | Поток логов (`tail -f`) + командная строка |
| `STATUS` | Системная сводка, метры утилизации, список сервисов |
| `CHAT` | Диалог с серверным ботом и подсказки-быстрые вопросы |
| `CONTROL` | Операции с линией, обслуживанием и питанием + журнал операций |
| `SETUP` | Внешний вид и параметры подключения |

Плюс boot-экран с инициализацией и автоподключением при старте.

## Стек

- Flutter 3.41.7 / Dart 3.11.5 (stable)
- `flutter_bloc` — `Bloc` для терминала и чата, `Cubit` для темы, статуса,
  настроек и панели управления
- `equatable` — модели
- `shared_preferences` — персист настроек (ключ `retro_settings_v1`)
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

Слои разделены, сеть пока подменена моками. Всё, что нужно знать для замены
бэкенда, — интерфейсы репозиториев.

```
core/      модели, тема, утилиты
data/      интерфейсы репозиториев + мок-реализации
features/  bloc / cubit
ui/        виджеты, экраны, shell
```

**Точка подмены** — единственный файл `lib/app.dart`: там `MockServerRepository`
и `MockChatRepository` передаются через `RepositoryProvider`. Меняем их на
Firebase/API-реализации — и всё приложение переезжает на реальные данные.

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

Планируемые реализации: `FirebaseServerRepository` (Realtime / Firestore) и
`ApiServerRepository` (прямой REST к агенту).

### Параметры подключения

`ConnectionSettings` уже описывает форму контракта (пока только сохраняется
локально, в сеть не уходит):

- `serverId` — логический id машины, путь `servers/{serverId}/...`
- `firebaseProjectId`, `firebaseApiKey`, `firebaseRegion`
- `apiBaseUrl`, `apiToken`
- `pollIntervalSeconds`, `autoConnect`

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

## Демо-команды терминала

```
help              список команд
status            однострочная сводка о линии
uptime            время с последней загрузки
services          список юнитов с состояниями
logs <n>          хвост буфера
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

- [ ] `FirebaseServerRepository` — Realtime Database / Firestore (`servers/{id}`)
- [ ] `ApiServerRepository` — REST/WebSocket к серверному агенту
- [ ] Аутентификация и шифрование токена (сейчас ключи хранятся в
      `shared_preferences` открытым текстом — только для демо)
- [ ] Push-уведомления об инцидентах
- [ ] iOS-таргет

## Заметки

- Android-метка приложения — **Remote Console** (`android/app/src/main/AndroidManifest.xml`).
- `applicationId` — `com.example.news_erver`.
- Персист настроек — `<shared_preferences>/retro_settings_v1` (JSON).
- При сборке APK возможен warning Kotlin-daemon (pub-cache на `C:`, проект на
  `D:`). На результат не влияет; при желании — `kotlin.incremental=false` в
  `android/gradle.properties`.
