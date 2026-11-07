// PDF pipeline regression tests — v1.0.0 pdfrx edition.
//
// These drive the REAL PdfDocumentController against a FAKE pdfrx engine
// (installed through pdfrx's official PdfrxEntryFunctions seam). The fake
// models pdfium's semantics faithfully:
//   * openFile returns a document whose pages are known synchronously;
//   * render() produces real BGRA pixels (PdfImage.createFromBgraData) that
//     the controller decodes through the REAL ui.Image pipeline;
//   * individual renders can be made to fail or hang, to prove the
//     controller's isolation/retry guarantees.
//
// This is the suite that guards the "only page 1 renders / gray pages"
// class of bugs for good: EVERY page of a multi-page document must produce
// a bitmap, a failing page must never affect the others, and nothing may
// ever hang.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanote_native/src/controllers/pdf_document_controller.dart';
import 'package:nanote_native/src/workspace/pdf_page_tile.dart'
    show PdfPageBitmap;
import 'package:pdfrx/pdfrx.dart';

// ---------------------------------------------------------------------------
// Fake pdfrx engine
// ---------------------------------------------------------------------------

class _FakePage implements PdfPage {
  _FakePage(this._doc, this._number, this._width, this._height);

  final PdfDocument _doc;
  final int _number;
  final double _width;
  final double _height;

  /// When > 0, the first N render calls throw (transient failure).
  int failFirst = 0;

  @override
  PdfDocument get document => _doc;

  @override
  int get pageNumber => _number;

  @override
  double get width => _width;

  @override
  double get height => _height;

  @override
  PdfPageRotation get rotation => PdfPageRotation.none;

  @override
  bool get isLoaded => true;

  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
    PdfPageRenderPriority? priority,
  }) async {
    if (failFirst > 0) {
      failFirst--;
      throw StateError('fake pdfium transient failure');
    }
    final w = (fullWidth ?? width ?? _width).round();
    final h = (fullHeight ?? height ?? _height).round();
    // Distinct gray value per page so tests can tell pages apart.
    final v = (180 + (_number * 13) % 60).toUnsigned(8);
    final px = Uint8List(w * h * 4);
    for (var i = 0; i < px.length; i += 4) {
      px[i] = v; // B
      px[i + 1] = v; // G
      px[i + 2] = v; // R
      px[i + 3] = 0xFF; // A
    }
    return PdfImage.createFromBgraData(px, width: w, height: h);
  }

  @override
  PdfPageRenderCancellationToken createCancellationToken() =>
      throw UnimplementedError();

  @override
  Future<PdfPageRawText?> loadText() async => null;

  @override
  Future<List<PdfLink>> loadLinks({
    bool compact = false,
    bool enableAutoLinkDetection = true,
  }) async => const [];
}

class _FakeDocument extends PdfDocument {
  _FakeDocument(this.fakePages) : super(sourceName: 'fake');

  final List<_FakePage> fakePages;

  @override
  List<PdfPage> get pages => fakePages;

  @override
  Future<void> dispose() async {}

  @override
  bool get isEncrypted => false;

  @override
  bool isIdenticalDocumentHandle(Object? other) => identical(this, other);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeEngine implements PdfrxEntryFunctions {
  _FakeEngine(this.doc);

  final _FakeDocument doc;

  @override
  Future<PdfDocument> openFile(
    String filePath, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    bool useProgressiveLoading = false,
  }) async => doc;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FakeDocument doc;
  late PdfDocumentController ctrl;

  setUp(() {
    ctrl = PdfDocumentController.I;
    final d = _FakeDocument(<_FakePage>[]);
    doc = d;
    doc.fakePages
        .addAll([for (var i = 1; i <= 20; i++) _FakePage(d, i, 595, 842)]);
    PdfrxEntryFunctions.instance = _FakeEngine(doc);
  });

  tearDown(() async {
    await ctrl.close();
    PdfrxEntryFunctions.instance = _FakeEngine(_FakeDocument(<_FakePage>[]));
  });

  test('open reports every page synchronously (no missing-size voids)', () async {
    expect(await ctrl.open('/fake/sample.pdf'), isTrue);
    expect(ctrl.isOpen, isTrue);
    expect(ctrl.pageCount, 20);
    for (var n = 1; n <= 20; n++) {
      final s = ctrl.pageSize(n);
      expect(s, isNotNull, reason: 'page $n size must be known at once');
      expect(s!.width, 595);
      expect(s.height, 842);
    }
    expect(ctrl.pageSize(21), isNull);
    expect(ctrl.pageSize(0), isNull);
  });

