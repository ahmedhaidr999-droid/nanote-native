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
/// v2.6.0 pipeline hardening — "only page 1 renders, pages 2+ stay gray":
///
/// The upstream pdfx 2.11 Android render coroutine caught only `Exception`,
/// so an `OutOfMemoryError` from `Bitmap.createBitmap` during a full-page
/// raster escaped the handler: the platform reply was never delivered, the
/// Dart render future NEVER completed, and this controller's serialized
/// queue stalled forever right after the first successful page. The vendored
/// fork (third_party/pdfx) fixes that at the source (catches `Throwable`).
/// This controller adds the matching defense-in-depth so NO failure mode —
/// transient, OOM, or a hypothetically wedged platform call — can ever
/// permanently kill a page again:
///
///  * MEMORY BUDGET — max render width 1440px (not 1600) and an 8-entry
///    LRU (not 12): ~95MB of decoded pixels worst case instead of ~175MB,
///    which is what pushed mid-RAM devices into the OOM in the first place.
///  * WATCHDOG — every queued pdfx task carries a deadline. A task that
///    exceeds it has its future completed with `null` (callers unblock),
///    the queue is force-reset, and a best-effort document REOPEN is
///    scheduled (rate-limited) — the only reliable way to clear a bad
///    native PdfRenderer state.
///  * NO PERMANENT PAGE DEATH — a VISIBLE (priority) page request always
///    gets fresh render attempts (the background give-up counter resets);
///    reopening the document clears every failure record.
///  * UNIQUE LIVE-IMAGE HANDLES — ref-counting is keyed by unique handles
///    (key#seq) instead of the shared cache key, so a same-key re-render
///    can never leak the old pixels nor dispose pixels a tile still paints.
///  * CALLER TIMEOUTS — `pageImage` awaits with its own deadline, so a
///    stuck future can never freeze a tile's request loop.
///
/// Carried over from the v2.1/v2.4 hardening: WHITE paper placeholder
/// while pending/missing, failure-transparent size resolution, render
/// retries with backoff, PRIORITY queue for on-screen pages, serialized
/// pdfx access, token-guarded results, JPEG pipeline.
///
///  * 1-BASED page numbers everywhere (pdfx convention).
///  * Quality buckets `[1.0, 1.5, 2.0, 3.0] × dpr`.
class PdfDocumentController extends ChangeNotifier {
  PdfDocumentController._();

  static final PdfDocumentController I = PdfDocumentController._();

  static const List<double> _buckets = [1.0, 1.5, 2.0, 3.0];

  /// v2.6.0: 8 entries × ≤ ~12MB ≈ 95MB worst case (was 12 × ~14.5MB).
  static const int _maxCacheEntries = 8;

  /// v2.6.0: 1440px wide rasters (~170dpi for A4) — plenty for fit-width
  /// reading at 3× dpr, ~20% fewer bytes per bitmap than 1600px, and the
  /// reduced LRU halves the peak decoded-image budget (the OOM driver).
  static const int _maxRenderWidthPx = 1440;

  // ------------------------------------------------------- v2.6.0 watchdog

  /// Deadline for a single queued render task. Generous: real renders take
  /// 50–600ms; anything beyond this is presumed wedged natively.
  /// (Non-const: shortened by the pipeline regression tests.)
  static Duration renderDeadline = const Duration(seconds: 20);

  /// Deadline for open/close/document tasks.
  static Duration docDeadline = const Duration(seconds: 15);

  /// Deadline for the cheap page-size tasks.
  static Duration sizeDeadline = const Duration(seconds: 8);

  /// Caller-side timeout for `pageImage` awaits (tiles never freeze).
  static Duration callTimeout = const Duration(seconds: 22);

  /// Cooldown between watchdog-forced document recoveries.
  static const Duration _recoveryCooldown = Duration(seconds: 20);

  /// Maximum consecutive watchdog recoveries before giving up (the user
  /// re-enters the notebook to retry; prevents reopen loops).
  static const int _maxAutoRecoveries = 3;

