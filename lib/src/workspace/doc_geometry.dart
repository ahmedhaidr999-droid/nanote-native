import 'package:flutter/material.dart';

import '../controllers/stroke_engine.dart';
import '../models/paper.dart';

/// Doc-space geometry of the notebook: pages stacked vertically, separated
/// by a gap. All accessors work in DOCUMENT coordinates — the space the
/// [ViewportController] matrix maps to the screen.
///
/// The class holds the engine's LIVE page list, so page additions, deletions
/// and reorders are picked up automatically (every accessor recomputes from
/// scratch — page counts are small).
///
/// §2 INFINITY PAPER model:
///  * Every page carries pads (padX/padY grow LEFT/UP of the original
///    origin; growW/growH extend right/bottom). Page-local ink coordinates
///    may be NEGATIVE (down to -padX/-padY).
///  * [pageRect] returns the FULL grown rect (starts at negative doc
///    coordinates when pads exist) — used for widget placement, hit-testing
///    and culling.
///  * [pageOrigin] returns the ANCHOR (the original top-left of the page,
///    before any growth) — the point page-local ink is measured from, so
///    existing ink NEVER shifts when the paper grows.
///  * Infinite notebooks stack their pages with a 28-unit gap (§1); normal
///    notebooks keep the classic 56.
class DocGeometry {
  /// Live reference to [StrokeEngine.pages].
  final List<PageMeta> pages;

  DocGeometry(this.pages);

  /// Doc-space gap between consecutive pages (§1: 28 for infinite
  /// notebooks, 56 otherwise).
  double get pageGap => _allInfinite ? kInfiniteGap : 56.0;

  bool get _allInfinite => pages.isNotEmpty && pages.every((p) => p.isInfinite);

  /// §2 The Y of page [pageIndex]'s ANCHOR (original top-left). Y
  /// accumulates each page's FULL height (base + pads + growth) plus the
  /// gap — pads are reserved by the layout so pages never overlap.
  double _anchorY(int pageIndex) {
    var y = 0.0;
    for (var i = 0; i < pageIndex && i < pages.length; i++) {
      y += pages[i].effectiveSize.height + pageGap;
    }
    return y;
  }

  /// §2 Rect of the page at visual [pageIndex] (0-based) — the FULL grown
  /// paper: starts at (-padX, anchorY - padY) and spans the base size plus
  /// all growth. For normal pages (no pads) this is the classic rect.
  Rect pageRect(int pageIndex) {
    double w;
    double h;
    double padX;
    double padY;
    if (pageIndex >= 0 && pageIndex < pages.length) {
      final meta = pages[pageIndex];
      final size = meta.effectiveSize;
      w = size.width;
      h = size.height;
      padX = meta.padX;
      padY = meta.padY;
    } else {
      // Defensive fallback for out-of-range indices (never crashes).
      final fallback = pageSizeDef(PageSizeId.a4Portrait);
      w = fallback.w;
      h = fallback.h;
      padX = 0;
      padY = 0;
    }
    return Rect.fromLTWH(-padX, _anchorY(pageIndex) - padY, w, h);
  }

  /// §2 The ANCHOR of the page with the given STABLE ink id — the original
  /// top-left the page-local ink coordinates are measured from (NOT the
  /// grown rect's top-left). Returns [Offset.zero] for unknown ids
  /// (defensive).
  Offset pageOrigin(int pageId) {
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].id == pageId) {
        return Offset(0, _anchorY(i));
      }
    }
    return Offset.zero;
  }

  /// The page whose FULL rect contains [docPoint] (null when the point
  /// falls in a gap or outside every page).
  PageMeta? pageAt(Offset docPoint) {
    for (var i = 0; i < pages.length; i++) {
      if (pageRect(i).contains(docPoint)) return pages[i];
    }
    return null;
  }

  /// Visual index of the page whose rect contains [docPoint].
  int? pageIndexAtDoc(Offset docPoint) {
    for (var i = 0; i < pages.length; i++) {
      if (pageRect(i).contains(docPoint)) return i;
    }
    return null;
  }

  /// Document point → page-local point of [pageId] (anchor-relative; may
  /// be NEGATIVE on infinite pages).
  Offset toPage(Offset doc, int pageId) => doc - pageOrigin(pageId);

  /// Page-local point of [pageId] → document point.
  Offset toDoc(Offset page, int pageId) => page + pageOrigin(pageId);

  /// Union of all page rects inflated by a generous margin (pan clamping /
  /// gesture bounds). §5: for infinite notebooks the viewport applies its
  /// own wider roam margin on top of this.
  Rect get docBounds => tightBounds.inflate(400);

  /// Union of all page rects WITHOUT inflation — used by the viewport clamp
  /// (an axis that fits the screen stays centered; larger axes keep their
  /// edges inside the view). §2: extends into NEGATIVE coordinates when
  /// infinite pages grew left/up.
  Rect get tightBounds {
    if (pages.isEmpty) {
      final fallback = pageSizeDef(PageSizeId.a4Portrait);
      return Rect.fromLTWH(0, 0, fallback.w, fallback.h);
    }
    var bounds = pageRect(0);
    for (var i = 1; i < pages.length; i++) {
      bounds = bounds.expandToInclude(pageRect(i));
    }
    return bounds;
  }

  /// Pages whose rects intersect [docRect] — viewport culling list.
  List<PageMeta> visiblePages(Rect docRect) {
    final out = <PageMeta>[];
    for (var i = 0; i < pages.length; i++) {
      if (pageRect(i).overlaps(docRect)) out.add(pages[i]);
    }
    return out;
  }
}
