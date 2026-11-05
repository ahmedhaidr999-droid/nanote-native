import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../controllers/audio_controller.dart';
import '../controllers/pdf_document_controller.dart';
import '../controllers/settings_controller.dart';
import '../controllers/stroke_engine.dart';
import '../controllers/tool_controller.dart';
import '../controllers/viewport_controller.dart';
import '../i18n/strings.dart';
import '../models/page_elements.dart';
import '../models/paper.dart';
import '../persistence/file_store.dart';
import '../services/export_service.dart';
import '../services/image_cache.dart';
import '../theme/nanote_theme.dart';
import '../ui/panels/audio_panel.dart' show showAudioPanel;
import '../ui/panels/color_popover.dart' show showColorPopover;
import '../ui/panels/pages_sheet.dart' show showPagesSheet;
import '../ui/panels/sticker_picker.dart' show showStickerPicker;
import '../ui/panels/text_sheet.dart' show showTextSheet;
import '../ui/panels/translate_popup.dart' show showTranslatePopup;
import 'doc_geometry.dart';
import 'elements_painter.dart';
import 'filmstrip.dart';
import 'gesture_router.dart';
import 'ink_painter.dart';
import 'laser_overlay.dart';
import 'pdf_page_tile.dart';
import 'ruler_overlay.dart';
import 'tool_rail.dart';
import 'tool_settings_panel.dart';

/// The full editor screen: header (back, title, undo/redo, zoom %, export
/// menu, audio, pages, settings), body (filmstrip | transformed canvas stack |
/// tool rail), overlays (selection bar, laser, ruler, lasso, eraser circle),
/// autosave and gesture-router wiring.
class DocumentWorkspace extends StatefulWidget {
  const DocumentWorkspace({super.key, required this.notebookId});

  final int notebookId;

  @override
  State<DocumentWorkspace> createState() => _DocumentWorkspaceState();
}

class _DocumentWorkspaceState extends State<DocumentWorkspace> {
  static const double _wideBreakpoint = 900;

  late final ViewportController viewport;
  late final DocGeometry geometry;
  late final RulerState ruler;
  late final GestureRouter router;
  late final Listenable _canvasRepaint;

  Timer? _autosave;
  int _lastAutosaveMs = -1;

  int? _currentPageId;
  bool _railHidden = false;
  bool _didInitialFit = false;

  /// After the initial fit, re-fit once when the first PDF page aspect lands
  /// (PDF notebooks start with a paper-size guess that gets corrected).
  bool _refitOnAspect = false;
  Size _screenSize = Size.zero;
  final Set<int> _loadRequested = {};

  // ---------------------------------------------------------------- setup

  @override
  void initState() {
    super.initState();
    final engine = StrokeEngine.I;
    viewport = ViewportController();
    geometry = DocGeometry(engine.pages);
    ruler = RulerState();
    router = GestureRouter(
      viewport: viewport,
      engine: engine,
      tools: ToolController.I,
      settings: SettingsController.I,
      audio: AudioController.I,
      geometry: geometry,
      ruler: ruler,
      onToggleToolbar: () => setState(() => _railHidden = !_railHidden),
      onQuickExport: _quickExport,
      onTextTap: _onTextTap,
      onPickImage: _onPickImage,
      onPickSticker: _onPickSticker,
      onPageChanged: _jumpToPage,
    );

    // Canvas repaints on: viewport motion, page-list/geometry changes, audio
    // replay clock — and PDF controller changes (doc opened / new renders /
    // page-size resolutions that feed the per-page aspect override).
    _canvasRepaint = Listenable.merge([
      viewport,
      engine.pagesChanged,
      AudioController.I, // drives the sync-replay cursor repaint
      PdfDocumentController.I,
      PdfDocumentController.I.renderTick,
    ]);

    // Painters resolve ImageEl src (relative path) through this hook — see
    // elements_painter.dart. AppImageCache.peekSync (Agent E) resolves via a
    // pre-resolved base directory; visible images are prewarmed separately.
    ElementsPainter.resolveImage = (rel) => AppImageCache.peekSync(rel);

    AudioController.I.addListener(_updateRecordingClock);
    _updateRecordingClock();
    SettingsController.I.addListener(_onSettingsChanged);

    unawaited(_open());
  }

