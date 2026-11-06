import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_lucide/flutter_lucide.dart';

import '../controllers/audio_controller.dart';
import '../controllers/pdf_document_controller.dart';
import '../controllers/settings_controller.dart';
import '../controllers/stroke_engine.dart';
import '../controllers/tool_controller.dart';
import '../controllers/viewport_controller.dart';
import '../i18n/strings.dart';
import '../models/page_elements.dart';
import '../models/paper.dart';
import '../models/tool.dart';
import '../persistence/file_store.dart';
import '../services/export_service.dart';
import '../services/image_cache.dart';
import '../services/translate_service.dart';
import '../theme/nanote_theme.dart';
import '../ui/panels/audio_panel.dart' show showAudioPanel;
import '../ui/panels/pages_sheet.dart' show showPagesSheet;
import '../ui/panels/sticker_picker.dart' show showStickerPicker;
import '../ui/panels/text_sheet.dart' show showTextSheet;
import '../ui/panels/translate_popup.dart' show showTranslatePopup;
import 'doc_geometry.dart';
import 'elements_painter.dart';
import 'gesture_router.dart';
import 'ink_painter.dart';
import 'laser_overlay.dart';
import 'paper_painter.dart';
import 'pdf_page_tile.dart';
import 'pdf_text_layer.dart';
import 'ruler_overlay.dart';
import 'tool_rail.dart';
import 'tool_settings_panel.dart';

/// The full editor screen: header (back, title, undo/redo, zoom %, export
/// menu, audio, pages manager, settings), body (transformed canvas stack |
/// tool rail), overlays (selection bar, laser, ruler, lasso, eraser circle),
/// autosave and gesture-router wiring.
class DocumentWorkspace extends StatefulWidget {
  const DocumentWorkspace({super.key, required this.notebookId});

  final int notebookId;

  @override
  State<DocumentWorkspace> createState() => _DocumentWorkspaceState();
}

class _DocumentWorkspaceState extends State<DocumentWorkspace> {
  late final ViewportController viewport;
  late final DocGeometry geometry;
  late final RulerState ruler;
  late final GestureRouter router;
  late final Listenable _canvasRepaint;
  late final PdfTextSelectionController textSel;

  Timer? _autosave;
  int _lastAutosaveMs = -1;

  int? _currentPageId;
  bool _railHidden = false;
  bool _didInitialFit = false;

  /// After the initial fit, re-fit once when the first PDF page aspect lands
  // (PDF notebooks start with a paper-size guess that gets corrected).
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
    textSel = PdfTextSelectionController();
    router = GestureRouter(
      viewport: viewport,
      engine: engine,
      tools: ToolController.I,
      settings: SettingsController.I,
      audio: AudioController.I,
      geometry: geometry,
      textSel: textSel,
      ruler: ruler,
      onToggleToolbar: () => setState(() => _railHidden = !_railHidden),
      onQuickExport: _quickExport,
      onTextTap: _onTextTap,
      onTextSelectTap: _onTextSelectTap,
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
    // PDF text layer: complete pending long-press picks the moment the
    // background extraction lands.
    PdfTextService.I.addListener(_onPdfTextReady);

    unawaited(_open());
  }

  void _onPdfTextReady() {
    router.completePendingTextPick();
  }

