import 'package:isar/isar.dart';

import '../models/library_models.dart';
import 'app_db.dart';
import 'stroke_repository.dart';

part 'library_repository.g.dart';

/// A library edge tab (color + emoji).
@collection
class TabEntity {
  Id id = Isar.autoIncrement;

  String name = '';

  int color = 0xFF1E6FF2;

  String emoji = '📓';

  int position = 0;

  TabEntity();

  TabEntity.of(this.name, this.color, this.emoji, this.position);
}

/// A (possibly nested) folder.
@collection
class FolderEntity {
  Id id = Isar.autoIncrement;

  String name = '';

  int color = 0xFF5A6B85;

  String emoji = '📁';

  int? parentId;

  int position = 0;

  FolderEntity();

  FolderEntity.of(this.name, this.color, this.emoji, this.parentId, this.position);
}

@collection
class NotebookEntity {
  Id id = Isar.autoIncrement;

  String title = '';

  /// Built-in cover id (c1..c8) or null when a custom image is used.
  String? coverId = 'c1';

  /// Relative path of a custom cover image (under the files dir).
  String? coverImagePath;

  int? folderId;

  bool favorite = false;

  DateTime createdAt = DateTime.now();

  DateTime modifiedAt = DateTime.now();

  DateTime openedAt = DateTime.now();

  /// Defaults applied to new pages.
  int template = 0; // TemplateId index
  int pageSize = 0; // PageSizeId index
  int paperColor = 0xFFFFFFFF;

  /// Flattened text of all TextEls — rebuilt on save, used by search.
  String textIndex = '';

  List<int> tagIds = [];

  /// Relative path of an imported PDF background (never modified).
  String? pdfPath;

  /// Soft delete.
  bool deleted = false;

  DateTime? deletedAt;

  NotebookEntity();

  NotebookEntity.of(this.title);
}

/// A page of a notebook.
///
/// CRITICAL: the Isar [id] IS the ink slot. Strokes and elements reference
/// pages by this stable id — never by visual index (pages can be reordered or
/// deleted; index-keyed ink corrupts).
@collection
class PageEntity {
  Id id = Isar.autoIncrement;

  int notebookId = 0;

  int position = 0;

  String title = '';

  bool bookmarked = false;

  int template = 0;

  int pageSize = 0;

  int paperColor = 0xFFFFFFFF;

  DateTime createdAt = DateTime.now();

  DateTime modifiedAt = DateTime.now();

  PageEntity();

  PageEntity.of(this.notebookId, this.position, this.template, this.pageSize,
      this.paperColor);
}

@collection
class TagEntity {
  Id id = Isar.autoIncrement;

  String name = '';

  int color = 0xFF9333EA;

  TagEntity();

  TagEntity.of(this.name, this.color);
}

@collection
class RecordingEntity {
  Id id = Isar.autoIncrement;

  int notebookId = 0;

  int pageId = 0;

  /// Relative path under the recordings dir.
  String path = '';

  int durationMs = 0;

  DateTime createdAt = DateTime.now();

  RecordingEntity();

  RecordingEntity.of(this.notebookId, this.pageId, this.path, this.durationMs);
}

/// Library-level CRUD + queries.
class LibraryRepository {
  LibraryRepository._();

  static final LibraryRepository I = LibraryRepository._();

  Isar get _db => AppDb.db;

  // ---------------------------------------------------------------- tabs

  Future<List<TabEntity>> tabs() async =>
      _db.tabEntitys.filter().idGreaterThan(-1).sortByPosition().findAll();

  Future<TabEntity> createTab(String name, int color, String emoji) async {
    final existing = await tabs();
    final t = TabEntity.of(name, color, emoji, existing.length);
    await _db.writeTxn(() async => await _db.tabEntitys.put(t));
    return t;
  }

  Future<void> updateTab(TabEntity t) async =>
      _db.writeTxn(() async => await _db.tabEntitys.put(t));

  Future<void> deleteTab(TabEntity t) async =>
      _db.writeTxn(() async => await _db.tabEntitys.delete(t.id));

  // ------------------------------------------------------------- folders

  Future<List<FolderEntity>> folders() async =>
      _db.folderEntitys.filter().idGreaterThan(-1).sortByPosition().findAll();

  Future<FolderEntity> createFolder(String name, int color, String emoji,
      int? parentId) async {
    final all = await folders();
    final siblings = all.where((f) => f.parentId == parentId).length;
    final f = FolderEntity.of(name, color, emoji, parentId, siblings);
    await _db.writeTxn(() async => await _db.folderEntitys.put(f));
    return f;
  }

