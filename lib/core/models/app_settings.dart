import 'package:equatable/equatable.dart';

/// Everything the app needs to reach the remote server.
///
/// Nothing here is wired to a network call yet: the demo shows the fields so
/// the shape is agreed before Firebase / the server API is plugged in.
class ConnectionSettings extends Equatable {
  const ConnectionSettings({
    this.serverId = 'srv-01',
    this.firebaseProjectId = '',
    this.firebaseApiKey = '',
    this.firebaseRegion = 'europe-west1',
    this.apiBaseUrl = '',
    this.apiToken = '',
    this.pollIntervalSeconds = 5,
    this.autoConnect = true,
  });

  /// Logical id of the machine this app watches (used for the Firebase path
  /// `servers/{serverId}/...`).
  final String serverId;

  final String firebaseProjectId;
  final String firebaseApiKey;
  final String firebaseRegion;

  /// Direct REST endpoint of the server agent, e.g. `https://host:8443`.
  final String apiBaseUrl;

  final String apiToken;

  final int pollIntervalSeconds;
  final bool autoConnect;

  bool get firebaseConfigured =>
      firebaseProjectId.trim().isNotEmpty && firebaseApiKey.trim().isNotEmpty;

  bool get apiConfigured => apiBaseUrl.trim().isNotEmpty;

  /// 0..1 completeness of the connection form, used by the settings screen.
  double get completeness {
    final fields = <bool>[
      serverId.trim().isNotEmpty,
      firebaseProjectId.trim().isNotEmpty,
      firebaseApiKey.trim().isNotEmpty,
      apiBaseUrl.trim().isNotEmpty,
    ];
    return fields.where((f) => f).length / fields.length;
  }

  ConnectionSettings copyWith({
    String? serverId,
    String? firebaseProjectId,
    String? firebaseApiKey,
    String? firebaseRegion,
    String? apiBaseUrl,
    String? apiToken,
    int? pollIntervalSeconds,
    bool? autoConnect,
  }) {
    return ConnectionSettings(
      serverId: serverId ?? this.serverId,
      firebaseProjectId: firebaseProjectId ?? this.firebaseProjectId,
      firebaseApiKey: firebaseApiKey ?? this.firebaseApiKey,
      firebaseRegion: firebaseRegion ?? this.firebaseRegion,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      apiToken: apiToken ?? this.apiToken,
      pollIntervalSeconds: pollIntervalSeconds ?? this.pollIntervalSeconds,
      autoConnect: autoConnect ?? this.autoConnect,
    );
  }

  Map<String, dynamic> toJson() => {
    'serverId': serverId,
    'firebaseProjectId': firebaseProjectId,
    'firebaseApiKey': firebaseApiKey,
    'firebaseRegion': firebaseRegion,
    'apiBaseUrl': apiBaseUrl,
    'apiToken': apiToken,
    'pollIntervalSeconds': pollIntervalSeconds,
    'autoConnect': autoConnect,
  };

  factory ConnectionSettings.fromJson(Map<String, dynamic> json) {
    return ConnectionSettings(
      serverId: json['serverId'] as String? ?? 'srv-01',
      firebaseProjectId: json['firebaseProjectId'] as String? ?? '',
      firebaseApiKey: json['firebaseApiKey'] as String? ?? '',
      firebaseRegion: json['firebaseRegion'] as String? ?? 'europe-west1',
      apiBaseUrl: json['apiBaseUrl'] as String? ?? '',
      apiToken: json['apiToken'] as String? ?? '',
      pollIntervalSeconds: (json['pollIntervalSeconds'] as num?)?.toInt() ?? 5,
      autoConnect: json['autoConnect'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => [
    serverId,
    firebaseProjectId,
    firebaseApiKey,
    firebaseRegion,
    apiBaseUrl,
    apiToken,
    pollIntervalSeconds,
    autoConnect,
  ];
}

/// All persisted user preferences.
class AppSettings extends Equatable {
  const AppSettings({
    this.paletteId = 'phosphor_green',
    this.fontModeId = 'crt',
    this.glow = true,
    this.scanlines = true,
    this.flicker = true,
    this.textScale = 1.0,
    this.connection = const ConnectionSettings(),
  });

  final String paletteId;
  final String fontModeId;
  final bool glow;
  final bool scanlines;
  final bool flicker;
  final double textScale;
  final ConnectionSettings connection;

  AppSettings copyWith({
    String? paletteId,
    String? fontModeId,
    bool? glow,
    bool? scanlines,
    bool? flicker,
    double? textScale,
    ConnectionSettings? connection,
  }) {
    return AppSettings(
      paletteId: paletteId ?? this.paletteId,
      fontModeId: fontModeId ?? this.fontModeId,
      glow: glow ?? this.glow,
      scanlines: scanlines ?? this.scanlines,
      flicker: flicker ?? this.flicker,
      textScale: textScale ?? this.textScale,
      connection: connection ?? this.connection,
    );
  }

  Map<String, dynamic> toJson() => {
    'paletteId': paletteId,
    'fontModeId': fontModeId,
    'glow': glow,
    'scanlines': scanlines,
    'flicker': flicker,
    'textScale': textScale,
    'connection': connection.toJson(),
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      paletteId: json['paletteId'] as String? ?? 'phosphor_green',
      fontModeId: json['fontModeId'] as String? ?? 'crt',
      glow: json['glow'] as bool? ?? true,
      scanlines: json['scanlines'] as bool? ?? true,
      flicker: json['flicker'] as bool? ?? true,
      textScale: (json['textScale'] as num?)?.toDouble() ?? 1.0,
      connection: ConnectionSettings.fromJson(
        (json['connection'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }

  @override
  List<Object?> get props => [
    paletteId,
    fontModeId,
    glow,
    scanlines,
    flicker,
    textScale,
    connection,
  ];
}
