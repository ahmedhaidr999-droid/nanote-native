// END-TO-END verification of the "only PDF page 1 renders, pages 2+ stay
// blank/gray" fix — through the REAL production pipeline.
//
//   PdfPageTile → PdfDocumentController → PdfDocumentPigeon (REAL)
//     → PdfPagePigeon (REAL, incl. the per-document locks)
//     → PdfPageImagePigeon.render (REAL) → getPixels (REAL temp-file I/O)
//     → Pigeon BasicMessageChannel (REAL codec + encoding)
//        ↕ mocked ONLY at the BinaryMessenger level — exactly where the
//          Android Kotlin (Messages.kt) sits.
//
// The fake native side models Messages.kt semantics faithfully:
//   * documents/pages repositories (register/close)
//   * android.graphics.pdf.PdfRenderer: ONE open page per renderer — a
//     second openPage fails with "Current page is not closed"
//   * renderPage runs ASYNC (Dispatchers.IO) and writes a REAL temp file
//     whose bytes the real Dart getPixels() then reads and deletes
//   * closeDocument with an open page fails (IllegalStateException analog)
//   * a "wedge": a render whose platform reply is NEVER delivered (native
//     hang / pre-fix OOM) — with the OLD GLOBAL pdfx lock this poisoned
//     every pdfx call app-wide forever; with the fork's PER-DOCUMENT locks
//     the controller's watchdog recovery replaces the document and later
//     pages render again.
//
// Scenarios:
//   A. 5-page PDF, every page mounted → all pages render & paint.
//   B. Scroll: page 1 visible, user pans down → pages 2..5 mount late and
//      render (culling + late tiles).
//   C. THE DEVICE BUG: page 1 renders, then a native render WEDGES —
//      after watchdog recovery, FRESH pages must still render (with the
//      old global lock they never did — the lock stayed poisoned forever).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfx/src/renderer/has_pdf_support.dart'
    show debugOverrideSupported;
import 'package:pdfx/src/renderer/io/pigeon.dart'
    show PdfxApi, OpenPathMessage, OpenReply, IdMessage, GetPageMessage,
         GetPageReply, RenderPageMessage, RenderPageReply;
import 'package:pdfx/src/renderer/io/platform_pigeon.dart'
    show PdfxPlatformPigeon;
import 'package:pdfx/src/renderer/interfaces/platform.dart'
    show PdfxPlatform;

import 'package:nanote_native/src/controllers/pdf_document_controller.dart';
import 'package:nanote_native/src/controllers/stroke_engine.dart'
    show PageMeta;
import 'package:nanote_native/src/controllers/viewport_controller.dart';
import 'package:nanote_native/src/models/paper.dart';
import 'package:nanote_native/src/workspace/doc_geometry.dart';
import 'package:nanote_native/src/workspace/paper_painter.dart';
import 'package:nanote_native/src/workspace/pdf_page_tile.dart';

/// ---------------------------------------------------------------------------
/// Fake NATIVE layer (models io.scer.pdfx Messages.kt exactly)
/// ---------------------------------------------------------------------------

class _NativeDoc {
  _NativeDoc(this.id, this.pageSizes);
  final String id;
  final Map<int, ui.Size> pageSizes;
  int? openPage;
  bool closed = false;
}

class _OpenPage {
  _OpenPage(this.docId, this.pageNumber);
  final String docId;
  final int pageNumber;
}

class FakeNative {
  FakeNative({required this.pageCount});

  final int pageCount;
  final Map<String, _NativeDoc> documents = {};
  final Map<String, _OpenPage> pages = {};
  final List<String> log = [];

  /// When > 0: the next N renders never deliver a platform reply.
  int wedgeNextRenders = 0;

  /// When > 0: the next N renders throw a native error (transient).
  int failNextRenders = 0;

  Directory? tempDir;

  final Map<int, Uint8List> _pngs = {};
  void registerPng(int page, Uint8List bytes) => _pngs[page] = bytes;

  static const _chanOpenFile = 'dev.flutter.pigeon.PdfxApi.openDocumentFile';
  static const _chanCloseDoc = 'dev.flutter.pigeon.PdfxApi.closeDocument';
  static const _chanGetPage = 'dev.flutter.pigeon.PdfxApi.getPage';
  static const _chanRender = 'dev.flutter.pigeon.PdfxApi.renderPage';
  static const _chanClosePage = 'dev.flutter.pigeon.PdfxApi.closePage';

