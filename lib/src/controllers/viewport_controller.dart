import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../controllers/stroke_engine.dart';

/// Unified zoom/pan. ONE matrix: screen = doc × scale + pan.
///
/// All painting happens inside a single Transform driven by [matrix]; input
/// is converted through the inverse — ink can never drift.
///
/// v2.0.1 additions:
///  * [panBounds] + [clampToDoc] — the document can never be panned fully
///    off-screen. When an axis fits inside the viewport it is kept perfectly
///    CENTERED (fixes "pages not centered / floating") — except on infinite
///    papers, which NEVER center-lock (§5).
///  * [fitPageWidth] — opens/jumps fit the page WIDTH (like every notes
///    app); page JUMPS animate over min(520ms, 150 + dist×0.08) with a
///    cubic ease-out (§5).
///  * [startFling] — ballistic inertial scrolling for smooth continuous
///    vertical page flow after a pan gesture ends.
///
/// v2.4.0 INFINITY PAPER (§4/§5):
///  * Zoom range switches with the notebook type at OPEN: normal papers
///    50%–800%, infinite papers 8%–2400%.
///  * Roaming: free travel up to 1.5 SCREEN EDGES beyond the content in
///    every direction, with rubber-band bounce at the limit; infinite
///    papers are NEVER center-locked.
///  * The saved infinite view is restored when the same notebook reopens.
class ViewportController extends ChangeNotifier {
  double _scale = 1.0;
  Offset _pan = Offset.zero;

  /// §4 Zoom range — swaps with the notebook type the moment a notebook
  /// opens (the workspace reads these through the engine's paper type).
  static double get minScale =>
      StrokeEngine.I.isInfiniteDoc ? 0.08 : 0.5;
  static double get maxScale =>
      StrokeEngine.I.isInfiniteDoc ? 24.0 : 8.0;

  /// §5 Infinite papers roam up to 1.5 screen edges past the content.
  static const double _infiniteRoamScreens = 1.5;

  /// How far past the doc edges a pan may overshoot before clamping
  /// (logical px) — keeps panning from feeling rigid mid-gesture.
  static const double _overscrollMargin = 96.0;

  /// §5 true while the current notebook is an infinite-paper notebook.
  bool get _infinite => StrokeEngine.I.isInfiniteDoc;

  /// Tight doc-space bounds of all pages (set by the workspace each layout).
  Rect? panBounds;

  /// Canvas size (set by the workspace each layout).
  Size screenExtent = Size.zero;

  /// Bumped ~220ms after the last gesture (settle) so PDF tiles can
  /// re-render at higher quality. Zero re-renders DURING a pinch.
  final ValueNotifier<int> renderTick = ValueNotifier<int>(0);

  Timer? _settleTimer;

  double get scale => _scale;

  /// Zoom percent for the header (e.g. 137).
  int get zoomPercent => (_scale * 100).round();

  Matrix4 get matrix => Matrix4.identity()
    ..scale(_scale, _scale, 1.0)
    ..setTranslation(vm.Vector3(_pan.dx, _pan.dy, 0));

  Offset get pan => _pan;

  Offset toScreen(Offset doc) => doc * _scale + _pan;

  Offset toDoc(Offset screen) => (screen - _pan) / _scale;

  /// Visible doc-space rectangle.
  Rect visibleDocRect(Size screenSize) {
    final tl = toDoc(Offset.zero);
    final br = toDoc(Size(screenSize.width, screenSize.height).bottomRight(Offset.zero));
    return Rect.fromLTRB(tl.dx, tl.dy, br.dx, br.dy);
  }

  // ----------------------------------------------------------- clamping

  /// The pan overshoot margin for the current doc type: 1.5 screen edges on
  /// infinite papers (§5), 96px otherwise.
  double get _roamMargin {
    if (!_infinite) return _overscrollMargin;
    final s = screenExtent;
    return math.max(
      s.width * _infiniteRoamScreens,
      s.height * _infiniteRoamScreens,
    );
  }

  /// Clamps the current pan so the doc stays reachable: an axis that fits
  /// the viewport is centered (NORMAL papers only — infinite papers never
  /// center-lock); a larger axis keeps its edges within the roam margin.
  void clampToDoc() {
    final bounds = panBounds;
    if (bounds == null || screenExtent.isEmpty) return;
    _pan = Offset(
      _clampAxis(_pan.dx, bounds.left, bounds.right, screenExtent.width),
      _clampAxis(_pan.dy, bounds.top, bounds.bottom, screenExtent.height),
    );
  }