  Future<void> updateFolder(FolderEntity f) async =>
      _db.writeTxn(() async => await _db.folderEntitys.put(f));

  Future<void> deleteFolder(FolderEntity f, {bool recursive = true}) async {
    final all = await folders();
    final children = all.where((x) => x.parentId == f.id).toList();
    await _db.writeTxn(() async {
      if (recursive) {
        for (final c in children) {
          c.parentId = f.parentId;
          await _db.folderEntitys.put(c);
        }
      }
      // Notebooks keep existing; they simply fall back to root.
      await _db.folderEntitys.delete(f.id);
    });
  }

  // ---------------------------------------------------------------- tags

  Future<List<TagEntity>> tags() async => _db.tagEntitys.filter().idGreaterThan(-1).findAll();

  Future<TagEntity> createTag(String name, int color) async {
    final t = TagEntity.of(name, color);
    await _db.writeTxn(() async => await _db.tagEntitys.put(t));
    return t;
  }

  Future<void> updateTag(TagEntity t) async =>
      _db.writeTxn(() async => await _db.tagEntitys.put(t));

  Future<void> deleteTag(TagEntity t) async =>
      _db.writeTxn(() async => await _db.tagEntitys.delete(t.id));

  // ------------------------------------------------------------ notebooks

  Future<NotebookEntity> createNotebook({
    required String title,
    String? coverId,
    String? coverImagePath,
    int? folderId,
    int template = 0,
    int pageSize = 0,
    int paperColor = 0xFFFFFFFF,
  }) async {
    final n = NotebookEntity.of(title);
    n.coverId = coverId;
    n.coverImagePath = coverImagePath;
    n.folderId = folderId;
    n.template = template;
    n.pageSize = pageSize;
    n.paperColor = paperColor;
    final page = PageEntity.of(n.id, 0, template, pageSize, paperColor);
    await _db.writeTxn(() async {
      final id = await _db.notebookEntitys.put(n);
      n.id = id;
      page.notebookId = id;
      await _db.pageEntitys.put(page);
    });
    return n;
  }

  Future<void> updateNotebook(NotebookEntity n) async =>
      _db.writeTxn(() async => await _db.notebookEntitys.put(n));

  Future<void> touchNotebook(int notebookId, {bool opened = false}) async {
    final n = await _db.notebookEntitys.get(notebookId);
    if (n == null) return;
    n.modifiedAt = DateTime.now();
    if (opened) n.openedAt = DateTime.now();
    await _db.writeTxn(() async => await _db.notebookEntitys.put(n));
  }

  Future<List<NotebookEntity>> activeNotebooks() async =>
      _db.notebookEntitys.filter().deletedEqualTo(false).findAll();

  Future<List<NotebookEntity>> trashedNotebooks() async =>
      _db.notebookEntitys.filter().deletedEqualTo(true).sortByDeletedAtDesc().findAll();

  Future<NotebookEntity?> notebook(int id) => _db.notebookEntitys.get(id);

  Future<void> setFavorite(NotebookEntity n, bool fav) async {
    n.favorite = fav;
    await updateNotebook(n);
  }

  Future<void> moveToFolder(NotebookEntity n, int? folderId) async {
    n.folderId = folderId;
    await updateNotebook(n);
  }

  /// Soft-deletes the notebook (trash, 30-day retention).
  Future<void> trashNotebook(NotebookEntity n) async {
    n.deleted = true;
    n.deletedAt = DateTime.now();
    await updateNotebook(n);
  }

  Future<void> restoreNotebook(NotebookEntity n) async {
    n.deleted = false;
    n.deletedAt = null;
    await updateNotebook(n);
  }

  /// Permanently deletes the notebook, its pages, ink, elements and
  /// recordings.
  Future<void> purgeNotebook(NotebookEntity n) async {
    final pages = await pagesOf(n.id);
    final recordings = await recordingsOf(n.id);
    await _db.writeTxn(() async {
      for (final p in pages) {
        await _db.strokeEntitys.filter().pageIdEqualTo(p.id).deleteAll();
        await _db.elementEntitys.filter().pageIdEqualTo(p.id).deleteAll();
        await _db.pageEntitys.delete(p.id);
      }
      for (final r in recordings) {
        await _db.recordingEntitys.delete(r.id);
      }
      await _db.notebookEntitys.delete(n.id);
    });
    await StrokeRepository.I.deleteNotebookFiles(n, pages, recordings);
  }

  Future<void> emptyTrash() async {
    final trashed = await trashedNotebooks();
    for (final n in trashed) {
      await purgeNotebook(n);
    }
  }

