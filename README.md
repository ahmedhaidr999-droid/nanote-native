# Nanote Native

**A local-first handwriting notes app for Android — 100% Flutter/Dart, no WebView.**

<p>
<img alt="platform" src="https://img.shields.io/badge/platform-Android-3DDC84">
<img alt="flutter" src="https://img.shields.io/badge/Flutter-3.47-02569B">
<img alt="dart" src="https://img.shields.io/badge/Dart-3.13-0175C2">
<img alt="license" src="https://img.shields.io/badge/license-MIT-green">
</p>

## v1.0.0 — the clean rebuild

The v1.0.0 app is a **complete rebuild from scratch** with the strongest,
most stable engine set available to Flutter today — same identity, same
features, fresh code:

| Layer | v2.x | v1.0.0 |
|---|---|---|
| PDF engine | pdfx 2.11 (Android `PdfRenderer` over a platform channel + a vendored fork + a 2.8k-line custom text parser) | **pdfrx on pdfium** — Google's Chrome PDF engine, called directly over FFI. No platform channel that can wedge, no custom parser: text extraction comes from pdfium itself |
| Database | Isar 3.1 (abandoned; pinned the toolchain to Flutter 3.29) | **Drift on SQLite** — actively maintained, type-safe, migrations |
| Toolchain | Flutter 3.29 (Isar ceiling) | **Flutter 3.47 stable / Dart 3.13** |
| Ink engine | perfect-freehand | perfect-freehand (kept — it is the best there is) |
| Vendored forks / overrides | 2 | **0** |

**Your data survives the update.** The app installs directly over any v2.x
release (same app id, same signing key), and on first launch it migrates the
old Isar database into Drift **in place, preserving every id** — notebooks,
pages, ink, elements, recordings, tags, folders, covers, settings and
imported PDFs all carry over. The legacy files are renamed `*.migrated` and
never touched again. A `.nanote` backup made by any version restores into
any other version (format v2, byte-compatible both directions).

**Why PDF rendering can't gray-out anymore.** The v2.x failures all traced
back to one fragile chain: pdfx marshalled renders over a platform channel
whose Android coroutine could die mid-render (an `OutOfMemoryError` escaped
its `Exception`-only catch, the reply was never delivered, and the Dart
future never completed — wedging a serialized queue forever after the first
page). v1.0.0 talks to pdfium **directly over FFI**: every call returns,
exceptions propagate, renders run on background workers, and the same page
can render concurrently. What survived from the v2.6.0 hardening is the part
that was right: a 1440px raster budget with an 8-entry LRU, ref-counted
image handles (pixels in use are never disposed), retry-with-backoff for
failed renders, and priority re-renders for visible pages.

**Verification:** 25 tests, all green — the multi-page regression suite
drives the real controller against a fake of pdfium's exact semantics
(every page of a 20-page document must render; a failing page must never
affect the others; retry, LRU eviction, close-during-render), the text-layer
suite checks view-space mapping + RTL visual/logical word order through
pdfrx's real formatter, and the persistence suite round-trips the `.nanote`
backup format with preserved ids.

## Feature map

