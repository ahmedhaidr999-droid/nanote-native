# Nanote Native

**A local-first handwriting notes app for Android — 100% Flutter/Dart, no WebView.**
Full feature parity with the Nanote v1.9.1 web app, rebuilt native.

<p>
<img alt="platform" src="https://img.shields.io/badge/platform-Android-3DDC84">
<img alt="flutter" src="https://img.shields.io/badge/Flutter-3.29-02569B">
<img alt="dart" src="https://img.shields.io/badge/Dart-3.7-0175C2">
<img alt="license" src="https://img.shields.io/badge/license-MIT-green">
</p>

## v2.6.3 — Release pipeline repaired + install-on-update fixed

No app-code changes: this release fixes the **release pipeline and the
"App not installed" problem** on top of v2.6.2.

**What was conflicting and got removed:**
- Corrupted workflow branch filter (`branches: ain]` → `[main]`) that made
  main pushes unreliable and double-built tags.
- Duplicate workflow runs per push (a `concurrency` group now cancels the
  superseded run).
- The abandoned `v1` / `v2-line` / `rebuild/v1.0.0-pdfrx` branches, the stray
  `v1.0.0` / `v2.7.0` tags and the failed `apk.yml` runs are gone.

**Why updates refused to install ("App not installed"):**
- Releases **v2.0.0–v2.4.0 were signed with a different, since-lost
  certificate** than v2.5.1+. Android refuses to update an app when the
  signing certificate changes — that is the classic "App not installed"
  error. From v2.5.1 on (including this v2.6.3) every release is signed
  with the same release keystore, so updates install with data intact.
- If a device still holds a ≤ v2.4.0 install: export a `.nanote` backup
  from the old app, uninstall it, install v2.6.3, restore the backup.
- Signing now happens **inside the Gradle build** (`key.properties` +
  keystore restored from repository secrets before `assembleRelease`):
  one APK, signed exactly once with the release identity — no more
  debug-signed intermediate that gets re-signed afterwards.
- `versionName` is derived from `pubspec.yaml` (no more hardcoded
  `--build-name`), `versionCode` stays the workflow run number
  (monotonic: 39 → 42 → 43+).

## v2.6.2 — Structure restored + PDFium engine + reliable PDF import

**What happened:** a "clean rebuild" (the abandoned v1.0.0/v2.7.0 line)
swapped the whole app architecture (Drift instead of Isar, a rewritten
workspace) when only a color-design change had been asked for, and PDF
import regressed on top. This release **rolls the tree back to the
original, battle-tested v2.6.1 architecture** (pdfx + Isar + the
three-layer engine) and layers the genuinely good parts of the abandoned
line on top of it — nothing else changed.

