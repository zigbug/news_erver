import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/app_settings.dart';
import 'settings_state.dart';

/// Single source of truth for user preferences: palette, font, CRT effects and
/// the (not yet wired) connection config. Persisted as JSON in
/// [SharedPreferences].
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({SharedPreferences? prefs}) : _prefs = prefs, super(const SettingsState());

  static const String storageKey = 'retro_settings_v1';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs?.getString(storageKey);
    AppSettings settings = const AppSettings();
    if (raw != null && raw.isNotEmpty) {
      try {
        settings = AppSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        settings = const AppSettings();
      }
    }
    emit(SettingsState(settings: settings, restored: true));
  }

  Future<void> _persist(AppSettings settings) async {
    final raw = jsonEncode(settings.toJson());
    await _prefs?.setString(storageKey, raw);
    emit(state.copyWith(settings: settings, savedAt: DateTime.now()));
  }

  Future<void> setPalette(String paletteId) =>
      _persist(state.settings.copyWith(paletteId: paletteId));

  Future<void> setFontMode(String fontModeId) =>
      _persist(state.settings.copyWith(fontModeId: fontModeId));

  Future<void> setGlow(bool value) => _persist(state.settings.copyWith(glow: value));

  Future<void> setScanlines(bool value) =>
      _persist(state.settings.copyWith(scanlines: value));

  Future<void> setFlicker(bool value) =>
      _persist(state.settings.copyWith(flicker: value));

  Future<void> setTextScale(double value) =>
      _persist(state.settings.copyWith(textScale: value.clamp(0.8, 1.6)));

  Future<void> updateConnection(ConnectionSettings connection) =>
      _persist(state.settings.copyWith(connection: connection));

  Future<void> setAutoConnect(bool value) => _persist(
    state.settings.copyWith(
      connection: state.settings.connection.copyWith(autoConnect: value),
    ),
  );

  Future<void> resetToDefaults() => _persist(const AppSettings());
}
