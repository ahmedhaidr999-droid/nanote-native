import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

/// Unified zoom/pan. ONE matrix: screen = doc × scale + pan.
///
/// All painting happens inside a single Transform driven by [matrix]; input
/// is converted through the inverse — ink can never drift.
///
/// v2.0.1 additions:
///  * [panBounds] + [clampToDoc] — the document can never be panned fully
///    off-screen. When an axis fits inside the viewport it is kept perfectly
///    CENTERED (fixes "pages not centered / floating").
///  * [fitPageWidth] — opens/jumps fit the page WIDTH (like every notes app).
///  * [startFling] — ballistic inertial scrolling for smooth continuous
///    vertical page flow after a pan gesture ends.
class ViewportController extends ChangeNotifier {
  double _scale = 1.0;
  Offset _pan = Offset.zero;

  static const double minScale = 0.3;
  static const double maxScale = 8.0;

  /// How far past the doc edges a pan may overshoot before clamping
  /// (logical px) — keeps panning from feeling rigid mid-gesture.
  static const double _overscrollMargin = 96.0;

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
    final br = toDoc(Offset(screenSize.width, screenSize.height));
    return Rect.fromLTRB(tl.dx, tl.dy, br.dx, br.dy);
  }

  // ----------------------------------------------------------- clamping

  /// Clamps the current pan so the doc stays reachable: an axis that fits the
  /// viewport is centered; a larger axis keeps its edges within
  /// [_overscrollMargin] of the viewport borders.
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
      // Doc fits → keep it perfectly centered on this axis.
      final docCenter = (docMin + docMax) / 2 * _scale;
      return (view / 2) - docCenter;
    }
    // Doc larger than the viewport → keep edges within the margin.
    final minPan = view - docMax * _scale - _overscrollMargin;
    final maxPan = -docMin * _scale + _overscrollMargin;
    return panAxis.clamp(minPan, maxPan);
  }

  void setMatrix(double scale, Offset pan, {bool settle = false}) {
    _scale = scale.clamp(minScale, maxScale);
    _pan = pan;
    clampToDoc();
    notifyListeners();
    if (settle) endInteraction();
  }

  void panBy(Offset screenDelta) {
    _pan += screenDelta;
    clampToDoc();
    notifyListeners();
  }

  /// Zoom by [factor] keeping the doc point under [focalScreen] fixed.
  void zoomBy(double factor, Offset focalScreen) {
    zoomTo(_scale * factor, focalScreen);
  }

  void zoomTo(double target, Offset focalScreen) {
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
    _pan = screenSize.center(Offset.zero) - docPoint * _scale;
    clampToDoc();
    notifyListeners();
  }

  /// Centers the given doc rect (a page) in the screen at 1x.
  void fitRect(Rect docRect, Size screenSize, {double targetScale = 1.0}) {
    _scale = targetScale.clamp(minScale, maxScale);
    _pan = screenSize.center(Offset.zero) - docRect.center * _scale;
    clampToDoc();
    notifyListeners();
  }

  /// Fits the WIDTH of [docRect] into the screen (notes-app style): the page
  /// spans the full canvas width, vertically the page top is preferred with a
  /// small gap. When the page is shorter than the screen it is centered.
  void fitPageWidth(Rect docRect, Size screenSize, {double margin = 16}) {
    if (screenSize.isEmpty || docRect.width <= 0) return;
    final usable = math.max(64.0, screenSize.width - margin * 2);
    var s = usable / docRect.width;
    // Don't zoom absurdly far in for very small pages.
    if (s > 2.5) s = 2.5;
    _scale = s.clamp(minScale, maxScale);
    final topGap = 20.0;
    final scaledH = docRect.height * _scale;
    if (scaledH <= screenSize.height) {
      // Whole page fits → center it.
      _pan = screenSize.center(Offset.zero) - docRect.center * _scale;
    } else {
      _pan = Offset(
        (screenSize.width - docRect.width * _scale) / 2 - docRect.left * _scale,
        topGap - docRect.top * _scale,
      );
    }
    clampToDoc();
    notifyListeners();
  }

  // ------------------------------------------------------------- fling

  double _flingSpeed = 0;
  Offset _flingVelocity = Offset.zero;
  bool get isFlinging => _flingSpeed > 0;

  /// Starts an inertial scroll from a finger-lift velocity (screen px/s).
  /// Exponential decay keeps the motion buttery; [clampToDoc] runs every
  /// frame so the pages glide and settle inside the document bounds.
  void startFling(Offset velocityScreenPerSec) {
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
    stopFling();
    _settleTimer?.cancel();
    super.dispose();
  }
}
