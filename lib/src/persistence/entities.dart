/// Plain library entities — the exact same shape the old Isar entities had
/// (fields, constructors, defaults), so every controller/UI module keeps
/// working unchanged. Persistence is Drift (SQLite); repositories map rows
/// ⇄ entities.
///
/// CRITICAL: `PageEntity.id` IS the ink slot. Strokes and elements reference
/// pages by this stable id — never by visual index (pages can be reordered or
/// deleted; index-keyed ink corrupts).

class TabEntity {
  int id = 0; // assigned by the DB on insert (autoincrement, ≥1)

  String name = '';

  int color = 0xFF1E6FF2;

  String emoji = '📓';

  int position = 0;

  TabEntity();

  TabEntity.of(this.name, this.color, this.emoji, this.position);
}

class FolderEntity {
  int id = 0;

  String name = '';

  int color = 0xFF5A6B85;

  String emoji = '📁';

  int? parentId;

  int position = 0;

  FolderEntity();

  FolderEntity.of(this.name, this.color, this.emoji, this.parentId, this.position);
}

class NotebookEntity {
  int id = 0;

  String title = '';

  /// Built-in cover id (c1..c12) or null when a custom image is used.
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

class PageEntity {
  int id = 0;

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

class TagEntity {
  int id = 0;

  String name = '';

  int color = 0xFF9333EA;

  TagEntity();

  TagEntity.of(this.name, this.color);
}

class RecordingEntity {
  int id = 0;

  int notebookId = 0;

  int pageId = 0;

  /// Relative path under the recordings dir.
  String path = '';

  int durationMs = 0;

  DateTime createdAt = DateTime.now();

  RecordingEntity();

  RecordingEntity.of(this.notebookId, this.pageId, this.path, this.durationMs);
}

/// One committed ink stroke, stored as JSON for full fidelity
/// (style + points + audio sync + group).
class StrokeEntity {
  int id = 0;

  /// The STABLE ink slot: PageEntity.id (never the visual index).
  int pageId = 0;

  /// Global z-order within the page (shared with elements).
  int z = 0;

  String data = '';

  StrokeEntity();

  StrokeEntity.of(this.pageId, this.z, this.data);
}

/// One page element (text / shape / image / sticker), stored as JSON.
class ElementEntity {
  int id = 0;

  int pageId = 0;

  int z = 0;

  String data = '';

  ElementEntity();

  ElementEntity.of(this.pageId, this.z, this.data);
}
