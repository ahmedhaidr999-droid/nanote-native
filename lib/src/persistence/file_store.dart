import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// All user files live under one base dir:
///   images/  pdfs/  recordings/  stickers/  covers/
/// Entities store RELATIVE paths; this store resolves them.
class FileStore {
  FileStore._();

  static Directory? _base;

  static Future<Directory> base() async {
    if (_base != null) return _base!;
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(docs.path, 'nanote_files'));
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    _base = d;
    return d;
  }

  static Future<Directory> _sub(String name) async {
    final b = await base();
    final d = Directory(p.join(b.path, name));
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return d;
  }

  static Future<Directory> imagesDir() => _sub('images');
  static Future<Directory> pdfsDir() => _sub('pdfs');
  static Future<Directory> recordingsDir() => _sub('recordings');
  static Future<Directory> stickersDir() => _sub('stickers');
  static Future<Directory> coversDir() => _sub('covers');

  /// Copies a picked file into [kind] ("images" | "pdfs" | "stickers" |
  /// "covers") and returns the RELATIVE path ("images/xxx.png").
  static Future<String> importFile(File src, String kind) async {
    final dir = await _sub(kind);
    final ext = p.extension(src.path).isEmpty ? '.bin' : p.extension(src.path);
    final name =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$ext';
    final dst = File(p.join(dir.path, name));
    await src.copy(dst.path);
    return '$kind/$name';
  }

  /// Creates an empty file for recording; returns the RELATIVE path.
  static Future<String> newRecordingFile() async {
    await _sub('recordings'); // ensure the dir exists
    final name =
        'rec_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}.m4a';
    return 'recordings/$name';
  }

  static Future<File> resolve(String relPath) async {
    final b = await base();
    return File(p.join(b.path, relPath));
  }

  static Future<File?> tryResolve(String relPath) async {
    try {
      final f = await resolve(relPath);
      if (await f.exists()) return f;
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteRelative(String relPath) async {
    try {
      final f = await resolve(relPath);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Best effort.
    }
  }

  /// Lists user sticker files (relative paths).
  static Future<List<String>> listStickers() async {
    final dir = await stickersDir();
    final out = <String>[];
    await for (final e in dir.list()) {
      if (e is File) {
        final ext = p.extension(e.path).toLowerCase();
        if (ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.webp') {
          out.add('stickers/${p.basename(e.path)}');
        }
      }
    }
    out.sort();
    return out;
  }

  /// Lists every stored file (relative) — used by backup.
  static Future<List<String>> listAllFiles() async {
    final b = await base();
    final out = <String>[];
    await for (final e in b.list(recursive: true, followLinks: false)) {
      if (e is File) {
        out.add(p.relative(e.path, from: b.path));
      }
    }
    out.sort();
    return out;
  }
}
