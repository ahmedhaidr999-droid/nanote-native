import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../models/page_elements.dart';
import '../models/paper.dart';
import 'tool_controller.dart';

/// Result of a recognition pass: the replacement [ShapeEl] (null when nothing
/// matched) plus a 0..1 confidence. The caller (gesture router) commits the
/// swap itself via `StrokeEngine.replaceStrokeWithShape`.
class RecognizedShape {
  final ShapeEl? element; // null when nothing recognized
  final double confidence; // 0..1
  const RecognizedShape(this.element, this.confidence);
}

/// Pure-Dart draw & hold shape recognition.
///
/// Pipeline: RDP simplify → closure test → corner count + radial variance
/// heuristics → line / ellipse / triangle / rect / polygon / star. Input and
/// output geometry live in the SAME page space.
class ShapeRecognizer {
  static const double rdpEpsilon = 2.0;

  /// Minimum bounding-box diagonal (page units) for a recognizable gesture.
  static const double _minDiagonal = 8.0;

  /// First→last distance below this fraction of the bbox diagonal = closed.
  static const double _closureRatio = 0.18;

  /// Radial variance ratio (variance / mean²) below this = ellipse-ish.
  static const double _ellipseVariance = 0.02;

  static RecognizedShape recognize(List<Offset> pts) {
    if (pts.length < 4) return const RecognizedShape(null, 0);

    var minX = pts.first.dx, maxX = pts.first.dx;
    var minY = pts.first.dy, maxY = pts.first.dy;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final diag = math.sqrt(
        (maxX - minX) * (maxX - minX) + (maxY - minY) * (maxY - minY));
    if (diag < _minDiagonal) return const RecognizedShape(null, 0);

    final simplified = _rdp(pts, rdpEpsilon);
    if (simplified.length < 2) return const RecognizedShape(null, 0);

    final first = pts.first;
    final last = pts.last;
    final closed = (first - last).distance < _closureRatio * diag;

    if (!closed) {
      if (simplified.length <= 2) {
        // Straight-ish open gesture → LINE.
        return RecognizedShape(
          _line(first, last, minX, minY, maxX, maxY),
          0.9,
        );
      }
      // Open multi-corner gesture: not part of the v1.9.1 shape set.
      return const RecognizedShape(null, 0);
    }

    // ---- closed shapes ------------------------------------------------

    // RDP always keeps both endpoints; for a closed gesture they are the
    // duplicate closure point, so the real corner count is length - 1.
    final cornerCount = simplified.length - 1;
    if (cornerCount < 1) return const RecognizedShape(null, 0);
    final corners = simplified.sublist(0, simplified.length - 1);

    if (cornerCount <= 2) {
      // Few corners + low radial variance → ELLIPSE.
      final ratio = _radialVarianceRatio(pts);
      if (ratio < _ellipseVariance) {
        // Lower variance → higher confidence (0.85 .. 0.95).
        var conf = 0.85 + (_ellipseVariance - ratio) / _ellipseVariance * 0.10;
        if (conf > 0.95) conf = 0.95;
        return RecognizedShape(
          _bbox(ShapeType.ellipse, minX, minY, maxX, maxY),
          conf,
        );
      }
      return const RecognizedShape(null, 0);
    }

    if (cornerCount == 3) {
      return RecognizedShape(
        _bbox(ShapeType.triangle, minX, minY, maxX, maxY),
        0.8,
      );
    }

    if (cornerCount == 4) {
      if (_hasRightAngles(corners)) {
        return RecognizedShape(
          _bbox(ShapeType.rect, minX, minY, maxX, maxY),
          0.85,
        );
      }
      return RecognizedShape(
        _bbox(ShapeType.polygon, minX, minY, maxX, maxY, sides: 4),
        0.5,
      );
    }

    if (cornerCount <= 8) {
      if (_isStar(corners, _centroid(pts))) {
        return RecognizedShape(
          _bbox(ShapeType.star, minX, minY, maxX, maxY),
          0.7,
        );
      }
      return RecognizedShape(
        _bbox(ShapeType.polygon, minX, minY, maxX, maxY, sides: cornerCount),
        0.6,
      );
    }

    // Scribbled closed blob → ELLIPSE.
    return RecognizedShape(
      _bbox(ShapeType.ellipse, minX, minY, maxX, maxY),
      0.55,
    );
  }

  // ---------------------------------------------------------------- helpers

