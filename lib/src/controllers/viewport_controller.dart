import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

/// Unified zoom/pan. ONE matrix: screen = doc × scale + pan.
///
/// All painting happens inside a single Transform driven by [matrix]; input
/// is converted through the inverse — ink can never drift.
class ViewportController extends ChangeNotifier {
  double _scale = 1.0;
  Offset _pan = Offset.zero;

  static const double minScale = 0.5;
  static const double maxScale = 8.0;

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

  void setMatrix(double scale, Offset pan, {bool settle = false}) {
    _scale = scale.clamp(minScale, maxScale);
    _pan = pan;
    notifyListeners();
    if (settle) endInteraction();
  }

  void panBy(Offset screenDelta) {
    _pan += screenDelta;
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
    notifyListeners();
  }

  void centerDoc(Offset docPoint, Size screenSize) {
    _pan = screenSize.center(Offset.zero) - docPoint * _scale;
    notifyListeners();
  }

  /// Centers the given doc rect (a page) in the screen at 1x.
  void fitRect(Rect docRect, Size screenSize, {double targetScale = 1.0}) {
    _scale = targetScale.clamp(minScale, maxScale);
    _pan = screenSize.center(Offset.zero) - docRect.center * _scale;
    notifyListeners();
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
    _settleTimer?.cancel();
    super.dispose();
  }
}
