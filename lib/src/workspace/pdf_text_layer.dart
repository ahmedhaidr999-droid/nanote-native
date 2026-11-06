import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../controllers/settings_controller.dart';
import '../controllers/stroke_engine.dart';
import '../controllers/tool_controller.dart';
import '../models/stroke.dart';
import '../services/pdf_text_extractor.dart';

/// Background text extraction for the currently open PDF.
///
/// Extraction runs ONCE per document inside an isolate (the whole parse —
/// xref, fonts, content streams of every page) and the resulting word
/// boxes are cached in plain maps, so hit-testing, "select all" and page
/// switches are instant afterwards.
class PdfTextService extends ChangeNotifier {
  PdfTextService._();

  static final PdfTextService I = PdfTextService._();

  String? _path;
  Map<int, PdfTextPage>? _pages; // 1-based page number → text
  bool _loading = false;

  bool get isReady => _pages != null;
  bool get isLoading => _loading;
  String? get path => _path;

  /// Extracts the text of the PDF at [absPath] (no-op when already done).
  Future<void> load(String absPath) async {
    if (_path == absPath) {
      if (_pages != null || _loading) return;
    }
    _path = absPath;
    _pages = null;
    _loading = true;
    notifyListeners();
    try {
      final bytes = await _readFile(absPath);
      if (_path != absPath) return; // superseded
      final result = await Isolate.run(() => extractPdfTextPages(bytes));
      if (_path != absPath) return;
      _pages = result;
    } catch (_) {
      if (_path == absPath) _pages = {};
    } finally {
      if (_path == absPath) _loading = false;
      notifyListeners();
    }
  }

  static Future<Uint8List> _readFile(String path) => File(path).readAsBytes();

  /// Drops the cache (document closed).
  void clear() {
    _path = null;
    _pages = null;
    _loading = false;
    notifyListeners();
  }

  PdfTextPage? page(int pageNumber) => _pages?[pageNumber];
}

// ---------------------------------------------------------------------------
// Selection controller
// ---------------------------------------------------------------------------

/// Which boundary of the selection a drag is moving.
enum PdfSelHandle { none, start, end }

/// State of the PDF text selection: the owning page, the selected word
/// range and the view→page scale. Everything is stored in PAGE-LOCAL doc
/// units (what the engine's strokes use), so the selection survives
/// zoom/pan untouched.
class PdfTextSelectionController extends ChangeNotifier {
  int? pageId;
  int pageNumber = 0;

  /// View-points → page-units scale (page doc width / pdfx page width).
  double scale = 1.0;

  /// Normalization against pdfx's reported page size (CropBox vs MediaBox
  /// edge cases): pdfxWidth / extractedViewWidth.
  double _normX = 1.0;
  double _normY = 1.0;

  int anchor = -1;
  int focus = -1;
  bool menuVisible = true;

  bool get hasSelection => pageId != null && anchor >= 0 && focus >= 0;

  PdfTextPage? get _page => PdfTextService.I.page(pageNumber);

  void begin({
    required int pageId,
    required int pageNumber,
    required double scale,
    required int wordIndex,
    double? pdfxW,
    double? pdfxH,
  }) {
    this.pageId = pageId;
    this.pageNumber = pageNumber;
    this.scale = scale > 0.01 ? scale : 1.0;
    _updateNorm(pdfxW, pdfxH);
    anchor = wordIndex;
    focus = wordIndex;
    menuVisible = true;
    notifyListeners();
  }

  void updateScale(double scale, {double? pdfxW, double? pdfxH}) {
    this.scale = scale > 0.01 ? scale : this.scale;
    _updateNorm(pdfxW, pdfxH);
    notifyListeners();
  }

  void _updateNorm(double? pdfxW, double? pdfxH) {
    final p = _page;
    if (p == null || pdfxW == null || pdfxH == null) {
      _normX = 1.0;
      _normY = 1.0;
      return;
    }
    _normX = (pdfxW > 0.5 && p.viewW > 0.5) ? pdfxW / p.viewW : 1.0;
    _normY = (pdfxH > 0.5 && p.viewH > 0.5) ? pdfxH / p.viewH : 1.0;
  }

  /// Extends the selection to [wordIndex] (the opposite boundary stays).
  void extendTo(int wordIndex) {
    if (!hasSelection) return;
    if (wordIndex < 0) return;
    focus = wordIndex;
    notifyListeners();
  }

  /// Begins a handle drag: the boundary OPPOSITE [leftSide] is pinned as
  /// the anchor; subsequent [dragFocusTo] calls move the dragged side.
  void beginHandleDrag({required bool leftSide}) {
    final r = range;
    if (r == null) return;
    anchor = leftSide ? r.$2 : r.$1;
    focus = leftSide ? r.$1 : r.$2;
    notifyListeners();
  }

  /// Moves the focus boundary to [wordIndex] (handle/long-press drags).
  void dragFocusTo(int wordIndex) {
    if (!hasSelection || wordIndex < 0) return;
    if (focus == wordIndex) return;
    focus = wordIndex;
    notifyListeners();
  }