  void install(TestWidgetsFlutterBinding binding) {
    final m = binding.defaultBinaryMessenger;
    m.setMockMessageHandler(_chanOpenFile, _onOpenFile);
    m.setMockMessageHandler(_chanCloseDoc, _onCloseDoc);
    m.setMockMessageHandler(_chanGetPage, _onGetPage);
    m.setMockMessageHandler(_chanRender, _onRender);
    m.setMockMessageHandler(_chanClosePage, _onClosePage);
  }

  // ignore: library_private_types_in_public_api
  void uninstall(TestWidgetsFlutterBinding binding) {
    final m = binding.defaultBinaryMessenger;
    m.setMockMessageHandler(_chanOpenFile, null);
    m.setMockMessageHandler(_chanCloseDoc, null);
    m.setMockMessageHandler(_chanGetPage, null);
    m.setMockMessageHandler(_chanRender, null);
    m.setMockMessageHandler(_chanClosePage, null);
  }

  ByteData? _ok(Object result) =>
      PdfxApi.codec.encodeMessage(<Object?, Object?>{'result': result});

  ByteData? _err(String code, String message) =>
      PdfxApi.codec.encodeMessage(<Object?, Object?>{
        'error': <Object?, Object?>{'code': code, 'message': message},
      });

  Future<ByteData?> _onOpenFile(ByteData? message) async {
    final msg =
        (PdfxApi.codec.decodeMessage(message) as List<Object?>)[0]
            as OpenPathMessage;
    log.add('openDocumentFile(${msg.path})');
    if (!await File(msg.path ?? '').exists()) {
      return _err('pdf_renderer', 'File not found');
    }
    final id = 'doc-${documents.length}';
    documents[id] = _NativeDoc(id, {
      for (var p = 1; p <= pageCount; p++) p: const ui.Size(595, 842),
    });
    return _ok(OpenReply()
      ..id = id
      ..pagesCount = pageCount);
  }

  Future<ByteData?> _onCloseDoc(ByteData? message) async {
    final msg = (PdfxApi.codec.decodeMessage(message) as List<Object?>)[0]
        as IdMessage;
    log.add('closeDocument(${msg.id})');
    final doc = documents[msg.id ?? ''];
    if (doc == null) {
      return _err('pdf_renderer', 'Document not exist');
    }
    if (doc.openPage != null) {
      // Android: PdfRenderer.close() refuses while a page is open.
      return _err('pdf_renderer', 'Current page is not closed');
    }
    doc.closed = true;
    documents.remove(msg.id);
    return _ok(<Object?, Object?>{});
  }

  Future<ByteData?> _onGetPage(ByteData? message) async {
    final msg =
        (PdfxApi.codec.decodeMessage(message) as List<Object?>)[0]
            as GetPageMessage;
    final doc = documents[msg.documentId ?? ''];
    log.add('getPage(${msg.pageNumber})');
    if (doc == null) return _err('pdf_renderer', 'Document not exist');
    final n = msg.pageNumber ?? -1;
    if (n < 1 || n > doc.pageSizes.length) {
      return _err('pdf_renderer', 'Page out of range');
    }
    // *** THE ANDROID RULE: one open page per renderer ***
    if (doc.openPage != null) {
      return _err('pdf_renderer',
          'openPage($n) while page ${doc.openPage} is still open '
          '(android: "Current page is not closed")');
    }
    final pageId = 'page-$n-${DateTime.now().microsecondsSinceEpoch}';
    pages[pageId] = _OpenPage(doc.id, n);
    doc.openPage = n;
    final size = doc.pageSizes[n]!;
    return _ok(GetPageReply()
      ..id = pageId
      ..width = size.width
      ..height = size.height);
  }

  Future<ByteData?> _onRender(ByteData? message) async {
    final msg =
        (PdfxApi.codec.decodeMessage(message) as List<Object?>)[0]
            as RenderPageMessage;
    final n = pages[msg.pageId ?? '']?.pageNumber ?? -1;
    log.add('render($n)');

    // Dispatchers.IO: the reply arrives later (or NEVER when wedged).
    await Future<void>.delayed(const Duration(milliseconds: 20));

    if (wedgeNextRenders > 0) {
      wedgeNextRenders--;
      log.add('render($n) WEDGED — platform reply never delivered');
      return Completer<ByteData?>().future;
    }
    if (failNextRenders > 0) {
      failNextRenders--;
      return _err('pdf_renderer', 'injected transient render failure');
    }
    final page = pages[msg.pageId ?? ''];
    if (page == null) {
      return _err('pdf_renderer', 'Page not exist in pages repository');
    }
    final png = _pngs[n];
    if (png == null) {
      return _err('pdf_renderer', 'no test PNG for page $n');
    }
    tempDir ??= await Directory.systemTemp.createTemp('pdfx_fake');
    final file = File(
        '${tempDir!.path}/render-${DateTime.now().microsecondsSinceEpoch}.png');
    await file.writeAsBytes(png);
    return _ok(RenderPageReply()
      ..width = msg.width
      ..height = msg.height
      ..path = file.path);
  }

