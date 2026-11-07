# Nanote Native — Implementation Contract

This document pins the **public API surface** every module must implement or
consume **EXACTLY**. Contract files that already exist on disk (models,
persistence, engine, viewport, settings controller, pen bus, gesture router)
are the source of truth — **read them before writing any code**.

## Ground rules for all modules

1. Do NOT modify any file outside your assigned file list.
2. Do NOT invent new public members on shared classes. If you need one, note
   it in your final report instead.
3. No placeholders, no TODOs, no unimplemented throws. Complete, compiling
   Dart.
4. All UI strings come from `S.t('key')` (`lib/src/i18n/strings.dart`). If a
   key you need does not exist, use the closest existing key and list the
   missing keys in your final report. NEVER edit strings.dart.
5. Colors/theme: use `Theme.of(context)` and `nanoteColors(context)`
   (extension with accent, accentFg, secondaryFg, mutedFg, success, warning).
   Radius 12 (`NANOTE_RADIUS`). Touch targets ≥44px.
6. Controllers are singletons: `StrokeEngine.I`, `SettingsController.I`,
   `ViewportController` (created per editor), plus (to be implemented)
   `ToolController.I`, `AudioController.I`, `PdfDocumentController.I`,
   `LaserController.I`, `LibraryController.I`.
7. Relative imports only (`import '../models/stroke.dart';`). Package imports
   for external packages.
8. All widget files that own controllers need `import
   'package:flutter/material.dart';` (or widgets/foundation as appropriate).

## Existing modules (read these files first — they are final)

- `lib/src/models/paper.dart` — TemplateId, PageSizeId, PAGE_SIZES,
  PageSizeDef/pageSizeDef()/pageSizeIdFrom(), GRID_PITCH, INK_PALETTE,
  HIGHLIGHTER_PALETTE, PAPER_COLORS, paperColorFrom, isDarkPaper,
  templateLineColor, ShapeType + ShapeTypeX (fromId, key, isPolylineLike),
  TextFontId + TextFontIdX (fromId, key, fontFamily), CoverDef,
  BUILTIN_COVERS, coverById.
- `lib/src/models/tool.dart` — Tool enum + isDrawingPen.
- `lib/src/models/stroke.dart` — StrokeKind, StrokeStyle (+forKind, toJson,
  fromJson, copyWith, flutterColor), PressureCurve, Stroke (pts flat stride 3:
  point(i), pressure(i), append, bbox, pathLength, outline, buildPath,
  distanceTo, transformed, deepCopy, toJson/fromJson, id, z, tStart, tEnd,
  groupId), StrokeIdGen.next().
- `lib/src/models/page_elements.dart` — sealed PageElement (id, z, bbox(),
  deepCopy, toJson); TextEl, ShapeEl, ImageEl; elementFromJson,
  elementToJson, translateElement, rotatePoint, ElementIdGen.next().
- `lib/src/models/settings.dart` — PenAction (21), PenButton (4), PenPattern
  (4), AppSettings (all fields + actionFor/setAction/toJson/fromJson).
- `lib/src/models/library_models.dart` — LibrarySection, SortKey, ViewMode,
  TRASH_RETENTION.
- `lib/src/theme/nanote_theme.dart` — NanoteTheme.light()/dark(),
  NanoteColors extension, nanoteColors(context), NANOTE_RADIUS.
- `lib/src/i18n/strings.dart` — S.t(key), S.lang (ValueNotifier<Lang>), S.num,
  S.pageOf(page, total), S.isAr, S.textDirection.
- `lib/src/persistence/app_db.dart` — AppDb.init()/db/isReady/wipeAll().
- `lib/src/persistence/library_repository.dart` — TabEntity, FolderEntity,
  NotebookEntity, PageEntity, TagEntity, RecordingEntity; LibraryRepository.I
  with CRUD (tabs(), createTab, folders(), createFolder, tags(), createTag,
  createNotebook, updateNotebook, touchNotebook, activeNotebooks,
  trashedNotebooks, notebook, setFavorite, moveToFolder, trashNotebook,
  restoreNotebook, purgeNotebook, emptyTrash, purgeExpiredTrash, pagesOf,
  page, addPage, updatePage, deletePage, reorderPages, pageCount,
  recordingsOf, addRecording, deleteRecording, dumpAll, restoreAll).
