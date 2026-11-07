import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'entities.dart';
import 'migration/migrator.dart';
import 'tables.dart';

part 'app_db.g.dart';

/// ONE Drift (SQLite) database for ALL tables. Open once at bootstrap.
///
/// Replaces the old Isar store (abandoned package that pinned the toolchain
/// to Flutter 3.29). Legacy Isar data is migrated in-place on first launch —
/// see `migration/migrator.dart`.
@DriftDatabase(
  tables: [Tabs, Folders, Notebooks, Pages, Tags, Recordings, Strokes, Elements],
)
class AppDb extends _$AppDb {
  AppDb._(super.e);

  /// Public test constructor (inject an in-memory executor).
  AppDb.forTesting(super.e);

  static AppDb? _db;

  static bool get isReady => _db != null;

  /// The opened database (throws if [init] was not called).
  static AppDb get db {
    final d = _db;
    if (d == null) {
      throw StateError('AppDb.init() must be called before using the database');
    }
    return d;
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
      );

  /// Opens the database, creating it if needed, then (once) migrates any
  /// legacy Isar data found next to it.
  static Future<void> init() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'nanote_v1.db'));
    final db = AppDb._(LazyDatabase(() async {
      return NativeDatabase.createInBackground(file);
    }));
    // Force the lazy connection open so migrations/query validation run now.
    await db.customSelect('SELECT 1').get();
    _db = db;
    await LegacyMigrator.runIfNeeded(db, docsDir: dir);
  }

  /// Test seam: inject an in-memory (or otherwise faked) database.
  static Future<void> initForTesting(AppDb db) async {
    if (_db != null) return;
    await db.customSelect('SELECT 1').get();
    _db = db;
  }

  /// Closes the singleton (tests only — the app never closes it).
  static Future<void> resetForTesting() async {
    final d = _db;
    _db = null;
    await d?.close();
  }

  /// Wipes every table (used by backup restore). IDs reset to Isar-era
  /// semantics (fresh autoincrement from 1).
  Future<void> wipeAll() async {
    await transaction(() async {
      for (final t in allTables) {
        await delete(t).go();
      }
    });
  }

  // ------------------------------------------------------------ row mappers
  // Kept here so both repositories share them.

  static List<int> decodeTagIds(String raw) {
    try {
      final v = jsonDecode(raw);
      if (v is List) return [for (final e in v) (e as num).toInt()];
    } catch (_) {
      // Corrupt cell: empty tags rather than crash.
    }
    return const [];
  }

  static String encodeTagIds(List<int> ids) => jsonEncode(ids);
}

/// Row ⇄ entity conversions (plain entities keep the whole app unchanged).
extension TabRowX on Tab {
  TabEntity toEntity() => TabEntity()
    ..id = id
    ..name = name
    ..color = color
    ..emoji = emoji
    ..position = position;
}

extension FolderRowX on Folder {
  FolderEntity toEntity() => FolderEntity()
    ..id = id
    ..name = name
    ..color = color
    ..emoji = emoji
    ..parentId = parentId
    ..position = position;
}

extension NotebookRowX on Notebook {
  NotebookEntity toEntity() => NotebookEntity()
    ..id = id
    ..title = title
    ..coverId = coverId
    ..coverImagePath = coverImagePath
    ..folderId = folderId
    ..favorite = favorite
    ..createdAt = createdAt
    ..modifiedAt = modifiedAt
    ..openedAt = openedAt
    ..template = template
    ..pageSize = pageSize
    ..paperColor = paperColor
    ..textIndex = textIndex
    ..tagIds = AppDb.decodeTagIds(tagIds)
    ..pdfPath = pdfPath
    ..deleted = deleted
    ..deletedAt = deletedAt;
}

extension PageRowX on Page {
  PageEntity toEntity() => PageEntity()
    ..id = id
    ..notebookId = notebookId
    ..position = position
    ..title = title
    ..bookmarked = bookmarked
    ..template = template
    ..pageSize = pageSize
    ..paperColor = paperColor
    ..createdAt = createdAt
    ..modifiedAt = modifiedAt;
}

extension TagRowX on Tag {
  TagEntity toEntity() => TagEntity()
    ..id = id
    ..name = name
    ..color = color;
}

extension RecordingRowX on Recording {
  RecordingEntity toEntity() => RecordingEntity()
    ..id = id
    ..notebookId = notebookId
    ..pageId = pageId
    ..path = path
    ..durationMs = durationMs
    ..createdAt = createdAt;
}

extension StrokeRowX on StrokeRow {
  StrokeEntity toEntity() => StrokeEntity()
    ..id = id
    ..pageId = pageId
    ..z = z
    ..data = data;
}

extension ElementRowX on ElementRow {
  ElementEntity toEntity() => ElementEntity()
    ..id = id
    ..pageId = pageId
    ..z = z
    ..data = data;
}