  /// Delay before the watchdog-forced document reopen (lets the presumed
  /// stuck native call settle). Non-const: shortened in tests.
  static Duration recoveryDelay = const Duration(milliseconds: 1500);

  PdfDocument? _doc;
  int _token = 0;

  /// Serialized pdfx work (renders + doc open/close) — never two pdfx
  /// operations in flight at once. Priority (visible page) renders are
  /// picked before background work.
  final List<_QueueTask> _pending = [];
  _QueueTask? _running;

  final LinkedHashMap<String, ui.Image> _cache = LinkedHashMap();

  /// Cache key → handle of the live image currently backing it.
  final Map<String, String> _cacheHandles = {};

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

  /// Ref-counted live images by UNIQUE handle (never the shared cache
  /// key): a same-key re-render creates a new handle, so releasing an old
  /// handle can never decrement a replacement's ref-count — no leaks, no
  /// premature disposal.
  final Map<String, _LiveImage> _live = {};

  /// Monotonic handle sequence.
  int _handleSeq = 0;

  // ------------------------------------------------------------------ state

  /// Absolute path of the currently open document (null when closed).
  String? currentPath;

  /// Bumped whenever new rendered images become ready.
  final ValueNotifier<int> renderTick = ValueNotifier<int>(0);

  bool get isOpen => _doc != null;

  /// Page count of the open document (0 when closed).
  int get pageCount => _doc?.pagesCount ?? 0;

  // ------------------------------------------------------------ watchdog

  DateTime? _lastRecoveryAt;
  int _recoveries = 0;
  String? _recoveryPath;

  /// Called when the RUNNING task blows its deadline: unblock everyone,
  /// reset the queue, and schedule a rate-limited document reopen.
  void _onTaskExpired(_QueueTask task) {
    if (!identical(_running, task)) return;
    _running = null;
    // Unblock every queued caller (their tasks are dropped).
    for (final t in List.of(_pending)) {
      t.abandon();
    }
    _pending.clear();
    // Drop in-flight bookkeeping so retries start FRESH renders.
    _inFlight.clear();
    // Best-effort native recovery, rate-limited.
    _scheduleWedgeRecovery();
  }

  void _scheduleWedgeRecovery() {
    final path = currentPath;
    final now = DateTime.now();
    final last = _lastRecoveryAt;
    if (last != null && now.difference(last) < _recoveryCooldown) return;
    if (path == null) return;
    if (_recoveryPath == path && _recoveries >= _maxAutoRecoveries) return;
    if (_recoveryPath != path) {
      _recoveryPath = path;
      _recoveries = 0;
    }
    _recoveries++;
    _lastRecoveryAt = now;
    // Give the (presumed stuck) native call a moment to settle, then
    // reopen the document outside the reset queue.
    Future<void>.delayed(recoveryDelay, () {
      // Only when this exact document is still what the user has open —
      // never resurrect a doc the user (or the workspace) already closed.
      if (currentPath == path) {
        unawaited(_reopenForRecovery(path));
      }
    });
  }

