import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:news_erver/core/push/local_notifications.dart';
import 'package:news_erver/core/push/push_payload.dart';

void main() {
  group('severity', () {
    test('channel ids map onto the three importance classes', () {
      expect(severityForChannel(kPushCriticalChannel), PushSeverity.critical);
      expect(severityForChannel(kPushAlertChannel), PushSeverity.alert);
      expect(severityForChannel(kPushQuietChannel), PushSeverity.quiet);
      expect(severityForChannel('HUB_SILENT'), PushSeverity.quiet);
      expect(severityForChannel('other'), isNull);
      expect(severityForChannel(null), isNull);
      expect(severityForChannel('  '), isNull);
    });

    test('free-form severity aliases', () {
      for (final raw in ['critical', 'CRASH', 'fatal', 'emergency']) {
        expect(severityFromText(raw), PushSeverity.critical, reason: raw);
      }
      for (final raw in [
        'quiet',
        'silent',
        'low',
        'info',
        'debug',
        'background',
      ]) {
        expect(severityFromText(raw), PushSeverity.quiet, reason: raw);
      }
      for (final raw in [
        'alert',
        'important',
        'default',
        'normal',
        'high',
        'warning',
        'warn',
      ]) {
        expect(severityFromText(raw), PushSeverity.alert, reason: raw);
      }
      expect(severityFromText('nonsense'), isNull);
      expect(severityFromText(null), isNull);
    });

    test('every severity has a channel with a name and description', () {
      for (final severity in PushSeverity.values) {
        final channel = channelIdForSeverity(severity);
        expect(channel, isNotEmpty);
        expect(channelNameFor(channel), isNotEmpty);
        expect(channelDescriptionFor(channel), isNotEmpty);
      }
    });
  });

  group('payload from FCM data', () {
    test('explicit channel id wins over severity text', () {
      final payload = PushPayload.fromData({
        'channel_id': kPushQuietChannel,
        'severity': 'critical',
      });
      expect(payload.severity, PushSeverity.quiet);
    });

    test('notification channel is a fallback hint', () {
      final payload = PushPayload.fromData(
        const {},
        channelId: kPushCriticalChannel,
      );
      expect(payload.severity, PushSeverity.critical);
    });

    test('severity, priority and importance are understood', () {
      expect(
        PushPayload.fromData({'severity': 'quiet'}).severity,
        PushSeverity.quiet,
      );
      expect(
        PushPayload.fromData({'priority': 'critical'}).severity,
        PushSeverity.critical,
      );
      expect(
        PushPayload.fromData({'importance': 'low'}).severity,
        PushSeverity.quiet,
      );
    });

    test('defaults to a loud alert when nothing is specified', () {
      final payload = PushPayload.fromData(const {});
      expect(payload.severity, PushSeverity.alert);
      expect(payload.target, PushTarget.status);
    });

    test('route drives the target tab', () {
      for (final route in ['chat', '/chat', 'CHAT', 'assistant']) {
        expect(
          PushPayload.fromData({'route': route}).target,
          PushTarget.chat,
          reason: route,
        );
      }
      expect(
        PushPayload.fromData({'route': 'terminal'}).target,
        PushTarget.terminal,
      );
      expect(
        PushPayload.fromData({'route': 'control'}).target,
        PushTarget.control,
      );
      expect(
        PushPayload.fromData({'route': 'setup'}).target,
        PushTarget.settings,
      );
      expect(
        PushPayload.fromData({'route': 'status'}).target,
        PushTarget.status,
      );
    });

    test('type is used when the route is missing or unknown', () {
      expect(
        PushPayload.fromData({'type': 'chat.message'}).target,
        PushTarget.chat,
      );
      expect(
        PushPayload.fromData({'type': 'service.down'}).target,
        PushTarget.status,
      );
      expect(
        PushPayload.fromData({'type': 'log.line'}).target,
        PushTarget.terminal,
      );
      expect(
        PushPayload.fromData({'route': 'nonsense', 'type': 'log.line'}).target,
        PushTarget.terminal,
      );
    });

    test('entity and message ids are picked up', () {
      final payload = PushPayload.fromData({
        'entity_id': 'ses_1',
        'message_id': 'm-1',
      });
      expect(payload.entityId, 'ses_1');
      expect(payload.messageId, 'm-1');

      expect(PushPayload.fromData({'session_id': 'ses_2'}).entityId, 'ses_2');
      expect(
        PushPayload.fromData(const {}, messageId: 'fcm-1').messageId,
        'fcm-1',
      );
    });
  });

  group('encoded payload', () {
    test('round-trips through JSON', () {
      const original = PushPayload(
        target: PushTarget.chat,
        severity: PushSeverity.quiet,
        entityId: 'ses_1',
        messageId: 'm-1',
      );
      final decoded = PushPayload.decode(original.encode());
      expect(decoded, isNotNull);
      expect(decoded!.target, PushTarget.chat);
      expect(decoded.severity, PushSeverity.quiet);
      expect(decoded.entityId, 'ses_1');
      expect(decoded.messageId, 'm-1');
    });

    test('tolerates empty, plain and broken payloads', () {
      expect(PushPayload.decode(null), isNull);
      expect(PushPayload.decode('  '), isNull);
      expect(PushPayload.decode('chat'), isNull);
      expect(PushPayload.decode('{not json'), isNull);
      expect(PushPayload.decode('[]'), isNull);
    });

    test('falls back to route/type when target is absent', () {
      expect(
        PushPayload.decode('{"route":"terminal"}')!.target,
        PushTarget.terminal,
      );
      expect(
        PushPayload.decode('{"type":"chat.message"}')!.target,
        PushTarget.chat,
      );
      expect(PushPayload.decode('{}')!.target, PushTarget.status);
      expect(PushPayload.decode('{}')!.severity, PushSeverity.alert);
    });
  });

  group('dedupe', () {
    test('accepts a key once and ignores repeats', () {
      final dedupe = PushDedupe();
      expect(dedupe.accept('a'), isTrue);
      expect(dedupe.accept('a'), isFalse);
      expect(dedupe.accept(null), isTrue);
      expect(dedupe.accept('  '), isTrue);
    });

    test('evicts the oldest key beyond capacity', () {
      final dedupe = PushDedupe(capacity: 2);
      expect(dedupe.accept('a'), isTrue);
      expect(dedupe.accept('b'), isTrue);
      expect(dedupe.accept('c'), isTrue);
      expect(dedupe.accept('a'), isTrue);
    });
  });

  group('notification id', () {
    test('explicit id wins', () {
      expect(
        notificationIdFor(messageId: 'm-1', data: {'notification_id': '42'}),
        42,
      );
    });

    test('is stable for the same message', () {
      final first = notificationIdFor(messageId: 'm-1');
      final second = notificationIdFor(messageId: 'm-1');
      expect(first, second);
      expect(first, isNonNegative);
    });

    test('derives an id when the message id is missing', () {
      final id = notificationIdFor(
        data: {'entity_id': 'ses_1', 'type': 'chat.message'},
        sentTime: DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      expect(id, isNonNegative);
    });
  });

  group('display', () {
    test('a data-only ping without title or body is not shown', () async {
      // No title/body means no platform call, so this is safe in unit tests.
      final shown = await showPushNotification(
        FlutterLocalNotificationsPlugin(),
        const RemoteMessage(data: {}),
      );
      expect(shown, isFalse);
    });
  });
}