  /// Ramer–Douglas–Peucker simplification (iterative, epsilon in page units).
  static List<Offset> _rdp(List<Offset> pts, double epsilon) {
    if (pts.length < 3) return List<Offset>.of(pts);
    final keep = List<bool>.filled(pts.length, false);
    keep.first = true;
    keep.last = true;
    final stack = <int>[0, pts.length - 1];
    while (stack.isNotEmpty) {
      final end = stack.removeLast();
      final start = stack.removeLast();
      if (end <= start + 1) continue;
      var maxDist = -1.0;
      var maxIdx = -1;
      for (var i = start + 1; i < end; i++) {
        final d = _distanceToSegment(pts[i], pts[start], pts[end]);
        if (d > maxDist) {
          maxDist = d;
          maxIdx = i;
        }
      }
      if (maxDist > epsilon) {
        keep[maxIdx] = true;
        stack
          ..add(start)
          ..add(maxIdx)
          ..add(maxIdx)
          ..add(end);
      }
    }
    return [
      for (var i = 0; i < pts.length; i++)
        if (keep[i]) pts[i],
    ];
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return (p - a).distance;
    var t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final px = a.dx + t * dx;
    final py = a.dy + t * dy;
    return math.sqrt((p.dx - px) * (p.dx - px) + (p.dy - py) * (p.dy - py));
  }

  /// Variance of the points' distance to their centroid, normalized by the
  /// mean distance squared. Low (< ~0.02) ⇒ ellipse-like roundness.
  static double _radialVarianceRatio(List<Offset> pts) {
    final c = _centroid(pts);
    final dists = <double>[];
    var sum = 0.0;
    for (final p in pts) {
      final d = math.sqrt(
          (p.dx - c.dx) * (p.dx - c.dx) + (p.dy - c.dy) * (p.dy - c.dy));
      dists.add(d);
      sum += d;
    }
    final mean = sum / dists.length;
    if (mean <= 0) return double.infinity;
    var varSum = 0.0;
    for (final d in dists) {
      varSum += (d - mean) * (d - mean);
    }
    final variance = varSum / dists.length;
    return variance / (mean * mean);
  }

  static Offset _centroid(List<Offset> pts) {
    var sx = 0.0, sy = 0.0;
    for (final p in pts) {
      sx += p.dx;
      sy += p.dy;
    }
    return Offset(sx / pts.length, sy / pts.length);
  }

  /// True when every turn between successive edges of the closed [corners]
  /// polygon is 90° ± 20°.
  static bool _hasRightAngles(List<Offset> corners) {
    final n = corners.length;
    if (n < 3) return false;
    final tolerance = math.pi / 9; // 20°
    for (var i = 0; i < n; i++) {
      final prev = corners[(i - 1 + n) % n];
      final cur = corners[i];
      final next = corners[(i + 1) % n];
      final e1 = cur - prev;
      final e2 = next - cur;
      final len1 = e1.distance;
      final len2 = e2.distance;
      if (len1 == 0 || len2 == 0) return false;
      final cosTurn =
          (e1.dx * e2.dx + e1.dy * e2.dy) / (len1 * len2);
      final turn = math.acos(cosTurn.clamp(-1.0, 1.0));
      if ((turn - math.pi / 2).abs() > tolerance) return false;
    }
    return true;
  }

  /// Star signature: corner radii (about [centroid]) alternate between
  /// long (> 1.25× mean) and short (< 0.8× mean).
  static bool _isStar(List<Offset> corners, Offset centroid) {
    if (corners.length < 5) return false;
    final radii = <double>[];
    var sum = 0.0;
    for (final c in corners) {
      final r = (c - centroid).distance;
      radii.add(r);
      sum += r;
    }
    final mean = sum / radii.length;
    if (mean <= 0) return false;
    var classified = 0;
    bool? prevLong;
    for (final r in radii) {
      if (r > mean * 1.25) {
        if (prevLong == true) return false; // two longs in a row
        prevLong = true;
        classified++;
      } else if (r < mean * 0.8) {
        if (prevLong == false) return false; // two shorts in a row
        prevLong = false;
        classified++;
      }
      // Radii in the ambiguous band don't break the alternation.
    }
    return classified >= 4;
  }

  // ---------------------------------------------------------------- output

  /// Bbox-geometry shape (rect-like / ellipse / triangle / polygon / star).
  static ShapeEl _bbox(
    ShapeType type,
    double minX,
    double minY,
    double maxX,
    double maxY, {
    int sides = 5,
  }) {
    return ShapeEl(
      id: ElementIdGen.next(),
      z: 0, // the engine assigns the real z-order on commit
      type: type,
      strokeColor: ToolController.I.shapeStrokeColor,
      strokeWidth: ToolController.I.shapeStrokeWidth,
      x: minX,
      y: minY,
      w: maxX - minX,
      h: maxY - minY,
      sides: sides,
    );
  }

  /// Polyline-geometry shape (line) defined by its endpoints.
  static ShapeEl _line(
    Offset a,
    Offset b,
    double minX,
    double minY,
    double maxX,
    double maxY,
  ) {
    return ShapeEl(
      id: ElementIdGen.next(),
      z: 0, // the engine assigns the real z-order on commit
      type: ShapeType.line,
      strokeColor: ToolController.I.shapeStrokeColor,
      strokeWidth: ToolController.I.shapeStrokeWidth,
      x: minX,
      y: minY,
      w: maxX - minX,
      h: maxY - minY,
      pts: [a, b],
    );
  }
}
