import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../controllers/session_controller.dart';
import '../../controllers/settings_controller.dart';
import '../../l10n/app_localizations.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.controller,
    required this.sessionController,
  });

  final SettingsController controller;
  final SessionController sessionController;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  static const _accentOptions = <Color>[
    Color(0xFF6C6CFF),
    Color(0xFF4DD0E1),
    Color(0xFFFF7043),
    Color(0xFF7E57C2),
    Color(0xFF26C6DA),
    Color(0xFF03DAC5),
    Color(0xFFEF5350),
  ];

  static const _fontOptions = <String>['Outfit', 'Inter', 'Space Grotesk'];

  late final TextEditingController _manualHostController;
  late final TextEditingController _manualPortController;
  bool _isSavingConnection = false;

  @override
  void initState() {
    super.initState();
    final session = widget.sessionController;
    _manualHostController = TextEditingController(text: session.host ?? '');
    _manualPortController =
        TextEditingController(text: session.port.toString());
  }

  @override
  void dispose() {
    _manualHostController.dispose();
    _manualPortController.dispose();
    super.dispose();
  }

  Future<void> _saveManualConnection() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final host = _manualHostController.text.trim();
    final portValue = int.tryParse(_manualPortController.text.trim());
    if (host.isEmpty || portValue == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.translate('settings_connection_invalid')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    setState(() => _isSavingConnection = true);
    await widget.sessionController.setConnection(
      host: host,
      port: portValue,
    );
    if (!mounted) return;
    setState(() => _isSavingConnection = false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.translate('settings_connection_saved')),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _openLink(String url) async {
    final launched = await launchUrlString(url, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      final l10n = context.l10n;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l10n
                  .translate('settings_link_error')
                  .replaceFirst('{url}', url),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  TextStyle? _sectionTitleStyle(ThemeData theme) {
    return theme.textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w700,
      fontSize: 18,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final selectedLanguage =
            controller.localeOverride?.languageCode ?? 'system';
        final selectedTheme = controller.themeMode;
        final accentColor = controller.accentColor;

        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, bottomInset + 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: l10n.translate('settings_close'),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Text(
                        l10n.translate('settings_title'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.translate('settings_section_general'),
                  style: _sectionTitleStyle(theme),
                ),
                const SizedBox(height: 12),
                Text(l10n.translate('settings_language_label'),
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'system',
                      label: Text(l10n.translate('settings_language_system')),
                    ),
                    ButtonSegment(
                      value: 'en',
                      label: Text(l10n.translate('settings_language_en')),
                    ),
                    ButtonSegment(
                      value: 'tr',
                      label: Text(l10n.translate('settings_language_tr')),
                    ),
                  ],
                  selected: {selectedLanguage},
                  onSelectionChanged: (value) {
                    final next = value.first;
                    controller.setLocaleOverride(
                      next == 'system' ? null : next,
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text(l10n.translate('settings_text_size'),
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: controller.textScale,
                        min: 0.9,
                        max: 1.3,
                        divisions: 8,
                        onChanged: (value) {
                          controller.setTextScale(value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${(controller.textScale * 100).round()}%',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.translate('settings_section_appearance'),
                  style: _sectionTitleStyle(theme),
                ),
                const SizedBox(height: 12),
                Text(l10n.translate('settings_theme_label'),
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(l10n.translate('settings_theme_system')),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(l10n.translate('settings_theme_light')),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(l10n.translate('settings_theme_dark')),
                    ),
                  ],
                  selected: {selectedTheme},
                  onSelectionChanged: (value) {
                    controller.setThemeMode(value.first);
                  },
                ),
                const SizedBox(height: 16),
                Text(l10n.translate('settings_font_label'),
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: controller.bodyFont,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  items: _fontOptions
                      .map(
                        (font) => DropdownMenuItem(
                          value: font,
                          child: Text(font),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      controller.setBodyFont(value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text(l10n.translate('settings_accent_color'),
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _accentOptions
                      .map((color) => GestureDetector(
                            onTap: () => controller.setAccentColor(color),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color,
                                border: Border.all(
                                  color:
                                      color.value == accentColor.value
                                          ? theme.colorScheme.onPrimary
                                          : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: controller.useShader,
                  onChanged: (value) {
                    controller.setShaderEnabled(value);
                  },
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.translate('settings_shader_label')),
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.translate('settings_section_chat'),
                  style: _sectionTitleStyle(theme),
                ),
                const SizedBox(height: 12),
                Text(l10n.translate('settings_temperature_label'),
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: widget.sessionController.temperature,
                        min: 0.1,
                        max: 1.5,
                        divisions: 14,
                        label: widget.sessionController.temperature
                            .toStringAsFixed(2),
                        onChanged: (value) {
                          widget.sessionController.updateTemperature(value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        widget.sessionController.temperature
                            .toStringAsFixed(2),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.translate('settings_section_connection'),
                  style: _sectionTitleStyle(theme),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _manualHostController,
                        decoration: InputDecoration(
                          labelText:
                              l10n.translate('settings_connection_host'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _manualPortController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText:
                              l10n.translate('settings_connection_port'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _isSavingConnection ? null : _saveManualConnection,
                    child: _isSavingConnection
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.translate('settings_connection_save')),
                  ),
                ),
                const SizedBox(height: 24),
                Divider(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.translate('settings_about_title'),
                  style: _sectionTitleStyle(theme),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.translate('settings_about_description'),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () =>
                      _openLink('https://github.com/fatih'),
                  icon: const Icon(Icons.link_rounded),
                  label: Text(l10n.translate('settings_about_action')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
