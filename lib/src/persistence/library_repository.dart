import 'package:drift/drift.dart';

import '../models/library_models.dart';
import 'app_db.dart';
import 'entities.dart';
import 'stroke_repository.dart';

// The v2.x codebase defined these entities inside this file — keep the
// import surface identical for every consumer.
export 'entities.dart';

/// Library-level CRUD + queries. Same public API the whole app has always
/// used — now backed by Drift/SQLite instead of Isar.
class LibraryRepository {
  LibraryRepository._();

  static final LibraryRepository I = LibraryRepository._();

  AppDb get _db => AppDb.db;

  // ---------------------------------------------------------------- tabs

  Future<List<TabEntity>> tabs() async {
    final rows = await (_db.select(_db.tabs)
          ..orderBy([(r) => OrderingTerm.asc(r.position)]))
        .get();
    return [for (final r in rows) r.toEntity()];
  }

  Future<TabEntity> createTab(String name, int color, String emoji) async {
    final existing = await tabs();
    final t = TabEntity.of(name, color, emoji, existing.length);
    t.id = await _db
        .into(_db.tabs)
        .insert(TabsCompanion.insert(
          name: Value(name),
          color: Value(color),
          emoji: Value(emoji),
          position: Value(existing.length),
        ));
    return t;
  }

  Future<void> updateTab(TabEntity t) async {
    await (_db.update(_db.tabs)..where((r) => r.id.equals(t.id))).write(
      TabsCompanion(
        name: Value(t.name),
        color: Value(t.color),
        emoji: Value(t.emoji),
        position: Value(t.position),
      ),
    );
  }

  Future<void> deleteTab(TabEntity t) async {
    await (_db.delete(_db.tabs)..where((r) => r.id.equals(t.id))).go();
  }

  // ------------------------------------------------------------- folders

  Future<List<FolderEntity>> folders() async {
    final rows = await (_db.select(_db.folders)
          ..orderBy([(r) => OrderingTerm.asc(r.position)]))
        .get();
    return [for (final r in rows) r.toEntity()];
  }

  Future<FolderEntity> createFolder(
      String name, int color, String emoji, int? parentId) async {
    final all = await folders();
    final siblings =
        all.where((f) => f.parentId == parentId).length;
    final f = FolderEntity.of(name, color, emoji, parentId, siblings);
    f.id = await _db.into(_db.folders).insert(FoldersCompanion.insert(
          name: Value(name),
          color: Value(color),
          emoji: Value(emoji),
          parentId: Value(parentId),
          position: Value(siblings),
        ));
    return f;
  }

  Future<void> updateFolder(FolderEntity f) async {
    await (_db.update(_db.folders)..where((r) => r.id.equals(f.id))).write(
      FoldersCompanion(
        name: Value(f.name),
        color: Value(f.color),
        emoji: Value(f.emoji),
        parentId: Value(f.parentId),
        position: Value(f.position),
      ),
    );
  }

  Future<void> deleteFolder(FolderEntity f, {bool recursive = true}) async {
    final all = await folders();
    final children = all.where((x) => x.parentId == f.id).toList();
    await _db.transaction(() async {
      if (recursive) {
        for (final c in children) {
          c.parentId = f.parentId;
          await updateFolder(c);
        }
      }
      // Notebooks keep existing; they simply fall back to root.
      await (_db.delete(_db.folders)..where((r) => r.id.equals(f.id))).go();
    });
  }

  // ---------------------------------------------------------------- tags

  Future<List<TagEntity>> tags() async {
    final rows = await _db.select(_db.tags).get();
    return [for (final r in rows) r.toEntity()];
  }

  Future<TagEntity> createTag(String name, int color) async {
    final t = TagEntity.of(name, color);
    t.id = await _db.into(_db.tags).insert(
        TagsCompanion.insert(name: Value(name), color: Value(color)));
    return t;
  }

  Future<void> updateTag(TagEntity t) async {
    await (_db.update(_db.tags)..where((r) => r.id.equals(t.id))).write(
      TagsCompanion(name: Value(t.name), color: Value(t.color)),
    );
  }

