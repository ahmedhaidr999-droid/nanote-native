import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/settings_controller.dart';
import '../../i18n/strings.dart';
import '../../services/backup_service.dart';
import '../../theme/nanote_theme.dart';

/// Settings ('/settings'): Appearance / Writing / Pens / Stickers /
/// Translation / Data (backup & restore) / About.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  // ------------------------------------------------------------------- data

  Future<void> _createBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await BackupService.createBackup();
      if (!mounted) return;
      if (path != null) {
        await Share.shareXFiles([XFile(path)]);
        if (mounted) {
          messenger.showSnackBar(
              SnackBar(content: Text(S.t('backupCreated'))));
        }
      } else {
        messenger.showSnackBar(
            SnackBar(content: Text(S.t('backupFailed'))));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(S.t('backupFailed'))));
      }
    }
  }

  Future<void> _restoreBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.t('restoreBackup')),
        content: Text(S.t('restoreConfirmWipe')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.t('confirm')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['nanote'],
    );
    final files = res?.files;
    final path = (files != null && files.isNotEmpty) ? files.first.path : null;
    if (path == null || !mounted) return;
    final success = await BackupService.restoreBackup(File(path));
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
        content:
            Text(success ? S.t('restoreDone') : S.t('restoreFailed'))));
    if (success) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
    }
  }

  Future<void> _checkUpdates() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(
        Uri.parse('https://github.com/ahmedhaidr999-droid/nanote-native/releases'),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(S.t('updateCheckFailed'))));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
            SnackBar(content: Text(S.t('updateCheckFailed'))));
      }
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('settings'))),
      body: ListenableBuilder(
        listenable: SettingsController.I,
        builder: (context, _) {
          final s = SettingsController.I.settings;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              // ------------------------------------------------- appearance
              _header(context, 'appearance'),
              _card(context, children: [
                _control(
                  context,
                  label: S.t('themeMode'),
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'light',
                        label: Text(S.t('themeLight')),
                        icon: const Icon(Icons.light_mode_outlined),
                      ),
                      ButtonSegment(
                        value: 'dark',
                        label: Text(S.t('themeDark')),
                        icon: const Icon(Icons.dark_mode_outlined),
                      ),
                      ButtonSegment(
                        value: 'system',
                        label: Text(S.t('themeSystem')),
                        icon: const Icon(Icons.brightness_auto_outlined),
                      ),
                    ],
                    selected: {s.themeMode},
                    onSelectionChanged: (sel) =>
                        SettingsController.I.setThemeMode(sel.first),
                  ),
                ),
                _control(
                  context,
                  label: S.t('language'),
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'en', label: Text(S.t('english'))),
                      ButtonSegment(value: 'ar', label: Text(S.t('arabic'))),
                    ],
                    selected: {s.lang},
                    onSelectionChanged: (sel) =>
                        SettingsController.I.setLang(sel.first),
                  ),
                ),
                SwitchListTile(
                  value: s.leftHanded,
                  onChanged: (v) => SettingsController.I.setLeftHanded(v),
                  title: Text(S.t('leftHanded')),
                  subtitle: Text(S.t('leftHandedHint')),
                ),
              ]),

              // ---------------------------------------------------- writing
              _header(context, 'writing'),
              _card(context, children: [
                _sliderTile(
                  context,
                  label: S.t('pressureCurve'),
                  value: s.pressureCurve,
                  min: 0.4,
                  max: 2.5,
                  divisions: 21,
                  format: (v) => v.toStringAsFixed(2),
                  onChanged: (v) => SettingsController.I.setPressureCurve(v),
                  endLabels: [
                    S.t('curveFirm'),
                    S.t('curveLinear'),
                    S.t('curveSoft'),
                  ],
                ),
                SwitchListTile(
                  value: s.drawWithFinger,
                  onChanged: (v) => SettingsController.I.setDrawWithFinger(v),
                  title: Text(S.t('drawWithFinger')),
                  subtitle: Text(S.t('drawWithFingerHint')),
                ),
                SwitchListTile(
                  value: s.shapeDetection,
                  onChanged: (v) => SettingsController.I.setShapeDetection(v),
                  title: Text(S.t('shapeDetection')),
                ),
                _sliderTile(
                  context,
                  label: S.t('highlighterOpacity'),
                  value: s.highlighterOpacity,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  format: (v) => '${(v * 100).round()}%',
                  onChanged: (v) =>
                      SettingsController.I.setHighlighterOpacity(v),
                ),
                _control(
                  context,
                  label: S.t('autosave'),
                  child: SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                          value: 0, label: Text(S.t('autosaveNow'))),
                      ButtonSegment(
                          value: 1000, label: Text(S.t('autosave1s'))),
                      ButtonSegment(
                          value: 5000, label: Text(S.t('autosave5s'))),
                    ],
                    selected: {s.autosaveDelayMs},
                    onSelectionChanged: (sel) =>
                        SettingsController.I.setAutosaveDelayMs(sel.first),
                  ),
                ),
              ]),

              // ------------------------------------------------------- pens
              _header(context, 'pens'),
              _card(context, children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(S.t('penManager')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/pen'),
                ),
              ]),

              // --------------------------------------------------- stickers
              _header(context, 'stickerPicker'),
              _card(context, children: [
                ListTile(
                  leading: const Icon(Icons.emoji_emotions_outlined),
                  title: Text(S.t('stickerManager')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/stickers'),
                ),
              ]),

              // ------------------------------------------------- translation
              _header(context, 'translation'),
              _card(context, children: [
                _label(context, S.t('translateEngine')),
                RadioListTile<String>(
                  value: 'nanote',
                  groupValue: s.translateEngine,
                  title: Text(S.t('engineNanote')),
                  onChanged: (v) {
                    if (v != null) SettingsController.I.setTranslateEngine(v);
                  },
                ),
                RadioListTile<String>(
                  value: 'google',
                  groupValue: s.translateEngine,
                  title: Text(S.t('engineGoogle')),
                  onChanged: (v) {
                    if (v != null) SettingsController.I.setTranslateEngine(v);
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _label(context, S.t('targetLanguage')),
                RadioListTile<String>(
                  value: 'auto',
                  groupValue: s.translateTarget,
                  title: Text(S.t('targetAuto')),
                  onChanged: (v) {
                    if (v != null) SettingsController.I.setTranslateTarget(v);
                  },
                ),
                RadioListTile<String>(
                  value: 'ar',
                  groupValue: s.translateTarget,
                  title: Text(S.t('arabic')),
                  onChanged: (v) {
                    if (v != null) SettingsController.I.setTranslateTarget(v);
                  },
                ),
                RadioListTile<String>(
                  value: 'en',
                  groupValue: s.translateTarget,
                  title: Text(S.t('english')),
                  onChanged: (v) {
                    if (v != null) SettingsController.I.setTranslateTarget(v);
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _control(
                  context,
                  label: S.t('askAi'),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'chatgpt', label: Text('ChatGPT')),
                      ButtonSegment(value: 'gemini', label: Text('Gemini')),
                      ButtonSegment(value: 'claude', label: Text('Claude')),
                    ],
                    selected: {s.aiService},
                    onSelectionChanged: (sel) =>
                        SettingsController.I.setAiService(sel.first),
                  ),
                ),
              ]),

              // ------------------------------------------------------- data
              _header(context, 'data'),
              _card(context, children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(S.t('backupRestore'),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48,
                        child: FilledButton.tonalIcon(
                          onPressed: _createBackup,
                          icon: const Icon(Icons.archive_outlined),
                          label: Text(S.t('createBackup')),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _restoreBackup,
                          icon: const Icon(Icons.settings_backup_restore),
                          label: Text(S.t('restoreBackup')),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _caption(
                          context, Icons.phone_iphone, S.t('dataHint')),
                      const SizedBox(height: 4),
                      _caption(
                          context, Icons.wifi_off_outlined, S.t('privacy')),
                    ],
                  ),
                ),
              ]),

              // ------------------------------------------------------ about
              _header(context, 'about'),
              _card(context, children: [
                ListTile(
                  title: Text(S.t('version')),
                  trailing: const Text(
                    '2.0.0',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.system_update_alt),
                  title: Text(S.t('checkUpdates')),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: _checkUpdates,
                ),
              ]),

              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------- helpers

  Widget _header(BuildContext context, String key) {
    final nc = nanoteColors(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(
        S.t(key).toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: nc.mutedFg,
        ),
      ),
    );
  }

  Widget _card(BuildContext context, {required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }

  Widget _control(
    BuildContext context, {
    required String label,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: child),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(label,
          style:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    );
  }

  Widget _sliderTile(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) format,
    required ValueChanged<double> onChanged,
    List<String>? endLabels,
  }) {
    final nc = nanoteColors(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              Text(format(value),
                  style: TextStyle(fontSize: 12, color: nc.mutedFg)),
            ],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            label: format(value),
            onChanged: onChanged,
          ),
          if (endLabels != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final l in endLabels)
                    Text(l,
                        style:
                            TextStyle(fontSize: 10, color: nc.mutedFg)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _caption(BuildContext context, IconData icon, String text) {
    final nc = nanoteColors(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: nc.mutedFg),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: nc.mutedFg),
          ),
        ),
      ],
    );
  }
}
