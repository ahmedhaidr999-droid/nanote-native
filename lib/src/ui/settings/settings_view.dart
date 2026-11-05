import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/settings_controller.dart';
import '../../i18n/strings.dart';
import '../../services/backup_service.dart';
import '../../theme/nanote_theme.dart';

/// Settings ('/settings'): Appearance / Writing / Pens / Stickers /
/// Translation / Backup & restore / About — v1.9.1 card sections.
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
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 32),
            children: [
              // ------------------------------------------------- appearance
              _section(
                context,
                icon: LucideIcons.palette,
                title: S.t('appearance'),
                children: [
                  _controlRow(
                    context,
                    label: S.t('themeMode'),
                    child: _segmented<String>(
                      context,
                      options: [
                        _SegOption('light', S.t('themeLight'),
                            icon: LucideIcons.sun),
                        _SegOption('dark', S.t('themeDark'),
                            icon: LucideIcons.moon),
                        _SegOption('system', S.t('themeSystem'),
                            icon: LucideIcons.monitor),
                      ],
                      selected: s.themeMode,
                      onChanged: (v) =>
                          SettingsController.I.setThemeMode(v),
                    ),
                  ),
                  _divider(),
                  _controlRow(
                    context,
                    label: S.t('language'),
                    child: _segmented<String>(
                      context,
                      options: [
                        _SegOption('ar', S.t('arabic'),
                            icon: LucideIcons.languages),
                        _SegOption('en', S.t('english')),
                      ],
                      selected: s.lang,
                      onChanged: (v) => SettingsController.I.setLang(v),
                    ),
                  ),
                  _divider(),
                  _controlRow(
                    context,
                    label: S.t('numerals'),
                    child: _segmented<String>(
                      context,
                      options: [
                        _SegOption('latin', S.t('numeralsLatin')),
                        _SegOption('hindi', S.t('numeralsHindi')),
                      ],
                      selected: s.numerals,
                      onChanged: (v) =>
                          SettingsController.I.setNumerals(v),
                    ),
                  ),
                  _divider(),
                  _switchRow(
                    context,
                    icon: LucideIcons.hand,
                    title: S.t('leftHanded'),
                    subtitle: S.t('leftHandedHint'),
                    value: s.leftHanded,
                    onChanged: (v) =>
                        SettingsController.I.setLeftHanded(v),
                  ),
                ],
              ),

              // ---------------------------------------------------- writing
              _section(
                context,
                icon: LucideIcons.pen_line,
                title: S.t('writing'),
                children: [
                  _sliderTile(
                    context,
                    label: S.t('pressureCurve'),
                    value: s.pressureCurve,
                    min: 0.4,
                    max: 2.5,
                    divisions: 21,
                    format: (v) => S.num(v.toStringAsFixed(2)),
                    onChanged: (v) =>
                        SettingsController.I.setPressureCurve(v),
                    endLabels: [
                      S.t('curveFirm'),
                      S.t('curveLinear'),
                      S.t('curveSoft'),
                    ],
                  ),
                  _divider(),
                  _switchRow(
                    context,
                    icon: LucideIcons.pointer,
                    title: S.t('drawWithFinger'),
                    subtitle: S.t('drawWithFingerHint'),
                    value: s.drawWithFinger,
                    onChanged: (v) =>
                        SettingsController.I.setDrawWithFinger(v),
                  ),
                  _divider(),
                  _switchRow(
                    context,
                    icon: LucideIcons.shapes,
                    title: S.t('shapeDetection'),
                    value: s.shapeDetection,
                    onChanged: (v) =>
                        SettingsController.I.setShapeDetection(v),
                  ),
                  _divider(),
                  _sliderTile(
                    context,
                    label: S.t('highlighterOpacity'),
                    value: s.highlighterOpacity,
                    min: 0.1,
                    max: 1.0,
                    divisions: 9,
                    format: (v) => '${S.num((v * 100).round())}%',
                    onChanged: (v) =>
                        SettingsController.I.setHighlighterOpacity(v),
                  ),
                  _divider(),
                  _controlRow(
                    context,
                    label: S.t('autosave'),
                    child: _segmented<int>(
                      context,
                      options: [
                        _SegOption(0, S.t('autosaveNow')),
                        _SegOption(1000, S.t('autosave1s')),
                        _SegOption(5000, S.t('autosave5s')),
                      ],
                      selected: s.autosaveDelayMs,
                      onChanged: (v) =>
                          SettingsController.I.setAutosaveDelayMs(v),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),

              // ------------------------------------------------------- pens
              _section(
                context,
                icon: LucideIcons.pen_tool,
                title: S.t('pens'),
                children: [
                  _linkRow(
                    context,
                    icon: LucideIcons.pen_tool,
                    title: S.t('penManager'),
                    onTap: () => Navigator.pushNamed(context, '/pen'),
                  ),
                ],
              ),

              // --------------------------------------------------- stickers
              _section(
                context,
                icon: LucideIcons.sticker,
                title: S.t('stickerPicker'),
                children: [
                  _linkRow(
                    context,
                    icon: LucideIcons.sticker,
                    title: S.t('stickerManager'),
                    onTap: () => Navigator.pushNamed(context, '/stickers'),
                  ),
                ],
              ),

              // ------------------------------------------------- translation
              _section(
                context,
                icon: LucideIcons.languages,
                title: S.t('translation'),
                children: [
                  _label(context, S.t('translateEngine')),
                  _radioRow<String>(
                    context,
                    value: 'nanote',
                    groupValue: s.translateEngine,
                    label: S.t('engineNanote'),
                    onChanged: (v) =>
                        SettingsController.I.setTranslateEngine(v),
                  ),
                  _radioRow<String>(
                    context,
                    value: 'google',
                    groupValue: s.translateEngine,
                    label: S.t('engineGoogle'),
                    onChanged: (v) =>
                        SettingsController.I.setTranslateEngine(v),
                  ),
                  _divider(),
                  _label(context, S.t('targetLanguage')),
                  _radioRow<String>(
                    context,
                    value: 'auto',
                    groupValue: s.translateTarget,
                    label: S.t('targetAuto'),
                    onChanged: (v) =>
                        SettingsController.I.setTranslateTarget(v),
                  ),
                  _radioRow<String>(
                    context,
                    value: 'ar',
                    groupValue: s.translateTarget,
                    label: S.t('arabic'),
                    onChanged: (v) =>
                        SettingsController.I.setTranslateTarget(v),
                  ),
                  _radioRow<String>(
                    context,
                    value: 'en',
                    groupValue: s.translateTarget,
                    label: S.t('english'),
                    onChanged: (v) =>
                        SettingsController.I.setTranslateTarget(v),
                  ),
                  _divider(),
                  _controlRow(
                    context,
                    label: S.t('askAi'),
                    child: _segmented<String>(
                      context,
                      options: const [
                        _SegOption('chatgpt', 'ChatGPT'),
                        _SegOption('gemini', 'Gemini'),
                        _SegOption('claude', 'Claude'),
                      ],
                      selected: s.aiService,
                      onChanged: (v) =>
                          SettingsController.I.setAiService(v),
                    ),
                  ),
                ],
              ),

              // ------------------------------------------------- backup
              _section(
                context,
                icon: LucideIcons.database_backup,
                title: S.t('backupRestore'),
                children: [
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: _createBackup,
                      icon: const Icon(LucideIcons.database_backup),
                      label: Text(S.t('createBackup')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _restoreBackup,
                      icon: const Icon(LucideIcons.upload),
                      label: Text(S.t('restoreBackup')),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _caption(
                      context, LucideIcons.smartphone, S.t('dataHint')),
                  const SizedBox(height: 4),
                  _caption(
                      context, LucideIcons.wifi_off, S.t('privacy')),
                ],
              ),

              // ------------------------------------------------------ about
              _section(
                context,
                icon: LucideIcons.info,
                title: S.t('about'),
                children: [
                  _valueRow(
                    context,
                    title: S.t('version'),
                    value: '2.2.0',
                  ),
                  _divider(),
                  _linkRow(
                    context,
                    icon: LucideIcons.refresh_cw,
                    title: S.t('checkUpdates'),
                    trailingIcon: LucideIcons.external_link,
                    onTap: _checkUpdates,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------- helpers

  /// Rounded-xl card with a muted section header (icon + 13px w700).
  Widget _section(
    BuildContext context, {
    IconData? icon,
    required String title,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(NANOTE_RADIUS_LG),
        border: Border.all(color: cs.outline),
        boxShadow: nc.inkShadow1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: nc.mutedFg),
                const SizedBox(width: 7),
              ],
              Text(
                title,
                style: nanoteText(TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: nc.mutedFg,
                )),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 17, thickness: 1, indent: 4, endIndent: 4);

  /// Small tinted square that carries a row's leading icon.
  Widget _iconChip(BuildContext context, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: nc.accent,
        borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
      ),
      child: Icon(icon, size: 17, color: cs.primary),
    );
  }

  Widget _controlRow(
    BuildContext context, {
    required String label,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: nanoteText(const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: child),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
      child: Text(label,
          style: nanoteText(const TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w600))),
    );
  }

  Widget _switchRow(
    BuildContext context, {
    IconData? icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(NANOTE_RADIUS),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            if (icon != null) ...[
              _iconChip(context, icon),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: nanoteText(const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600))),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: nanoteText(TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: nanoteColors(context).mutedFg)),
                    ),
                  ],
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }

  Widget _linkRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    IconData? trailingIcon,
  }) {
    final nc = nanoteColors(context);
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            _iconChip(context, icon),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: nanoteText(const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600))),
            ),
            Icon(trailingIcon ?? LucideIcons.chevron_right,
                size: 18, color: nc.mutedFg),
          ],
        ),
      ),
    );
  }

  Widget _valueRow(
    BuildContext context, {
    required String title,
    required String value,
  }) {
    final nc = nanoteColors(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: nanoteText(const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600))),
          ),
          Text(value,
              style: nanoteText(TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: nc.mutedFg))),
        ],
      ),
    );
  }

  Widget _radioRow<T>(
    BuildContext context, {
    required T value,
    required T groupValue,
    required String label,
    required ValueChanged<T> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    final selected = value == groupValue;
    return Pressable(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? cs.primary : cs.outline,
                    width: 2,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration:
                              BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: nanoteText(TextStyle(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ))),
              ),
            ],
          ),
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: nanoteText(const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600))),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: nc.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  format(value),
                  style: nanoteText(TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: nc.accentFg,
                  )),
                ),
              ),
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
                        style: nanoteText(
                            TextStyle(fontSize: 10, color: nc.mutedFg))),
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
        Icon(icon, size: 15, color: nc.mutedFg),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: nanoteText(
                TextStyle(fontSize: 12, height: 1.35, color: nc.mutedFg)),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Segmented control (muted track + card selected chip)