- `lib/src/persistence/stroke_repository.dart` — StrokeEntity, ElementEntity;
  StrokeRepository.I (loadStrokes, loadElements, savePage, deletePageInk,
  duplicatePageInk, dumpStrokes/restoreStrokes, dumpElements/restoreElements).
- `lib/src/persistence/settings_store.dart` — SettingsStore.I.load()/save().
- `lib/src/persistence/file_store.dart` — FileStore.base(),
  imagesDir()/pdfsDir()/recordingsDir()/stickersDir()/coversDir(),
  importFile(File, kind), newRecordingFile(), resolve(rel)/tryResolve(rel),
  deleteRelative(rel), listStickers(), listAllFiles().
- `lib/src/controllers/stroke_engine.dart` — **READ THE WHOLE FILE**. Exposes
  StrokeEngine.I, PageMeta, PageInk, EraserCursor, LiveStrokeNotifier
  (value/tick), SelHandle, all InkOps. Engine API:
  openNotebook/close/pageInk/pageInkOrNull/ensureLoaded/ensureAllLoaded/
  markDirty/flush, beginStroke/extendStroke/endStroke/cancelStroke,
  beginEraserGesture/eraseStrokeAt/eraseAreaAt/endEraserGesture,
  undo/redo/canUndo/canRedo + historyChanged, selectedStrokeIds/
  selectedElementIds/selectionPageId/hasSelection/clearSelection/
  selectInLasso/selectionBBox/selectionHandlesPage/hitSelectionHandle/
  selectionChanged, beginSelectionTransform/moveSelectionBy/scaleSelectionBy/
  rotateSelectionBy/endSelectionTransform/cancelSelectionTransform,
  deleteSelection/duplicateSelection/copySelection/cutSelection/pasteAt/
  hasClipboard/bringSelectionToFront/sendSelectionToBack/groupSelection/
  ungroupSelection, elementAt/addElement/updateElement/removeElement,
  replaceStrokeWithShape, pages/metaOf/addPage/duplicatePage/deletePage/
  reorderPage/setPageBookmark/setPageTitle + pagesChanged, liveStroke/
  eraserCursor/lassoPreview, invalidateAllOutlines, recordingClock (field:
  int Function()?).
- `lib/src/controllers/viewport_controller.dart` — ViewportController
  (scale/pan/matrix/toScreen/toDoc/visibleDocRect/setMatrix/panBy/zoomBy/
  zoomTo/centerDoc/fitRect/endInteraction/requestRender/renderTick,
  minScale/maxScale). NOTE: no zoomPercent getter — compute
  `(viewport.scale * 100).round()` yourself.
- `lib/src/controllers/settings_controller.dart` — SettingsController.I
  (settings, load, setThemeMode/setLang/setLeftHanded/setPressureCurve/
  setDrawWithFinger/setShapeDetection/setHighlighterOpacity/
  setAutosaveDelayMs/setPenAction/setPenShortcutsEnabled/setTranslateEngine/
  setTranslateTarget/setAiService/saveRaw).
- `lib/src/controllers/pen_bus.dart` — PenBus.I (notifier
  ValueNotifier<PenInfo?>, stats PenStats). PenInfo(kind, pressure, tiltX,
  tiltY, buttons, hover, lastSeen, reportRateHz).
- `lib/src/workspace/gesture_router.dart` — GestureRouter (final, do not
  change). Consumes: ToolController.I (tool, currentStrokeStyle(),
  eraserRadius, eraserMode, laser (LaserController), cycleColorNext,
  widthUp/widthDown), AudioController.I, DocGeometry, RulerState,
  ShapeRecognizer.recognize (static).

## Modules to be implemented (exact public APIs)

### controllers/tool_controller.dart (Agent C)

