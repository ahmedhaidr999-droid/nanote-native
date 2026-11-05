import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../controllers/pdf_document_controller.dart';
import '../../controllers/stroke_engine.dart';
import '../../i18n/strings.dart';
import '../../models/paper.dart';
import '../../services/export_service.dart';
import '../../theme/nanote_theme.dart';
import '../../workspace/elements_painter.dart';

/// Full-height PAGES MANAGER (opened from the top bar "pages" button — the
/// old left-side filmstrip is gone).
///
/// * Grid of live mini previews (paper + ink + PDF background).
/// * Tap a page → jump to it (the sheet pops with the page id).
/// * Long-press → multi-SELECT mode; tap more pages to extend the selection.
/// * Selection actions: export (PDF of the selection / PNG when single),
///   rename, duplicate, move up/down, bookmark, delete (with confirm).
/// * Add page (+) appends a new page after the last one.
Future<void> showPagesSheet(
  BuildContext context,
  StrokeEngine engine, {
  void Function(int pageId)? onJump,
  int? currentId,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _PagesSheet(engine: engine, onJump: onJump, currentId: currentId),
  ).then((pageId) {
    if (pageId != null) onJump?.call(pageId);
  });
}

class _PagesSheet extends StatefulWidget {
  const _PagesSheet({required this.engine, this.onJump, this.currentId});

  final StrokeEngine engine;
  final void Function(int pageId)? onJump;
  final int? currentId;

  @override
  State<_PagesSheet> createState() => _PagesSheetState();
}

class _PagesSheetState extends State<_PagesSheet> {
  final Set<int> _selected = {};
  bool _selectMode = false;
  bool _busy = false;

  bool get _hasSelection => _selected.isNotEmpty;

  void _toggle(int pageId) {
    setState(() {
      if (_selected.contains(pageId)) {
        _selected.remove(pageId);
      } else {
        _selected.add(pageId);
      }
      if (_selected.isEmpty) _selectMode = false;
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selected.clear();
      _selectMode = false;
    });
  }

  List<PageMeta> get _selectedMetas {
    final pages = widget.engine.pages;
    return [
      for (final m in pages)
        if (_selected.contains(m.id)) m,
    ];
  }

  // ---------------------------------------------------------------- actions

  Future<void> _addPage() async {
    final meta = await widget.engine.addPage();
    if (!mounted) return;
    Navigator.of(context).pop(meta.id);
  }

