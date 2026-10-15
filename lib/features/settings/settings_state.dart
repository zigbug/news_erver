import 'package:equatable/equatable.dart';

import '../../core/models/app_settings.dart';

class SettingsState extends Equatable {
  const SettingsState({
    this.settings = const AppSettings(),
    this.restored = false,
    this.savedAt,
  });

  final AppSettings settings;

  /// True once preferences have been read from disk. The app shows a boot
  /// sequence until then.
  final bool restored;

  /// Timestamp of the last successful write, surfaced in settings.
  final DateTime? savedAt;

  SettingsState copyWith({
    AppSettings? settings,
    bool? restored,
    DateTime? savedAt,
  }) {
    return SettingsState(
      settings: settings ?? this.settings,
      restored: restored ?? this.restored,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  @override
  List<Object?> get props => [settings, restored, savedAt];
}
