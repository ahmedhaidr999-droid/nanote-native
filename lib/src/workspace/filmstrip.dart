import 'package:flutter/material.dart';

import '../controllers/stroke_engine.dart';
import '../controllers/viewport_controller.dart';
import '../i18n/strings.dart';
import '../models/paper.dart';
import '../theme/nanote_theme.dart';
import 'doc_geometry.dart';
import 'elements_painter.dart';

/// Vertical rail of page thumbnails (wide layouts only — the workspace hides
/// it under ~900px width).
///
/// * Tap a thumbnail → [onJump](pageId).
/// * Long-press → bottom sheet: add page after / duplicate / delete (with
///   confirmation) / move up / move down / bookmark toggle / rename title.
/// * Trailing "+" button appends a page and jumps to it.
/// * Listens to [StrokeEngine.pagesChanged].
class Filmstrip extends StatelessWidget {
  const Filmstrip({
    super.key,
    required this.engine,
    required this.viewport,
    required this.geometry,
    required this.onJump,
  });

  final StrokeEngine engine;
  final ViewportController viewport;
  final DocGeometry geometry;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 72,
      decoration: BoxDecoration(
        color: scheme.secondary,
        border: BorderDirectional(
          end: BorderSide(color: scheme.outline),
        ),
      ),
      child: ListenableBuilder(
        listenable: engine.pagesChanged,
        builder: (context, _) {
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: engine.pages.length,
                  itemBuilder: (context, i) =>
                      _thumb(context, engine.pages[i], i),
                ),
              ),
              Divider(height: 1, color: scheme.outline),
              IconButton(
                tooltip: S.t('addPage'),
                icon: const Icon(Icons.add),
                onPressed: () async {
                  final meta = await engine.addPage();
                  onJump(meta.id);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _thumb(BuildContext context, PageMeta meta, int index) {
    final scheme = Theme.of(context).colorScheme;
    final colors = nanoteColors(context);
    final ps = meta.effectiveSize;
    final thumbH = 56.0 * ps.height / ps.width;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onJump(meta.id),
        onLongPress: () => _showPageMenu(context, meta, index),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outline),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 56,
              height: thumbH,
              child: Stack(
                children: [
                  CustomPaint(
                    size: Size(56, thumbH),
                    painter: _ThumbPainter(
                      meta: meta,
                      ink: engine.pageInk(meta.id),
                    ),
                  ),
                  PositionedDirectional(
                    top: 2,
                    start: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        S.num(index + 1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (meta.bookmarked)
                    PositionedDirectional(
                      bottom: 2,
                      end: 2,
                      child: Icon(
                        Icons.bookmark,
                        size: 14,
                        color: colors.warning,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPageMenu(
      BuildContext context, PageMeta meta, int index) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final onlyPage = engine.pages.length <= 1;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(S.t('addPage')),
                onTap: () => Navigator.pop(ctx, 'addAfter'),
              ),
              ListTile(
                leading: const Icon(Icons.content_copy),
                title: Text(S.t('duplicatePage')),
                onTap: () => Navigator.pop(ctx, 'duplicate'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(S.t('deletePage')),
                enabled: !onlyPage,
                onTap: onlyPage ? null : () => Navigator.pop(ctx, 'delete'),
              ),
              ListTile(
                leading: const Icon(Icons.arrow_upward),
                title: Text(S.t('moveUp')),
                enabled: index > 0,
                onTap: index > 0 ? () => Navigator.pop(ctx, 'up') : null,
              ),
              ListTile(
                leading: const Icon(Icons.arrow_downward),
                title: Text(S.t('moveDown')),
                enabled: index < engine.pages.length - 1,
                onTap: index < engine.pages.length - 1
                    ? () => Navigator.pop(ctx, 'down')
                    : null,
              ),
              ListTile(
                leading: Icon(
                  meta.bookmarked ? Icons.bookmark : Icons.bookmark_border,
                ),
                title: Text(S.t('bookmark')),
                onTap: () => Navigator.pop(ctx, 'bookmark'),
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: Text(S.t('rename')),
                onTap: () => Navigator.pop(ctx, 'rename'),
              ),
            ],
          ),
        );
      },
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'addAfter':
        final m = await engine.addPage(afterPosition: meta.position);
        onJump(m.id);
        break;
      case 'duplicate':
        final m = await engine.duplicatePage(meta.id);
        onJump(m.id);
        break;
      case 'delete':
        final ok = await _confirmDelete(context);
        if (ok == true) await engine.deletePage(meta.id);
        break;
      case 'up':
        await engine.reorderPage(meta.id, meta.position - 1);
        break;
      case 'down':
        await engine.reorderPage(meta.id, meta.position + 1);
        break;
      case 'bookmark':
        await engine.setPageBookmark(meta.id, !meta.bookmarked);
        break;
      case 'rename':
        await _rename(context, meta);
        break;
    }
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('deletePage')),
        content: Text(S.t('confirmDeletePage')),
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
  }

  Future<void> _rename(BuildContext context, PageMeta meta) async {
    final controller = TextEditingController(text: meta.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('pageTitle')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: S.t('untitledPage')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.t('save')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await engine.setPageTitle(meta.id, controller.text.trim());
    }
    controller.dispose();
  }
}

/// Scaled-down page render: applies `thumbWidth / pageWidth` scaling, then
/// delegates to [PageContentPainter] (paper + content).
class _ThumbPainter extends CustomPainter {
  _ThumbPainter({required this.meta, required this.ink}) : super(repaint: ink);

  final PageMeta meta;
  final PageInk ink;

  @override
  void paint(Canvas canvas, Size size) {
    final ps = meta.effectiveSize;
    if (ps.width <= 0 || ps.height <= 0) return;
    final scale = size.width / ps.width;
    PageContentPainter(
      template: TemplateIdX.fromId(meta.template),
      paperColor: paperColorFrom(meta.paperColor),
      pageSize: ps,
      ink: ink,
      scaleForThumb: scale,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _ThumbPainter oldDelegate) => true;
}
