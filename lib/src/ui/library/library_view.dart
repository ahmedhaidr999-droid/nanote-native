import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../controllers/library_controller.dart';
import '../../i18n/strings.dart';
import '../../models/library_models.dart';
import '../../persistence/library_repository.dart';
import '../../theme/nanote_theme.dart';
import 'library_dialogs.dart';
import 'notebook_card.dart';

/// The library home screen ('/'): brand top bar with expandable search,
/// bottom navigation (My Notebooks / Folders / Tags / Trash), folder
/// breadcrumbs + chips, notebook grid/list, sort, view toggle, PDF import
/// and the gradient "+" FAB.
class LibraryView extends StatefulWidget {
  const LibraryView({super.key});

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

/// Sections of the bottom navigation bar.
enum _LibTab { notebooks, folders, tags, trash }

class _LibraryViewState extends State<LibraryView> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  /// Active bottom-nav tab.
  _LibTab _tab = _LibTab.notebooks;

  /// Whether the top-bar search field is expanded.
  bool _searchOpen = false;

  /// All active (non-trashed) notebooks — powers the Folders tab list and
  /// the per-folder / per-tag notebook counts.
  List<NotebookEntity> _activeNotebooks = const [];
  Map<int, int> _folderCounts = const {};

  @override
  void initState() {
    super.initState();
    unawaited(LibraryController.I.reload());
    // Purge expired trash once at startup, then refresh.
    unawaited(LibraryRepository.I.purgeExpiredTrash()
        .then((_) => LibraryController.I.reload())
        .catchError((_) {}));
    LibraryController.I.addListener(_onLibraryChanged);
    unawaited(_refreshLibraryCache());
  }

