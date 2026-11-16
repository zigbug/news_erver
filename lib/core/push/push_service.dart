import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/repositories/server_repository.dart';
import '../logging/app_logger.dart';
import '../models/server_status.dart';
import 'local_notifications.dart';
import 'push_payload.dart';

/// Runs on a separate background isolate when an FCM message arrives while the
/// app is backgrounded or terminated. Firebase does not re-run `main()` there,
/// so keep this self-contained — no app state, no [talker]. It is wired up in
/// `main.dart` right after `Firebase.initializeApp()`.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[push] background message id=${message.messageId}');
  // A `notification` block is rendered by Android itself — drawing it here
  // would duplicate it. Data-only pushes have no system UI, so draw those.
  if (message.notification != null) return;
  try {
    final plugin = await initLocalNotifications();
    final shown = await showPushNotification(plugin, message);
    if (!shown) {
      debugPrint('[push] background data-only ping — nothing to display');
    }
  } catch (e) {
    debugPrint('[push] background display failed: $e');
  }
}

/// Owns Firebase Cloud Messaging: the notification permission, the device
/// token, the message listeners, and the local notifications drawn while the
/// app is in the foreground.
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
  bool _disposed = false;

  /// Foreground display path. Null when the platform plugin is unavailable
  /// (widget tests) or initialization failed; FCM token registration still
  /// proceeds in that case.
  FlutterLocalNotificationsPlugin? _local;

  /// Guards against drawing the same FCM delivery twice.
  final PushDedupe _dedupe = PushDedupe();

  /// Tab requested by the last notification tap. A [ValueNotifier] instead of
  /// a broadcast stream so a tap that arrives before the shell subscribes is
  /// not lost: the shell reads the current value when it mounts.
  final ValueNotifier<PushTarget?> _pendingTap = ValueNotifier(null);

  ValueListenable<PushTarget?> get pendingTap => _pendingTap;

  /// Requests permission, wires the listeners and starts watching for a live
  /// link. Safe to call once; a Firebase failure is logged, not thrown, so a
  /// mis-configured build degrades to "no push" instead of a crash.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      talker.info(
        'push: permission ${settings.authorizationStatus.name} '
        '(alert=${settings.alert}, badge=${settings.badge}, sound=${settings.sound})',
      );
      // Local notifications are initialized separately: if the plugin is
      // missing, token registration and tap handling must still work.
      await _initLocalNotifications();
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

  Future<void> _initLocalNotifications() async {
    try {
      final plugin = await initLocalNotifications(onTap: _onLocalTap);
      if (_disposed) return;
      _local = plugin;
      final launch = await plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        talker.info('push: app launched from a notification');
        _handlePayload(launch?.notificationResponse?.payload);
      }
    } catch (e, st) {
      talker.handle(
        e,
        st,
        'push: local notifications unavailable (foreground display disabled)',
      );
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _statusSub?.cancel();
    _statusSub = null;
    _local = null;
    _pendingTap.dispose();
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

  Future<void> _onForeground(RemoteMessage message) async {
    final notification = message.notification;
    final title = textOf(notification?.title) ?? textOf(message.data['title']);
    final body = textOf(notification?.body) ?? textOf(message.data['body']);
    final channel = notification?.android?.channelId;
    talker.info(
      'push ← ${title ?? "(no title)"}${body == null ? "" : " · $body"} '
      '· channel=${channel ?? "(none)"} notification=${notification != null}',
    );

    if (title == null && body == null) {
      talker.info('push: data-only ping — nothing to display');
      return;
    }
    final key = message.messageId ?? textOf(message.data['notification_id']);
    if (!_dedupe.accept(key)) {
      talker.info('push: duplicate ignored (${key ?? "no key"})');
      return;
    }
    final plugin = _local;
    if (plugin == null) {
      talker.warning(
        'push: local notifications unavailable — foreground push not shown',
      );
      return;
    }
    try {
      await showPushNotification(plugin, message);
      talker.info('push: shown in foreground');
    } catch (e, st) {
      talker.handle(e, st, 'push: foreground display failed');
    }
  }

  void _onLocalTap(NotificationResponse response) {
    talker.info('push: notification tapped (id=${response.id ?? "?"})');
    _handlePayload(response.payload);
  }

  void _onOpened(RemoteMessage message) {
    talker.info('push: notification opened (${message.messageId ?? "no id"})');
    final payload = PushPayload.fromData(
      message.data,
      messageId: message.messageId,
      channelId: message.notification?.android?.channelId,
    );
    _emitTarget(payload.target);
  }

  void _handlePayload(String? raw) {
    final payload = PushPayload.decode(raw);
    if (payload == null) {
      talker.info('push: tap without a usable payload');
      return;
    }
    talker.info(
      'push: route → ${payload.target.name}'
      '${payload.entityId == null ? "" : " (${payload.entityId})"}',
    );
    _emitTarget(payload.target);
  }

  void _emitTarget(PushTarget target) {
    if (_disposed) return;
    // Reset first so tapping the same tab twice still notifies the shell.
    _pendingTap.value = null;
    _pendingTap.value = target;
  }

  String _short(String token) =>
      token.length <= 12 ? token : '${token.substring(0, 12)}…';
}
