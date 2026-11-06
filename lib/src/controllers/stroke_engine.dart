import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/page_elements.dart';
import '../models/paper.dart';
import '../models/stroke.dart';
import '../persistence/library_repository.dart';
import '../persistence/stroke_repository.dart';

/// Lightweight mirror of a PageEntity for the editor.
class PageMeta {
  final int id; // STABLE ink slot
  int position;
  String title;
  bool bookmarked;
  int template;
  int pageSize;
  int paperColor;

  /// Transient per-page PDF size override (doc units). When the notebook has
  /// a PDF background, each page adopts the aspect of its PDF page so the
  /// render is NEVER distorted and ink lands exactly on the PDF content.
  /// Not persisted — re-applied from the PDF on open (see
  /// StrokeEngine.applyPdfPageSize).
  Size? pdfSize;

  /// §2 INFINITY PAPER growth (doc units, always ≥ 0, session state):
  ///  * [padX] / [padY] — how far the paper extends LEFT OF / ABOVE the
  ///    original origin. Page-local ink coordinates may be NEGATIVE down
  ///    to (-padX, -padY).
  ///  * [growW] / [growH] — how far the paper extends BEYOND the base
  ///    width/height (right/bottom).
  /// Derived from content on load, then grown monotonically while writing
  /// (the paper chases the pen) — see StrokeEngine._growForContent.
  double padX = 0;
  double padY = 0;
  double growW = 0;
  double growH = 0;

  PageMeta({
    required this.id,
    required this.position,
    required this.title,
    required this.bookmarked,
    required this.template,
    required this.pageSize,
    required this.paperColor,
  });

  PageSizeDef get sizeDef => pageSizeDef(pageSizeIdFrom(pageSize));

  /// §2 true for INFINITE pages (growth/pads are no-ops otherwise).
  bool get isInfinite => isInfinitySize(pageSize);

  /// The size used for layout: the PDF aspect when known, else the paper
  /// size — INFINITE pages add their growth pads (§2: four directions).
  Size get effectiveSize {
    final base = pdfSize ?? sizeDef.size;
    if (!isInfinite) return base;
    return Size(base.width + growW + padX, base.height + growH + padY);
  }

  /// §2 The FULL page rect offset of the original origin (anchor) relative
  /// to the grown paper's top-left. Painters translate page-local ink by
  /// this offset; the layout subtracts it from the rect origin.
  Offset get padOffset => Offset(padX, padY);

  factory PageMeta.from(PageEntity p) => PageMeta(
        id: p.id,
        position: p.position,
        title: p.title,
        bookmarked: p.bookmarked,
        template: p.template,
        pageSize: p.pageSize,
        paperColor: p.paperColor,
      );
}

/// Ink of one page. Notifies painters when THIS page's content changes, so
/// drawing repaints only the touched page.
class PageInk extends ChangeNotifier {
  final int pageId;

  /// Committed strokes (z-ordered against elements).
  final List<Stroke> strokes = [];

  /// Committed elements (z-ordered against strokes).
  final List<PageElement> elements = [];

  bool strokesLoaded = false;

  /// §2 mirror of PageMeta.padOffset (kept in sync by the engine) — the
  /// painters translate page-local (possibly negative) ink by this.
  Offset padOffset = Offset.zero;

  PageInk(this.pageId);

  void touch() => notifyListeners();

  void sortInk() {
    strokes.sort((a, b) => a.z.compareTo(b.z));
    elements.sort((a, b) => a.z.compareTo(b.z));
  }

  int nextZ() {
    var z = 0;
    for (final s in strokes) {
      if (s.z >= z) z = s.z + 1;
    }
    for (final e in elements) {
      if (e.z >= z) z = e.z + 1;
    }
    return z;
  }
}

/// Screen-space eraser cursor (shown ONLY during an active erase gesture).
class EraserCursor {
  const EraserCursor({required this.screenPos, required this.radius});

  final Offset screenPos;
  final double radius;
}

/// Live stroke notifier. Unlike ValueNotifier, notifies even when the same
/// Stroke instance is extended point by point.
class LiveStrokeNotifier extends ChangeNotifier {
  Stroke? _value;

  Stroke? get value => _value;

  set value(Stroke? s) {
    _value = s;
    notifyListeners();
  }

  void tick() => notifyListeners();
}

/// Selection handle ids (corner + top rotate handle).
enum SelHandle { none, topLeft, topRight, bottomLeft, bottomRight, rotate }

// ---------------------------------------------------------------------------
// Undo ops
// ---------------------------------------------------------------------------

sealed class InkOp {
  /// Pages this op touches (used to prune history when pages are deleted).
  Iterable<int> get pageIds;

  void undo(StrokeEngine e);

  void redo(StrokeEngine e);
}

class AddInkOp extends InkOp {
  final int pageId;
  final List<Stroke> strokes;

  AddInkOp(this.pageId, this.strokes);

  @override
  Iterable<int> get pageIds => [pageId];

  @override
  void undo(StrokeEngine e) {
    final ink = e.pageInk(pageId);
    ink.strokes.removeWhere((s) => strokes.any((x) => x.id == s.id));
    e.markDirty(pageId);
    ink.touch();
  }

  @override
  void redo(StrokeEngine e) {
    final ink = e.pageInk(pageId);
    ink.strokes.addAll(strokes.map((s) => s.deepCopy()));
    ink.sortInk();
    e.markDirty(pageId);
    ink.touch();
  }
}

class RemoveInkOp extends InkOp {
  final int pageId;
  final List<Stroke> strokes;

  RemoveInkOp(this.pageId, this.strokes);

  @override
  Iterable<int> get pageIds => [pageId];

  @override
  void undo(StrokeEngine e) {
    final ink = e.pageInk(pageId);
    ink.strokes.addAll(strokes.map((s) => s.deepCopy()));
    ink.sortInk();
    e.markDirty(pageId);
    ink.touch();
  }

  @override
  void redo(StrokeEngine e) {
    final ink = e.pageInk(pageId);
    ink.strokes.removeWhere((s) => strokes.any((x) => x.id == s.id));
    e.markDirty(pageId);
    ink.touch();
  }
}

class AddElementsOp extends InkOp {
  final int pageId;
  final List<PageElement> elements;

  AddElementsOp(this.pageId, this.elements);

  @override
  Iterable<int> get pageIds => [pageId];

  @override
  void undo(StrokeEngine e) {
    final ink = e.pageInk(pageId);
    ink.elements.removeWhere((x) => elements.any((y) => y.id == x.id));
    e.markDirty(pageId);
    ink.touch();
  }

