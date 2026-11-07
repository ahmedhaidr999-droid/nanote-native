import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../i18n/strings.dart';
import '../models/library_models.dart';
import '../models/paper.dart';
import '../persistence/file_store.dart';
import '../persistence/library_repository.dart';

/// Library state: tabs, folders, tags and the FILTERED [notebooks] list.
///
/// Tabs are cosmetic quick-switch views (a [TabEntity] holds no data): picking
/// one resets the view to the root of the "all" section. Folder filtering
/// applies in the all/favorites sections (null folder = root); the trash
/// section ignores folders. Search matches title, text index, tag names and
/// the notebook's folder path — case-insensitive, instant (synchronous
/// refilter over the cached section list).
class LibraryController extends ChangeNotifier {
  LibraryController._();

  static final LibraryController I = LibraryController._();

  List<TabEntity> tabs = [];
  List<FolderEntity> folders = [];
  List<TagEntity> tags = [];

  /// FILTERED result list (section + folder + query + sort applied).
  List<NotebookEntity> notebooks = [];

  int? selectedTabId; // null = "All"
  int? currentFolderId; // null = root
  LibrarySection section = LibrarySection.all;
  String query = '';
  SortKey sortKey = SortKey.opened;
  bool sortAsc = false;
  ViewMode viewMode = ViewMode.grid;

  /// Section-scoped, unfiltered notebook list (active or trashed).
  List<NotebookEntity> _sectionAll = [];

  /// notebookId -> page count, filled asynchronously after each refilter.
  final Map<int, int> _pageCounts = {};

  int? pageCountOf(int notebookId) => _pageCounts[notebookId];

  // ------------------------------------------------------------------ reload

  Future<void> reload() async {
    tabs = await LibraryRepository.I.tabs();
    folders = await LibraryRepository.I.folders();
    tags = await LibraryRepository.I.tags();
    _sectionAll = section == LibrarySection.trash
        ? await LibraryRepository.I.trashedNotebooks()
        : await LibraryRepository.I.activeNotebooks();
    _applyFilters();
  }

  void _applyFilters() {
    var list = List<NotebookEntity>.of(_sectionAll);

    if (section == LibrarySection.favorites) {
      list = list.where((n) => n.favorite).toList();
    }
    if (section != LibrarySection.trash) {
      // Folder filter (null = root). The trash section ignores folders.
      list = list.where((n) => n.folderId == currentFolderId).toList();
    }

    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((n) {
        if (n.title.toLowerCase().contains(q)) return true;
        if (n.textIndex.toLowerCase().contains(q)) return true;
        for (final t in tags) {
          if (n.tagIds.contains(t.id) && t.name.toLowerCase().contains(q)) {
            return true;
          }
        }
        if (_pathNames(n.folderId).toLowerCase().contains(q)) return true;
        return false;
      }).toList();
    }

