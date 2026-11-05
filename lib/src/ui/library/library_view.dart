import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../controllers/library_controller.dart';
import '../../i18n/strings.dart';
import '../../models/library_models.dart';
import '../../persistence/library_repository.dart';
import '../../theme/nanote_theme.dart';
import 'library_dialogs.dart';
import 'notebook_card.dart';

/// Responsive breakpoints.
const double _kSm = 600.0;
const double _kMd = 900.0;
const double _kLg = 1200.0;

/// The library home screen ('/'): edge tab rail (or chip row on phones),
/// folder breadcrumbs + chips, notebook grid/list, search, sort, view toggle,
/// PDF import, trash section and the "new notebook" FAB.
class LibraryView extends StatefulWidget {
  const LibraryView({super.key});

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(LibraryController.I.reload());
    // Purge expired trash once at startup, then refresh.
    unawaited(LibraryRepository.I.purgeExpiredTrash()
        .then((_) => LibraryController.I.reload())
        .catchError((_) {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
    await Navigator.pushNamed(context, '/notebook', arguments: nb.id);
    if (mounted) unawaited(c.reload());
  }

  Future<void> _importPdf() async {
    final c = LibraryController.I;
    final messenger = ScaffoldMessenger.of(context);
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final files = res?.files;
    final path = (files != null && files.isNotEmpty) ? files.first.path : null;
    if (path == null || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(S.t('importingPdf'))));
    final nb = await c.importPdf(File(path));
    if (!mounted) return;
    if (nb != null) {
      if (c.section != LibrarySection.all) {
        await c.setSection(LibrarySection.all);
      }
      messenger.showSnackBar(SnackBar(content: Text(S.t('pdfImported'))));
    } else {
      messenger.showSnackBar(SnackBar(content: Text(S.t('error'))));
    }
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LibraryController.I,
      builder: (context, _) {
        final c = LibraryController.I;
        final wide = MediaQuery.of(context).size.width >= _kMd;
        final content = Column(
          children: [
            if (!wide) _tabsRow(context, c),
            if (c.section != LibrarySection.trash)
              _folderBar(context, c)
            else
              _trashBanner(context, c),
            Expanded(child: _body(context, c)),
          ],
        );
        return Scaffold(
          appBar: AppBar(
            title: _searchField(context, c),
            actions: [
              _sortButton(context, c),
              _viewToggle(c),
              IconButton(
                onPressed: _importPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: S.t('importPdf'),
              ),
              IconButton(
                onPressed: () => Navigator.pushNamed(context, '/settings'),
                icon: const Icon(Icons.settings_outlined),
                tooltip: S.t('settings'),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: wide
              ? Row(
                  children: [
                    _tabRail(context, c),
                    VerticalDivider(
                        width: 1,
                        color: Theme.of(context).colorScheme.outline),
                    Expanded(child: content),
                  ],
                )
              : content,
          floatingActionButton: c.section == LibrarySection.trash
              ? null
              : FloatingActionButton.extended(
                  onPressed: _createNotebook,
                  icon: const Icon(Icons.add),
                  label: Text(S.t('newNotebook')),
                ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- top bar

  Widget _searchField(BuildContext context, LibraryController c) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: _searchCtrl,
        onChanged: c.setQuery,
        decoration: InputDecoration(
          hintText: S.t('searchHint'),
          isDense: true,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: c.query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: S.t('clear'),
                  onPressed: () {
                    _searchCtrl.clear();
                    c.setQuery('');
                  },
                ),
        ),
      ),
    );
  }

  Widget _sortButton(BuildContext context, LibraryController c) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.sort),
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
                SizedBox(
                  width: 22,
                  child: c.sortKey == k
                      ? const Icon(Icons.check, size: 18)
                      : null,
                ),
                Text(S.t(k.key)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'asc',
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child:
                    c.sortAsc ? const Icon(Icons.check, size: 18) : null,
              ),
              Text(S.t('ascending')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'desc',
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child:
                    !c.sortAsc ? const Icon(Icons.check, size: 18) : null,
              ),
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
        c.viewMode == ViewMode.grid ? Icons.view_list : Icons.grid_view,
      ),
      tooltip: S.t(c.viewMode == ViewMode.grid ? 'listView' : 'gridView'),
    );
  }

