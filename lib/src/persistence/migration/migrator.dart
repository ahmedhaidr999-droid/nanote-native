import 'dart:io';

import 'package:isar/isar.dart';
import 'package:path/path.dart' as p;

import '../app_db.dart';
import '../entities.dart';
import '../library_repository.dart';
import '../stroke_repository.dart';
import 'isar_legacy.dart';

/// One-time migration: legacy Isar (v2.x) → Drift/SQLite (v1.0.0+).
///
/// The old app kept its database in `<docs>/nanote.isar`. When the rebuilt
/// app starts for the first time it looks for that file; if present it reads
/// every collection through the legacy schemas and reinserts the rows into
/// Drift PRESERVING the numeric ids (page ids are the ink slots!). The old
/// Isar files are then renamed to `*.migrated` and a flag file prevents any
/// repeat.
///
/// Failure policy: any error (missing native core on exotic devices, corrupt
/// data, …) leaves the old files untouched and simply starts fresh — the
/// user can always restore a `.nanote` backup from Settings.
class LegacyMigrator {
  LegacyMigrator._();

  static const String _flagName = 'nanote_v1_migrated.flag';

  /// Returns true when legacy data was found and imported.
  static Future<bool> runIfNeeded(AppDb db, {required Directory docsDir}) async {
    final flag = File(p.join(docsDir.path, _flagName));
    try {
      if (await flag.exists()) return false;
    } catch (_) {
      return false;
    }

    // Locate legacy Isar files (the old app opened name:'nanote' in docs/).
    final List<FileSystemEntity> entries;
    try {
      entries = docsDir.listSync(followLinks: false);
    } catch (_) {
      return false;
    }
    final isarFiles = entries
        .whereType<File>()
        .where((f) {
          final n = p.basename(f.path);
          return n.startsWith('nanote') && n.endsWith('.isar');
        })
        .toList();
    if (isarFiles.isEmpty) {
      // Nothing to migrate — remember the decision.
      try {
        await flag.writeAsString('none\n');
      } catch (_) {}
      return false;
    }

    // Guard: if Drift already holds data (interrupted earlier migration that
    // committed but could not write the flag), just finalize.
    final existingNotebooks = await db.select(db.notebooks).get();
    if (existingNotebooks.isNotEmpty) {
      await _finalize(docsDir, isarFiles, flag);
      return true;
    }

    Isar? isar;
    try {
      isar = await Isar.open(
        [
          TabEntitySchema,
          FolderEntitySchema,
          NotebookEntitySchema,
          PageEntitySchema,
          TagEntitySchema,
          RecordingEntitySchema,
          StrokeEntitySchema,
          ElementEntitySchema,
        ],
        directory: docsDir.path,
        name: 'nanote',
        inspector: false,
      );

      final tabs = await _all(isar.collection<TabEntity>());
      final folders = await _all(isar.collection<FolderEntity>());
      final notebooks = await _all(isar.collection<NotebookEntity>());
      final pages = await _all(isar.collection<PageEntity>());
      final tags = await _all(isar.collection<TagEntity>());
      final recordings = await _all(isar.collection<RecordingEntity>());
      final strokes = await _all(isar.collection<StrokeEntity>());
      final elements = await _all(isar.collection<ElementEntity>());

      await LibraryRepository.I.restoreAll(
        tabs: tabs,
        folders: folders,
        notebooks: notebooks,
        pages: pages,
        tags: tags,
        recordings: recordings,
      );
      await StrokeRepository.I.restoreStrokes(strokes);
      await StrokeRepository.I.restoreElements(elements);

      await isar.close();
      await _finalize(docsDir, isarFiles, flag);
      return true;
    } catch (_) {
      try {
        await isar?.close();
      } catch (_) {
        // Best effort.
      }
      return false;
    }
  }

  /// Reads every object of a legacy collection. Isar 3 has no parameter-less
  /// getAll — an empty IdWhereClause traverses the whole primary index.
  static Future<List<T>> _all<T>(IsarCollection<T> c) {
    // ignore: experimental_member_use, invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    final query = c.buildQuery<T>(
      whereClauses: const [IdWhereClause.any()],
    );
    return query.findAll();
  }

  static Future<void> _finalize(
    Directory docsDir,
    List<File> isarFiles,
    File flag,
  ) async {
    for (final f in isarFiles) {
      try {
        await f.rename('${f.path}.migrated');
      } catch (_) {
        // Renaming is only cosmetic — the flag is the real guard.
      }
    }
    // Also rename the lock file if present.
    try {
      final lock = File(p.join(docsDir.path, 'nanote.lock'));
      if (await lock.exists()) {
        await lock.rename('${lock.path}.migrated');
      }
    } catch (_) {}
    try {
      await flag.writeAsString('ok\n');
    } catch (_) {}
  }
}
