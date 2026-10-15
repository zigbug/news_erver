import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_fonts.dart';
import '../../core/theme/retro_palette.dart';
import '../../core/theme/retro_palettes.dart';
import '../../core/theme/retro_theme.dart';
import '../../core/utils/formatters.dart';
import '../../features/settings/settings_cubit.dart';
import '../../features/settings/settings_state.dart';
import '../widgets/bar_meter.dart';
import '../widgets/glow_text.dart';
import '../widgets/retro_button.dart';
import '../widgets/retro_switch_row.dart';
import '../widgets/terminal_panel.dart';

/// Theme, CRT effects and the (not yet wired) connection config.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _serverId;
  late final TextEditingController _projectId;
  late final TextEditingController _apiKey;
  late final TextEditingController _region;
  late final TextEditingController _baseUrl;
  late final TextEditingController _token;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final connection = context.read<SettingsCubit>().state.settings.connection;
    _serverId = TextEditingController(text: connection.serverId);
    _projectId = TextEditingController(text: connection.firebaseProjectId);
    _apiKey = TextEditingController(text: connection.firebaseApiKey);
    _region = TextEditingController(text: connection.firebaseRegion);
    _baseUrl = TextEditingController(text: connection.apiBaseUrl);
    _token = TextEditingController(text: connection.apiToken);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final controller in [_serverId, _projectId, _apiKey, _region, _baseUrl, _token]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Persists the connection form 600 ms after the last keystroke.
  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final current = context.read<SettingsCubit>().state.settings.connection;
      context.read<SettingsCubit>().updateConnection(
        current.copyWith(
          serverId: _serverId.text.trim(),
          firebaseProjectId: _projectId.text.trim(),
          firebaseApiKey: _apiKey.text.trim(),
          firebaseRegion: _region.text.trim(),
          apiBaseUrl: _baseUrl.text.trim(),
          apiToken: _token.text.trim(),
        ),
      );
    });
  }

  Future<void> _resetConfirm() async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: GlowText('reset appearance?', size: 15, weight: FontWeight.w700),
        content: GlowText(
          'палитра, шрифт и CRT-эффекты вернутся к значениям по умолчанию.\nнастройки подключения останутся.',
          size: 12.5,
          color: palette.primaryDim,
          glow: false,
        ),
        actions: [
          RetroButton(label: 'N', onPressed: () => Navigator.of(context).pop(false)),
          RetroButton(
            label: 'Y',
            destructive: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      if (!mounted) return;
      await context.read<SettingsCubit>().resetToDefaults();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final settings = state.settings;
        final connection = settings.connection;
        final cubit = context.read<SettingsCubit>();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TerminalPanel(
                title: 'palette',
                trailing: Text(
                  settings.paletteId.toUpperCase(),
                  style: context.retroStyle(size: 10, color: palette.primaryDim, glow: false),
                ),
                child: SizedBox(
                  height: 76,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: RetroPalettes.all.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final option = RetroPalettes.all[i];
                      return _PaletteCard(
                        palette: option,
                        selected: option.id == settings.paletteId,
                        onTap: () => cubit.setPalette(option.id),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TerminalPanel(
                title: 'font',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        for (final mode in AppFontMode.values) ...[
                          Expanded(
                            child: RetroButton(
                              label: mode == AppFontMode.crt ? 'crt · vt323' : 'mono · jetbrains',
                              dense: true,
                              onPressed: () => cubit.setFontMode(mode.id),
                              subtitle: mode == AppFontMode.crt
                                  ? 'кириллица через fallback'
                                  : 'полная кириллица',
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'text size',
                      style: context.retroStyle(size: 11, color: palette.primaryDim, glow: false),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        RetroButton(
                          label: '−',
                          dense: true,
                          onPressed: settings.textScale <= 0.8
                              ? null
                              : () => cubit.setTextScale(settings.textScale - 0.1),
                        ),
                        const SizedBox(width: 10),
                        GlowText('${(settings.textScale * 100).round()}%', size: 14),
                        const SizedBox(width: 10),
                        RetroButton(
                          label: '+',
                          dense: true,
                          onPressed: settings.textScale >= 1.6
                              ? null
                              : () => cubit.setTextScale(settings.textScale + 0.1),
                        ),
                        const Spacer(),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'FRAGMENTED TYPE looks like this at 100%',
                            textAlign: TextAlign.right,
                            style: context.retroStyle(size: 11, color: palette.primaryDim, glow: false),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TerminalPanel(
                title: 'crt effects',
                child: Column(
                  children: [
                    RetroSwitchRow(
                      label: 'scanlines',
                      hint: 'горизонтальные линии развёртки',
                      value: settings.scanlines,
                      onChanged: cubit.setScanlines,
                    ),
                    const RetroRule(),
                    RetroSwitchRow(
                      label: 'phosphor glow',
                      hint: 'свечение текста платы',
                      value: settings.glow,
                      onChanged: cubit.setGlow,
                    ),
                    const RetroRule(),
                    RetroSwitchRow(
                      label: 'tube flicker',
                      hint: 'лёгкое мерцание экрана',
                      value: settings.flicker,
                      onChanged: cubit.setFlicker,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TerminalPanel(
                title: 'connection · firebase + api',
                accent: true,
                trailing: GlowText(
                  '${(connection.completeness * 100).round()}%',
                  size: 11,
                  color: palette.accent,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: palette.warning.withValues(alpha: 0.6)),
                        color: palette.warning.withValues(alpha: 0.08),
                      ),
                      child: Text(
                        'ДЕМО: поля сохраняются локально и пока не используются. '
                        'интеграция Firebase и API сервера — следующий шаг.',
                        style: context.retroStyle(size: 11, color: palette.warning, glow: false),
                      ),
                    ),
                    const SizedBox(height: 12),
                    BarMeter(
                      label: 'config',
                      ratio: connection.completeness,
                      width: 16,
                    ),
                    const SizedBox(height: 12),
                    _field('server id', _serverId, hint: 'srv-01'),
                    _field('firebase project id', _projectId, hint: 'my-server-console'),
                    _field('firebase web api key', _apiKey, obscure: true, hint: 'AIza…'),
                    _field('firebase region', _region, hint: 'europe-west1'),
                    _field('api base url', _baseUrl, hint: 'https://srv-01.lan:8443'),
                    _field('api token', _token, obscure: true, hint: 'bearer …'),
                    const SizedBox(height: 8),
                    Text(
                      'poll interval',
                      style: context.retroStyle(size: 11, color: palette.primaryDim, glow: false),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        RetroButton(
                          label: '−',
                          dense: true,
                          onPressed: connection.pollIntervalSeconds <= 1
                              ? null
                              : () => cubit.updateConnection(
                                  connection.copyWith(
                                    pollIntervalSeconds: connection.pollIntervalSeconds - 1,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 10),
                        GlowText('${connection.pollIntervalSeconds} s', size: 14),
                        const SizedBox(width: 10),
                        RetroButton(
                          label: '+',
                          dense: true,
                          onPressed: connection.pollIntervalSeconds >= 60
                              ? null
                              : () => cubit.updateConnection(
                                  connection.copyWith(
                                    pollIntervalSeconds: connection.pollIntervalSeconds + 1,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    RetroSwitchRow(
                      label: 'auto connect on boot',
                      hint: 'поднимать линию при запуске',
                      value: connection.autoConnect,
                      onChanged: cubit.setAutoConnect,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GlowText(
                            connection.firebaseConfigured
                                ? 'firebase: ready to wire'
                                : 'firebase: not configured',
                            size: 11,
                            color: connection.firebaseConfigured
                                ? palette.success
                                : palette.primaryDim,
                            glow: false,
                          ),
                        ),
                        GlowText(
                          connection.apiConfigured ? 'api: set' : 'api: unset',
                          size: 11,
                          color: connection.apiConfigured ? palette.success : palette.primaryDim,
                          glow: false,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TerminalPanel(
                title: 'maintenance',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: RetroButton(
                            label: 'reset appearance',
                            icon: Icons.restart_alt,
                            expand: true,
                            onPressed: _resetConfirm,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.savedAt == null
                          ? 'settings: defaults (nothing saved yet)'
                          : 'saved ${clockOf(state.savedAt!)}',
                      style: context.retroStyle(size: 10, color: palette.primaryDim, glow: false),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool obscure = false,
    String? hint,
  }) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.retroStyle(size: 11, color: palette.primaryDim, glow: false),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            obscureText: obscure,
            obscuringCharacter: '•',
            onChanged: (_) => _scheduleSave(),
            style: context.retroStyle(size: 13, letterSpacing: 0.4),
            decoration: InputDecoration(hintText: hint),
          ),
          if (obscure && controller.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'stored: ${maskSecret(controller.text)}',
                style: context.retroStyle(size: 10, color: palette.primaryDim, glow: false),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaletteCard extends StatelessWidget {
  const _PaletteCard({required this.palette, required this.selected, required this.onTap});

  final RetroPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? palette.accent : palette.border;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: palette.background,
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selected ? '▸ Aa 0123' : '  Aa 0123',
              maxLines: 1,
              style: TextStyle(
                fontFamily: AppFontMode.mono.family,
                fontSize: 12,
                color: palette.primary,
                shadows: [
                  Shadow(color: palette.primary.withValues(alpha: 0.5), blurRadius: 6),
                ],
              ),
            ),
            const Spacer(),
            Text(
              palette.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFontMode.mono.family,
                fontSize: 9,
                letterSpacing: 0.6,
                color: selected ? palette.accent : palette.primaryDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
