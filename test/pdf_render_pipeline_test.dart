// Reproduction harness for the "only PDF page 1 renders, pages 2+ stay
// blank/gray" report.
//
// Drives the REAL PdfDocumentController + REAL PdfPageTile widgets against a
// high-fidelity fake of pdfx's Android native layer. The fake models the
// ACTUAL native semantics that matter:
//
//  * android.graphics.pdf.PdfRenderer allows only ONE open page at a time —
//    a second openPage while one is open throws IllegalStateException
//    ("Current page is not closed");
//  * renderPage runs on a background coroutine (Dispatchers.IO) — it is
//    ASYNC and does NOT close the page;
//  * getPage/closePage/openDocument run synchronously on the platform
//    thread;
//  * renders produce real decodable PNG bytes (distinct per page).
//
// Any violation the app commits against these semantics shows up as a
// failed render — exactly what the user sees on pages 2+.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfx/pdfx.dart'
    hide PdfDocument, PdfPage, PdfPageImage, PdfPageImageFormat;
import 'package:pdfx/src/renderer/interfaces/document.dart'
    show PdfDocument;
import 'package:pdfx/src/renderer/has_pdf_support.dart'
    show debugOverrideSupported;
import 'package:pdfx/src/renderer/interfaces/page.dart';
import 'package:pdfx/src/renderer/interfaces/platform.dart';
import 'package:pdfx/src/renderer/interfaces/document.dart' show PlatformNotSupportedException;

import 'package:nanote_native/src/controllers/pdf_document_controller.dart';
import 'package:nanote_native/src/controllers/viewport_controller.dart';
import 'package:nanote_native/src/workspace/pdf_page_tile.dart';

/// ---------------------------------------------------------------------------
/// Fake pdfx platform (Android semantics)
/// ---------------------------------------------------------------------------

class FakePdfxException implements Exception {
  FakePdfxException(this.message);
  final String message;
  @override
  String toString() => 'FakePdfxException: $message';
}

class FakePdfPage extends PdfPage {
  FakePdfPage({
    required super.document,
    required String requiredId,
    required super.pageNumber,
    required super.width,
    required super.height,
  })  : _theId = requiredId,
        super(id: requiredId, autoCloseAndroid: false);

  final String _theId;

  @override
  String? get id => _theId;

  @override
  Future<PdfPageImage?> render({
    required double width,
    required double height,
    PdfPageImageFormat format = PdfPageImageFormat.jpeg,
    String? backgroundColor,
    Rect? cropRect,
    int quality = 100,
    bool forPrint = false,
    bool removeTempFile = true,
  }) async {
    final fake = document as FakePdfDocument;
    fake.log.add('render(${pageNumber})');
    if (fake.isClosed) {
      throw FakePdfxException('render on closed document');
    }
    if (isClosed) {
      throw FakePdfxException('render on closed page $pageNumber');
    }
    if (!fake.openPages.containsKey(_theId)) {
      throw FakePdfxException('render on unregistered page $pageNumber');
    }
    fake.platform?.requestedWidths.add(width.round());
    // Simulate the pre-fix native OOM wedge: the platform reply is NEVER
    // delivered — the Dart future never completes.
    if (fake.platform?.wedgeNextRender ?? false) {
      fake.platform!.wedgeNextRender = false;
      fake.log.add('render($pageNumber) WEDGED (never replies)');
      // IMPORTANT: the page stays OPEN natively (the Dart close below
      // never runs because the awaiter is stuck) — exactly the native
      // state after the wedged render.
      return Completer<PdfPageImage?>().future;
    }
    // Simulate the native Dispatchers.IO render coroutine.
    await Future<void>.delayed(const Duration(milliseconds: 6));
    // Optional injected transient failure (pdfium hiccup / OOM bitmap).
    final plat = fake.platform;
    if (plat != null && plat.failNextRenderCount > 0) {
      plat.failNextRenderCount--;
      throw FakePdfxException('injected transient render failure');
    }
    final bytes = fake.pngFor(pageNumber);
    return FakePdfPageImage(
      id: _theId,
      pageNumber: pageNumber,
      width: width.toInt(),
      height: height.toInt(),
      bytes: bytes,
      format: format,
      quality: quality,
    );
  }

  @override
  Future<PdfPageTexture> createTexture() => throw UnimplementedError();

