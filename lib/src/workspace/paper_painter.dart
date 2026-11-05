import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/paper.dart';

/// Paints one page's paper: background fill + template lines.
///
/// The canvas is expected to be translated to the page origin already;
/// [size] is the page's logical size (PageSizeDef.size).
///
/// [paintBackground] can be disabled when a PDF background tile is painted
/// underneath (PDF notebooks show the PDF render instead of the paper fill;
/// template lines still render above it).
class PaperPainter extends CustomPainter {
  PaperPainter({
    required this.template,
    required this.paperColor,
    required this.size,
    this.paintBackground = true,
  });

  final TemplateId template;
  final Color paperColor;
  final Size size;
  final bool paintBackground;

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

    final lineColor = templateLineColor(paperColor);
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    switch (template) {
      case TemplateId.blank:
        break;
      case TemplateId.ruled:
        _ruled(canvas, line);
        break;
      case TemplateId.college:
        _ruled(canvas, line);
        canvas.drawLine(
          const Offset(72, 0),
          Offset(72, size.height),
          line,
        );
        break;
      case TemplateId.grid:
        _gridLines(canvas, line, line);
        break;
      case TemplateId.dots:
        _dots(canvas, lineColor);
        break;
      case TemplateId.graph:
        final major = Paint()
          ..color = lineColor
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke;
        _gridLines(canvas, line, major);
        break;
      case TemplateId.isometric:
        _isometric(canvas, line);
        break;
      case TemplateId.hex:
        _hex(canvas, line);
        break;
      case TemplateId.staff:
        _staff(canvas, line);
        break;
      case TemplateId.crossGrid:
        _gridLines(canvas, line, line);
        _cellDiagonals(canvas, line);
        break;
      case TemplateId.diagonal:
        _lineFamily(canvas, line, math.pi / 4, GRID_PITCH * 2);
        break;
      case TemplateId.manuscript:
        _manuscript(canvas, line, lineColor);
        break;
    }

    canvas.restore();
  }

  // ------------------------------------------------------------------ ruled

  /// Horizontal lines every GRID_PITCH, offset so the first line doesn't lie
  /// on the top paper edge.
  void _ruled(Canvas canvas, Paint line) {
    for (var y = GRID_PITCH; y < size.height; y += GRID_PITCH) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  // ------------------------------------------------------------------- grid

  void _gridLines(Canvas canvas, Paint minor, Paint major) {
    var i = 0;
    for (var y = GRID_PITCH; y < size.height; y += GRID_PITCH, i++) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        (i + 1) % 4 == 0 ? major : minor,
      );
    }
    i = 0;
    for (var x = GRID_PITCH; x < size.width; x += GRID_PITCH, i++) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        (i + 1) % 4 == 0 ? major : minor,
      );
    }
  }

  void _cellDiagonals(Canvas canvas, Paint line) {
    for (var y = GRID_PITCH; y < size.height; y += GRID_PITCH) {
      for (var x = GRID_PITCH; x < size.width; x += GRID_PITCH) {
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

  void _dots(Canvas canvas, Color color) {
    final fill = Paint()..color = color;
    for (var y = GRID_PITCH; y < size.height; y += GRID_PITCH) {
      for (var x = GRID_PITCH; x < size.width; x += GRID_PITCH) {
        canvas.drawCircle(Offset(x, y), 1.2, fill);
      }
    }
  }

  // -------------------------------------------------------------- isometric

  /// 30° diagonal lines in both directions + verticals.
  void _isometric(Canvas canvas, Paint line) {
    const a = math.pi / 6; // 30°
    _lineFamily(canvas, line, a, GRID_PITCH);
    _lineFamily(canvas, line, -a, GRID_PITCH);
    for (var x = GRID_PITCH; x < size.width; x += GRID_PITCH) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
  }

  /// Family of infinite lines at [angle] with perpendicular spacing [pitch],
  /// clipped to the page rect.
  void _lineFamily(Canvas canvas, Paint line, double angle, double pitch) {
    final rect = Offset.zero & size;
    final d = Offset(math.cos(angle), math.sin(angle));
    final n = Offset(-d.dy, d.dx); // unit normal
    final diag = rect.size.longestSide;
    final maxK = (diag / pitch).floor() + 2;
    for (var k = -maxK; k <= maxK; k++) {
      final q = n * (k * pitch); // a point on the k-th line
      final seg = _clipSegment(rect, q - d * diag, q + d * diag);
      if (seg == null) continue;
      canvas.drawLine(seg.$1, seg.$2, line);
    }
  }

  // -------------------------------------------------------------------- hex

  /// Flat-top hexagon tiling with circumradius GRID_PITCH * 0.75.
  void _hex(Canvas canvas, Paint line) {
    final r = GRID_PITCH * 0.75;
    final dx = 1.5 * r; // column spacing
    final dy = math.sqrt(3) * r; // vertical spacing inside a column
    final cols = (size.width / dx).floor() + 1;
    final rows = (size.height / dy).floor() + 2;
    for (var col = -1; col <= cols; col++) {
      final cx = col * dx;
      for (var row = -1; row <= rows; row++) {
        final cy = row * dy + (col.isOdd ? dy / 2 : 0);
        final path = Path();
        for (var v = 0; v < 6; v++) {
          final a = v * math.pi / 3;
          final px = cx + math.cos(a) * r;
          final py = cy + math.sin(a) * r;
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

  /// Groups of 5 horizontal lines (gap 8) repeating every 96 units.
  void _staff(Canvas canvas, Paint line) {
    for (var y0 = 96.0; y0 + 32.0 <= size.height; y0 += 96) {
      for (var i = 0; i < 5; i++) {
        final y = y0 + i * 8.0;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      }
    }
  }

  // -------------------------------------------------------------- manuscript

  /// Handwriting guide: baseline every 64 units + dashed midline 32 above
  /// (dashes 6 on / 4 off).
  void _manuscript(Canvas canvas, Paint line, Color lineColor) {
    final dash = Paint()
      ..color = lineColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var y = 64.0; y < size.height; y += 64) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      final midY = y - 32;
      if (midY > 0) {
        var x = 0.0;
        while (x < size.width) {
          final end = math.min(x + 6, size.width);
          canvas.drawLine(Offset(x, midY), Offset(end, midY), dash);
          x = end + 4;
        }
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
        oldDelegate.paintBackground != paintBackground;
  }
}
