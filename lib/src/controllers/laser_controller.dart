import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// Laser pointer modes.
enum LaserMode { normal, timed }

/// One transient laser stroke. Points live in PAGE space; laser ink is NEVER
/// committed to the document (no Stroke / engine interaction).
class LaserStroke {
  LaserStroke({required this.pageId, required this.createdAtMs});

  /// Page this stroke belongs to.
  final int pageId;

  /// Stroke points in page space (y down).
  final List<Offset> points = [];

  /// Arrival wall-clock time (ms since epoch) per point — drives the comet
  /// trail fade.
  final List<int> pointTimesMs = [];

  /// Wall-clock creation time (ms since epoch).
  final int createdAtMs;

  /// Whether pen-up already happened for this stroke.
  bool released = false;

  /// Age of the stroke in ms.
  int get ageMs => DateTime.now().millisecondsSinceEpoch - createdAtMs;
}

/// Ephemeral laser-pointer overlay state.
///
///  * [LaserMode.normal] — comet trail: each point fades out after ~600ms.
///  * [LaserMode.timed] — the whole stroke stays on screen for [seconds]
///    (plus a short fade window) after release.
///
/// The overlay widget owns a ~30fps timer that calls [tick] to advance the
/// fades; [tick] always notifies so repaints stay in lock-step with the clock.
class LaserController extends ChangeNotifier {
  LaserController._();

  static final LaserController I = LaserController._();

  /// normal = comet trail (~600ms per-point fade); timed = whole stroke
  /// stays [seconds] seconds.
  LaserMode mode = LaserMode.normal;

  /// Timed mode: seconds the whole stroke stays visible (1..10).
  int seconds = 3;

  /// Laser color (0xAARRGGBB).
  int color = 0xFFE5484D;

  final List<LaserStroke> _strokes = [];
  LaserStroke? _current;

  /// Render data for the painter: active strokes, oldest first. Treat the
  /// returned list as read-only.
  List<LaserStroke> get strokes => _strokes;

  /// Starts a laser stroke on [pageId].
  void beginStroke(int pageId) {
    _current = LaserStroke(pageId: pageId, createdAtMs: _nowMs());
    _strokes.add(_current!);
    notifyListeners();
  }

  /// Appends a page-space point to the active stroke.
  void addPoint(Offset pagePoint) {
    final s = _current;
    if (s == null) return;
    s.points.add(pagePoint);
    s.pointTimesMs.add(_nowMs());
    notifyListeners();
  }

  /// Releases the active stroke (pen up). The stroke keeps fading per the
  /// current mode.
  void endStroke() {
    _current?.released = true;
    _current = null;
    notifyListeners();
  }

  /// Advances fades and drops finished strokes. Call from a ~30fps timer
  /// owned by the laser overlay.
  void tick() {
    if (_strokes.isNotEmpty) {
      final now = _nowMs();
      if (mode == LaserMode.normal) {
        // Comet trail: finished when ALL points have fully faded (>600ms old).
        _strokes.removeWhere((s) {
          if (s.points.isEmpty) return now - s.createdAtMs > 600;
          for (final t in s.pointTimesMs) {
            if (now - t <= 600) return false;
          }
          return true;
        });
      } else {
        // Timed: released strokes stay `seconds` (measured from release —
        // the last point — so the whole stroke is fully visible for the
        // stay window) plus a 400ms fade window, matching the overlay's
        // fade curve exactly.
        final linger = _clampedSeconds() * 1000 + 400;
        _strokes.removeWhere((s) {
          if (!s.released) return false; // still being drawn — stays visible
          final last = s.pointTimesMs.isNotEmpty
              ? s.pointTimesMs.last
              : s.createdAtMs;
          return now - last > linger;
        });
      }
    }
    notifyListeners();
  }

  /// Drops every stroke immediately.
  void clear() {
    _strokes.clear();
    _current = null;
    notifyListeners();
  }

  int _clampedSeconds() => seconds < 1 ? 1 : (seconds > 10 ? 10 : seconds);

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;
}