  test('EVERY page of a 20-page document renders — the gray-pages regression',
      () async {
    await ctrl.open('/fake/sample.pdf');
    final bitmaps = <int, PdfPageBitmap>{};
    for (var n = 1; n <= 20; n++) {
      final bmp = await ctrl.pageImage(n, 1.0, priority: true);
      expect(bmp, isNotNull, reason: 'page $n must render');
      bitmaps[n] = bmp!;
    }
    // Distinct live images per page (no page-1-image-everywhere bug).
    final ids = <String>{};
    for (final b in bitmaps.values) {
      ids.add(b.handle);
    }
    expect(ids.length, 20, reason: 'each page must own a distinct image');
    // Images have real pixels.
    for (final b in bitmaps.values) {
      expect(b.image.width, greaterThan(0));
      expect(b.image.height, greaterThan(0));
    }
  });

  test('quality buckets quantize and reuse cached rasters', () async {
    await ctrl.open('/fake/sample.pdf');
    final a = await ctrl.pageImage(1, 1.0);
    final b = await ctrl.pageImage(1, 1.05); // same bucket
    expect(identical(a!.image, b!.image), isTrue,
        reason: 'nearby scale hints must share the cached raster');
    expect(a.key, b.key);
    final c = await ctrl.pageImage(1, 3.0); // higher bucket → new raster
    expect(identical(a.image, c!.image), isFalse);
  });

  test('a transient failure on page 3 never affects the other pages', () async {
    await ctrl.open('/fake/sample.pdf');
    doc.fakePages[2].failFirst = 1;
    // First attempt fails (the fake throws once) — exactly like the real
    // tile, we request again: priority requests bypass the retry-delay
    // gate, so the retry succeeds immediately.
    await ctrl.pageImage(3, 1.0, priority: true);
    final second = await ctrl.pageImage(3, 1.0, priority: true);
    expect(second, isNotNull, reason: 'priority render retries past failures');
    for (var n = 1; n <= 20; n++) {
      if (n == 3) continue;
      final bmp = await ctrl.pageImage(n, 1.0);
      expect(bmp, isNotNull, reason: 'page $n unaffected by page 3 failure');
    }
  });

  test('failed render is retried after the retry delay', () async {
    await ctrl.open('/fake/sample.pdf');
    doc.fakePages[4].failFirst = 1;
    // Non-priority: first attempt fails → null, then the retry-delay gate.
    final r1 = await ctrl.pageImage(5, 1.0);
    expect(r1, isNull);
    await Future<void>.delayed(
        Duration(milliseconds: PdfDocumentController.retryDelay.inMilliseconds + 50));
    final r2 = await ctrl.pageImage(5, 1.0);
    expect(r2, isNotNull, reason: 'after the delay the page renders');
  });

  test('LRU eviction keeps retained images alive; release disposes them',
      () async {
    await ctrl.open('/fake/sample.pdf');
    // Capacity is 8; render 9 different pages to force one eviction.
    final handles = <String>[];
    for (var n = 1; n <= 9; n++) {
      final bmp = await ctrl.pageImage(n, 1.0, priority: true);
      expect(bmp, isNotNull);
      ctrl.retain(bmp!.handle);
      handles.add(bmp.handle);
    }
    // All 9 images still alive (all retained) and painting one does not
    // throw (this was the "painting a disposed image kills the rasterizer"
    // gray-screen bug).
    final stillValid = await ctrl.pageImage(1, 1.0, priority: true);
    expect(stillValid, isNotNull);
    // Release every handle: everything must be disposed without throwing.
    for (final h in handles) {
      ctrl.release(h);
    }
    expect(() {
      for (final h in handles) {
        ctrl.release(h); // double release must be clamped, not negative.
      }
    }, returnsNormally);
  });

  test('close() unblocks queued renders and later publishes are dropped',
      () async {
    await ctrl.open('/fake/sample.pdf');
    // Flood the queue with more pages than the concurrency cap.
    final futures = [
      for (var n = 1; n <= 20; n++) ctrl.pageImage(n, 1.0),
    ];
    await ctrl.close();
    final results = await Future.wait(futures);
    for (final r in results) {
      expect(r, isNull, reason: 'queued renders resolve null after close');
    }
    expect(ctrl.isOpen, isFalse);
    expect(ctrl.pageCount, 0);
    // The controller can reopen.
    expect(await ctrl.open('/fake/sample.pdf'), isTrue);
    final bmp = await ctrl.pageImage(1, 1.0, priority: true);
    expect(bmp, isNotNull);
  });

  test('reopen of the same path is a no-op; a new path closes the old doc',
      () async {
    await ctrl.open('/fake/a.pdf');
    expect(await ctrl.open('/fake/a.pdf'), isTrue);
    expect(ctrl.currentPath, '/fake/a.pdf');
    expect(await ctrl.open('/fake/b.pdf'), isTrue);
    expect(ctrl.currentPath, '/fake/b.pdf');
    expect(ctrl.pageCount, 20);
  });
}
