import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:talker_bloc_logger/talker_bloc_logger.dart';

import 'app.dart';
import 'core/logging/app_logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

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
