// Workspace layout/culling verification for multi-page PDF notebooks —
// the exact math the canvas AnimatedBuilder runs every frame:
//
//   viewport.panBounds = geometry.tightBounds;
//   viewport.clampToDoc();
//   final visible = geometry.visiblePages(viewport.visibleDocRect(size));
//
// Uses the REAL DocGeometry, ViewportController and PageMeta classes (no
// database): pages are built directly and the per-page PDF aspect is
// applied the way StrokeEngine.applyPdfPageSize does on open.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nanote_native/src/controllers/stroke_engine.dart'
    show PageMeta;
import 'package:nanote_native/src/controllers/viewport_controller.dart';
import 'package:nanote_native/src/workspace/doc_geometry.dart';
import 'package:nanote_native/src/models/paper.dart';

PageMeta _page(int id, {int position = 0}) => PageMeta(
      id: id,
      position: position,
      title: 'p$id',
      bookmarked: false,
      template: TemplateId.blank.index,
      pageSize: PageSizeId.a4Portrait.index,
      paperColor: PAPER_COLORS.first.toARGB32(),
    );

void main() {
  test('pages stack vertically with the classic 56-unit gap', () {
    final pages = [_page(1, position: 0), _page(2, position: 1), _page(3, position: 2)];
    final geo = DocGeometry(pages);

    final r0 = geo.pageRect(0);
    final r1 = geo.pageRect(1);
    final r2 = geo.pageRect(2);

    expect(r0.top, 0);
    expect(r1.top, closeTo(r0.bottom + 56, 1e-9),
        reason: 'page 2 must start 56 units below page 1');
    expect(r2.top, closeTo(r1.bottom + 56, 1e-9));
    expect(r1.width, r0.width);
    expect(r2.height, greaterThan(0));
  });

  test('PDF aspect overrides keep pages non-degenerate and stacked', () {
    final pages = [_page(1, position: 0), _page(2, position: 1), _page(3, position: 2)];
    // The workspace applies the PDF aspect per page (base width, PDF ratio).
    for (final p in pages) {
      // A4 portrait PDF: 595.27 x 841.89 → aspect ~1.414.
      p.pdfSize = const Size(595.27, 841.89);
    }
    final geo = DocGeometry(pages);

    for (var i = 0; i < pages.length; i++) {
      final r = geo.pageRect(i);
      expect(r.width, greaterThan(0));
      expect(r.height, greaterThan(0));
      expect(r.isFinite, isTrue, reason: 'page ${i + 1} rect must be finite');
    }
    final b = geo.tightBounds;
    expect(b.isFinite, isTrue);
    expect(b.height,
        greaterThan(geo.pageRect(0).height * pages.length));
  });

  test('scrolling exposes pages 2+ (culling never hides laid-out pages)',
      () async {
    final pages = <PageMeta>[];
    for (var i = 0; i < 5; i++) {
      pages.add(_page(100 + i, position: i));
    }
    for (final p in pages) {
      p.pdfSize = const Size(595.27, 841.89);
    }
    final geo = DocGeometry(pages);

    // The real viewport wiring the workspace performs.
    final viewport = ViewportController();
    addTearDown(viewport.dispose);
    const screen = Size(420, 800);
    viewport.screenExtent = screen;
    viewport.panBounds = geo.tightBounds;
    viewport.clampToDoc();

    // Initial fit: page width into the screen (workspace _scheduleInitialFit).
    viewport.fitPageWidth(geo.pageRect(0), screen, animated: false);
    viewport.panBounds = geo.tightBounds;
    viewport.clampToDoc();

    // Page 1 visible at open.
    var visible = geo.visiblePages(viewport.visibleDocRect(screen));
    expect(visible.map((p) => p.id), contains(100));

    // Scroll DOWN to each successive page the way a fling/pan does: move
    // the pan so the page's rect center lands at the screen center.
    for (var i = 1; i < pages.length; i++) {
      final rect = geo.pageRect(i);
      final centerDoc = rect.center;
      // screen = doc * scale + pan → pan = screenCenter - doc * scale
      viewport.setMatrix(
        viewport.scale,
        screen.center(Offset.zero) - centerDoc * viewport.scale,
      );
      viewport.panBounds = geo.tightBounds;
      viewport.clampToDoc();

      visible = geo.visiblePages(viewport.visibleDocRect(screen));
      expect(
        visible.map((p) => p.id),
        contains(pages[i].id),
        reason:
            'after scrolling to page ${i + 1} it must be in the visible set',
      );
    }

    // Page JUMP (pages manager → fitPageWidth of the target page).
    final target = geo.pageRect(4);
    viewport.fitPageWidth(target, screen, animated: false);
    viewport.panBounds = geo.tightBounds;
    viewport.clampToDoc();
    visible = geo.visiblePages(viewport.visibleDocRect(screen));
    expect(visible.map((p) => p.id), contains(pages[4].id),
        reason: 'jumping to the last page must make it visible');
  });

  test('pan clamping allows reaching the last page (no scroll lock)', () {
    final pages = <PageMeta>[];
    for (var i = 0; i < 10; i++) {
      pages.add(_page(200 + i, position: i));
    }
    for (final p in pages) {
      p.pdfSize = const Size(595.27, 841.89);
    }
    final geo = DocGeometry(pages);
    final viewport = ViewportController();
    addTearDown(viewport.dispose);
    const screen = Size(420, 800);
    viewport.screenExtent = screen;
    viewport.panBounds = geo.tightBounds;
    viewport.clampToDoc();
    viewport.fitPageWidth(geo.pageRect(0), screen, animated: false);
    viewport.panBounds = geo.tightBounds;
    viewport.clampToDoc();

    // Panning far down must clamp INSIDE the document bounds — the bottom
    // page must remain reachable (never locked to page 1).
    viewport.panBy(const Offset(0, -100000));
    final visible = geo.visiblePages(viewport.visibleDocRect(screen));
    expect(visible, isNotEmpty);
    expect(visible.map((p) => p.id), contains(pages.last.id),
        reason: 'the last page must be reachable by scrolling');
  });
}