  void wedgeNextRrenders_decrement() {
    wedgeNextRenders--;
  }

  Future<ByteData?> _onClosePage(ByteData? message) async {
    final msg = (PdfxApi.codec.decodeMessage(message) as List<Object?>)[0]
        as IdMessage;
    final page = pages[msg.id ?? ''];
    log.add('closePage(${page?.pageNumber})');
    if (page == null) {
      return _err('pdf_renderer', 'Page not exist in pages repository');
    }
    pages.remove(msg.id);
    final doc = documents[page.docId];
    if (doc != null && doc.openPage == page.pageNumber) {
      doc.openPage = null;
    }
    return _ok(<Object?, Object?>{});
  }
}

/// ---------------------------------------------------------------------------
/// Workspace-equivalent harness (the exact _buildCanvasArea structure)
/// ---------------------------------------------------------------------------

class _Harness extends StatefulWidget {
  const _Harness({
    required this.pdf,
    required this.viewport,
    required this.geometry,
    required this.pages,
  });

  final PdfDocumentController pdf;
  final ViewportController viewport;
  final DocGeometry geometry;
  final List<PageMeta> pages;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late final Listenable _repaint;

  @override
  void initState() {
    super.initState();
    _repaint = Listenable.merge([
      widget.viewport,
      widget.pdf,
      widget.pdf.renderTick,
    ]);
  }

