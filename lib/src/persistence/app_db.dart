import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'library_repository.dart';
import 'stroke_repository.dart';

/// ONE Isar instance for ALL schemas. Open once at bootstrap.
class AppDb {
  AppDb._();

  static Isar? _isar;

  static bool get isReady => _isar != null;

  static Isar get db {
    final d = _isar;
    if (d == null) {
      throw StateError('AppDb.init() must be called before using the database');
    }
    return d;
  }

  static Future<void> init() async {
    if (_isar != null) return;
    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
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
      directory: dir.path,
      name: 'nanote',
      inspector: false,
    );
  }

  /// Wipes every collection (used by backup restore).
  static Future<void> wipeAll() async {
    final isar = db;
    await isar.writeTxn(() async {
      await isar.clear();
    });
  }
}
