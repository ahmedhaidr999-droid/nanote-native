import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'package:pdfx/src/renderer/get_pixels/main.dart';
import 'package:pdfx/src/renderer/interfaces/document.dart';
import 'package:pdfx/src/renderer/interfaces/page.dart';
import 'package:pdfx/src/renderer/interfaces/platform.dart';
import 'package:pdfx/src/renderer/io/pigeon.dart';
import 'package:synchronized/synchronized.dart';
import 'package:universal_platform/universal_platform.dart';

// NANOTE FIX (fork hardening): upstream used ONE GLOBAL lock for every
// pdfx call in the process. A single platform call that never completes
// (native wedge, engine teardown mid-call, OOM crash pre-Throwable-fix)
// held that lock FOREVER - every subsequent pdfx operation app-wide
// queued behind it and never ran, which is exactly the 'only page 1
// renders, every other page stays blank' failure. Android's real
// constraint is per-PdfRenderer (one open page per document), so the
// lock scope is now PER DOCUMENT: a wedged call can only ever block its
// own document, and the app-level controller replaces that document on
// watchdog recovery - after which rendering continues on a fresh lock.
final _api = PdfxApi();

class PdfxPlatformPigeon extends PdfxPlatform {
  PdfDocument _open(OpenReply result, String sourceName) => PdfDocumentPigeon._(
        sourceName: sourceName,
        id: result.id!,
        pagesCount: result.pagesCount!,
      );

  /// Open PDF document from filesystem path
  @override
  Future<PdfDocument> openFile(String filePath, {String? password}) async {
    if (UniversalPlatform.isWeb) {
      throw PlatformNotSupportedException();
    }
    return _open(
      await _api.openDocumentFile(OpenPathMessage()
        ..path = filePath
        ..password = password),
      'file:$filePath',
    );
  }

  /// Open PDF document from application assets
  @override
  Future<PdfDocument> openAsset(String name, {String? password}) async => _open(
        await _api.openDocumentAsset(OpenPathMessage()
          ..path = name
          ..password = password),
        'asset:$name',
      );

  /// Open PDF file from memory (Uint8List)
  @override
  Future<PdfDocument> openData(FutureOr<Uint8List> data,
          {String? password}) async =>
      _open(
        await _api.openDocumentData(OpenDataMessage()
          ..data = await data
          ..password = password),
        'memory:binary',
      );
}

/// Handles PDF document loaded on memory.
class PdfDocumentPigeon extends PdfDocument {
  PdfDocumentPigeon._({
    required super.sourceName,
    required super.id,
    required super.pagesCount,
  }) : _pages = List<PdfPage?>.filled(pagesCount, null);

  final List<PdfPage?> _pages;

  /// NANOTE FIX (fork hardening): per-document serialization (Android
  /// allows exactly ONE open page per PdfRenderer). See the note above
  /// the global lock this replaces.
  final Lock _docLock = Lock();

  @override
  Future<void> close() => _docLock.synchronized(() async {
        // NANOTE FIX: idempotent close. Upstream THREW on a second close
        // and marked the doc closed BEFORE the native call - a native
        // close failure (Android refuses with a page still open after a
        // wedged render) left the doc leaked natively and every later
        // close() throwing forever. Now: closing twice is a no-op, and a
        // native close error is swallowed - the caller replaces the
        // document anyway (watchdog recovery), and close() can never
        // wedge the pipeline again.
        if (isClosed) return;
        isClosed = true;
        try {
          return await _api.closeDocument(IdMessage()..id = id);
        } catch (_) {
          // Native renderer refused/failed - this instance is dead to us
          // either way; never propagate, never block the caller.
        }
      });

