import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:talker_bloc_logger/talker_bloc_logger.dart';

import 'app.dart';
import 'core/logging/app_logger.dart';
import 'core/push/push_service.dart';

Future<void> _createNotificationChannels() async {
  final plugin = FlutterLocalNotificationsPlugin();

  const critical = AndroidNotificationChannel(
    'hub_critical',
    'Критичные события',
    description: 'Падение сервиса, сбои',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );
  const alerts = AndroidNotificationChannel(
    'hub_alerts',
    'Оповещения',
    description: 'Сообщения от ассистента и статуса',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );
  const silent = AndroidNotificationChannel(
    'hub_silent',
    'Фоновые события',
    description: 'Технические события',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  await plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(critical);
  await plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(alerts);
  await plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(silent);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Firebase must be up before the push service reads from it. A failure here
  // (e.g. a missing/invalid google-services.json) is logged rather than fatal:
  // the console still runs, it just cannot receive push notifications.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await _createNotificationChannels();
    talker.info('firebase ready');
  } catch (e, st) {
    talker.handle(e, st, 'firebase init failed (push disabled)');
  }

  // Route BLoC events and uncaught errors to the logger. State churn is left
  // out on purpose: StatusCubit emits on every /status poll and TerminalBloc on
  // every tailed log line, so logging changes/transitions would bury the real
  // trace under the very polling it exists to observe. User actions still show
  // up as events (and as HTTP lines from HubApi).
  Bloc.observer = TalkerBlocObserver(
    talker: talker,
    settings: TalkerBlocLoggerSettings(
      printEvents: true,
      printEventFullData: false,
      printChanges: false,
      printTransitions: false,
      printStateFullData: false,
      printCreations: false,
      printClosings: false,
    ),
  );
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    talker.handle(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    talker.handle(error, stack);
    return true;
  };

  talker.info('app started');
  runApp(const RetroConsoleApp());
}