  @override
  void dispose() {
    widget.viewport.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      widget.viewport.screenExtent = size;
      widget.viewport.panBounds = widget.geometry.tightBounds;
      widget.viewport.clampToDoc();
      return AnimatedBuilder(
        animation: _repaint,
        builder: (context, _) {
          widget.viewport.panBounds = widget.geometry.tightBounds;
          widget.viewport.clampToDoc();
          final visible = widget.geometry
              .visiblePages(widget.viewport.visibleDocRect(size));
          return Transform(
            transform: widget.viewport.matrix,
            child: Stack(
              children: [
                for (final meta in visible)
                  Builder(builder: (context) {
                    final index = widget.pages.indexOf(meta);
                    final rect = widget.geometry.pageRect(index);
                    return Positioned.fromRect(
                      key: ValueKey('page-${meta.id}'),
                      rect: rect,
                      child: RepaintBoundary(
                        key: ValueKey('rb-page-${meta.id}'),
                        child: Stack(children: [
                          CustomPaint(
                            size: rect.size,
                            painter: PaperPainter(
                              template: TemplateId.blank,
                              paperColor: const Color(0xFFFFFFFF),
                              size: rect.size,
                              paintBackground: true,
                            ),
                          ),
                          PdfPageTile(
                            pdf: widget.pdf,
                            pageNumber: index + 1,
                            scale: widget.viewport.scale,
                            viewport: widget.viewport,
                            pageSize: rect.size,
                          ),
                        ]),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      );
    });
  }
}

Future<Uint8List> _pngForPage(int page) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 48, 64),
    ui.Paint()..color = Color.fromARGB(255, 30 + page * 35 % 200, 90, 210),
  );
  canvas.drawRect(
    Rect.fromLTWH(8.0, 8.0 + page * 4.0, 16, 16),
    ui.Paint()..color = const Color(0xFFFF00FF),
  );
  final img = await recorder.endRecording().toImage(48, 64);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  final bytes = data!.buffer.asUint8List();
  img.dispose();
  return Uint8List.fromList(bytes);
}

/// Interleaves fake-time pumps with real-async windows — mirrors the real
/// app where frames and async work interleave continuously.
Future<void> _settle(WidgetTester tester,
    {int rounds = 12,
    Duration fake = const Duration(milliseconds: 60),
    Duration real = const Duration(milliseconds: 140)}) async {
  for (var r = 0; r < rounds; r++) {
    await tester.pump(fake);
    await tester.runAsync(() async {
      await Future<void>.delayed(real);
    });
  }
  await tester.pump();
}

/// Waits until [page]'s tile boundary paints non-placeholder pixels (or
/// fails after [attempts] settle rounds). Pages mount lazily and each
/// render crosses 5+ async hops — a fixed settle budget raced renders.
Future<Color> _waitForPaint(WidgetTester tester, List<PageMeta> pages,
    int pageIndex) async {
  final rbFinder = find.byKey(ValueKey('rb-page-${pages[pageIndex].id}'));
  var color = const Color(0xFFFFFFFF);
  for (var attempt = 0; attempt < 14; attempt++) {
    if (rbFinder.evaluate().isNotEmpty) {
      final ctx = rbFinder.first.evaluate().first;
      await tester.runAsync(() async {
        final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
        final img = await boundary.toImage(pixelRatio: 1.0);
        final bd =
            await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        img.dispose();
        final px = bd!.buffer.asUint8List();
        final bw = boundary.size.width.floor();
        final bh = boundary.size.height.floor();
        final off = ((bh ~/ 2) * bw + (bw ~/ 2)) * 4;
        color = Color.fromARGB(px[off + 3], px[off], px[off + 1], px[off + 2]);
      });
      if (color != const Color(0xFFFFFFFF)) return color;
    }
    await _settle(tester, rounds: 2);
  }
  return color;
}

List<PageMeta> _pages(int count) => List.generate(
      count,
      (i) => PageMeta(
        id: 1000 + i,
        position: i,
        title: 'p$i',
        bookmarked: false,
        template: TemplateId.blank.index,
        pageSize: PageSizeId.a4Portrait.index,
        paperColor: PAPER_COLORS.first.toARGB32(),
      ),
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  binding.window.devicePixelRatioTestValue = 2.0;
  debugOverrideSupported = true;

  late File pdfFile;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('nanote_e2e');
    pdfFile = File('${dir.path}/doc.pdf');
    await pdfFile.writeAsBytes(List.filled(64, 0x25));
  });

  setUp(() {
    // The REAL Pigeon platform implementation (the production path).
    PdfxPlatform.instance = PdfxPlatformPigeon();
  });

  tearDown(() async {
    PdfDocumentController.renderDeadline = const Duration(seconds: 20);
    PdfDocumentController.docDeadline = const Duration(seconds: 15);
    PdfDocumentController.sizeDeadline = const Duration(seconds: 8);
    PdfDocumentController.callTimeout = const Duration(seconds: 22);
    PdfDocumentController.recoveryDelay =
        const Duration(milliseconds: 1500);
  });

  testWidgets(
      'E2E A: real pigeon pipeline renders ALL pages of a 5-page PDF',
      (tester) async {
    final native = FakeNative(pageCount: 5);
    native.install(binding);
    addTearDown(() => native.uninstall(binding));

    final controller = PdfDocumentController.I;
    final viewport = ViewportController();
    final pages = _pages(5);
    final geo = DocGeometry(pages);

    await tester.runAsync(() async {
      for (var p = 1; p <= 5; p++) {
        native.registerPng(p, await _pngForPage(p));
      }
      expect(await controller.open(pdfFile.path), isTrue);
      expect(controller.pageCount, 5);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 900,
          child: _Harness(
            pdf: controller,
            viewport: viewport,
            geometry: geo,
            pages: pages,
          ),
        ),
      ),
    ));

    viewport.fitPageWidth(geo.pageRect(0), const Size(600, 900),
        animated: false);
    await _settle(tester);

    // Every mounted page must eventually paint real pixels. Pages beyond
    // the viewport are CULLED (lazy loading) — track which mounted.
    final mounted = <int>[];
    for (var i = 0; i < 5; i++) {
      final rbFinder = find.byKey(ValueKey('rb-page-${pages[i].id}'));
      if (rbFinder.evaluate().isEmpty) continue; // culled (off-screen)
      mounted.add(i);
      final color = await _waitForPaint(tester, pages, i);
      expect(color, isNot(const Color(0xFFFFFFFF)),
          reason: 'page ${i + 1} must paint its render');
    }
    expect(mounted, isNotEmpty, reason: 'at least page 1 must be visible');

    // The native log must be balanced and every MOUNTED page rendered
    // (pages beyond the viewport stay unrendered until scrolled to —
    // that is test B's job).
    expect(native.log.join('\n'), isNot(contains('Current page is not closed')));
    for (final i in mounted) {
      expect(native.log.join('\n'), contains('render(${i + 1})'),
          reason: 'native must render mounted page ${i + 1}');
    }
    expect(native.pages, isEmpty, reason: 'no page left open');

    await controller.close();
    await tester.pump(const Duration(seconds: 6));
  }, timeout: const Timeout(Duration(minutes: 6)));

  testWidgets(
      'E2E B: scroll — user pans down; pages 2..5 mount late and render',
      (tester) async {
    final native = FakeNative(pageCount: 5);
    native.install(binding);
    addTearDown(() => native.uninstall(binding));

    final controller = PdfDocumentController.I;
    final viewport = ViewportController();
    final pages = _pages(5);
    final geo = DocGeometry(pages);

    await tester.runAsync(() async {
      for (var p = 1; p <= 5; p++) {
        native.registerPng(p, await _pngForPage(p));
      }
      expect(await controller.open(pdfFile.path), isTrue);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 900,
          child: _Harness(
            pdf: controller,
            viewport: viewport,
            geometry: geo,
            pages: pages,
          ),
        ),
      ),
    ));

    viewport.fitPageWidth(geo.pageRect(0), const Size(600, 900),
        animated: false);
    await _settle(tester, rounds: 6);

    // User pans down through the document (gesture-router style panBy).
    for (var i = 1; i < 5; i++) {
      final target = geo.pageRect(i);
      final destPan = const Size(600, 900).center(Offset.zero) -
          target.center * viewport.scale;
      var guard = 0;
      while ((viewport.pan - destPan).distance > 40 && guard++ < 40) {
        final step = destPan - viewport.pan;
        final move = step.distance > 260
            ? Offset.fromDirection(step.direction, 260)
            : step;
        viewport.panBy(move);
        await tester.pump(const Duration(milliseconds: 16));
      }
      final color = await _waitForPaint(tester, pages, i);
      expect(color, isNot(const Color(0xFFFFFFFF)),
          reason: 'page ${i + 1} must paint after scrolling to it');
    }

    for (var p = 1; p <= 5; p++) {
      expect(native.log.join('\n'), contains('render($p)'),
          reason: 'native must render page $p after scrolling');
    }
    expect(native.log.join('\n'), isNot(contains('Current page is not closed')));

    await controller.close();
    await tester.pump(const Duration(seconds: 6));
  }, timeout: const Timeout(Duration(minutes: 6)));

  testWidgets(
      'E2E C (THE DEVICE BUG): a wedged native render must not kill every '
      'later page — per-document-lock recovery', (tester) async {
    final native = FakeNative(pageCount: 5);
    native.install(binding);
    addTearDown(() => native.uninstall(binding));

    final controller = PdfDocumentController.I;

    // Short deadlines so the watchdog + recovery run in test time.
    PdfDocumentController.renderDeadline = const Duration(milliseconds: 800);
    PdfDocumentController.docDeadline = const Duration(milliseconds: 800);
    PdfDocumentController.sizeDeadline = const Duration(milliseconds: 800);
    PdfDocumentController.callTimeout = const Duration(milliseconds: 1200);
    PdfDocumentController.recoveryDelay =
        const Duration(milliseconds: 200);

    await tester.runAsync(() async {
      for (var p = 1; p <= 5; p++) {
        native.registerPng(p, await _pngForPage(p));
      }
      expect(await controller.open(pdfFile.path), isTrue);

      // Page 1 renders fine (fresh memory — the device symptom).
      final p1 = await controller.pageImage(1, 2.0, priority: true);
      expect(p1, isNotNull, reason: 'page 1 must render');

      // The next native render WEDGES: the platform reply is never
      // delivered (native hang / pre-fix OOM). With the OLD GLOBAL pdfx
      // lock this single call poisoned EVERY pdfx operation forever.
      native.wedgeNextRenders = 1;
      final p2 = await controller.pageImage(2, 2.0, priority: true);
      expect(p2, isNull, reason: 'the wedged render must time out to null');

      // Watchdog fires → queue force-reset → document reopens (fresh
      // per-document lock). Wait that out in real time.
      for (var i = 0; i < 25; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(controller.isOpen, isTrue,
          reason: 'watchdog recovery must reopen the document');

      // THE ASSERTION THAT FAILED WITH THE GLOBAL LOCK: fresh pages must
      // render after recovery (a fresh document ⇒ a fresh lock).
      final p3 = await controller.pageImage(3, 3.0, priority: true);
      expect(p3, isNotNull,
          reason: 'page 3 must render after watchdog recovery — with the '
              'old global pdfx lock this stayed null forever (the '
              '"only page 1 renders" device bug)');
      final p4 = await controller.pageImage(4, 4.0, priority: true);
      expect(p4, isNotNull, reason: 'page 4 must render after recovery too');
    });

    await controller.close();
    await tester.pump(const Duration(seconds: 6));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
