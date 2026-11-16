import 'dart:convert';

/// Android channel ids created in `main.dart`. The id is part of the public
/// contract with the hub: a push that names one of these channels lands in the
/// matching importance bucket, and Android fixes the sound per channel.
const String kPushCriticalChannel = 'hub_critical';
const String kPushAlertChannel = 'hub_alerts';
const String kPushQuietChannel = 'hub_silent';

/// How loudly a push should announce itself.
///
/// Android 8+ ignores per-notification sound and importance once a channel
/// exists, so this enum is really a channel selector: [critical] and [alert]
/// use high-importance channels with sound, [quiet] uses the low-importance
/// silent channel.
enum PushSeverity { critical, alert, quiet }

/// Tab a tapped push should open.
enum PushTarget { terminal, status, chat, control, settings }

/// Severity implied by a channel id, or null when the id is unknown.
PushSeverity? severityForChannel(String? channelId) {
  switch (textOf(channelId)?.toLowerCase()) {
    case kPushCriticalChannel:
      return PushSeverity.critical;
    case kPushAlertChannel:
      return PushSeverity.alert;
    case kPushQuietChannel:
      return PushSeverity.quiet;
  }
  return null;
}

/// Maps a free-form severity/priority/importance string from the hub to a
/// channel class. Unknown values return null so the caller can fall back.
PushSeverity? severityFromText(String? raw) {
  switch (textOf(raw)?.toLowerCase()) {
    case 'critical':
    case 'crash':
    case 'fatal':
    case 'emergency':
      return PushSeverity.critical;
    case 'quiet':
    case 'silent':
    case 'low':
    case 'info':
    case 'debug':
    case 'background':
      return PushSeverity.quiet;
    case 'alert':
    case 'important':
    case 'default':
    case 'normal':
    case 'high':
    case 'warning':
    case 'warn':
      return PushSeverity.alert;
  }
  return null;
}

String channelIdForSeverity(PushSeverity severity) => switch (severity) {
  PushSeverity.critical => kPushCriticalChannel,
  PushSeverity.alert => kPushAlertChannel,
  PushSeverity.quiet => kPushQuietChannel,
};

/// Human-readable channel name, kept in sync with the channels registered in
/// `main.dart`.
String channelNameFor(String channelId) => switch (channelId) {
  kPushCriticalChannel => 'Критичные события',
  kPushQuietChannel => 'Фоновые события',
  _ => 'Оповещения',
};

/// Human-readable channel description, kept in sync with `main.dart`.
String channelDescriptionFor(String channelId) => switch (channelId) {
  kPushCriticalChannel => 'Падение сервиса, сбои',
  kPushQuietChannel => 'Технические события',
  _ => 'Сообщения от ассистента и статуса',
};

/// Resolves a hub-supplied route (`chat`, `/status`, `terminal`, ...) to a tab.
/// Returns null when the value is empty or does not look like a known route.
PushTarget? targetFromRoute(String? raw) {
  final route = textOf(raw)?.toLowerCase();
  if (route == null) return null;
  if (route.contains('chat') ||
      route.contains('assistant') ||
      route.contains('opencode')) {
    return PushTarget.chat;
  }
  if (route.contains('terminal') ||
      route.contains('journal') ||
      route.contains('shell') ||
      route.contains('log')) {
    return PushTarget.terminal;
  }
  if (route.contains('control') ||
      route.contains('power') ||
      route.contains('reboot') ||
      route.contains('restart')) {
    return PushTarget.control;
  }
  if (route.contains('setup') ||
      route.contains('setting') ||
      route.contains('config')) {
    return PushTarget.settings;
  }
  if (route.contains('status') ||
      route.contains('monitor') ||
      route.contains('dashboard') ||
      route.contains('service') ||
      route.contains('home')) {
    return PushTarget.status;
  }
  return null;
}

/// Resolves an event `type` (`chat.message`, `service.down`, ...) to a tab.
PushTarget? targetFromType(String? raw) {
  final type = textOf(raw)?.toLowerCase();
  if (type == null) return null;
  if (type.contains('chat') ||
      type.contains('message') ||
      type.contains('assistant') ||
      type.contains('agent') ||
      type.contains('opencode')) {
    return PushTarget.chat;
  }
  if (type.contains('log') ||
      type.contains('journal') ||
      type.contains('terminal') ||
      type.contains('shell')) {
    return PushTarget.terminal;
  }
  if (type.contains('control') ||
      type.contains('power') ||
      type.contains('reboot') ||
      type.contains('restart')) {
    return PushTarget.control;
  }
  if (type.contains('setting') || type.contains('config')) {
    return PushTarget.settings;
  }
  if (type.contains('service') ||
      type.contains('status') ||
      type.contains('monitor') ||
      type.contains('crash') ||
      type.contains('error') ||
      type.contains('disk') ||
      type.contains('cpu') ||
      type.contains('memory')) {
    return PushTarget.status;
  }
  return null;
}