  double _clampAxis(double panAxis, double docMin, double docMax, double view) {
    final docExtent = (docMax - docMin) * _scale;
    if (docExtent <= view) {
      // §5: infinite papers NEVER center-lock — free roam with the wide
      // margin even when the (still short) paper fits the screen.
      if (_infinite) {
        final minPan = view - docMax * _scale - _roamMargin;
        final maxPan = -docMin * _scale + _roamMargin;
        return panAxis.clamp(minPan, maxPan);
      }
      // Doc fits → keep it perfectly centered on this axis.
      final docCenter = (docMin + docMax) / 2 * _scale;
      return (view / 2) - docCenter;
    }
    // Doc larger than the viewport → keep edges within the margin.
    final minPan = view - docMax * _scale - _roamMargin;
    final maxPan = -docMin * _scale + _roamMargin;
    return panAxis.clamp(minPan, maxPan);
  }

  void setMatrix(double scale, Offset pan, {bool settle = false}) {
    _cancelJump();
    _scale = scale.clamp(minScale, maxScale);
    _pan = pan;
    clampToDoc();
    notifyListeners();
    if (settle) endInteraction();
  }

  void panBy(Offset screenDelta) {
    _cancelJump();
    _pan += screenDelta;
    clampToDoc();
    notifyListeners();
  }

  /// Zoom by [factor] keeping the doc point under [focalScreen] fixed.
  void zoomBy(double factor, Offset focalScreen) {
    zoomTo(_scale * factor, focalScreen);
  }

  void zoomTo(double target, Offset focalScreen) {
    _cancelJump();
    final s = target.clamp(minScale, maxScale);
    if ((s - _scale).abs() < 0.0001) return;
    final docFocal = toDoc(focalScreen);
    _scale = s;
    // screen = doc*s + pan  =>  pan = screen - doc*s
    _pan = focalScreen - docFocal * s;
    clampToDoc();
    notifyListeners();
  }

  void centerDoc(Offset docPoint, Size screenSize) {
    _cancelJump();
    _pan = screenSize.center(Offset.zero) - docPoint * _scale;
    clampToDoc();
    notifyListeners();
  }

  /// Centers the given doc rect (a page) in the screen at 1x.
  void fitRect(Rect docRect, Size screenSize, {double targetScale = 1.0}) {
    _cancelJump();
    _scale = targetScale.clamp(minScale, maxScale);
    _pan = screenSize.center(Offset.zero) - docRect.center * _scale;
    clampToDoc();
    notifyListeners();
  }

  // ------------------------------------------------ §5 animated jumps

  /// §5 Page-jump flight: min(520ms, 150 + travel×0.08) with a cubic
  /// ease-out. The gesture owns the math while dragging/flinging/bouncing —
  /// any input cancels the flight instantly.
  bool _jumping = false;
  double _jumpFromScale = 1;
  double _jumpToScale = 1;
  Offset _jumpFromPan = Offset.zero;
  Offset _jumpToPan = Offset.zero;
  Duration _jumpElapsed = Duration.zero;
  Duration _lastJumpAt = Duration.zero;

  /// §5 Restores the saved infinite view ONCE per workspace open; explicit
  /// page jumps afterwards fly normally.
  bool _didRestoreInfinite = false;

  void _cancelJump() {
    _jumping = false;
  }

  /// Fits the WIDTH of [docRect] into the screen (notes-app style): the page
  /// spans the full canvas width, vertically the page top is preferred with
  /// a small gap. When the page is shorter than the screen it is centered
  /// (normal papers). [animated] jumps fly the §5 flight; the initial open
  /// fit lands instantly.
  void fitPageWidth(
    Rect docRect,
    Size screenSize, {
    double margin = 16,
    bool animated = true,
  }) {
    if (screenSize.isEmpty || docRect.width <= 0) return;

    // §5 infinite papers restore the SAVED view once per open.
    if (_infinite &&
        animated &&
        !_didRestoreInfinite &&
        _tryRestoreInfiniteView()) {
      return;
    }

    final usable = math.max(64.0, screenSize.width - margin * 2);
    var s = usable / docRect.width;
    // Don't zoom absurdly far in for very small pages.
    if (s > 2.5) s = 2.5;
    final targetScale = s.clamp(minScale, maxScale);
    final topGap = 20.0;
    final scaledH = docRect.height * targetScale;
    Offset targetPan;
    if (scaledH <= screenSize.height && !_infinite) {
      // Whole page fits → center it (never center-lock infinite papers).
      targetPan = screenSize.center(Offset.zero) - docRect.center * targetScale;
    } else {
      targetPan = Offset(
        (screenSize.width - docRect.width * targetScale) / 2 -
            docRect.left * targetScale,
        topGap - docRect.top * targetScale,
      );
    }

    if (!animated || screenExtent.isEmpty) {
      _scale = targetScale;
      _pan = targetPan;
      clampToDoc();
      notifyListeners();
      return;
    }

    // §5 flight duration: min(520ms, 150 + distance × 0.08).
    final dist = (targetPan - _pan).distance;
    final ms = math.min(520.0, 150.0 + dist * 0.08);
    _jumping = true;
    _jumpFromScale = _scale;
    _jumpToScale = targetScale;
    _jumpFromPan = _pan;
    _jumpToPan = targetPan;
    _jumpElapsed = Duration.zero;
    _lastJumpAt = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    SchedulerBinding.instance.scheduleFrameCallback(_jumpTick);
  }

