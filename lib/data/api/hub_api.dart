import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<Map<String, dynamic>> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final connection = _connection();
    final base = _normalize(connection.apiBaseUrl);
    final apiKey = connection.apiToken.trim();

    final request = http.Request(method, _uri(base, path, query));
    request.headers['Accept'] = 'application/json';
    if (apiKey.isNotEmpty) request.headers['X-API-Key'] = apiKey;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }

    http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const HubApiException(null, 'таймаут ответа хаба');
    } catch (e) {
      throw HubApiException(null, 'нет связи с хабом: $e');
    }

    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HubApiException(
        response.statusCode,
        _errorMessage(decoded) ?? 'HTTP ${response.statusCode}',
        body: decoded,
      );
    }

    if (decoded is Map<String, dynamic>) return decoded;
    return decoded is Map
        ? decoded.cast<String, dynamic>()
        : <String, dynamic>{};
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

  void close() {
    if (_ownsClient) _client.close();
  }
}
