import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/paper.dart';

/// Paints one page's paper: background fill + template lines.
///
/// The canvas is expected to be translated to the page origin already;
/// [size] is the page's logical size (PageSizeDef.size — for INFINITE pages
/// the full GROWN size; the workspace passes `geometry.pageRect(i).size`).
///
/// [paintBackground] can be disabled when a PDF background tile is painted
/// underneath (PDF notebooks show the PDF render instead of the paper fill;
/// template lines still render above it).
///
/// §6 SEAMLESS INFINITE TEMPLATES: [patternOrigin] is the page's pad offset
/// (the ANCHOR's position inside the grown paper widget). The template
/// geometry is drawn ANCHOR-ALIGNED — translated by the origin — so the
/// pattern NEVER shifts when the paper grows, and the lines flow across
/// the whole grown region with NO visible boundaries. Normal pages pass
/// [Offset.zero] (identical to the classic behavior).
class PaperPainter extends CustomPainter {
  PaperPainter({
    required this.template,
    required this.paperColor,
    required this.size,
    this.paintBackground = true,
    this.patternOrigin = Offset.zero,
  });

  final TemplateId template;
  final Color paperColor;
  final Size size;
  final bool paintBackground;

  /// §6 anchor offset of the template grid (infinite papers).
  final Offset patternOrigin;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final rect = Offset.zero & size;
    if (paintBackground) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = paperColor,
      );
    }

    if (template == TemplateId.blank || size.isEmpty) return;

    // Clip all template strokes to the page rect so diagonals / hexes never
    // spill into the gap between pages.
    canvas.save();
    canvas.clipRect(rect);

    // §6: draw the template in ANCHOR space so it stays put while the
    // infinite paper grows (ink coordinates are anchor-relative too).
    canvas.translate(patternOrigin.dx, patternOrigin.dy);
    final region = Rect.fromLTWH(
      -patternOrigin.dx,
      -patternOrigin.dy,
      size.width,
      size.height,
    );

    final lineColor = templateLineColor(paperColor);
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    switch (template) {
      case TemplateId.blank:
        break;
      case TemplateId.ruled:
        _ruled(canvas, line, region);
        break;
      case TemplateId.college:
        _ruled(canvas, line, region);
        canvas.drawLine(
          Offset(72, region.top),
          Offset(72, region.bottom),
          line,
        );
        break;
      case TemplateId.grid:
        _gridLines(canvas, line, line, region);
        break;
      case TemplateId.dots:
        _dots(canvas, lineColor, region);
        break;
      case TemplateId.graph:
        final major = Paint()
          ..color = lineColor
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke;
        _gridLines(canvas, line, major, region);
        break;
      case TemplateId.isometric:
        _isometric(canvas, line, region);
        break;
      case TemplateId.hex:
        _hex(canvas, line, region);
        break;
      case TemplateId.staff:
        _staff(canvas, line, region);
        break;
      case TemplateId.crossGrid:
        _gridLines(canvas, line, line, region);
        _cellDiagonals(canvas, line, region);
        break;
      case TemplateId.diagonal:
        _lineFamily(canvas, line, region, math.pi / 4, GRID_PITCH * 2);
        break;
      case TemplateId.manuscript:
        _manuscript(canvas, line, lineColor, region);
        break;
    }

    canvas.restore();
  }

  // ------------------------------------------------------------------ ruled

  /// Horizontal lines every GRID_PITCH across [r], offset so the first line
  /// doesn't lie on the paper's original top edge.
  void _ruled(Canvas canvas, Paint line, Rect r) {
    for (var y = _afterTop(r, GRID_PITCH); y < r.bottom; y += GRID_PITCH) {
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), line);
    }
  }

  // ------------------------------------------------------------------- grid

  void _gridLines(Canvas canvas, Paint minor, Paint major, Rect r) {
    for (var y = _afterTop(r, GRID_PITCH); y < r.bottom; y += GRID_PITCH) {
      canvas.drawLine(
        Offset(r.left, y),
        Offset(r.right, y),
        _isMajor(y) ? major : minor,
      );
    }
    for (var x = _afterTop(_h(r), GRID_PITCH); x < r.right; x += GRID_PITCH) {
      canvas.drawLine(
        Offset(x, r.top),
        Offset(x, r.bottom),
        _isMajor(x) ? major : minor,
      );
    }
  }

  /// First anchor-aligned multiple of [pitch] strictly after [r.top]
  /// (identical to the classic `for (y = pitch; …)` on zero-origin pages).
  static double _afterTop(Rect r, double pitch) =>
      r.top - (r.top % pitch) + pitch;

  /// A rect reinterpreted for the horizontal axis (left↔top).
  static Rect _h(Rect r) => Rect.fromLTRB(r.top, r.left, r.bottom, r.right);

  /// Graph major lines: every 4th anchor-aligned pitch multiple.
  static bool _isMajor(double v) => (v / GRID_PITCH).round() % 4 == 0;

  void _cellDiagonals(Canvas canvas, Paint line, Rect r) {
    final yFirst = _afterTop(r, GRID_PITCH);
    final xFirst = _afterTop(_h(r), GRID_PITCH);
    for (var y = yFirst; y < r.bottom; y += GRID_PITCH) {
      for (var x = xFirst; x < r.right; x += GRID_PITCH) {
        canvas.drawLine(
          Offset(x, y),
          Offset(x + GRID_PITCH, y + GRID_PITCH),
          line,
        );
        canvas.drawLine(
          Offset(x, y + GRID_PITCH),
          Offset(x + GRID_PITCH, y),
          line,
        );
      }
    }
  }

  // ------------------------------------------------------------------- dots

  void _dots(Canvas canvas, Color color, Rect r) {
    final fill = Paint()..color = color;
    final yFirst = _afterTop(r, GRID_PITCH);
    final xFirst = _afterTop(_h(r), GRID_PITCH);
    for (var y = yFirst; y < r.bottom; y += GRID_PITCH) {
      for (var x = xFirst; x < r.right; x += GRID_PITCH) {
        canvas.drawCircle(Offset(x, y), 1.2, fill);
      }
    }
  }

  // -------------------------------------------------------------- isometric

  /// 30° diagonal lines in both directions + verticals.
  void _isometric(Canvas canvas, Paint line, Rect r) {
    const a = math.pi / 6; // 30°
    _lineFamily(canvas, line, r, a, GRID_PITCH);
    _lineFamily(canvas, line, r, -a, GRID_PITCH);
    final xFirst = _afterTop(_h(r), GRID_PITCH);
    for (var x = xFirst; x < r.right; x += GRID_PITCH) {
      canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), line);
    }
  }

  /// Family of infinite lines at [angle] with perpendicular spacing [pitch],
  /// clipped to [r]. Anchor-aligned: line positions are multiples of the
  /// pitch measured from the anchor, so growth never shifts the family.
  void _lineFamily(Canvas canvas, Paint line, Rect r, double angle, double pitch) {
    final d = Offset(math.cos(angle), math.sin(angle));
    final n = Offset(-d.dy, d.dx); // unit normal
    // Anchor sits at local (0,0) inside [r]'s coordinate space.
    final proj0 = 0.0; // anchor projection on the normal
    final diag = r.size.longestSide;
    // Range of normal-projections covering [r].
    final corners = [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight];
    var minProj = double.infinity;
    var maxProj = double.negativeInfinity;
    for (final c in corners) {
      final p = c.dx * n.dx + c.dy * n.dy;
      minProj = math.min(minProj, p);
      maxProj = math.max(maxProj, p);
    }
    final kMin = ((minProj - proj0) / pitch).floor() - 1;
    final kMax = ((maxProj - proj0) / pitch).ceil() + 1;
    for (var k = kMin; k <= kMax; k++) {
      final q = n * (k * pitch); // a point on the k-th line
      final seg = _clipSegment(r, q - d * diag, q + d * diag);
      if (seg == null) continue;
      canvas.drawLine(seg.$1, seg.$2, line);
    }
  }

  // -------------------------------------------------------------------- hex

  /// Flat-top hexagon tiling with circumradius GRID_PITCH * 0.75.
  void _hex(Canvas canvas, Paint line, Rect r) {
    final hr = GRID_PITCH * 0.75;
    final dx = 1.5 * hr; // column spacing
    final dy = math.sqrt(3) * hr; // vertical spacing inside a column
    final colMin = (r.left / dx).floor() - 1;
    final colMax = (r.right / dx).ceil() + 1;
    final rowMin = (r.top / dy).floor() - 1;
    final rowMax = (r.bottom / dy).ceil() + 1;
    for (var col = colMin; col <= colMax; col++) {
      final cx = col * dx;
      for (var row = rowMin; row <= rowMax; row++) {
        final cy = row * dy + (col.isOdd ? dy / 2 : 0);
        final path = Path();
        for (var v = 0; v < 6; v++) {
          final a = v * math.pi / 3;
          final px = cx + math.cos(a) * hr;
          final py = cy + math.sin(a) * hr;
          if (v == 0) {
            path.moveTo(px, py);
          } else {
            path.lineTo(px, py);
          }
        }
        path.close();
        canvas.drawPath(path, line);
      }
    }
  }

  // ------------------------------------------------------------------ staff

  /// Groups of 5 horizontal lines (gap 8) repeating every 96 units,
  /// anchor-aligned.
  void _staff(Canvas canvas, Paint line, Rect r) {
    final first = _afterTop(r, 96);
    for (var y0 = first; y0 + 32.0 <= r.bottom; y0 += 96) {
      for (var i = 0; i < 5; i++) {
        final y = y0 + i * 8.0;
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y), line);
      }
    }
  }

  // -------------------------------------------------------------- manuscript

  /// Handwriting guide: baseline every 64 units + dashed midline 32 above
  /// (dashes 6 on / 4 off), anchor-aligned.
  void _manuscript(Canvas canvas, Paint line, Color lineColor, Rect r) {
    final dash = Paint()
      ..color = lineColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final first = _afterTop(r, 64);
    for (var y = first; y < r.bottom; y += 64) {
      canvas.drawLine(Offset(r.left, y), Offset(r.right, y), line);
      final midY = y - 32;
      var x = r.left;
      while (x < r.right) {
        final end = math.min(x + 6, r.right);
        canvas.drawLine(Offset(x, midY), Offset(end, midY), dash);
        x = end + 4;
      }
    }
  }

  // -------------------------------------------------------------- clip util

  /// Liang–Barsky clip of segment a→b to [r]; null when fully outside.
  (Offset, Offset)? _clipSegment(Rect r, Offset a, Offset b) {
    var t0 = 0.0;
    var t1 = 1.0;
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final tests = <(double, double)>[
      (-dx, a.dx - r.left),
      (dx, r.right - a.dx),
      (-dy, a.dy - r.top),
      (dy, r.bottom - a.dy),
    ];
    for (final (p, q) in tests) {
      if (p == 0) {
        if (q < 0) return null;
        continue;
      }
      final t = q / p;
      if (p < 0) {
        if (t > t1) return null;
        if (t > t0) t0 = t;
      } else {
        if (t < t0) return null;
        if (t < t1) t1 = t;
      }
    }
    return (
      Offset(a.dx + t0 * dx, a.dy + t0 * dy),
      Offset(a.dx + t1 * dx, a.dy + t1 * dy),
    );
  }

  @override
  bool shouldRepaint(covariant PaperPainter oldDelegate) {
    return oldDelegate.template != template ||
        oldDelegate.paperColor != paperColor ||
        oldDelegate.size != size ||
        oldDelegate.paintBackground != paintBackground ||
        oldDelegate.patternOrigin != patternOrigin;
  }
}
