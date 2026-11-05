import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:pdfx/pdfx.dart';

import '../persistence/file_store.dart';

/// Background PDF renderer for imported notebooks.
///
///  * 1-BASED page numbers everywhere (pdfx convention).
///  * Quality buckets `[1.0, 1.5, 2.0, 3.0, 4.0] × dpr`; the smallest bucket
///    ≥ the requested scale hint wins (else the largest), max render width
///    2200px with the height scaled proportionally.
///  * LRU cache of 18 decoded [ui.Image]s keyed by `'pageNumber@widthPx'`.
///  * SERIALIZED render queue — pdfx on Android cannot render two pages at
///    once, and every [PdfPage] is closed right after its render.
///  * Every render is token-guarded: results produced against a document
///    that has since been closed/replaced are dropped (and disposed).
class PdfDocumentController extends ChangeNotifier {
  PdfDocumentController._();

  static final PdfDocumentController I = PdfDocumentController._();

  static const List<double> _buckets = [1.0, 1.5, 2.0, 3.0, 4.0];
  static const int _maxCacheEntries = 18;
  static const int _maxRenderWidthPx = 2200;

  PdfDocument? _doc;
  int _token = 0;

  /// Serialized work queue (renders + doc open/close) — never two pdfx
  /// operations in flight at once.
  Future<void> _queue = Future<void>.value();

  final LinkedHashMap<String, ui.Image> _cache = LinkedHashMap();
  final Map<String, Future<ui.Image?>> _inFlight = {};
  final Map<int, Future<Size?>> _sizeFutures = {};

  /// Page sizes in pdf points (pdfx page.width/height), filled lazily.
  final Map<int, Size> _pageSizes = {};

  // ------------------------------------------------------------------ state

  /// Absolute path of the currently open document (null when closed).
  String? currentPath;

  /// Bumped whenever new rendered images become ready.
  final ValueNotifier<int> renderTick = ValueNotifier<int>(0);

  bool get isOpen => _doc != null;

  /// Page count of the open document (0 when closed).
  int get pageCount => _doc?.pagesCount ?? 0;

  // ------------------------------------------------------------------ open

  /// Opens the PDF at [absPath], closing any previous document first.
  /// Returns false when the file cannot be opened.
  Future<bool> open(String absPath) async {
    final token = ++_token;
    final ok = await _enqueue<bool>(() async {
      final old = _doc;
      _doc = null;
      currentPath = null;
      _clearCaches();
      if (old != null) {
        try {
          await old.close();
        } catch (_) {
          // Already closed natively — nothing to do.
        }
      }
      try {
        final doc = await PdfDocument.openFile(absPath);
        if (token != _token) {
          // A newer open/close raced in — discard this document.
          try {
            await doc.close();
          } catch (_) {}
          return false;
        }
        _doc = doc;
        currentPath = absPath;
        return true;
      } catch (_) {
        return false;
      }
    });
    notifyListeners();
    return ok;
  }

  /// Resolves [relPath] through [FileStore] and opens the result.
  Future<void> openRelative(String relPath) async {
    try {
      final abs = await FileStore.resolve(relPath);
      await open(abs.path);
    } catch (_) {
      // Unresolvable path — treat as a failed open.
    }
  }

  /// Closes the document and drops every cached image/page size.
  Future<void> close() async {
    _token++;
    await _enqueue<void>(() async {
      final old = _doc;
      _doc = null;
      currentPath = null;
      _clearCaches();
      if (old != null) {
        try {
          await old.close();
        } catch (_) {
          // Already closed natively — nothing to do.
        }
      }
    });
    notifyListeners();
  }

  /// Maps a 0-based doc page index to the 1-based page number used by pdfx.
  int pageForDocPage(int docPageIndex) => docPageIndex + 1;

  // -------------------------------------------------------------- page size

  /// Page size in pdf points (pdfx page.width/height at 72dpi). Returns the
  /// cached value, or null when it is not known yet — an async fill is kicked
  /// off in that case, so re-query after the next [renderTick] bump.
  Size? pageSize(int pageNumber) {
    final doc = _doc;
    if (doc == null) return null;
    if (pageNumber < 1 || pageNumber > doc.pagesCount) return null;
    final cached = _pageSizes[pageNumber];
    if (cached != null) return cached;
    unawaited(_resolvePageSize(doc, _token, pageNumber));
    return null;
  }

  /// Queues a tiny task that opens the page, records its size and closes it.
  Future<Size?> _resolvePageSize(
      PdfDocument doc, int token, int pageNumber) {
    final existing = _sizeFutures[pageNumber];
    if (existing != null) return existing;
    final fut = _enqueue<Size?>(() async {
      if (token != _token || _doc != doc) return null;
      PdfPage? page;
      try {
        page = await doc.getPage(pageNumber);
        _pageSizes[pageNumber] = Size(page.width, page.height);
        await page.close();
        // Let listeners (workspace aspect apply + tiles) know a size landed.
        renderTick.value++;
        return _pageSizes[pageNumber];
      } catch (_) {
        try {
          await page?.close();
        } catch (_) {}
        return null;
      }
    });
    _sizeFutures[pageNumber] = fut;
    unawaited(fut.whenComplete(() => _sizeFutures.remove(pageNumber)));
    return fut;
  }

