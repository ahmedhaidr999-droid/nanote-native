import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/viewport_controller.dart';
import '../models/paper.dart';
import '../theme/nanote_theme.dart';

/// Doc-space state of the on-canvas ruler. All geometry is in DOCUMENT
/// coordinates; the overlay renders inside the page transform.
class RulerState extends ChangeNotifier {
  bool active = false;
  Offset centerDoc = const Offset(400, 300);
  double angle = 0; // radians
  double length = 420; // doc units

  Offset? _dragOffset;

  /// The ruler segment endpoints in doc space.
  (Offset, Offset) segment() {
    final dir = Offset(math.cos(angle), math.sin(angle));
    final half = length / 2;
    return (centerDoc - dir * half, centerDoc + dir * half);
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    var t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  /// Hit test for dragging (distance point→segment ≤ 28 doc units).
  bool hitBody(Offset doc) {
    final (a, b) = segment();
    return _distToSegment(doc, a, b) <= 28;
  }

  /// Rotate handle: a point 48 beyond the FIRST endpoint along the ruler
  /// direction; hit radius 26.
  bool hitRotateHandle(Offset doc) {
    final (a, b) = segment();
    final d = b - a;
    final len = d.distance;
    if (len == 0) return false;
    final dir = d / len;
    final handle = a - dir * 48;
    return (doc - handle).distance <= 26;
  }

  /// Stores the drag offset so [moveTo] keeps the ruler under the finger.
  void beginDrag(Offset doc) {
    _dragOffset = centerDoc - doc;
  }

  void moveTo(Offset doc) {
    final off = _dragOffset;
    if (off == null) return;
    centerDoc = doc + off;
    notifyListeners();
  }

  void rotateBy(double delta) {
    angle += delta;
    notifyListeners();
  }

  /// Toggles ruler visibility (used by the tool rail).
  void toggle() {
    active = !active;
    notifyListeners();
  }

  /// Ink snap: project [p] onto the ruler segment; when the perpendicular
  /// distance is ≤ 14 return the projected point, else null.
  Offset? snap(Offset p) {
    final (a, b) = segment();
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return null;
    var t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    final proj = a + ab * t;
    return (p - proj).distance <= 14 ? proj : null;
  }
}

/// Renders the ruler inside the doc-space stack (listens to [ruler]).
///
/// Because it lives INSIDE the page transform at doc scale, the painter is
/// sized to the segment's bounding box and translated to its origin; stroke
/// widths are divided by the viewport scale so borders stay ~constant on
/// screen across zoom levels.
class RulerOverlay extends StatelessWidget {
  const RulerOverlay({super.key, required this.ruler, required this.viewport});

  final RulerState ruler;
  final ViewportController viewport;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ruler,
      builder: (context, _) {
        if (!ruler.active) return const SizedBox.shrink();
        final (a, b) = ruler.segment();
        final rect = Rect.fromPoints(a, b).inflate(90);
        final scheme = Theme.of(context).colorScheme;
        final colors = nanoteColors(context);
        return Positioned.fromRect(
          rect: rect,
          child: CustomPaint(
            size: rect.size,
            painter: _RulerPainter(
              ruler: ruler,
              viewport: viewport,
              origin: rect.topLeft,
              bodyColor: scheme.surface,
              borderColor: scheme.outline,
              tickColor: colors.mutedFg,
              handleColor: scheme.primary,
            ),
          ),
        );
      },
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.ruler,
    required this.viewport,
    required this.origin,
    required this.bodyColor,
    required this.borderColor,
    required this.tickColor,
    required this.handleColor,
  });

  final RulerState ruler;
  final ViewportController viewport;
  final Offset origin;
  final Color bodyColor;
  final Color borderColor;
  final Color tickColor;
  final Color handleColor;

  @override
  void paint(Canvas canvas, Size size) {
    final sw = 1.5 / math.max(0.1, viewport.scale);

    // Work in doc coordinates.
    canvas.save();
    canvas.translate(-origin.dx, -origin.dy);

    final center = ruler.centerDoc;
    final half = ruler.length / 2;

    // Ruler body (rounded rect along the segment, breadth 56).
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(ruler.angle);
    final body = Rect.fromLTWH(-half, -28, ruler.length, 56);
    final rrect = RRect.fromRectAndRadius(
      body,
      const Radius.circular(NANOTE_RADIUS),
    );
    canvas.drawRRect(rrect, Paint()..color = bodyColor.withValues(alpha: 0.85));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw,
    );

    // Tick marks every GRID_PITCH along the ruler; every 5th is longer.
    final tick = Paint()
      ..color = tickColor
      ..strokeWidth = sw
      ..style = PaintingStyle.stroke;
    final steps = (half / GRID_PITCH).floor();
    for (var k = -steps; k <= steps; k++) {
      final x = k * GRID_PITCH;
      final len = k % 5 == 0 ? 16.0 : 8.0;
      canvas.drawLine(Offset(x, -28), Offset(x, -28 + len), tick);
    }
    canvas.restore();

    // Rotate handle: 48 beyond the FIRST endpoint along the ruler direction.
    final dir = Offset(math.cos(ruler.angle), math.sin(ruler.angle));
    final first = center - dir * half;
    final handle = first - dir * 48;
    canvas.drawCircle(handle, 14, Paint()..color = bodyColor);
    canvas.drawCircle(
      handle,
      14,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw,
    );
    canvas.drawCircle(handle, 4.5, Paint()..color = handleColor);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) => true;
}