  @override
  void redo(StrokeEngine e) {
    final ink = e.pageInk(pageId);
    ink.elements.addAll(elements.map((x) => x.deepCopy()));
    ink.sortInk();
    e.markDirty(pageId);
    ink.touch();
  }
}

class RemoveElementsOp extends InkOp {
  final int pageId;
  final List<PageElement> elements;

  RemoveElementsOp(this.pageId, this.elements);

  @override
  Iterable<int> get pageIds => [pageId];

  @override
  void undo(StrokeEngine e) {
    final ink = e.pageInk(pageId);
    ink.elements.addAll(elements.map((x) => x.deepCopy()));
    ink.sortInk();
    e.markDirty(pageId);
    ink.touch();
  }

  @override
  void redo(StrokeEngine e) {
    final ink = e.pageInk(pageId);
    ink.elements.removeWhere((x) => elements.any((y) => y.id == x.id));
    e.markDirty(pageId);
    ink.touch();
  }
}

/// One item snapshot pair (deep copies).
class TransformSnapshot {
  final Map<int, Stroke> strokesBefore = {};
  final Map<int, Stroke> strokesAfter = {};
  final Map<String, PageElement> elementsBefore = {};
  final Map<String, PageElement> elementsAfter = {};
}

/// Move / scale / rotate / any in-place mutation of strokes and/or elements.
class TransformOp extends InkOp {
  final int pageId;
  final TransformSnapshot snap;

  TransformOp(this.pageId, this.snap);

  @override
  Iterable<int> get pageIds => [pageId];

  void _apply(StrokeEngine e, Map<int, Stroke> strokes,
      Map<String, PageElement> elements) {
    final ink = e.pageInk(pageId);
    for (final s in ink.strokes.toList()) {
      final repl = strokes[s.id];
      if (repl != null) {
        ink.strokes[ink.strokes.indexOf(s)] = repl.deepCopy();
      }
    }
    for (final el in ink.elements.toList()) {
      final repl = elements[el.id];
      if (repl != null) {
        ink.elements[ink.elements.indexOf(el)] = repl.deepCopy();
      }
    }
    ink.sortInk();
    e.markDirty(pageId);
    ink.touch();
  }

  @override
  void undo(StrokeEngine e) => _apply(e, snap.strokesBefore, snap.elementsBefore);

  @override
  void redo(StrokeEngine e) => _apply(e, snap.strokesAfter, snap.elementsAfter);
}

/// Shape recognition: ink replaced by a shape element — revertible.
class ReplaceInkOp extends InkOp {
  final int pageId;
  final Stroke stroke;
  final ShapeEl shape;

  ReplaceInkOp(this.pageId, this.stroke, this.shape);

  @override
  Iterable<int> get pageIds => [pageId];

  @override
  void undo(StrokeEngine e) {
    final ink = e.pageInk(pageId);
    ink.elements.removeWhere((x) => x.id == shape.id);
    ink.strokes.add(stroke.deepCopy());
    ink.sortInk();
    e.markDirty(pageId);
    ink.touch();
  }

  @override
  void redo(StrokeEngine e) {
    final ink = e.pageInk(pageId);
    ink.strokes.removeWhere((s) => s.id == stroke.id);
    ink.elements.add(shape.deepCopy());
    ink.sortInk();
    e.markDirty(pageId);
    ink.touch();
  }
}

/// Groups several ops into ONE undo step (eraser gesture, paste…).
class CompositeOp extends InkOp {
  final List<InkOp> ops;

  CompositeOp(this.ops);

  @override
  Iterable<int> get pageIds => ops.expand((o) => o.pageIds);

  @override
  void undo(StrokeEngine e) {
    for (final o in ops.reversed) {
      o.undo(e);
    }
  }

  @override
  void redo(StrokeEngine e) {
    for (final o in ops) {
      o.redo(e);
    }
  }
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

class StrokeEngine extends ChangeNotifier {
  StrokeEngine._();

  static final StrokeEngine I = StrokeEngine._();

  final LibraryRepository _lib = LibraryRepository.I;
  final StrokeRepository _repo = StrokeRepository.I;

  NotebookEntity? notebook;
  final List<PageMeta> pages = [];

  final Map<int, PageInk> _inks = {};
  final Set<int> _dirtyPages = {};

  // Cheap notifiers (never repaint the whole document).
  final LiveStrokeNotifier liveStroke = LiveStrokeNotifier();
  final ValueNotifier<EraserCursor?> eraserCursor = ValueNotifier<EraserCursor?>(null);
  final ValueNotifier<List<Offset>> lassoPreview = ValueNotifier<List<Offset>>(const []);
  final ChangeNotifier historyChanged = ChangeNotifier();
  final ChangeNotifier selectionChanged = ChangeNotifier();
  final ChangeNotifier pagesChanged = ChangeNotifier();

  // History.
  final List<InkOp> _undoStack = [];
  final List<InkOp> _redoStack = [];
  static const int maxHistory = 200;

  // Recording clock (ms since recording start) — installed by the workspace.
  int Function()? recordingClock;

  bool get isOpen => notebook != null;

  // ------------------------------------------------------------------ pages

  Future<void> openNotebook(int notebookId) async {
    await flush();
    final n = await _lib.notebook(notebookId);
    if (n == null) return;
    notebook = n;
    await _lib.touchNotebook(notebookId, opened: true);
    pages.clear();
    _inks.clear();
    _dirtyPages.clear();
    _undoStack.clear();
    _redoStack.clear();
    _clearSelection();
    final entities = await _lib.pagesOf(notebookId);
    for (final p in entities) {
      pages.add(PageMeta.from(p));
    }
    _sortPages();
    // Elements load eagerly (text index + thumbnails); strokes stay lazy.
    for (final meta in pages) {
      final ink = pageInk(meta.id);
      ink.elements.addAll(await _repo.loadElements(meta.id));
    }
    pagesChanged.notifyListeners();
  }

  Future<void> close() async {
    await flush();
    notebook = null;
    pages.clear();
    _inks.clear();
    _dirtyPages.clear();
    _undoStack.clear();
    _redoStack.clear();
    _clearSelection();
    liveStroke.value = null;
    lassoPreview.value = const [];
    eraserCursor.value = null;
    pagesChanged.notifyListeners();
  }

  void _sortPages() {
    pages.sort((a, b) => a.position.compareTo(b.position));
    for (var i = 0; i < pages.length; i++) {
      pages[i].position = i;
    }
  }

