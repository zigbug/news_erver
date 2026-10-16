import 'package:talker_flutter/talker_flutter.dart';

/// Single application-wide logger.
///
/// Everything funnels here: BLoC events and errors (`TalkerBlocObserver` in
/// `main.dart`), uncaught Flutter/async errors, explicit `talker.*` calls in
/// the data layer, and every hub HTTP request/response (`HubApi._send`). The
/// in-app log viewer (the `▤` button in the status strip) shows this history,
/// so a dev can see what the client is doing without a cable attached.
final Talker talker = TalkerFlutter.init(
  settings: TalkerSettings(
    useHistory: true,
    maxHistoryItems: 5000,
    useConsoleLogs: true,
  ),
);
