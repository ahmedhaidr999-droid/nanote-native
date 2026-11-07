import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import '../persistence/file_store.dart';

/// LRU (24) cache of decoded [ui.Image]s, keyed by the path RELATIVE to the
/// [FileStore] base directory (e.g. `images/abc.png`). Absolute paths are
/// accepted too — they are canonicalized back to their relative key once the
/// base directory is known.
///
/// Deliberately NOT named `ImageCache` — that would clash with Flutter's own
/// image cache. The workspace installs [peekSync] as the
/// `ElementsPainter.resolveImage` hook so page elements can resolve their
/// images synchronously during paint.
///
/// Evicted entries are NOT disposed on purpose: painters resolve images
/// synchronously during a paint pass and may still hold a reference to an
/// entry for the rest of that frame — disposing it would kill the
/// rasterizer (same policy as the ref-counted PDF page cache; see
/// PdfDocumentController). The engine attaches a finalizer to every
/// [ui.Image], so evicted-but-unreferenced pixels are reclaimed by the GC.
class AppImageCache {
  AppImageCache._();

  /// Maximum decoded images kept alive at once.
  static const int _maxEntries = 24;

  /// canonical key -> decoded image. Insertion order = age (eldest first).
  static final LinkedHashMap<String, ui.Image> _cache =
      LinkedHashMap<String, ui.Image>();

  /// Remembered FileStore base directory. After the first successful load,
  /// relative paths can be turned into absolute ones (and back) fully
  /// synchronously via [p.join]/[p.relative].
  static Directory? _baseDir;

  // ------------------------------------------------------- relative-path API

  /// Cached decoded image for [relPath] (relative to the FileStore base), or
  /// null when it has not been loaded (yet).
  ///
  /// A hit re-inserts the entry so LRU freshness is updated. Absolute paths
  /// are accepted too once the base directory is known — they are mapped back
  /// to their relative key.
  static ui.Image? peekSync(String relPath) {
    final key = _canonicalKey(relPath);
    final hit = _cache.remove(key);
    if (hit == null) return null;
    _cache[key] = hit; // re-insert as most recently used
    return hit;
  }

  /// Resolves [relPath] through the [FileStore], loads the bytes, decodes the
  /// first frame and caches the result. Repeated calls are served from the
  /// cache.
  static Future<ui.Image> loadByRel(String relPath) async {
    final key = _canonicalKey(relPath);
    final cached = peekSync(key);
    if (cached != null) return cached;

    final file = await FileStore.resolve(key);
    final bytes = await file.readAsBytes();
    final image = await decodeBytes(bytes);

    // Remember the base dir on the FIRST successful resolve so later
    // peekSync calls can build absolute paths synchronously.
    _baseDir ??= await FileStore.base();

    _insert(key, image);
    return image;
  }

  // ----------------------------------------------------- absolute-path API

  /// Cached decoded image for an ABSOLUTE path, or null. Equivalent to
  /// [peekSync] (absolute keys are canonicalized to relative ones).
  static ui.Image? peek(String absPath) => peekSync(absPath);

  /// Loads + decodes an ABSOLUTE path and caches it under its canonical
  /// (relative, when under the FileStore base) key.
  static Future<ui.Image> load(String absPath) async {
    _baseDir ??= await FileStore.base();
    final cached = peekSync(absPath);
    if (cached != null) return cached;
    final bytes = await File(absPath).readAsBytes();
    final image = await decodeBytes(bytes);
    _insert(_canonicalKey(absPath), image);
    return image;
  }

  // -------------------------------------------------------------- common

  /// Drops every cached image. The [ui.Image] objects themselves are NOT
  /// disposed — painters may still hold references to them; the GC reclaims
  /// the native memory eventually.
  static void clear() {
    _cache.clear();
  }

  /// Shared decoding helper: raw image bytes -> first-frame [ui.Image].
  static Future<ui.Image> decodeBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  // ------------------------------------------------------------ private

  /// Canonical (relative) cache key for [path]; absolute paths are converted
  /// using the remembered base dir.
  static String _canonicalKey(String path) {
    final base = _baseDir;
    if (base != null && p.isAbsolute(path)) {
      return p.relative(path, from: base.path);
    }
    return path;
  }

  static void _insert(String key, ui.Image image) {
    _cache
      ..remove(key)
      ..[key] = image;
    while (_cache.length > _maxEntries) {
      _cache.remove(_cache.keys.first); // evict the eldest entry
    }
  }
}
