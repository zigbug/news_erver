import 'package:flutter_test/flutter_test.dart';
import 'package:news_erver/core/models/app_settings.dart';
import 'package:news_erver/core/theme/app_fonts.dart';
import 'package:news_erver/core/theme/retro_palettes.dart';
import 'package:news_erver/core/theme/retro_theme.dart';

void main() {
  group('RetroPalettes', () {
    test('falls back to the default palette for unknown ids', () {
      expect(RetroPalettes.byId('nope').id, RetroPalettes.phosphorGreen.id);
      expect(RetroPalettes.byId(null).id, RetroPalettes.phosphorGreen.id);
    });

    test('every palette is reachable by id', () {
      for (final palette in RetroPalettes.all) {
        expect(RetroPalettes.byId(palette.id).id, palette.id);
      }
    });
  });

  group('RetroTheme.fromSettings', () {
    test('maps palette, font mode and effect switches', () {
      const settings = AppSettings(
        paletteId: 'amber_p3',
        fontModeId: 'mono',
        glow: false,
        scanlines: false,
        flicker: false,
        textScale: 1.2,
      );

      final retro = RetroTheme.fromSettings(settings);

      expect(retro.palette.id, 'amber_p3');
      expect(retro.fontMode, AppFontMode.mono);
      expect(retro.scanlines, isFalse);
      expect(retro.flicker, isFalse);
      expect(retro.textScale, 1.2);
      expect(retro.glowActive, isFalse);
      expect(retro.glowShadows(), isEmpty);
    });

    test('crt font is drawn larger than mono at the same size', () {
      final crt = RetroTheme.fromSettings(const AppSettings(fontModeId: 'crt'));
      final mono = RetroTheme.fromSettings(const AppSettings(fontModeId: 'mono'));

      final crtSize = crt.style(size: 14).fontSize!;
      final monoSize = mono.style(size: 14).fontSize!;

      expect(crtSize, greaterThan(monoSize));
    });

    test('paper palette disables the phosphor glow', () {
      final retro = RetroTheme.fromSettings(const AppSettings());
      final paper = RetroTheme.fromSettings(
        const AppSettings(paletteId: 'paper'),
      );

      expect(retro.glowActive, isTrue);
      expect(paper.glowActive, isFalse);
    });
  });
}
