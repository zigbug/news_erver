import 'package:flutter_test/flutter_test.dart';
import 'package:news_erver/core/models/app_settings.dart';
import 'package:news_erver/features/settings/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('starts with defaults and marks itself restored', () async {
    final cubit = SettingsCubit();
    await cubit.init();

    expect(cubit.state.restored, isTrue);
    expect(cubit.state.settings.paletteId, 'phosphor_green');
    expect(cubit.state.savedAt, isNull);
    await cubit.close();
  });

  test('persists palette, effects and connection across restarts', () async {
    final first = SettingsCubit();
    await first.init();
    await first.setPalette('amber_p3');
    await first.setFontMode('mono');
    await first.setGlow(false);
    await first.setTextScale(1.4);
    await first.updateConnection(
      const ConnectionSettings(
        serverId: 'srv-42',
        firebaseProjectId: 'demo-project',
        apiBaseUrl: 'https://srv-42.lan:8443',
        pollIntervalSeconds: 12,
      ),
    );
    expect(first.state.savedAt, isNotNull);
    await first.close();

    final second = SettingsCubit();
    await second.init();

    expect(second.state.settings.paletteId, 'amber_p3');
    expect(second.state.settings.fontModeId, 'mono');
    expect(second.state.settings.glow, isFalse);
    expect(second.state.settings.textScale, 1.4);
    expect(second.state.settings.connection.serverId, 'srv-42');
    expect(second.state.settings.connection.firebaseProjectId, 'demo-project');
    expect(second.state.settings.connection.pollIntervalSeconds, 12);
    expect(second.state.settings.connection.apiConfigured, isTrue);
    await second.close();
  });

  test('clamps text scale and survives corrupted storage', () async {
    SharedPreferences.setMockInitialValues({
      SettingsCubit.storageKey: '{not json',
    });

    final cubit = SettingsCubit();
    await cubit.init();
    expect(cubit.state.settings.paletteId, 'phosphor_green');

    await cubit.setTextScale(4);
    expect(cubit.state.settings.textScale, 1.6);
    await cubit.setTextScale(0.1);
    expect(cubit.state.settings.textScale, 0.8);
    await cubit.close();
  });
}
