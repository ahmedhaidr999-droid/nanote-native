import 'package:flutter/material.dart';

import '../controllers/stroke_engine.dart';
import '../models/stroke.dart';

/// Paints the committed strokes of ONE page in page-local coordinates (the
/// caller already translated the canvas to the page origin).
///
/// Normal strokes are filled with their full style color. Highlighter strokes
/// are EXCLUDED from the normal pass and rendered afterwards, grouped by
/// color: each group is drawn inside ONE `saveLayer(color.withValues(alpha: op))`
/// with a full-alpha paint, so the same color NEVER darkens where it overlaps
/// itself.
///
/// [replayAt] (audio-sync replay cursor in ms) hides strokes whose tStart is
/// after the cursor.
class InkPainter extends CustomPainter {
  InkPainter({required this.ink, this.replayAt}) : super(repaint: ink);

  final PageInk ink;
  final int? replayAt;

  @override
  void paint(Canvas canvas, Size size) {
    paintInk(canvas, ink.strokes, replayAt: replayAt);
  }

  /// True when the stroke must be hidden at the given replay cursor.
  static bool hiddenByReplay(Stroke s, int? replayAt) =>
      replayAt != null && s.tStart != null && s.tStart! > replayAt;

  /// Paints a stroke list (z-ordered, page space): normal strokes first, then
  /// highlighter groups. Shared by [InkPainter], [PageContentPainter], export
  /// and thumbnails.
  static void paintInk(Canvas canvas, List<Stroke> strokes, {int? replayAt}) {
    final paint = Paint();
    final groups = <int, List<Stroke>>{};
    for (final s in strokes) {
      if (hiddenByReplay(s, replayAt)) continue;
      if (s.style.kind == StrokeKind.highlighter) {
        groups.putIfAbsent(s.style.color, () => []).add(s);
        continue;
      }
      paint.color = s.style.flutterColor;
      canvas.drawPath(s.buildPath(), paint);
    }
    paintHighlighterGroups(canvas, groups);
  }

  /// Draws highlighter groups; each color group shares ONE translucent layer
  /// so overlapping strokes of the same color never self-darken.
  static void paintHighlighterGroups(Canvas canvas, Map<int, List<Stroke>> groups) {
    groups.forEach((color, list) {
      if (list.isEmpty) return;
      Rect? bounds;
      for (final s in list) {
        bounds = bounds == null ? s.bbox : bounds.expandToInclude(s.bbox);
      }
      if (bounds == null) return;
      final opacity = list.first.style.opacity.clamp(0.05, 1.0);
      canvas.saveLayer(
        bounds.inflate(8),
        Paint()..color = Color(color).withValues(alpha: opacity),
      );
      final paint = Paint()..color = Color(color);
      for (final s in list) {
        canvas.drawPath(s.buildPath(), paint);
      }
      canvas.restore();
    });
  }

  @override
  bool shouldRepaint(covariant InkPainter oldDelegate) {
    return oldDelegate.ink != ink || oldDelegate.replayAt != replayAt;
  }
}

/// Paints the in-progress stroke from [StrokeEngine.I.liveStroke] (page space,
/// placed on the page the user is drawing on). Repaints on every live-stroke
/// tick; paints nothing when no stroke is active.
class LiveStrokePainter extends CustomPainter {
  LiveStrokePainter({required Listenable repaint}) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final s = StrokeEngine.I.liveStroke.value;
    if (s == null || s.isEmpty) return;
    final paint = Paint();
    if (s.style.kind == StrokeKind.highlighter) {
      // Simple translucent preview — no saveLayer needed for a live preview.
      paint.color = s.style.flutterColor.withValues(alpha: 0.5);
    } else {
      paint.color = s.style.flutterColor;
    }
    canvas.drawPath(s.buildPath(), paint);
  }

  @override
  bool shouldRepaint(covariant LiveStrokePainter oldDelegate) => true;
}