  Future<void> _open() async {
    final engine = StrokeEngine.I;
    await engine.openNotebook(widget.notebookId);
    if (!mounted) return;
    final pdfPath = engine.notebook?.pdfPath;
    if (pdfPath != null) {
      final f = await FileStore.tryResolve(pdfPath);
      if (f != null) {
        final ok = await PdfDocumentController.I.open(f.path);
        // SELF-HEAL: a PDF notebook must own one page per PDF page. Older
        // notebooks (single-page import era) show only page 1 otherwise.
        if (ok) {
          await engine.syncPagesToPdfCount(PdfDocumentController.I.pageCount);
          // Background text extraction for long-press text selection —
          // v2.6.0: DELAYED by a beat. The isolate copies the whole PDF
          // and parses every page, competing with the first page RENDERS
          // for memory on low-RAM devices (the "only page 1 renders" OOM
          // driver). The visible page renders first; the text layer lands
          // right after.
          Future<void>.delayed(const Duration(seconds: 2), () {
            if (PdfDocumentController.I.currentPath == f.path) {
              unawaited(PdfTextService.I.load(f.path));
            }
          });
        }
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
  /// (which notifies listeners) is deferred to a post-frame callback so
  /// nothing is ever notified during the build phase. Pending applications
  /// accumulate in [_pendingPdfSizes] — nothing is ever DROPPED when a
  /// callback is already scheduled (a dropped aspect left stale geometry on
  /// the pages below while scrolling).
  bool _pdfSizesScheduled = false;
  final List<(PageMeta, Size)> _pendingPdfSizes = [];

  void _applyPdfSizes() {
    final pdf = PdfDocumentController.I;
    final engine = StrokeEngine.I;
    if (!pdf.isOpen || engine.pages.isEmpty) return;
    final count = pdf.pageCount;
    for (var i = 0; i < engine.pages.length; i++) {
      final meta = engine.pages[i];
      if (meta.pdfSize != null) continue;
      if (i >= count) break; // beyond the PDF → keep paper size
      final ps = pdf.pageSize(i + 1); // 1-based; null → async resolve kicked
      if (ps == null || ps.width <= 0 || ps.height <= 0) continue;
      final base = meta.sizeDef.size;
      final size = Size(base.width, base.width * ps.height / ps.width);
      // Dedupe against what is already pending.
      final already = _pendingPdfSizes.any(
        (e) => e.$1.id == meta.id,
      );
      if (!already) _pendingPdfSizes.add((meta, size));
    }
    if (_pendingPdfSizes.isEmpty || _pdfSizesScheduled) return;
    _pdfSizesScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pdfSizesScheduled = false;
      if (!mounted || _pendingPdfSizes.isEmpty) return;
      final batch = List.of(_pendingPdfSizes);
      _pendingPdfSizes.clear();
      var refit = _refitOnAspect;
      for (final (meta, size) in batch) {
        if (meta.pdfSize != null) continue;
        StrokeEngine.I.applyPdfPageSize(meta.id, size);
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
    PdfTextService.I.removeListener(_onPdfTextReady);
    StrokeEngine.I.recordingClock = null;
    router.dispose();
    textSel.dispose();
    PdfTextService.I.clear();
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
      // Select it (contract: insert + select) and hand over to the LASSO
      // (§9: insert → auto-select → lasso) so the user can immediately
      // move/resize the image with pen OR finger — the image tool's next
      // tap inserts another image.
      engine.selectElements(pageId, [el.id]);
      ToolController.I.tool = Tool.lasso;
      ToolController.I.closeSettings();
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

  /// §7 text-select tool: tapping a text element opens the translation
  /// popup directly (no lasso needed). Tapping empty space does nothing.
  void _onTextSelectTap(int pageId, Offset pagePoint) {
    final engine = StrokeEngine.I;
    final el = engine.elementAt(pageId, pagePoint);
    if (el is TextEl && el.text.trim().isNotEmpty) {
      // Visually select it so the user sees WHAT is being translated.
      engine.selectElements(pageId, [el.id]);
      unawaited(showTranslatePopup(context, el.text));
    }
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
        builder: (context, _) => _buildEditorBody(context, engine),
      ),
    );
  }

  /// Editor body: the canvas fills the screen; the FIXED tool rail floats
  /// above it. Position comes from settings.railPosition ONLY (never
  /// dragged): start/end → vertical capsule centered on that edge;
  /// top/bottom → horizontal capsule. leftHanded mirrors the vertical
  /// side (§0).
  Widget _buildEditorBody(BuildContext context, StrokeEngine engine) {
    final settings = SettingsController.I.settings;
    final dock = resolveRailDock(settings.railPosition, settings.leftHanded);
    final rail = ToolRail(
      tools: ToolController.I,
      engine: engine,
      ruler: ruler,
      dock: dock,
      hidden: _railHidden,
      onCollapse: () => setState(() => _railHidden = true),
      onToggleFinger: _onToggleFingerDraw,
      onMicTap: () => unawaited(showAudioPanel(context, engine)),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // The canvas (full-bleed; the rail floats above it).
        Positioned.fill(child: _buildCanvasArea(context)),
        // The fixed rail, docked per settings.
        _railHidden
            ? _railReturnHandle(context, dock)
            : Align(
                alignment: switch (dock) {
                  RailDock.top => Alignment.topCenter,
                  RailDock.bottom => Alignment.bottomCenter,
                  RailDock.start => AlignmentDirectional.centerStart,
                  RailDock.end => AlignmentDirectional.centerEnd,
                },
                child: SafeArea(
                  minimum: const EdgeInsets.all(10),
                  child: rail,
                ),
              ),
      ],
    );
  }

  /// §12 finger-drawing toggle with the required toast feedback.
  void _onToggleFingerDraw(bool v) {
    SettingsController.I.setDrawWithFinger(v);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(S.t(v ? 'fingerWriteOn' : 'fingerWriteOff')),
        ),
      );
  }