  void selectAll() {
    final p = _page;
    if (p == null || p.words.isEmpty) return;
    anchor = 0;
    focus = p.words.length - 1;
    menuVisible = true;
    notifyListeners();
  }

  void toggleMenu() {
    if (!hasSelection) return;
    menuVisible = !menuVisible;
    notifyListeners();
  }

  /// Hides the action bar but KEEPS the handles (the "Select text"
  /// action — tap inside the selection to bring the bar back).
  void hideMenu() {
    if (!hasSelection || !menuVisible) return;
    menuVisible = false;
    notifyListeners();
  }

  void clear({bool notify = true}) {
    if (!hasSelection && !menuVisible) return;
    pageId = null;
    anchor = -1;
    focus = -1;
    menuVisible = true;
    if (notify) notifyListeners();
  }

  // ------------------------------------------------------------ geometry

  /// Selected word range (inclusive, normalized).
  (int, int)? get range {
    if (!hasSelection) return null;
    final a = anchor < focus ? anchor : focus;
    final b = anchor < focus ? focus : anchor;
    return (a, b);
  }

  Rect wordRectPage(int i) {
    final p = _page;
    if (p == null || i < 0 || i >= p.words.length) return Rect.zero;
    final w = p.words[i];
    return Rect.fromLTWH(
      w.x * _normX * scale,
      w.y * _normY * scale,
      w.w * _normX * scale,
      w.h * _normY * scale,
    );
  }

  /// Selection rectangles per line (page units) — for painting.
  List<Rect> selectionRectsPage() {
    final r = range;
    final p = _page;
    if (r == null || p == null) return const [];
    final out = <Rect>[];
    for (final line in p.lines) {
      if (line.end < r.$1 || line.start > r.$2) continue;
      final a = wordRectPage(line.start > r.$1 ? line.start : r.$1);
      final b = wordRectPage(line.end < r.$2 ? line.end : r.$2);
      var top = a.top;
      var bottom = a.bottom;
      if (b.top < top) top = b.top;
      if (b.bottom > bottom) bottom = b.bottom;
      out.add(Rect.fromLTRB(
        a.left < b.left ? a.left : b.left,
        top,
        a.right > b.right ? a.right : b.right,
        bottom,
      ));
    }
    return out;
  }

  /// The selection's overall bbox (page units).
  Rect? selectionBBoxPage() {
    final rects = selectionRectsPage();
    if (rects.isEmpty) return null;
    var b = rects.first;
    for (final r in rects) {
      b = b.expandToInclude(r);
    }
    return b;
  }

  /// Handle positions (page units): start = leading edge of the first
  /// rect, end = trailing edge of the last.
  (Offset, Offset)? handlePositionsPage() {
    final rects = selectionRectsPage();
    if (rects.isEmpty) return null;
    final first = rects.first;
    final last = rects.last;
    return (
      Offset(first.left, first.center.dy),
      Offset(last.right, last.center.dy),
    );
  }

  /// Hit-tests a PDF VIEW point (points) against the words; returns the
  /// nearest word index or null when nothing is near.
  int? hitWord(Offset viewPoint) {
    final p = _page;
    if (p == null || p.words.isEmpty) return null;
    final vx = viewPoint.dx / (_normX > 0 ? _normX : 1);
    final vy = viewPoint.dy / (_normY > 0 ? _normY : 1);
    return hitWordInPage(p, Offset(vx, vy));
  }