  @override
  Future<void> close() async {
    final fake = document as FakePdfDocument;
    fake.log.add('closePage(${pageNumber})');
    if (isClosed) {
      throw FakePdfxException('page $pageNumber already closed');
    }
    if (!fake.openPages.containsKey(_theId)) {
      throw FakePdfxException('closePage: $pageNumber not open');
    }
    isClosed = true;
    fake.openPages.remove(_theId);
  }
}

class FakePdfPageImage extends PdfPageImage {
  const FakePdfPageImage({
    required super.id,
    required super.pageNumber,
    required super.width,
    required super.height,
    required super.bytes,
    required super.format,
    required super.quality,
  });
}

class FakePdfDocument extends PdfDocument {
  FakePdfDocument({
    required super.sourceName,
    required super.id,
    required super.pagesCount,
    required this.pageSize,
    this.platform,
  });

  final FakePdfxPlatform? platform;

  /// Page size in points (A4 default).
  final Size pageSize;

  /// Page id → page number. Non-empty ⇔ a page is OPEN right now.
  final Map<String, int> openPages = {};

  /// Every native call, in order (for diagnostics).
  final List<String> log = [];

  final Map<int, Uint8List> _pngCache = {};

  Uint8List pngFor(int pageNumber) {
    final cached = _pngCache[pageNumber];
    if (cached != null) return cached;
    throw StateError('no PNG generated for page $pageNumber');
  }

  void registerPng(int pageNumber, Uint8List bytes) =>
      _pngCache[pageNumber] = bytes;

  @override
  Future<void> close() async {
    log.add('closeDocument');
    if (isClosed) {
      throw FakePdfxException('document already closed');
    }
    if (openPages.isNotEmpty) {
      throw FakePdfxException(
          'closeDocument with ${openPages.length} page(s) still open');
    }
    isClosed = true;
  }

  @override
  Future<PdfPage> getPage(int pageNumber,
      {bool autoCloseAndroid = false}) async {
    log.add('getPage($pageNumber)');
    if (isClosed) {
      throw FakePdfxException('getPage on closed document');
    }
    if (pageNumber < 1 || pageNumber > pagesCount) {
      throw RangeError('page $pageNumber');
    }
    // *** THE ANDROID RULE ***
    // android.graphics.pdf.PdfRenderer allows exactly ONE open page per
    // renderer: openPage throws IllegalStateException("Current page is not
    // closed") when a second page opens before the first closed.
    if (openPages.isNotEmpty) {
      final openNo = openPages.values.first;
      throw FakePdfxException(
          'openPage($pageNumber) while page $openNo is still open '
          '(android: "Current page is not closed")');
    }
    final theId = 'page-$pageNumber-${DateTime.now().microsecondsSinceEpoch}';
    final page = FakePdfPage(
      document: this,
      requiredId: theId,
      pageNumber: pageNumber,
      width: pageSize.width,
      height: pageSize.height,
    );
    openPages[theId] = pageNumber;
    return page;
  }
}

class FakePdfxPlatform extends PdfxPlatform {
  final List<FakePdfDocument> documents = [];
  FakePdfDocument? lastDocument;
  int pageCount = 3;
  Size pageSize = const Size(595, 842);

  /// When > 0, the next N render calls fail once each (transient error).
  int failNextRenderCount = 0;

  /// When true, the next render's future NEVER completes — simulates the
  /// pre-fix native OOM wedge (platform reply never delivered).
  bool wedgeNextRender = false;

  /// Render widths requested natively (for memory-cap assertions).
  final List<int> requestedWidths = [];

  @override
  Future<PdfDocument> openData(FutureOr<Uint8List> data,
      {String? password}) async {
    throw UnimplementedError();
  }

  @override
  Future<PdfDocument> openAsset(String name, {String? password}) async {
    throw UnimplementedError();
  }

  @override
  Future<PdfDocument> openFile(String filePath, {String? password}) async {
    final doc = FakePdfDocument(
      sourceName: 'file:$filePath',
      id: 'doc-${documents.length}',
      pagesCount: pageCount,
      pageSize: pageSize,
      platform: this,
    );
    for (var p = 1; p <= pageCount; p++) {
      doc.registerPng(p, await _pngForPage(p));
    }
    documents.add(doc);
    lastDocument = doc;
    return doc;
  }
}

/// Builds a small, valid, visually distinct PNG per page number.
Future<Uint8List> _pngForPage(int page) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 24, 32),
    ui.Paint()..color = Color.fromARGB(255, 40 * page % 256, 100, 200),
  );
  canvas.drawRect(
    Rect.fromLTWH(4.0, 4.0 + page * 2.0, 8, 8),
    ui.Paint()..color = const Color(0xFFFFFFF00),
  );
  final img = await recorder.endRecording().toImage(24, 32);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  final bytes = data!.buffer.asUint8List();
  img.dispose();
  return Uint8List.fromList(bytes);
}

