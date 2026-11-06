import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:pdfx/pdfx.dart';

import '../persistence/file_store.dart';
import '../workspace/pdf_page_tile.dart' show PdfPageBitmap;

/// Background PDF renderer for imported notebooks.
///
/// v2.1 pipeline hardening (fixes: PDF pages 2+ never rendering while
/// continuous-scrolling, and pages turning gray while writing/erasing):
///
///  * WHITE paper placeholder — a page whose render is still missing looks
///    like white paper, never a gray block.
///  * Size-resolution NEVER caches failures: a page whose `getPage` failed
///    once is retried on the next query (previously one transient pdfx error
///    made that page unrenderable forever — the classic "only page 1 shows").
///  * Render retries with backoff — transient pdfium/PNG-pipeline errors
///    re-enqueue after a short delay instead of giving up.
///  * PRIORITY queue — renders for pages that are on screen RIGHT NOW jump
///    ahead of prefetch/background work, so the visible page paints first.
///  * Ref-counted images — a tile that holds a rendered image RETAINS it;
///    the LRU may evict it logically, but the pixels are only disposed once
///    no tile uses them (painting a disposed ui.Image crashes the raster
///    thread → page suddenly gray/blank).
///  * JPEG pipeline — much faster than PNG for full-page rasterization.
///
///  * 1-BASED page numbers everywhere (pdfx convention).
///  * Quality buckets `[1.0, 1.5, 2.0, 3.0] × dpr`; max render width 1600px.
///  * LRU cache of 12 decoded [ui.Image]s keyed by `'pageNumber@widthPx'`.
///  * SERIALIZED pdfx access — pdfx/Android cannot handle parallel page
///    operations; every render + doc open/close runs through one queue.
///  * Every render is token-guarded: results produced against a document
///    that has since been closed/replaced are dropped (and disposed).
class PdfDocumentController extends ChangeNotifier {
  PdfDocumentController._();

  static final PdfDocumentController I = PdfDocumentController._();

  static const List<double> _buckets = [1.0, 1.5, 2.0, 3.0];
  static const int _maxCacheEntries = 12;
  static const int _maxRenderWidthPx = 1600;

  PdfDocument? _doc;
  int _token = 0;

  /// Serialized pdfx work (renders + doc open/close) — never two pdfx
  /// operations in flight at once. Two lanes: priority (visible page)
  /// renders are picked before background work.
  final List<_QueueTask> _pending = [];
  _QueueTask? _running;

  final LinkedHashMap<String, ui.Image> _cache = LinkedHashMap();

  /// In-flight render futures by cache key (dedupes concurrent requests).
  final Map<String, Future<ui.Image?>> _inFlight = {};

  /// Failed renders by key → when the failure was recorded (for retry).
  final Map<String, DateTime> _failedAt = {};
  static const Duration _retryDelay = Duration(milliseconds: 650);

  /// In-flight size resolutions by page number.
  final Map<int, Future<Size?>> _sizeFutures = {};

  /// Page sizes in pdf points (pdfx page.width/height), filled lazily.
  /// Pages whose resolution FAILED are not cached, so they are retried.
  final Map<int, Size> _pageSizes = {};

  /// Ref-counted live images: cache key → (image, retained count).
  /// The LRU removes the entry, but the image is only disposed when its
  /// ref-count reaches 0 (tiles retain what they paint).
  final Map<String, _LiveImage> _live = {};

  // ------------------------------------------------------------------ state

  /// Absolute path of the currently open document (null when closed).
  String? currentPath;

  /// Bumped whenever new rendered images become ready.
  final ValueNotifier<int> renderTick = ValueNotifier<int>(0);

  bool get isOpen => _doc != null;

  /// Page count of the open document (0 when closed).
  int get pageCount => _doc?.pagesCount ?? 0;

  // ------------------------------------------------------------------ queue

  void _enqueueTask(_QueueTask task) {
    _pending.add(task);
    _drain();
  }

  void _drain() {
    if (_running != null) return;
    // Priority tasks first (FIFO within each lane).
    _QueueTask? next;
    for (var i = 0; i < _pending.length; i++) {
      if (_pending[i].priority) {
        next = _pending.removeAt(i);
        break;
      }
    }
    next ??= _pending.isEmpty ? null : _pending.removeAt(0);
    if (next == null) return;
    _running = next;
    next.run().whenComplete(() {
      _running = null;
      // Continue after the current frame so microtask chains can't starve
      // the platform channel.
      scheduleMicrotask(_drain);
    });
  }

