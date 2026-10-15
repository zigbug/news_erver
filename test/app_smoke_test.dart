import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:news_erver/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Boots the whole demo app and walks every tab, failing on the first
/// exception. Catches layout regressions (unbounded viewports etc.) that the
/// unit tests cannot see.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boots and every tab renders without exceptions', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const RetroConsoleApp());

    // Boot sequence, then the shell with an auto-connecting link.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      _expectNoException(tester, 'boot frame $i');
    }

    for (final tab in ['STATUS', 'CHAT', 'CONTROL', 'SETUP', 'TERMINAL']) {
      await tester.tap(find.text(tab));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        _expectNoException(tester, 'tab $tab frame $i');
      }
    }
  });

  testWidgets('crt effects and palette can be toggled', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const RetroConsoleApp());
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 300));
      _expectNoException(tester, 'boot frame $i');
    }

    await tester.tap(find.text('SETUP'));
    await tester.pump(const Duration(milliseconds: 300));
    _expectNoException(tester, 'setup open');

    for (final label in ['SCANLINES', 'PHOSPHOR GLOW', 'TUBE FLICKER']) {
      final finder = find.text(label);
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(finder);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 300));
        _expectNoException(tester, 'toggle $label');
      }
    }

    final fontButton = find.textContaining('JETBRAINS');
    await tester.ensureVisible(fontButton);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(fontButton);
    await tester.pump(const Duration(milliseconds: 300));
    _expectNoException(tester, 'font switch');
  });
}

void _expectNoException(WidgetTester tester, String stage) {
  final error = tester.takeException();
  if (error != null) {
    debugPrint('=== EXCEPTION during $stage ===\n$error');
    fail('exception during $stage: $error');
  }
}
