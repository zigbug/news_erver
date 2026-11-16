import 'dart:convert';

/// One event from opencode, normalised across API versions.
///
/// OpenCode v1 sends `{type, properties}`, v2 sends `{type, data}`, and the
/// v2 SSE endpoint wraps the whole thing in `{event, data}` where `data` may
/// itself be a JSON string. The chat only cares about the event name and its
/// payload, so this folds all those shapes into one.
class OpencodeEvent {
  const OpencodeEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;
}

/// Returns null for frames that carry no recognisable event.
OpencodeEvent? parseOpencodeEvent(Map<String, dynamic> raw) {
  // Standard SSE envelope: `event: <name>` plus `data: <payload>`.
  // OpenCode v2 may put the full event in `data` (as a JSON string or object);
  // if it does, prefer the nested event and only fall back to the envelope.
  final envelope = raw['event'];
  if (envelope is String && envelope.isNotEmpty) {
    Object? payload = raw['data'];
    if (payload is String) {
      try {
        payload = jsonDecode(payload);
      } catch (_) {
        // Keep the raw string; there is nothing to unwrap.
      }
    }
    if (payload is Map) {
      final nested = parseOpencodeEvent(payload.cast<String, dynamic>());
      if (nested != null) return nested;
      return OpencodeEvent(envelope, payload.cast<String, dynamic>());
    }
    return OpencodeEvent(envelope, const {});
  }

  final type = raw['type'];
  if (type is String && type.isNotEmpty) {
    final properties = raw['properties'];
    if (properties is Map) {
      return OpencodeEvent(type, properties.cast<String, dynamic>());
    }
    final data = raw['data'];
    if (data is Map) {
      return OpencodeEvent(type, data.cast<String, dynamic>());
    }
    // Old v1 events without a properties map — keep the frame itself.
    return OpencodeEvent(type, raw);
  }

  // An envelope that carries only a nested event.
  final data = raw['data'];
  if (data is Map) {
    return parseOpencodeEvent(data.cast<String, dynamic>());
  }
  return null;
}