  /// Raw hit-test against a page's word boxes (VIEW points, no
  /// normalization) — shared by the router's initial long-press pick.
  static int? hitWordInPage(PdfTextPage p, Offset viewPoint) {
    if (p.words.isEmpty) return null;
    final vx = viewPoint.dx;
    final vy = viewPoint.dy;
    var best = -1;
    var bestDist = double.infinity;
    for (var i = 0; i < p.words.length; i++) {
      final w = p.words[i];
      final cx = vx < w.x
          ? w.x
          : (vx > w.x + w.w ? w.x + w.w : vx);
      final cy = vy < w.y
          ? w.y
          : (vy > w.y + w.h ? w.y + w.h : vy);
      final dx = vx - cx;
      final dy = vy - cy;
      final d = dx * dx + dy * dy;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    if (best < 0) return null;
    // Tolerance: accept when within ~1.1 word heights of the word box.
    final w = p.words[best];
    final tol = (w.h > 0 ? w.h : 10) * 1.1;
    return bestDist <= tol * tol ? best : null;
  }

  /// Selected text in LOGICAL reading order (RTL lines reversed).
  String selectedText() {
    final r = range;
    final p = _page;
    if (r == null || p == null) return '';
    final sb = StringBuffer();
    for (final line in p.lines) {
      if (line.end < r.$1 || line.start > r.$2) continue;
      final a = line.start > r.$1 ? line.start : r.$1;
      final b = line.end < r.$2 ? line.end : r.$2;
      final words = [
        for (var i = a; i <= b; i++) p.words[i].text,
      ];
      if (line.rtl) {
        for (var i = 0, j = words.length - 1; i < j; i++, j--) {
          final t = words[i];
          words[i] = words[j];
          words[j] = t;
        }
      }
      if (sb.isNotEmpty) sb.write('\n');
      sb.write(words.join(' '));
    }
    return sb.toString();
  }

  // ------------------------------------------------------------ annotations

  /// Builds highlighter strokes covering the selected lines (page units,
  /// current highlighter color/size/opacity — new strokes only, existing
  /// annotations are never touched).
  List<Stroke> buildHighlightStrokes() {
    final r = range;
    final p = _page;
    if (r == null || p == null) return const [];
    final tools = ToolController.I;
    final pen = tools.pen(StrokeKind.highlighter);
    // The highlighter's OWN defaults (never the current tool's) with the
    // live opacity setting — exactly what drawing with the highlighter
    // would commit.
    final op = SettingsController.I.settings.highlighterOpacity;
    final style = StrokeStyle.forKind(StrokeKind.highlighter, pen.color)
        .copyWith(size: pen.size, opacity: op < 0.1 ? 0.1 : op);
    final out = <Stroke>[];
    for (final line in p.lines) {
      if (line.end < r.$1 || line.start > r.$2) continue;
      final a = wordRectPage(line.start > r.$1 ? line.start : r.$1);
      final b = wordRectPage(line.end < r.$2 ? line.end : r.$2);
      var top = a.top;
      var bottom = a.bottom;
      if (b.top < top) top = b.top;
      if (b.bottom > bottom) bottom = b.bottom;
      final rect = Rect.fromLTRB(
        a.left < b.left ? a.left : b.left,
        top,
        a.right > b.right ? a.right : b.right,
        bottom,
      );
      if (rect.width < 1) continue;
      final h = rect.height.clamp(6.0, 48.0);
      final cy = rect.center.dy;
      final stroke = Stroke(
        id: StrokeIdGen.next(),
        style: style.copyWith(size: h),
        pts: [
          rect.left, cy, 0.5,
          rect.left + rect.width * 0.5, cy, 0.5,
          rect.right, cy, 0.5,
        ],
        z: StrokeEngine.I.pageInk(pageId ?? -1).nextZ(),
      );
      out.add(stroke);
    }
    return out;
  }

  /// Builds underline strokes under the selected lines' baselines.
  List<Stroke> buildUnderlineStrokes() {
    final r = range;
    final p = _page;
    if (r == null || p == null || pageId == null) return const [];
    final tools = ToolController.I;
    final color = tools.pen(StrokeKind.fineliner).color;
    final style = StrokeStyle.forKind(StrokeKind.fineliner, color);
    final out = <Stroke>[];
    for (final line in p.lines) {
      if (line.end < r.$1 || line.start > r.$2) continue;
      final a = wordRectPage(line.start > r.$1 ? line.start : r.$1);
      final b = wordRectPage(line.end < r.$2 ? line.end : r.$2);
      // Baseline: line bottom lifted by ~12% of the line height (just
      // under the text, above the descenders).
      final h = a.height > 0 ? a.height : b.height;
      final y = (a.bottom < b.bottom ? a.bottom : b.bottom) - h * 0.16;
      final left = a.left < b.left ? a.left : b.left;
      final right = a.right > b.right ? a.right : b.right;
      if (right - left < 1) continue;
      final stroke = Stroke(
        id: StrokeIdGen.next(),
        style: style.copyWith(size: (h * 0.06).clamp(1.0, 3.0)),
        pts: [
          left, y, 0.5,
          left + (right - left) * 0.5, y, 0.5,
          right, y, 0.5,
        ],
        z: StrokeEngine.I.pageInk(pageId!).nextZ(),
      );
      out.add(stroke);
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// Overlay painter (page space)
// ---------------------------------------------------------------------------

/// Paints the selection rectangles + start/end handles in PAGE-LOCAL
/// coordinates (placed inside the page's Positioned stack by the
/// workspace, exactly like the ink selection overlay).
class PdfSelectionPainter extends CustomPainter {
  PdfSelectionPainter({
    required this.sel,
    required this.primary,
    required this.surface,
  }) : super(repaint: sel);

  final PdfTextSelectionController sel;
  final Color primary;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final rects = sel.selectionRectsPage();
    if (rects.isEmpty) return;
    final fill = Paint()..color = primary.withValues(alpha: 0.26);
    for (final r in rects) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.inflate(0.5), const Radius.circular(2)),
        fill,
      );
    }
    // Handles: filled circles with a primary ring (matches the ink
    // selection handle style — radius 8 page units).
    final handles = sel.handlePositionsPage();
    if (handles == null) return;
    final fillP = Paint()..color = surface;
    final ring = Paint()
      ..color = primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final p in [handles.$1, handles.$2]) {
      canvas.drawCircle(p, 8, fillP);
      canvas.drawCircle(p, 8, ring);
    }
  }

  @override
  bool shouldRepaint(covariant PdfSelectionPainter oldDelegate) => true;
}
