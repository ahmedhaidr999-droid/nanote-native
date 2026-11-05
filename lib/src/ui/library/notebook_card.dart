import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../controllers/library_controller.dart';
import '../../i18n/strings.dart';
import '../../models/paper.dart';
import '../../persistence/file_store.dart';
import '../../persistence/library_repository.dart';
import '../../theme/nanote_theme.dart';
import '../widgets/cover_art.dart';

/// Resolved cover-image file cache (avoids re-hitting the disk on rebuilds).
final Map<String, Future<File?>> _coverFileCache = {};

/// A notebook in the library: grid variant (3:4 [CoverArt], title, page-count
/// chip, favorite badge) or a list row ([listMode]).
///
/// Long-press invokes [onMenu] — the parent shows the action sheet (rename /
/// move / tags / favorite / delete-or-restore).
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

  /// Renders a row instead of the grid cell.
  final bool listMode;

  @override
  Widget build(BuildContext context) {
    return listMode ? _buildList(context) : _buildGrid(context);
  }

  // ------------------------------------------------------------------- grid

  Widget _buildGrid(BuildContext context) {
    return Pressable(
      onTap: onOpen,
      onLongPress: () => onMenu(notebook),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: w,
                height: w * 4 / 3,
                child: _coverWithOverlays(context),
              ),
              const SizedBox(height: 6),
              Text(
                notebook.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _pageCountChip(context),
              ),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------------- list

  Widget _buildList(BuildContext context) {
    final nc = nanoteColors(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding:
            const EdgeInsetsDirectional.fromSTEB(12, 8, 6, 8),
        onTap: onOpen,
        onLongPress: () => onMenu(notebook),
        leading: SizedBox(
          width: 44,
          height: 58,
          child: _cover(radius: NANOTE_RADIUS_SM),
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
              icon: const Icon(LucideIcons.ellipsis_vertical, size: 20),
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

  /// Cover stack with the optional overlays (favorite star, PDF / trash
  /// countdown badges).
  Widget _coverWithOverlays(BuildContext context) {
    final nc = nanoteColors(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        _cover(radius: NANOTE_RADIUS_LG),
        // Favorite star — bottom-start corner.
        if (notebook.favorite)
          PositionedDirectional(
            start: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.star,
                  size: 14, color: nc.warning),
            ),
          ),
        // PDF / trash countdown badge — bottom-end corner.
        PositionedDirectional(
          end: 6,
          bottom: 6,
          child: _coverBadge(),
        ),
      ],
    );
  }

  /// The notebook cover: custom image when set, otherwise the built-in
  /// [CoverArt] (3:4, gradient/flat/dots/lines, ink-1 shadow).
  Widget _cover({required double radius}) {
    final rel = notebook.coverImagePath;
    if (rel != null) {
      return FutureBuilder<File?>(
        future:
            _coverFileCache.putIfAbsent(rel, () => FileStore.tryResolve(rel)),
        builder: (context, snap) {
          final f = snap.data;
          if (f != null) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                boxShadow: nanoteColors(context).inkShadow1,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Image.file(
                  f,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) =>
                      CoverArt(cover: _coverDef, borderRadius: radius),
                ),
              ),
            );
          }
          return CoverArt(cover: _coverDef, borderRadius: radius);
        },
      );
    }
    return CoverArt(cover: _coverDef, borderRadius: radius);
  }

  CoverDef get _coverDef =>
      coverById(notebook.coverId) ?? BUILTIN_COVERS.first;

  /// Small rounded-full page-count chip ("12 pages") on a secondary surface.
  Widget _pageCountChip(BuildContext context) {
    final nc = nanoteColors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: nc.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${S.num(pageCount)} ${S.t('pagesCount')}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: nc.mutedFg,
        ),
      ),
    );
  }

  /// Trash countdown chip, or a PDF badge for imported notebooks.
  Widget _coverBadge() {
    if (notebook.deleted) {
      final days = LibraryController.I.daysLeftInTrash(notebook);
      return _scrimBadge(
        child: Text(
          '${S.num(days)} ${S.t('daysLeft')}',
          style: const TextStyle(
              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
        ),
      );
    }
    if (notebook.pdfPath != null) {
      return _scrimBadge(
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.file_text, size: 14, color: Colors.white),
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

  Widget _scrimBadge({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: child,
    );
  }

  Widget _favoriteButton(BuildContext context) {
    final nc = nanoteColors(context);
    return IconButton(
      onPressed: onFavorite,
      icon: Icon(
        notebook.favorite ? LucideIcons.star : LucideIcons.star_off,
        size: 20,
      ),
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