// ---------------------------------------------------------------------------

class _SegOption<T> {
  const _SegOption(this.value, this.label, {this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

Widget _segmented<T>(
  BuildContext context, {
  required List<_SegOption<T>> options,
  required T selected,
  required ValueChanged<T> onChanged,
  double fontSize = 12.5,
}) {
  final nc = nanoteColors(context);
  return Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: nc.surfaceVariant,
      borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
    ),
    child: Row(
      children: [
        for (final o in options)
          Expanded(
            child: _segChip(
              context,
              icon: o.icon,
              label: o.label,
              selected: o.value == selected,
              fontSize: fontSize,
              onTap: () => onChanged(o.value),
            ),
          ),
      ],
    ),
  );
}

Widget _segChip(
  BuildContext context, {
  IconData? icon,
  required String label,
  required bool selected,
  required VoidCallback onTap,
  double fontSize = 12.5,
}) {
  final cs = Theme.of(context).colorScheme;
  final nc = nanoteColors(context);
  return Pressable(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? cs.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
        border: selected ? Border.all(color: cs.outline) : null,
        boxShadow: selected ? nc.inkShadow1 : const <BoxShadow>[],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: selected ? cs.primary : nc.mutedFg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: nanoteText(TextStyle(
                fontSize: fontSize,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? cs.primary : nc.mutedFg,
              )),
            ),
          ),
        ],
      ),
    ),
  );
}