  @override
  void dispose() {
    LibraryController.I.removeListener(_onLibraryChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onLibraryChanged() => unawaited(_refreshLibraryCache());

  Future<void> _refreshLibraryCache() async {
    final all = await LibraryRepository.I.activeNotebooks();
    if (!mounted) return;
    final counts = <int, int>{};
    for (final n in all) {
      final fid = n.folderId;
      if (fid != null) counts[fid] = (counts[fid] ?? 0) + 1;
    }
    setState(() {
      _activeNotebooks = all;
      _folderCounts = counts;
    });
  }

  // ----------------------------------------------------------------- actions

  Future<void> _openNotebook(int id) async {
    await Navigator.pushNamed(context, '/notebook', arguments: id);
    if (mounted) unawaited(LibraryController.I.reload());
  }

  Future<void> _createNotebook() async {
    final c = LibraryController.I;
    final nb = await showCreateNotebookSheet(
      context,
      folderId: c.currentFolderId,
    );
    if (nb == null || !mounted) return;
    // Make sure the fresh notebook is visible when we come back.
    if (c.section != LibrarySection.all) {
      await c.setSection(LibrarySection.all);
    }
    if (!mounted) return;
    await Navigator.pushNamed(context, '/notebook', arguments: nb.id);
    if (mounted) unawaited(c.reload());
  }

  Future<void> _importPdf() async {
    final c = LibraryController.I;
    final messenger = ScaffoldMessenger.of(context);
    // v1.0.0: file_picker 13 removed `FilePicker.platform` — pickFiles is
    // now static and returns a non-null list (empty when the user cancels).
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = files.isNotEmpty ? files.first.path : null;
    if (path == null || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(S.t('importingPdf'))));
    final nb = await c.importPdf(File(path));
    if (!mounted) return;
    if (nb != null) {
      if (c.section != LibrarySection.all) {
        await c.setSection(LibrarySection.all);
      }
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(S.t('pdfImported'))));
      // Open the imported PDF right away.
      await Navigator.pushNamed(context, '/notebook', arguments: nb.id);
      if (mounted) unawaited(c.reload());
    } else {
      messenger.showSnackBar(SnackBar(content: Text(S.t('error'))));
    }
  }

  Future<void> _createFolder() async {
    final c = LibraryController.I;
    final folder = await showCreateFolderDialog(
      context,
      parentId: c.currentFolderId,
    );
    if (folder == null || !mounted) return;
    await c.reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.t('folderCreated'))),
      );
    }
  }

  /// The + menu: new notebook, import PDF or new folder.
  Future<void> _showCreateMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (context) => SafeArea(
        child: NanoteSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sheetActionRow(
                context,
                icon: LucideIcons.book_plus,
                label: S.t('newNotebook'),
                onTap: () => Navigator.pop(context, 'notebook'),
              ),
              sheetActionRow(
                context,
                icon: LucideIcons.file_text,
                label: S.t('importPdf'),
                onTap: () => Navigator.pop(context, 'pdf'),
              ),
              sheetActionRow(
                context,
                icon: LucideIcons.folder_plus,
                label: S.t('newFolder'),
                onTap: () => Navigator.pop(context, 'folder'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'notebook':
        await _createNotebook();
      case 'pdf':
        await _importPdf();
      case 'folder':
        await _createFolder();
    }
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LibraryController.I,
      builder: (context, _) {
        final c = LibraryController.I;
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 56,
            automaticallyImplyLeading: false,
            title: _searchOpen
                ? _searchField(context, c)
                : _brandHeader(context),
            actions: _searchOpen
                ? [
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 20),
                      tooltip: S.t('close'),
                      onPressed: _closeSearch,
                    ),
                    const SizedBox(width: 4),
                  ]
                : [
                    IconButton(
                      icon: const Icon(LucideIcons.search, size: 20),
                      tooltip: S.t('search'),
                      onPressed: _openSearch,
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.settings, size: 20),
                      tooltip: S.t('settings'),
                      onPressed: () =>
                          Navigator.pushNamed(context, '/settings'),
                    ),
                    const SizedBox(width: 4),
                  ],
          ),
          body: switch (_tab) {
            _LibTab.notebooks => _notebooksTab(context, c),
            _LibTab.folders => _foldersTab(context, c),
            _LibTab.tags => _tagsTab(context, c),
            _LibTab.trash => _trashTab(context, c),
          },
          bottomNavigationBar: _bottomNav(context),
          // The + button opens the create menu: notebook / folder / PDF.
          floatingActionButton:
              _tab == _LibTab.trash ? null : _gradientFab(context),
        );
      },
    );
  }

  // ---------------------------------------------------------------- top bar

  /// Logo mark + wordmark, the START side of the top bar.
  Widget _brandHeader(BuildContext context) {
    final nc = nanoteColors(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: nc.brandGradient,
            ),
            borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
          ),
          child: const Icon(LucideIcons.pen_tool, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 10),
        const Text('Nanote'),
      ],
    );
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    _searchCtrl.clear();
    LibraryController.I.setQuery('');
    setState(() => _searchOpen = false);
  }

  /// Pill search field (surfaceVariant fill, no border) shown in the top bar
  /// while searching.
  Widget _searchField(BuildContext context, LibraryController c) {
    final nc = nanoteColors(context);
    final pillBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: BorderSide.none,
    );
    return SizedBox(
      height: 42,
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        onChanged: c.setQuery,
        decoration: InputDecoration(
          hintText: S.t('searchHint'),
          isDense: true,
          filled: true,
          fillColor: nc.surfaceVariant,
          prefixIcon: const Icon(LucideIcons.search, size: 20),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 44),
          suffixIcon: c.query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(LucideIcons.x, size: 20),
                  tooltip: S.t('clear'),
                  onPressed: () {
                    _searchCtrl.clear();
                    c.setQuery('');
                  },
                ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          border: pillBorder,
          enabledBorder: pillBorder,
          focusedBorder: pillBorder,
        ),
      ),
    );
  }

  // ------------------------------------------------------------ bottom nav

  Widget _bottomNav(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    final navTheme = Theme.of(context).navigationBarTheme.copyWith(
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? cs.primary
                  : nc.mutedFg,
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => nanoteText(
              TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: states.contains(WidgetState.selected)
                    ? cs.primary
                    : nc.mutedFg,
              ),
            ),
          ),
        );
    return Theme(
      data: Theme.of(context).copyWith(navigationBarTheme: navTheme),
      child: NavigationBar(
        height: 64,
        selectedIndex: _tab.index,
        onDestinationSelected: _onNavTap,
        destinations: [
          NavigationDestination(
            icon: const Icon(LucideIcons.book, size: 24),
            label: S.t('myNotebooks'),
          ),
          NavigationDestination(
            icon: const Icon(LucideIcons.folder, size: 24),
            label: S.t('folders'),
          ),
          NavigationDestination(
            icon: const Icon(LucideIcons.tag, size: 24),
            label: S.t('tags'),
          ),
          NavigationDestination(
            icon: const Icon(LucideIcons.trash, size: 24),
            label: S.t('trash'),
          ),
        ],
      ),
    );
  }

  void _onNavTap(int index) {
    final c = LibraryController.I;
    final tab = _LibTab.values[index];
    if (tab == _LibTab.trash) {
      if (c.section != LibrarySection.trash) {
        unawaited(c.setSection(LibrarySection.trash));
      }
    } else if (c.section == LibrarySection.trash) {
      unawaited(c.setSection(LibrarySection.all));
    }
    setState(() => _tab = tab);
  }

  // ------------------------------------------------------------------- FAB

  /// Gradient rounded-square "+" — the app's hero element.
  Widget _gradientFab(BuildContext context) {
    final nc = nanoteColors(context);
    return Tooltip(
      message: S.t('create'),
      child: Pressable(
        onTap: () => unawaited(_showCreateMenu()),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: nc.brandGradient,
            ),
            borderRadius: BorderRadius.circular(NANOTE_RADIUS_LG),
            boxShadow: nc.inkShadow2,
          ),
          child: const Icon(LucideIcons.plus, size: 24, color: Colors.white),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- notebooks tab

  Widget _notebooksTab(BuildContext context, LibraryController c) {
    return Column(
      children: [
        _sectionRow(context, c),
        _folderBar(context, c),
        Expanded(child: _body(context, c)),
      ],
    );
  }

  /// All / Favorites sections, the user's quick tabs and "new tab".
  Widget _sectionRow(BuildContext context, LibraryController c) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          _sectionChip(
            context,
            icon: LucideIcons.notebook,
            label: S.t('all'),
            selected:
                c.selectedTabId == null && c.section == LibrarySection.all,
            onTap: () => unawaited(c.selectTab(null)),
          ),
          const SizedBox(width: 8),
          _sectionChip(
            context,
            icon: LucideIcons.star,
            label: S.t('favorites'),
            selected: c.section == LibrarySection.favorites,
            onTap: () =>
                unawaited(c.setSection(LibrarySection.favorites)),
          ),
          for (final t in c.tabs) ...[
            const SizedBox(width: 8),
            _userTabChip(context, c, t),
          ],
          const SizedBox(width: 8),
          _newTabChip(context),
        ],
      ),
    );
  }

  Widget _sectionChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? nc.accent : nc.surfaceVariant,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16, color: selected ? cs.primary : nc.mutedFg),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? cs.primary : nc.mutedFg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _userTabChip(BuildContext context, LibraryController c, TabEntity t) {
    final selected =
        c.selectedTabId == t.id && c.section == LibrarySection.all;
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return Pressable(
      onTap: () => unawaited(c.selectTab(t.id)),
      onLongPress: () => _showTabMenu(context, t),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? nc.accent : nc.surfaceVariant,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              t.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? cs.primary : nc.mutedFg,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Color(t.color),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _newTabChip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return Pressable(
      onTap: () => _showCreateTabDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: nc.surfaceVariant,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.plus, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              S.t('newTab'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- folders

  /// Breadcrumbs + child folder chips + "new folder", with the sort and
  /// view-toggle controls at the end.
  Widget _folderBar(BuildContext context, LibraryController c) {
    final children = c.childFolders(c.currentFolderId);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (c.currentFolderId != null) ..._breadcrumbChips(context, c),
                  for (final f in children) _folderChip(context, c, f),
                  _newFolderChip(context, c),
                ],
              ),
            ),
          ),
          _sortButton(context, c),
          _viewToggle(c),
        ],
      ),
    );
  }

  List<Widget> _breadcrumbChips(BuildContext context, LibraryController c) {
    final chain = <FolderEntity>[];
    final visited = <int>{};
    var id = c.currentFolderId;
    while (id != null && visited.add(id)) {
      FolderEntity? f;
      for (final x in c.folders) {
        if (x.id == id) {
          f = x;
          break;
        }
      }
      if (f == null) break;
      chain.insert(0, f);
      id = f.parentId;
    }
    return [
      _folderPill(
        context,
        icon: LucideIcons.house,
        label: S.t('rootFolder'),
        highlighted: false,
        onTap: () => c.enterFolder(null),
      ),
      for (final f in chain)
        _folderPill(
          context,
          emoji: f.emoji,
          label: f.name,
          highlighted: f.id == c.currentFolderId,
          onTap: f.id == c.currentFolderId
              ? null
              : () => c.enterFolder(f.id),
        ),
    ];
  }

  Widget _folderPill(
    BuildContext context, {
    String? emoji,
    IconData? icon,
    required String label,
    required bool highlighted,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    final fg = highlighted ? cs.primary : nc.secondaryFg;
    return Pressable(
      onTap: onTap,
      enabled: onTap != null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: highlighted ? nc.accent : nc.surfaceVariant,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null) ...[
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
            ],
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _folderChip(
      BuildContext context, LibraryController c, FolderEntity f) {
    final nc = nanoteColors(context);
    return Pressable(
      onTap: () => c.enterFolder(f.id),
      onLongPress: () => _showFolderMenu(context, f),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: nc.surfaceVariant,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(f.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                f.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: nc.secondaryFg,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Directionality.of(context) == TextDirection.rtl
                  ? LucideIcons.chevron_left
                  : LucideIcons.chevron_right,
              size: 14,
              color: nc.mutedFg,
            ),
          ],
        ),
      ),
    );
  }

  Widget _newFolderChip(BuildContext context, LibraryController c) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: () => showCreateFolderDialog(
        context,
        parentId: c.currentFolderId,
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.folder_plus, size: 14, color: cs.primary),
            const SizedBox(width: 4),
            Text(
              S.t('newFolder'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ sort / view

  Widget _sortButton(BuildContext context, LibraryController c) {
    Widget check(bool on) => SizedBox(
          width: 22,
          child: on
              ? const Icon(LucideIcons.check, size: 16)
              : null,
        );
    return PopupMenuButton<String>(
      icon: Icon(
        c.sortAsc
            ? LucideIcons.arrow_up_narrow_wide
            : LucideIcons.arrow_down_wide_narrow,
        size: 20,
      ),
      tooltip: S.t('sortBy'),
      onSelected: (v) {
        if (v == 'asc') {
          c.setSort(c.sortKey, true);
        } else if (v == 'desc') {
          c.setSort(c.sortKey, false);
        } else {
          for (final k in SortKey.values) {
            if (k.key == v) c.setSort(k, c.sortAsc);
          }
        }
      },
      itemBuilder: (context) => [
        for (final k in SortKey.values)
          PopupMenuItem(
            value: k.key,
            child: Row(
              children: [
                check(c.sortKey == k),
                Text(S.t(k.key)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'asc',
          child: Row(
            children: [
              check(c.sortAsc),
              Text(S.t('ascending')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'desc',
          child: Row(
            children: [
              check(!c.sortAsc),
              Text(S.t('descending')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _viewToggle(LibraryController c) {
    return IconButton(
      onPressed: () => c.setViewMode(
        c.viewMode == ViewMode.grid ? ViewMode.list : ViewMode.grid,
      ),
      icon: Icon(
        c.viewMode == ViewMode.grid
            ? LucideIcons.layout_list
            : LucideIcons.layout_grid,
        size: 20,
      ),
      tooltip: S.t(c.viewMode == ViewMode.grid ? 'listView' : 'gridView'),
    );
  }

  /// The notebooks toolbar (sort + view toggle), end-aligned. Used by tabs
  /// that show the notebook list but have no folder bar.
  Widget _listToolbar(BuildContext context, LibraryController c) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 4),
      child: Row(
        children: [
          const Spacer(),
          _sortButton(context, c),
          _viewToggle(c),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ trash

  Widget _trashTab(BuildContext context, LibraryController c) {
    return Column(
      children: [
        _trashBanner(context, c),
        _listToolbar(context, c),
        Expanded(child: _body(context, c)),
      ],
    );
  }

  Widget _trashBanner(BuildContext context, LibraryController c) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: nc.warning.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(NANOTE_RADIUS),
          border: Border.all(color: nc.warning.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.trash, size: 16, color: nc.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    S.t('emptyTrashHint'),
                    style: TextStyle(fontSize: 12, color: nc.mutedFg),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                ),
                onPressed: () async {
                  final ok = await showConfirmDialog(
                    context,
                    title: S.t('emptyTrashNow'),
                    message: S.t('confirmEmptyTrash'),
                  );
                  if (ok) await c.emptyTrash();
                },
                icon: const Icon(LucideIcons.flame, size: 20),
                label: Text(S.t('emptyTrashNow')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------- folders tab

  Widget _foldersTab(BuildContext context, LibraryController c) {
    final children = c.childFolders(c.currentFolderId);
    final notebooksHere = [
      for (final n in _activeNotebooks)
        if (n.folderId == c.currentFolderId) n,
    ];
    final nc = nanoteColors(context);
    return CustomScrollView(
      slivers: [
        if (c.currentFolderId != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _breadcrumbChips(context, c),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              childAspectRatio: 1.35,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => i < children.length
                  ? _folderCard(context, c, children[i])
                  : _newFolderCard(context, c),
              childCount: children.length + 1,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 20, 16, 4),
            child: Text(
              S.t('notebooks'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: nc.mutedFg,
              ),
            ),
          ),
        ),
        if (notebooksHere.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
              child: Text(
                S.t('emptyLibraryHint'),
                style: TextStyle(fontSize: 13, color: nc.mutedFg),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: NotebookCard(
                    notebook: notebooksHere[i],
                    pageCount: c.pageCountOf(notebooksHere[i].id) ?? 0,
                    tags: c.tagsOf(notebooksHere[i]),
                    onOpen: () => _openNotebook(notebooksHere[i].id),
                    onFavorite: () =>
                        c.toggleFavorite(notebooksHere[i]),
                    onMenu: (nb) => showNotebookMenuSheet(context, nb),
                    listMode: true,
                  ),
                ),
                childCount: notebooksHere.length,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 108)),
      ],
    );
  }

  Widget _folderCard(
      BuildContext context, LibraryController c, FolderEntity f) {
    final nc = nanoteColors(context);
    final color = Color(f.color);
    final count = _folderCounts[f.id] ?? 0;
    return Pressable(
      onTap: () => unawaited(c.enterFolder(f.id)),
      onLongPress: () => _showFolderMenu(context, f),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(NANOTE_RADIUS),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(f.emoji, style: const TextStyle(fontSize: 20)),
                const Spacer(),
                Icon(LucideIcons.folder, size: 16, color: color),
              ],
            ),
            const Spacer(),
            Text(
              f.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.book, size: 14, color: nc.mutedFg),
                const SizedBox(width: 4),
                Text(
                  S.num(count),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: nc.mutedFg,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _newFolderCard(BuildContext context, LibraryController c) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: () => showCreateFolderDialog(
        context,
        parentId: c.currentFolderId,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NANOTE_RADIUS),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.45),
            width: 1.2,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.folder_plus, size: 24, color: cs.primary),
              const SizedBox(height: 6),
              Text(
                S.t('newFolder'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- tags tab

  Widget _tagsTab(BuildContext context, LibraryController c) {
    final nc = nanoteColors(context);
    if (c.tags.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: nc.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.tag, size: 24, color: nc.mutedFg),
              ),
              const SizedBox(height: 14),
              Text(
                S.t('untagged'),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => showCreateTagSheet(context),
                icon: const Icon(LucideIcons.plus, size: 20),
                label: Text(S.t('newTag')),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 108),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in c.tags) _tagChip(context, c, t),
            _newTagChip(context),
          ],
        ),
      ],
    );
  }

  Widget _tagChip(BuildContext context, LibraryController c, TagEntity t) {
    final nc = nanoteColors(context);
    final color = Color(t.color);
    var count = 0;
    for (final n in _activeNotebooks) {
      if (n.tagIds.contains(t.id)) count++;
    }
    return Pressable(
      onTap: () => _filterByTag(t.name),
      onLongPress: () => _confirmDeleteTag(context, c, t),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: nc.surfaceVariant,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                S.num(count),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: nc.mutedFg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _newTagChip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Pressable(
      onTap: () => showCreateTagSheet(context),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.primary.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.plus, size: 14, color: cs.primary),
            const SizedBox(width: 4),
            Text(
              S.t('newTag'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Filter the notebooks list by tag name through the existing search.
  void _filterByTag(String name) {
    final c = LibraryController.I;
    _searchCtrl.text = name;
    c.setQuery(name);
    setState(() {
      _searchOpen = true;
      _tab = _LibTab.notebooks;
    });
  }

  Future<void> _confirmDeleteTag(
      BuildContext context, LibraryController c, TagEntity t) async {
    final ok = await showConfirmDialog(
      context,
      title: S.t('delete'),
      message: t.name,
    );
    if (ok) await c.deleteTag(t);
  }

  // ------------------------------------------------------------------- body

  Widget _body(BuildContext context, LibraryController c) {
    if (c.notebooks.isEmpty) return _emptyState(context, c);
    if (c.viewMode == ViewMode.grid) {
      return LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 16.0;
          final avail = math.max(0.0, constraints.maxWidth - 32);
          final cross = math.max(1, (avail / 160).ceil());
          final cellW = (avail - spacing * (cross - 1)) / cross;
          // 3:4 cover + ~54px of labels underneath.
          final cellH = cellW * 4 / 3 + 54;
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 108),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cross,
              childAspectRatio: cellW / cellH,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
            ),
            itemCount: c.notebooks.length,
            itemBuilder: (context, i) =>
                _notebookCard(context, c, c.notebooks[i]),
          );
        },
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 108),
      itemCount: c.notebooks.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: NotebookCard(
          notebook: c.notebooks[i],
          pageCount: c.pageCountOf(c.notebooks[i].id) ?? 0,
          tags: c.tagsOf(c.notebooks[i]),
          onOpen: () => _openNotebook(c.notebooks[i].id),
          onFavorite: () => c.toggleFavorite(c.notebooks[i]),
          onMenu: (nb) => showNotebookMenuSheet(context, nb),
          listMode: true,
        ),
      ),
    );
  }

  Widget _notebookCard(
      BuildContext context, LibraryController c, NotebookEntity n) {
    return NotebookCard(
      notebook: n,
      pageCount: c.pageCountOf(n.id) ?? 0,
      tags: c.tagsOf(n),
      onOpen: () => _openNotebook(n.id),
      onFavorite: () => c.toggleFavorite(n),
      onMenu: (nb) => showNotebookMenuSheet(context, nb),
    );
  }

  Widget _emptyState(BuildContext context, LibraryController c) {
    final nc = nanoteColors(context);
    final String title;
    final String? hint;
    final IconData icon;
    if (c.section == LibrarySection.trash) {
      title = S.t('emptyTrash');
      hint = S.t('emptyTrashHint');
      icon = LucideIcons.trash;
    } else if (c.query.trim().isNotEmpty) {
      title = S.t('noResults');
      hint = null;
      icon = LucideIcons.search;
    } else {
      title = S.t('emptyLibrary');
      hint = S.t('emptyLibraryHint');
      icon = LucideIcons.book_open;
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: nc.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: nc.mutedFg),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (hint != null) ...[
              const SizedBox(height: 6),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: nc.mutedFg),
              ),
            ],
            if (c.section != LibrarySection.trash &&
                c.query.trim().isEmpty) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _createNotebook,
                icon: const Icon(LucideIcons.plus, size: 20),
                label: Text(S.t('newNotebook')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- tab menus

  Future<void> _showCreateTabDialog(BuildContext context) async {
    final c = LibraryController.I;
    final nameCtrl = TextEditingController();
    var emoji = '📓';
    var color = kPickerColors.first;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(S.t('newTab')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: InputDecoration(hintText: S.t('nameHint')),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in kEmojiChoices)
                      InkWell(
                        onTap: () => setD(() => emoji = e),
                        borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(NANOTE_RADIUS_SM),
                            border: Border.all(
                              color: emoji == e
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                              width: emoji == e ? 2 : 1,
                            ),
                          ),
                          child:
                              Text(e, style: const TextStyle(fontSize: 20)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final col in kPickerColors)
                      ColorDot(
                        color: col,
                        selected: col == color,
                        onTap: () => setD(() => color = col),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(S.t('cancel')),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                await c.createTab(name, color.toARGB32(), emoji);
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(S.t('create')),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
  }

  Future<void> _showTabMenu(BuildContext context, TabEntity t) async {
    final c = LibraryController.I;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (context) => SafeArea(
        child: NanoteSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 8),
                child: Row(
                  children: [
                    Text(t.emoji, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
              sheetActionRow(
                context,
                icon: LucideIcons.pencil,
                label: S.t('rename'),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
              sheetActionRow(
                context,
                icon: LucideIcons.trash,
                label: S.t('deleteTab'),
                destructive: true,
                onTap: () => Navigator.pop(context, 'delete'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'rename') {
      await showRenameDialog(
          context, t.name, 'renameTab', (s) => c.renameTab(t, s));
    } else if (action == 'delete') {
      final ok = await showConfirmDialog(
        context,
        title: S.t('deleteTab'),
        message: t.name,
      );
      if (ok) await c.deleteTab(t);
    }
  }

  Future<void> _showFolderMenu(BuildContext context, FolderEntity f) async {
    final c = LibraryController.I;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (context) => SafeArea(
        child: NanoteSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 8),
                child: Row(
                  children: [
                    Text(f.emoji, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
              sheetActionRow(
                context,
                icon: LucideIcons.pencil,
                label: S.t('rename'),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
              sheetActionRow(
                context,
                icon: LucideIcons.trash,
                label: S.t('deleteFolder'),
                destructive: true,
                onTap: () => Navigator.pop(context, 'delete'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'rename') {
      await showRenameDialog(
          context, f.name, 'renameFolder', (s) => c.renameFolder(f, s));
    } else if (action == 'delete') {
      final ok = await showConfirmDialog(
        context,
        title: S.t('deleteFolder'),
        message: S.t('confirmDeleteFolder'),
      );
      if (ok) await c.deleteFolder(f);
    }
  }
}