  /// Applies a per-page PDF size override (see [PageMeta.pdfSize]) and
  /// notifies layout listeners. Call for each page as PDF sizes resolve.
  void applyPdfPageSize(int pageId, Size size) {
    for (final p in pages) {
      if (p.id == pageId) {
        final cur = p.pdfSize;
        if (cur != null &&
            (cur.width - size.width).abs() < 0.5 &&
            (cur.height - size.height).abs() < 0.5) {
          return; // already correct
        }
        p.pdfSize = size;
        pagesChanged.notifyListeners();
        return;
      }
    }
  }

  /// PDF notebooks own ONE page per PDF page. Notebooks created by older
  /// app versions (or an interrupted import) can hold FEWER pages than the
  /// PDF — the editor then shows only page 1 and dark, empty space below
  /// ("only the first page exists" bug). This SELF-HEALS the page list on
  /// open: every missing page is appended at the end. Extra notebook pages
  /// beyond the PDF are kept (the user may have added them).
  Future<void> syncPagesToPdfCount(int pdfPageCount) async {
    final n = notebook;
    if (n == null || n.pdfPath == null) return;
    if (pdfPageCount <= 0) return;
    final missing = pdfPageCount - pages.length;
    if (missing <= 0) return;
    for (var i = 0; i < missing; i++) {
      // addPage(null) appends at the end and notifies pagesChanged.
      await addPage();
    }
  }

  PageInk pageInk(int pageId) =>
      _inks.putIfAbsent(pageId, () => PageInk(pageId));

  PageInk? pageInkOrNull(int pageId) => _inks[pageId];

  // ------------------------------------------------- §2/§3 infinity paper

  /// True when THIS notebook is an infinite-paper notebook (its default
  /// page size is the infinite one — every page of the notebook shares it).
  bool get isInfiniteDoc => notebook != null && isInfinitySize(notebook!.pageSize);

  /// §2 Page-local pad offset of a page (painters use it to translate
  /// anchor-relative ink onto the grown paper widget).
  Offset padOffsetOf(int pageId) {
    final meta = metaOf(pageId);
    return meta?.padOffset ?? Offset.zero;
  }

  /// §3 THE CHASE: grows the page so the paper keeps [kInfiniteChase] doc
  /// units of room beyond [newBounds] (page-local, possibly negative), in
  /// steps of [kInfiniteStep]. Runs on every committed stroke/element —
  /// ink flows freely WHILE drawing; the paper expands on lift/save.
  /// Normal pages never grow (identical layout to v2.2.0).
  void _growForContent(int pageId, Rect newBounds) {
    final meta = metaOf(pageId);
    if (meta == null || !meta.isInfinite) return;
    var changed = false;

    // Top edge: paper top (-padY) must stay ≥ chase above content top.
    final needPadY = kInfiniteChase - newBounds.top;
    if (needPadY > meta.padY) {
      final target = math.max(
        meta.padY + kInfiniteStep,
        (needPadY / kInfiniteStep).ceil() * kInfiniteStep,
      );
      meta.padY = target;
      changed = true;
    }
    // Left edge.
    final needPadX = kInfiniteChase - newBounds.left;
    if (needPadX > meta.padX) {
      final target = math.max(
        meta.padX + kInfiniteStep,
        (needPadX / kInfiniteStep).ceil() * kInfiniteStep,
      );
      meta.padX = target;
      changed = true;
    }
    // Right edge: paper right (baseW + growW) − chase ≥ content right.
    final baseW = meta.sizeDef.size.width;
    final needGrowW = newBounds.right + kInfiniteChase - baseW;
    if (needGrowW > meta.growW) {
      final target = math.max(
        meta.growW + kInfiniteStep,
        (needGrowW / kInfiniteStep).ceil() * kInfiniteStep,
      );
      meta.growW = target;
      changed = true;
    }
    // Bottom edge.
    final baseH = meta.sizeDef.size.height;
    final needGrowH = newBounds.bottom + kInfiniteChase - baseH;
    if (needGrowH > meta.growH) {
      final target = math.max(
        meta.growH + kInfiniteStep,
        (needGrowH / kInfiniteStep).ceil() * kInfiniteStep,
      );
      meta.growH = target;
      changed = true;
    }

    if (changed) {
      final ink = pageInk(pageId);
      ink.padOffset = meta.padOffset;
      ink.touch(); // painters re-read the pad immediately
      pagesChanged.notifyListeners(); // relayout with the new page rect
    }
  }

  /// §2 Re-derives the pads of an infinite page from its CURRENT content
  /// (used on load — same content → same geometry).
  void _recomputePads(int pageId) {
    final meta = metaOf(pageId);
    if (meta == null || !meta.isInfinite) return;
    Rect? bounds;
    final ink = pageInkOrNull(pageId);
    if (ink != null) {
      for (final s in ink.strokes) {
        bounds = bounds == null ? s.bbox : bounds.expandToInclude(s.bbox);
      }
      for (final e in ink.elements) {
        bounds = bounds == null ? e.bbox() : bounds.expandToInclude(e.bbox());
      }
    }
    meta.padX = 0;
    meta.padY = 0;
    meta.growW = 0;
    meta.growH = 0;
    if (bounds != null) _growForContent(pageId, bounds);
    pageInk(pageId).padOffset = meta.padOffset;
  }

  /// Wipes ALL ink + elements of a page as ONE undoable step ("Clear
  /// page" — the UI confirms with a two-stage button).
  Future<void> clearPage(int pageId) async {
    final ink = pageInk(pageId);
    if (ink.strokes.isEmpty && ink.elements.isEmpty) return;
    final strokes = [for (final s in ink.strokes) s.deepCopy()];
    final elements = [for (final e in ink.elements) e.deepCopy()];
    ink.strokes.clear();
    ink.elements.clear();
    markDirty(pageId);
    ink.touch();
    _clearSelection();
    _pushOp(CompositeOp([
      RemoveInkOp(pageId, strokes),
      RemoveElementsOp(pageId, elements),
    ]));
    await flush();
  }

  /// Lazily loads strokes for a page (called when it becomes visible).
  Future<void> ensureLoaded(int pageId) async {
    final ink = pageInk(pageId);
    if (ink.strokesLoaded) return;
    ink.strokes.addAll(await _repo.loadStrokes(pageId));
    ink.strokesLoaded = true;
    // §3 Infinite pages: re-derive the growth pads from the loaded ink so
    // reopening lands on the same geometry the content needs.
    _recomputePads(pageId);
    ink.touch();
  }

  Future<void> ensureAllLoaded() async {
    for (final p in pages) {
      await ensureLoaded(p.id);
    }
  }

  void markDirty(int pageId) {
    _dirtyPages.add(pageId);
  }