  /// Deletes trash older than [TRASH_RETENTION]. Call at startup.
  Future<void> purgeExpiredTrash() async {
    final cutoff = DateTime.now().subtract(TRASH_RETENTION);
    final trashed = await trashedNotebooks();
    for (final n in trashed) {
      if (n.deletedAt != null && n.deletedAt!.isBefore(cutoff)) {
        await purgeNotebook(n);
      }
    }
  }

  // ----------------------------------------------------------------- pages

  Future<List<PageEntity>> pagesOf(int notebookId) async =>
      _db.pageEntitys.filter().notebookIdEqualTo(notebookId).sortByPosition().findAll();

  Future<PageEntity?> page(int id) => _db.pageEntitys.get(id);

  Future<PageEntity> addPage(
    int notebookId,
    int position,
    int template,
    int pageSize,
    int paperColor,
  ) async {
    final p = PageEntity.of(notebookId, position, template, pageSize, paperColor);
    await _db.writeTxn(() async => await _db.pageEntitys.put(p));
    return p;
  }

  Future<void> updatePage(PageEntity p) async =>
      _db.writeTxn(() async => await _db.pageEntitys.put(p));

  Future<void> deletePage(PageEntity p) async {
    await _db.writeTxn(() async {
      await _db.strokeEntitys.filter().pageIdEqualTo(p.id).deleteAll();
      await _db.elementEntitys.filter().pageIdEqualTo(p.id).deleteAll();
      await _db.recordingEntitys.filter().pageIdEqualTo(p.id).deleteAll();
      await _db.pageEntitys.delete(p.id);
    });
  }

  /// Renumbers positions 0..n-1 in the given order of ids.
  Future<void> reorderPages(int notebookId, List<int> orderedIds) async {
    final pages = await pagesOf(notebookId);
    await _db.writeTxn(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        final p = pages.firstWhere((x) => x.id == orderedIds[i],
            orElse: () => PageEntity()..id = orderedIds[i]);
        p.position = i;
        await _db.pageEntitys.put(p);
      }
    });
  }

  Future<int> pageCount(int notebookId) async =>
      _db.pageEntitys.filter().notebookIdEqualTo(notebookId).count();

  // ------------------------------------------------------------ recordings

  Future<List<RecordingEntity>> recordingsOf(int notebookId) async => _db
      .recordingEntitys.filter().notebookIdEqualTo(notebookId).sortByCreatedAtDesc().findAll();

  Future<void> addRecording(RecordingEntity r) async =>
      _db.writeTxn(() async => await _db.recordingEntitys.put(r));

  Future<void> deleteRecording(RecordingEntity r) async =>
      _db.writeTxn(() async => await _db.recordingEntitys.delete(r.id));

  // -------------------------------------------------------------- raw access

  /// Dumps every entity (backup). Order matters for restore.
  Future<(List<TabEntity>, List<FolderEntity>, List<NotebookEntity>,
          List<PageEntity>, List<TagEntity>, List<RecordingEntity>)>
      dumpAll() async {
    final tabs = await _db.tabEntitys.filter().idGreaterThan(-1).sortByPosition().findAll();
    final folders = await _db.folderEntitys.filter().idGreaterThan(-1).sortByPosition().findAll();
    final notebooks = await _db.notebookEntitys.filter().idGreaterThan(-1).findAll();
    final pages = await _db.pageEntitys.filter().idGreaterThan(-1).findAll();
    final tags = await _db.tagEntitys.filter().idGreaterThan(-1).findAll();
    final recordings = await _db.recordingEntitys.filter().idGreaterThan(-1).findAll();
    return (tabs, folders, notebooks, pages, tags, recordings);
  }

  /// Reinserts entities preserving their numeric Isar ids (ink slots depend
  /// on them!). Assumes the DB was wiped beforehand.
  Future<void> restoreAll({
    required List<TabEntity> tabs,
    required List<FolderEntity> folders,
    required List<NotebookEntity> notebooks,
    required List<PageEntity> pages,
    required List<TagEntity> tags,
    required List<RecordingEntity> recordings,
  }) async {
    await _db.writeTxn(() async {
      for (final t in tabs) {
        await _db.tabEntitys.put(t);
      }
      for (final f in folders) {
        await _db.folderEntitys.put(f);
      }
      for (final n in notebooks) {
        await _db.notebookEntitys.put(n);
      }
      for (final p in pages) {
        await _db.pageEntitys.put(p);
      }
      for (final t in tags) {
        await _db.tagEntitys.put(t);
      }
      for (final r in recordings) {
        await _db.recordingEntitys.put(r);
      }
    });
  }
}
