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
  /// page 0 using each page's own size definition (PageMeta.pageSize →
  /// pageSizeIdFrom → PAGE_SIZES).
  Rect pageRect(int pageIndex) {
    var y = 0.0;
    for (var i = 0; i < pageIndex && i < pages.length; i++) {
      y += pages[i].sizeDef.h + pageGap;
    }
    double w;
    double h;
    if (pageIndex >= 0 && pageIndex < pages.length) {
      w = pages[pageIndex].sizeDef.w;
      h = pages[pageIndex].sizeDef.h;
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
  Rect get docBounds {
    if (pages.isEmpty) {
      final fallback = pageSizeDef(PageSizeId.a4Portrait);
      return Rect.fromLTWH(0, 0, fallback.w, fallback.h).inflate(400);
    }
    var bounds = pageRect(0);
    for (var i = 1; i < pages.length; i++) {
      bounds = bounds.expandToInclude(pageRect(i));
    }
    return bounds.inflate(400);
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
