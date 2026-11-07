import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../controllers/audio_controller.dart';
import '../../controllers/stroke_engine.dart';
import '../../i18n/strings.dart';
import '../../persistence/library_repository.dart';
import '../../theme/nanote_theme.dart';

/// Audio notes panel: record button with live level meter + elapsed time,
/// sync-replay toggle (with exit banner) and the notebook's recording list
/// with play/pause, seek slider and delete. Driven by [AudioController.I].
///
/// v1.9.1 restyle: pill record button, thin level meter, ink-1 recording
/// cards (radius 12, 1px border), circular play buttons, Lucide icons.
Future<void> showAudioPanel(BuildContext context, StrokeEngine engine) async {
  final controller = AudioController.I;
  final notebookId = engine.notebook?.id;
  if (notebookId != null) {
    unawaited(controller.loadForNotebook(notebookId));
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _AudioPanel(engine: engine),
  );
}

class _AudioPanel extends StatefulWidget {
  const _AudioPanel({required this.engine});

  final StrokeEngine engine;

  @override
  State<_AudioPanel> createState() => _AudioPanelState();
}

class _AudioPanelState extends State<_AudioPanel> {
  AudioController get _controller => AudioController.I;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncTimer);
    _syncTimer();
  }

  @override
  void dispose() {
    _controller.removeListener(_syncTimer);
    _tickTimer?.cancel();
    _tickTimer = null;
    super.dispose();
  }

  /// Keeps a 500ms refresh loop alive only while recording (elapsed readout).
  void _syncTimer() {
    if (!mounted) return;
    if (_controller.isRecording) {
      _tickTimer ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted && _controller.isRecording) {
          setState(() {});
        }
      });
    } else {
      _tickTimer?.cancel();
      _tickTimer = null;
    }
  }

  Future<void> _toggleRecord() async {
    final notebook = widget.engine.notebook;
    if (notebook == null) return;
    final controller = _controller;
    if (controller.isRecording) {
      await controller.stopRecording();
      return;
    }
    final pageId =
        widget.engine.pages.isNotEmpty ? widget.engine.pages.first.id : 0;
    final granted = await controller.startRecording(notebook.id, pageId);
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('micDenied'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      S.t('audioPanel'),
                      style: nanoteText(TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      )),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) => _recordSection(context, controller),
            ),
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) => _replaySection(context, controller),
            ),
            Divider(height: 1, color: scheme.outline),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 6),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  S.t('recordings'),
                  style: nanoteText(TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: nanoteColors(context).mutedFg,
                  )),
                ),
              ),
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final recordings = controller.recordings;
                  if (recordings.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          S.t('noRecordings'),
                          style:
                              TextStyle(color: nanoteColors(context).mutedFg),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: recordings.length,
                    itemBuilder: (context, i) => _RecordingRow(
                      controller: controller,
                      engine: widget.engine,
                      recording: recordings[i],
                      index: i,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recordSection(BuildContext context, AudioController controller) {
    final cs = nanoteColors(context);
    final scheme = Theme.of(context).colorScheme;
    final recording = controller.isRecording;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            style: recording
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: _toggleRecord,
            icon: Icon(recording ? LucideIcons.square : LucideIcons.mic,
                size: 18),
            label: Text(recording ? S.t('stopRecording') : S.t('record')),
          ),
          if (recording) ...[
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: controller.level,
              builder: (context, _) {
                final level =
                    controller.level.value.clamp(0.0, 1.0).toDouble();
                return ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 6,
                    child: LinearProgressIndicator(
                      value: level,
                      minHeight: 6,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${S.t('recording')} · ${_fmtMs(controller.recordingElapsedMs())}',
                    style: nanoteText(TextStyle(
                        color: cs.mutedFg, fontSize: 13)),
                  ),
                ),
                _recordingPageBadge(context, controller, cs),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _recordingPageBadge(
      BuildContext context, AudioController controller, NanoteColors cs) {
    final pageId = controller.recordingPageId;
    if (pageId == null) return const SizedBox.shrink();
    final index = widget.engine.pages.indexWhere((p) => p.id == pageId);
    if (index < 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: cs.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${S.t('page')} ${S.num(index + 1)}',
        style: nanoteText(
            TextStyle(color: cs.accentFg, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _replaySection(BuildContext context, AudioController controller) {
    final cs = nanoteColors(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text(S.t('syncReplay'),
              style: nanoteText(const TextStyle(fontSize: 14))),
          subtitle: Text(
            S.t('replayHint'),
            style: TextStyle(color: cs.mutedFg, fontSize: 12),
          ),
          value: controller.syncReplayMode,
          onChanged: (v) => controller.setSyncReplay(v),
        ),
        if (controller.syncReplayMode)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 12, 8),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(NANOTE_RADIUS),
                border: Border.all(color: scheme.outline),
                boxShadow: cs.inkShadow1,
              ),
              padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 4),
              child: Row(
                children: [
                  Icon(LucideIcons.rotate_ccw, size: 18, color: cs.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(S.t('replayMode'),
                        style:
                            nanoteText(const TextStyle(fontSize: 13))),
                  ),
                  TextButton(
                    onPressed: () =>
                        unawaited(controller.exitSyncReplay()),
                    child: Text(S.t('exitReplay')),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RecordingRow extends StatelessWidget {
  const _RecordingRow({
    required this.controller,
    required this.engine,
    required this.recording,
    required this.index,
  });

  final AudioController controller;
  final StrokeEngine engine;
  final RecordingEntity recording;
  final int index;

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('confirmDeleteRecording')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t('delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await controller.deleteRecording(recording);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = nanoteColors(context);
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final active = controller.playing?.id == recording.id;
        final playing = active && controller.isPlaying;
        final pageIndex =
            engine.pages.indexWhere((p) => p.id == recording.pageId);
        return Container(
          margin: const EdgeInsetsDirectional.fromSTEB(16, 5, 16, 5),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(NANOTE_RADIUS),
            border: Border.all(color: scheme.outline),
            boxShadow: cs.inkShadow1,
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 4, 6),
            child: Column(
              children: [
                Row(
                  children: [
                    Pressable(
                      onTap: () =>
                          unawaited(controller.togglePlayPause(recording)),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: cs.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Icon(
                            playing ? LucideIcons.pause : LucideIcons.play,
                            size: 18,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${S.num(index + 1)} · ${_hm(recording.createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: nanoteText(TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            )),
                          ),
                          Text(
                            '${_fmtMs(recording.durationMs)}'
                            '${pageIndex >= 0 ? ' · ${S.t('page')} ${S.num(pageIndex + 1)}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(color: cs.mutedFg, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        tooltip: S.t('deleteRecording'),
                        padding: EdgeInsets.zero,
                        icon: Icon(LucideIcons.trash,
                            size: 18, color: cs.mutedFg),
                        onPressed: () => unawaited(_confirmDelete(context)),
                      ),
                    ),
                  ],
                ),
                if (active)
                  StreamBuilder<Duration>(
                    stream: controller.onPositionChanged,
                    builder: (context, snapshot) {
                      final position =
                          snapshot.data ?? controller.position;
                      var duration = controller.duration ??
                          Duration(milliseconds: recording.durationMs);
                      if (duration.inMilliseconds <= 0) {
                        duration = const Duration(milliseconds: 1);
                      }
                      final positionMs = position.inMilliseconds
                          .clamp(0, duration.inMilliseconds)
                          .toInt();
                      return Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 12, 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 44,
                              child: Text(_fmtMs(positionMs),
                                  style: nanoteText(TextStyle(
                                      fontSize: 11,
                                      color: cs.mutedFg))),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: const SliderThemeData(
                                  trackHeight: 3,
                                  thumbShape:
                                      RoundSliderThumbShape(enabledThumbRadius: 7),
                                  overlayShape:
                                      RoundSliderOverlayShape(overlayRadius: 12),
                                ),
                                child: Slider(
                                  value: positionMs.toDouble(),
                                  max: duration.inMilliseconds.toDouble(),
                                  onChanged: (v) => unawaited(controller
                                      .seekTo(Duration(milliseconds: v.round()))),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 44,
                              child: Text(_fmtMs(duration.inMilliseconds),
                                  textAlign: TextAlign.end,
                                  style: nanoteText(TextStyle(
                                      fontSize: 11,
                                      color: cs.mutedFg))),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---- time formatting (Arabic-Indic aware) --------------------------------

String _digits(String s) {
  if (!S.isAr) return s;
  const ar = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  return String.fromCharCodes(s.runes.map((r) {
    final c = r - 0x30;
    return (c >= 0 && c <= 9) ? ar[c].runes.first : r;
  }));
}

String _two(int n) => n < 10 ? '0$n' : '$n';

String _fmtMs(int ms) {
  if (ms < 0) ms = 0;
  final minutes = ms ~/ 60000;
  final seconds = (ms % 60000) ~/ 1000;
  return _digits('${_two(minutes)}:${_two(seconds)}');
}

String _hm(DateTime t) => _digits('${_two(t.hour)}:${_two(t.minute)}');
