import 'package:flutter_test/flutter_test.dart';
import 'package:news_erver/core/utils/formatters.dart';

void main() {
  test('blockBar fills proportionally', () {
    expect(blockBar(0, width: 5), '░░░░░');
    expect(blockBar(1, width: 5), '▓▓▓▓▓');
    expect(blockBar(0.5, width: 4), '▓▓░░');
    expect(blockBar(2, width: 3), '▓▓▓');
  });

  test('percentOf pads to a fixed width', () {
    expect(percentOf(4.2), '004%');
    expect(percentOf(42.6), '043%');
    expect(percentOf(120), '100%');
  });

  test('megabytes switches to GB above 1024', () {
    expect(megabytes(512), '512 MB');
    expect(megabytes(2048), '2.00 GB');
  });

  test('uptimeOf compacts durations', () {
    expect(uptimeOf(const Duration(minutes: 7)), '07m');
    expect(uptimeOf(const Duration(hours: 3, minutes: 5)), '03h 05m');
    expect(uptimeOf(const Duration(days: 2, hours: 4, minutes: 9)), '2d 04h 09m');
  });

  test('maskSecret hides all but a prefix', () {
    expect(maskSecret(''), '—');
    expect(maskSecret('abcd'), '••••');
    expect(maskSecret('AIzaSy1234567'), startsWith('AIza'));
    expect(maskSecret('AIzaSy1234567'), isNot(contains('1234567')));
  });
}