```dart
enum EraserMode { stroke, area }

class PenState {
  int color;      // 0xAARRGGBB
  double size;
  PenState({required this.color, required this.size});
  PenState copyWith({int? color, double? size});
}

class ToolController extends ChangeNotifier {
  static final ToolController I = ToolController._();

  Tool tool;                       // current tool (setter notifies)
  Map<StrokeKind, PenState> pens;  // remembered per pen
  PenState pen(StrokeKind kind);

  List<int> favoriteColors;        // up to 5 (ARGB ints)
  List<int> recentColors;          // most recent first, max 8

  EraserMode eraserMode;
  double eraserRadius;             // page-space radius; presets 12/28/48

  // Shape tool state
  ShapeType shapeType;
  int shapeStrokeColor;
  double shapeStrokeWidth;
  int? shapeFillColor;
  double shapeFillOpacity;
  bool shapeGridSnap;
  bool shapeAspectLock;
  int shapeSides;                  // polygon 3..12

  // Laser
  LaserController get laser;       // LaserController.I

  // Text defaults
  int textColor;
  double textSize;
  TextFontId textFont;
  bool textBold, textItalic, textUnderline;
  int textAlign;                   // 0/1/2

  StrokeStyle currentStrokeStyle();  // from tool + pen + settings
  void setPenColor(int color);
  void setPenSize(double size);
  void cycleColorNext();             // next palette color for current pen
  void widthUp();
  void widthDown();
  void addRecentColor(int color);
  void toggleFavoriteColor(int color);

  Future<void> load();               // from settings.penStates etc.
  Future<void> save();               // persists pen states + palettes
}
```

`currentStrokeStyle()`: builds a StrokeStyle via
`StrokeStyle.forKind(kind, color).copyWith(size: ...)` and for highlighter
applies `SettingsController.I.settings.highlighterOpacity` to opacity. Map
current tool → StrokeKind (fountain→fountain … highlighter→highlighter).

### controllers/pdf_document_controller.dart (Agent C)

```dart
class PdfDocumentController extends ChangeNotifier {
  static final PdfDocumentController I = PdfDocumentController._();

  bool get isOpen;
  int get pageCount;                 // 0 when closed
  String? currentPath;

  Future<bool> open(String absPath); // closes previous; false on failure
  Future<void> close();

  /// Page size in pdf points (from pdfx page.width/height).
  Size? pageSize(int pageNumber);    // 1-BASED page numbers everywhere

  /// Renders at the best quality bucket for [scaleHint] (screen scale × dpr).
  /// Buckets [1.0,1.5,2.0,3.0,4.0]×dpr, max render width 2200px.
  /// LRU cache of 18 ui.Images. SERIALIZED page queue (pdfx/Android:
  /// never render two pages at once; close each PdfPage after render).
  Future<ui.Image?> pageImage(int pageNumber, double scaleHint);

  final ValueNotifier<int> renderTick; // bumped when new images are ready
  void bump();                        // external re-render request
}
```

Verified pdfx 2.11 API:
`PdfDocument.openFile(path)` → `doc.pagesCount`, `doc.getPage(n)` (1-based),
`page.width/page.height` (pixels), `await page.render(width: w, height: h,
format: PdfPageImageFormat.png, backgroundColor: '#FFFFFF', quality: 95)` →
`PdfPageImage?` with `.bytes` (Uint8List), then `await page.close()`, finally
`await doc.close()`. Decode bytes via `ui.instantiateImageCodec` or
`ui.decodeImageFromList`.

### controllers/shape_recognizer.dart (Agent C)

```dart
class RecognizedShape {
  final ShapeEl? element;   // null when nothing recognized
  final double confidence;  // 0..1
  const RecognizedShape(this.element, this.confidence);
}

class ShapeRecognizer {
  static const double rdpEpsilon = 2.0;
  static RecognizedShape recognize(List<Offset> pts);
}
```

RDP simplify → corner count + closure (first-last < 15% of bbox diagonal) +
radial variance heuristics → line (0–1 corners), triangle (3), rectangle (4 +
right angles), ellipse (few corners + low radial variance), polygon
(≥3 corners, regular), star (corner count = 2×points). The returned ShapeEl
must have a fresh `ElementIdGen.next()` id, strokeColor/width from
ToolController.I, z=0 (engine sets it), and geometry in the SAME page space
as the input points.

### controllers/laser_controller.dart (Agent C)

```dart
enum LaserMode { normal, timed }

class LaserController extends ChangeNotifier {
  static final LaserController I = LaserController._();

  LaserMode mode;        // normal = comet trail (~600ms per-point fade)
  int seconds;           // timed mode: whole stroke stays N seconds (1..10)
  int color;             // ARGB

  void beginStroke(int pageId);   // page the laser started on
  void addPoint(Offset pagePoint);
  void endStroke();

  /// Snapshot for the painter: pageId → list of (points, alpha-per-stroke,
  /// per-point ages). The overlay calls [tick] from a ~30fps timer that
  /// drives fading.
  void tick();                       // advances fades + notifyListeners

  /// Render data: per active stroke: points + list of point ages (ms) +
  /// stroke alpha (0..1). Compute inside the painter via ageOf(i).
  List<LaserStroke> get strokes;
}

class LaserStroke {
  final int pageId;            // page this stroke belongs to
  final List<Offset> points;   // page space
  final int createdAtMs;       // engine clock (DateTime.now)
  final bool released;         // pen up already happened
  int get ageMs;               // now - createdAtMs
  List<int> pointTimesMs;      // arrival time per point
}
```