  /// Get page object. The first page is 1.
  @override
  Future<PdfPage> getPage(
    int pageNumber, {
    bool autoCloseAndroid = false,
  }) async {
    if (pageNumber < 1 || pageNumber > pagesCount) {
      throw RangeError.range(pageNumber, 1, pagesCount);
    }
    return _docLock.synchronized<PdfPage>(() async {
      if (isClosed) {
        throw PdfDocumentAlreadyClosedException();
      }
      var page = _pages[pageNumber - 1];
      if (page == null) {
        final result = await _api.getPage(
          GetPageMessage()
            ..documentId = id
            ..pageNumber = pageNumber
            ..autoCloseAndroid = autoCloseAndroid,
        );

        page = PdfPagePigeon(
          document: this,
          id: result.id,
          pageNumber: pageNumber,
          width: result.width!,
          height: result.height!,
          autoCloseAndroid: autoCloseAndroid,
        );
      }

      return page;
    });
  }

  @override
  bool operator ==(Object other) =>
      other is PdfDocumentPigeon && other.id == id;

  @override
  int get hashCode => identityHashCode(id);
}

class PdfPagePigeon extends PdfPage {
  PdfPagePigeon({
    required super.document,
    required super.id,
    required super.pageNumber,
    required super.width,
    required super.height,
    required bool autoCloseAndroid,
  }) : super(
          autoCloseAndroid: autoCloseAndroid,
        ) {
    if (autoCloseAndroid) {
      isClosed = true;
    }
  }

  @override
  Future<PdfPageImage?> render({
    required double width,
    required double height,
    PdfPageImageFormat format = PdfPageImageFormat.png,
    String? backgroundColor,
    Rect? cropRect,
    int quality = 100,
    bool forPrint = false,
    @visibleForTesting bool removeTempFile = true,
  }) =>
      (document as PdfDocumentPigeon)._docLock
          .synchronized<PdfPageImage?>(() async {
        if (document.isClosed) {
          throw PdfDocumentAlreadyClosedException();
        } else if (isClosed) {
          throw PdfPageAlreadyClosedException();
        }

        return PdfPageImagePigeon.render(
          pageId: id,
          pageNumber: pageNumber,
          width: width,
          height: height,
          format: format,
          backgroundColor: backgroundColor,
          crop: cropRect,
          quality: quality,
          forPrint: forPrint,
          removeTempFile: removeTempFile,
        );
      });

  @override
  Future<PdfPageTexture> createTexture() async {
    final result = await _api.registerTexture();

    return PdfPageTexturePigeon(
      id: result.id!,
      pageId: id,
      pageNumber: pageNumber,
    );
  }

  @override
  Future<void> close() =>
      (document as PdfDocumentPigeon)._docLock.synchronized(() async {
        // NANOTE FIX: idempotent page close (upstream threw on double
        // close; a failed close left the page marked closed natively
        // while the error propagated - both worse than a quiet no-op).
        if (isClosed) return;
        isClosed = true;
        try {
          return await _api.closePage(IdMessage()..id = id);
        } catch (_) {
          // Page already gone natively - nothing to do.
        }
      });

  @override
  bool operator ==(Object other) =>
      other is PdfPagePigeon &&
      other.document.hashCode == document.hashCode &&
      other.pageNumber == pageNumber;

  @override
  int get hashCode => document.hashCode ^ pageNumber;
}

class PdfPageImagePigeon extends PdfPageImage {
  PdfPageImagePigeon({
    required super.id,
    required super.pageNumber,
    required super.width,
    required super.height,
    required super.bytes,
    required super.format,
    required super.quality,
  });