  /// §0: while the rail is folded, a floating rounded 10×14px pill handle
  /// sits on the same docked edge — one tap brings the rail back.
  Widget _railReturnHandle(BuildContext context, RailDock dock) {
    final scheme = Theme.of(context).colorScheme;
    final colors = nanoteColors(context);
    final vertical = dock.isVertical;
    // Visible pill: 10×14 on a vertical edge, 14×10 on a horizontal one
    // (§0). Wrapped in a 44×44 invisible tap target.
    final handle = Tooltip(
      message: S.t('showToolbar'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _railHidden = false),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: vertical ? 10 : 14,
              height: vertical ? 14 : 10,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(999),
                boxShadow: colors.inkShadow2,
              ),
            ),
          ),
        ),
      ),
    );
    return Align(
      alignment: switch (dock) {
        RailDock.top => Alignment.topCenter,
        RailDock.bottom => Alignment.bottomCenter,
        RailDock.start => AlignmentDirectional.centerStart,
        RailDock.end => AlignmentDirectional.centerEnd,
      },
      child: SafeArea(
        minimum: const EdgeInsets.all(10),
        child: handle,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, StrokeEngine engine) {
    final title = (engine.notebook?.title ?? '').trim();
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return AppBar(
      toolbarHeight: 56,
      leading: IconButton(
        icon: Icon(isRtl ? LucideIcons.arrow_right : LucideIcons.arrow_left,
            size: 22),
        tooltip: S.t('close'),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        title.isEmpty ? S.t('editor') : title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        // Spec top bar: back • title • undo/redo • export. Undo/redo LIVE
        // in the header on every screen size (the §0 rail no longer carries
        // them — its 14 slots are the fixed tool/toggle set).
        ListenableBuilder(
          listenable: engine.historyChanged,
          builder: (context, _) => Row(
            children: [
              IconButton(
                icon: const Icon(LucideIcons.undo, size: 20),
                tooltip: S.t('undo'),
                onPressed: engine.canUndo ? engine.undo : null,
              ),
              IconButton(
                icon: const Icon(LucideIcons.redo, size: 20),
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
          icon: const Icon(LucideIcons.share, size: 20),
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
          icon: const Icon(LucideIcons.mic, size: 20),
          tooltip: S.t('audio'),
          onPressed: () => unawaited(showAudioPanel(context, engine)),
        ),
        IconButton(
          icon: const Icon(LucideIcons.layers, size: 20),
          tooltip: S.t('pages'),
          onPressed: () => unawaited(showPagesSheet(
            context,
            engine,
            onJump: _jumpToPage,
            currentId: _currentMeta?.id,
          )),
        ),
        IconButton(
          icon: const Icon(LucideIcons.settings, size: 20),
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
                    // Refresh the pan bounds on EVERY repaint (page adds,
                    // PDF aspect changes, deletions) — the LayoutBuilder
                    // above only re-runs on parent rebuilds, so a stale
                    // bounds previously LOCKED scrolling after the page
                    // list changed.
                    viewport.panBounds = geometry.tightBounds;
                    viewport.clampToDoc();
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
                            key: const ValueKey('overlay-shape-preview'),
                            child: _buildShapePreviewOverlay(context),
                          ),
                          KeyedSubtree(
                            key: const ValueKey('overlay-lasso'),
                            child: _buildLassoOverlay(context),
                          ),
                          KeyedSubtree(
                            key: const ValueKey('overlay-selection'),
                            child: _buildSelectionHandles(context),
                          ),
                          KeyedSubtree(
                            key: const ValueKey('overlay-pdf-text-selection'),
                            child: _buildPdfTextSelectionOverlay(context),
                          ),
                          KeyedSubtree(
                            key: const ValueKey('overlay-crop'),
                            child: _buildCropOverlay(context),
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
              builder: (context, _) => ValueListenableBuilder<CropSession?>(
                valueListenable: router.cropSession,
                builder: (context, crop, _) => crop == null
                    ? _buildSelectionBar(context)
                    : const SizedBox.shrink(),
              ),
            ),
            AnimatedBuilder(
              animation: viewport,
              builder: (context, _) => ValueListenableBuilder<CropSession?>(
                valueListenable: router.cropSession,
                builder: (context, crop, _) => crop == null
                    ? _buildPdfTextBar(context)
                    : const SizedBox.shrink(),
              ),
            ),
            _buildCropBar(context),
          ],
        );
      },
    );
  }

  /// Floating tool-settings panel, CLAMPED to the screen (§0): the panel
  /// never overflows the viewport — its width/height adapt via a
  /// LayoutBuilder, it scrolls internally and stays beside/away from the
  /// docked rail. Tap a rail tool → select + open; tap the ACTIVE tool
  /// again → close.
  Widget _buildToolSettingsPanel(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ToolController.I, SettingsController.I]),
      builder: (context, _) {
        if (_railHidden || !ToolController.I.settingsOpen) {
          return const SizedBox.shrink();
        }
        final settings = SettingsController.I.settings;
        final dock =
            resolveRailDock(settings.railPosition, settings.leftHanded);
        return LayoutBuilder(
          builder: (context, constraints) {
            final screen = constraints.biggest;
            // Reserve the rail's footprint on its edge (vertical rail is
            // 56px wide + 10px margin; horizontal is 56px tall + 10px).
            final double availW;
            final double availH;
            final EdgeInsetsGeometry padding;
            final AlignmentGeometry alignment;
            switch (dock) {
              case RailDock.top:
                availW = screen.width - 24;
                availH = screen.height - 80; // app-bar-less body: top rail + pad
                alignment = Alignment.topCenter;
                padding = const EdgeInsets.only(top: 72);
              case RailDock.bottom:
                availW = screen.width - 24;
                availH = screen.height - 80;
                alignment = Alignment.bottomCenter;
                padding = const EdgeInsets.only(bottom: 76);
              case RailDock.start:
                availW = screen.width - 24 - 66; // rail column + margins
                availH = screen.height - 24;
                alignment = AlignmentDirectional.topStart;
                padding = const EdgeInsetsDirectional.fromSTEB(66, 12, 12, 12);
              case RailDock.end:
                availW = screen.width - 24 - 66;
                availH = screen.height - 24;
                alignment = AlignmentDirectional.topEnd;
                padding = const EdgeInsetsDirectional.fromSTEB(12, 12, 66, 12);
            }
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: Align(
                key: ValueKey('panel-${ToolController.I.tool.name}'),
                alignment: alignment,
                child: Padding(
                  padding: padding,
                  child: ToolSettingsPanel(
                    tools: ToolController.I,
                    maxWidth: availW.clamp(180.0, 300.0),
                    maxHeight: availH.clamp(160.0, 520.0),
                    onClearPage: () {
                      final meta = _currentMeta;
                      if (meta == null) return;
                      StrokeEngine.I.clearPage(meta.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(
                            content: Text(S.t('pageCleared')),
                          ));
                      }
                    },
                  ),
                ),
              ),
            );
          },
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
          // PDF ROOT-CAUSE FIX (pages showed blank while the thumbnails
          // rendered fine): a Flutter Stack paints LATER children ON TOP,
          // and the old order (PDF tile FIRST, then the content painter
          // with an OPAQUE paper fill) buried the rendered PDF under the
          // paper. The correct layering — the very one the thumbnails use:
          //   1. opaque paper fill (bottom): a pending/failed render still
          //      looks like white paper, never a dark void;
          //   2. the PDF tile: covers the fill once its render lands;
          //   3. template lines + ink + elements (top) with the paper fill
          //      SKIPPED (paintPaper: false) so the PDF shows through.
          if (pdfOpen)
            CustomPaint(
              size: rect.size,
              painter: PaperPainter(
                template: TemplateId.blank,
                paperColor: paperColorFrom(meta.paperColor),
                size: rect.size,
                paintBackground: true,
              ),
            ),
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
              // Paper fill only for NON-PDF pages — the dedicated fill
              // under the tile already covers the pending-render void.
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
              pad: StrokeEngine.I.padOffsetOf(pageId),
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
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<EraserCursor?>(
      valueListenable: engine.eraserCursor,
      builder: (context, cur, _) {
        if (cur == null) return const SizedBox.shrink();
        // ERASER-CURSOR FIX (the REAL flicker root cause): the old code
        // returned a `Positioned` nested inside IgnorePointer — a
        // ParentDataWidget under a RenderObjectWidget parent, so the
        // position was NEVER applied: the pale circle rendered stuck at
        // the top-start corner, appearing/vanishing with every tap =
        // "pale screen flash". Rebuilt with Align + Transform.translate
        // (depth-safe) AND as a thin ring only (no large translucent
        // fill), isolated in a RepaintBoundary.
        return Align(
          alignment: AlignmentDirectional.topStart,
          widthFactor: 1,
          heightFactor: 1,
          child: Transform.translate(
            offset: cur.screenPos - Offset(cur.radius, cur.radius),
            child: RepaintBoundary(
              child: Container(
                width: cur.radius * 2,
                height: cur.radius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.85),
                    width: 1.6,
                  ),
                ),
                child: cur.radius >= 18
                    ? Center(
                        child: Icon(
                          LucideIcons.eraser,
                          size: math.min(cur.radius * 0.7, 18),
                          color: scheme.primary.withValues(alpha: 0.75),
                        ),
                      )
                    : null,
              ),
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
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: scheme.outline),
              boxShadow: nanoteColors(context).inkShadow2,
            ),
            child: Material(
              elevation: 0,
              borderRadius: BorderRadius.circular(999),
              color: scheme.surface,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _barBtn(LucideIcons.trash, 'deleteSelection',
                        engine.deleteSelection),
                    _barBtn(LucideIcons.copy_plus, 'duplicateSelection',
                        engine.duplicateSelection),
                    _barBtn(LucideIcons.copy, 'copySelection',
                        engine.copySelection),
                    _barBtn(LucideIcons.clipboard_paste, 'pasteSelection',
                        engine.hasClipboard ? _pasteHere : null),
                    _barBtn(LucideIcons.bring_to_front, 'bringFront',
                        engine.bringSelectionToFront),
                    _barBtn(LucideIcons.send_to_back, 'sendBack',
                        engine.sendSelectionToBack),
                    _barBtn(LucideIcons.combine, 'group',
                        engine.groupSelection),
                    _barBtn(LucideIcons.split, 'ungroup',
                        engine.ungroupSelection),
                    if (_selectedTextElement(engine, pageId) != null)
                      _barBtn(LucideIcons.languages, 'translate', () {
                        final el = _selectedTextElement(engine, pageId);
                        if (el != null && el.text.trim().isNotEmpty) {
                          unawaited(showTranslatePopup(context, el.text));
                        }
                      }),
                    // §5 image actions (single selected user image): rotate,
                    // flip, crop — previously only stroke-agnostic buttons
                    // existed and NOTHING could transform an image.
                    if (_selectedImageElement(engine, pageId) != null) ...[
                      _barBtn(LucideIcons.rotate_ccw, 'rotateLeft', () {
                        final el = _selectedImageElement(engine, pageId);
                        if (el != null) _rotateImage(el, pageId, -1);
                      }),
                      _barBtn(LucideIcons.rotate_cw, 'rotateRight', () {
                        final el = _selectedImageElement(engine, pageId);
                        if (el != null) _rotateImage(el, pageId, 1);
                      }),
                      _barBtn(LucideIcons.arrow_left_right, 'flipH', () {
                        final el = _selectedImageElement(engine, pageId);
                        if (el != null) _flipImage(el, pageId, true);
                      }),
                      _barBtn(LucideIcons.arrow_up_down, 'flipV', () {
                        final el = _selectedImageElement(engine, pageId);
                        if (el != null) _flipImage(el, pageId, false);
                      }),
                      _barBtn(LucideIcons.crop, 'crop', () {
                        final el = _selectedImageElement(engine, pageId);
                        if (el != null) router.beginCrop(pageId, el);
                      }),
                    ],
                  ],
                ),
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

  /// The single selected user IMAGE (drives the §5 image actions).
  ImageEl? _selectedImageElement(StrokeEngine engine, int pageId) {
    if (engine.selectedElementIds.length != 1 ||
        engine.selectedStrokeIds.isNotEmpty) {
      return null;
    }
    final ink = engine.pageInkOrNull(pageId);
    if (ink == null) return null;
    for (final el in ink.elements) {
      if (el is ImageEl &&
          engine.selectedElementIds.contains(el.id) &&
          el.src != null) {
        return el;
      }
    }
    return null;
  }

  /// Rotates the image by [quarterTurns] × 90° around its center (undoable).
  void _rotateImage(ImageEl el, int pageId, int quarterTurns) {
    final updated = el.deepCopy();
    final c = updated.center;
    updated.rotation += quarterTurns * math.pi / 2;
    // Keep the visual center: swap w/h with the new rotation.
    updated.x = c.dx - updated.h / 2;
    updated.y = c.dy - updated.w / 2;
    final w = updated.w;
    updated.w = updated.h;
    updated.h = w;
    StrokeEngine.I.updateElement(pageId, updated);
  }

  /// Mirrors the image horizontally / vertically (undoable).
  void _flipImage(ImageEl el, int pageId, bool horizontal) {
    final updated = el.deepCopy();
    if (horizontal) {
      updated.flipH = !updated.flipH;
    } else {
      updated.flipV = !updated.flipV;
    }
    StrokeEngine.I.updateElement(pageId, updated);
  }

  /// Live §8 shape-drag preview: paints the element being dragged out on
  /// its page (page-local coords).
  Widget _buildShapePreviewOverlay(BuildContext context) {
    return ValueListenableBuilder<ShapeDragPreview?>(
      valueListenable: router.shapePreview,
      builder: (context, pv, _) {
        if (pv == null) return const SizedBox.shrink();
        final idx = StrokeEngine.I.pages.indexWhere((p) => p.id == pv.pageId);
        if (idx < 0) return const SizedBox.shrink();
        final rect = geometry.pageRect(idx);
        return Positioned.fromRect(
          rect: rect,
          child: CustomPaint(
            size: rect.size,
            painter: _ShapePreviewPainter(preview: pv),
          ),
        );
      },
    );
  }

  /// §5 crop editor overlay: dims everything outside the crop window,
  /// draws the window (rotated with the image) + rule-of-thirds + corner
  /// handles.
  Widget _buildCropOverlay(BuildContext context) {
    return ValueListenableBuilder<CropSession?>(
      valueListenable: router.cropSession,
      builder: (context, s, _) {
        if (s == null) return const SizedBox.shrink();
        final idx = StrokeEngine.I.pages.indexWhere((p) => p.id == s.pageId);
        if (idx < 0) return const SizedBox.shrink();
        final rect = geometry.pageRect(idx);
        return Positioned.fromRect(
          rect: rect,
          child: CustomPaint(
            size: rect.size,
            painter: _CropOverlayPainter(
              session: s,
              primary: Theme.of(context).colorScheme.primary,
              pad: StrokeEngine.I.padOffsetOf(s.pageId),
            ),
          ),
        );
      },
    );
  }

  /// §5 crop action bar (screen space, bottom-center): cancel / reset /
  /// confirm. Modal — the canvas router feeds the crop session while open.
  Widget _buildCropBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = nanoteColors(context);
    return ValueListenableBuilder<CropSession?>(
      valueListenable: router.cropSession,
      builder: (context, s, _) {
        if (s == null) return const SizedBox.shrink();
        return Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: scheme.outline),
                boxShadow: colors.inkShadow2,
              ),
              child: Material(
                elevation: 0,
                borderRadius: BorderRadius.circular(999),
                color: scheme.surface,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 20),
                      tooltip: S.t('cancel'),
                      onPressed: router.cancelCrop,
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.maximize, size: 20),
                      tooltip: S.t('reset'),
                      onPressed: s.reset,
                    ),
                    IconButton(
                      icon: Icon(LucideIcons.check,
                          size: 20, color: scheme.primary),
                      tooltip: S.t('confirm'),
                      onPressed: router.commitCrop,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// PDF text-selection rectangles + handles (page space of the owning
  /// page — the same doc-space overlay pattern as the ink selection).
  Widget _buildPdfTextSelectionOverlay(BuildContext context) {
    final engine = StrokeEngine.I;
    return ListenableBuilder(
      listenable: Listenable.merge([textSel, PdfTextService.I]),
      builder: (context, _) {
        if (!textSel.hasSelection) return const SizedBox.shrink();
        final pageId = textSel.pageId;
        if (pageId == null) return const SizedBox.shrink();
        final idx = engine.pages.indexWhere((p) => p.id == pageId);
        if (idx < 0) return const SizedBox.shrink();
        final rect = geometry.pageRect(idx);
        final scheme = Theme.of(context).colorScheme;
        return Positioned.fromRect(
          rect: rect,
          child: CustomPaint(
            size: rect.size,
            painter: PdfSelectionPainter(
              sel: textSel,
              primary: scheme.primary,
              surface: scheme.surface,
            ),
          ),
        );
      },
    );
  }

  /// Floating PDF text-selection action bar (screen space, above the
  /// selection): Copy · Translate · Search the web · Highlight ·
  /// Underline · Select text · Select all · Ask <AI>.
  Widget _buildPdfTextBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([textSel, PdfTextService.I]),
      builder: (context, _) {
        if (!textSel.hasSelection || !textSel.menuVisible) {
          return const SizedBox.shrink();
        }
        final pageId = textSel.pageId;
        final box = textSel.selectionBBoxPage();
        if (pageId == null || box == null) return const SizedBox.shrink();
        final origin = geometry.pageOrigin(pageId);
        final topLeftScreen = viewport.toScreen(box.topLeft + origin);
        final bottomScreen =
            viewport.toScreen(Offset(box.right, box.bottom) + origin);
        var top = topLeftScreen.dy - 60;
        if (top < 8) top = bottomScreen.dy + 12;
        top = top
            .clamp(8.0, math.max(8.0, _screenSize.height - 72))
            .toDouble();
        final left = (topLeftScreen.dx - 24)
            .clamp(8.0, math.max(8.0, _screenSize.width - 120))
            .toDouble();
        return Positioned(
          left: left,
          top: top,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: scheme.outline),
              boxShadow: nanoteColors(context).inkShadow2,
            ),
            child: Material(
              elevation: 0,
              borderRadius: BorderRadius.circular(999),
              color: scheme.surface,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _barBtn(LucideIcons.copy, 'copy', () {
                      _copyPdfSelection();
                    }),
                    _barBtn(LucideIcons.languages, 'translate', () {
                      final text = textSel.selectedText();
                      textSel.clear();
                      if (text.trim().isNotEmpty) {
                        unawaited(showTranslatePopup(context, text));
                      }
                    }),
                    _barBtn(LucideIcons.globe, 'searchWeb', () {
                      final text = textSel.selectedText();
                      textSel.clear();
                      if (text.trim().isNotEmpty) {
                        unawaited(TranslateService.openWebSearch(text));
                      }
                    }),
                    _barBtn(LucideIcons.highlighter, 'highlightText', () {
                      _annotatePdfSelection(highlight: true);
                    }),
                    _barBtn(LucideIcons.underline, 'underlineText', () {
                      _annotatePdfSelection(highlight: false);
                    }),
                    _barBtn(LucideIcons.text_cursor_input, 'selectText', () {
                      // Keep the handles, hide the bar (tap inside the
                      // selection to bring it back).
                      textSel.hideMenu();
                    }),
                    _barBtn(LucideIcons.list_checks, 'selectAll', () {
                      textSel.selectAll();
                    }),
                    _barBtn(LucideIcons.sparkles, _askAiLabel(), () {
                      final text = textSel.selectedText();
                      textSel.clear();
                      if (text.trim().isNotEmpty) {
                        unawaited(TranslateService.askAi(context, text));
                      }
                    }),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _askAiLabel() {
    final service = SettingsController.I.settings.aiService;
    return switch (service) {
      'gemini' => 'askGemini',
      'claude' => 'askClaude',
      _ => 'askChatgpt',
    };
  }

  void _copyPdfSelection() {
    final text = textSel.selectedText();
    textSel.clear();
    if (text.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(S.t('copiedToClipboard'))),
      );
  }

  /// Commits highlight / underline strokes over the selected text (ONE
  /// undoable op via the engine, new strokes only — existing annotations
  /// keep their own colors/opacity).
  void _annotatePdfSelection({required bool highlight}) {
    final pageId = textSel.pageId;
    if (pageId == null) return;
    final strokes = highlight
        ? textSel.buildHighlightStrokes()
        : textSel.buildUnderlineStrokes();
    if (strokes.isEmpty) return;
    StrokeEngine.I.commitStrokes(pageId, strokes);
    textSel.clear();
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
    // §2 selection bounds are page-local — translate onto the grown paper.
    final pad = StrokeEngine.I.padOffsetOf(engine.selectionPageId ?? -1);
    canvas.translate(pad.dx, pad.dy);
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
  _LassoPainter({required this.points, required this.color, this.pad = Offset.zero});

  final List<Offset> points;
  final Color color;

  /// §2 pad offset of the owning page (page-local points may be negative).
  final Offset pad;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    canvas.translate(pad.dx, pad.dy);
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

/// Live §8 shape being dragged out (page space) — painted through the
/// shared element painter so the preview matches the committed look.
class _ShapePreviewPainter extends CustomPainter {
  _ShapePreviewPainter({required this.preview, this.pad = Offset.zero});

  final ShapeDragPreview preview;

  /// §2 pad offset of the owning page.
  final Offset pad;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(pad.dx, pad.dy);
    ElementsPainter.paintElement(canvas, preview.el);
  }

  @override
  bool shouldRepaint(covariant _ShapePreviewPainter oldDelegate) => true;
}

/// §5 crop editor: dim outside the window, window border + rule-of-thirds
/// + corner handles — all rotated with the image (page space).
class _CropOverlayPainter extends CustomPainter {
  _CropOverlayPainter({
    required this.session,
    required this.primary,
    this.pad = Offset.zero,
  });

  final CropSession session;
  final Color primary;

  /// §2 pad offset of the owning page.
  final Offset pad;

  @override
  void paint(Canvas canvas, Size size) {
    final el = session.el;
    final w = session.window;

    canvas.save();
    // Rotate into the element's frame so the window follows the image.
    final c = el.center;
    canvas.translate(c.dx, c.dy);
    canvas.rotate(el.rotation);
    canvas.translate(-c.dx, -c.dy);

    // Dim everything outside the crop window (even-odd fill).
    final dimPath = Path()
      ..addRect(Offset.zero & size)
      ..addRect(w)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dimPath, Paint()..color = const Color(0x8A0F172A));

    // Window border.
    canvas.drawRect(
      w,
      Paint()
        ..color = primary
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    // Rule-of-thirds guides.
    final third = Paint()
      ..color = primary.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = w.left + w.width * i / 3;
      canvas.drawLine(Offset(x, w.top), Offset(x, w.bottom), third);
      final y = w.top + w.height * i / 3;
      canvas.drawLine(Offset(w.left, y), Offset(w.right, y), third);
    }

    // Corner handles.
    final fill = Paint()..color = const Color(0xFFFFFFFF);
    final ring = Paint()
      ..color = primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final p in [w.topLeft, w.topRight, w.bottomRight, w.bottomLeft]) {
      canvas.drawCircle(p, 9, fill);
      canvas.drawCircle(p, 9, ring);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) => true;
}

