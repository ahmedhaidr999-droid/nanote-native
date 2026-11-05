import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../controllers/settings_controller.dart';
import '../../i18n/strings.dart';
import '../../services/translate_service.dart';
import '../../theme/nanote_theme.dart';

/// Translation dialog: source text, engine selector (Nanote online /
/// Google web), target selector (auto / Arabic / English), result card with
/// copy, and Ask-AI buttons. Engine/target persist through
/// [SettingsController].
///
/// v1.9.1 restyle: custom equal-width segmented controls (surfaceVariant
/// track, card-lifted selection), 12px w700 muted section titles, ink-1
/// result card, Lucide icons, pill buttons.
Future<void> showTranslatePopup(BuildContext context, String initialText) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _TranslateDialog(initialText: initialText),
  );
}

class _TranslateDialog extends StatefulWidget {
  const _TranslateDialog({required this.initialText});

  final String initialText;

  @override
  State<_TranslateDialog> createState() => _TranslateDialogState();
}

class _TranslateDialogState extends State<_TranslateDialog> {
  late final TextEditingController _source =
      TextEditingController(text: widget.initialText);
  late String _engine;
  late String _target;
  bool _loading = false;
  TranslateResult? _result;

  @override
  void initState() {
    super.initState();
    _engine = SettingsController.I.settings.translateEngine;
    _target = SettingsController.I.settings.translateTarget;
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  /// "Auto (follows UI)": Arabic UI -> English and vice versa.
  String get _resolvedTarget =>
      _target == 'auto' ? (S.isAr ? 'en' : 'ar') : _target;

  Future<void> _translate() async {
    final text = _source.text.trim();
    if (text.isEmpty || _loading) return;
    final target = _resolvedTarget;

    if (_engine == 'google') {
      final ok = await TranslateService.openGoogleTranslate(text, target);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('error'))),
        );
      }
      return;
    }

    setState(() => _loading = true);
    TranslateResult? result;
    try {
      result = await TranslateService.translate(text, target: target);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
    if (!mounted) return;
    setState(() => _result = result);
    if (result == null) {
      // Distinguish "offline dictionary refused (low coverage)" from a
      // generic failure.
      final preview = TranslateService.offlinePreview(text, target);
      final lowCoverage = preview != null && preview.$1 < 0.25;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(lowCoverage ? S.t('coverageTooLow') : S.t('translateFailed')),
        ),
      );
    }
  }

  Future<void> _ask(String service) async {
    final text = _source.text.trim();
    if (text.isEmpty) return;
    await SettingsController.I.setAiService(service);
    if (!mounted) return;
    await TranslateService.askAi(context, text);
  }

  // ------------------------------------------------------------- segments

  Widget _sectionTitle(BuildContext context, String key) {
    final cs = nanoteColors(context);
    return Text(
      S.t(key),
      style: nanoteText(TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: cs.mutedFg,
      )),
    );
  }

  /// Equal-width segmented control (v1.9.1): surfaceVariant track, selected
  /// segment lifted to the card surface with ink-1 shadow + primary label.
  Widget _segmented(
    BuildContext context, {
    required String current,
    required List<(String, String)> values,
    required ValueChanged<String> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final cs = nanoteColors(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
      ),
      child: Row(
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: i == 0 ? 0 : 2,
                  end: i == values.length - 1 ? 0 : 2,
                ),
                child: Pressable(
                  onTap: () => onChanged(values[i].$1),
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: current == values[i].$1
                          ? scheme.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
                      boxShadow:
                          current == values[i].$1 ? cs.inkShadow1 : null,
                    ),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 4),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          values[i].$2,
                          maxLines: 1,
                          style: nanoteText(TextStyle(
                            fontSize: 12,
                            fontWeight: current == values[i].$1
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: current == values[i].$1
                                ? scheme.primary
                                : cs.mutedFg,
                          )),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = nanoteColors(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(S.t('translate')),
      scrollable: true,
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _source,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(
                hintText: S.t('sourceText'),
                labelText: S.t('sourceText'),
              ),
            ),
            const SizedBox(height: 14),
            _sectionTitle(context, 'translateEngine'),
            const SizedBox(height: 8),
            _segmented(
              context,
              current: _engine,
              values: [
                ('nanote', S.t('engineNanote')),
                ('google', S.t('engineGoogle')),
              ],
              onChanged: (v) {
                setState(() => _engine = v);
                unawaited(SettingsController.I.setTranslateEngine(v));
              },
            ),
            const SizedBox(height: 14),
            _sectionTitle(context, 'targetLanguage'),
            const SizedBox(height: 8),
            _segmented(
              context,
              current: _target,
              values: [
                ('auto', S.t('targetAuto')),
                ('ar', S.t('arabic')),
                ('en', S.t('english')),
              ],
              onChanged: (v) {
                setState(() => _target = v);
                unawaited(SettingsController.I.setTranslateTarget(v));
              },
            ),
            if (_result != null) ...[
              const SizedBox(height: 14),
              _sectionTitle(context, 'resultText'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(NANOTE_RADIUS),
                  border: Border.all(color: scheme.outline),
                  boxShadow: cs.inkShadow1,
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(_result!.text),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (_result!.usedOffline)
                          Expanded(
                            child: Text(
                              '${S.t('offlineUsed')} · '
                              '${S.num((_result!.coverage * 100).round())}% '
                              '${S.t('coverage')}',
                              style: TextStyle(
                                  color: cs.mutedFg, fontSize: 12),
                            ),
                          )
                        else
                          const Spacer(),
                        IconButton(
                          tooltip: S.t('copy'),
                          icon: Icon(LucideIcons.copy,
                              size: 18, color: scheme.primary),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: _result!.text),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(S.t('copiedToClipboard'))),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            _sectionTitle(context, 'askAi'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(_ask('chatgpt')),
                    icon: const Icon(LucideIcons.bot, size: 16),
                    label: const Text('ChatGPT'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(_ask('gemini')),
                    icon: const Icon(LucideIcons.sparkles, size: 16),
                    label: const Text('Gemini'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(_ask('claude')),
                    icon: const Icon(LucideIcons.brain, size: 16),
                    label: const Text('Claude'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 10),
                Text(S.t('translating')),
              ],
            ),
          )
        else
          FilledButton.icon(
            onPressed: _translate,
            icon: const Icon(LucideIcons.languages, size: 16),
            label: Text(S.t('translate')),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.t('close')),
        ),
      ],
    );
  }
}
