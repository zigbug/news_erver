import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'push_payload.dart';

/// White silhouette used for the status bar. It is also declared in
/// `AndroidManifest.xml` as the FCM default icon.
const String kPushIcon = 'ic_stat_hub';

/// Builds the local-notifications plugin. The optional [onTap] callback fires
/// on the main isolate when the operator taps a notification that this app
/// drew itself; taps on system-drawn FCM notifications arrive through
/// `FirebaseMessaging.onMessageOpenedApp` instead.
Future<FlutterLocalNotificationsPlugin> initLocalNotifications({
  DidReceiveNotificationResponseCallback? onTap,
}) async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings(kPushIcon),
    ),
    onDidReceiveNotificationResponse: onTap,
  );
  return plugin;
}

/// Notification styling for [severity]. Sound and vibration are ultimately
/// decided by the Android channel, but the details mirror the channel so
/// pre-8.0 devices and the plugin's own fallbacks behave the same way.
NotificationDetails notificationDetailsFor(
  PushSeverity severity, {
  String? body,
}) {
  final channelId = channelIdForSeverity(severity);
  final loud = severity != PushSeverity.quiet;
  return NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelNameFor(channelId),
      channelDescription: channelDescriptionFor(channelId),
      icon: kPushIcon,
      importance: loud ? Importance.high : Importance.low,
      priority: loud ? Priority.high : Priority.low,
      playSound: loud,
      enableVibration: loud,
      channelShowBadge: loud,
      category: AndroidNotificationCategory.status,
      styleInformation: body == null
          ? null
          : BigTextStyleInformation(body, summaryText: null),
    ),
  );
}

/// Draws [message] as a local notification. Returns false when the message has
/// neither a title nor a body, i.e. there is nothing worth showing (a
/// data-only liveness ping).
///
/// Foreground FCM messages are never drawn by Android, and background
/// data-only messages have no system UI at all, so both paths end up here.
Future<bool> showPushNotification(
  FlutterLocalNotificationsPlugin plugin,
  RemoteMessage message,
) async {
  final notification = message.notification;
  final data = message.data;
  final title =
      textOf(notification?.title) ??
      textOf(data['title']) ??
      textOf(data['subject']);
  final body =
      textOf(notification?.body) ??
      textOf(data['body']) ??
      textOf(data['text']);
  if (title == null && body == null) return false;

  final payload = PushPayload.fromData(
    data,
    messageId: message.messageId,
    channelId: notification?.android?.channelId,
  );
  await plugin.show(
    id: notificationIdFor(
      messageId: message.messageId,
      data: data,
      sentTime: message.sentTime,
    ),
    title: title ?? 'Remote Console',
    body: body,
    notificationDetails: notificationDetailsFor(payload.severity, body: body),
    payload: payload.encode(),
  );
  return true;
}