NEVER committed to the document.

### controllers/audio_controller.dart (Agent C)

```dart
class AudioController extends ChangeNotifier {
  static final AudioController I = AudioController._();

  // Recording (package:record — class AudioRecorder).
  bool get isRecording;
  int? recordingPageId;
  int recordingElapsedMs();          // while recording
  ValueNotifier<double> level;       // 0..1 normalized from Amplitude dB

  Future<bool> startRecording(int notebookId, int pageId); // false = no permission
  Future<void> stopRecording();      // saves RecordingEntity + file

  Future<void> loadForNotebook(int notebookId);
  List<RecordingEntity> recordings;  // of current notebook, newest first

  // Playback (package:audioplayers).
  bool get isPlaying;
  Duration position;
  Duration? duration;
  RecordingEntity? playing;

  Future<void> play(RecordingEntity r);
  Future<void> togglePlayPause(RecordingEntity r);
  Future<void> stopPlayback();
  Future<void> seekTo(Duration d);
  Stream<Duration>? get onPositionChanged;   // audioplayers stream
  Stream<Duration>? get onDurationChanged;

  // Sync replay: while [syncReplayMode] and playing, replayAtMs follows the
  // player position; painters hide strokes with tStart > replayAtMs.
  bool syncReplayMode;
  int get replayAtMs;
  void setSyncReplay(bool enabled);  // starts playback if needed
  Future<void> exitSyncReplay();

  Future<void> deleteRecording(RecordingEntity r);
}
```

Verified record 6.2.1 API: `AudioRecorder()`,
`await recorder.hasPermission()`,
`await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc,
numChannels: 1, sampleRate: 44100), path: absPath)`,
`await recorder.stop()` → path, `await recorder.getAmplitude()` →
`Amplitude(current: dB, max: dB)` (both negative dB; -45..0 typical).
Recording file: `FileStore.newRecordingFile()` then `FileStore.resolve()`.
audioplayers 6: `AudioPlayer()`, `player.play(DeviceFileSource(path))`,
`player.onPositionChanged`, `player.onDurationChanged`,
`player.onPlayerStateChanged`, `player.pause()`, `player.stop()`,
`player.seek(pos)`, `player.release()`.

### controllers/library_controller.dart (Agent D)

```dart
class LibraryController extends ChangeNotifier {
  static final LibraryController I = LibraryController._();

  List<TabEntity> tabs;
  List<FolderEntity> folders;
  List<TagEntity> tags;
  List<NotebookEntity> notebooks;    // FILTERED result list

  int? selectedTabId;                // null = "All"
  int? currentFolderId;              // null = root
  LibrarySection section;            // all / favorites / trash
  String query;                      // instant search
  SortKey sortKey; bool sortAsc;
  ViewMode viewMode;

  Future<void> reload();             // refetch + refilter + notify

  // Mutations (all call reload internally):
  Future<void> selectTab(int? id);
  Future<void> enterFolder(int? id);
  Future<void> setSection(LibrarySection s);
  void setQuery(String q);
  void setSort(SortKey k, bool asc);
  void setViewMode(ViewMode m);

  Future<NotebookEntity> createNotebook({title, coverId, coverImagePath,
      folderId, template, pageSize, paperColor});
  Future<void> renameNotebook(NotebookEntity n, String title);
  Future<void> toggleFavorite(NotebookEntity n);
  Future<void> moveNotebook(NotebookEntity n, int? folderId);
  Future<void> assignTag(NotebookEntity n, TagEntity t);
  Future<void> unassignTag(NotebookEntity n, TagEntity t);
  Future<void> trashNotebook(NotebookEntity n);
  Future<void> restoreNotebook(NotebookEntity n);
  Future<void> purgeNotebook(NotebookEntity n);
  Future<void> emptyTrash();

  Future<NotebookEntity?> importPdf(File pdfFile);  // new notebook, 1 page per PDF page

  Future<TagEntity> createTag(String name, int color);
  Future<void> deleteTag(TagEntity t);

  Future<FolderEntity> createFolder(String name, int color, String emoji);
  Future<void> renameFolder(FolderEntity f, String name);
  Future<void> deleteFolder(FolderEntity f);

  Future<TabEntity> createTab(String name, int color, String emoji);
  Future<void> renameTab(TabEntity t, String name);
  Future<void> deleteTab(TabEntity t);

  // Helpers for the UI:
  String folderPath(int? folderId);        // "Root / A / B" (localized)
  List<FolderEntity> childFolders(int? parentId);
  List<TagEntity> tagsOf(NotebookEntity n);
  int daysLeftInTrash(NotebookEntity n);
}
```

