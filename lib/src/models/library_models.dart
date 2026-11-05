/// Library-level enums and small models (UI state lives in
/// [../controllers/library_controller.dart]).

enum LibrarySection { all, favorites, trash }

enum SortKey { opened, modified, created, title }

extension SortKeyX on SortKey {
  String get key => 'sort.${name}';
}

enum ViewMode { grid, list }

/// 30-day trash retention.
const Duration TRASH_RETENTION = Duration(days: 30);
