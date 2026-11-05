import 'package:flutter/material.dart';

import '../controllers/stroke_engine.dart';
import '../models/paper.dart';

/// Doc-space geometry of the notebook: pages stacked vertically, separated by
/// [pageGap]. All accessors work in DOCUMENT coordinates — the space the
/// [ViewportController] matrix maps to the screen.
///
/// The class holds the engine's LIVE page list, so page additions, deletions
/// and reorders are picked up automatically (every accessor recomputes from
/// scratch — page counts are small).
class DocGeometry {
  /// Doc-space gap between consecutive pages.
  static const double pageGap = 56.0;

  /// Live reference to [StrokeEngine.pages].
  final List<PageMeta> pages;

  DocGeometry(this.pages);

  /// Rect of the page at visual [pageIndex] (0-based). Y accumulates from
  /// page 0 using each page's own EFFECTIVE size (PageMeta.effectiveSize →
  /// the PDF aspect for PDF notebooks, else the paper size definition).
  Rect pageRect(int pageIndex) {
    var y = 0.0;
    for (var i = 0; i < pageIndex && i < pages.length; i++) {
      y += pages[i].effectiveSize.height + pageGap;
    }
    double w;
    double h;
    if (pageIndex >= 0 && pageIndex < pages.length) {
      w = pages[pageIndex].effectiveSize.width;
      h = pages[pageIndex].effectiveSize.height;
    } else {
      // Defensive fallback for out-of-range indices (never crashes).
      final fallback = pageSizeDef(PageSizeId.a4Portrait);
      w = fallback.w;
      h = fallback.h;
    }
    return Rect.fromLTWH(0, y, w, h);
  }

  /// Doc-space origin (top-left) of the page with the given STABLE ink id.
  /// Returns [Offset.zero] for unknown ids (defensive).
  Offset pageOrigin(int pageId) {
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].id == pageId) return pageRect(i).topLeft;
    }
    return Offset.zero;
  }

  /// The page whose rect contains [docPoint] (null when the point falls in a
  /// gap or outside every page).
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

  /// Document point → page-local point of [pageId].
  Offset toPage(Offset doc, int pageId) => doc - pageOrigin(pageId);

  /// Page-local point of [pageId] → document point.
  Offset toDoc(Offset page, int pageId) => page + pageOrigin(pageId);

  /// Union of all page rects inflated by a generous margin (pan clamping /
  /// gesture bounds).
  Rect get docBounds => tightBounds.inflate(400);

  /// Union of all page rects WITHOUT inflation — used by the viewport clamp
  /// (an axis that fits the screen stays centered; larger axes keep their
  /// edges inside the view).
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