  Future<void> _open() async {
    final engine = StrokeEngine.I;
    await engine.openNotebook(widget.notebookId);
    if (!mounted) return;
    final pdfPath = engine.notebook?.pdfPath;
    if (pdfPath != null) {
      final f = await FileStore.tryResolve(pdfPath);
      if (f != null) {
        await PdfDocumentController.I.open(f.path);
      }
    }
    if (!mounted) return;
    _startAutosave();
    setState(() {});
  }

  /// Per-page PDF aspect application: each notebook page whose PDF page size
  /// is known adopts the PDF's aspect ratio (at the paper's base width), so
  /// the PDF render is NEVER stretched and ink lands exactly on the content.
  ///
  /// Reads/kicks size resolution during build, but the ACTUAL application
  /// (which notifies listeners — e.g. the filmstrip, built BEFORE the canvas)
  /// is deferred to a post-frame callback so nothing is ever notified during
  /// the build phase.
  bool _pdfSizesScheduled = false;

  void _applyPdfSizes() {
    final pdf = PdfDocumentController.I;
    final engine = StrokeEngine.I;
    if (!pdf.isOpen || engine.pages.isEmpty) return;
    final count = pdf.pageCount;
    final pending = <(PageMeta, Size)>[];
    for (var i = 0; i < engine.pages.length; i++) {
      final meta = engine.pages[i];
      if (meta.pdfSize != null) continue;
      if (i >= count) break; // beyond the PDF → keep paper size
      final ps = pdf.pageSize(i + 1); // 1-based; null → async resolve kicked
      if (ps == null || ps.width <= 0 || ps.height <= 0) continue;
      final base = meta.sizeDef.size;
      pending.add((meta, Size(base.width, base.width * ps.height / ps.width)));
    }
    if (pending.isEmpty || _pdfSizesScheduled) return;
    _pdfSizesScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pdfSizesScheduled = false;
      if (!mounted) return;
      var refit = _refitOnAspect;
      for (final (meta, size) in pending) {
        if (meta.pdfSize != null) continue;
        engine.applyPdfPageSize(meta.id, size);
        if (refit) {
          // First aspect landed → re-fit page 0 so the opened view centers
          // the REAL page instead of the paper-size guess.
          refit = false;
          _refitOnAspect = false;
          if (_screenSize != Size.zero) {
            viewport.fitPageWidth(geometry.pageRect(0), _screenSize);
          }
        }
      }
    });
  }

  void _updateRecordingClock() {
    final audio = AudioController.I;
    StrokeEngine.I.recordingClock =
        audio.isRecording ? () => audio.recordingElapsedMs() : null;
  }

  void _onSettingsChanged() {
    if (SettingsController.I.settings.autosaveDelayMs != _lastAutosaveMs) {
      _startAutosave();
    }
  }

  void _startAutosave() {
    _autosave?.cancel();
    _autosave = null;
    StrokeEngine.I.historyChanged.removeListener(_flushNow);
    final ms = SettingsController.I.settings.autosaveDelayMs;
    _lastAutosaveMs = ms;
    if (ms > 0) {
      _autosave = Timer.periodic(
        Duration(milliseconds: ms),
        (_) => unawaited(StrokeEngine.I.flush()),
      );
    } else {
      // 0 = flush right after every history change.
      StrokeEngine.I.historyChanged.addListener(_flushNow);
    }
  }

  void _flushNow() => unawaited(StrokeEngine.I.flush());

  @override
  void dispose() {
    _autosave?.cancel();
    StrokeEngine.I.historyChanged.removeListener(_flushNow);
    AudioController.I.removeListener(_updateRecordingClock);
    SettingsController.I.removeListener(_onSettingsChanged);
    StrokeEngine.I.recordingClock = null;
    router.dispose();
    unawaited(StrokeEngine.I.flush());
    unawaited(StrokeEngine.I.close());
    unawaited(PdfDocumentController.I.close());
    ruler.dispose();
    viewport.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- helpers

  PageMeta? get _currentMeta {
    final engine = StrokeEngine.I;
    if (_currentPageId != null) {
      final m = engine.metaOf(_currentPageId!);
      if (m != null) return m;
    }
    return engine.pages.isEmpty ? null : engine.pages.first;
  }

  int? _replayAt() {
    final audio = AudioController.I;
    return audio.syncReplayMode ? audio.replayAtMs : null;
  }

  void _jumpToPage(int pageId) {
    final engine = StrokeEngine.I;
    final idx = engine.pages.indexWhere((p) => p.id == pageId);
    if (idx < 0) return;
    _currentPageId = pageId;
    viewport.fitPageWidth(geometry.pageRect(idx), _screenSize);
  }

  void _quickExport() {
    final meta = _currentMeta;
    if (meta == null) return;
    unawaited(ExportService.sharePagePng(StrokeEngine.I, meta));
  }

  void _resetZoom() {
    if (_screenSize == Size.zero) return;
    final meta = _currentMeta;
    if (meta == null) {
      viewport.zoomTo(1.0, _screenSize.center(Offset.zero));
      viewport.endInteraction();
      return;
    }
    final idx = StrokeEngine.I.pages.indexOf(meta);
    viewport.fitPageWidth(
      geometry.pageRect(idx < 0 ? 0 : idx),
      _screenSize,
    );
    viewport.endInteraction();
  }

  /// Keeps the page under the screen center current (used to decide where
  /// the live-stroke painter and paste go). While a stroke is live the page
  /// stays pinned to where the user started drawing (see _handlePointerDown).
  void _syncCurrentPageFromCenter(Size size) {
    final engine = StrokeEngine.I;
    if (engine.liveStroke.value != null) return;
    if (engine.pages.isEmpty) return;
    final meta = geometry.pageAt(viewport.toDoc(size.center(Offset.zero)));
    if (meta != null) _currentPageId = meta.id;
  }

  void _handlePointerDown(PointerDownEvent e) {
    final engine = StrokeEngine.I;
    if (engine.liveStroke.value == null) {
      // e.localPosition — canvas-relative. (e.position is window-GLOBAL;
      // using it picked the page 56px below the pen.)
      final meta = geometry.pageAt(viewport.toDoc(e.localPosition));
      if (meta != null && meta.id != _currentPageId) {
        setState(() => _currentPageId = meta.id);
      }
    }
    router.onPointerDown(e);
  }

  void _scheduleInitialFit() {
    if (_didInitialFit || _screenSize == Size.zero) return;
    if (StrokeEngine.I.pages.isEmpty) return;
    _didInitialFit = true;
    _refitOnAspect = StrokeEngine.I.notebook?.pdfPath != null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Notes-app style: fit the page WIDTH into the canvas, centered.
      viewport.fitPageWidth(geometry.pageRect(0), _screenSize);
    });
  }

  /// Lazy ink loading: request each newly visible page once, and prewarm its
  /// images so ImageEls appear once decoded.
  void _requestLoads(List<PageMeta> visible) {
    final engine = StrokeEngine.I;
    for (final meta in visible) {
      if (!_loadRequested.add(meta.id)) continue;
      unawaited(engine.ensureLoaded(meta.id));
      final ink = engine.pageInkOrNull(meta.id);
      if (ink == null) continue;
      for (final el in ink.elements) {
        if (el is ImageEl && el.src != null) {
          // Prewarm; once decoded, touch the ink so the page painter repaints
          // and resolves the image through ElementsPainter.resolveImage.
          unawaited(
            AppImageCache.loadByRel(el.src!).then((_) => ink.touch()),
          );
        }
      }
    }
  }

  // ------------------------------------------------------- router callbacks

  /// Text tool tap flow:
  ///  1. Tapped an existing TextEl → open the sheet in edit mode.
  ///  2. Otherwise create an EMPTY TextEl at the tap point, commit it via
  ///     engine.addElement, then open the sheet with `existing:` so the sheet
  ///     UPDATES it. When the user saves with empty text the SHEET removes
  ///     the just-created element (engine.removeElement) — that is the
  ///     agreed contract with the text sheet panel.
  void _onTextTap(int pageId, Offset pagePoint) {
    final engine = StrokeEngine.I;
    final tools = ToolController.I;
    final existing = engine.elementAt(pageId, pagePoint);
    if (existing is TextEl) {
      unawaited(showTextSheet(context, engine, pageId, existing: existing));
      return;
    }
    final el = TextEl(
      id: ElementIdGen.next(),
      z: 0, // engine.addElement assigns the real z
      text: '',
      x: pagePoint.dx,
      y: pagePoint.dy - 14,
      w: 220,
      size: tools.textSize,
      font: tools.textFont,
      color: tools.textColor,
      bold: tools.textBold,
      italic: tools.textItalic,
      underline: tools.textUnderline,
      align: tools.textAlign,
    );
    engine.addElement(pageId, el);
    unawaited(showTextSheet(context, engine, pageId, existing: el));
  }

  /// Image tool flow: pick a file → import into the files dir → decode to
  /// read dimensions → insert an ImageEl centered at the tap point.
  Future<void> _onPickImage(int pageId, Offset pagePoint) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      final path = result?.files.single.path;
      if (path == null || !mounted) return;
      final rel = await FileStore.importFile(File(path), 'images');
      final absFile = await FileStore.resolve(rel);
      final img = await AppImageCache.load(absFile.path);
      if (!mounted) return;
      final w = math.min(280.0, img.width.toDouble());
      final h = w * img.height / img.width;
      final el = ImageEl(
        id: ElementIdGen.next(),
        z: 0,
        src: rel,
        x: pagePoint.dx - w / 2,
        y: pagePoint.dy - h / 2,
        w: w,
        h: h,
      );
      final engine = StrokeEngine.I;
      engine.addElement(pageId, el);
      // Select it (contract: insert + select).
      engine.selectElements(pageId, [el.id]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.t('error'))),
        );
      }
    }
  }

  void _onPickSticker(int pageId, Offset pagePoint) {
    unawaited(showStickerPicker(context, StrokeEngine.I, pageId, pagePoint));
  }

  void _pasteHere() {
    final engine = StrokeEngine.I;
    final pageId = engine.selectionPageId ?? _currentPageId;
    if (pageId == null) return;
    final centerDoc = viewport.toDoc(_screenSize.center(Offset.zero));
    final pagePoint = centerDoc - geometry.pageOrigin(pageId);
    engine.pasteAt(pageId, pagePoint);
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final engine = StrokeEngine.I;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(context, engine),
      body: ListenableBuilder(
        listenable: SettingsController.I,
        builder: (context, _) {
          final leftHanded = SettingsController.I.settings.leftHanded;
          final wide = MediaQuery.sizeOf(context).width > _wideBreakpoint;
          final rail = ToolRail(
            tools: ToolController.I,
            engine: engine,
            ruler: ruler,
            leftHanded: leftHanded,
            hidden: _railHidden,
            onColorTap: () => unawaited(showColorPopover(context, ToolController.I)),
            onUndo: engine.undo,
            onRedo: engine.redo,
          );
          final canvas = Expanded(child: _buildCanvasArea(context));
          final Widget? strip = wide
              ? Filmstrip(
                  engine: engine,
                  viewport: viewport,
                  geometry: geometry,
                  onJump: _jumpToPage,
                )
              : null;
          final row = leftHanded
              ? [rail, if (strip != null) strip, canvas]
              : [if (strip != null) strip, canvas, rail];
          return Row(children: row);
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, StrokeEngine engine) {
    final title = (engine.notebook?.title ?? '').trim();
    return AppBar(
      toolbarHeight: 56,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: S.t('close'),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        title.isEmpty ? S.t('editor') : title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        ListenableBuilder(
          listenable: engine.historyChanged,
          builder: (context, _) => Row(
            children: [
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: S.t('undo'),
                onPressed: engine.canUndo ? engine.undo : null,
              ),
              IconButton(
                icon: const Icon(Icons.redo),
                tooltip: S.t('redo'),
                onPressed: engine.canRedo ? engine.redo : null,
              ),
            ],
          ),
        ),
        AnimatedBuilder(
          animation: viewport,
          builder: (context, _) => TextButton(
            onPressed: _resetZoom,
            child: Text('${S.num((viewport.scale * 100).round())}%'),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: S.t('export'),
          icon: const Icon(Icons.share),
          onSelected: (v) {
            if (v == 'png') {
              final meta = _currentMeta;
              if (meta != null) {
                unawaited(ExportService.sharePagePng(engine, meta));
              }
            } else if (v == 'pdf') {
              unawaited(ExportService.shareNotebookPdf(engine));
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'png', child: Text(S.t('exportPng'))),
            PopupMenuItem(value: 'pdf', child: Text(S.t('exportPdf'))),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.mic),
          tooltip: S.t('audio'),
          onPressed: () => unawaited(showAudioPanel(context, engine)),
        ),
        IconButton(
          icon: const Icon(Icons.layers),
          tooltip: S.t('pages'),
          onPressed: () => unawaited(
              showPagesSheet(context, engine, onJump: _jumpToPage)),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: S.t('settings'),
          onPressed: () => Navigator.pushNamed(context, '/settings'),
        ),
      ],
    );
  }

  Widget _buildCanvasArea(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        _screenSize = size;
        router.screenSize = size;
        // Viewport clamping: an axis where the doc fits stays centered, a
        // larger axis keeps its edges within the view (pages can never be
        // panned fully off-screen — the "floating away" fix).
        viewport.screenExtent = size;
        viewport.panBounds = geometry.tightBounds;
        viewport.clampToDoc();
        _scheduleInitialFit();
        return Stack(
          fit: StackFit.expand,
          children: [
            // The drawing canvas — raw Listener only (NO GestureDetector).
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handlePointerDown,
              onPointerMove: router.onPointerMove,
              onPointerUp: router.onPointerUp,
              onPointerCancel: router.onPointerCancel,
              onPointerHover: router.onPointerHover,
              onPointerSignal: router.onPointerSignal,
              onPointerPanZoomStart: router.onPointerPanZoomStart,
              onPointerPanZoomUpdate: router.onPointerPanZoomUpdate,
              onPointerPanZoomEnd: router.onPointerPanZoomEnd,
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: _canvasRepaint,
                  builder: (context, _) {
                    _applyPdfSizes();
                    _syncCurrentPageFromCenter(size);
                    final visible =
                        geometry.visiblePages(viewport.visibleDocRect(size));
                    _requestLoads(visible);
                    return Transform(
                      transform: viewport.matrix,
                      child: Stack(
                        children: [
                          // KEYED pages: without ValueKeys the Stack matches
                          // children BY INDEX, so when the visible window
                          // shifts (scroll), one page's tile STATE (with its
                          // rendered PDF image) jumps onto ANOTHER page —
                          // pages appeared to float/move/shuffle. Keys pin
                          // each page subtree to its stable page id.
                          for (final meta in visible)
                            _buildPage(context, meta),
                          // Doc-space overlays (keyed so their indices never
                          // fight the variable-length page list above):
                          KeyedSubtree(
                            key: const ValueKey('overlay-ruler'),
                            child: RulerOverlay(ruler: ruler, viewport: viewport),
                          ),
                          KeyedSubtree(
                            key: const ValueKey('overlay-lasso'),
                            child: _buildLassoOverlay(context),
                          ),
                          KeyedSubtree(
                            key: const ValueKey('overlay-selection'),
                            child: _buildSelectionHandles(context),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            // Screen-space overlays (OUTSIDE the Listener so taps on the
            // action bar never reach the canvas router).
            IgnorePointer(child: _buildEraserCursor(context)),
            // Floating per-tool settings panel (tapping the active tool in
            // the rail toggles it).
            _buildToolSettingsPanel(context),
            AnimatedBuilder(
              animation: viewport,
              builder: (context, _) => _buildSelectionBar(context),
            ),
          ],
        );
      },
    );
  }

  /// Floating tool-settings panel anchored at the rail edge of the canvas.
  /// Tap a rail tool → select + open; tap the ACTIVE tool again → close.
  Widget _buildToolSettingsPanel(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ToolController.I, SettingsController.I]),
      builder: (context, _) {
        if (_railHidden || !ToolController.I.settingsOpen) {
          return const SizedBox.shrink();
        }
        final isRtl = Directionality.of(context) == TextDirection.rtl;
        final leftHanded = SettingsController.I.settings.leftHanded;
        // The Row places the rail at the outer edge; in RTL the visual order
        // flips, so "rail on the right" ⇔ isRtl == leftHanded.
        final railAtRight = isRtl == leftHanded;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: Align(
            key: ValueKey('panel-${ToolController.I.tool.name}'),
            alignment: railAtRight ? Alignment.topRight : Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: ToolSettingsPanel(tools: ToolController.I),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPage(BuildContext context, PageMeta meta) {
    final engine = StrokeEngine.I;
    final index = engine.pages.indexOf(meta);
    final rect = geometry.pageRect(index);
    final ink = engine.pageInk(meta.id);
    final pdf = PdfDocumentController.I;
    final pdfOpen = pdf.isOpen && index >= 0 && index < pdf.pageCount;
    return Positioned.fromRect(
      // Stable key: the page subtree (PDF tile state, laser overlay) always
      // follows THIS page — never shuffled onto a neighbor on scroll.
      key: ValueKey('page-${meta.id}'),
      rect: rect,
      child: Stack(
        children: [
          if (pdfOpen)
            PdfPageTile(
              pdf: pdf,
              pageNumber: index + 1, // pdfx page numbers are 1-based
              scale: viewport.scale,
              viewport: viewport,
              pageSize: rect.size,
            ),
          CustomPaint(
            size: rect.size,
            painter: PageContentPainter(
              template: TemplateIdX.fromId(meta.template),
              paperColor: paperColorFrom(meta.paperColor),
              pageSize: rect.size,
              ink: ink,
              replayAt: _replayAt(),
              // The PDF tile provides the visual paper when present.
              paintPaper: !pdfOpen,
            ),
          ),
          if (meta.id == _currentPageId)
            CustomPaint(
              size: rect.size,
              painter: LiveStrokePainter(repaint: engine.liveStroke),
            ),
          LaserOverlay(laser: ToolController.I.laser, pageId: meta.id),
        ],
      ),
    );
  }

  // ----------------------------------------------------- doc-space overlays

  /// Lasso preview: points are PAGE-space of the page the lasso started on.
  /// Page rects are disjoint, so adding each page's origin to the first
  /// point and testing containment finds the owning page unambiguously.
  Widget _buildLassoOverlay(BuildContext context) {
    final engine = StrokeEngine.I;
    return ValueListenableBuilder<List<Offset>>(
      valueListenable: engine.lassoPreview,
      builder: (context, pts, _) {
        if (pts.isEmpty) return const SizedBox.shrink();
        final pageId = _pageIdForPageSpacePoint(pts.first);
        if (pageId == null) return const SizedBox.shrink();
        final idx = engine.pages.indexWhere((p) => p.id == pageId);
        if (idx < 0) return const SizedBox.shrink();
        final rect = geometry.pageRect(idx);
        return Positioned.fromRect(
          rect: rect,
          child: CustomPaint(
            size: rect.size,
            painter: _LassoPainter(
              points: pts,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      },
    );
  }

  int? _pageIdForPageSpacePoint(Offset pagePoint) {
    final engine = StrokeEngine.I;
    for (var i = 0; i < engine.pages.length; i++) {
      final doc = pagePoint + geometry.pageOrigin(engine.pages[i].id);
      if (geometry.pageRect(i).contains(doc)) return engine.pages[i].id;
    }
    return null;
  }

  /// Selection handles + dashed bbox, drawn in PAGE space of the page owning
  /// the current selection.
  Widget _buildSelectionHandles(BuildContext context) {
    final engine = StrokeEngine.I;
    return ListenableBuilder(
      listenable: engine.selectionChanged,
      builder: (context, _) {
        if (!engine.hasSelection) return const SizedBox.shrink();
        final pageId = engine.selectionPageId;
        if (pageId == null) return const SizedBox.shrink();
        final idx = engine.pages.indexWhere((p) => p.id == pageId);
        if (idx < 0) return const SizedBox.shrink();
        final rect = geometry.pageRect(idx);
        final scheme = Theme.of(context).colorScheme;
        return Positioned.fromRect(
          rect: rect,
          child: CustomPaint(
            size: rect.size,
            painter: _SelectionHandlesPainter(
              engine: engine,
              primary: scheme.primary,
              surface: scheme.surface,
            ),
          ),
        );
      },
    );
  }

  // --------------------------------------------------- screen-space overlays

  Widget _buildEraserCursor(BuildContext context) {
    final engine = StrokeEngine.I;
    final error = Theme.of(context).colorScheme.error;
    return ValueListenableBuilder<EraserCursor?>(
      valueListenable: engine.eraserCursor,
      builder: (context, cur, _) {
        if (cur == null) return const SizedBox.shrink();
        return Positioned(
          left: cur.screenPos.dx - cur.radius,
          top: cur.screenPos.dy - cur.radius,
          child: Container(
            width: cur.radius * 2,
            height: cur.radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: error.withValues(alpha: 0.08),
              border: Border.all(color: error.withValues(alpha: 0.7), width: 1.5),
            ),
          ),
        );
      },
    );
  }

  /// Floating selection action bar above the selection bbox (screen space).
  Widget _buildSelectionBar(BuildContext context) {
    final engine = StrokeEngine.I;
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: engine.selectionChanged,
      builder: (context, _) {
        if (!engine.hasSelection) return const SizedBox.shrink();
        final pageId = engine.selectionPageId;
        final box = engine.selectionBBox();
        if (pageId == null || box == null) return const SizedBox.shrink();
        final origin = geometry.pageOrigin(pageId);
        final topLeftScreen = viewport.toScreen(box.topLeft + origin);
        final bottomScreen = viewport.toScreen(
          Offset(box.right, box.bottom) + origin,
        );
        var top = topLeftScreen.dy - 60;
        if (top < 8) top = bottomScreen.dy + 12;
        top = top.clamp(8.0, math.max(8.0, _screenSize.height - 72)).toDouble();
        final left = (topLeftScreen.dx - 24)
            .clamp(8.0, math.max(8.0, _screenSize.width - 120)).toDouble();
        return Positioned(
          left: left,
          top: top,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(NANOTE_RADIUS),
            color: scheme.surface,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _barBtn(Icons.delete_outline, 'deleteSelection',
                      engine.deleteSelection),
                  _barBtn(Icons.content_copy, 'duplicateSelection',
                      engine.duplicateSelection),
                  _barBtn(Icons.copy, 'copySelection', engine.copySelection),
                  _barBtn(Icons.content_paste, 'pasteSelection',
                      engine.hasClipboard ? _pasteHere : null),
                  _barBtn(Icons.flip_to_front, 'bringFront',
                      engine.bringSelectionToFront),
                  _barBtn(Icons.flip_to_back, 'sendBack',
                      engine.sendSelectionToBack),
                  _barBtn(Icons.call_merge, 'group', engine.groupSelection),
                  _barBtn(Icons.call_split, 'ungroup', engine.ungroupSelection),
                  if (_selectedTextElement(engine, pageId) != null)
                    _barBtn(Icons.translate, 'translate', () {
                      final el = _selectedTextElement(engine, pageId);
                      if (el != null && el.text.trim().isNotEmpty) {
                        unawaited(showTranslatePopup(context, el.text));
                      }
                    }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// First selected TextEl (drives the translate action in the bar).
  TextEl? _selectedTextElement(StrokeEngine engine, int pageId) {
    final ink = engine.pageInkOrNull(pageId);
    if (ink == null) return null;
    for (final el in ink.elements) {
      if (el is TextEl && engine.selectedElementIds.contains(el.id)) {
        return el;
      }
    }
    return null;
  }

  Widget _barBtn(IconData icon, String label, VoidCallback? onTap) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: S.t(label),
      onPressed: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Private painters
// ---------------------------------------------------------------------------

/// Dashed selection bbox + corner/rotate handle circles (page space).
class _SelectionHandlesPainter extends CustomPainter {
  _SelectionHandlesPainter({
    required this.engine,
    required this.primary,
    required this.surface,
  }) : super(repaint: engine.selectionChanged);

  final StrokeEngine engine;
  final Color primary;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final box = engine.selectionBBox();
    if (box == null) return;
    final edge = Paint()
      ..color = primary
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    _dashRect(canvas, box, edge);

    final fill = Paint()..color = surface;
    final ring = Paint()
      ..color = primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final p in engine.selectionHandlesPage().values) {
      canvas.drawCircle(p, 8, fill);
      canvas.drawCircle(p, 8, ring);
    }
  }

  void _dashRect(Canvas canvas, Rect r, Paint paint) {
    final corners = <Offset>[
      r.topLeft,
      r.topRight,
      r.bottomRight,
      r.bottomLeft,
      r.topLeft,
    ];
    for (var i = 0; i < 4; i++) {
      final a = corners[i];
      final b = corners[i + 1];
      final len = (b - a).distance;
      if (len <= 0) continue;
      final dir = (b - a) / len;
      var t = 0.0;
      while (t < len) {
        final end = math.min(t + 6, len);
        canvas.drawLine(a + dir * t, a + dir * end, paint);
        t = end + 4;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SelectionHandlesPainter oldDelegate) => true;
}

/// Lasso polyline preview (page space).
class _LassoPainter extends CustomPainter {
  _LassoPainter({required this.points, required this.color});

  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LassoPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
