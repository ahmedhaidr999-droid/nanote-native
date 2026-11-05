import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/page_elements.dart';
import '../models/paper.dart';

/// Builds the path of a [ShapeEl] in PAGE space.
///
/// * Polyline-like types (line / arrow / doubleArrow / arc) and freeform use
///   [ShapeEl.pts] — their geometry (and any rotation) is already baked into
///   the points.
/// * Bbox types (rect / roundedRect / ellipse / triangle / star / hexagon /
///   polygon) use [ShapeEl.x/y/w/h]. Rotation is NOT applied here — the
///   painter rotates the canvas around the bbox center (only when
///   `el.pts == null`).
Path buildShapePath(ShapeEl el) {
  final path = Path();
  final pts = el.pts;
  if (pts != null && pts.isNotEmpty) {
    switch (el.type) {
      case ShapeType.line:
      case ShapeType.freeform:
        path.moveTo(pts.first.dx, pts.first.dy);
        for (var i = 1; i < pts.length; i++) {
          path.lineTo(pts[i].dx, pts[i].dy);
        }
        return path;
      case ShapeType.arrow:
        _addArrow(path, pts.first, pts.last);
        return path;
      case ShapeType.doubleArrow:
        _addArrow(path, pts.first, pts.last);
        _addArrow(path, pts.last, pts.first);
        return path;
      case ShapeType.arc:
        path.moveTo(pts.first.dx, pts.first.dy);
        if (pts.length >= 3) {
          final mid = pts[pts.length ~/ 2];
          final end = pts.last;
          // Quadratic bezier that passes through the middle point:
          // B(0.5) = (start + 2*control + end) / 4 = mid.
          final control = mid * 2 - (pts.first + end) / 2;
          path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
        } else {
          path.lineTo(pts.last.dx, pts.last.dy);
        }
        return path;
      default:
        // Bbox-shaped element that (unexpectedly) carries points — fall
        // through to the bbox geometry below.
        break;
    }
  }

  // ------------------------------------------------------------------ bbox
  final cx = el.x + el.w / 2;
  final cy = el.y + el.h / 2;
  final rx = (el.w / 2).abs();
  final ry = (el.h / 2).abs();
  final box = Rect.fromCenter(
    center: Offset(cx, cy),
    width: math.max(1.0, rx * 2),
    height: math.max(1.0, ry * 2),
  );

  switch (el.type) {
    case ShapeType.rect:
      path.addRect(box);
      break;
    case ShapeType.roundedRect:
      path.addRRect(RRect.fromRectAndRadius(box, const Radius.circular(12)));
      break;
    case ShapeType.ellipse:
      path.addOval(box);
      break;
    case ShapeType.triangle:
      // Apex at top-center, base along the bottom edge.
      path.moveTo(cx, box.top);
      path.lineTo(box.right, box.bottom);
      path.lineTo(box.left, box.bottom);
      path.close();
      break;
    case ShapeType.star:
      _addStar(path, cx, cy, box.width / 2, box.height / 2, 5, 0.45);
      break;
    case ShapeType.hexagon:
      _addRegularPolygon(path, cx, cy, box.width / 2, box.height / 2, 6);
      break;
    case ShapeType.polygon:
      _addRegularPolygon(path, cx, cy, box.width / 2, box.height / 2, el.sides);
      break;
    default:
      // line/arrow/doubleArrow/arc/freeform without points: degenerate box.
      path.addRect(box);
      break;
  }
  return path;
}

/// Adds a shaft from [from] to [to] plus a solid arrowhead (two lines at
/// ±25°, length max(12, len * 0.2)) at [to]. The whole thing lives in ONE
/// stroked path.
void _addArrow(Path path, Offset from, Offset to) {
  final d = to - from;
  final len = d.distance;
  if (len < 1) {
    path.moveTo(from.dx, from.dy);
    path.lineTo(to.dx, to.dy);
    return;
  }
  final ang = d.direction;
  final headLen = math.max(12.0, len * 0.2);
  const spread = 25.0 * math.pi / 180.0;

  path.moveTo(from.dx, from.dy);
  path.lineTo(to.dx, to.dy);
  for (final a in <double>[ang + math.pi - spread, ang + math.pi + spread]) {
    path.moveTo(to.dx, to.dy);
    path.lineTo(to.dx + math.cos(a) * headLen, to.dy + math.sin(a) * headLen);
  }
}

/// n-point star centered at (cx, cy); inner vertices at [innerFrac] of the
/// outer radius.
void _addStar(Path path, double cx, double cy, double rx, double ry, int points,
    double innerFrac) {
  final n = points.clamp(3, 12);
  for (var i = 0; i < n * 2; i++) {
    final frac = i.isEven ? 1.0 : innerFrac;
    final a = -math.pi / 2 + i * math.pi / n;
    final x = cx + math.cos(a) * rx * frac;
    final y = cy + math.sin(a) * ry * frac;
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
}

/// Regular [sides]-gon (3..12) centered at (cx, cy), first vertex at the top.
void _addRegularPolygon(Path path, double cx, double cy, double rx, double ry,
    int sides) {
  final n = sides.clamp(3, 12);
  for (var i = 0; i < n; i++) {
    final a = -math.pi / 2 + i * 2 * math.pi / n;
    final x = cx + math.cos(a) * rx;
    final y = cy + math.sin(a) * ry;
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
}
