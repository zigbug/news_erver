import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:news_erver/data/api/opencode_event_parser.dart';

void main() {
  test('parses the opencode v1 {type, properties} shape', () {
    final event = parseOpencodeEvent({
      'type': 'message.part.delta',
      'properties': {
        'sessionID': 's1',
        'field': 'text',
        'partID': 'p1',
        'delta': 'hello',
      },
    });

    expect(event, isNotNull);
    expect(event!.type, 'message.part.delta');
    expect(event.data['sessionID'], 's1');
    expect(event.data['delta'], 'hello');
  });

  test('parses the opencode v2 {type, data} shape', () {
    final event = parseOpencodeEvent({
      'id': 'evt_1',
      'created': 1770000000000,
      'type': 'session.text.delta',
      'data': {
        'sessionID': 's1',
        'assistantMessageID': 'm1',
        'ordinal': 0,
        'delta': 'world',
      },
    });

    expect(event, isNotNull);
    expect(event!.type, 'session.text.delta');
    expect(event.data['sessionID'], 's1');
    expect(event.data['delta'], 'world');
  });

  test('unwraps a v2 SSE envelope whose data is a JSON string', () {
    const inner = {
      'id': 'evt_2',
      'type': 'session.text.delta',
      'data': {
        'sessionID': 's1',
        'assistantMessageID': 'm1',
        'ordinal': 0,
        'delta': 'chunk',
      },
    };

    final event = parseOpencodeEvent({
      'event': 'session.text.delta',
      'data': jsonEncode(inner),
    });

    expect(event, isNotNull);
    expect(event!.type, 'session.text.delta');
    expect(event.data['assistantMessageID'], 'm1');
    expect(event.data['delta'], 'chunk');
  });

  test('falls back to the SSE event line for bare payloads', () {
    final event = parseOpencodeEvent({
      'event': 'session.idle',
      'data': {'sessionID': 's1'},
    });

    expect(event, isNotNull);
    expect(event!.type, 'session.idle');
    expect(event.data['sessionID'], 's1');
  });

  test('ignores frames without a type or event name', () {
    expect(parseOpencodeEvent({'foo': 'bar'}), isNull);
  });
}
