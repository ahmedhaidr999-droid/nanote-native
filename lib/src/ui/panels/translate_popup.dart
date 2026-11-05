import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/settings_controller.dart';
import '../../i18n/strings.dart';
import '../../services/translate_service.dart';
import '../../theme/nanote_theme.dart';

/// Translation dialog: source text, engine selector (Nanote online /
/// Google web), target selector (auto / Arabic / English), result card with
/// copy, and Ask-AI buttons. Engine/target persist through
/// [SettingsController].
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

  @override
  Widget build(BuildContext context) {
    final cs = nanoteColors(context);
    final labelStyle = Theme.of(context).textTheme.titleSmall;
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
            const SizedBox(height: 12),
            Text(S.t('translateEngine'), style: labelStyle),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'nanote', label: Text(S.t('engineNanote'))),
                ButtonSegment(value: 'google', label: Text(S.t('engineGoogle'))),
              ],
              selected: {_engine},
              onSelectionChanged: (selection) {
                setState(() => _engine = selection.first);
                unawaited(
                    SettingsController.I.setTranslateEngine(selection.first));
              },
            ),
            const SizedBox(height: 12),
            Text(S.t('targetLanguage'), style: labelStyle),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'auto', label: Text(S.t('targetAuto'))),
                ButtonSegment(value: 'ar', label: Text(S.t('arabic'))),
                ButtonSegment(value: 'en', label: Text(S.t('english'))),
              ],
              selected: {_target},
              onSelectionChanged: (selection) {
                setState(() => _target = selection.first);
                unawaited(
                    SettingsController.I.setTranslateTarget(selection.first));
              },
            ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              Text(S.t('resultText'), style: labelStyle),
              const SizedBox(height: 4),
              Card(
                child: Padding(
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
                            icon: const Icon(Icons.copy),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: _result!.text),
                              );
                              if (!mounted) return;
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
              ),
            ],
            const SizedBox(height: 12),
            Text(S.t('askAi'), style: labelStyle),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(_ask('chatgpt')),
                    icon: const Icon(Icons.smart_toy, size: 18),
                    label: const Text('ChatGPT'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(_ask('gemini')),
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Gemini'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(_ask('claude')),
                    icon: const Icon(Icons.psychology, size: 18),
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
          FilledButton(
            onPressed: _translate,
            child: Text(S.t('translate')),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.t('close')),
        ),
      ],
    );
  }
}
