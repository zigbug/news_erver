import '../../core/models/log_entry.dart';
import '../../core/models/server_status.dart';

/// Everything the app can ask of the remote server.
/// The concrete backend is [data/api/api_server_repository.dart].
/// Implementations: ApiServerRepository (hub REST).
abstract interface class ServerRepository {
  /// Live tail of the server log.
  Stream<LogEntry> logs();

  /// Periodic status snapshots.
  Stream<ServerStatus> status();

  /// Last known snapshot, or null before the first one arrives.
  ServerStatus? get lastStatus;

  /// Brings the link up. Emits progress through [status].
  Future<void> connect();

  /// Brings the link down on purpose.
  Future<void> disconnect();

  /// Drops and re-establishes the link.
  Future<void> reconnect();

  /// Reboots the remote machine (destructive — always confirm in the UI).
  Future<void> rebootServer();

  /// Restarts a single service by name.
  Future<void> restartService(String name);

  /// Drops caches without a restart.
  Future<void> clearCache();

  /// Runs a shell-style command from the terminal prompt and returns its
  /// textual output. Read-only by design; destructive commands must go through
  /// the named methods above.
  Future<String> runCommand(String command);

  /// Recent log lines to seed the terminal view.
  Future<List<LogEntry>> fetchLogHistory({int limit = 40});

  /// Sources currently tailed by [logs] (one or more — a merged feed).
  List<String> get logSources;

  /// Sets the tailed log sources. An empty list is ignored; order-insensitive.
  void setLogSources(List<String> sources);

  /// Sources the hub can serve (falls back to a built-in list when offline).
  Future<List<String>> availableLogSources();

  void dispose();
}
