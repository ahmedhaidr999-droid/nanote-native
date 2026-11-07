import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../controllers/stroke_engine.dart';
import '../i18n/strings.dart';
import '../models/page_elements.dart';
import '../models/paper.dart';
import '../models/stroke.dart';
import 'ink_painter.dart';
import 'paper_painter.dart';
import 'shape_path.dart';
import 'sticker_art.dart';

/// Hook that resolves an ImageEl's RELATIVE [ImageEl.src] to an
/// already-decoded image.
///
/// WHY A HOOK: the engine stores only relative paths and FileStore resolution
/// is async, so a painter cannot resolve them synchronously itself. The
/// workspace installs the hook once, e.g. in initState:
///
/// ```dart
/// ElementsPainter.resolveImage = (rel) => AppImageCache.peekSync(rel);
/// ```
///
/// where `AppImageCache.peekSync(String relPath)` (Agent E) resolves the
/// relative path via a pre-resolved base directory and returns the cached
/// decoded image or null. When the hook is null, or returns null (image not
/// decoded yet / missing file), the painter draws a gray rounded placeholder
/// with a broken-image glyph. The workspace should also prewarm visible
/// images (AppImageCache.loadByRel) so they appear once decoded.
class ElementsPainter extends CustomPainter {
  static ui.Image? Function(String relPath)? resolveImage;

  ElementsPainter({required this.ink, this.replayAt}) : super(repaint: ink);

  final PageInk ink;

  /// Audio-sync replay cursor (ms). NOTE: elements are ALWAYS visible during
  /// replay — only strokes carry audio timestamps — so this field is accepted
  /// for API symmetry but intentionally ignored when painting elements.
  final int? replayAt;

  @override
  void paint(Canvas canvas, Size size) {
    paintElements(canvas, ink.elements, replayAt: replayAt);
  }

  /// Paints a whole element list (used by this painter, export + thumbnails).
  static void paintElements(Canvas canvas, List<PageElement> elements,
      {int? replayAt}) {
    for (final el in elements) {
      paintElement(canvas, el);
    }
  }

  /// Paints ONE element in page space.
  static void paintElement(Canvas canvas, PageElement el) {
    if (el is TextEl) {
      _paintText(canvas, el);
    } else if (el is ShapeEl) {
      _paintShape(canvas, el);
    } else if (el is ImageEl) {
      _paintImage(canvas, el);
    }
  }

  // ------------------------------------------------------------------- text