Search matches: title, folder names on its path, tag names, textIndex —
case-insensitive, instant (on every query change).
Sort: opened/modified/created/title × asc/desc.
`importPdf`: copy file via FileStore.importFile(f, 'pdfs'), open with
`PdfDocument.openFile` to read pagesCount, create notebook + N pages each
with the pdf as background (notebook.pdfPath set).

### workspace/doc_geometry.dart (Agent B)

```dart
class DocGeometry {
  static const double pageGap = 56.0;   // doc-space gap between pages

  DocGeometry(this.pages);             // engine.pages (live list)
  final List<PageMeta> pages;

  Rect pageRect(int pageIndex);        // (0, cumY, w, h)
  Offset pageOrigin(int pageId);
  PageMeta? pageAt(Offset docPoint);   // page containing the doc point
  int? pageIndexAtDoc(Offset docPoint);
  Offset toPage(Offset doc, int pageId);      // doc - origin
  Offset toDoc(Offset page, int pageId);
  Rect get docBounds;                  // union of all pages + margins
  List<PageMeta> visiblePages(Rect docRect);  // culled
}
```

### workspace painters (Agent B)

```dart
class PaperPainter extends CustomPainter {
  PaperPainter({required this.template, required this.paperColor, required this.size});
  // size = PageSizeDef (w,h). Paints the paper bg + template lines with
  // templateLineColor(paperColor). GRID_PITCH=24 base; staff = 5 lines
  // grouped; isometric = 30°; hex tiling; manuscript = baseline + dashed mid.
}

class InkPainter extends CustomPainter {
  InkPainter({required this.ink, this.replayAt});   // super(repaint: ink)
  // Paints committed strokes of the page in z order merged with elements?
  // NO — only strokes. Elements are painted by ElementsPainter. z-order
  // merge: see PageContentPainter below.
  // Highlighter strokes: group by color, draw each group inside ONE
  // saveLayer(color.withOpacity(opacity)) so the same color NEVER darkens
  // where it overlaps itself. Highlighters render AFTER normal strokes.
  // replayAt != null → hide strokes with tStart > replayAt.
}

class LiveStrokePainter extends CustomPainter {
  LiveStrokePainter({required Listenable repaint});  // engine.liveStroke
  // Paints the in-progress stroke (fountain etc. + laser preview is separate).
}

class ElementsPainter extends CustomPainter {
  ElementsPainter({required this.ink, this.replayAt});  // super(repaint: ink)
  // Paints TextEl (rich text via TextPainter), ShapeEl via buildShapePath,
  // ImageEl via AppImageCache + builtin stickers via StickerArt.
  // Rotation: canvas.save(); translate(center); rotate(rotation); … restore.
  // flipH/flipV via canvas.scale.
}

/// Composes ink + elements in interleaved z order (used by the page widget,
/// thumbnails and export).
class PageContentPainter extends CustomPainter {
  PageContentPainter({required this.ink, this.replayAt, this.selectedStrokeIds,
    this.selectedElementIds});
}

Path buildShapePath(ShapeEl el);   // 12 shape types incl. arrowheads, star,
                                   // polygon(sides), freeform pts, arc
```

### workspace/sticker_art.dart (Agent B)

```dart
class StickerArt {
  static const List<String> builtinIds =
      ['heart', 'star', 'smiley', 'check', 'cross', 'arrow', 'bulb', 'flag'];
  /// Vector paths for a builtin sticker scaled into [size].
  List<Path> paths(String id, Size size);
}
```
Draw them as filled paths with a pleasant two-tone look (body + accent), all
inside the box.