| Area | What you get |
|---|---|
| **Library** | Edge tabs (color+emoji), nested folders, favorites, tags, trash (30-day retention, restore/purge/empty), instant search (titles + folders + tags + text-box content), sort (opened/modified/created/title × asc/desc), grid & list views, PDF import (each PDF page becomes a page background; original file stored untouched) |
| **Notebooks** | 12 built-in covers + custom cover image, 12 paper templates, 4 page sizes (A4 P/L, Letter P/L) + Infinity Paper, 8 paper colors |
| **Writing** | 5 pressure-sensitive pens (fountain, ballpoint, brush, fineliner, highlighter) via perfect-freehand, per-pen remembered color/width, 16-color palette + 5 favorites + custom hue/saturation wheel + recents, pressure curve (firm ↔ soft), highlighter 10–100% opacity that never self-darkens |
| **PDF** | Every page renders (pdfium), pinch-zoom re-renders at the right sharpness, text selection: long-press → Copy · Translate · Search the web · Highlight · Underline · Select text · Select all · Ask AI |
| **Erasing** | Stroke eraser (whole-stroke delete) + area eraser, 3 size presets, circle cursor |
| **Selection** | Lasso with polygon containment, move / scale / rotate (15° magnetism), floating action bar (delete, duplicate, copy, paste, bring-front, send-back) |
| **Elements** | Text boxes (6 Arabic-capable fonts, size, color, bold/italic/underline, align; searchable), 12 shape types with fill/opacity/grid-snap/aspect-lock, images (rotate/flip/crop), 8 built-in stickers + user PNG collection |
| **Shape recognition** | Draw & hold ~650 ms → line/triangle/rect/polygon/ellipse/star recognized (RDP + heuristics) → replaces ink as ONE undoable shape |
| **Ruler / Laser** | Draggable + rotatable ruler with edge snapping; comet-trail and timed laser in any color |
| **Pages** | Stable ink slots (ids, never visual index), add / duplicate / delete / reorder, bookmarks, titles, filmstrip + pages manager with live thumbnails |
| **Undo/redo** | 200 ops, sealed op hierarchy (ink, elements, transforms, shape-replace) |
| **Audio notes** | Record per page (AAC/m4a), live level meter, playback, sync replay (ink appears when it was written) |
| **Translation** | "Nanote" engine (MyMemory), Google, offline AR↔EN dictionary (~400 pairs), Ask AI (ChatGPT / Gemini / Claude) |
| **Electronic pen** | Live pen card (kind, pressure, tilt, buttons, report rate), 4 buttons × 4 patterns bound to 21 actions |
| **Export / Backup** | Page PNG @2×, whole-notebook PDF, share sheet; single-file `.nanote` backup/restore |
| **UI** | Arabic (RTL, Arabic-Indic numerals ٠١٢٣) + English, light/dark/system, left-handed mode, v1.9.1 design tokens (Nanote Blue, Lucide icons, Inter + Noto Sans Arabic) |

## Architecture

```
lib/
  main.dart                    bootstrap, theme, locale, routes
  src/
    theme/                     v1.9.1 tokens (ThemeExtension)
    i18n/                      AR/EN dictionaries + ValueNotifier<Lang>
    models/                    paper, tools, strokes, elements, settings
    controllers/
      stroke_engine.dart       THE engine — pages keyed by stable ink slot,
                               undo/redo, eraser, lasso, transforms
      viewport_controller.dart ONE Matrix4: screen = doc×scale + pan
      gesture_router.dart      raw Listener input: stylus/finger routing,
                               palm rejection, barrel-button patterns
      pdf_document_controller  pdfrx/pdfium + quality buckets + LRU(8) +
                               ref-counted handles + retry
      tool/library/audio/laser/shape_recognizer/settings/pen_bus
    persistence/               Drift (SQLite): one database, all tables;
                               repositories keep the v2.x API; entities
                               are plain classes
      migration/               one-time Isar→Drift data migration
    services/                  translate, export, backup, image cache
    workspace/                 painters, tiles, text layer, tool rail,
                               overlays, document workspace
    ui/                        library, creation, settings, panels
```

**Solved patterns baked in:** ink lives in page-point space converted through
the inverse viewport matrix (ink never drifts); the ink slot is the page's
stable id; per-page notifiers so drawing repaints only the touched page;
highlighters render per-(color,opacity) group inside one `saveLayer` with
MULTIPLY compositing (text stays readable at 100%); PDF renders are
bucket-quantized and settle after pinch so zooming doesn't thrash the
renderer.

## Getting the APK

1. Go to the **Actions** tab → latest successful **Android APK** run →
   **Artifacts** → `nanote-native-apk`.
   (Or download from **Releases** — tags `v*`.)
2. Transfer the APK to your phone and install it ("install unknown apps"
   must be allowed for your browser/file manager).
3. The CI build is signed with the permanent `nanote-release.keystore` when
   the repo's `NANOTE_KEYSTORE_BASE64` / `NANOTE_KEYSTORE_PASSWORD` /
   `NANOTE_KEY_ALIAS` / `NANOTE_KEY_PASSWORD` secrets are configured — the
   same key as every release since v2.5.1, so updates install directly.

## Building locally

```bash
flutter pub get
dart run build_runner build    # drift codegen (committed .g.dart also works)
flutter test                   # 25 tests
flutter build apk --release
```

Toolchain: Flutter 3.47.x stable. The `android/` folder is committed
(Gradle 9.3, AGP 9.1, Kotlin 2.4) including the legacy-plugin shim that
`isar_flutter_libs` (migration-only dependency) needs under AGP 8+ — see
`android/build.gradle.kts`.

## Privacy

Local-first: everything lives on the device (SQLite + files). Internet is
used ONLY for user-initiated translation (MyMemory) and Ask-AI/update
links. No accounts, no analytics, no server.
