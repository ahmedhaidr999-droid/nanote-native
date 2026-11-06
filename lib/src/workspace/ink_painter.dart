import 'package:flutter/material.dart';

import '../controllers/stroke_engine.dart';
import '../models/stroke.dart';

/// Paints the committed strokes of ONE page in page-local coordinates (the
/// caller already translated the canvas to the page origin).
///
/// Normal strokes are filled with their full style color. Highlighter
/// strokes are EXCLUDED from the normal pass and rendered afterwards,
/// grouped by (color, opacity): each group is drawn inside ONE
/// `saveLayer` with a MULTIPLY blend, so
///   * the same color NEVER darkens where it overlaps itself, and
///   * the ink/PDF text UNDER the highlight stays readable at ANY opacity
///     (multiply keeps dark text dark — a real highlighter tints the
///     paper, it never covers it).
///
/// HIGHLIGHTER OPACITY BUG (user report) — the old code grouped by color
/// only and used the FIRST stroke's opacity for the whole group, so a
/// stroke drawn right after changing the transparency rendered at the
/// OLD value until the group's composition changed (page switch).
/// Grouping by (color, opacity) makes every stroke render at its OWN
/// opacity, captured at creation time from the live setting.
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
    final groups = <(int, double), List<Stroke>>{};
    for (final s in strokes) {
      if (hiddenByReplay(s, replayAt)) continue;
      if (s.style.kind == StrokeKind.highlighter) {
        groups
            .putIfAbsent((s.style.color, s.style.opacity), () => [])
            .add(s);
        continue;
      }
      paint.color = s.style.flutterColor;
      canvas.drawPath(s.buildPath(), paint);
    }
    paintHighlighterGroups(canvas, groups);
  }

  /// Draws highlighter groups; each (color, opacity) group shares ONE
  /// translucent layer so overlapping strokes of the same color never
  /// self-darken, and the MULTIPLY blend keeps everything underneath
  /// (PDF text, ink, paper lines) readable.
  static void paintHighlighterGroups(
      Canvas canvas, Map<(int, double), List<Stroke>> groups) {
    groups.forEach((key, list) {
      final (color, opacity) = key;
      if (list.isEmpty) return;
      Rect? bounds;
      for (final s in list) {
        bounds = bounds == null ? s.bbox : bounds.expandToInclude(s.bbox);
      }
      if (bounds == null) return;
      final op = opacity.clamp(0.05, 1.0);
      canvas.saveLayer(
        bounds.inflate(8),
        Paint()
          // White modulates nothing — only the ALPHA scales the layer, and
          // MULTIPLY composites it: result = lerp(dst, color×dst, op).
          // At op = 1 the text under the highlight is still fully visible.
          ..color = const Color(0xFFFFFFFF).withValues(alpha: op)
          ..blendMode = BlendMode.multiply,
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
    // §2: live-stroke points are ANCHOR-relative — translate by the page's
    // pad offset so the preview lands on the grown paper correctly.
    final pad = StrokeEngine.I.padOffsetOf(StrokeEngine.I.livePageId);
    canvas.save();
    canvas.translate(pad.dx, pad.dy);
    final paint = Paint();
    if (s.style.kind == StrokeKind.highlighter) {
      // Live preview mirrors the COMMITTED look: the stroke's own opacity
      // with a MULTIPLY blend (previously a hardcoded 0.5 SRC_OVER that
      // never matched the setting being changed).
      paint
        ..color = s.style.flutterColor
            .withValues(alpha: s.style.opacity.clamp(0.05, 1.0))
        ..blendMode = BlendMode.multiply;
    } else {
      paint.color = s.style.flutterColor;
    }
    // live=true: no end taper while the stroke is still growing.
    canvas.drawPath(s.buildPath(live: true), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LiveStrokePainter oldDelegate) => true;
}