  Future<void> _reopenForRecovery(String path) async {
    _token++;
    final old = _doc;
    _doc = null;
    currentPath = null;
    _clearCaches();
    if (old != null) {
      try {
        await old.close().timeout(docDeadline);
      } catch (_) {
        // Already closed natively / wedged — nothing more we can do.
      }
    }
    try {
      final doc = await PdfDocument.openFile(path).timeout(docDeadline);
      _doc = doc;
      currentPath = path;
    } catch (_) {
      // Reopen failed — tiles keep the paper placeholder; the next
      // workspace open retries.
      return;
    }
    // A previous page may have been left OPEN natively by the wedged
    // render; the fresh PdfRenderer is independent, so rendering works.
    renderTick.value = renderTick.value + 1;
    notifyListeners();
  }

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
    next.onExpired = () => _onTaskExpired(next!);
    next.run().whenComplete(() {
      if (identical(_running, next)) _running = null;
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
    final ok = await _runQueued<bool?>(() async {
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
    }, priority: true, deadline: docDeadline);
    if (ok == true) {
      // Fresh document → reset the wedge-recovery budget for this path.
      if (_recoveryPath != absPath) {
        _recoveryPath = absPath;
        _recoveries = 0;
      }
      // Wake every mounted tile: tiles that mounted while the document was
      // still opening burn their 5 retries on `doc == null` and would
      // otherwise stay blank until the next unrelated tick.
      renderTick.value = renderTick.value + 1;
    }
    notifyListeners();
    return ok == true;
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
    await _runQueued<void>(() async {
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
    }, priority: true, deadline: docDeadline);
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
    }, priority: true, deadline: sizeDeadline);
    _sizeFutures[pageNumber] = fut;
    unawaited(fut.whenComplete(() => _sizeFutures.remove(pageNumber)));
    return fut;
  }

  // ---------------------------------------------------------------- renders

  /// Renders page [pageNumber] (1-based) at the best quality bucket for
  /// [scaleHint] (screen scale × device pixel ratio). Returns the decoded
  /// image (with its cache key + live handle — tiles retain/release it)
  /// from the LRU cache, scheduling a render on a miss. Null when the
  /// document is closed, the page is out of range, or the render failed.
  ///
  /// [priority] — the page is visible on screen right now: its render jumps
  /// the queue and ALWAYS gets fresh attempts (v2.6.0: a visible page can
  /// no longer be permanently abandoned by the background give-up counter).
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
    if (hit != null) {
      final handle = _cacheHandles[key];
      if (handle != null) return PdfPageBitmap(hit, key, handle);
    }

    // A recent failure for this key: retry only after the backoff (or
    // immediately when the page is on screen — and a PRIORITY request
    // also RESETS the give-up counter: visible pages never die).
    final fail = _failedAt[key];
    if (fail != null) {
      final since = DateTime.now().difference(fail);
      if (since < _retryDelay && !priority) return null;
      _failedAt.remove(key);
      if (priority) _retryCounts.remove(key);
    }

    var pending = _inFlight[key];
    if (pending != null) {
      try {
        final img = await pending.timeout(callTimeout);
        if (img != null) {
          final handle = _cacheHandles[key];
          if (handle != null) return PdfPageBitmap(img, key, handle);
        }
        return null;
      } on TimeoutException {
        // Drop the entry so the next request starts a FRESH render
        // instead of queueing behind the stuck one.
        if (identical(_inFlight[key], pending)) _inFlight.remove(key);
        return null;
      }
    }

    final hPx = (wPx * size.height / size.width).round();
    pending = _runQueued<ui.Image?>(
      priority: priority,
      deadline: renderDeadline,
      () => _render(doc, token, pageNumber, wPx, hPx),
    );
    _inFlight[key] = pending;
    final fut = pending;
    unawaited(fut.whenComplete(() {
      if (identical(_inFlight[key], fut)) _inFlight.remove(key);
    }));
    try {
      final img = await fut.timeout(callTimeout);
      if (img == null) return null;
      final handle = _cacheHandles[key];
      return handle == null ? null : PdfPageBitmap(img, key, handle);
    } on TimeoutException {
      if (identical(_inFlight[key], fut)) _inFlight.remove(key);
      return null;
    }
  }

  /// External re-render request (e.g. after a viewport change): bumps
  /// [renderTick] so tiles repaint and re-request their bucket.
  void bump() {
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
    if (live.refs <= 0 && live.evicted) {
      _live.remove(handle);
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
  /// mounted tiles re-request. v2.6.0: the give-up cap only applies to
  /// BACKGROUND work — priority (visible) requests reset the counter in
  /// [pageImage], so an on-screen page always gets fresh attempts.
  void _scheduleRetry(String key) {
    _failedAt.putIfAbsent(key, () => DateTime.now());
    final tries = (_retryCounts[key] ?? 0) + 1;
    _retryCounts[key] = tries;
    if (tries > 8) return; // background give-up (visible pages reset this)
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

  /// LRU insert (access-order eviction, max 8 entries). Evicted entries
  /// keep their pixels alive while any tile retains them. v2.6.0: every
  /// stored image gets a UNIQUE handle — replacing a key never touches the
  /// ref-count of the image it replaces (the old entry stays keyed by its
  /// own handle until its last holder releases it: no leak, no premature
  /// disposal).
  void _store(String key, ui.Image image) {
    // Retire the previous handle for this key (if any).
    final oldHandle = _cacheHandles.remove(key);
    if (oldHandle != null) {
      final old = _live[oldHandle];
      if (old != null) {
        old.evicted = true;
        if (old.refs <= 0) {
          _live.remove(oldHandle);
          _disposeImage(old.image);
        }
        // else: still painted by a holder — release(oldHandle) disposes
        // the pixels exactly when the last reference drops.
      }
    }
    final handle = '$key#${_handleSeq++}';
    _cacheHandles[key] = handle;
    _live[handle] = _LiveImage(image);
    _cache.remove(key);
    _cache[key] = image;
    while (_cache.length > _maxCacheEntries) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
      final oldestHandle = _cacheHandles.remove(oldestKey);
      if (oldestHandle != null) {
        final live = _live[oldestHandle];
        if (live != null) {
          live.evicted = true;
          if (live.refs <= 0) {
            _live.remove(oldestHandle);
            _disposeImage(live.image);
          }
          // Retained → disposed by release() when the last ref drops.
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
    _cacheHandles.clear();
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

  /// Runs [task] on the serialized queue with the given priority and a
  /// WATCHDOG deadline. The queue tail never stalls on a failed task; the
  /// returned future carries the task's own result/error and ALWAYS
  /// completes — on deadline expiry it completes with `null` and the
  /// controller schedules a document recovery.
  Future<T?> _runQueued<T>(Future<T> Function() task,
      {bool priority = false, Duration? deadline}) {
    final t = _QueueTask<T>(task, priority: priority, deadline: deadline);
    _enqueueTask(t);
    return t.future;
  }
}

/// One serialized pdfx task with a watchdog deadline.
class _QueueTask<T> {
  _QueueTask(this._task, {this.priority = false, this.deadline});

  final Future<T> Function() _task;
  final bool priority;
  final Duration? deadline;

  final Completer<T?> _completer = Completer<T?>();
  Timer? _watchdog;

  /// Set by the queue right before the task runs.
  void Function()? onExpired;

  /// True when the watchdog fired (native call presumed wedged).
  bool expired = false;

  Future<T?> get future => _completer.future;

  /// Executes the task NOW (the queue calls this when it is this task's
  /// turn) and completes the shared future. Never throws. The future is
  /// ALSO completed (with null) by the watchdog if the task blows its
  /// deadline — callers never wait forever.
  Future<void> run() async {
    _startWatchdog();
    try {
      final result = await _task();
      if (!_completer.isCompleted) _completer.complete(result);
    } catch (e, s) {
      if (!_completer.isCompleted) _completer.completeError(e, s);
    } finally {
      _watchdog?.cancel();
    }
  }

  /// Completes the future with null and stops the watchdog — used when the
  /// queue is force-reset around a wedged task.
  void abandon() {
    expired = true;
    _watchdog?.cancel();
    if (!_completer.isCompleted) _completer.complete(null);
  }

  void _startWatchdog() {
    final d = deadline;
    if (d == null) return;
    _watchdog = Timer(d, () {
      if (_completer.isCompleted) return;
      expired = true;
      // Unblock the caller FIRST, then let the queue recover.
      _completer.complete(null);
      onExpired?.call();
    });
  }
}

class _LiveImage {
  _LiveImage(this.image);

  final ui.Image image;
  int refs = 0;
  bool evicted = false;
}