### workspace/ruler_overlay.dart (Agent B)

```dart
class RulerState extends ChangeNotifier {
  bool active;             // toggle from the toolbar
  Offset centerDoc;        // ruler center in doc space
  double angle;            // radians
  double length;           // 420 doc units
  bool hitBody(Offset doc);          // hit test for dragging
  bool hitRotateHandle(Offset doc);
  void beginDrag(Offset doc);
  void moveTo(Offset doc);            // while dragging
  void rotateBy(double delta);
  /// Ink snap: project [p] onto the ruler EDGE if within 14pt, else null.
  Offset? snap(Offset p);
  /// The ruler segment endpoints in doc space.
  (Offset, Offset) segment();
}

class RulerOverlay extends StatelessWidget {  // or StatefulWidget
  // Renders the ruler inside the transformed canvas; listens to RulerState.
  const RulerOverlay({required this.ruler, required this.viewport});
}
```

### workspace/pdf_page_tile.dart (Agent B)

```dart
class PdfPageTile extends StatefulWidget {
  const PdfPageTile({required this.pdf, required this.pageNumber,
    required this.scale, required this.viewport});
  // Positioned per page by the workspace. Listens to pdf.renderTick +
  // viewport.renderTick; requests render at current bucket; paints the
  // ui.Image at page size; shows nothing when no PDF is open.
}
```

### workspace/laser_overlay.dart (Agent B)

```dart
class LaserOverlay extends StatelessWidget {
  const LaserOverlay({required this.laser, required this.pageId});
  // Listens to LaserController (repaint). Comet trail: per-point alpha from
  // point age (fade ~600ms). Timed: whole stroke alpha fades after N seconds.
  // Owns a 30fps Timer that calls laser.tick() while mounted.
}
```

### workspace/filmstrip.dart + tool_rail.dart + document_workspace.dart (Agent B)

```dart
class Filmstrip extends StatelessWidget {
  const Filmstrip({required this.engine, required this.viewport,
    required this.geometry, required this.onJump});
  // Vertical thumbnail rail: per-page mini canvas (paper + ink via
  // PageContentPainter scaled), jump on tap, long-press menu: duplicate /
  // delete / move up / move down / bookmark / rename title. "+" adds a page.
  // max height with scroll + custom scrollbar. Bookmarked pages show a badge.
}

class ToolRail extends StatelessWidget {
  const ToolRail({required this.tools, required this.engine,
    required this.ruler, this.leftHanded = false, this.onColorTap,
    this.onWidthTap});
  // Vertical rail of the 13 tools (Material icons), undo/redo, ruler toggle,
  // current color swatch (opens color popover). Highlights current tool.
  // width 56, icons 24, min target 44px. Mirrored when leftHanded.
}

/// The full editor screen: header (back, title, undo/redo, zoom %, export
/// menu, audio, pages, settings), body (filmstrip | transformed canvas stack
/// | tool rail), overlays (selection bar, laser, ruler, eraser circle),
/// panels via the show* helpers below, autosave timer, gesture router wiring.
class DocumentWorkspace extends StatefulWidget {
  const DocumentWorkspace({required this.notebookId});
  final int notebookId;
}
```

Workspace structure (Agent B must follow):
- `Listener` (behavior: translucent) with the router handlers wraps a
  `Stack` whose first child is `AnimatedBuilder` on viewport → `Transform`.
- Inside the transform: vertical `Stack`/`Positioned` pages: for each visible
  page (DocGeometry.visiblePages(viewport.visibleDocRect(size))): a
  `CustomPaint` with `PageContentPainter` (paper + pdf tile + content) or
  layered painters; then overlays (ruler, lasso preview, selection handles).
- The live stroke painter sits on top of the ACTIVE page's content, in page
  space (translate to page origin).
- The eraser circle + selection bar + laser overlay live in SCREEN space
  (outside the transform) — laser needs page-space mapping: render laser
  overlay per page inside the transform.
- Autosave: `Timer.periodic` per settings.autosaveDelayMs → engine.flush();
  also flush on dispose; set `engine.recordingClock = audio.recordingElapsedMs`
  while recording (null otherwise).
- PDF: on open, if notebook.pdfPath != null → resolve via FileStore and
  `PdfDocumentController.I.open(...)`.
