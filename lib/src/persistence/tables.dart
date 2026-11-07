import 'package:drift/drift.dart';

/// Drift (SQLite) tables for the v1.0.0 rebuild. Column shapes mirror the
/// legacy Isar entities 1:1 so the plain entities in `entities.dart` (and the
/// `.nanote` backup format v2) stay byte-compatible.
///
/// IDs: INTEGER PRIMARY KEY (SQLite rowid semantics: auto-assigned ids start
/// at 1; restoring rows with explicit ids works and future auto ids continue
/// above the current max — same behavior the old Isar store had).

class Tabs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withDefault(const Constant(''))();
  IntColumn get color => integer().withDefault(const Constant(0xFF1E6FF2))();
  TextColumn get emoji => text().withDefault(const Constant('📓'))();
  IntColumn get position => integer().withDefault(const Constant(0))();
}

class Folders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withDefault(const Constant(''))();
  IntColumn get color => integer().withDefault(const Constant(0xFF5A6B85))();
  TextColumn get emoji => text().withDefault(const Constant('📁'))();
  IntColumn get parentId => integer().nullable()();
  IntColumn get position => integer().withDefault(const Constant(0))();
}

class Notebooks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get coverId => text().nullable()();
  TextColumn get coverImagePath => text().nullable()();
  IntColumn get folderId => integer().nullable()();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime()();
  DateTimeColumn get openedAt => dateTime()();
  IntColumn get template => integer().withDefault(const Constant(0))();
  IntColumn get pageSize => integer().withDefault(const Constant(0))();
  IntColumn get paperColor =>
      integer().withDefault(const Constant(0xFFFFFFFF))();
  TextColumn get textIndex => text().withDefault(const Constant(''))();

  /// JSON-encoded List<int> (kept as text for debuggability + easy backup
  /// round-tripping).
  TextColumn get tagIds => text().withDefault(const Constant('[]'))();
  TextColumn get pdfPath => text().nullable()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  List<String> get customConstraints => const [];
}

class Pages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get notebookId => integer()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  TextColumn get title => text().withDefault(const Constant(''))();
  BoolColumn get bookmarked => boolean().withDefault(const Constant(false))();
  IntColumn get template => integer().withDefault(const Constant(0))();
  IntColumn get pageSize => integer().withDefault(const Constant(0))();
  IntColumn get paperColor =>
      integer().withDefault(const Constant(0xFFFFFFFF))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime()();
}

class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withDefault(const Constant(''))();
  IntColumn get color => integer().withDefault(const Constant(0xFF9333EA))();
}

class Recordings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get notebookId => integer()();
  IntColumn get pageId => integer()();
  TextColumn get path => text().withDefault(const Constant(''))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
}

/// Ink strokes — `data` holds the exact legacy JSON (Stroke.toJson).
/// Row class renamed (`StrokeRow`) to avoid clashing with models/stroke.dart.
@DataClassName('StrokeRow')
@TableIndex(name: 'idx_strokes_page', columns: {#pageId, #z})
class Strokes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get pageId => integer()();
  IntColumn get z => integer().withDefault(const Constant(0))();
  TextColumn get data => text().withDefault(const Constant(''))();
}

/// Page elements — `data` holds the exact legacy JSON (elementToJson).
/// Row class renamed (`ElementRow`) to avoid clashing with model element types.
@DataClassName('ElementRow')
@TableIndex(name: 'idx_elements_page', columns: {#pageId, #z})
class Elements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get pageId => integer()();
  IntColumn get z => integer().withDefault(const Constant(0))();
  TextColumn get data => text().withDefault(const Constant(''))();
}