  // ---------------------------------------------------------------- renders

  /// Renders page [pageNumber] (1-based) at the best quality bucket for
  /// [scaleHint] (screen scale × device pixel ratio). Returns the decoded
  /// image from the LRU cache, scheduling a render on a miss. Null when the
  /// document is closed, the page is out of range, or the render failed.
  Future<ui.Image?> pageImage(int pageNumber, double scaleHint) async {
    final doc = _doc;
    final token = _token;
    if (doc == null) return null;
    if (pageNumber < 1 || pageNumber > doc.pagesCount) return null;

    var size = _pageSizes[pageNumber];
    size ??= await _resolvePageSize(doc, token, pageNumber);
    if (size == null) return null;
    if (size.width <= 0 || size.height <= 0) return null;
    if (token != _token || _doc != doc) return null;

    final scale = _bucketFor(scaleHint);
    var wPx = (size.width * scale).round();
    if (wPx > _maxRenderWidthPx) wPx = _maxRenderWidthPx;
    if (wPx < 1) wPx = 1;
    final key = '$pageNumber@$wPx';

    final hit = _cacheHit(key);
    if (hit != null) return hit;

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final hPx = (wPx * size.height / size.width).round();
    final fut = _enqueue<ui.Image?>(
        () => _render(doc, token, pageNumber, wPx, hPx));
    _inFlight[key] = fut;
    unawaited(fut.whenComplete(() => _inFlight.remove(key)));
    return fut;
  }

  /// External re-render request (e.g. after a viewport change): bumps
  /// [renderTick] so tiles repaint and re-request their bucket.
  void bump() {
    renderTick.value = renderTick.value + 1;
  }

  // ---------------------------------------------------------------- helpers

  double _bucketFor(double scaleHint) {
    final dpr = _devicePixelRatio;
    for (final b in _buckets) {
      if (b * dpr >= scaleHint) return b * dpr;
    }
    return _buckets.last * dpr;
  }

  double get _devicePixelRatio {
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) return views.first.devicePixelRatio;
    } catch (_) {
      // Binding not ready — assume a typical hi-dpi display.
    }
    return 2.0;
  }

  Future<ui.Image?> _render(
      PdfDocument doc, int token, int pageNumber, int wPx, int hPx) async {
    if (token != _token || _doc != doc) return null;
    PdfPage? page;
    try {
      page = await doc.getPage(pageNumber);
      _pageSizes[pageNumber] ??= Size(page.width, page.height);
      final img = await page.render(
        width: wPx.toDouble(),
        height: hPx.toDouble(),
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
        quality: 95,
      );
      await page.close();
      page = null;
      if (token != _token || _doc != doc) return null;
      if (img == null || img.bytes.isEmpty) return null;
      final image = await _decode(img.bytes);
      if (token != _token || _doc != doc) {
        image.dispose();
        return null;
      }
      _store('$pageNumber@$wPx', image);
      renderTick.value = renderTick.value + 1;
      notifyListeners();
      return image;
    } catch (_) {
      try {
        await page?.close();
      } catch (_) {}
      return null;
    }
  }

  Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  /// LRU insert (access-order eviction, max 18 entries).
  void _store(String key, ui.Image image) {
    final existing = _cache.remove(key);
    if (existing != null) _disposeImage(existing);
    _cache[key] = image;
    while (_cache.length > _maxCacheEntries) {
      final oldestKey = _cache.keys.first;
      final oldest = _cache.remove(oldestKey);
      if (oldest != null) _disposeImage(oldest);
    }
  }

  /// LRU read: re-inserts the entry so it becomes most recently used.
  ui.Image? _cacheHit(String key) {
    final img = _cache.remove(key);
    if (img == null) return null;
    _cache[key] = img;
    return img;
  }

  void _clearCaches() {
    for (final img in _cache.values) {
      _disposeImage(img);
    }
    _cache.clear();
    _pageSizes.clear();
    _inFlight.clear();
    _sizeFutures.clear();
  }

  /// Disposal is deferred by a grace window: tiles keep painting the last
  /// image they fetched for a few frames after the cache drops it, and
  /// painting a disposed ui.Image crashes the native rasterizer.
  void _disposeImage(ui.Image image) {
    Future<void>.delayed(_disposeGrace, () => image.dispose());
  }

  static const Duration _disposeGrace = Duration(seconds: 5);

  /// Chains [task] onto the serialized queue. The queue tail swallows errors
  /// so one failed render can never stall the chain; the returned future
  /// carries the task's own result/error.
  Future<T> _enqueue<T>(Future<T> Function() task) {
    final fut = _queue.then((_) => task());
    _queue = fut.then((_) {}, onError: (_) {});
    return fut;
  }
}