  Future<void> _deleteSelected() async {
    final metas = _selectedMetas;
    if (metas.isEmpty) return;
    // Never delete every page — a notebook must keep at least one.
    if (metas.length >= widget.engine.pages.length) {
      _toast(S.t('cantDeleteAllPages'));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('deletePages')),
        content: Text(S.t('confirmDeletePages')
            .replaceAll('{n}', S.num(metas.length))),
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
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    for (final m in metas) {
      // Keep at least one page.
      if (widget.engine.pages.length <= 1) break;
      await widget.engine.deletePage(m.id);
      _selected.remove(m.id);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selectMode = _selected.isNotEmpty;
    });
  }

  Future<void> _duplicateSelected() async {
    final metas = _selectedMetas;
    if (metas.isEmpty) return;
    setState(() => _busy = true);
    PageMeta? last;
    for (final m in metas) {
      last = await widget.engine.duplicatePage(m.id);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected.clear();
      _selectMode = false;
    });
    if (last != null) Navigator.of(context).pop(last.id);
  }

  Future<void> _exportSelectedPdf() async {
    final metas = _selectedMetas;
    if (metas.isEmpty) return;
    _exitSelectMode();
    unawaited(ExportService.sharePagesPdf(widget.engine, metas));
  }

  Future<void> _exportSelectedPng(PageMeta meta) async {
    _exitSelectMode();
    unawaited(ExportService.sharePagePng(widget.engine, meta));
  }

  Future<void> _moveSelected(int delta) async {
    final metas = _selectedMetas;
    if (metas.length != 1) return;
    final m = metas.first;
    final pages = widget.engine.pages;
    final idx = pages.indexWhere((p) => p.id == m.id);
    if (idx < 0) return;
    final target = idx + delta;
    if (target < 0 || target >= pages.length) return;
    setState(() => _busy = true);
    await widget.engine.reorderPage(m.id, target);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _renameSelected() async {
    final metas = _selectedMetas;
    if (metas.length != 1) return;
    final m = metas.first;
    final controller = TextEditingController(text: m.title);
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
      await widget.engine.setPageTitle(m.id, controller.text.trim());
    }
    controller.dispose();
    if (mounted) _exitSelectMode();
  }

  Future<void> _bookmarkSelected() async {
    final metas = _selectedMetas;
    if (metas.isEmpty) return;
    final allMarked = metas.every((m) => m.bookmarked);
    for (final m in metas) {
      await widget.engine.setPageBookmark(m.id, !allMarked);
    }
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = nanoteColors(context);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.92,
      child: Column(
        children: [
          // Header.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectMode
                        ? '${S.num(_selected.length)} / ${S.num(widget.engine.pages.length)}'
                        : S.t('pagesManager'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (_selectMode) ...[
                  IconButton(
                    tooltip: S.t('selectAll'),
                    icon: const Icon(Icons.select_all),
                    onPressed: () => setState(() {
                      _selected
                        ..clear()
                        ..addAll(widget.engine.pages.map((p) => p.id));
                    }),
                  ),
                  IconButton(
                    tooltip: S.t('close'),
                    icon: const Icon(Icons.close),
                    onPressed: _exitSelectMode,
                  ),
                ] else ...[
                  IconButton(
                    tooltip: S.t('addPage'),
                    icon: const Icon(Icons.add),
                    onPressed: () => unawaited(_addPage()),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outline),
          // Grid.
          Expanded(
            child: Stack(
              children: [
                ListenableBuilder(
                  listenable: widget.engine.pagesChanged,
                  builder: (context, _) {
                    final pages = widget.engine.pages;
                    if (pages.isEmpty) {
                      return Center(child: Text(S.t('none')));
                    }
                    return GridView.builder(
                      padding: const EdgeInsets.all(14),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 150,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: pages.length,
                      itemBuilder: (context, i) => _PageCell(
                        engine: widget.engine,
                        meta: pages[i],
                        index: i,
                        total: pages.length,
                        selected: _selected.contains(pages[i].id),
                        selectMode: _selectMode,
                        isCurrent: pages[i].id == widget.currentId,
                        onTap: () {
                          if (_selectMode) {
                            _toggle(pages[i].id);
                          } else {
                            Navigator.of(context).pop(pages[i].id);
                          }
                        },
                        onLongPress: () {
                          if (!_selectMode) {
                            setState(() {
                              _selectMode = true;
                              _selected.add(pages[i].id);
                            });
                          } else {
                            _toggle(pages[i].id);
                          }
                        },
                      ),
                    );
                  },
                ),
                if (_busy)
                  Positioned.fill(
                    child: Container(
                      color: scheme.surface.withValues(alpha: 0.5),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
          ),
          // Selection action bar.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _hasSelection
                ? _buildActionBar(context, colors)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar(BuildContext context, NanoteColors colors) {
    final scheme = Theme.of(context).colorScheme;
    final metas = _selectedMetas;
    final single = metas.length == 1;
    final allMarked = metas.isNotEmpty && metas.every((m) => m.bookmarked);
    Widget bar(BuildContext context) => Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(top: BorderSide(color: scheme.outline)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  _action(Icons.picture_as_pdf, 'exportPdf', _exportSelectedPdf),
                  if (single)
                    _action(Icons.image_outlined, 'exportPng',
                        () => _exportSelectedPng(metas.first)),
                  if (single) _action(Icons.edit_outlined, 'rename', _renameSelected),
                  _action(Icons.content_copy, 'duplicatePage',
                      _duplicateSelected),
                  if (single)
                    _action(Icons.arrow_upward, 'moveUp',
                        () => _moveSelected(-1)),
                  if (single)
                    _action(Icons.arrow_downward, 'moveDown',
                        () => _moveSelected(1)),
                  _action(
                    allMarked ? Icons.bookmark : Icons.bookmark_border,
                    'bookmark',
                    _bookmarkSelected,
                  ),
                  _action(Icons.delete_outline, 'deletePages', _deleteSelected,
                      destructive: true),
                ],
              ),
            ),
          ),
        );
    return bar(context);
  }

  Widget _action(IconData icon, String label, Future<void> Function() onTap,
      {bool destructive = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(NANOTE_RADIUS),
        onTap: () => unawaited(onTap()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 22,
                  color: destructive ? scheme.error : scheme.primary),
              const SizedBox(height: 2),
              Text(
                S.t(label),
                style: TextStyle(
                  fontSize: 10.5,
                  color: destructive ? scheme.error : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One grid cell: live mini preview + number + bookmark + selection overlay.
class _PageCell extends StatefulWidget {
  const _PageCell({
    required this.engine,
    required this.meta,
    required this.index,
    required this.total,
    required this.selected,
    required this.selectMode,
    required this.isCurrent,
    required this.onTap,
    required this.onLongPress,
  });

  final StrokeEngine engine;
  final PageMeta meta;
  final int index;
  final int total;
  final bool selected;
  final bool selectMode;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_PageCell> createState() => _PageCellState();
}

class _PageCellState extends State<_PageCell> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.engine.ensureLoaded(widget.meta.id));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = nanoteColors(context);
    return InkWell(
      borderRadius: BorderRadius.circular(NANOTE_RADIUS),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NANOTE_RADIUS),
          border: Border.all(
            color: widget.selected
                ? scheme.primary
                : widget.isCurrent
                    ? scheme.primary.withValues(alpha: 0.55)
                    : scheme.outline,
            width: widget.selected ? 2.4 : 1.4,
          ),
          color: scheme.surface,
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _thumb(colors),
                    ),
                  ),
                  // Number badge.
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        S.num(widget.index + 1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (widget.meta.bookmarked)
                    Positioned(
                      top: 3,
                      right: 3,
                      child: Icon(
                        Icons.bookmark,
                        size: 14,
                        color: colors.warning,
                        shadows: const [
                          Shadow(blurRadius: 3, color: Colors.black45),
                        ],
                      ),
                    ),
                  if (widget.selectMode)
                    Positioned(
                      top: 3,
                      right: 3,
                      child: _checkbox(scheme),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.meta.title.isNotEmpty
                  ? widget.meta.title
                  : S.t('untitledPage'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkbox(ColorScheme scheme) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.selected ? scheme.primary : Colors.black.withValues(alpha: 0.4),
        border: Border.all(color: Colors.white, width: 1.6),
      ),
      child: widget.selected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }

  Widget _thumb(NanoteColors colors) {
    return _PdfThumb(
      engine: widget.engine,
      meta: widget.meta,
      ink: widget.engine.pageInk(widget.meta.id),
    );
  }
}

/// Mini preview: PDF background (when the notebook has one) + paper +
/// template + ink, painted via the shared [PageContentPainter].
class _PdfThumb extends StatefulWidget {
  const _PdfThumb({required this.engine, required this.meta, required this.ink});

  final StrokeEngine engine;
  final PageMeta meta;
  final PageInk ink;

  @override
  State<_PdfThumb> createState() => _PdfThumbState();
}

class _PdfThumbState extends State<_PdfThumb> {
  ui.Image? _pdfImage;
  String? _retainedKey;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPdf());
  }

  Future<void> _loadPdf() async {
    final pdfPath = widget.engine.notebook?.pdfPath;
    if (pdfPath == null) return;
    final ctrl = PdfDocumentController.I;
    if (!ctrl.isOpen) return;
    final index = widget.engine.pages.indexWhere((p) => p.id == widget.meta.id);
    if (index < 0 || index + 1 > ctrl.pageCount) return;
    try {
      final bmp = await ctrl.pageImage(index + 1, 0.4);
      if (mounted && bmp != null) {
        // Retain while this thumbnail paints it.
        ctrl.retain(bmp.key);
        setState(() {
          _pdfImage = bmp.image;
          _retainedKey = bmp.key;
        });
      }
    } catch (_) {
      // No PDF background — plain paper preview.
    }
  }

  @override
  void dispose() {
    final key = _retainedKey;
    if (key != null) {
      PdfDocumentController.I.release(key);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ps = widget.meta.effectiveSize;
        final w = constraints.maxWidth;
        final h = w * ps.height / ps.width;
        return ListenableBuilder(
          listenable: widget.ink,
          builder: (context, _) => SizedBox(
            width: w,
            height: h,
            child: CustomPaint(
              size: Size(w, h),
              painter: _ThumbPainter(
                meta: widget.meta,
                ink: widget.ink,
                pdfImage: _pdfImage,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Scaled-down page render: PDF background (fitted) + paper + content via
/// [PageContentPainter].
class _ThumbPainter extends CustomPainter {
  _ThumbPainter({required this.meta, required this.ink, this.pdfImage});

  final PageMeta meta;
  final PageInk ink;
  final ui.Image? pdfImage;

  @override
  void paint(Canvas canvas, Size size) {
    final ps = meta.effectiveSize;
    if (ps.width <= 0 || ps.height <= 0) return;
    final scale = size.width / ps.width;

    final pdf = pdfImage;
    if (pdf != null) {
      canvas.drawImageRect(
        pdf,
        Rect.fromLTWH(0, 0, pdf.width.toDouble(), pdf.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.low,
      );
      PageContentPainter(
        template: TemplateIdX.fromId(meta.template),
        paperColor: paperColorFrom(meta.paperColor),
        pageSize: ps,
        ink: ink,
        paintPaper: false,
        scaleForThumb: scale,
      ).paint(canvas, size);
    } else {
      PageContentPainter(
        template: TemplateIdX.fromId(meta.template),
        paperColor: paperColorFrom(meta.paperColor),
        pageSize: ps,
        ink: ink,
        scaleForThumb: scale,
      ).paint(canvas, size);
    }
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
