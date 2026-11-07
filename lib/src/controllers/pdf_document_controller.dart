import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import '../persistence/file_store.dart';
import '../workspace/pdf_page_tile.dart' show PdfPageBitmap;

/// Background PDF renderer for imported notebooks — **v1.0.0 pdfrx edition**.
///
/// Engine: [pdfrx] on top of **pdfium** (Google's Chrome PDF engine). This
/// replaces the entire v2.x pdfx pipeline. Why the swap is inherently safer:
///
///  * pdfx talked to Android's `PdfRenderer` over a platform channel whose
///    coroutine could die mid-render (the v2.6.0 "only page 1 renders" OOM
///    wedge — the Dart future never completed and a serialized queue stalled
///    forever). pdfrx calls pdfium **directly over FFI**: every call returns,
///    exceptions propagate normally, and renders run on background workers.
///    There is no platform channel that can wedge — so the whole
///    watchdog/force-reopen machinery is simply gone.
///  * Page sizes are available synchronously after open (no async
///    size-resolution dance, no missing-size voids).
///  * The same page can render concurrently — Android's "one open page at a
///    time" rule does not exist in pdfium.
///
/// What IS kept from the v2.6.0 hardening (it was right):
///  * MEMORY BUDGET — max raster width 1440px, 8-entry LRU (~95MB worst
///    case of decoded pixels).
///  * NO PERMANENT PAGE DEATH — a failed render is retried after a short
///    delay; VISIBLE (priority) requests always get a fresh attempt.
///  * REF-COUNTED HANDLES — tiles retain/release images by unique handle
///    (`key#seq`); the LRU can evict logically but pixels in use are never
///    disposed, and a same-key re-render can never collide with the
///    ref-count of the image a visible tile is still painting.
class PdfDocumentController extends ChangeNotifier {
  PdfDocumentController._();

  static final PdfDocumentController I = PdfDocumentController._();

  // ------------------------------------------------------------ constants

  /// Max raster width in pixels (memory budget — same as v2.6.0).
  static const int _maxRasterWidth = 1440;

  /// Min raster width in pixels (fit-width on a small phone).
  static const int _minRasterWidth = 360;

  /// Quality bucket step (px). Requests are quantized so zooming does not
  /// produce an unbounded stream of near-identical rasters.
  static const int _bucketStep = 240;

  /// Cached pages (by cache key) — 8 entries ≈ 95MB worst case.
  static const int _lruCapacity = 8;

  /// How long a failed render stays "hot" before the same key may retry.
  static const Duration retryDelay = Duration(milliseconds: 650);

  /// Concurrent pdfium renders. pdfium is thread-safe; the cap exists only
  /// to bound peak memory while scrolling a long document.
  static const int _maxConcurrentRenders = 2;

  // ------------------------------------------------------------------ state

  PdfDocument? _doc;
  String? currentPath;

  /// Bumped whenever new rendered images become ready.
  final ValueNotifier<int> renderTick = ValueNotifier<int>(0);

  bool get isOpen => _doc != null;

  /// Page count of the open document (0 when closed).
  int get pageCount => _doc?.pages.length ?? 0;

  // ----------------------------------------------------------------- open

