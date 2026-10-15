import 'dart:async';

import '../../core/models/app_settings.dart';
import '../../core/models/log_entry.dart';
import '../../core/models/server_status.dart';
import '../mock/mock_chat_repository.dart';
import '../mock/mock_server_repository.dart';
import '../repositories/chat_repository.dart';
import '../repositories/server_repository.dart';
import 'api_chat_repository.dart';
import 'api_server_repository.dart';
import 'hub_api.dart';

/// A stable [ServerRepository] that swaps its delegate under the hood: the demo
/// mock until an API base URL is configured, then the hub-backed
/// [ApiServerRepository]. The instance never changes, so bloc subscriptions and
/// the SETUP form are never torn down when the user edits the connection.
class AdaptiveServerRepository implements ServerRepository {
  AdaptiveServerRepository() {
    _subscribe();
  }

  /// Shared, connection-aware client. Reused by the chat repository too.
  late final HubApi api = HubApi(connection: () => _connection);

  final _statusController = StreamController<ServerStatus>.broadcast();
  final _logController = StreamController<LogEntry>.broadcast();

  ServerRepository _delegate = MockServerRepository();
  StreamSubscription<ServerStatus>? _statusSub;
  StreamSubscription<LogEntry>? _logSub;

  ConnectionSettings _connection = const ConnectionSettings();
  bool _connected = false;
  ServerStatus? _last;

  /// Reconfigures the delegate when the connection target (or poll interval)
  /// changes. Safe to call on every settings change.
  Future<void> configure(ConnectionSettings connection) async {
    final targetChanged =
        connection.apiBaseUrl.trim() != _connection.apiBaseUrl.trim() ||
        connection.apiToken.trim() != _connection.apiToken.trim();
    final pollChanged =
        connection.pollIntervalSeconds != _connection.pollIntervalSeconds;
    _connection = connection;
    if (!targetChanged && !pollChanged) return;

    _teardown();
    _delegate = connection.apiConfigured
        ? ApiServerRepository(
            api,
            pollIntervalSeconds: connection.pollIntervalSeconds,
          )
        : MockServerRepository();
    _subscribe();
    if (_connected) {
      try {
        await _delegate.connect();
      } catch (_) {
        // Surfaced through the stream / control errors on the next poll.
      }
    }
  }

  void _subscribe() {
    _statusSub = _delegate.status().listen((status) {
      _last = status;
      if (!_statusController.isClosed) _statusController.add(status);
    });
    _logSub = _delegate.logs().listen((entry) {
      if (!_logController.isClosed) _logController.add(entry);
    });
  }

  void _teardown() {
    _statusSub?.cancel();
    _logSub?.cancel();
    _statusSub = null;
    _logSub = null;
    _delegate.dispose();
    _last = null;
  }

  @override
  ServerStatus? get lastStatus => _last;

  @override
  Stream<LogEntry> logs() => _logController.stream;

  @override
  Stream<ServerStatus> status() => _statusController.stream;

  @override
  Future<void> connect() async {
    _connected = true;
    await _delegate.connect();
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _delegate.disconnect();
  }

  @override
  Future<void> reconnect() => _delegate.reconnect();

  @override
  Future<void> rebootServer() => _delegate.rebootServer();

  @override
  Future<void> restartService(String name) => _delegate.restartService(name);

  @override
  Future<void> clearCache() => _delegate.clearCache();

  @override
  Future<String> runCommand(String command) => _delegate.runCommand(command);

  @override
  Future<List<LogEntry>> fetchLogHistory({int limit = 40}) =>
      _delegate.fetchLogHistory(limit: limit);

  @override
  void dispose() {
    _teardown();
    _statusController.close();
    _logController.close();
    api.close();
  }
}

/// Stable [ChatRepository] mirroring [AdaptiveServerRepository]: the mock bot
/// until the hub is configured, then the live status-bot.
class AdaptiveChatRepository implements ChatRepository {
  AdaptiveChatRepository(this._server, this._api);

  final ServerRepository _server;
  final HubApi _api;

  final ChatRepository _mock = MockChatRepository();
  ChatRepository? _apiBot;
  ConnectionSettings _connection = const ConnectionSettings();

  void configure(ConnectionSettings connection) => _connection = connection;

  ChatRepository get _active => _connection.apiConfigured
      ? (_apiBot ??= ApiChatRepository(_api, _server))
      : _mock;

  @override
  String get greeting => _active.greeting;

  @override
  List<String> get suggestions => _active.suggestions;

  @override
  Future<String> reply(String prompt) => _active.reply(prompt);
}
