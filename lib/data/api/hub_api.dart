import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/logging/app_logger.dart';
import '../../core/models/app_settings.dart';

/// Raised when the hub is unreachable or answers with a non-2xx status.
class HubApiException implements Exception {
  const HubApiException(this.statusCode, this.message, {this.body});

  /// HTTP status, or null when the request never completed (offline/timeout).
  final int? statusCode;

  final String message;

  /// Decoded error body, when the hub returned JSON.
  final Object? body;

  bool get isUnauthorized => statusCode == 401;

  bool get isOffline => statusCode == null;

  @override
  String toString() =>
      statusCode == null ? message : 'HTTP $statusCode · $message';
}

/// Thin, stateless client for the server_hub REST API.
///
/// The connection parameters are read through [connection] on every request, so
/// a single instance keeps working after the user edits the base URL or key in
/// SETUP. Authentication uses the single hub key (`X-API-Key`), which may be
/// the read or the admin key.
class HubApi {
  HubApi({
    required ConnectionSettings Function() connection,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _connection = connection,
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final ConnectionSettings Function() _connection;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  /// Snapshot of the connection the client will use for the next request.
  ConnectionSettings get connection => _connection();

  /// Exchanges the admin password for a ready-to-use API key.
  ///
  /// Hits `POST /auth/token`; the hub replies with `{apiKey, role}`. Throws
  /// [HubApiException] when the password is wrong (401) or the endpoint is
  /// disabled (503).
  Future<String> login(String password) async {
    final json = await _asMap(
      _request('POST', '/auth/token', body: {'password': password}),
    );
    final key = json['apiKey'];
    if (key is! String || key.isEmpty) {
      throw const HubApiException(null, 'хаб вернул пустой ключ');
    }
    return key;
  }

  static String _normalize(String value) {
    var v = value.trim();
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  Uri _uri(String base, String path, Map<String, String>? query) {
    final uri = Uri.parse('$base$path');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  /// [quiet] silences this call in the Talker history. Background polling
  /// (`/status`, `/logs` tails) sets it, so a device idling for ten minutes
  /// doesn't bury real events under a line every two seconds. Failures stay
  /// visible through the repository's own `degraded` / `connect failed` logs.
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    bool quiet = false,
  }) => _asMap(_request('GET', path, query: query, quiet: quiet));

  Future<List<dynamic>> getList(
    String path, {
    Map<String, String>? query,
    bool quiet = false,
  }) async {
    final decoded = await _request('GET', path, query: query, quiet: quiet);
    return decoded is List ? decoded : const [];
  }

  Future<Map<String, dynamic>> post(String path, {Object? body}) =>
      _asMap(_request('POST', path, body: body));

  Future<Map<String, dynamic>> delete(String path) =>
      _asMap(_request('DELETE', path));

  Future<Map<String, dynamic>> _asMap(Future<Object?> future) async {
    final decoded = await future;
    if (decoded is Map<String, dynamic>) return decoded;
    return decoded is Map
        ? decoded.cast<String, dynamic>()
        : <String, dynamic>{};
  }

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool quiet = false,
  }) async {
    final connection = _connection();
    final base = _normalize(connection.apiBaseUrl);
    final apiKey = connection.apiToken.trim();
    final uri = _uri(base, path, query);

    final request = http.Request(method, uri);
    request.headers['Accept'] = 'application/json';
    if (apiKey.isNotEmpty) request.headers['X-API-Key'] = apiKey;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }

    final stopwatch = Stopwatch()..start();
    http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      if (!quiet) {
        talker.warning('$method $uri → таймаут (${timeout.inSeconds}s)');
      }
      throw const HubApiException(null, 'таймаут ответа хаба');
    } catch (e) {
      if (!quiet) talker.error('$method $uri → нет связи: $e');
      throw HubApiException(null, 'нет связи с хабом: $e');
    }
    stopwatch.stop();

    final decoded = _decode(response.body);
    final trace =
        '$method $uri → ${response.statusCode} (${stopwatch.elapsedMilliseconds}ms)';
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = _errorMessage(decoded) ?? 'HTTP ${response.statusCode}';
      if (!quiet) talker.warning('$trace · $message');
      throw HubApiException(response.statusCode, message, body: decoded);
    }
    if (!quiet) {
      if (apiKey.isEmpty && !path.startsWith('/auth/')) {
        talker.info('$trace · нет X-API-Key (хаб ответит 401)');
      } else {
        talker.info(trace);
      }
    }

    return decoded;
  }

  Object? _decode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  String? _errorMessage(Object? decoded) =>
      decoded is Map && decoded['error'] is String
      ? decoded['error'] as String
      : null;

  /// Subscribes to an SSE endpoint (`GET [path]`) and yields every decoded
  /// `data:` frame as it arrives.
  ///
  /// The chat uses this for opencode's `/chat/event`: one long-lived
  /// connection replaces per-message polling. The hub answers with
  /// `text/event-stream` and proxies the headless opencode instance without
  /// buffering, so frames pass through the moment the agent produces them.
  /// Comment frames (`: heartbeat`) are skipped.
  Stream<Map<String, dynamic>> stream(
    String path, {
    Duration attachTimeout = const Duration(seconds: 15),
  }) async* {
    final connection = _connection();
    final base = _normalize(connection.apiBaseUrl);
    final apiKey = connection.apiToken.trim();
    final uri = _uri(base, path, null);

    final request = http.Request('GET', uri);
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Cache-Control'] = 'no-cache';
    if (apiKey.isNotEmpty) request.headers['X-API-Key'] = apiKey;

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(attachTimeout);
    } on TimeoutException {
      talker.warning('GET $uri → таймаут подключения к потоку');
      throw const HubApiException(null, 'таймаут подключения к потоку');
    } catch (e) {
      talker.error('GET $uri → нет связи: $e');
      throw HubApiException(null, 'нет связи с хабом: $e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await http.Response.fromStream(response);
      final decoded = _decode(body.body);
      final message = _errorMessage(decoded) ?? 'HTTP ${response.statusCode}';
      talker.warning('GET $uri → ${response.statusCode} · $message');
      throw HubApiException(response.statusCode, message, body: decoded);
    }
    talker.info('GET $uri → ${response.statusCode} (SSE)');

    var buffer = '';
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer = (buffer + chunk).replaceAll('\r\n', '\n');
      var index = buffer.indexOf('\n\n');
      while (index != -1) {
        final frame = buffer.substring(0, index);
        buffer = buffer.substring(index + 2);
        index = buffer.indexOf('\n\n');

        final data = <String>[];
        for (final line in frame.split('\n')) {
          if (line.startsWith('data:')) {
            data.add(line.substring(5).replaceFirst(RegExp(r'^ '), ''));
          }
        }
        if (data.isEmpty) continue; // comment / keep-alive frame
        try {
          final decoded = jsonDecode(data.join('\n'));
          if (decoded is Map<String, dynamic>) {
            yield decoded;
          } else if (decoded is Map) {
            yield decoded.cast<String, dynamic>();
          }
        } catch (_) {
          // Not JSON — keep-alive noise, ignore.
        }
      }
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
