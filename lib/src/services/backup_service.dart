import 'dart:convert';
import 'dart:io';

import '../controllers/settings_controller.dart';
import '../controllers/stroke_engine.dart';
import '../models/settings.dart';
import '../persistence/app_db.dart';
import '../persistence/file_store.dart';
import '../persistence/library_repository.dart';
import '../persistence/stroke_repository.dart';

/// Single-file `.nanote` backup: one JSON document containing the settings,
/// every library entity, every ink/element row and every stored file
/// (base64). Restore wipes the database + files and reinserts everything
/// PRESERVING the numeric Isar ids (page ids are the ink slots!).
class BackupService {
  BackupService._();

  static const int formatVersion = 2;

  /// Writes a full backup to a temp file and returns its path (for sharing),
  /// or null on failure.
  static Future<String?> createBackup() async {
    try {
      // Make sure no unsaved ink is left in memory.
      try {
        await StrokeEngine.I.flush();
      } catch (_) {
        // No notebook open / db hiccup: keep going with stored state.
      }

      final settings = SettingsController.I.settings.toJson();
      final (tabs, folders, notebooks, pages, tags, recordings) =
          await LibraryRepository.I.dumpAll();
      final strokes = await StrokeRepository.I.dumpStrokes();
      final elements = await StrokeRepository.I.dumpElements();

      final files = <String, String>{};
      for (final rel in await FileStore.listAllFiles()) {
        try {
          final f = await FileStore.resolve(rel);
          files[rel] = base64Encode(await f.readAsBytes());
        } catch (_) {
          // Unreadable file: skip it rather than fail the whole backup.
        }
      }

      final doc = <String, dynamic>{
        'format': formatVersion,
        'createdAt': DateTime.now().toIso8601String(),
        'settings': settings,
        'entities': {
          'tabs': [for (final t in tabs) _tabToMap(t)],
          'folders': [for (final f in folders) _folderToMap(f)],
          'notebooks': [for (final n in notebooks) _notebookToMap(n)],
          'pages': [for (final p in pages) _pageToMap(p)],
          'tags': [for (final t in tags) _tagToMap(t)],
          'recordings': [for (final r in recordings) _recordingToMap(r)],
        },
        'ink': {
          'strokes': [
            for (final s in strokes)
              {'id': s.id, 'pageId': s.pageId, 'z': s.z, 'data': s.data},
          ],
          'elements': [
            for (final e in elements)
              {'id': e.id, 'pageId': e.pageId, 'z': e.z, 'data': e.data},
          ],
        },
        'files': files,
      };

      final ts = DateTime.now().millisecondsSinceEpoch;
      final file =
          File('${Directory.systemTemp.path}/nanote_backup_$ts.nanote');
      await file.writeAsString(jsonEncode(doc));
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Parses the backup, wipes the DB + stored files, then reinserts
  /// everything with the ORIGINAL ids. Returns false on any failure (the UI
  /// restart afterwards is handled by main.dart).
  static Future<bool> restoreBackup(File file) async {
    try {
      final raw = await file.readAsString();
      final doc = (jsonDecode(raw) as Map).cast<String, dynamic>();
      if ((doc['format'] as num?)?.toInt() != formatVersion) return false;

      // Parse EVERYTHING before touching existing data.
      final entities = _asMap(doc['entities']);
      final tabs = [for (final m in _list(entities['tabs'])) _tabFromMap(m)];
      final folders = [
        for (final m in _list(entities['folders'])) _folderFromMap(m)
      ];
      final notebooks = [
        for (final m in _list(entities['notebooks'])) _notebookFromMap(m)
      ];
      final pages = [for (final m in _list(entities['pages'])) _pageFromMap(m)];
      final tags = [for (final m in _list(entities['tags'])) _tagFromMap(m)];
      final recordings = [
        for (final m in _list(entities['recordings'])) _recordingFromMap(m)
      ];

      final ink = _asMap(doc['ink']);
      final strokeRows = <StrokeEntity>[];
      for (final m in _list(ink['strokes'])) {
        final e = StrokeEntity();
        e.id = _asInt(m['id']);
        e.pageId = _asInt(m['pageId']);
        e.z = _asInt(m['z']);
        e.data = m['data'] as String? ?? '';
        strokeRows.add(e);
      }
      final elementRows = <ElementEntity>[];
      for (final m in _list(ink['elements'])) {
        final e = ElementEntity();
        e.id = _asInt(m['id']);
        e.pageId = _asInt(m['pageId']);
        e.z = _asInt(m['z']);
        e.data = m['data'] as String? ?? '';
        elementRows.add(e);
      }

      final files = _asMap(doc['files']);

      // Wipe the database and every stored file.
      await AppDb.wipeAll();
      try {
        for (final rel in await FileStore.listAllFiles()) {
          await FileStore.deleteRelative(rel);
        }
      } catch (_) {
        // Best effort.
      }

      // Reinsert entities + ink with their original ids.
      await LibraryRepository.I.restoreAll(
        tabs: tabs,
        folders: folders,
        notebooks: notebooks,
        pages: pages,
        tags: tags,
        recordings: recordings,
      );
      await StrokeRepository.I.restoreStrokes(strokeRows);
      await StrokeRepository.I.restoreElements(elementRows);

      // Restore files (base64 -> FileStore, creating parent dirs).
      for (final entry in files.entries) {
        try {
          final f = await FileStore.resolve(entry.key);
          await f.parent.create(recursive: true);
          await f.writeAsBytes(base64Decode(entry.value as String));
        } catch (_) {
          // Best effort: one broken file must not abort the restore.
        }
      }

      // Restore settings.
      final s = doc['settings'];
      if (s is Map) {
        SettingsController.I.settings =
            AppSettings.fromJson(s.cast<String, dynamic>());
        await SettingsController.I.saveRaw();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------- helpers

  static Map<String, dynamic> _asMap(dynamic v) =>
      (v as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

  static List<Map<String, dynamic>> _list(dynamic v) => [
        for (final e in (v as List? ?? const []))
          (e as Map).cast<String, dynamic>(),
      ];

  static int _asInt(dynamic v) => (v as num?)?.toInt() ?? 0;

  static DateTime _asDate(dynamic v, [DateTime? fallback]) {
    if (v is String) {
      return DateTime.tryParse(v) ?? fallback ?? DateTime.now();
    }
    return fallback ?? DateTime.now();
  }

  // ---------------------------------------------------------------- tabs

  static Map<String, dynamic> _tabToMap(TabEntity t) => {
        'id': t.id,
        'name': t.name,
        'color': t.color,
        'emoji': t.emoji,
        'position': t.position,
      };

  static TabEntity _tabFromMap(Map<String, dynamic> m) {
    final t = TabEntity()
      ..id = _asInt(m['id'])
      ..name = m['name'] as String? ?? ''
      ..color = _asInt(m['color'])
      ..emoji = m['emoji'] as String? ?? '📓'
      ..position = _asInt(m['position']);
    return t;
  }

  // -------------------------------------------------------------- folders

  static Map<String, dynamic> _folderToMap(FolderEntity f) => {
        'id': f.id,
        'name': f.name,
        'color': f.color,
        'emoji': f.emoji,
        'parentId': f.parentId,
        'position': f.position,
      };

  static FolderEntity _folderFromMap(Map<String, dynamic> m) {
    final f = FolderEntity()
      ..id = _asInt(m['id'])
      ..name = m['name'] as String? ?? ''
      ..color = _asInt(m['color'])
      ..emoji = m['emoji'] as String? ?? '📁'
      ..parentId = m['parentId'] as int?
      ..position = _asInt(m['position']);
    return f;
  }

  // ------------------------------------------------------------ notebooks

  static Map<String, dynamic> _notebookToMap(NotebookEntity n) => {
        'id': n.id,
        'title': n.title,
        'coverId': n.coverId,
        'coverImagePath': n.coverImagePath,
        'folderId': n.folderId,
        'favorite': n.favorite,
        'createdAt': n.createdAt.toIso8601String(),
        'modifiedAt': n.modifiedAt.toIso8601String(),
        'openedAt': n.openedAt.toIso8601String(),
        'template': n.template,
        'pageSize': n.pageSize,
        'paperColor': n.paperColor,
        'textIndex': n.textIndex,
        'tagIds': n.tagIds,
        'pdfPath': n.pdfPath,
        'deleted': n.deleted,
        'deletedAt': n.deletedAt?.toIso8601String(),
      };

  static NotebookEntity _notebookFromMap(Map<String, dynamic> m) {
    final n = NotebookEntity()
      ..id = _asInt(m['id'])
      ..title = m['title'] as String? ?? ''
      ..coverId = m['coverId'] as String?
      ..coverImagePath = m['coverImagePath'] as String?
      ..folderId = m['folderId'] as int?
      ..favorite = m['favorite'] as bool? ?? false
      ..createdAt = _asDate(m['createdAt'])
      ..modifiedAt = _asDate(m['modifiedAt'])
      ..openedAt = _asDate(m['openedAt'])
      ..template = _asInt(m['template'])
      ..pageSize = _asInt(m['pageSize'])
      ..paperColor = _asInt(m['paperColor'])
      ..textIndex = m['textIndex'] as String? ?? ''
      ..tagIds = [
        for (final e in (m['tagIds'] as List? ?? const [])) (e as num).toInt(),
      ]
      ..pdfPath = m['pdfPath'] as String?
      ..deleted = m['deleted'] as bool? ?? false
      ..deletedAt = m['deletedAt'] == null
          ? null
          : _asDate(m['deletedAt']);
    return n;
  }

  // --------------------------------------------------------------- pages

  static Map<String, dynamic> _pageToMap(PageEntity p) => {
        'id': p.id,
        'notebookId': p.notebookId,
        'position': p.position,
        'title': p.title,
        'bookmarked': p.bookmarked,
        'template': p.template,
        'pageSize': p.pageSize,
        'paperColor': p.paperColor,
        'createdAt': p.createdAt.toIso8601String(),
        'modifiedAt': p.modifiedAt.toIso8601String(),
      };

  static PageEntity _pageFromMap(Map<String, dynamic> m) {
    final p = PageEntity()
      ..id = _asInt(m['id'])
      ..notebookId = _asInt(m['notebookId'])
      ..position = _asInt(m['position'])
      ..title = m['title'] as String? ?? ''
      ..bookmarked = m['bookmarked'] as bool? ?? false
      ..template = _asInt(m['template'])
      ..pageSize = _asInt(m['pageSize'])
      ..paperColor = _asInt(m['paperColor'])
      ..createdAt = _asDate(m['createdAt'])
      ..modifiedAt = _asDate(m['modifiedAt']);
    return p;
  }

  // ---------------------------------------------------------------- tags

  static Map<String, dynamic> _tagToMap(TagEntity t) => {
        'id': t.id,
        'name': t.name,
        'color': t.color,
      };

  static TagEntity _tagFromMap(Map<String, dynamic> m) {
    final t = TagEntity()
      ..id = _asInt(m['id'])
      ..name = m['name'] as String? ?? ''
      ..color = _asInt(m['color']);
    return t;
  }

  // ---------------------------------------------------------- recordings

  static Map<String, dynamic> _recordingToMap(RecordingEntity r) => {
        'id': r.id,
        'notebookId': r.notebookId,
        'pageId': r.pageId,
        'path': r.path,
        'durationMs': r.durationMs,
        'createdAt': r.createdAt.toIso8601String(),
      };

  static RecordingEntity _recordingFromMap(Map<String, dynamic> m) {
    final r = RecordingEntity()
      ..id = _asInt(m['id'])
      ..notebookId = _asInt(m['notebookId'])
      ..pageId = _asInt(m['pageId'])
      ..path = m['path'] as String? ?? ''
      ..durationMs = _asInt(m['durationMs'])
      ..createdAt = _asDate(m['createdAt']);
    return r;
  }
}