  // ------------------------------------------------------------------ open

  /// Opens the PDF at [absPath], closing any previous document first.
  /// Returns false when the file cannot be opened.
  Future<bool> open(String absPath) async {
    final token = ++_token;
    final ok = await _runQueued<bool>(priority: true, () async {
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
    if (ok) {
      // Wake every mounted tile: tiles that mounted while the document was
      // still opening burn their 5 retries on `doc == null` and would
      // otherwise stay blank until the next unrelated tick.
      renderTick.value = renderTick.value + 1;
    }
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
    await _runQueued<void>(priority: true, () async {
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

  // -------------------------------------------------------------- page size

  /// Page size in pdf points (pdfx page.width/height at 72dpi). Returns the
  /// cached value, or null when it is not known yet — an async fill is kicked
  /// off in that case (failures are NOT cached: the next call retries).
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
  /// Resolves to null on failure — and the page is left un-cached so a later
  /// call retries it (this is the "page 2 never appears" fix). PRIORITY:
  /// size tasks are cheap and unblock the waiting renders.
  Future<Size?> _resolvePageSize(
      PdfDocument doc, int token, int pageNumber) {
    final existing = _sizeFutures[pageNumber];
    if (existing != null) return existing;
    final fut = _runQueued<Size?>(() async {
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
    }, priority: true);
    _sizeFutures[pageNumber] = fut;
    unawaited(fut.whenComplete(() => _sizeFutures.remove(pageNumber)));
    return fut;
  }

  // ---------------------------------------------------------------- renders

  /// Renders page [pageNumber] (1-based) at the best quality bucket for
  /// [scaleHint] (screen scale × device pixel ratio). Returns the decoded
  /// image (with its cache key — tiles retain/release it) from the LRU
  /// cache, scheduling a render on a miss. Null when the document is
  /// closed, the page is out of range, or the render failed.
  ///
  /// [priority] — the page is visible on screen right now: its render jumps
  /// the queue and a recent transient failure is retried immediately.
  Future<PdfPageBitmap?> pageImage(int pageNumber, double scaleHint,
      {bool priority = false}) async {
    final doc = _doc;
    final token = _token;
    if (doc == null) return null;
    if (pageNumber < 1 || pageNumber > doc.pagesCount) return null;

    var size = _pageSizes[pageNumber];
    size ??= await _resolvePageSize(doc, token, pageNumber);
    if (size == null || size.width <= 0 || size.height <= 0) return null;
    if (token != _token || _doc != doc) return null;

    final scale = _bucketFor(scaleHint);
    var wPx = (size.width * scale).round();
    if (wPx > _maxRenderWidthPx) wPx = _maxRenderWidthPx;
    if (wPx < 1) wPx = 1;
    final key = '$pageNumber@$wPx';

    final hit = _cacheHit(key);
    if (hit != null) return PdfPageBitmap(hit, key);

    // A recent failure for this key: retry only after the backoff (or
    // immediately when the page is on screen).
    final fail = _failedAt[key];
    if (fail != null) {
      final since = DateTime.now().difference(fail);
      if (since < _retryDelay && !priority) return null;
      _failedAt.remove(key);
    }

    final pending = _inFlight[key];
    if (pending != null) {
      final img = await pending;
      return img == null ? null : PdfPageBitmap(img, key);
    }

    final hPx = (wPx * size.height / size.width).round();
    final fut = _runQueued<ui.Image?>(
      priority: priority,
      () => _render(doc, token, pageNumber, wPx, hPx),
    );
    _inFlight[key] = fut;
    unawaited(fut.whenComplete(() => _inFlight.remove(key)));
    final img = await fut;
    return img == null ? null : PdfPageBitmap(img, key);
  }

  /// External re-render request (e.g. after a viewport change): bumps
  /// [renderTick] so tiles repaint and re-request their bucket.
  void bump() {
    renderTick.value = renderTick.value + 1;
  }

  // ------------------------------------------------------------ ref-counting

  /// Marks the image under [key] as in use by a tile. While retained the
  /// pixels are never disposed, even if the LRU evicts the entry.
  void retain(String key) {
    final live = _live[key];
    if (live != null) live.refs++;
  }

  /// Drops one reference; disposes the pixels when the image was evicted
  /// from the LRU and this was the last reference. Clamped at zero so a
  /// rare double-release can never drive a count negative.
  void release(String key) {
    final live = _live[key];
    if (live == null) return;
    if (live.refs > 0) live.refs--;
    if (live.refs <= 0 && live.evicted) {
      _live.remove(key);
      _disposeImage(live.image);
    }
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
        // JPEG is dramatically faster than PNG for full-page rasters and we
        // always render on an opaque white background anyway.
        format: PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
        quality: 90,
      );
      await page.close();
      page = null;
      if (token != _token || _doc != doc) return null;
      if (img == null || img.bytes.isEmpty) {
        _scheduleRetry('$pageNumber@$wPx');
        return null;
      }
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
      _scheduleRetry('$pageNumber@$wPx');
      return null;
    }
  }

  /// Records a failed render and bumps [renderTick] after the backoff so
  /// mounted tiles re-request (bounded to a few retries per key).
  void _scheduleRetry(String key) {
    _failedAt.putIfAbsent(key, () => DateTime.now());
    final tries = (_retryCounts[key] ?? 0) + 1;
    _retryCounts[key] = tries;
    if (tries > 4) return; // give up — likely a broken page/document
    Future<void>.delayed(_retryDelay, () {
      if (_failedAt.containsKey(key)) {
        renderTick.value = renderTick.value + 1;
      }
    });
  }

  final Map<String, int> _retryCounts = {};

  Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  /// LRU insert (access-order eviction, max 12 entries). Evicted entries
  /// keep their pixels alive while any tile retains them.
  void _store(String key, ui.Image image) {
    final existing = _live.remove(key);
    if (existing != null) {
      // Same key re-rendered: replace the pixels. Old pixels are disposed
      // once unreferenced (or immediately when nobody holds them).
      if (existing.refs <= 0) {
        _disposeImage(existing.image);
      } else {
        existing.evicted = true; // dispose when the last ref drops
      }
    }
    _live[key] = _LiveImage(image);
    _cache.remove(key);
    _cache[key] = image;
    while (_cache.length > _maxCacheEntries) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
      final live = _live[oldestKey];
      if (live != null) {
        live.evicted = true;
        if (live.refs <= 0) {
          _live.remove(oldestKey);
          _disposeImage(live.image);
        }
      }
    }
    _failedAt.remove(key);
    _retryCounts.remove(key);
  }

  /// LRU read: re-inserts the entry so it becomes most recently used.
  ui.Image? _cacheHit(String key) {
    final img = _cache.remove(key);
    if (img == null) return null;
    _cache[key] = img;
    return img;
  }

  void _clearCaches() {
    for (final live in _live.values) {
      if (!live.evicted) _disposeImage(live.image);
    }
    _live.clear();
    _cache.clear();
    _pageSizes.clear();
    _inFlight.clear();
    _sizeFutures.clear();
    _failedAt.clear();
    _retryCounts.clear();
    // Queued tasks are NOT dropped: stale ones are token-guarded no-ops and
    // their callers await their futures (dropping them would hang open()).
  }

  /// Disposal is deferred by a grace window: tiles keep painting the last
  /// image they fetched for a few frames after the cache drops it, and
  /// painting a disposed ui.Image crashes the native rasterizer.
  void _disposeImage(ui.Image image) {
    Future<void>.delayed(_disposeGrace, () => image.dispose());
  }

  static const Duration _disposeGrace = Duration(seconds: 5);

  /// Runs [task] on the serialized queue with the given priority. The
  /// queue tail never stalls on a failed task; the returned future carries
  /// the task's own result/error.
  Future<T> _runQueued<T>(Future<T> Function() task, {bool priority = false}) {
    final t = _QueueTask<T>(task, priority: priority);
    _enqueueTask(t);
    return t.future;
  }
}

class _QueueTask<T> {
  _QueueTask(this._task, {this.priority = false});

  final Future<T> Function() _task;
  final bool priority;
  final Completer<T> _completer = Completer<T>();

  Future<T> get future => _completer.future;

  /// Executes the task NOW (the queue calls this when it is this task's
  /// turn) and completes the shared future. Never throws.
  Future<void> run() async {
    try {
      final result = await _task();
      if (!_completer.isCompleted) _completer.complete(result);
    } catch (e, s) {
      if (!_completer.isCompleted) _completer.completeError(e, s);
    }
  }
}

class _LiveImage {
  _LiveImage(this.image);

  final ui.Image image;
  int refs = 0;
  bool evicted = false;
}
