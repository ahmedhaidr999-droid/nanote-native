import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/stroke_engine.dart';
import '../../i18n/strings.dart';
import '../../models/paper.dart';
import '../../workspace/elements_painter.dart';

/// Full-height page manager: thumbnails, labels, bookmarks, add / duplicate /
/// delete / reorder / rename. Tapping a row pops the sheet with the page id
/// (Navigator.pop(result)) so the caller can center the viewport on it.
Future<void> showPagesSheet(BuildContext context, StrokeEngine engine,
    {void Function(int pageId)? onJump}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _PagesSheet(engine: engine, onJump: onJump),
  ).then((pageId) {
    if (pageId != null) onJump?.call(pageId);
  });
}

class _PagesSheet extends StatelessWidget {
  const _PagesSheet({required this.engine, this.onJump});

  final StrokeEngine engine;
  final void Function(int pageId)? onJump;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    S.t('pagesManager'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: S.t('addPage'),
                  icon: const Icon(Icons.add),
                  onPressed: () => unawaited(engine.addPage()),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListenableBuilder(
              listenable: engine.pagesChanged,
              builder: (context, _) {
                final pages = engine.pages;
                if (pages.isEmpty) {
                  return Center(child: Text(S.t('none')));
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: pages.length,
                  itemBuilder: (context, i) => _PageRow(
                    engine: engine,
                    meta: pages[i],
                    index: i,
                    total: pages.length,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PageRow extends StatelessWidget {
  const _PageRow({
    required this.engine,
    required this.meta,
    required this.index,
    required this.total,
  });

  final StrokeEngine engine;
  final PageMeta meta;
  final int index;
  final int total;

  Future<void> _onMenu(BuildContext context, String action) async {
    switch (action) {
      case 'title':
        await _rename(context);
        break;
      case 'dup':
        await engine.duplicatePage(meta.id);
        break;
      case 'del':
        await _confirmDelete(context);
        break;
      case 'up':
        if (index > 0) {
          await engine.reorderPage(meta.id, index - 1);
        }
        break;
      case 'down':
        if (index < total - 1) {
          await engine.reorderPage(meta.id, index + 1);
        }
        break;
    }
  }

  Future<void> _rename(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(title: S.t('pageTitle'), initial: meta.title),
    );
    if (name != null && name.isNotEmpty) {
      await engine.setPageTitle(meta.id, name);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('confirmDeletePage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t('delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await engine.deletePage(meta.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Lazily pull the page's strokes so the thumbnail can render them.
    unawaited(engine.ensureLoaded(meta.id));
    return ListenableBuilder(
      listenable: engine.pageInk(meta.id),
      builder: (context, _) {
        final ps = meta.sizeDef.size;
        final thumbHeight = 56 * ps.height / ps.width;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          leading: SizedBox(
            width: 56,
            height: thumbHeight,
            child: CustomPaint(
              painter: _ThumbPainter(meta, engine.pageInk(meta.id)),
            ),
          ),
          title: Text(
            meta.title.isNotEmpty ? meta.title : S.t('untitledPage'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(S.pageOf(index + 1, total)),
          onTap: () => Navigator.of(context).pop(meta.id),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: S.t('bookmark'),
                icon: Icon(
                  meta.bookmarked ? Icons.bookmark : Icons.bookmark_border,
                ),
                color: meta.bookmarked
                    ? Theme.of(context).colorScheme.primary
                    : null,
                onPressed: () =>
                    unawaited(engine.setPageBookmark(meta.id, !meta.bookmarked)),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (v) => unawaited(_onMenu(context, v)),
                itemBuilder: (ctx) => [
                  _menuItem('title', Icons.edit_outlined, S.t('pageTitle')),
                  _menuItem('dup', Icons.content_copy, S.t('duplicatePage')),
                  _menuItem('del', Icons.delete_outline, S.t('deletePage')),
                  _menuItem(
                      'up', Icons.arrow_upward, S.t('moveUp'),
                      enabled: index > 0),
                  _menuItem(
                      'down', Icons.arrow_downward, S.t('moveDown'),
                      enabled: index < total - 1),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label,
      {bool enabled = true}) {
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: S.t('nameHint')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(S.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(S.t('save')),
        ),
      ],
    );
  }
}

/// Tiny page thumbnail: PageContentPainter (paper + content) scaled into a
/// 56px-wide box via its [PageContentPainter.scaleForThumb] support.
class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.meta, this.ink);

  final PageMeta meta;
  final PageInk ink;

  @override
  void paint(Canvas canvas, Size size) {
    final ps = meta.sizeDef.size;
    if (ps.width <= 0 || ps.height <= 0) return;
    final scale = size.width / ps.width;
    PageContentPainter(
      template: TemplateIdX.fromId(meta.template),
      paperColor: paperColorFrom(meta.paperColor),
      pageSize: ps,
      ink: ink,
      scaleForThumb: scale,
    ).paint(canvas, size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = isDarkPaper(paperColorFrom(meta.paperColor))
            ? const Color(0x33FFFFFF)
            : const Color(0x1F000000),
    );
  }

  @override
  bool shouldRepaint(covariant _ThumbPainter oldDelegate) => true;
}