- Panel invocations (Agent E implements these EXACT signatures):
  - `showColorPopover(context, tools)` — Future<void>
  - `showTextSheet(context, engine, pageId, {TextEl? existing})` — Future<void>
  - `showStickerPicker(context, engine, pageId, centerDoc)` — Future<void>
  - `showPagesSheet(context, engine)` — Future<void>
  - `showAudioPanel(context, engine)` — Future<void>
  - `showTranslatePopup(context, initialText)` — Future<void>
  - `ExportService.sharePagePng(engine, pageMeta)` — Future<void>
  - `ExportService.shareNotebookPdf(engine)` — Future<void>
- Text tool tap: `engine.elementAt(pageId, pagePoint)` → TextEl?
  showTextSheet(existing:) else create TextEl at point (default size 18,
  width 220) then showTextSheet. Image tool: FilePicker image →
  FileStore.importFile(f, 'images') → ImageEl centered at point (w=280,
  h proportional via decoded image), engine.addElement, select it.
  Sticker tool: showStickerPicker.
- Selection action bar (floating, above selection in screen space):
  delete, duplicate, copy, paste (enabled when engine.hasClipboard),
  bring-front, send-back, group, ungroup — calling the engine methods.

### services/image_cache.dart (Agent E)

```dart
/// LRU(24) of decoded ui.Images keyed by absolute path.
class AppImageCache {
  static Future<ui.Image> load(String absPath);
  static ui.Image? peek(String absPath);
  static void clear();
}
```
(Do NOT name it ImageCache — clashes with Flutter's.)

### services/translate_service.dart (Agent E)

```dart
class TranslateResult {
  final String text;
  final bool usedOffline;
  final double coverage;     // offline word coverage 0..1
  const TranslateResult(...);
}

class TranslateService {
  /// MyMemory: https://api.mymemory.translated.net/get?q=..&langpair=SRC|TGT
  /// Source auto-detected: Arabic when >30% of characters are Arabic-range.
  static Future<TranslateResult?> translateOnline(String text, String target);
  /// Offline AR<->EN dictionary (~180 pairs), word-by-word, coverage %,
  /// refuse (null) below 25% coverage.
  static TranslateResult? translateOffline(String text, String target);
  /// Chain: online → offline → null.
  static Future<TranslateResult?> translate(String text, {String? target});
  /// "google" engine: launch translate.google.com/?sl=auto&tl=TGT&op=translate&text=..
  static Future<bool> openGoogleTranslate(String text, String target);
  /// Ask AI: copy to clipboard first, then launch chatgpt.com/?q=… |
  /// gemini.google.com/app?q=… | claude.ai/new?q=…
  static Future<void> askAi(BuildContext context, String text);
}
```

### services/export_service.dart (Agent E)

```dart
class ExportService {
  /// PNG at 2x: paper + template + PDF bg + ink + elements via
  /// PictureRecorder → toImage(w*2, h*2) → temp file → Share.shareXFiles.
  static Future<void> sharePagePng(StrokeEngine engine, PageMeta page);
  /// PDF: one page per notebook page; raster each page 2x, embed into
  /// pw.Page(pageFormat: PdfPageFormat(w*0.75, h*0.75)) as pw.Image;
  /// share the .pdf file.
  static Future<void> shareNotebookPdf(StrokeEngine engine);
}
```
Uses PaperPainter / PageContentPainter paint() directly on a Canvas —
painters are plain CustomPainters, they can paint anywhere.

### services/backup_service.dart (Agent E)

```dart
class BackupService {
  /// Single .nanote JSON: {version: 2, entities: {...}, files: {relPath: base64}}
  static Future<String?> createBackup();   // returns path (for share) or null
  /// Wipes DB + files, reinserts PRESERVING numeric Isar ids.
  static Future<bool> restoreBackup(File file);
  static const int formatVersion = 2;
}
```

### UI panels (Agent E) — exact signatures

```dart
Future<void> showColorPopover(BuildContext context, ToolController tools);
// 16 palette (5 for highlighter) + 5 favorite slots + hue/saturation custom
// wheel (custom painter) + recent colors. Sets pen color + addRecentColor.

Future<void> showTextSheet(BuildContext context, StrokeEngine engine,
    int pageId, {TextEl? existing});
// content TextField, 6 fonts, size slider, color, bold/italic/underline,
// align start/center/end. Creates or updates the TextEl (engine.addElement /
// engine.updateElement). Empty text on new → no element.

Future<void> showStickerPicker(BuildContext context, StrokeEngine engine,
    int pageId, Offset centerDoc);
// 8 builtin + user PNGs (FileStore.listStickers). Insert as ImageEl
// (builtinId or src), w=96 h=96 at centerDoc, engine.addElement.

Future<void> showPagesSheet(BuildContext context, StrokeEngine engine);
// Full page list: labels, bookmarks, add/duplicate/delete/reorder,
// jump-to (viewport centering is done via callback — sheet only mutates
// engine + reports the pageId via Navigator.pop(result)).

Future<void> showAudioPanel(BuildContext context, StrokeEngine engine);
// Record button (with level meter), recordings list (play/pause + delete),
// sync-replay toggle, exit replay. Uses AudioController.I.

Future<void> showTranslatePopup(BuildContext context, String initialText);
// Source text field, result area, engine selector (Nanote/Google), target
// selector (auto/ar/en), translate button with loading, Ask AI buttons.
```

### Library + settings UI (Agent D) — screens

- `ui/library/library_view.dart` — `LibraryView` (StatefulWidget): edge tab
  rail (color + emoji chips, long-press to edit/delete), folder breadcrumb +
  child folder chips, notebook grid/list (NotebookCard), search bar, sort
  menu, view toggle, FAB "new notebook", PDF import button, trash section
  view (restore/purge/empty + days-left badge).
- `ui/library/notebook_card.dart` — `NotebookCard` (cover gradient or image,
  title, page count via LibraryRepository.I.pageCount, favorite star, tag
  dots, context menu: rename/move/tags/favorite/delete).
- `ui/library/library_dialogs.dart` — helpers: `showCreateNotebookSheet(context)`
  (name, cover picker, template picker, page size, paper color), rename
  dialogs, folder pickers, tag editor.
- `ui/notebook/create_notebook_view.dart` — full-screen create flow (same
  fields as the sheet) — expose `class CreateNotebookView` with
  `onCreated(NotebookEntity)` callback via constructor OR route pop result.
- `ui/settings/settings_view.dart` — `SettingsView`: sections Appearance /
  Writing / Pens (→ PenManagerView) / Stickers (→ StickerManagerView) /
  Translation / Data (backup/restore) / About (version 2.0.0, check updates
  → https://github.com/ahmedhaidr999-droid/nanote-native/releases).
- `ui/settings/pen_manager_view.dart` — `PenManagerView`: connected-pen live
  card (PenBus.I.notifier: kind, pressure, tilt, buttons, report rate),
  TEST PAD (own Listener drawing live trace + meters), shortcuts editor
  (4 buttons × 4 patterns → PenAction dropdown), master switch.
- `ui/settings/sticker_manager_view.dart` — `StickerManagerView`: user PNG
  stickers grid, import via FilePicker, delete.

Navigation (main.dart will do): `/` LibraryView, `/notebook` (args int id)
DocumentWorkspace, `/settings` SettingsView, `/pen` PenManagerView,
`/stickers` StickerManagerView.

## Package API cheat-sheet (verified)

- perfect_freehand 2.5.2: `getStroke(List<PointVector>, options:
  StrokeOptions(...)) → List<Offset>`; `PointVector(x, y, [pressure])`;
  StrokeOptions named args: size, thinning, smoothing, streamline,
  simulatePressure, isComplete, start/end: StrokeEndOptions.start(cap:,
  customTaper:)/.end(...) (customTaper -1 = full taper, 0 = off).
- pdfx 2.11: see PdfDocumentController above.
- record 6.2.1: see AudioController above.
- audioplayers 6: AudioPlayer, DeviceFileSource, onPositionChanged…
- file_picker 8: `FilePicker.platform.pickFiles(type: FileType.image)` /
  `(type: FileType.custom, allowedExtensions: ['pdf','png'])` → result.files.single.path.
- share_plus 10: `Share.shareXFiles([XFile(path)], text: ...)`.
- url_launcher 6: `launchUrl(Uri.parse(url), mode:
  LaunchMode.externalApplication)`.
- pdf 3.13: `final doc = pw.Document(); doc.addPage(pw.Page(pageFormat:
  PdfPageFormat(wPt, hPt), build: (_) => pw.Image(pw.MemoryImage(bytes))));
  await doc.save()` → bytes.
- Clipboard: `Clipboard.setData(ClipboardData(text: ...))`.
