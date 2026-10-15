/// Small formatting helpers used across the retro UI.
library;

String pad2(int value) => value.toString().padLeft(2, '0');

/// `HH:mm:ss`
String clockOf(DateTime t) => '${pad2(t.hour)}:${pad2(t.minute)}:${pad2(t.second)}';

/// `HH:mm`
String hhmmOf(DateTime t) => '${pad2(t.hour)}:${pad2(t.minute)}';

/// Fixed-width percentage, e.g. `042%`.
String percentOf(double value, {int width = 3}) {
  final v = value.clamp(0, 100).round().toString();
  return '${v.padLeft(width, '0')}%';
}

/// Memory in MB or GB.
String megabytes(double mb) =>
    mb >= 1024 ? '${(mb / 1024).toStringAsFixed(2)} GB' : '${mb.round()} MB';

/// Compact uptime label, e.g. `3d 04h 21m`.
String uptimeOf(Duration d) {
  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;
  if (days > 0) return '${days}d ${pad2(hours)}h ${pad2(minutes)}m';
  if (hours > 0) return '${pad2(hours)}h ${pad2(minutes)}m';
  return '${pad2(minutes)}m';
}

/// Builds a retro progress bar: `▓▓▓▓░░░░░░`.
String blockBar(double ratio, {int width = 10, String filled = '▓', String empty = '░'}) {
  final clamped = ratio.clamp(0.0, 1.0);
  final on = (clamped * width).round();
  return filled * on + empty * (width - on);
}

/// Masks a secret for display: `abcd••••••`.
String maskSecret(String value, {int visible = 4}) {
  if (value.isEmpty) return '—';
  if (value.length <= visible) return '•' * value.length;
  return '${value.substring(0, visible)}${'•' * (value.length - visible).clamp(0, 8)}';
}