  /// Render a full image of specified PDF file.
  ///
  /// [width], [height] specify resolution to render in pixels.
  /// As default PNG uses transparent background. For change it you can set
  /// [backgroundColor] property like a hex string ('#000000')
  /// [format] - image type, all types can be seen here [PdfPageImageFormat]
  /// [crop] - render only the necessary part of the image
  /// [quality] - hint to the JPEG and WebP compression algorithms (0-100)
  static Future<PdfPageImage?> render({
    required String? pageId,
    required int pageNumber,
    required double width,
    required double height,
    required PdfPageImageFormat format,
    required String? backgroundColor,
    required Rect? crop,
    required int quality,
    required bool forPrint,
    required bool removeTempFile,
  }) async {
    if (format == PdfPageImageFormat.webp &&
        (UniversalPlatform.isIOS ||
            UniversalPlatform.isWindows ||
            UniversalPlatform.isMacOS)) {
      throw PdfNotSupportException(
        'PDF Renderer on IOS & Windows, MacOs platforms '
        'do not support WEBP format',
      );
    }

    backgroundColor ??=
        (format == PdfPageImageFormat.jpeg) ? '#FFFFFF' : '#00FFFFFF';

    final result = await _api.renderPage(RenderPageMessage()
      ..pageId = pageId
      ..width = width.toInt()
      ..height = height.toInt()
      ..format = format.value
      ..backgroundColor = backgroundColor
      ..crop = crop != null
      ..cropX = crop?.left.toInt()
      ..cropY = crop?.top.toInt()
      ..cropWidth = crop?.width.toInt()
      ..cropHeight = crop?.height.toInt()
      ..quality = quality
      ..forPrint = forPrint);

    final retWidth = result.width, retHeight = result.height;
    late final Uint8List pixels;
    // NANOTE FIX (fork hardening): choose the pixel source by the REPLY'S
    // SHAPE, not by the host platform. The Android/iOS/macOS native side
    // replies with a temp-file PATH (no data); the Windows native side
    // replies with in-memory data (no path). Branching on the platform made
    // every render die with a null-check when the reply shape didn't match
    // the host (an Android-shaped reply consumed off-device - exactly what
    // the pipeline tests need to do - crashed on "bytes!" and renders
    // failed SILENTLY: the controller retried forever, pages stayed blank).
    if (result.path != null) {
      pixels = await getPixels(
        path: result.path,
        removeTempFile: removeTempFile,
      );
    } else {
      pixels = await getPixels(
        bytes: result.data,
        removeTempFile: removeTempFile,
      );
    }

    return PdfPageImagePigeon(
      id: pageId,
      pageNumber: pageNumber,
      width: retWidth,
      height: retHeight,
      bytes: pixels,
      format: format,
      quality: quality,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PdfPageImagePigeon &&
      other.bytes.lengthInBytes == bytes.lengthInBytes;

  @override
  int get hashCode => identityHashCode(id) ^ pageNumber;
}

class PdfPageTexturePigeon extends PdfPageTexture {
  PdfPageTexturePigeon({
    required super.id,
    required super.pageId,
    required super.pageNumber,
  });

  int? _texWidth;
  int? _texHeight;

  @override
  int? get textureWidth => _texWidth;

  @override
  int? get textureHeight => _texHeight;

  @override
  bool get hasUpdatedTexture => _texWidth != null;

  @override
  Future<void> dispose() =>
      _api.unregisterTexture(UnregisterTextureMessage()..id = id);

  @override
  Future<bool> updateRect({
    required String documentId,
    int destinationX = 0,
    int destinationY = 0,
    int? width,
    int? height,
    int sourceX = 0,
    int sourceY = 0,
    int? textureWidth,
    int? textureHeight,
    double? fullWidth,
    double? fullHeight,
    String? backgroundColor,
    bool allowAntiAliasing = true,
  }) async {
    try {
      final params = UpdateTextureMessage()
        ..documentId = documentId
        ..pageNumber = pageNumber
        ..textureId = id
        ..pageId = pageId
        ..destinationX = destinationX
        ..destinationY = destinationY
        ..width = width
        ..height = height
        ..sourceX = sourceX
        ..sourceY = sourceY
        ..textureWidth = textureWidth
        ..textureHeight = textureHeight
        ..fullWidth = fullWidth
        ..fullHeight = fullHeight
        ..backgroundColor = backgroundColor
        ..allowAntiAliasing = allowAntiAliasing;
      await _api.updateTexture(params);
      _texWidth = textureWidth ?? _texWidth;
      _texHeight = textureHeight ?? _texHeight;
      return true;
    } catch (error) {
      return false;
    }
  }

  @override
  int get hashCode => identityHashCode(id) ^ pageNumber;

  @override
  bool operator ==(Object other) =>
      other is PdfPageTexturePigeon &&
      other.id == id &&
      other.pageId == pageId &&
      other.pageNumber == pageNumber;
}
