# Remote Console — Руководство пользователя

Remote Console — это ретро-терминальное приложение (стиль зелёного CRT) для мониторинга и управления удалённым сервером.

## 1. Общая информация

- Платформа: Android (первичная). Доступны также Windows/Web/Chrome/Edge.
- Стиль интерфейса: терминальный CRT (фосфорный зелёный, скан-линии, виньетка на тёмных палитрах).
- Подключение к серверу: REST API, опрос (polling) каждые 5 секунд (статус) и 10 секунд (логи).
- Хранение настроек: локально (SharedPreferences).

## 2. Запуск и первый экран

При запуске приложения отображается BootScreen с логотипом и надписью REMOTE CONSOLE — booting.... После загрузки настроек открывается главный интерфейс с нижней навигацией.

## 3. Вкладки

Навигация снизу: TERMINAL, STATUS, CHAT, CONTROL, SETUP.

### 3.1 TERMINAL
Два режима переключения сверху: JOURNAL и SHELL.

- **JOURNAL** — просмотр потока логов сервера (live log). Фильтрация по уровням и по источникам логов. В заголовке видно количество строк.
- **SHELL** — интерактивная консоль. Внизу поле ввода > с кнопкой RUN. Команда добавляется в лог с меткой prompt, вывод — с меткой shell.

Использование: переключить режим → в SHELL ввести команду → Enter/RUN.

### 3.2 STATUS
Отображает: Hostname/OS, Uptime, CPU/Load, Memory, Disk, Temperature, Services, Link (ONLINE/OFFLINE/DEGRADED). Обновляется каждые 5 секунд.

### 3.3 CHAT
Терминальный чат с ботом. Есть поле ввода SEND, индикатор busy при генерации, подсказки (Suggestions).

### 3.4 CONTROL
Блоки с кнопками действий управления сервером (рестарты, перезагрузка и др.). Отправляются на API хаба.

### 3.5 SETUP
Настройки подключения, темы, шрифта, CRT-эффектов.

**Connection:** API Base URL, Password (кнопка FETCH KEY для обмена на API-ключ), Poll interval (5с), Log interval (10с), Auto-connect on boot, Ping.

**Theme & Palette:** PHOSPHOR GREEN/AMBER P3/ICE CYAN/MONO CRT/PAPER READER.

**Font:** VT323/JetBrainsMono, CRT mode scaling.

**CRT Effects:** Scanlines, Vignette, Tube glow/flicker, Glowing text (только для тёмных палитр).

## 4. Подключение к серверу

1. SETUP → API Base URL (с http:// или https://)
2. При наличии пароля: Password → FETCH KEY (получит и сохранит API-ключ)
3. Либо ввести готовый API Key
4. Настроить интервалы при необходимости
5. PING — проверка соединения (должен быть OK)
6. Переключиться на STATUS/TERMINAL — начнётся опрос

При пустом Base URL приложение работает в оффлайн-режиме.

## 5. Особенности

- Polling: статус 5с, логи 10с. Меняются в SETUP без перезапуска.
- Два режима TERMINAL разделены фильтрацией по source (prompt/shell vs остальные).
- Оффлайн-режим: Link → OFFLINE/DEGRADED, UI не блокируется, ретраи.
- Настройки хранятся в SharedPreferences (retro_settings_v1).
- SHELL — интерактивная консоль с вводом команд.