/// ---------------------------------------------------------------------------
/// Harness
/// ---------------------------------------------------------------------------

Future<void> _pumpTiles(
  WidgetTester tester, {
  required FakePdfxPlatform platform,
  required PdfDocumentController controller,
  required ViewportController viewport,
  int pageCount = 3,
  double scale = 1.0,
  Map<int, GlobalKey>? tileKeys,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: 900,
          child: Stack(
            children: [
              for (var i = 0; i < pageCount; i++)
                Positioned.fromRect(
                  rect: Rect.fromLTWH(0, 850.0 * i, 595, 842),
                  child: RepaintBoundary(
                    key: tileKeys?[i],
                    child: PdfPageTile(
                      pdf: controller,
                      pageNumber: i + 1,
                      scale: scale,
                      viewport: viewport,
                      pageSize: const Size(595, 842),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Interleaves fake-time pumps (advance frozen timers: retry backoffs,
/// render latencies initiated during pumpWidget) with real-async windows
/// (complete image decodes that need the real event loop). This mirrors
/// the real app: frames and async work interleave continuously.
Future<void> _settle(WidgetTester tester,
    {int rounds = 14,
    Duration fake = const Duration(milliseconds: 60),
    Duration real = const Duration(milliseconds: 120)}) async {
  for (var r = 0; r < rounds; r++) {
    await tester.pump(fake);
    await tester.runAsync(() async {
      await Future<void>.delayed(real);
    });
  }
  await tester.pump();
}

void main() {
  setUp(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.window.devicePixelRatioTestValue = 2.0;
    // The vendored pdfx test seam: the support check passes on any host so
    // the REAL controller can run against our fake platform.
    debugOverrideSupported = true;
  });

  testWidgets('all pages of a multi-page PDF render (pages 2+ bug)',
      (tester) async {
    final platform = FakePdfxPlatform()..pageCount = 3;
    PdfxPlatform.instance = platform;

    final controller = PdfDocumentController.I;
    final viewport = ViewportController();
    addTearDown(() async {
      await controller.close();
      viewport.dispose();
    });

    // Tiles mount first (doc still closed → white placeholders), then the
    // document opens inside the SAME real-async window so renders + decodes
    // complete.
    final tileKeys = <int, GlobalKey>{};
    for (var i = 0; i < 3; i++) {
      tileKeys[i] = GlobalKey(debugLabel: 'tile-$i');
    }
    await _pumpTiles(tester,
        platform: platform,
        controller: controller,
        viewport: viewport,
        tileKeys: tileKeys);

    var opened = false;
    await tester.runAsync(() async {
      opened = await controller.open('/tmp/fake.pdf');
      expect(opened, isTrue, reason: 'document must open');
      expect(controller.pageCount, 3);
    });
    await _settle(tester);

    // Inspect what the tiles PAINTED: sample the center pixel of each tile
    // via its RepaintBoundary. White (255,255,255) = still the placeholder;
    // our fake renders a distinct blue per page (40*p, 100, 200).
    final tiles = tester.widgetList<PdfPageTile>(find.byType(PdfPageTile));
    expect(tiles.length, 3);
    final painted = <int, Color>{};
    for (var i = 0; i < 3; i++) {
      final ctx = tileKeys[i]!.currentContext!;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
      var color = const Color(0xFFFFFFFF);
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1.0);
        final w = img.width;
        final h = img.height;
        final bd =
            await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        img.dispose();
        final x = (w / 2).floor();
        final y = (h / 2).floor();
        final off = (y * w + x) * 4;
        final px = bd!.buffer.asUint8List();
        color = Color.fromARGB(px[off + 3], px[off], px[off + 1], px[off + 2]);
      });
      painted[i] = color;
    }
    for (var i = 0; i < 3; i++) {
      expect(
        painted[i],
        isNot(const Color(0xFFFFFFFF)),
        reason:
            'page ${i + 1} must paint a rendered image, not the placeholder',
      );
    }

    // The native log must show balanced open/close and no Android-rule
    // violations.
    final doc = platform.lastDocument!;
    // ignore: avoid_print
    print('--- native log ---\n${doc.log.join('\n')}');
    // ignore: avoid_print
    print('open pages at end: ${doc.openPages}');
    expect(doc.openPages, isEmpty,
        reason: 'no page may stay open after settling');
    expect(
      doc.log.join('\n'),
      isNot(contains('Current page is not closed')),
      reason: 'the app must never hit the one-open-page native rule',
    );

    // Expire the controller's deferred-dispose grace timers so the test
    // binding sees no pending timers at teardown.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets(
      'scroll-late mount: page 1 renders, pages 2/3 mount later and render',
      (tester) async {
    final platform = FakePdfxPlatform()..pageCount = 3;
    PdfxPlatform.instance = platform;

    final controller = PdfDocumentController.I;
    final viewport = ViewportController();
    addTearDown(() async {
      await controller.close();
      viewport.dispose();
    });

    // Only page 1 mounted initially (below-the-fold pages mount on scroll).
    final keys = <int, GlobalKey>{};
    for (var i = 0; i < 3; i++) {
      keys[i] = GlobalKey(debugLabel: 'tile-$i');
    }
    await _pumpTiles(tester,
        platform: platform,
        controller: controller,
        viewport: viewport,
        pageCount: 1,
        tileKeys: keys);

    await tester.runAsync(() async {
      final ok = await controller.open('/tmp/fake.pdf');
      expect(ok ?? false, isTrue);
    });
    await _settle(tester);

    // User scrolls: pages 2 and 3 mount NOW.
    await _pumpTiles(tester,
        platform: platform,
        controller: controller,
        viewport: viewport,
        pageCount: 3,
        tileKeys: keys);
    await _settle(tester);

    for (var i = 0; i < 3; i++) {
      final boundary =
          keys[i]!.currentContext!.findRenderObject() as RenderRepaintBoundary;
      var color = const Color(0xFFFFFFFF);
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1.0);
        final w = img.width, h = img.height;
        final bd =
            await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        img.dispose();
        final px = bd!.buffer.asUint8List();
        final off = ((h ~/ 2) * w + (w ~/ 2)) * 4;
        color = Color.fromARGB(px[off + 3], px[off], px[off + 1], px[off + 2]);
      });
      expect(
        color,
        isNot(const Color(0xFFFFFFFF)),
        reason: 'late-mounted page ${i + 1} must render',
      );
    }

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('zoom re-render: tiles re-request at the new bucket and repaint',
      (tester) async {
    final platform = FakePdfxPlatform()..pageCount = 3;
    PdfxPlatform.instance = platform;

    final controller = PdfDocumentController.I;
    final viewport = ViewportController();
    addTearDown(() async {
      await controller.close();
      viewport.dispose();
    });

    final keys = <int, GlobalKey>{};
    for (var i = 0; i < 3; i++) {
      keys[i] = GlobalKey(debugLabel: 'tile-$i');
    }
    await _pumpTiles(tester,
        platform: platform,
        controller: controller,
        viewport: viewport,
        scale: 1.0,
        tileKeys: keys);

    await tester.runAsync(() async {
      await controller.open('/tmp/fake.pdf');
    });
    await _settle(tester);

    // The user zooms to 160% and the gesture settles: the workspace rebuilds
    // tiles with the new scale and bumps viewport.renderTick.
    await _pumpTiles(tester,
        platform: platform,
        controller: controller,
        viewport: viewport,
        scale: 1.6,
        tileKeys: keys);
    await tester.runAsync(() async {
      viewport.endInteraction(); // fires renderTick after 220ms
    });
    await _settle(tester);

    for (var i = 0; i < 3; i++) {
      final boundary =
          keys[i]!.currentContext!.findRenderObject() as RenderRepaintBoundary;
      var color = const Color(0xFFFFFFFF);
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1.0);
        final w = img.width, h = img.height;
        final bd =
            await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        img.dispose();
        final px = bd!.buffer.asUint8List();
        final off = ((h ~/ 2) * w + (w ~/ 2)) * 4;
        color = Color.fromARGB(px[off + 3], px[off], px[off + 1], px[off + 2]);
      });
      expect(
        color,
        isNot(const Color(0xFFFFFFFF)),
        reason: 'page ${i + 1} must repaint after zoom re-render',
      );
    }

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets(
      'pages-manager thumbnails do not starve or break tile renders',
      (tester) async {
    final platform = FakePdfxPlatform()..pageCount = 6;
    PdfxPlatform.instance = platform;

    final controller = PdfDocumentController.I;
    final viewport = ViewportController();
    addTearDown(() async {
      await controller.close();
      viewport.dispose();
    });

    final keys = <int, GlobalKey>{};
    for (var i = 0; i < 6; i++) {
      keys[i] = GlobalKey(debugLabel: 'tile-$i');
    }
    await _pumpTiles(tester,
        platform: platform,
        controller: controller,
        viewport: viewport,
        pageCount: 6,
        tileKeys: keys);

    await tester.runAsync(() async {
      await controller.open('/tmp/fake.pdf');
      // The pages sheet opens: 6 thumbnails request pageImage(n, 0.4)
      // (non-priority) WHILE the visible tiles request priority renders.
      for (var n = 1; n <= 6; n++) {
        // ignore: unawaited_futures
        controller.pageImage(n, 0.4);
      }
    });
    // Every thumbnail must resolve to an image.
    await tester.runAsync(() async {
      for (var n = 1; n <= 6; n++) {
        final bmp = await controller.pageImage(n, 0.4);
        expect(bmp, isNotNull, reason: 'thumbnail $n must render');
      }
    });
    await _settle(tester);

    for (var i = 0; i < 6; i++) {
      final boundary =
          keys[i]!.currentContext!.findRenderObject() as RenderRepaintBoundary;
      var color = const Color(0xFFFFFFFF);
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1.0);
        final w = img.width, h = img.height;
        final bd =
            await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        img.dispose();
        final px = bd!.buffer.asUint8List();
        final off = ((h ~/ 2) * w + (w ~/ 2)) * 4;
        color = Color.fromARGB(px[off + 3], px[off], px[off + 1], px[off + 2]);
      });
      expect(
        color,
        isNot(const Color(0xFFFFFFFF)),
        reason: 'page ${i + 1} tile must render despite the thumbnail storm',
      );
    }

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('transient native render failures recover via retry',
      (tester) async {
    final platform = FakePdfxPlatform()..pageCount = 3;
    PdfxPlatform.instance = platform;

    final controller = PdfDocumentController.I;
    final viewport = ViewportController();
    addTearDown(() async {
      await controller.close();
      viewport.dispose();
    });

    final keys = <int, GlobalKey>{};
    for (var i = 0; i < 3; i++) {
      keys[i] = GlobalKey(debugLabel: 'tile-$i');
    }
    await _pumpTiles(tester,
        platform: platform,
        controller: controller,
        viewport: viewport,
        tileKeys: keys);

    // Fail the FIRST render attempts natively (transient pdfium error),
    // then succeed.
    await tester.runAsync(() async {
      platform.failNextRenderCount = 2;
      await controller.open('/tmp/fake.pdf');
    });
    await _settle(tester, rounds: 24);

    for (var i = 0; i < 3; i++) {
      final boundary =
          keys[i]!.currentContext!.findRenderObject() as RenderRepaintBoundary;
      var color = const Color(0xFFFFFFFF);
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1.0);
        final w = img.width, h = img.height;
        final bd =
            await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        img.dispose();
        final px = bd!.buffer.asUint8List();
        final off = ((h ~/ 2) * w + (w ~/ 2)) * 4;
        color = Color.fromARGB(px[off + 3], px[off], px[off + 1], px[off + 2]);
      });
      expect(
        color,
        isNot(const Color(0xFFFFFFFF)),
        reason: 'page ${i + 1} must recover after transient failures',
      );
    }

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('dispose→reopen race: close() then immediate open() keeps '
      'rendering (single-session recovery)', (tester) async {
    final platform = FakePdfxPlatform()..pageCount = 3;
    PdfxPlatform.instance = platform;

    final controller = PdfDocumentController.I;
    final viewport = ViewportController();
    addTearDown(() async {
      await controller.close();
      viewport.dispose();
    });

    await tester.runAsync(() async {
      await controller.open('/tmp/fake.pdf');
    });
    await _settle(tester);

    // Workspace dispose fires close() unawaited, then the next workspace
    // opens immediately (user backs out and re-enters quickly). Both calls
    // share one guarded zone: the controller's task queue continues its
    // drain chain in the zone the tasks were scheduled from.
    await tester.runAsync(() async {
      // ignore: unawaited_futures
      controller.close();
      await controller.open('/tmp/fake.pdf');
    });
    await _settle(tester);

    // After the race the controller must still render every page.
    await tester.runAsync(() async {
      for (var n = 1; n <= 3; n++) {
        final bmp = await controller.pageImage(n, 2.0);
        expect(bmp, isNotNull, reason: 'page $n must render after the race');
      }
    });

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets(
      'THE BUG: a never-completing native render (pre-fix OOM wedge) must '
      'not kill the pipeline — watchdog recovers and later pages render',
      (tester) async {
    final platform = FakePdfxPlatform()..pageCount = 4;
    PdfxPlatform.instance = platform;

    final controller = PdfDocumentController.I;
    final viewport = ViewportController();
    addTearDown(() async {
      // Restore production deadlines before closing.
      PdfDocumentController.renderDeadline =
          const Duration(seconds: 20);
      PdfDocumentController.docDeadline = const Duration(seconds: 15);
      PdfDocumentController.sizeDeadline = const Duration(seconds: 8);
      PdfDocumentController.callTimeout = const Duration(seconds: 22);
      PdfDocumentController.recoveryDelay =
          const Duration(milliseconds: 1500);
      await controller.close();
      viewport.dispose();
    });

    // Short deadlines so the watchdog fires in milliseconds, not seconds.
    PdfDocumentController.renderDeadline = const Duration(milliseconds: 700);
    PdfDocumentController.docDeadline = const Duration(milliseconds: 700);
    PdfDocumentController.sizeDeadline = const Duration(milliseconds: 700);
    PdfDocumentController.callTimeout = const Duration(milliseconds: 900);
    PdfDocumentController.recoveryDelay = const Duration(milliseconds: 100);

    final keys = <int, GlobalKey>{};
    for (var i = 0; i < 3; i++) {
      keys[i] = GlobalKey(debugLabel: 'tile-$i');
    }
    await _pumpTiles(tester,
        platform: platform,
        controller: controller,
        viewport: viewport,
        tileKeys: keys);

    await tester.runAsync(() async {
      await controller.open('/tmp/fake.pdf');
      // Page 1 renders fine (memory still fresh)...
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });

    // ...then a FRESH page's native render WEDGES (the pre-fix OOM: the
    // platform reply is never delivered; the future never completes).
    // v2.6.1: with the 1080px cap every bucket of an A4 page maps to one
    // cache key, so the wedged page must be one the tiles never rendered
    // (page 4) — the caller-side timeout unblocks the request, the
    // watchdog resets the queue and the document reopens.
    await tester.runAsync(() async {
      platform.wedgeNextRender = true;
      final bmp = await controller.pageImage(4, 4.0);
      expect(bmp, isNull, reason: 'a wedged render must time out to null');
      // Let the watchdog + recovery reopen complete in real time.
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });

    // The controller must be open again and render EVERY page.
    expect(controller.isOpen, isTrue,
        reason: 'watchdog recovery must reopen the document');
    await tester.runAsync(() async {
      for (var n = 1; n <= 4; n++) {
        final bmp = await controller.pageImage(n, 4.0);
        expect(bmp, isNotNull,
            reason: 'page $n must render after watchdog recovery');
      }
    });
    await _settle(tester);

    // The tiles must paint again after recovery.
    for (var i = 0; i < 3; i++) {
      final boundary =
          keys[i]!.currentContext!.findRenderObject() as RenderRepaintBoundary;
      var color = const Color(0xFFFFFFFF);
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1.0);
        final w = img.width, h = img.height;
        final bd =
            await img.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        img.dispose();
        final px = bd!.buffer.asUint8List();
        final off = ((h ~/ 2) * w + (w ~/ 2)) * 4;
        color = Color.fromARGB(px[off + 3], px[off], px[off + 1], px[off + 2]);
      });
      expect(
        color,
        isNot(const Color(0xFFFFFFFF)),
        reason: 'page ${i + 1} tile must repaint after watchdog recovery',
      );
    }

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('memory budget: render widths are capped at 1080px',
      (tester) async {
    final platform = FakePdfxPlatform()..pageCount = 2;
    PdfxPlatform.instance = platform;

    final controller = PdfDocumentController.I;
    final viewport = ViewportController();
    addTearDown(() async {
      await controller.close();
      viewport.dispose();
    });

    await tester.runAsync(() async {
      await controller.open('/tmp/fake.pdf');
      // Extreme zoom hints (8x on a 3x-dpr display would ask for 14,000px).
      for (var n = 1; n <= 2; n++) {
        await controller.pageImage(n, 24.0, priority: true);
      }
    });
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();

    // ignore: avoid_print
    print('requested widths: ${platform.requestedWidths}');
    expect(platform.requestedWidths, isNotEmpty);
    for (final w in platform.requestedWidths) {
      expect(w, lessThanOrEqualTo(1080),
          reason: 'every native render must respect the v2.6.1 1080px '
              'memory cap');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
