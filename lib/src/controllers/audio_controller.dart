import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../persistence/file_store.dart';
import '../persistence/library_repository.dart';

/// Audio notes: recording (package:record, AAC/m4a into [FileStore]) and
/// playback (package:audioplayers), plus ink-sync replay.
///
/// The controller never touches the stroke engine: the WORKSPACE installs
/// `StrokeEngine.I.recordingClock = AudioController.I.recordingElapsedMs`
/// while a recording is active (and removes it afterwards), and hides
/// strokes with `tStart > replayAtMs` during sync replay.
class AudioController extends ChangeNotifier {
  AudioController._() {
    _initPlayer();
  }

  static final AudioController I = AudioController._();

  // ------------------------------------------------------------- recording

  final AudioRecorder _rec = AudioRecorder();

  /// Normalized mic level 0..1 (from dBFS, -45..0 → 0..1) while recording.
  final ValueNotifier<double> level = ValueNotifier<double>(0);

  Timer? _levelTimer;
  DateTime? _startedAt;
  String? _recordingRel;
  int? _recordingNotebookId;
  int? _recordingPageId;

  bool get isRecording => _startedAt != null;

  /// Page the active recording is attached to (null when not recording).
  int? get recordingPageId => _recordingPageId;

  /// Elapsed recording time in ms (0 when not recording).
  int recordingElapsedMs() {
    final s = _startedAt;
    if (s == null) return 0;
    return DateTime.now().difference(s).inMilliseconds;
  }

