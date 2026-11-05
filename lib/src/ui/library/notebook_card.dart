import 'dart:io';

import 'package:flutter/material.dart';

import '../../controllers/library_controller.dart';
import '../../i18n/strings.dart';
import '../../models/paper.dart';
import '../../persistence/file_store.dart';
import '../../persistence/library_repository.dart';
import '../../theme/nanote_theme.dart';

/// Resolved cover-image file cache (avoids re-hitting the disk on rebuilds).
final Map<String, Future<File?>> _coverFileCache = {};

/// A notebook in the library: grid variant (cover ~3:4, title, page count,
/// favorite star, tag dots) or a list row ([listMode]).
///
/// Long-press or the overflow button invokes [onMenu] — the parent shows the
/// action sheet (rename / move / tags / favorite / delete-or-restore).
class NotebookCard extends StatelessWidget {
  const NotebookCard({
    super.key,
    required this.notebook,
    required this.onOpen,
    required this.pageCount,
    required this.tags,
    required this.onFavorite,
    required this.onMenu,
    this.listMode = false,
  });

  final NotebookEntity notebook;
  final VoidCallback onOpen;
  final int pageCount;
  final List<TagEntity> tags;
  final VoidCallback onFavorite;

  /// Long-press / overflow menu — the parent shows the modal sheet.
  final void Function(NotebookEntity notebook) onMenu;

  /// Renders a ListTile-style row instead of the grid card.
  final bool listMode;

  @override
  Widget build(BuildContext context) {
    return listMode ? _buildList(context) : _buildGrid(context);
  }

  // ------------------------------------------------------------------- grid

  Widget _buildGrid(BuildContext context) {
    final nc = nanoteColors(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        onLongPress: () => onMenu(notebook),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCover(),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.35),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onMenu(notebook),
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child:
                              Icon(Icons.more_vert, size: 20, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  Positioned(bottom: 6, left: 6, child: _coverBadge()),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsetsDirectional.only(start: 10, end: 2, top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notebook.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${S.num(pageCount)} ${S.t('pagesCount')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: nc.mutedFg),
                        ),
                      ),
                      _favoriteButton(context),
                    ],
                  ),
                  _tagDots(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- list

  Widget _buildList(BuildContext context) {
    final nc = nanoteColors(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onOpen,
        onLongPress: () => onMenu(notebook),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(width: 44, height: 58, child: _buildCover()),
        ),
        title: Text(
          notebook.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _subtitleText(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: nc.mutedFg),
            ),
            _tagDots(),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _favoriteButton(context),
            IconButton(
              onPressed: () => onMenu(notebook),
              icon: const Icon(Icons.more_vert, size: 20),
              tooltip: S.t('edit'),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitleText() {
    final base = '${S.num(pageCount)} ${S.t('pagesCount')}';
    if (notebook.deleted) {
      final days = LibraryController.I.daysLeftInTrash(notebook);
      return '$base · ${S.num(days)} ${S.t('daysLeft')}';
    }
    return base;
  }

  // ----------------------------------------------------------------- pieces

  Widget _buildCover() {
    final rel = notebook.coverImagePath;
    if (rel != null) {
      return FutureBuilder<File?>(
        future:
            _coverFileCache.putIfAbsent(rel, () => FileStore.tryResolve(rel)),
        builder: (context, snap) {
          final f = snap.data;
          if (f != null) {
            return Image.file(
              f,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => _gradientCover(),
            );
          }
          return _gradientCover();
        },
      );
    }
    return _gradientCover();
  }

  Widget _gradientCover() {
    final cover = coverById(notebook.coverId) ?? BUILTIN_COVERS.first;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: cover.colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  /// Trash countdown chip, or a PDF badge for imported notebooks.
  Widget _coverBadge() {
    if (notebook.deleted) {
      final days = LibraryController.I.daysLeftInTrash(notebook);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '${S.num(days)} ${S.t('daysLeft')}',
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
        ),
      );
    }
    if (notebook.pdfPath != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf, size: 12, color: Colors.white),
            SizedBox(width: 3),
            Text('PDF',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _favoriteButton(BuildContext context) {
    final nc = nanoteColors(context);
    return IconButton(
      onPressed: onFavorite,
      icon: Icon(notebook.favorite ? Icons.star : Icons.star_border, size: 20),
      color: notebook.favorite ? nc.warning : nc.mutedFg,
      tooltip: S.t(notebook.favorite ? 'unfavorite' : 'favorite'),
    );
  }

  Widget _tagDots() {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3, bottom: 4),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            for (final t in tags.take(6))
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Color(t.color),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6), width: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