  Future<void> flush() async {
    final n = notebook;
    if (n == null) return;
    if (_dirtyPages.isEmpty) return;
    final dirty = List<int>.of(_dirtyPages);
    _dirtyPages.clear();
    for (final pageId in dirty) {
      final ink = pageInk(pageId);
      await _repo.savePage(pageId, ink.strokes, ink.elements);
    }
    // Rebuild the searchable text index.
    final buf = StringBuffer();
    for (final p in pages) {
      final ink = _inks[p.id];
      if (ink == null) continue;
      for (final el in ink.elements) {
        if (el is TextEl && el.text.trim().isNotEmpty) {
          buf.write(el.text);
          buf.write(' ');
        }
      }
    }
    n.textIndex = buf.toString();
    n.modifiedAt = DateTime.now();
    await _lib.updateNotebook(n);
  }

  // ------------------------------------------------------------------ draw

  void beginStroke(int pageId, StrokeStyle style) {
    final stroke = Stroke(
      id: StrokeIdGen.next(),
      style: style,
      pts: <double>[],
      z: pageInk(pageId).nextZ(),
    );
    if (recordingClock != null) {
      stroke.tStart = recordingClock!();
    }
    liveStroke.value = stroke;
    _livePage = pageId;
  }

  int _livePage = -1;

  /// The page the live stroke is being drawn on (-1 when idle) — painters
  /// use it to resolve the page's pad offset (§2).
  int get livePageId => _livePage;

  void extendStroke(Offset pagePoint, double pressure, {bool realPressure = false}) {
    final s = liveStroke.value;
    if (s == null) return;
    if (s.isEmpty) {
      s.append(pagePoint, pressure, realPressure: realPressure);
      // First point: also seed a tiny bit of history for nicer outlines.
      s.append(pagePoint, pressure, realPressure: realPressure);
    } else {
      s.append(pagePoint, pressure, realPressure: realPressure);
    }
    liveStroke.tick(); // re-notify listeners on every point
  }

  /// Commits the live stroke as ONE AddInkOp. Returns the stroke (or null if
  /// it was a dot/empty).
  Future<void> endStroke() async {
    final s = liveStroke.value;
    liveStroke.value = null;
    if (s == null || s.pointCount < 2) {
      _livePage = -1;
      return;
    }
    if (recordingClock != null) {
      s.tEnd = recordingClock!();
    }
    final pageId = _livePage;
    _livePage = -1;
    final ink = pageInk(pageId);
    ink.strokes.add(s);
    ink.sortInk();
    markDirty(pageId);
    ink.touch();
    _pushOp(AddInkOp(pageId, [s.deepCopy()]));
    // §3 the paper chases the pen (infinite pages only).
    _growForContent(pageId, s.bbox);
  }

  void cancelStroke() {
    liveStroke.value = null;
    _livePage = -1;
  }

  /// Commits PRE-BUILT strokes (e.g. PDF text highlight / underline
  /// annotations) as ONE undoable op — the exact same pipeline
  /// [endStroke] uses, so autosave, undo/redo and the infinite-paper
  /// growth behave identically.
  void commitStrokes(int pageId, List<Stroke> strokes) {
    if (pageId < 0 || strokes.isEmpty) return;
    final ink = pageInk(pageId);
    for (final s in strokes) {
      ink.strokes.add(s);
    }
    ink.sortInk();
    markDirty(pageId);
    ink.touch();
    _pushOp(AddInkOp(pageId, [for (final s in strokes) s.deepCopy()]));
    for (final s in strokes) {
      _growForContent(pageId, s.bbox);
    }
  }

  // ---------------------------------------------------------------- eraser

  final Set<int> _eraseGestureStrokes = {};
  final List<PageElement> _eraseGestureElements = [];
  int _erasePage = -1;

  void beginEraserGesture(int pageId) {
    _eraseGestureStrokes.clear();
    _eraseGestureElements.clear();
    _erasePage = pageId;
  }

  /// Stroke-eraser: deletes the WHOLE stroke when the point comes within
  /// radius + size/2 of any of its segments.
  void eraseStrokeAt(int pageId, Offset pagePoint, double radius) {
    final ink = pageInk(pageId);
    final hit = <Stroke>[];
    for (final s in ink.strokes) {
      if (s.distanceTo(pagePoint) <= radius + s.style.size / 2) {
        hit.add(s);
      }
    }
    if (hit.isEmpty) return;
    ink.strokes.removeWhere((s) => hit.contains(s));
    _eraseGestureStrokes.addAll(hit.map((s) => s.id));
    for (final h in hit) {
      _eraseRemovedStrokes.putIfAbsent(h.id, () => h.deepCopy());
    }
    markDirty(pageId);
    ink.touch();
  }

  final Map<int, Stroke> _eraseRemovedStrokes = {};

  /// Area-eraser: deletes strokes AND elements whose bbox intersects the
  /// circle.
  void eraseAreaAt(int pageId, Offset pagePoint, double radius) {
    final ink = pageInk(pageId);
    final circle = Rect.fromCircle(center: pagePoint, radius: radius);
    final hitStrokes = ink.strokes.where((s) => s.bbox.overlaps(circle)).toList();
    final hitElements =
        ink.elements.where((e) => e.bbox().overlaps(circle)).toList();
    if (hitStrokes.isEmpty && hitElements.isEmpty) return;
    ink.strokes.removeWhere((s) => hitStrokes.contains(s));
    ink.elements.removeWhere((e) => hitElements.contains(e));
    for (final h in hitStrokes) {
      _eraseGestureStrokes.add(h.id);
      _eraseRemovedStrokes.putIfAbsent(h.id, () => h.deepCopy());
    }
    for (final h in hitElements) {
      if (!_eraseGestureElements.any((e) => e.id == h.id)) {
        _eraseGestureElements.add(h.deepCopy());
      }
    }
    markDirty(pageId);
    ink.touch();
  }

  /// All hits of ONE erase gesture group into ONE undo op.
  void endEraserGesture() {
    final pageId = _erasePage;
    _erasePage = -1;
    final removedStrokes =
        _eraseRemovedStrokes.values.map((s) => s.deepCopy()).toList();
    final removedElements = List<PageElement>.of(_eraseGestureElements);
    _eraseGestureStrokes.clear();
    _eraseGestureElements.clear();
    _eraseRemovedStrokes.clear();
    if (removedStrokes.isEmpty && removedElements.isEmpty) return;
    final ops = <InkOp>[];
    if (removedStrokes.isNotEmpty) {
      ops.add(RemoveInkOp(pageId, removedStrokes));
    }
    if (removedElements.isNotEmpty) {
      ops.add(RemoveElementsOp(pageId, removedElements));
    }
    _pushOp(ops.length == 1 ? ops.first : CompositeOp(ops));
  }