  /// Starts a new m4a recording attached to ([notebookId], [pageId]).
  /// Returns false when mic permission is denied or the recorder fails.
  Future<bool> startRecording(int notebookId, int pageId) async {
    if (isRecording) return true; // already recording — keep the session
    try {
      if (!await _rec.hasPermission()) return false;
    } catch (_) {
      return false;
    }
    try {
      final relPath = await FileStore.newRecordingFile();
      final abs = await FileStore.resolve(relPath);
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: 1,
          sampleRate: 44100,
        ),
        path: abs.path,
      );
      _recordingRel = relPath;
      _recordingNotebookId = notebookId;
      _recordingPageId = pageId;
      _startedAt = DateTime.now();
      level.value = 0;
      _startLevelPolling();
      notifyListeners();
      return true;
    } catch (_) {
      // Recorder failed to start — make sure no half-session lingers.
      _startedAt = null;
      _recordingRel = null;
      _recordingNotebookId = null;
      _recordingPageId = null;
      _levelTimer?.cancel();
      _levelTimer = null;
      level.value = 0;
      notifyListeners();
      return false;
    }
  }

  void _startLevelPolling() {
    _levelTimer?.cancel();
    _levelTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (!isRecording) return;
      try {
        final amp = await _rec.getAmplitude();
        // amp.current is NEGATIVE dBFS (≈ -45..0) → normalize to 0..1.
        final v = (amp.current + 45) / 45;
        level.value = v < 0 ? 0 : (v > 1 ? 1 : v);
        notifyListeners();
      } catch (_) {
        // Amplitude unavailable on this platform tick — keep last value.
      }
    });
  }

  /// Stops the active recording and persists it as a [RecordingEntity]
  /// (file stays under the recordings dir, referenced by relative path).
  Future<void> stopRecording() async {
    _levelTimer?.cancel();
    _levelTimer = null;
    final startedAt = _startedAt;
    if (startedAt == null) return; // recording never started
    _startedAt = null;
    level.value = 0;

    final durationMs = DateTime.now().difference(startedAt).inMilliseconds;
    final rel = _recordingRel;
    final notebookId = _recordingNotebookId;
    final pageId = _recordingPageId;
    _recordingRel = null;
    _recordingNotebookId = null;
    _recordingPageId = null;

    try {
      await _rec.stop();
    } catch (_) {
      // Recorder already stopped — the file (if any) still gets indexed.
    }

    if (rel != null && notebookId != null && pageId != null) {
      try {
        final entity =
            RecordingEntity.of(notebookId, pageId, rel, durationMs);
        await LibraryRepository.I.addRecording(entity);
      } catch (_) {
        // DB write failed — the orphan file remains but is not listed.
      }
      if (_loadedNotebookId == notebookId) {
        await loadForNotebook(notebookId);
      }
    }
    notifyListeners();
  }

  // -------------------------------------------------------------- playback

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<void>? _completeSub;

  bool _playingState = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  /// Recordings of the currently loaded notebook, newest first.
  List<RecordingEntity> recordings = [];
  int? _loadedNotebookId;

  bool get isPlaying => _playingState;

  /// Playback head.
  Duration get position => _position;

  /// Total duration of the playing recording (null when unknown).
  Duration? get duration => _duration;

  /// The recording currently loaded into the player (null when idle).
  RecordingEntity? playing;

  /// Player position stream (audioplayers).
  Stream<Duration>? get onPositionChanged => _player.onPositionChanged;

  /// Player duration stream (audioplayers).
  Stream<Duration>? get onDurationChanged => _player.onDurationChanged;

  /// Player state stream (audioplayers).
  Stream<PlayerState>? get onPlayerStateChanged =>
      _player.onPlayerStateChanged;

  void _initPlayer() {
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      final playingNow = s == PlayerState.playing;
      if (_playingState != playingNow) {
        _playingState = playingNow;
        notifyListeners();
      }
    });
    _positionSub = _player.onPositionChanged.listen((p) {
      _position = p;
      notifyListeners();
    });
    _durationSub = _player.onDurationChanged.listen((d) {
      _duration = d;
      notifyListeners();
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      _onPlaybackComplete();
    });
  }

  Future<void> play(RecordingEntity r) async {
    try {
      final abs = await FileStore.resolve(r.path);
      if (!await abs.exists()) {
        return; // missing file — nothing to play
      }
      playing = r;
      _position = Duration.zero;
      notifyListeners();
      await _player.play(DeviceFileSource(abs.path));
    } catch (_) {
      if (playing != null && playing!.id == r.id) {
        playing = null;
        _playingState = false;
        notifyListeners();
      }
    }
  }

  Future<void> togglePlayPause(RecordingEntity r) async {
    if (playing != null && playing!.id == r.id) {
      if (_playingState) {
        try {
          await _player.pause();
        } catch (_) {}
        _playingState = false;
        notifyListeners();
      } else {
        try {
          await _player.resume();
        } catch (_) {
          await play(r);
        }
      }
      return;
    }
    await play(r);
  }

  Future<void> stopPlayback() async {
    try {
      await _player.stop();
    } catch (_) {}
    playing = null;
    _playingState = false;
    _position = Duration.zero;
    _duration = null;
    notifyListeners();
  }

  Future<void> seekTo(Duration d) async {
    if (playing == null) return;
    var target = d;
    if (target < Duration.zero) target = Duration.zero;
    final total = _duration;
    if (total != null && target > total) target = total;
    try {
      await _player.seek(target);
      _position = target;
      notifyListeners();
    } catch (_) {
      // Seek failed (e.g. player not ready) — keep the last position.
    }
  }

  void _onPlaybackComplete() {
    playing = null;
    _playingState = false;
    _position = Duration.zero;
    _duration = null;
    syncReplayMode = false; // exit replay when the recording runs out
    notifyListeners();
  }

  // ------------------------------------------------------------ sync replay

  /// True while ink-sync replay is active.
  bool syncReplayMode = false;

  /// Player position (ms) while playing — painters hide strokes whose
  /// tStart is greater than this. 0 when not playing.
  int get replayAtMs => _playingState ? _position.inMilliseconds : 0;

  /// Starts sync replay from a specific recording.
  void startSyncReplay(RecordingEntity r) {
    syncReplayMode = true;
    notifyListeners();
    unawaited(play(r));
  }

  /// Enables/disables sync replay. Enabling with nothing playing starts the
  /// first (newest) recording of the loaded notebook, if any.
  void setSyncReplay(bool enabled) {
    if (enabled) {
      syncReplayMode = true;
      if (playing == null && recordings.isNotEmpty) {
        unawaited(play(recordings.first));
      }
    } else {
      syncReplayMode = false;
    }
    notifyListeners();
  }

  /// Exits sync replay and stops playback.
  Future<void> exitSyncReplay() async {
    syncReplayMode = false;
    notifyListeners();
    await stopPlayback();
  }

  // ------------------------------------------------------------------- list

  /// Loads the recordings of [notebookId] (newest first) into [recordings].
  Future<void> loadForNotebook(int notebookId) async {
    _loadedNotebookId = notebookId;
    try {
      recordings = await LibraryRepository.I.recordingsOf(notebookId);
    } catch (_) {
      recordings = [];
    }
    notifyListeners();
  }

  /// Deletes a recording: stops it if playing, removes the file (missing
  /// files are fine) and the DB row, then reloads the list.
  Future<void> deleteRecording(RecordingEntity r) async {
    if (playing != null && playing!.id == r.id) {
      await stopPlayback();
    }
    await FileStore.deleteRelative(r.path);
    try {
      await LibraryRepository.I.deleteRecording(r);
    } catch (_) {
      // Row already gone — still refresh the list.
    }
    final nb = _loadedNotebookId;
    if (nb != null) {
      await loadForNotebook(nb);
    }
    notifyListeners();
  }

  // ----------------------------------------------------------------- dispose

  /// This controller is an app-lifetime singleton and is not disposed in
  /// practice, but everything it owns is released safely if it ever is.
  @override
  void dispose() {
    _levelTimer?.cancel();
    _levelTimer = null;
    _stateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