  static void _paintText(Canvas canvas, TextEl el) {
    if (el.text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: el.text,
        style: TextStyle(
          fontFamily: el.font.fontFamily,
          fontSize: el.size,
          color: Color(el.color),
          fontWeight: el.bold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: el.italic ? FontStyle.italic : FontStyle.normal,
          decoration:
              el.underline ? TextDecoration.underline : TextDecoration.none,
          decorationColor: Color(el.color),
        ),
      ),
      textAlign: el.textAlign,
      textDirection: S.textDirection,
    );
    tp.layout(maxWidth: math.max(1.0, el.w));
    tp.paint(canvas, Offset(el.x, el.y));
    // BUG FIX (port): dispose the TextPainter — every call lays out a fresh
    // native ui.Paragraph; painters run per frame (and per element), so
    // never disposing leaked paragraphs until GC finalizers caught up.
    tp.dispose();
  }

  // ------------------------------------------------------------------ shape

  static void _paintShape(Canvas canvas, ShapeEl el) {
    final path = buildShapePath(el);
    canvas.save();
    // Polyline-like shapes carry their geometry (and rotation) in points;
    // bbox shapes are rotated here around the bbox center.
    if (el.pts == null) {
      final c = el.bbox().center;
      canvas.translate(c.dx, c.dy);
      canvas.rotate(el.rotation);
      canvas.translate(-c.dx, -c.dy);
    }
    final fill = el.fillColor;
    if (fill != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color =
              Color(fill).withValues(alpha: el.fillOpacity.clamp(0.0, 1.0)),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Color(el.strokeColor)
        ..style = PaintingStyle.stroke
        ..strokeWidth = el.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  // ------------------------------------------------------------------ image

  static const Color _stickerBody = Color(0xFF1E6FF2);
  static const Color _stickerAccent = Color(0xFFFFFFFF);
  static const Color _imgPlaceholderBg = Color(0xFFE7EBF2);
  static const Color _imgPlaceholderFg = Color(0xFF94A3B8);
  static const Color _stickerBoxTint = Color(0x141E6FF2);

  static void _paintImage(Canvas canvas, ImageEl el) {
    canvas.save();
    final c = el.center;
    canvas.translate(c.dx, c.dy);
    canvas.rotate(el.rotation);
    canvas.scale(el.flipH ? -1.0 : 1.0, el.flipV ? -1.0 : 1.0);
    canvas.translate(-c.dx, -c.dy);

    final dst = Rect.fromLTWH(el.x, el.y, el.w, el.h);

    if (el.builtinId != null) {
      // Built-in vector sticker: subtle tinted box + two-tone vector art
      // (first path = body, the rest = accents).
      canvas.drawRRect(
        RRect.fromRectAndRadius(dst, const Radius.circular(8)),
        Paint()..color = _stickerBoxTint,
      );
      final art = const StickerArt().paths(el.builtinId!, dst.size);
      for (var i = 0; i < art.length; i++) {
        canvas.drawPath(
          art[i],
          Paint()..color = i == 0 ? _stickerBody : _stickerAccent,
        );
      }
    } else if (el.src != null) {
      final img = resolveImage?.call(el.src!);
      if (img != null) {
        // Source sub-rect: the normalized crop window (0..1), else the
        // whole image.
        final c = el.crop;
        Rect src;
        if (c != null && c.length == 4) {
          src = Rect.fromLTRB(
            c[0].clamp(0.0, 1.0) * img.width,
            c[1].clamp(0.0, 1.0) * img.height,
            c[2].clamp(0.0, 1.0) * img.width,
            c[3].clamp(0.0, 1.0) * img.height,
          );
        } else {
          src = Rect.fromLTWH(
              0, 0, img.width.toDouble(), img.height.toDouble());
        }
        canvas.drawImageRect(
          img,
          src,
          dst,
          Paint()..filterQuality = FilterQuality.medium,
        );
      } else {
        _paintMissingImage(canvas, dst);
      }
    } else {
      _paintMissingImage(canvas, dst);
    }
    canvas.restore();
  }

  static void _paintMissingImage(Canvas canvas, Rect dst) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(dst, const Radius.circular(8)),
      Paint()..color = _imgPlaceholderBg,
    );
    final c = dst.center;
    final s = math.min(dst.width, dst.height).clamp(12.0, 64.0);
    final fg = Paint()..color = _imgPlaceholderFg;
    // Broken-image glyph: mountain + sun.
    final mountain = Path()
      ..moveTo(c.dx - s * 0.45, c.dy + s * 0.28)
      ..lineTo(c.dx - s * 0.15, c.dy - s * 0.12)
      ..lineTo(c.dx + s * 0.05, c.dy + s * 0.08)
      ..lineTo(c.dx + s * 0.18, c.dy - s * 0.06)
      ..lineTo(c.dx + s * 0.45, c.dy + s * 0.28)
      ..close();
    canvas.drawPath(mountain, fg);
    canvas.drawCircle(Offset(c.dx - s * 0.22, c.dy - s * 0.20), s * 0.09, fg);
  }

  @override
  bool shouldRepaint(covariant ElementsPainter oldDelegate) {
    return oldDelegate.ink != ink || oldDelegate.replayAt != replayAt;
  }
}