  Future<void> deleteTag(TagEntity t) async {
    await (_db.delete(_db.tags)..where((r) => r.id.equals(t.id))).go();
  }

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
    final now = DateTime.now();
    final n = NotebookEntity.of(title)
      ..coverId = coverId
      ..coverImagePath = coverImagePath
      ..folderId = folderId
      ..template = template
      ..pageSize = pageSize
      ..paperColor = paperColor;
    await _db.transaction(() async {
      final id = await _db.into(_db.notebooks).insert(NotebooksCompanion.insert(
            title: Value(title),
            coverId: Value(coverId),
            coverImagePath: Value(coverImagePath),
            folderId: Value(folderId),
            favorite: const Value(false),
            createdAt: now,
            modifiedAt: now,
            openedAt: now,
            template: Value(template),
            pageSize: Value(pageSize),
            paperColor: Value(paperColor),
          ));
      n.id = id;
      await _db.into(_db.pages).insert(PagesCompanion.insert(
            notebookId: id,
            position: const Value(0),
            template: Value(template),
            pageSize: Value(pageSize),
            paperColor: Value(paperColor),
            createdAt: now,
            modifiedAt: now,
          ));
    });
    return n;
  }

  Future<void> updateNotebook(NotebookEntity n) async {
    await (_db.update(_db.notebooks)..where((r) => r.id.equals(n.id))).write(
      NotebooksCompanion(
        title: Value(n.title),
        coverId: Value(n.coverId),
        coverImagePath: Value(n.coverImagePath),
        folderId: Value(n.folderId),
        favorite: Value(n.favorite),
        createdAt: Value(n.createdAt),
        modifiedAt: Value(n.modifiedAt),
        openedAt: Value(n.openedAt),
        template: Value(n.template),
        pageSize: Value(n.pageSize),
        paperColor: Value(n.paperColor),
        textIndex: Value(n.textIndex),
        tagIds: Value(AppDb.encodeTagIds(n.tagIds)),
        pdfPath: Value(n.pdfPath),
        deleted: Value(n.deleted),
        deletedAt: Value(n.deletedAt),
      ),
    );
  }

  Future<void> touchNotebook(int notebookId, {bool opened = false}) async {
    final n = await notebook(notebookId);
    if (n == null) return;
    n.modifiedAt = DateTime.now();
    if (opened) n.openedAt = DateTime.now();
    await updateNotebook(n);
  }

  Future<List<NotebookEntity>> activeNotebooks() async {
    final rows = await (_db.select(_db.notebooks)
          ..where((r) => r.deleted.equals(false)))
        .get();
    return [for (final r in rows) r.toEntity()];
  }

  Future<List<NotebookEntity>> trashedNotebooks() async {
    final rows = await (_db.select(_db.notebooks)
          ..where((r) => r.deleted.equals(true))
          ..orderBy([(r) => OrderingTerm.desc(r.deletedAt)]))
        .get();
    return [for (final r in rows) r.toEntity()];
  }

  Future<NotebookEntity?> notebook(int id) async {
    final row =
        await (_db.select(_db.notebooks)..where((r) => r.id.equals(id)))
            .getSingleOrNull();
    return row?.toEntity();
  }

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
    await _db.transaction(() async {
      for (final p in pages) {
        await (_db.delete(_db.strokes)..where((r) => r.pageId.equals(p.id)))
            .go();
        await (_db.delete(_db.elements)..where((r) => r.pageId.equals(p.id)))
            .go();
        await (_db.delete(_db.pages)..where((r) => r.id.equals(p.id))).go();
      }
      for (final r in recordings) {
        await (_db.delete(_db.recordings)..where((x) => x.id.equals(r.id)))
            .go();
      }
      await (_db.delete(_db.notebooks)..where((r) => r.id.equals(n.id))).go();
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

  Future<List<PageEntity>> pagesOf(int notebookId) async {
    final rows = await (_db.select(_db.pages)
          ..where((r) => r.notebookId.equals(notebookId))
          ..orderBy([(r) => OrderingTerm.asc(r.position)]))
        .get();
    return [for (final r in rows) r.toEntity()];
  }

  Future<PageEntity?> page(int id) async {
    final row = await (_db.select(_db.pages)..where((r) => r.id.equals(id)))
        .getSingleOrNull();
    return row?.toEntity();
  }

  Future<PageEntity> addPage(
    int notebookId,
    int position,
    int template,
    int pageSize,
    int paperColor,
  ) async {
    final now = DateTime.now();
    final p = PageEntity.of(notebookId, position, template, pageSize, paperColor)
      ..createdAt = now
      ..modifiedAt = now;
    p.id = await _db.into(_db.pages).insert(PagesCompanion.insert(
          notebookId: notebookId,
          position: Value(position),
          template: Value(template),
          pageSize: Value(pageSize),
          paperColor: Value(paperColor),
          createdAt: now,
          modifiedAt: now,
        ));
    return p;
  }

  Future<void> updatePage(PageEntity p) async {
    await (_db.update(_db.pages)..where((r) => r.id.equals(p.id))).write(
      PagesCompanion(
        notebookId: Value(p.notebookId),
        position: Value(p.position),
        title: Value(p.title),
        bookmarked: Value(p.bookmarked),
        template: Value(p.template),
        pageSize: Value(p.pageSize),
        paperColor: Value(p.paperColor),
        createdAt: Value(p.createdAt),
        modifiedAt: Value(p.modifiedAt),
      ),
    );
  }

  Future<void> deletePage(PageEntity p) async {
    await _db.transaction(() async {
      await (_db.delete(_db.strokes)..where((r) => r.pageId.equals(p.id)))
          .go();
      await (_db.delete(_db.elements)..where((r) => r.pageId.equals(p.id)))
          .go();
      await (_db.delete(_db.recordings)
            ..where((r) => r.pageId.equals(p.id)))
          .go();
      await (_db.delete(_db.pages)..where((r) => r.id.equals(p.id))).go();
    });
  }

  /// Renumbers positions 0..n-1 in the given order of ids.
  Future<void> reorderPages(int notebookId, List<int> orderedIds) async {
    final pages = await pagesOf(notebookId);
    await _db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        final match =
            pages.where((x) => x.id == orderedIds[i]).firstOrNull;
        if (match == null) continue;
        match.position = i;
        await (_db.update(_db.pages)..where((r) => r.id.equals(match.id)))
            .write(PagesCompanion(position: Value(i)));
      }
    });
  }

  Future<int> pageCount(int notebookId) async {
    final count = countAll();
    final row = await (_db.selectOnly(_db.pages)
          ..addColumns([count])
          ..where(_db.pages.notebookId.equals(notebookId)))
        .getSingle();
    return row.read(count) ?? 0;
  }

  // ------------------------------------------------------------ recordings

  Future<List<RecordingEntity>> recordingsOf(int notebookId) async {
    final rows = await (_db.select(_db.recordings)
          ..where((r) => r.notebookId.equals(notebookId))
          ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
        .get();
    return [for (final r in rows) r.toEntity()];
  }

  Future<void> addRecording(RecordingEntity r) async {
    r.id = await _db.into(_db.recordings).insert(RecordingsCompanion.insert(
          notebookId: r.notebookId,
          pageId: r.pageId,
          path: Value(r.path),
          durationMs: Value(r.durationMs),
          createdAt: r.createdAt,
        ));
  }

  Future<void> deleteRecording(RecordingEntity r) async {
    await (_db.delete(_db.recordings)..where((x) => x.id.equals(r.id))).go();
  }

  // -------------------------------------------------------------- raw access

  /// Dumps every entity (backup). Order matters for restore.
  Future<(List<TabEntity>, List<FolderEntity>, List<NotebookEntity>,
          List<PageEntity>, List<TagEntity>, List<RecordingEntity>)>
      dumpAll() async {
    final tabs = await this.tabs();
    final folders = await this.folders();
    final notebooks = [for (final r in await _db.select(_db.notebooks).get()) r.toEntity()];
    final pages = [for (final r in await _db.select(_db.pages).get()) r.toEntity()];
    final tags = await this.tags();
    final recordings = [for (final r in await _db.select(_db.recordings).get()) r.toEntity()];
    return (tabs, folders, notebooks, pages, tags, recordings);
  }

  /// Reinserts entities preserving their numeric ids (ink slots depend on
  /// them!). Assumes the DB was wiped beforehand.
  Future<void> restoreAll({
    required List<TabEntity> tabs,
    required List<FolderEntity> folders,
    required List<NotebookEntity> notebooks,
    required List<PageEntity> pages,
    required List<TagEntity> tags,
    required List<RecordingEntity> recordings,
  }) async {
    await _db.transaction(() async {
      for (final t in tabs) {
        await _db.into(_db.tabs).insert(TabsCompanion.insert(
              id: Value(t.id),
              name: Value(t.name),
              color: Value(t.color),
              emoji: Value(t.emoji),
              position: Value(t.position),
            ));
      }
      for (final f in folders) {
        await _db.into(_db.folders).insert(FoldersCompanion.insert(
              id: Value(f.id),
              name: Value(f.name),
              color: Value(f.color),
              emoji: Value(f.emoji),
              parentId: Value(f.parentId),
              position: Value(f.position),
            ));
      }
      for (final n in notebooks) {
        await _db.into(_db.notebooks).insert(NotebooksCompanion.insert(
              id: Value(n.id),
              title: Value(n.title),
              coverId: Value(n.coverId),
              coverImagePath: Value(n.coverImagePath),
              folderId: Value(n.folderId),
              favorite: Value(n.favorite),
              createdAt: n.createdAt,
              modifiedAt: n.modifiedAt,
              openedAt: n.openedAt,
              template: Value(n.template),
              pageSize: Value(n.pageSize),
              paperColor: Value(n.paperColor),
              textIndex: Value(n.textIndex),
              tagIds: Value(AppDb.encodeTagIds(n.tagIds)),
              pdfPath: Value(n.pdfPath),
              deleted: Value(n.deleted),
              deletedAt: Value(n.deletedAt),
            ));
      }
      for (final p in pages) {
        await _db.into(_db.pages).insert(PagesCompanion.insert(
              id: Value(p.id),
              notebookId: p.notebookId,
              position: Value(p.position),
              title: Value(p.title),
              bookmarked: Value(p.bookmarked),
              template: Value(p.template),
              pageSize: Value(p.pageSize),
              paperColor: Value(p.paperColor),
              createdAt: p.createdAt,
              modifiedAt: p.modifiedAt,
            ));
      }
      for (final t in tags) {
        await _db.into(_db.tags).insert(TagsCompanion.insert(
              id: Value(t.id),
              name: Value(t.name),
              color: Value(t.color),
            ));
      }
      for (final r in recordings) {
        await _db.into(_db.recordings).insert(RecordingsCompanion.insert(
              id: Value(r.id),
              notebookId: r.notebookId,
              pageId: r.pageId,
              path: Value(r.path),
              durationMs: Value(r.durationMs),
              createdAt: r.createdAt,
            ));
      }
    });
  }
}