  /// Opens the PDF at [absPath]. Returns false when it cannot be opened.
  Future<bool> open(String absPath) async {
    if (currentPath == absPath && _doc != null) return true;
    await close();
    try {
      final doc = await PdfDocument.openFile(absPath);
      _doc = doc;
      currentPath = absPath;
      _cache.clear();
      _handles.clear();
      _live.clear();
      _inFlight.clear();
      _failedAt.clear();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Opens by FileStore-relative path.
  Future<void> openRelative(String relPath) async {
    final f = await FileStore.tryResolve(relPath);
    if (f == null) return;
    await open(f.path);
  }

  Future<void> close() async {
    final doc = _doc;
    _doc = null;
    currentPath = null;
    // Unblock queued waiters first (they get null and stop retrying —
    // isOpen is already false).
    final queued = List.of(_pending);
    _pending.clear();
    for (final t in queued) {
      if (!t.completer.isCompleted) t.completer.complete(null);
    }
    _inFlight.clear();
    for (final live in _live.values) {
      live.image.dispose();
    }
    _live.clear();
    _cache.clear();
    _handles.clear();
    _failedAt.clear();
    try {
      await doc?.dispose();
    } catch (_) {
      // Closing a half-open doc can throw on some pdfium builds — ignore.
    }
    notifyListeners();
  }

  // --------------------------------------------------------------- pages

  /// Page size in PDF points (rotated, i.e. exactly what the tile displays),
  /// or null when unknown. With pdfrx sizes are synchronous after open.
  Size? pageSize(int pageNumber) {
    final doc = _doc;
    if (doc == null) return null;
    if (pageNumber < 1 || pageNumber > doc.pages.length) return null;
    final p = doc.pages[pageNumber - 1];
    return Size(p.width, p.height);
  }

  // -------------------------------------------------------------- render

  /// Quality bucket for a requested raster width.
  static int _bucketFor(double targetWidth) {
    final w = targetWidth.clamp(
      _minRasterWidth.toDouble(),
      _maxRasterWidth.toDouble(),
    );
    return (w / _bucketStep).ceil() * _bucketStep;
  }

  /// Renders (or fetches from cache) a page as [scaleHint] × page-width
  /// pixels. [scaleHint] is viewport scale × dpr (screen sharpness).
  /// Returns null only when the render genuinely failed (the tile retries).
  Future<PdfPageBitmap?> pageImage(
    int pageNumber,
    double scaleHint, {
    bool priority = false,
  }) async {
    final doc = _doc;
    if (doc == null) return null;
    if (pageNumber < 1 || pageNumber > doc.pages.length) return null;

    final page = doc.pages[pageNumber - 1];
    final bucketPx = _bucketFor(page.width * (scaleHint > 0.01 ? scaleHint : 1));
    final key = '$pageNumber@$bucketPx';

    // 1. Cache hit (LRU touch).
    final cachedHandle = _cache[key];
    if (cachedHandle != null) {
      final live = _live[cachedHandle];
      if (live != null) {
        // Move to most-recently-used.
        _cache.remove(key);
        _cache[key] = cachedHandle;
        return PdfPageBitmap(live.image, key, cachedHandle);
      }
      _cache.remove(key);
    }

    // 2. Failed recently? Wait for the retry delay — except priority
    //    (visible) requests, which always get a fresh attempt.
    if (!priority) {
      final failedAt = _failedAt[key];
      if (failedAt != null &&
          DateTime.now().difference(failedAt) < retryDelay) {
        return null;
      }
    }

    // 3. Deduplicate concurrent requests for the same key.
    final existing = _inFlight[key];
    if (existing != null) {
      // This caller is visible; upgrade a still-queued task to priority so
      // it runs before background work.
      for (var i = 0; i < _pending.length; i++) {
        final t = _pending[i];
        if (t.key == key && !t.priority) {
          t.priority = true;
          _pending.removeAt(i);
          _pending.insert(_pendingPriorityCount, t);
          break;
        }
      }
      final img = await existing;
      if (img == null) return null;
      final handle = _handles[key];
      return handle == null ? null : PdfPageBitmap(img, key, handle);
    }

    // 4. Enqueue.
    final completer = Completer<ui.Image?>();
    _inFlight[key] = completer.future;
    final task = _RenderTask(
      key: key,
      page: page,
      widthPx: bucketPx,
      priority: priority,
      completer: completer,
    );
    _pending.insert(priority ? _pendingPriorityCount : _pending.length, task);
    _drain();
    unawaited(completer.future.whenComplete(() {
      _inFlight.remove(key);
    }));

    try {
      final img = await completer.future;
      if (img == null) return null;
      final handle = _handles[key];
      return handle == null ? null : PdfPageBitmap(img, key, handle);
    } on TimeoutException {
      return null;
    }
  }

  int get _pendingPriorityCount {
    var n = 0;
    for (final t in _pending) {
      if (t.priority) {
        n++;
      } else {
        break;
      }
    }
    return n;
  }

  final List<_RenderTask> _pending = [];
  int _running = 0;

  void _drain() {
    while (_running < _maxConcurrentRenders && _pending.isNotEmpty) {
      final task = _pending.removeAt(0);
      _running++;
      unawaited(task.run().whenComplete(() {
        _running--;
        _drain();
      }));
    }
  }

  // ------------------------------------------------------- image lifetime

  /// Cache key → handle of the live image currently backing it.
  final LinkedHashMap<String, String> _cache = LinkedHashMap();

  /// Live images by UNIQUE handle (`key#seq`).
  final Map<String, _LiveImage> _live = {};

  /// Cache key → handle (mirror of _cache values, for pageImage's return).
  final Map<String, String> _handles = {};

  /// In-flight render futures by cache key (dedupes concurrent requests).
  final Map<String, Future<ui.Image?>> _inFlight = {};

  /// Failed renders by key → when the failure was recorded (for retry).
  final Map<String, DateTime> _failedAt = {};

  /// Monotonic handle sequence.
  int _handleSeq = 0;

  void _publish(String key, ui.Image image) {
    if (_doc == null) {
      // A render finished after close() — nobody is listening; do not leak.
      image.dispose();
      return;
    }
    _handleSeq++;
    final handle = '$key#$_handleSeq';
    _live[handle] = _LiveImage(image);
    _handles[key] = handle;
    _cache[key] = handle;
    // LRU eviction: drop the oldest entries beyond capacity. Retained
    // pixels stay alive through the handle ref-count; they are disposed on
    // the final release.
    while (_cache.length > _lruCapacity) {
      final oldestKey = _cache.keys.first;
      final oldestHandle = _cache.remove(oldestKey);
      if (oldestHandle == null) continue;
      if (_handles[oldestKey] == oldestHandle) _handles.remove(oldestKey);
      final live = _live[oldestHandle];
      if (live == null) continue;
      live.evicted = true;
      if (live.refs <= 0) {
        live.image.dispose();
        _live.remove(oldestHandle);
      }
    }
    renderTick.value = renderTick.value + 1;
  }

  // ------------------------------------------------------------ ref-counting

  /// Marks the image under [handle] as in use by a tile. While retained the
  /// pixels are never disposed, even if the LRU evicts the entry.
  void retain(String handle) {
    final live = _live[handle];
    if (live != null) live.refs++;
  }

  /// Drops one reference; disposes the pixels when the image was evicted
  /// from the LRU and this was the last reference. Clamped at zero so a
  /// rare double-release can never drive a count negative.
  void release(String handle) {
    final live = _live[handle];
    if (live == null) return;
    if (live.refs > 0) live.refs--;
    if (live.evicted && live.refs <= 0) {
      _live.remove(handle);
      live.image.dispose();
    }
  }

  @override
  void dispose() {
    unawaited(close());
    renderTick.dispose();
    super.dispose();
  }
}

/// One queued pdfium render.
class _RenderTask {
  _RenderTask({
    required this.key,
    required this.page,
    required this.widthPx,
    required this.priority,
    required this.completer,
  });

  final String key;
  final PdfPage page;
  final int widthPx;
  bool priority;
  final Completer<ui.Image?> completer;
  bool _started = false;

  Future<void> run() async {
    if (_started) return;
    _started = true;
    try {
      final srcW = page.width;
      final srcH = page.height;
      if (srcW <= 0 || srcH <= 0) {
        completer.complete(null);
        return;
      }
      final wPx = widthPx;
      final hPx = (srcH * (wPx / srcW)).round();
      // pdfium render (FFI, background worker — cannot wedge).
      final pdfImage = await page.render(
        fullWidth: wPx.toDouble(),
        fullHeight: hPx.toDouble(),
        backgroundColor: 0xFFFFFFFF,
      );
      if (pdfImage == null) {
        completer.complete(null);
        return;
      }
      try {
        // BGRA pixels → immutable ui.Image (the failure-safe decode path:
        // a decode error propagates as an exception instead of a future
        // that never completes).
        final image = await _decodeBgra(
          pdfImage.pixels,
          pdfImage.width,
          pdfImage.height,
        );
        // The controller singleton publishes the image (creates the
        // handle + LRU entry) and clears any stale failure record.
        PdfDocumentController.I._failedAt.remove(key);
        PdfDocumentController.I._publish(key, image);
        completer.complete(image);
      } finally {
        pdfImage.dispose();
      }
    } catch (e) {
      PdfDocumentController.I._failedAt[key] = DateTime.now();
      if (!completer.isCompleted) completer.complete(null);
    }
  }

  static Future<ui.Image> _decodeBgra(Uint8List pixels, int w, int h) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: w,
        height: h,
        pixelFormat: ui.PixelFormat.bgra8888,
      );
      final codec = await descriptor.instantiateCodec();
      try {
        final frame = await codec.getNextFrame();
        return frame.image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}

/// A live (ref-counted) rendered image.
class _LiveImage {
  _LiveImage(this.image);

  final ui.Image image;
  int refs = 0;
  bool evicted = false;
}
