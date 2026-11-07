import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

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
/// * Add page (+ tile at the end of the grid, plus the header button)
///   appends a new page after the last one.
///
/// v1.9.1 restyle: rounded-lg thumbnails with 2px borders (primary for the
/// active page) + ink-1 shadows, pill page-number badge at the bottom-end
/// corner, 8px warning bookmark dot at the top-start corner, a dashed
/// "add page" tile and pill action buttons.
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
            padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsetsDirectional.only(start: 8),
                    child: Text(
                      _selectMode
                          ? '${S.num(_selected.length)} / ${S.num(widget.engine.pages.length)}'
                          : S.t('pagesManager'),
                      style: nanoteText(TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      )),
                    ),
                  ),
                ),
                if (_selectMode) ...[
                  IconButton(
                    tooltip: S.t('selectAll'),
                    icon: Icon(LucideIcons.square_check_big,
                        size: 20, color: colors.mutedFg),
                    onPressed: () => setState(() {
                      _selected
                        ..clear()
                        ..addAll(widget.engine.pages.map((p) => p.id));
                    }),
                  ),
                  IconButton(
                    tooltip: S.t('close'),
                    icon:
                        Icon(LucideIcons.x, size: 20, color: colors.mutedFg),
                    onPressed: _exitSelectMode,
                  ),
                ] else ...[
                  IconButton(
                    tooltip: S.t('addPage'),
                    icon: Icon(LucideIcons.plus,
                        size: 20, color: colors.mutedFg),
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
                      itemCount: pages.length + 1,
                      // The cells are keyed by PAGE ID (not grid slot):
                      // without the key, the builder reuses the element at
                      // each slot after a reorder/delete/duplicate, so the
                      // stateful thumbnail kept painting the previous slot's
                      // PDF background for the page now occupying it.
                      itemBuilder: (context, i) => i == pages.length
                          ? _AddPageCell(onTap: () => unawaited(_addPage()))
                          : _PageCell(
                              key: ValueKey(pages[i].id),
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  _action(LucideIcons.file_text, 'exportPdf',
                      _exportSelectedPdf),
                  if (single)
                    _action(LucideIcons.image, 'exportPng',
                        () => _exportSelectedPng(metas.first)),
                  if (single)
                    _action(LucideIcons.pencil, 'rename', _renameSelected),
                  _action(LucideIcons.copy, 'duplicatePage',
                      _duplicateSelected),
                  if (single)
                    _action(
                        LucideIcons.arrow_up, 'moveUp', () => _moveSelected(-1)),
                  if (single)
                    _action(LucideIcons.arrow_down, 'moveDown',
                        () => _moveSelected(1)),
                  _action(
                    LucideIcons.bookmark,
                    'bookmark',
                    _bookmarkSelected,
                    marked: allMarked,
                  ),
                  _action(LucideIcons.trash, 'deletePages', _deleteSelected,
                      destructive: true),
                ],
              ),
            ),
          ),
        );
    return bar(context);
  }

  /// Pill action button (44px target) with optional destructive tint.
  Widget _action(IconData icon, String label, Future<void> Function() onTap,
      {bool destructive = false, bool marked = false}) {
    final scheme = Theme.of(context).colorScheme;
    final colors = nanoteColors(context);
    final fg = destructive
        ? scheme.error
        : (marked ? colors.warning : scheme.primary);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
      child: Pressable(
        onTap: () => unawaited(onTap()),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: destructive
                ? scheme.error.withValues(alpha: 0.08)
                : colors.accent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                S.t(label),
                style: nanoteText(TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: destructive ? scheme.error : scheme.onSurface,
                )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed "add page" tile: dashed rounded-rect border (border color) with a
/// centered muted plus; tints to Nanote Blue while pressed.
class _AddPageCell extends StatefulWidget {
  const _AddPageCell({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AddPageCell> createState() => _AddPageCellState();
}

class _AddPageCellState extends State<_AddPageCell> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = _down ? scheme.primary : scheme.outline;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: _down
                ? scheme.primary.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
          ),
          padding: const EdgeInsets.all(6),
          child: CustomPaint(
            foregroundPainter: _DashedRRectPainter(
              color: tint,
              radius: NANOTE_RADIUS_MD,
            ),
            child: Center(
              child: Icon(
                LucideIcons.plus,
                size: 24,
                color: _down ? scheme.primary : nanoteColors(context).mutedFg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed rounded-rect stroke.
class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, this.radius = NANOTE_RADIUS_MD});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = color;
    const dash = 6.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        var next = dist + dash;
        if (next > metric.length) next = metric.length;
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

/// One grid cell: live mini preview + number badge + bookmark dot +
/// selection overlay.
class _PageCell extends StatefulWidget {
  const _PageCell({
    super.key,
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
    final active = widget.selected || widget.isCurrent;
    return Pressable(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
          border: Border.all(
            color: active ? scheme.primary : scheme.outline,
            width: 2,
          ),
          color: scheme.surface,
          boxShadow: colors.inkShadow1,
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
                      borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
                      child: _thumb(colors),
                    ),
                  ),
                  // Number badge (bottom-end corner).
                  PositionedDirectional(
                    bottom: 6,
                    end: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        S.num(widget.index + 1),
                        style: nanoteText(const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        )),
                      ),
                    ),
                  ),
                  // Bookmark dot (top-start corner).
                  if (widget.meta.bookmarked)
                    PositionedDirectional(
                      top: 6,
                      start: 6,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.warning,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.85),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  if (widget.selectMode)
                    PositionedDirectional(
                      top: 5,
                      end: 5,
                      child: _checkbox(scheme, colors),
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
              style: nanoteText(TextStyle(
                fontSize: 10.5,
                color: colors.mutedFg,
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkbox(ColorScheme scheme, NanoteColors colors) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.selected
            ? colors.accent
            : Colors.black.withValues(alpha: 0.4),
        border: Border.all(color: Colors.white, width: 1.6),
      ),
      child: widget.selected
          ? const Icon(LucideIcons.check, size: 13, color: Colors.white)
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
  String? _retainedHandle;

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
        // Retain while this thumbnail paints it (by unique handle).
        ctrl.retain(bmp.handle);
        setState(() {
          _pdfImage = bmp.image;
          _retainedHandle = bmp.handle;
        });
      }
    } catch (_) {
      // No PDF background — plain paper preview.
    }
  }

  @override
  void dispose() {
    final handle = _retainedHandle;
    if (handle != null) {
      PdfDocumentController.I.release(handle);
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