  void _jumpTick(Duration timestamp) {
    if (!_jumping) return;
    final dt = (timestamp - _lastJumpAt).inMicroseconds / 1e6;
    _lastJumpAt = timestamp;
    if (dt <= 0 || dt > 0.25) {
      SchedulerBinding.instance
          .scheduleFrameCallback(_jumpTick, rescheduling: true);
      return;
    }
    _jumpElapsed += Duration(microseconds: (dt * 1e6).round());
    const totalMs = 520;
    var t =
        (_jumpElapsed.inMilliseconds / totalMs).clamp(0.0, 1.0).toDouble();
    // Cubic ease-out.
    final e = 1 - (1 - t) * (1 - t) * (1 - t);
    _scale = _jumpFromScale + (_jumpToScale - _jumpFromScale) * e;
    _pan = Offset.lerp(_jumpFromPan, _jumpToPan, e)!;
    notifyListeners();
    if (t >= 1.0) {
      _jumping = false;
      _scale = _jumpToScale;
      _pan = _jumpToPan;
      clampToDoc();
      notifyListeners();
      endInteraction();
      return;
    }
    SchedulerBinding.instance
        .scheduleFrameCallback(_jumpTick, rescheduling: true);
  }

  // ------------------------------------------------ §5 infinite memory

  /// Last view of each infinite notebook (notebookId → (pan, scale)) so
  /// reopening lands exactly where you left off.
  static final Map<int, (Offset, double)> _infiniteViews = {};

  void _saveInfiniteView() {
    if (!_infinite) return;
    final nb = StrokeEngine.I.notebook;
    if (nb == null) return;
    _infiniteViews[nb.id] = (_pan, _scale);
  }

  bool _tryRestoreInfiniteView() {
    if (!_infinite) return false;
    final nb = StrokeEngine.I.notebook;
    if (nb == null) return false;
    _didRestoreInfinite = true;
    final saved = _infiniteViews[nb.id];
    if (saved == null) return false;
    _scale = saved.$2.clamp(minScale, maxScale);
    _pan = saved.$1;
    clampToDoc();
    notifyListeners();
    return true;
  }

  // ------------------------------------------------------------- fling

  double _flingSpeed = 0;
  Offset _flingVelocity = Offset.zero;
  bool get isFlinging => _flingSpeed > 0;

  /// Starts an inertial scroll from a finger-lift velocity (screen px/s).
  /// Exponential decay keeps the motion buttery; [clampToDoc] runs every
  /// frame so the pages glide and settle inside the document bounds.
  void startFling(Offset velocityScreenPerSec) {
    _cancelJump();
    stopFling();
    _flingVelocity = velocityScreenPerSec;
    _flingSpeed = velocityScreenPerSec.distance;
    if (_flingSpeed < 40) {
      _flingSpeed = 0;
      return;
    }
    _lastFlingAt = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    SchedulerBinding.instance.scheduleFrameCallback(_flingTick);
  }

  void stopFling() {
    _flingSpeed = 0;
    _flingVelocity = Offset.zero;
  }

  Duration _lastFlingAt = Duration.zero;

  void _flingTick(Duration timestamp) {
    if (!isFlinging) return;
    final dt = (timestamp - _lastFlingAt).inMicroseconds / 1e6;
    _lastFlingAt = timestamp;
    if (dt <= 0 || dt > 0.25) {
      SchedulerBinding.instance
          .scheduleFrameCallback(_flingTick, rescheduling: true);
      return;
    }
    // Exponential decay (~tau 240ms) — close to ClampingScrollPhysics feel.
    const tau = 0.24;
    final decay = math.exp(-dt / tau);
    _pan += _flingVelocity * dt;
    _flingVelocity *= decay;
    _flingSpeed = _flingVelocity.distance;
    clampToDoc();
    notifyListeners();
    if (_flingSpeed < 40) {
      stopFling();
      endInteraction();
      return;
    }
    // Re-schedule from INSIDE a frame callback → rescheduling: true.
    SchedulerBinding.instance
        .scheduleFrameCallback(_flingTick, rescheduling: true);
  }

  /// Called at the END of a pinch/zoom gesture: starts the settle timer.
  void endInteraction() {
    _saveInfiniteView();
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 220), () {
      renderTick.value++;
    });
  }

  /// Immediate re-render request (e.g. PDF page became visible).
  void requestRender() {
    renderTick.value++;
  }

  @override
  void dispose() {
    _saveInfiniteView();
    stopFling();
    _settleTimer?.cancel();
    super.dispose();
  }
}
