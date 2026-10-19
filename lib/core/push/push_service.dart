import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../data/repositories/server_repository.dart';
import '../logging/app_logger.dart';
import '../models/server_status.dart';

/// Runs on a separate background isolate when an FCM message arrives while the
/// app is backgrounded or terminated. Firebase does not re-run `main()` there,
/// so keep this self-contained — no app state, no [talker]. It is wired up in
/// `main.dart` right after `Firebase.initializeApp()`.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[push] background message id=${message.messageId}');
}

/// Owns Firebase Cloud Messaging: the notification permission, the device
/// token, and the message listeners.
///
/// The token is only handed to the hub once the link is actually up — [start]
/// watches [ServerRepository.status] and registers on the first `online`
/// snapshot, so a console that never reaches the hub never lands in `/devices`.
/// Registration is idempotent and skipped again until the token changes, so a
/// reconnect does not re-post it.
class PushService {
  PushService(this._repository);

  final ServerRepository _repository;

  /// Resolved lazily inside [start]: touching `FirebaseMessaging.instance` in
  /// the constructor would throw before the try/catch on builds where Firebase
  /// is not wired up (widget tests, a missing google-services.json).
  // FirebaseMessaging.instance accessed lazily inside start() to keep widget tests safe.

  /// FCM token (null until the platform hands one over). `onTokenRefresh`
  /// replaces it and triggers a fresh registration.
  String? _token;

  /// Last token the hub accepted — guards against re-posting on every status
  /// tick. Cleared (logically) only by a token change, never by a disconnect:
  /// signing out does not invalidate the push channel.
  String? _registeredToken;

  StreamSubscription<ServerStatus>? _statusSub;
  bool _started = false;

  /// Requests permission, wires the listeners and starts watching for a live
  /// link. Safe to call once; a Firebase failure is logged, not thrown, so a
  /// mis-configured build degrades to "no push" instead of a crash.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      messaging.onTokenRefresh.listen(_remember);
      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _onOpened(initial);
      _token = await messaging.getToken();
      talker.info(
        _token == null
            ? 'push: no token yet'
            : 'push: token ready (${_short(_token!)})',
      );
      _statusSub = _repository.status().listen(_onStatus);
    } catch (e, st) {
      _started = false;
      talker.handle(e, st, 'push: init failed');
    }
  }

  Future<void> dispose() async {
    await _statusSub?.cancel();
    _statusSub = null;
    // nothing to retain
    _started = false;
  }

  void _onStatus(ServerStatus status) {
    if (status.link == LinkState.online) _registerIfNeeded();
  }

  void _remember(String token) {
    _token = token;
    talker.info('push: token refreshed (${_short(token)})');
    _registerIfNeeded();
  }

  Future<void> _registerIfNeeded() async {
    final token = _token;
    if (token == null || token.isEmpty || token == _registeredToken) return;
    try {
      await _repository.registerDevice(token);
      _registeredToken = token;
      talker.info('push: device registered (${_short(token)})');
    } catch (e) {
      // Kept quiet: offline/first-connect races are expected. The next status
      // tick (or a token refresh) retries.
      talker.warning('push: registration deferred → retry when linked: $e');
    }
  }

  void _onForeground(RemoteMessage message) {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString();
    talker.info(
      'push ← ${title ?? "(no title)"}${body == null ? "" : " · $body"}',
    );
  }

  void _onOpened(RemoteMessage message) {
    talker.info('push: notification opened (${message.messageId ?? "no id"})');
  }

  String _short(String token) =>
      token.length <= 12 ? token : '${token.substring(0, 12)}…';
}