  // ---------------------------------------------------------------- history

  bool get canUndo => _undoStack.isNotEmpty;

  bool get canRedo => _redoStack.isNotEmpty;

  void _pushOp(InkOp op) {
    _undoStack.add(op);
    if (_undoStack.length > maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    historyChanged.notifyListeners();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final op = _undoStack.removeLast();
    op.undo(this);
    _redoStack.add(op);
    historyChanged.notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final op = _redoStack.removeLast();
    op.redo(this);
    _undoStack.add(op);
    historyChanged.notifyListeners();
  }

  void _pruneHistoryForPage(int pageId) {
    _undoStack.removeWhere((o) => o.pageIds.contains(pageId));
    _redoStack.removeWhere((o) => o.pageIds.contains(pageId));
    historyChanged.notifyListeners();
  }

  // -------------------------------------------------------------- selection

  final Set<int> selectedStrokeIds = {};
  final Set<String> selectedElementIds = {};
  int? selectionPageId;

  void _clearSelection() {
    selectedStrokeIds.clear();
    selectedElementIds.clear();
    selectionPageId = null;
    selectionChanged.notifyListeners();
  }

  void clearSelection() => _clearSelection();

  /// Selects exactly the given elements on [pageId] (used to auto-select
  /// newly inserted elements).
  void selectElements(int pageId, Iterable<String> elementIds) {
    selectedStrokeIds.clear();
    selectedElementIds
      ..clear()
      ..addAll(elementIds);
    selectionPageId = pageId;
    selectionChanged.notifyListeners();
  }

  bool get hasSelection =>
      selectedStrokeIds.isNotEmpty || selectedElementIds.isNotEmpty;

  /// Lasso selection: free polygon in PAGE space. Strokes are selected when
  /// their first point is contained; elements when their center or any bbox
  /// corner is contained. Auto-expands to all members of the same groupId.
  void selectInLasso(int pageId, List<Offset> polygon) {
    if (polygon.length < 3) {
      _clearSelection();
      return;
    }
    final ink = pageInk(pageId);
    selectedStrokeIds.clear();
    selectedElementIds.clear();
    selectionPageId = pageId;
    for (final s in ink.strokes) {
      if (s.isEmpty) continue;
      if (_pointInPolygon(s.point(0), polygon)) {
        selectedStrokeIds.add(s.id);
      }
    }
    for (final e in ink.elements) {
      final b = e.bbox();
      if (_pointInPolygon(b.center, polygon) ||
          _pointInPolygon(b.topLeft, polygon) ||
          _pointInPolygon(b.topRight, polygon) ||
          _pointInPolygon(b.bottomLeft, polygon) ||
          _pointInPolygon(b.bottomRight, polygon)) {
        selectedElementIds.add(e.id);
      }
    }
    // Group expansion: select all members of touched groups.
    final groups = <int>{};
    for (final s in ink.strokes) {
      if (s.groupId != null && selectedStrokeIds.contains(s.id)) {
        groups.add(s.groupId!);
      }
    }
    if (groups.isNotEmpty) {
      for (final s in ink.strokes) {
        if (s.groupId != null && groups.contains(s.groupId!)) {
          selectedStrokeIds.add(s.id);
        }
      }
    }
    selectionChanged.notifyListeners();
  }

  static bool _pointInPolygon(Offset p, List<Offset> poly) {
    var inside = false;
    var j = poly.length - 1;
    for (var i = 0; i < poly.length; i++) {
      final pi = poly[i];
      final pj = poly[j];
      if (((pi.dy > p.dy) != (pj.dy > p.dy)) &&
          (p.dx < (pj.dx - pi.dx) * (p.dy - pi.dy) / (pj.dy - pi.dy) + pi.dx)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  Rect? selectionBBox() {
    final pageId = selectionPageId;
    if (pageId == null) return null;
    final ink = pageInkOrNull(pageId);
    if (ink == null) return null;
    Rect? r;
    for (final s in ink.strokes) {
      if (selectedStrokeIds.contains(s.id)) {
        r = r == null ? s.bbox : r.expandToInclude(s.bbox);
      }
    }
    for (final e in ink.elements) {
      if (selectedElementIds.contains(e.id)) {
        final b = e.bbox();
        r = r == null ? b : r.expandToInclude(b);
      }
    }
    return r;
  }

  /// Page-space positions of the selection handles (4 corners + rotate).
  Map<SelHandle, Offset> selectionHandlesPage() {
    final b = selectionBBox();
    if (b == null) return const {};
    return {
      SelHandle.topLeft: b.topLeft,
      SelHandle.topRight: b.topRight,
      SelHandle.bottomLeft: b.bottomLeft,
      SelHandle.bottomRight: b.bottomRight,
      SelHandle.rotate: Offset(b.center.dx, b.top - 36),
    };
  }

  SelHandle hitSelectionHandle(Offset pagePoint, double tolerancePage) {
    final handles = selectionHandlesPage();
    for (final entry in handles.entries) {
      if ((entry.value - pagePoint).distance <= tolerancePage) {
        return entry.key;
      }
    }
    return SelHandle.none;
  }

  // ----------------------------------------------------- selection transforms

  TransformSnapshot? _transformSnap;

  void beginSelectionTransform() {
    final pageId = selectionPageId;
    if (pageId == null) return;
    final ink = pageInk(pageId);
    final snap = TransformSnapshot();
    for (final s in ink.strokes) {
      if (selectedStrokeIds.contains(s.id)) {
        snap.strokesBefore[s.id] = s.deepCopy();
      }
    }
    for (final e in ink.elements) {
      if (selectedElementIds.contains(e.id)) {
        snap.elementsBefore[e.id] = e.deepCopy();
      }
    }
    _transformSnap = snap;
  }

  /// Incremental move (no undo op until [endSelectionTransform]).
  void moveSelectionBy(Offset deltaPage) {
    final pageId = selectionPageId;
    if (pageId == null) return;
    final ink = pageInk(pageId);
    for (final s in ink.strokes) {
      if (selectedStrokeIds.contains(s.id)) {
        for (var i = 0; i < s.pointCount; i++) {
          s.pts[i * 3] += deltaPage.dx;
          s.pts[i * 3 + 1] += deltaPage.dy;
        }
        s.invalidateCaches();
      }
    }
    for (final e in ink.elements) {
      if (selectedElementIds.contains(e.id)) {
        translateElement(e, deltaPage.dx, deltaPage.dy);
      }
    }
    markDirty(pageId);
    ink.touch();
    selectionChanged.notifyListeners();
  }

  /// Scale: restores from the snapshot each frame, then scales around the
  /// OPPOSITE corner ([anchor] = opposite corner in page space).
  void scaleSelectionBy(double fx, double fy, Offset anchor) {
    final pageId = selectionPageId;
    if (pageId == null) return;
    _restoreSnapshot();
    final ink = pageInk(pageId);
    Offset map(Offset p) => Offset(
          anchor.dx + (p.dx - anchor.dx) * fx,
          anchor.dy + (p.dy - anchor.dy) * fy,
        );
    for (final s in ink.strokes) {
      if (!selectedStrokeIds.contains(s.id)) continue;
      for (var i = 0; i < s.pointCount; i++) {
        final p = map(s.point(i));
        s.pts[i * 3] = p.dx;
        s.pts[i * 3 + 1] = p.dy;
      }
      s.invalidateCaches();
    }
    for (final e in ink.elements) {
      if (!selectedElementIds.contains(e.id)) continue;
      if (e is TextEl) {
        final tl = map(Offset(e.x, e.y));
        final br = map(Offset(e.x + e.w, e.y + 40));
        e.x = tl.dx;
        e.y = tl.dy;
        e.w = math.max(24, (br.dx - tl.dx).abs());
        e.size = (e.size * ((fx + fy) / 2)).clamp(6.0, 240.0);
      } else if (e is ShapeEl) {
        if (e.pts != null) {
          e.pts = e.pts!.map(map).toList();
        }
        final tl = map(Offset(e.x, e.y));
        final br = map(Offset(e.x + e.w, e.y + e.h));
        e.x = math.min(tl.dx, br.dx);
        e.y = math.min(tl.dy, br.dy);
        e.w = math.max(1, (br.dx - tl.dx).abs());
        e.h = math.max(1, (br.dy - tl.dy).abs());
        e.strokeWidth = (e.strokeWidth * ((fx + fy) / 2)).clamp(0.5, 60.0);
      } else if (e is ImageEl) {
        final tl = map(Offset(e.x, e.y));
        final br = map(Offset(e.x + e.w, e.y + e.h));
        e.x = math.min(tl.dx, br.dx);
        e.y = math.min(tl.dy, br.dy);
        e.w = math.max(8, (br.dx - tl.dx).abs());
        e.h = math.max(8, (br.dy - tl.dy).abs());
      }
    }
    markDirty(pageId);
    ink.touch();
    selectionChanged.notifyListeners();
  }

  /// Rotate: restores from the snapshot each frame, then rotates around the
  /// selection center. [delta] is radians since gesture start; when [snap],
  /// it is magnetized to 15° steps.
  void rotateSelectionBy(double delta, {bool snap = false}) {
    final pageId = selectionPageId;
    if (pageId == null) return;
    _restoreSnapshot();
    var d = delta;
    if (snap) {
      const step = math.pi / 12; // 15°
      d = (d / step).roundToDouble() * step;
    }
    final center = selectionBBox()?.center ?? Offset.zero;
    Offset map(Offset p) => rotatePoint(p, center, d);

    final ink = pageInk(pageId);
    for (final s in ink.strokes) {
      if (!selectedStrokeIds.contains(s.id)) continue;
      for (var i = 0; i < s.pointCount; i++) {
        final p = map(s.point(i));
        s.pts[i * 3] = p.dx;
        s.pts[i * 3 + 1] = p.dy;
      }
      s.invalidateCaches();
    }
    for (final e in ink.elements) {
      if (!selectedElementIds.contains(e.id)) continue;
      if (e is TextEl) {
        final p = map(Offset(e.x, e.y));
        e.x = p.dx;
        e.y = p.dy;
      } else if (e is ShapeEl) {
        if (e.pts != null) {
          e.pts = e.pts!.map(map).toList();
        } else {
          e.rotation += d;
        }
      } else if (e is ImageEl) {
        e.rotation += d;
        final p = map(Offset(e.x, e.y));
        e.x = p.dx;
        e.y = p.dy;
      }
    }
    markDirty(pageId);
    ink.touch();
    selectionChanged.notifyListeners();
  }

  void _restoreSnapshot() {
    final snap = _transformSnap;
    final pageId = selectionPageId;
    if (snap == null || pageId == null) return;
    final ink = pageInk(pageId);
    for (final s in ink.strokes.toList()) {
      final before = snap.strokesBefore[s.id];
      if (before != null) {
        ink.strokes[ink.strokes.indexOf(s)] = before.deepCopy();
      }
    }
    for (final e in ink.elements.toList()) {
      final before = snap.elementsBefore[e.id];
      if (before != null) {
        ink.elements[ink.elements.indexOf(e)] = before.deepCopy();
      }
    }
    // Keep group ids from the snapshot (deep copies already carry them).
  }

  void endSelectionTransform() {
    final snap = _transformSnap;
    final pageId = selectionPageId;
    _transformSnap = null;
    if (snap == null || pageId == null) return;
    final ink = pageInk(pageId);
    for (final s in ink.strokes) {
      if (selectedStrokeIds.contains(s.id)) {
        snap.strokesAfter[s.id] = s.deepCopy();
      }
    }
    for (final e in ink.elements) {
      if (selectedElementIds.contains(e.id)) {
        snap.elementsAfter[e.id] = e.deepCopy();
      }
    }
    if (snap.strokesAfter.isEmpty && snap.elementsAfter.isEmpty) return;
    _pushOp(TransformOp(pageId, snap));
  }

  /// Cancels an in-progress transform gesture: restores the snapshot without
  /// pushing an undo op.
  void cancelSelectionTransform() {
    if (_transformSnap == null) return;
    _restoreSnapshot();
    _transformSnap = null;
    final pageId = selectionPageId;
    if (pageId != null) {
      final ink = pageInk(pageId);
      markDirty(pageId);
      ink.touch();
    }
    selectionChanged.notifyListeners();
  }

  // -------------------------------------------------------- selection actions

  void deleteSelection() {
    final pageId = selectionPageId;
    if (pageId == null) return;
    final ink = pageInk(pageId);
    final strokes =
        ink.strokes.where((s) => selectedStrokeIds.contains(s.id)).toList();
    final elements =
        ink.elements.where((e) => selectedElementIds.contains(e.id)).toList();
    if (strokes.isEmpty && elements.isEmpty) return;
    ink.strokes.removeWhere((s) => selectedStrokeIds.contains(s.id));
    ink.elements.removeWhere((e) => selectedElementIds.contains(e.id));
    markDirty(pageId);
    ink.touch();
    _clearSelection();
    final ops = <InkOp>[];
    if (strokes.isNotEmpty) ops.add(RemoveInkOp(pageId, strokes.map((s) => s.deepCopy()).toList()));
    if (elements.isNotEmpty) {
      ops.add(RemoveElementsOp(pageId, elements.map((e) => e.deepCopy()).toList()));
    }
    _pushOp(ops.length == 1 ? ops.first : CompositeOp(ops));
  }

  void duplicateSelection() {
    final pageId = selectionPageId;
    if (pageId == null) return;
    final clip = _copySelectionItems();
    _clearSelection();
    if (clip == null) return;
    _pasteClones(pageId, clip.$1, clip.$2, const Offset(16, 16));
  }

  void copySelection() {
    // Deep clones are captured immediately.
    _copySelectionItems();
  }

  (List<Stroke>, List<PageElement>)? _copySelectionItems() {
    final pageId = selectionPageId;
    if (pageId == null) return null;
    final ink = pageInk(pageId);
    final strokes = ink.strokes
        .where((s) => selectedStrokeIds.contains(s.id))
        .map((s) => s.deepCopy())
        .toList();
    final elements = ink.elements
        .where((e) => selectedElementIds.contains(e.id))
        .map((e) => e.deepCopy())
        .toList();
    if (strokes.isEmpty && elements.isEmpty) return null;
    _clipboard = (strokes, elements);
    return (strokes, elements);
  }

  (List<Stroke>, List<PageElement>)? _clipboard;

  bool get hasClipboard => _clipboard != null;

  void cutSelection() {
    copySelection();
    deleteSelection();
  }

  void pasteAt(int pageId, Offset centerPage) {
    final clip = _clipboard;
    if (clip == null) return;
    _clearSelection();
    _pasteClones(pageId, clip.$1, clip.$2, Offset.zero, at: centerPage);
  }

  void _pasteClones(int pageId, List<Stroke> strokes, List<PageElement> elements,
      Offset offset, {Offset? at}) {
    final ink = pageInk(pageId);
    // Determine the clipboard bbox center to honor pasteAt.
    Rect? r;
    for (final s in strokes) {
      r = r == null ? s.bbox : r.expandToInclude(s.bbox);
    }
    for (final e in elements) {
      r = r == null ? e.bbox() : r.expandToInclude(e.bbox());
    }
    var shift = offset;
    if (at != null && r != null) {
      shift = at - r.center;
    }
    var z = ink.nextZ();
    final newStrokes = <Stroke>[];
    for (final s in strokes) {
      final c = s.deepCopy();
      c.id = StrokeIdGen.next();
      c.z = z++;
      for (var i = 0; i < c.pointCount; i++) {
        c.pts[i * 3] += shift.dx;
        c.pts[i * 3 + 1] += shift.dy;
      }
      c.invalidateCaches();
      newStrokes.add(c);
    }
    final newElements = <PageElement>[];
    for (final e in elements) {
      final c = e.deepCopy();
      c.z = z++;
      translateElement(c, shift.dx, shift.dy);
      newElements.add(c);
    }
    ink.strokes.addAll(newStrokes);
    ink.elements.addAll(newElements);
    ink.sortInk();
    markDirty(pageId);
    ink.touch();
    selectionPageId = pageId;
    selectedStrokeIds.addAll(newStrokes.map((s) => s.id));
    selectedElementIds.addAll(newElements.map((e) => e.id));
    selectionChanged.notifyListeners();
    final ops = <InkOp>[];
    if (newStrokes.isNotEmpty) ops.add(AddInkOp(pageId, newStrokes));
    if (newElements.isNotEmpty) ops.add(AddElementsOp(pageId, newElements));
    _pushOp(ops.length == 1 ? ops.first : CompositeOp(ops));
    // §3 pasted content may land beyond the current paper (infinite only).
    Rect? pasted;
    for (final s in newStrokes) {
      pasted = pasted == null ? s.bbox : pasted.expandToInclude(s.bbox);
    }
    for (final e in newElements) {
      pasted = pasted == null ? e.bbox() : pasted.expandToInclude(e.bbox());
    }
    if (pasted != null) _growForContent(pageId, pasted);
  }

  void bringSelectionToFront() {
    final pageId = selectionPageId;
    if (pageId == null) return;
    final ink = pageInk(pageId);
    var z = ink.nextZ();
    final snap = TransformSnapshot();
    for (final s in ink.strokes) {
      if (selectedStrokeIds.contains(s.id)) {
        snap.strokesBefore[s.id] = s.deepCopy();
        s.z = z++;
        snap.strokesAfter[s.id] = s.deepCopy();
      }
    }
    for (final e in ink.elements) {
      if (selectedElementIds.contains(e.id)) {
        snap.elementsBefore[e.id] = e.deepCopy();
        e.z = z++;
        snap.elementsAfter[e.id] = e.deepCopy();
      }
    }
    ink.sortInk();
    markDirty(pageId);
    ink.touch();
    if (snap.strokesBefore.isNotEmpty || snap.elementsBefore.isNotEmpty) {
      _pushOp(TransformOp(pageId, snap));
    }
  }

  void sendSelectionToBack() {
    final pageId = selectionPageId;
    if (pageId == null) return;
    final ink = pageInk(pageId);
    var z = 0;
    for (final s in ink.strokes) {
      if (!selectedStrokeIds.contains(s.id)) z = math.min(z, s.z - 1);
    }
    for (final e in ink.elements) {
      if (!selectedElementIds.contains(e.id)) z = math.min(z, e.z - 1);
    }
    final snap = TransformSnapshot();
    for (final s in ink.strokes) {
      if (selectedStrokeIds.contains(s.id)) {
        snap.strokesBefore[s.id] = s.deepCopy();
        s.z = z--;
        snap.strokesAfter[s.id] = s.deepCopy();
      }
    }
    for (final e in ink.elements) {
      if (selectedElementIds.contains(e.id)) {
        snap.elementsBefore[e.id] = e.deepCopy();
        e.z = z--;
        snap.elementsAfter[e.id] = e.deepCopy();
      }
    }
    ink.sortInk();
    markDirty(pageId);
    ink.touch();
    if (snap.strokesBefore.isNotEmpty || snap.elementsBefore.isNotEmpty) {
      _pushOp(TransformOp(pageId, snap));
    }
  }

  void groupSelection() {
    final pageId = selectionPageId;
    if (pageId == null) return;
    final ink = pageInk(pageId);
    final group = DateTime.now().microsecondsSinceEpoch;
    for (final s in ink.strokes) {
      if (selectedStrokeIds.contains(s.id)) s.groupId = group;
    }
    // Elements join via a mapping stored on ShapeEl? v1 groups strokes only.
    markDirty(pageId);
    selectionChanged.notifyListeners();
  }

  void ungroupSelection() {
    final pageId = selectionPageId;
    if (pageId == null) return;
    final ink = pageInk(pageId);
    for (final s in ink.strokes) {
      if (selectedStrokeIds.contains(s.id)) s.groupId = null;
    }
    markDirty(pageId);
    selectionChanged.notifyListeners();
  }

  // ---------------------------------------------------------------- elements

  PageElement? elementAt(int pageId, Offset pagePoint) {
    final ink = pageInkOrNull(pageId);
    if (ink == null) return null;
    PageElement? best;
    for (final e in ink.elements) {
      if (e.bbox().contains(pagePoint)) {
        if (best == null || e.z > best.z) best = e;
      }
    }
    return best;
  }

  void addElement(int pageId, PageElement el) {
    final ink = pageInk(pageId);
    el.z = ink.nextZ();
    ink.elements.add(el);
    ink.sortInk();
    markDirty(pageId);
    ink.touch();
    _pushOp(AddElementsOp(pageId, [el.deepCopy()]));
    // §3 the paper chases the pen (infinite pages only).
    _growForContent(pageId, el.bbox());
  }

  void updateElement(int pageId, PageElement el) {
    final ink = pageInk(pageId);
    final i = ink.elements.indexWhere((e) => e.id == el.id);
    if (i < 0) return;
    final snap = TransformSnapshot();
    snap.elementsBefore[el.id] = ink.elements[i].deepCopy();
    ink.elements[i] = el;
    snap.elementsAfter[el.id] = el.deepCopy();
    markDirty(pageId);
    ink.touch();
    _pushOp(TransformOp(pageId, snap));
    // §3 a moved/scaled element may need more paper (infinite pages only).
    _growForContent(pageId, el.bbox());
  }

  void removeElement(int pageId, PageElement el) {
    final ink = pageInk(pageId);
    ink.elements.removeWhere((e) => e.id == el.id);
    markDirty(pageId);
    ink.touch();
    if (selectedElementIds.contains(el.id)) {
      selectedElementIds.remove(el.id);
      selectionChanged.notifyListeners();
    }
    _pushOp(RemoveElementsOp(pageId, [el.deepCopy()]));
  }

  // ------------------------------------------------------------ recognition

  /// Replaces a committed stroke with a shape element as ONE revertible op.
  void replaceStrokeWithShape(int pageId, Stroke stroke, ShapeEl shape) {
    final ink = pageInk(pageId);
    if (!ink.strokes.any((s) => s.id == stroke.id)) return;
    ink.strokes.removeWhere((s) => s.id == stroke.id);
    shape.z = stroke.z;
    ink.elements.add(shape);
    ink.sortInk();
    markDirty(pageId);
    ink.touch();
    _pushOp(ReplaceInkOp(pageId, stroke, shape));
    // §3 recognized shapes may extend past the ink they replace.
    _growForContent(pageId, shape.bbox());
  }

  // -------------------------------------------------------------- page ops

  PageMeta? metaOf(int pageId) {
    for (final p in pages) {
      if (p.id == pageId) return p;
    }
    return null;
  }

  Future<PageMeta> addPage({int? afterPosition}) async {
    final n = notebook!;
    final pos = afterPosition == null ? pages.length : afterPosition + 1;
    final entity = await _lib.addPage(
      n.id,
      pos,
      n.template,
      n.pageSize,
      n.paperColor,
    );
    final meta = PageMeta.from(entity);
    pages.insert(pos.clamp(0, pages.length), meta);
    for (var i = 0; i < pages.length; i++) {
      pages[i].position = i;
    }
    await _lib.reorderPages(n.id, pages.map((p) => p.id).toList());
    pagesChanged.notifyListeners();
    return meta;
  }

  Future<PageMeta> duplicatePage(int pageId) async {
    final src = metaOf(pageId)!;
    final newMeta = await addPage(afterPosition: src.position);
    await _repo.duplicatePageInk(pageId, newMeta.id);
    final ink = pageInk(newMeta.id);
    ink.elements.addAll(await _repo.loadElements(newMeta.id));
    ink.strokesLoaded = false; // lazy reload on demand
    pagesChanged.notifyListeners();
    return newMeta;
  }

  Future<void> deletePage(int pageId) async {
    final meta = metaOf(pageId);
    if (meta == null) return;
    final entity = await _lib.page(pageId);
    if (entity != null) await _lib.deletePage(entity);
    pages.remove(meta);
    for (var i = 0; i < pages.length; i++) {
      pages[i].position = i;
    }
    _inks.remove(pageId);
    _dirtyPages.remove(pageId);
    if (selectionPageId == pageId) _clearSelection();
    _pruneHistoryForPage(pageId);
    if (notebook != null) {
      await _lib.reorderPages(notebook!.id, pages.map((p) => p.id).toList());
    }
    pagesChanged.notifyListeners();
  }

  Future<void> reorderPage(int pageId, int newPosition) async {
    final meta = metaOf(pageId);
    if (meta == null) return;
    pages.remove(meta);
    pages.insert(newPosition.clamp(0, pages.length), meta);
    for (var i = 0; i < pages.length; i++) {
      pages[i].position = i;
    }
    if (notebook != null) {
      await _lib.reorderPages(notebook!.id, pages.map((p) => p.id).toList());
    }
    pagesChanged.notifyListeners();
  }

  Future<void> setPageBookmark(int pageId, bool value) async {
    final meta = metaOf(pageId);
    if (meta == null) return;
    meta.bookmarked = value;
    final entity = await _lib.page(pageId);
    if (entity != null) {
      entity.bookmarked = value;
      await _lib.updatePage(entity);
    }
    pagesChanged.notifyListeners();
  }

  Future<void> setPageTitle(int pageId, String title) async {
    final meta = metaOf(pageId);
    if (meta == null) return;
    meta.title = title;
    final entity = await _lib.page(pageId);
    if (entity != null) {
      entity.title = title;
      await _lib.updatePage(entity);
    }
    pagesChanged.notifyListeners();
  }

  /// Invalidates cached outlines (pressure curve changed).
  void invalidateAllOutlines() {
    for (final ink in _inks.values) {
      for (final s in ink.strokes) {
        s.invalidateCaches();
      }
      ink.touch();
    }
  }

  @override
  void dispose() {
    liveStroke.dispose();
    eraserCursor.dispose();
    lassoPreview.dispose();
    historyChanged.dispose();
    selectionChanged.dispose();
    pagesChanged.dispose();
    super.dispose();
  }
}