  // ------------------------------------------------------------------- tabs

  Widget _tabRail(BuildContext context, LibraryController c) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            const SizedBox(height: 8),
            _railSectionButton(
              context,
              icon: Icons.apps,
              label: S.t('all'),
              selected:
                  c.selectedTabId == null && c.section == LibrarySection.all,
              onTap: () => c.selectTab(null),
            ),
            _railSectionButton(
              context,
              icon: c.section == LibrarySection.favorites
                  ? Icons.star
                  : Icons.star_border,
              label: S.t('favorites'),
              selected: c.section == LibrarySection.favorites,
              onTap: () => c.setSection(LibrarySection.favorites),
            ),
            _railSectionButton(
              context,
              icon: Icons.delete_outline,
              label: S.t('trash'),
              selected: c.section == LibrarySection.trash,
              onTap: () => c.setSection(LibrarySection.trash),
            ),
            const Divider(height: 16),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  for (final t in c.tabs) _railTab(context, c, t),
                  IconButton(
                    onPressed: () => _showCreateTabDialog(context),
                    icon: const Icon(Icons.add),
                    tooltip: S.t('newTab'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _railSectionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? cs.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 22,
                    color: selected ? cs.onPrimary : cs.onSurface),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? cs.onPrimary : nc.mutedFg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _railTab(BuildContext context, LibraryController c, TabEntity t) {
    final selected =
        c.selectedTabId == t.id && c.section == LibrarySection.all;
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? cs.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => c.selectTab(t.id),
          onLongPress: () => _showTabMenu(context, t),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(t.emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(height: 2),
                Text(
                  t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? cs.onPrimary : nc.mutedFg,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 18,
                  height: 3,
                  decoration: BoxDecoration(
                    color: Color(t.color),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabsRow(BuildContext context, LibraryController c) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _tabChip(
            context,
            icon: Icons.apps,
            label: S.t('all'),
            selected:
                c.selectedTabId == null && c.section == LibrarySection.all,
            onTap: () => c.selectTab(null),
          ),
          const SizedBox(width: 6),
          _tabChip(
            context,
            icon: c.section == LibrarySection.favorites
                ? Icons.star
                : Icons.star_border,
            label: S.t('favorites'),
            selected: c.section == LibrarySection.favorites,
            onTap: () => c.setSection(LibrarySection.favorites),
          ),
          const SizedBox(width: 6),
          _tabChip(
            context,
            icon: Icons.delete_outline,
            label: S.t('trash'),
            selected: c.section == LibrarySection.trash,
            onTap: () => c.setSection(LibrarySection.trash),
          ),
          if (c.tabs.isNotEmpty) ...[
            const SizedBox(width: 6),
            Center(
              child: Container(
                width: 1,
                height: 28,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
          for (final t in c.tabs) ...[
            const SizedBox(width: 6),
            _userTabChip(context, c, t),
          ],
          const SizedBox(width: 6),
          _tabChip(
            context,
            icon: Icons.add,
            label: S.t('newTab'),
            selected: false,
            onTap: () => _showCreateTabDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _tabChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return Material(
      color: selected ? cs.primary : cs.secondary,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 16, color: selected ? cs.onPrimary : nc.secondaryFg),
              const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? cs.onPrimary : nc.secondaryFg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _userTabChip(BuildContext context, LibraryController c, TabEntity t) {
    final selected =
        c.selectedTabId == t.id && c.section == LibrarySection.all;
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return Material(
      color: selected ? cs.primary : cs.secondary,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: () => c.selectTab(t.id),
        onLongPress: () => _showTabMenu(context, t),
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(t.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                t.name,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? cs.onPrimary : nc.secondaryFg,
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
      ),
    );
  }

  // ---------------------------------------------------------------- folders

  Widget _folderBar(BuildContext context, LibraryController c) {
    final children = c.childFolders(c.currentFolderId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (c.currentFolderId != null) ..._breadcrumbChips(context, c),
          for (final f in children) _folderChip(context, c, f),
          _newFolderChip(context, c),
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
        emoji: '🏠',
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
    required String emoji,
    required String label,
    required bool highlighted,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: highlighted ? cs.primary : cs.secondary,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: highlighted ? cs.primary : cs.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: highlighted ? cs.onPrimary : nc.secondaryFg,
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
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return InkWell(
      onTap: () => c.enterFolder(f.id),
      onLongPress: () => _showFolderMenu(context, f),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.secondary,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outline),
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
            Icon(Icons.chevron_right, size: 14, color: nc.mutedFg),
          ],
        ),
      ),
    );
  }

  Widget _newFolderChip(BuildContext context, LibraryController c) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () =>
          showCreateFolderDialog(context, parentId: c.currentFolderId),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.create_new_folder_outlined,
                size: 14, color: cs.primary),
            const SizedBox(width: 4),
            Text(
              S.t('newFolder'),
              maxLines: 1,
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

  // ------------------------------------------------------------------ trash

  Widget _trashBanner(BuildContext context, LibraryController c) {
    final nc = nanoteColors(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
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
                Icon(Icons.delete_sweep_outlined,
                    size: 18, color: nc.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    S.t('emptyTrashHint'),
                    style: TextStyle(fontSize: 12, color: nc.mutedFg),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(S.t('emptyTrashNow')),
                      content: Text(S.t('confirmEmptyTrash')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(S.t('cancel')),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(S.t('delete')),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) await c.emptyTrash();
                },
                child: Text(S.t('emptyTrashNow')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- body

  Widget _body(BuildContext context, LibraryController c) {
    if (c.notebooks.isEmpty) return _emptyState(context, c);
    final width = MediaQuery.of(context).size.width;
    if (c.viewMode == ViewMode.grid) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: width >= _kLg ? 300 : (width >= _kSm ? 260 : 220),
          childAspectRatio: 0.56,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: c.notebooks.length,
        itemBuilder: (context, i) => _notebookCard(context, c, c.notebooks[i]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
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
      icon = Icons.delete_outline;
    } else if (c.query.trim().isNotEmpty) {
      title = S.t('noResults');
      hint = null;
      icon = Icons.search;
    } else {
      title = S.t('emptyLibrary');
      hint = S.t('emptyLibraryHint');
      icon = Icons.auto_stories_outlined;
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: nc.mutedFg),
            const SizedBox(height: 12),
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
                icon: const Icon(Icons.add),
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
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
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
      builder: (context) {
        final destructive = Theme.of(context).colorScheme.error;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
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
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(S.t('rename')),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: destructive),
                title: Text(
                  S.t('deleteTab'),
                  style: TextStyle(color: destructive),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null || !context.mounted) return;
    if (action == 'rename') {
      await showRenameDialog(
          context, t.name, 'renameTab', (s) => c.renameTab(t, s));
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(S.t('deleteTab')),
          content: Text(t.name),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(S.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(S.t('delete')),
            ),
          ],
        ),
      );
      if (ok == true) await c.deleteTab(t);
    }
  }

  Future<void> _showFolderMenu(BuildContext context, FolderEntity f) async {
    final c = LibraryController.I;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final destructive = Theme.of(context).colorScheme.error;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
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
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(S.t('rename')),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: destructive),
                title: Text(
                  S.t('deleteFolder'),
                  style: TextStyle(color: destructive),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null || !context.mounted) return;
    if (action == 'rename') {
      await showRenameDialog(
          context, f.name, 'renameFolder', (s) => c.renameFolder(f, s));
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(S.t('deleteFolder')),
          content: Text(S.t('confirmDeleteFolder')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(S.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(S.t('delete')),
            ),
          ],
        ),
      );
      if (ok == true) await c.deleteFolder(f);
    }
  }
}