/// What a tap on a notification should do. Encoded into the local
/// notification payload as JSON so it survives the app being killed.
class PushPayload {
  const PushPayload({
    required this.target,
    this.severity = PushSeverity.alert,
    this.entityId,
    this.messageId,
  });

  final PushTarget target;
  final PushSeverity severity;
  final String? entityId;
  final String? messageId;

  /// Builds a payload from FCM `data`. [channelId] is the channel named by the
  /// FCM `notification.android` block, if any; it is the strongest hint about
  /// how loud the push should be.
  static PushPayload fromData(
    Map<String, dynamic> data, {
    String? messageId,
    String? channelId,
  }) {
    final severity =
        severityForChannel(textOf(data['channel_id'])) ??
        severityForChannel(channelId) ??
        severityFromText(textOf(data['severity'])) ??
        severityFromText(textOf(data['priority'])) ??
        severityFromText(textOf(data['importance'])) ??
        PushSeverity.alert;
    final route =
        textOf(data['route']) ??
        textOf(data['target']) ??
        textOf(data['screen']);
    final type = textOf(data['type']) ?? textOf(data['kind']);
    return PushPayload(
      target:
          targetFromRoute(route) ?? targetFromType(type) ?? PushTarget.status,
      severity: severity,
      entityId:
          textOf(data['entity_id']) ??
          textOf(data['entityId']) ??
          textOf(data['session_id']),
      messageId:
          messageId ?? textOf(data['message_id']) ?? textOf(data['messageId']),
    );
  }

  /// JSON payload for `flutter_local_notifications`; decoded by [decode].
  String encode() => jsonEncode({
    'v': 1,
    'target': target.name,
    'severity': severity.name,
    if (entityId != null) 'entity_id': entityId,
    if (messageId != null) 'message_id': messageId,
  });

  /// Decodes a payload produced by [encode]. Returns null for empty or
  /// non-JSON payloads so a legacy/plain payload cannot break tap handling.
  static PushPayload? decode(String? raw) {
    final value = textOf(raw);
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) return null;
      final map = <String, dynamic>{
        for (final entry in decoded.entries) entry.key.toString(): entry.value,
      };
      return PushPayload(
        target:
            _enumByName(PushTarget.values, textOf(map['target'])) ??
            targetFromRoute(textOf(map['route'])) ??
            targetFromType(textOf(map['type'])) ??
            PushTarget.status,
        severity:
            _enumByName(PushSeverity.values, textOf(map['severity'])) ??
            PushSeverity.alert,
        entityId: textOf(map['entity_id']),
        messageId: textOf(map['message_id']),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Remembers recently shown push ids so a re-delivered message does not draw a
/// second notification. The set is bounded: old keys are evicted in insertion
/// order.
class PushDedupe {
  PushDedupe({this.capacity = 64}) : assert(capacity > 0);

  final int capacity;
  final Set<String> _seen = <String>{};

  /// Returns true when [key] is new (or null/empty, which cannot be compared)
  /// and remembers it; false when the same key was already accepted.
  bool accept(String? key) {
    final value = textOf(key);
    if (value == null) return true;
    if (!_seen.add(value)) return false;
    if (_seen.length > capacity) _seen.remove(_seen.first);
    return true;
  }
}

/// Stable notification id for an FCM message. Prefers an explicit
/// `notification_id`, then the FCM message id, then a key derived from the
/// event so repeated deliveries replace instead of stack.
int notificationIdFor({
  String? messageId,
  Map<String, dynamic>? data,
  DateTime? sentTime,
}) {
  final explicit = int.tryParse(textOf(data?['notification_id']) ?? '');
  if (explicit != null) return explicit & 0x7fffffff;
  final key =
      textOf(messageId) ??
      '${sentTime?.millisecondsSinceEpoch ?? 0}:'
          '${textOf(data?['entity_id']) ?? ''}:'
          '${textOf(data?['type']) ?? ''}';
  return key.hashCode & 0x7fffffff;
}

/// Trims a value into a non-empty string, or null. FCM `data` is
/// `Map<String, dynamic>`, so numbers/bools are stringified rather than lost.
String? textOf(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

T? _enumByName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
