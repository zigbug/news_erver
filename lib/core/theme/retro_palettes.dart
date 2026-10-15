import 'package:flutter/material.dart';

import 'retro_palette.dart';

/// Built-in palettes. The first one, [phosphorGreen], is the app default.
abstract final class RetroPalettes {
  static const RetroPalette phosphorGreen = RetroPalette(
    id: 'phosphor_green',
    name: 'PHOSPHOR P1',
    brightness: Brightness.dark,
    background: Color(0xFF030703),
    surface: Color(0xFF071108),
    surfaceAlt: Color(0xFF0B1A0C),
    border: Color(0xFF1F4D25),
    primary: Color(0xFF33FF66),
    primaryDim: Color(0xFF1E8F3A),
    accent: Color(0xFF9BFFB8),
    success: Color(0xFF33FF66),
    warning: Color(0xFFFFD24A),
    error: Color(0xFFFF5A4A),
    glowStrength: 0.85,
    scanlineOpacity: 0.16,
  );

  static const RetroPalette amber = RetroPalette(
    id: 'amber_p3',
    name: 'AMBER P3',
    brightness: Brightness.dark,
    background: Color(0xFF0A0602),
    surface: Color(0xFF140C03),
    surfaceAlt: Color(0xFF1E1305),
    border: Color(0xFF5B3B0C),
    primary: Color(0xFFFFB000),
    primaryDim: Color(0xFF8F6200),
    accent: Color(0xFFFFE08A),
    success: Color(0xFFB9FF6A),
    warning: Color(0xFFFFD24A),
    error: Color(0xFFFF6B3D),
    glowStrength: 0.85,
    scanlineOpacity: 0.16,
  );

  static const RetroPalette iceCyan = RetroPalette(
    id: 'ice_cyan',
    name: 'ICE CGA',
    brightness: Brightness.dark,
    background: Color(0xFF02060B),
    surface: Color(0xFF05121C),
    surfaceAlt: Color(0xFF08202F),
    border: Color(0xFF1D5A73),
    primary: Color(0xFF6FE3FF),
    primaryDim: Color(0xFF2E7C93),
    accent: Color(0xFFBFF4FF),
    success: Color(0xFF5CFFC4),
    warning: Color(0xFFFFD24A),
    error: Color(0xFFFF6688),
    glowStrength: 0.8,
    scanlineOpacity: 0.14,
  );

  static const RetroPalette grayCrt = RetroPalette(
    id: 'gray_crt',
    name: 'MONO CRT',
    brightness: Brightness.dark,
    background: Color(0xFF0A0A0A),
    surface: Color(0xFF141414),
    surfaceAlt: Color(0xFF1D1D1D),
    border: Color(0xFF3A3A3A),
    primary: Color(0xFFD8D8D8),
    primaryDim: Color(0xFF7A7A7A),
    accent: Color(0xFFFFFFFF),
    success: Color(0xFFB6FFB6),
    warning: Color(0xFFE8E8A0),
    error: Color(0xFFFF9B9B),
    glowStrength: 0.5,
    scanlineOpacity: 0.12,
  );

  static const RetroPalette paper = RetroPalette(
    id: 'paper',
    name: 'PAPER READER',
    brightness: Brightness.light,
    background: Color(0xFFE9E2CF),
    surface: Color(0xFFF3EDDD),
    surfaceAlt: Color(0xFFDFD6BE),
    border: Color(0xFF9C8F6E),
    primary: Color(0xFF17251A),
    primaryDim: Color(0xFF5C6B57),
    accent: Color(0xFF1D4E2A),
    success: Color(0xFF1D6B2A),
    warning: Color(0xFF8A6300),
    error: Color(0xFF9B2222),
    glowStrength: 0.0,
    scanlineOpacity: 0.05,
  );

  static const List<RetroPalette> all = [
    phosphorGreen,
    amber,
    iceCyan,
    grayCrt,
    paper,
  ];

  static RetroPalette byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => phosphorGreen);
}