**PDF engine — pdfium (Chrome's PDF engine), same pdfx API:**
- The vendored `third_party/pdfx` Android layer now renders through
  `com.github.barteksc:pdfium-android` instead of the per-vendor
  `android.graphics.pdf.PdfRenderer` (several Samsung/MIUI builds ship a
  broken one that refuses valid files — a real "PDFs don't open" driver).
- Pages are loaded exactly once (ref-counted), guaranteed loaded before
  render (pdfium silently renders BLANK for unloaded pages — the
  gray-page mode), unloaded on last release, bitmaps recycled after every
  render, annotations rendered (`FPDF_ANNOT`).
- All v2.6.1 Dart-side hardening is kept: **per-document locks** (a wedge
  can never poison the whole app again), **idempotent never-throwing
  closes**, **reply-shape pixel source**, watchdog + memory-aware retry
  ladder, 1080px raster cap.

**PDF import — typed, explained failures instead of a bare "error":**
- The picker result is validated (path readable, or bytes fallback for
  cloud/content-URI providers), the file is copied into app storage
  FIRST, the stored copy is signature-checked (`%PDF` header), and the
  engine open runs under a 20 s guard timeout.
- Every failure is reported with its actual reason (unreadable / not a
  PDF / password-protected / damaged / timeout / storage) in Arabic and
  English.

**PDF text selection removed (spec §8, native limitation):** pdfx
exposes no text layer, and the v2.5.0-era custom extractor (2.8k lines
parsing raw PDF bytes) was a memory-pressure contributor to the very OOM
class that grayed pages out. Nanote ships without PDF text selection and
leaves a **clean extension point**: `GestureRouter.onPdfLongPress`
receives every long-press on a rendered PDF page already resolved to
(pageId, pageNumber, screen point) — a future text-capable engine plugs
in there with zero gesture-router changes.

**Build:** no NDK needed (native libs shipped as-is), dead mips/mips64
ABIs filtered out, release lint off — matching the only configuration
that produced a green signed APK on CI.

## v2.6.1 — Real E2E diagnosis of "only page 1 renders"

The v2.6.0 analysis was refined against the REAL production pipeline
(tiles → controller → Pigeon channel → native) with E2E tests instead of
platform fakes. Root causes: (1) upstream pdfx serialized EVERY call
app-wide through one global lock — a single never-completing call held it
forever, so after a wedge even a reopened document queued eternally
behind the poisoned lock; (2) `close()` threw on double-close and marked
the doc closed before the native call — one failed native close leaked
the renderer and broke every later close; (3) the render pixel source
was chosen by host platform instead of the reply's shape; (4) OOM retries
looped at the same raster size forever on mid-RAM devices. Fixes:
per-document locks, idempotent closes, reply-shape pixel choice, a
memory-aware retry ladder (1440→1080→720→540→405 px per page after
consecutive failures), wedge-recovery budget resets, and pipeline
debug logging. 24 tests green including 3 new E2E ones.

## v2.6.0 — "Only page 1 renders, pages 2+ stay gray" — root cause fixed

**The bug:** after the v2.5.2 gray-screen fix, PDFs opened showing ONLY the
first page; every other page stayed blank/gray no matter how much the user
scrolled or flipped pages.

**Root cause (found by reproducing the full pipeline against a faithful
fake of pdfx's Android native layer):** pdfx 2.11's Android `renderPage`
coroutine (`Messages.kt`) catches only `Exception`. Rendering a full page
allocates a large ARGB bitmap (`Bitmap.createBitmap`); under memory
pressure that throws **`OutOfMemoryError` — an `Error`, not an
`Exception`** — which escapes the catch block. `result.error(...)` never
runs, the platform-channel reply is never sent, and the Dart-side render
future **never completes**. Nanote's renderer serializes every pdfx call
through one queue, so one wedged render stalls the queue FOREVER — right
after the first page (rendered while memory was still fresh). Contributing
factors: 1600px-wide rasters × a 12-entry LRU (~175MB of decoded pixels)
made the OOM likely on mid-RAM devices, and the v2.5.0 text-extraction
isolate (whole PDF copied + parsed) competed with renders at exactly the
wrong moment.

**The fix (replace the fragile parts with stable ones):**
- **Vendored pdfx fork** (`third_party/pdfx`, wired via
  `dependency_overrides`): the render coroutine now catches `Throwable` —
  every failure path delivers the platform reply, so a render can fail but
  never hang. Also fixed: the unawaited platform-support assert in
  `PdfDocument.openFile` (its error used to escape as an unhandled async
  error in the caller's zone).
- **Memory budget:** max raster width 1600→1440px and LRU 12→8 entries —
  ~95MB worst-case decoded pixels instead of ~175MB. Same on-screen
  sharpness at fit-width on 3×-dpr phones.
- **Watchdog:** every queued pdfx task carries a deadline. A task that
  blows it has its future completed (callers unblock), the queue is
  force-reset, and a rate-limited document REOPEN clears any bad native
  state. `pageImage` awaits with its own timeout, so a stuck future can
  never freeze a tile.
- **No permanent page death:** visible-page (priority) requests always get
  fresh render attempts; a document reopen clears every failure record.
- **Ref-count correctness:** live images are tracked by unique handles
  (`key#seq`), so a same-key re-render can never leak the old pixels nor
  dispose pixels a tile is still painting.
- **Text extraction delayed 2s** after open — the isolate no longer
  competes with the first page renders for memory.

**Verification:** 8 new pipeline regression tests (test/
pdf_render_pipeline_test.dart) drive the REAL controller + REAL tiles
against a fake that models Android's native semantics exactly — including
the one-open-page rule and the never-completing OOM wedge ("THE BUG"
test: watchdog recovers and every page renders afterwards), transient
failures, zoom re-renders, the pages-manager thumbnail storm, the
dispose→reopen race, and the 1440px memory cap. Plus 4 workspace-layout
tests (multi-page stacking, culling, pan clamping) — 25 tests total, all
green. Same release keystore as 2.5.x — updates install directly.

## v2.5.2 — Gray-screen fix (release builds)

**The bug:** opening ANY notebook (PDF included) left the screen gray in
release builds. `tool_rail.dart`'s `_verticalBody` wrapped its
`SingleChildScrollView` in a `Flexible` — but since v2.4.0 the capsule
lives under `Align > SafeArea > Container` with **no Flex ancestor**.
`Flexible.applyParentData` does an unchecked `as FlexParentData` cast,
which throws `BoxParentData is not a subtype of FlexParentData` on EVERY
workspace build in release mode (debug-only asserts hide it). The repeated
build exception replaced the workspace with Flutter's gray release
ErrorWidget.

**The fix:** a height-capped `ConstrainedBox` (viewport minus chrome) —
identical scrolling behavior, no Flex parent needed. Verified on an
Android emulator with a release APK: 0 errors; the PDF page and tool rail
render correctly. CI now signs releases with the permanent
`nanote-release.keystore` (same key as v2.5.1-signed — updates install
over it directly).

## v2.5.1 — PDF text selection: correctness & real-world PDF fixes

v2.5.0 shipped the PDF text-selection engine; this release hardens the
extractor against the real world (all fixes verified against PyMuPDF
ground-truth coordinates and covered by `test/pdf_text_extractor_test.dart`):

1. **Word boxes were ~fontSize× too wide** — the glyph quad passed the
   USER-space advance through the text rendering matrix, which scales by
   the font size again. Selection rectangles, hit-testing and highlight
   strokes now land exactly on the visible text ("The" at 14pt Helvetica:
   24.1pt — was 112pt).
2. **Standard fonts without /Widths fell back to 500 for every glyph** —
   built-in Adobe AFM metrics for the 14 standard fonts (plus
   metric-compatible aliases Arial/Times New Roman/Courier New and
   subset prefixes like `ABCDEF+Helvetica`) now drive the advances, so
   the very common non-embedded Helvetica/Times/Courier PDFs extract
   with exact positions.
3. **Form XObjects were not recursed** — Chrome print-to-PDF,
   wkhtmltopdf, Word exports and similar generators wrap the page text
   inside `/Fx Do` forms (with their own resources and matrices).
   Without recursion NO text was found on such pages. Forms are now
   interpreted with their /Matrix composed into the CTM and their own
   /Resources overlaid, with cycle/depth guards.
4. **Tc/Tw/Tz followed the spec formula** — `Tx = ((w0/1000)×Tfs +
   Tc + Tw)×Th`: char/word spacing are no longer divided by 1000, and
   horizontal scaling applies to the whole displacement (verified
   against kerned/spacing-heavy content streams).
5. **Shaped Arabic normalizes to base letters** — presentation forms
   (Arabic Presentation Forms-A/B) map back to their base letters, with
   lam-alef ligature expansion aware of visual vs logical storage, so
   copied/translated/searched text reads `اختبار`, not `ﺧﺘﺒﺎﺭ`.
6. **RTL word order follows the storage mode** — visual (shaped)
   lines reverse to the logical sentence on copy; naive unshaped lines
   keep their left-to-right logical order. Verified end-to-end: classic
   arabic-reshaper/bidi PDFs, logical per-glyph (Chrome/Word-style)
   PDFs and plain logical strings all copy as the author wrote them.

## v2.5.0 — PDF text selection + true-highlighter rendering

**Long-press any text in a PDF to select it.** Nanote now ships its own
pure-Dart PDF text extractor (no new dependencies, fully offline): it
parses classic xref tables, PDF 1.5+ xref streams, object streams,
Flate/ASCII85 filters, simple + composite (Identity-H) fonts with
ToUnicode CMaps, tracks the full text matrix, groups glyphs into
RTL-aware words/lines, and maps everything through the page's /Rotate so
the selection rectangles land exactly on the visible text — verified
against Latin, Arabic and rotated pages.

Selection is touch-first (no stylus needed) and works with any
non-eraser tool: press-and-hold picks the nearest word, drag or pull the
handles to extend, and an action bar appears with **Copy · Translate ·
Search the web · Highlight · Underline · Select text · Select all ·
Ask (the AI chosen in Settings: ChatGPT / Gemini / Claude)**. Highlight
and Underline commit real ink strokes through the engine — undoable,
autosaved, and rendered with the highlighter's live color/density. A
long-press on empty space or an image shows nothing (no text, no menu),
and the hold cancels any in-progress stroke so nothing unwanted is
drawn. Extraction runs once per document on a background isolate, so
the UI never blocks.

**The highlighter now behaves like a real highlighter.** Two bugs fixed:
1. *Opacity changes only applied after switching pages* — the renderer
   grouped strokes by color alone and painted each group at the FIRST
   stroke's opacity, so a stroke drawn right after changing the density
   rendered at the old value. Strokes are now grouped by (color,
   opacity) and every stroke renders at the density it was drawn with.
2. *100% opacity hid the text underneath* — highlight groups now
   composite with a MULTIPLY blend: the ink and PDF text under the
   highlight stay readable at ANY density (dark text stays dark; white
   paper takes the tint), overlapping strokes of the same color never
   self-darken, and the live preview matches the committed look
   (previously a hardcoded 50% alpha). Verified at pixel level: black
   text under a 100% highlight stays black.

## v2.4.0 — PDF all-pages root fix + Infinity Paper


**PDF notebooks now show every page.** Opening a PDF notebook self-heals its
page list to the PDF's page count (notebooks created by older versions — or
an interrupted import — previously owned a single page, so the editor showed
only page 1 and dark empty space below). The paper layer now always paints
under the PDF tile (a pending or failed render can never leave a dark void),
the pan bounds refresh on every repaint (a stale bounds could lock scrolling
after the page list changed), per-page PDF aspect application can no longer
drop resolved sizes, and tiles that burned their retries while the document
was still opening are woken the moment it opens.

**The v1.9.1 design system, applied across the whole app:**
- **Colors**: Nanote Blue `#1E6FF2` (light) / `#6BA6FF` (dark) as the only
  blue; ink-and-paper neutrals (`#F7F9FC`/`#0E1622` backgrounds), instant
  light/dark switching, no indigo, no other blues.
- **Type**: Inter for Latin (cv11 + ss01, tabular numbers) with Noto Sans
  Arabic for Arabic glyphs — bundled, offline.
- **Radius 8/10/12/16 + two ink shadows** (soft `ink-1`, floating `ink-2`),
  pill CTAs, capsule dark toasts, press-scale 0.96/120ms on every tappable.
- **Library**: 56px top bar (logo + search + settings), notebook grid with
  3:4 covers and page-count chips, bottom navigation (My Notebooks /
  Folders / Tags / Trash), gradient "+" capsule with the create menu
  (notebook / import PDF / folder), folder & tag color palettes (10/8).
- **12 notebook covers** (3:4): 6 gradients + 4 flat + 2 patterns (dots,
  lines) with per-cover text colors; live preview in the create screen.
- **Create screen**: live 3:4 cover preview (max 280px, start side on
  tablets, top on phones), cover grid (12) · template (12) · paper size
  (A4/A5/Letter + portrait/landscape) · paper color (8), pill CTA.
- **Editor**: the tool rail is now a floating frosted capsule — bottom-center
  horizontal on tablets/landscape, vertical on the phone edge — draggable by
  its handle between docks. 44×44 rounded tiles, active tool in solid
  primary, grouped with hairline separators.
- **Panels**: 256px tool-settings popover (5-column color grids, segmented
  controls, sliders with tabular values), restyled color picker (HSV wheel,
  per-tool favorites, recents), pages manager (bordered thumbnails, page
  badges, bookmark dots, dashed add-page tile), text/audio/translate/sticker
  panels.
- **Icons**: Lucide exclusively (thin 1.5–2 stroke, 14/16/20/24 sizes).
- **Numerals**: Latin digits by default; Hindi (٠١٢٣) optional in Settings.

## v2.0.1 — Editor fixes

- **Writing offset FIXED**: all pointer math now uses canvas-local coordinates
  (`e.localPosition`). Previously global window coordinates were mixed with the
  canvas transform, so ink, taps, lasso, the pinch focal and the eraser circle
  appeared ~56px away from the pen (app-bar height + rail width).
- **PDF pages no longer float/move/shuffle**: page tiles are pinned with stable
  `ValueKey`s (index-based Stack matching previously swapped one page's rendered
  PDF onto another page while scrolling), each page adopts its real PDF aspect
  ratio (no stretching), and the placeholder is light paper instead of gray.
- **Centered pages**: opening/jumping fits the page width and keeps any axis
  that fits the screen perfectly centered; pan is clamped to the document so
  pages can never be pushed off-screen.
- **Smooth continuous vertical scrolling**: inertial fling after panning
  (exponential decay, stops on any new touch), like a document viewer.
- **Tool settings panel**: tapping a rail tool selects it AND opens its own
  settings (colors, width, eraser mode/size, laser, text, shapes); tapping the
  active tool again closes the panel.
- **Eraser**: live circle preview while hovering with the tool active (correct
  screen-space radius under zoom), cursor position exact, cleared on tool switch.
- **Writing quality**: real stylus pressure is used when it varies (velocity
  simulation for finger/mouse), live strokes render without premature end taper.
- CI workflow branch filter repaired (`main`), build 2.0.1.


## Getting the APK

1. Go to the **Releases** page → latest `native-v*` release → download
   `nanote-native-<version>.apk`.
   (Or **Actions** tab → latest successful **Android APK** run →
   **Artifacts** → `nanote-native-apk`.)
2. Transfer the APK to your phone and install it ("install unknown apps"
   must be allowed for your browser/file manager).
3. Every release since v2.5.1 is signed **during the Gradle build** with the
   release keystore (`NANOTE_KEYSTORE_BASE64` / `NANOTE_KEYSTORE_PASSWORD` /
   `NANOTE_KEY_ALIAS` / `NANOTE_KEY_PASSWORD` repository secrets) — updates
   install over any v2.5.1+ build with data intact.
4. **"App not installed" when updating?** Your device still holds a ≤ v2.4.0
   build (those were signed with a different, since-lost certificate).
   Export a `.nanote` backup from the old app, uninstall it, install the
   new release, restore the backup.

## Feature map (v1.9.1 parity)

| Area | What you get |
|---|---|
| **Library** | Edge tabs (color+emoji), nested folders, favorites, tags, trash (30-day retention, restore/purge/empty), instant search (titles + folders + tags + text-box content), sort (opened/modified/created/title × asc/desc), grid & list views, PDF import (each PDF page becomes a page background; original file stored untouched) |
| **Notebooks** | 8 built-in gradient covers + custom cover image, 12 paper templates, 4 page sizes (A4 P/L, Letter P/L), 8 paper colors |
| **Writing** | 5 pressure-sensitive pens (fountain, ballpoint, brush, fineliner, highlighter) via perfect-freehand, per-pen remembered color/width, 16-color palette + 5 favorites + custom hue/saturation wheel + recents, pressure curve (firm ↔ soft), highlighter 10–100% opacity that never self-darkens (per-color saveLayer) |
| **Erasing** | Stroke eraser (whole-stroke delete, one undo op per gesture) + area eraser (bbox intersect), 3 size presets, circle cursor while erasing |
| **Selection** | Lasso with polygon containment + group expansion, move / scale (opposite-corner anchor) / rotate (15° magnetism), floating action bar (delete, duplicate, copy, paste, bring-front, send-back, group) |
| **Elements** | Text boxes (6 Arabic-capable fonts, size, color, bold/italic/underline, align; searchable text index), 12 shape types with fill/opacity/grid-snap/aspect-lock, images (rotate/flip H/V), 8 built-in vector stickers + user PNG collection |
| **Shape recognition** | Draw & hold ~650 ms → RDP + heuristics recognize line/triangle/rect/polygon/ellipse/star → replaces ink with an editable shape as ONE revertible undo op, then continues a fresh stroke |
| **Ruler** | Draggable + rotatable on-canvas ruler; ink snaps to its edge within 14 pt |
| **Laser** | Comet-trail mode (per-point ~600 ms fade) and timed mode (whole stroke stays 1–10 s), custom color — never committed |
| **Pages** | Stable ink slots (Isar id, never the visual index), add / duplicate / delete / reorder, bookmarks, editable titles, vertical filmstrip with live thumbnails + pages manager sheet |
| **Undo/redo** | 200 ops, sealed `InkOp` hierarchy (add/remove ink, add/remove elements, transform snapshots, shape-replace) |
| **Audio notes** | Record per page (AAC/m4a), live level meter, playback, **sync replay** — ink appears at the moment it was written; delete recordings |
| **Translation** | Engine “Nanote” (MyMemory API, auto source detection), engine “Google” (opens translate.google.com), offline AR↔EN dictionary fallback (~400 pairs, coverage %, refuses below 25%), Ask AI (ChatGPT / Gemini / Claude, clipboard-first) |
| **Electronic pen** | Live pen card (kind, pressure, tilt, buttons, report rate), test pad, 4 buttons × 4 patterns bound to 21 actions, master switch |
| **Export** | Page PNG @2×, whole-notebook PDF (correct page sizes), share sheet |
| **Backup** | Single-file `.nanote` backup (versioned JSON + base64 files), restore preserving numeric Isar ids |
| **UI** | Arabic (RTL, Arabic-Indic numerals ٠١٢٣) + English with instant switch, light/dark/system theme, left-handed mode, exact v1.9.1 design tokens |

## Architecture

Three layers, one transform:

```
lib/
  main.dart                    bootstrap, theme, locale, routes
  src/
    theme/                     exact v1.9.1 tokens (ThemeExtension)
    i18n/                      AR/EN dictionaries + ValueNotifier<Lang>
    models/                    paper, tools, strokes, elements, settings
    controllers/
      stroke_engine.dart       THE engine — pages keyed by stable ink slot,
                               undo/redo, eraser, lasso, transforms, clipboard
      viewport_controller.dart ONE Matrix4: screen = doc×scale + pan
      gesture_router.dart      raw Listener input (no GestureArena):
                               stylus/finger routing, palm rejection,
                               barrel-button patterns, pinch focal fix
      pdf_document_controller  pdfx + quality buckets + LRU(18) + serial queue
      tool/library/audio/laser/shape_recognizer/settings/pen_bus
    persistence/               ONE Isar instance, all schemas; JSON strokes
    services/                  translate, export, backup, image LRU cache
    workspace/                 painters, filmstrip, tool rail, overlays,
                               document workspace
    ui/                        library, notebook creation, settings, panels
```

**Solved patterns baked in** (from the v1.9.1 engine): ink lives in page-point
space and is converted through the inverse viewport matrix (ink never drifts);
the ink slot is the PageRow’s stable Isar id; per-page `ChangeNotifier`s so
drawing repaints only the touched page; highlighters render per-color inside
one `saveLayer`; transforms restore-from-snapshot each frame then scale
around the opposite corner / rotate around the center; the PDF settle timer
(220 ms) avoids re-rendering during pinch; pdfx rendering is serialized with
a single in-flight page (Android requirement).

> **PDF text layer note:** `pdfx` cannot extract text, so PDF text selection
> is intentionally not faked. A clean extension point exists:
> `GestureRouter.onPdfLongPress` receives every long-press on a rendered
> PDF page already resolved to (pageId, 1-based pageNumber, screen point).
> A future text-extracting engine (e.g. `pdfrx`) attaches there with zero
> gesture-router changes.

## Building locally

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # isar codegen
flutter run            # or: flutter build apk --release
```

The `android/` folder is **committed**: Gradle 8.10.2 wrapper, AGP 8.7.3,
Kotlin 2.1.0 (the Flutter 3.29.3 toolchain combo) plus the AGP-8 namespace
injection that `isar_flutter_libs` 3.1.0+1 needs — see `android/build.gradle`.
Toolchain: Flutter 3.29.x (the version Isar 3.1.0+1’s generator is verified
against). CI pins 3.29.3.

## Notes & deliberate deviations

- `targetSdk` is pinned to **35** in CI — the newest level fully supported by
  the Flutter 3.29 toolchain (AGP 8.1). Bumping to 36 requires a newer
  Flutter + AGP; the workflow documents the one-line change.
- `vector_math` is overridden to 2.2.0 because pdfx 2.11’s vendored
  `InteractiveViewer` calls `Matrix4.translateByDouble` (added in 2.2.0).
- Tabs in the library are quick-access views (colored, emoji) as in v1.9.1;
  folder assignment stays per-notebook.

## Privacy

Local-first: everything lives on the device (Isar + files). Internet is used
ONLY for user-initiated translation (MyMemory) and Ask-AI/update links.
No accounts, no analytics, no server.