/// Composes paper + ink + elements in interleaved z order — used by the page
/// widget, the filmstrip thumbnails and the export service.
///
/// * Paper is delegated to [PaperPainter].
/// * Strokes and elements merge in z order (both engine lists are z-sorted;
///   ties prefer the stroke).
/// * Highlighter strokes render LAST, grouped per (color, opacity) inside
///   one MULTIPLY saveLayer each (never self-darkens, keeps the PDF text
///   readable) — see [InkPainter].
/// * [selectedStrokeIds] / [selectedElementIds] (when non-null) add a
///   translucent primary tint over the selected items.
/// * [scaleForThumb] scales everything down for small thumbnail canvases
///   (the CustomPaint's size should be `pageSize * scaleForThumb`).
/// * [paintPaper] false skips the opaque paper fill (PDF background tiles
///   show through; template lines still render).
class PageContentPainter extends CustomPainter {
  PageContentPainter({
    required this.template,
    required this.paperColor,
    required this.pageSize,
    required this.ink,
    this.replayAt,
    this.scaleForThumb = 1.0,
    this.selectedStrokeIds,
    this.selectedElementIds,
    this.paintPaper = true,
  }) : super(repaint: ink);

  final TemplateId template;
  final Color paperColor;
  final Size pageSize;
  final PageInk ink;
  final int? replayAt;
  final double scaleForThumb;
  final Set<int>? selectedStrokeIds;
  final Set<String>? selectedElementIds;
  final bool paintPaper;

  static const Color _selectionTint = Color(0x331E6FF2);

  @override
  void paint(Canvas canvas, Size size) {
    if (scaleForThumb != 1.0) {
      canvas.save();
      canvas.scale(scaleForThumb, scaleForThumb);
    }

    // §6: the template grid is ANCHOR-aligned (never shifts while the
    // infinite paper grows); §2: ink + elements are anchor-relative too —
    // translate by the page's pad offset onto the grown paper widget.
    final pad = ink.padOffset;
    PaperPainter(
      template: template,
      paperColor: paperColor,
      size: pageSize,
      paintBackground: paintPaper,
      patternOrigin: pad,
    ).paint(canvas, pageSize);

    canvas.save();
    canvas.translate(pad.dx, pad.dy);

    // Interleaved z order (two-pointer merge of two z-sorted lists).
    final strokes = ink.strokes;
    final elements = ink.elements;
    final highlighters = <(int, double), List<Stroke>>{};
    final plain = Paint();
    var si = 0;
    var ei = 0;
    while (si < strokes.length || ei < elements.length) {
      final takeStroke = ei >= elements.length ||
          (si < strokes.length && strokes[si].z <= elements[ei].z);
      if (takeStroke) {
        final s = strokes[si++];
        if (InkPainter.hiddenByReplay(s, replayAt)) continue;
        if (s.style.kind == StrokeKind.highlighter) {
          highlighters
              .putIfAbsent((s.style.color, s.style.opacity), () => [])
              .add(s);
          continue;
        }
        plain.color = s.style.flutterColor;
        canvas.drawPath(s.buildPath(), plain);
      } else {
        ElementsPainter.paintElement(canvas, elements[ei++]);
      }
    }
    InkPainter.paintHighlighterGroups(canvas, highlighters);

    _paintSelectionTint(canvas);

    canvas.restore(); // pad offset (§2)

    if (scaleForThumb != 1.0) {
      canvas.restore();
    }
  }

  void _paintSelectionTint(Canvas canvas) {
    final selStrokes = selectedStrokeIds;
    final selElements = selectedElementIds;
    if (selStrokes == null && selElements == null) return;
    final tint = Paint()..color = _selectionTint;
    if (selStrokes != null) {
      for (final s in ink.strokes) {
        if (selStrokes.contains(s.id)) {
          canvas.drawPath(s.buildPath(), tint);
        }
      }
    }
    if (selElements != null) {
      for (final e in ink.elements) {
        if (selElements.contains(e.id)) {
          canvas.drawRect(e.bbox(), tint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant PageContentPainter oldDelegate) {
    return oldDelegate.ink != ink ||
        oldDelegate.replayAt != replayAt ||
        oldDelegate.template != template ||
        oldDelegate.paperColor != paperColor ||
        oldDelegate.pageSize != pageSize ||
        oldDelegate.scaleForThumb != scaleForThumb ||
        oldDelegate.paintPaper != paintPaper ||
        oldDelegate.selectedStrokeIds != selectedStrokeIds ||
        oldDelegate.selectedElementIds != selectedElementIds;
  }
}
