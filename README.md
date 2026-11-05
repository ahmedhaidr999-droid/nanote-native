# Nanote Native

**A local-first handwriting notes app for Android — 100% Flutter/Dart, no WebView.**
Full feature parity with the Nanote v1.9.1 web app, rebuilt native.

<p>
<img alt="platform" src="https://img.shields.io/badge/platform-Android-3DDC84">
<img alt="flutter" src="https://img.shields.io/badge/Flutter-3.29-02569B">
<img alt="dart" src="https://img.shields.io/badge/Dart-3.7-0175C2">
<img alt="license" src="https://img.shields.io/badge/license-MIT-green">
</p>

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

1. Go to the **Actions** tab → latest successful **Android APK** run →
   **Artifacts** → `nanote-native-apk`.
   (Or download from **Releases** if you tagged `native-v*`.)
2. Transfer the APK to your phone and install it ("install unknown apps"
   must be allowed for your browser/file manager).
3. The CI build is signed with the debug key unless the repo has the
   `NANOTE_KEYSTORE_BASE64` / `NANOTE_KEYSTORE_PASSWORD` /
   `NANOTE_KEY_ALIAS` / `NANOTE_KEY_PASSWORD` secrets configured — then it is
   re-signed with your release keystore via `apksigner`.

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
> is intentionally not faked. A clean extension point exists in
> `PdfDocumentController` — swap in a text-extracting implementation (e.g.
> `pdfrx`) if needed.

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