    list.sort(_compare);
    notebooks = list;
    _loadPageCounts();
    notifyListeners();
  }

  int _compare(NotebookEntity a, NotebookEntity b) {
    final int c = switch (sortKey) {
      SortKey.opened => a.openedAt.compareTo(b.openedAt),
      SortKey.modified => a.modifiedAt.compareTo(b.modifiedAt),
      SortKey.created => a.createdAt.compareTo(b.createdAt),
      SortKey.title => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    };
    return sortAsc ? c : -c;
  }

  void _loadPageCounts() {
    for (final n in notebooks) {
      final id = n.id;
      if (_pageCounts.containsKey(id)) continue;
      unawaited(LibraryRepository.I.pageCount(id).then((count) {
        if (_pageCounts[id] != count) {
          _pageCounts[id] = count;
          notifyListeners();
        }
      }));
    }
  }

  // -------------------------------------------------------------- view state

  /// Tabs are pure quick-switch views: selecting one shows the whole tree
  /// from the root of the "all" section.
  Future<void> selectTab(int? id) async {
    selectedTabId = id;
    currentFolderId = null;
    section = LibrarySection.all;
    await reload();
  }

  Future<void> enterFolder(int? id) async {
    currentFolderId = id;
    if (section == LibrarySection.trash) section = LibrarySection.all;
    await reload();
  }

  Future<void> setSection(LibrarySection s) async {
    section = s;
    await reload();
  }

  void setQuery(String q) {
    query = q;
    _applyFilters();
  }

  void setSort(SortKey k, bool asc) {
    sortKey = k;
    sortAsc = asc;
    _applyFilters();
  }

  void setViewMode(ViewMode m) {
    viewMode = m;
    notifyListeners();
  }

  // --------------------------------------------------------------- notebooks

  Future<NotebookEntity> createNotebook({
    String title = '',
    String? coverId = 'c1',
    String? coverImagePath,
    int? folderId,
    int template = 0,
    int pageSize = 0,
    int paperColor = 0xFFFFFFFF,
  }) async {
    final n = await LibraryRepository.I.createNotebook(
      title: title,
      coverId: coverId,
      coverImagePath: coverImagePath,
      folderId: folderId,
      template: template,
      pageSize: pageSize,
      paperColor: paperColor,
    );
    await reload();
    return n;
  }

  Future<void> renameNotebook(NotebookEntity n, String title) async {
    n.title = title;
    n.modifiedAt = DateTime.now();
    await LibraryRepository.I.updateNotebook(n);
    await reload();
  }

  Future<void> toggleFavorite(NotebookEntity n) async {
    await LibraryRepository.I.setFavorite(n, !n.favorite);
    await reload();
  }

  Future<void> moveNotebook(NotebookEntity n, int? folderId) async {
    await LibraryRepository.I.moveToFolder(n, folderId);
    await reload();
  }

  Future<void> assignTag(NotebookEntity n, TagEntity t) async {
    if (!n.tagIds.contains(t.id)) {
      n.tagIds = List<int>.of(n.tagIds)..add(t.id);
      await LibraryRepository.I.updateNotebook(n);
    }
    await reload();
  }

  Future<void> unassignTag(NotebookEntity n, TagEntity t) async {
    if (n.tagIds.contains(t.id)) {
      n.tagIds = List<int>.of(n.tagIds)..remove(t.id);
      await LibraryRepository.I.updateNotebook(n);
    }
    await reload();
  }

  Future<void> trashNotebook(NotebookEntity n) async {
    await LibraryRepository.I.trashNotebook(n);
    await reload();
  }

  Future<void> restoreNotebook(NotebookEntity n) async {
    await LibraryRepository.I.restoreNotebook(n);
    await reload();
  }

  Future<void> purgeNotebook(NotebookEntity n) async {
    await LibraryRepository.I.purgeNotebook(n);
    await reload();
  }

  Future<void> emptyTrash() async {
    await LibraryRepository.I.emptyTrash();
    await reload();
  }

  /// Imports a PDF as a new notebook (one page per PDF page, the PDF as
  /// page background). Returns null when the file cannot be imported.
  Future<NotebookEntity?> importPdf(File pdfFile) async {
    String? relPath;
    try {
      relPath = await FileStore.importFile(pdfFile, 'pdfs');
      final abs = await FileStore.resolve(relPath);
      final doc = await PdfDocument.openFile(abs.path);
      final count = doc.pages.length;
      // Pick the page orientation from the first page when possible.
      var pageSize = PageSizeId.a4Portrait.index;
      try {
        final first = doc.pages.first;
        final w = first.width;
        final h = first.height;
        if (w > h) pageSize = PageSizeId.a4Landscape.index;
      } catch (_) {
        // Keep the portrait default.
      }
      doc.dispose();

      var title = p.basenameWithoutExtension(pdfFile.path);
      if (title.isEmpty) title = 'PDF';

      final n = await LibraryRepository.I.createNotebook(
        title: title,
        coverId: 'c1',
        folderId: currentFolderId,
        template: TemplateId.blank.index,
        pageSize: pageSize,
        paperColor: PAPER_COLORS.first.toARGB32(),
      );
      n.pdfPath = relPath;
      await LibraryRepository.I.updateNotebook(n);

      // createNotebook already made page 0 — add the remaining pages.
      try {
        for (var i = 1; i < count; i++) {
          await LibraryRepository.I.addPage(
              n.id, i, n.template, n.pageSize, n.paperColor);
        }
      } catch (_) {
        await LibraryRepository.I.purgeNotebook(n);
        rethrow;
      }
      await reload();
      return n;
    } catch (_) {
      if (relPath != null) {
        try {
          await FileStore.deleteRelative(relPath);
        } catch (_) {
          // Best effort cleanup.
        }
      }
      return null;
    }
  }

  // -------------------------------------------------------------------- tags

  Future<TagEntity> createTag(String name, int color) async {
    final t = await LibraryRepository.I.createTag(name, color);
    await reload();
    return t;
  }

  Future<void> deleteTag(TagEntity t) async {
    // Unassign from every notebook (active and trashed).
    final active = await LibraryRepository.I.activeNotebooks();
    final trashed = await LibraryRepository.I.trashedNotebooks();
    for (final n in [...active, ...trashed]) {
      if (n.tagIds.contains(t.id)) {
        n.tagIds = List<int>.of(n.tagIds)..remove(t.id);
        await LibraryRepository.I.updateNotebook(n);
      }
    }
    await LibraryRepository.I.deleteTag(t);
    await reload();
  }

  // ----------------------------------------------------------------- folders

  /// Creates a folder inside the currently browsed folder
  /// ([currentFolderId]; null = root).
  Future<FolderEntity> createFolder(String name, int color, String emoji) async {
    final f = await LibraryRepository.I.createFolder(
        name, color, emoji, currentFolderId);
    await reload();
    return f;
  }

  Future<void> renameFolder(FolderEntity f, String name) async {
    f.name = name;
    await LibraryRepository.I.updateFolder(f);
    await reload();
  }

  Future<void> deleteFolder(FolderEntity f) async {
    await LibraryRepository.I.deleteFolder(f);
    // Children are re-parented to f's parent — follow them.
    if (currentFolderId == f.id) currentFolderId = f.parentId;
    await reload();
  }

  // -------------------------------------------------------------------- tabs

  Future<TabEntity> createTab(String name, int color, String emoji) async {
    final t = await LibraryRepository.I.createTab(name, color, emoji);
    await reload();
    return t;
  }

  Future<void> renameTab(TabEntity t, String name) async {
    t.name = name;
    await LibraryRepository.I.updateTab(t);
    await reload();
  }

  Future<void> deleteTab(TabEntity t) async {
    if (selectedTabId == t.id) selectedTabId = null;
    await LibraryRepository.I.deleteTab(t);
    await reload();
  }

  // ------------------------------------------------------------------ helpers

  /// "Library / A / B" (localized root label).
  String folderPath(int? folderId) {
    return [S.t('rootFolder'), ..._ancestorNames(folderId)].join(' / ');
  }

  List<FolderEntity> childFolders(int? parentId) {
    // [folders] is already sorted by position.
    return folders.where((f) => f.parentId == parentId).toList();
  }

  List<TagEntity> tagsOf(NotebookEntity n) {
    return tags.where((t) => n.tagIds.contains(t.id)).toList();
  }

  int daysLeftInTrash(NotebookEntity n) {
    final deletedAt = n.deletedAt;
    if (deletedAt == null) return TRASH_RETENTION.inDays;
    final elapsed = DateTime.now().difference(deletedAt);
    var left = TRASH_RETENTION.inDays - elapsed.inDays;
    if (left < 0) left = 0;
    if (left > TRASH_RETENTION.inDays) left = TRASH_RETENTION.inDays;
    return left;
  }

  FolderEntity? _folderById(int id) {
    for (final f in folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Ancestor folder names, outermost first (cycle-safe).
  List<String> _ancestorNames(int? folderId) {
    final names = <String>[];
    final visited = <int>{};
    var id = folderId;
    while (id != null && visited.add(id)) {
      final f = _folderById(id);
      if (f == null) break;
      names.insert(0, f.name);
      id = f.parentId;
    }
    return names;
  }

  /// Folder names on the notebook's path joined by "/" (search haystack).
  String _pathNames(int? folderId) => _ancestorNames(folderId).join('/');
}
