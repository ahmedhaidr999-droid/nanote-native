import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/paper.dart';
import '../models/stroke.dart';
import '../models/tool.dart';
import 'laser_controller.dart';
import 'settings_controller.dart';

/// Eraser behavior: whole-stroke hit testing vs. area erase.
enum EraserMode { stroke, area }

/// Remembered color + width of one pen kind.
class PenState {
  int color; // 0xAARRGGBB
  double size;

  PenState({required this.color, required this.size});

  PenState copyWith({int? color, double? size}) =>
      PenState(color: color ?? this.color, size: size ?? this.size);
}

/// App-wide tool state: current tool, per-pen color/width memory, palettes,
/// eraser / shape / laser / text defaults. Singleton: [ToolController.I].
class ToolController extends ChangeNotifier {
  ToolController._() {
    // Warm the singleton so pen memory is loaded as soon as settings are
    // ready (fire-and-forget; gesture router may touch us immediately).
    unawaited(ensureLoaded());
  }

  static final ToolController I = ToolController._();

  // ------------------------------------------------------------------ tool

  Tool _tool = Tool.fountain;

  /// Per-tool settings panel visibility (the tool rail toggles it: tap an
  /// inactive tool → select + OPEN its settings; tap the ACTIVE tool again →
  /// close the panel).
  bool settingsOpen = false;

  /// Current tool (setter notifies listeners).
  Tool get tool => _tool;
  set tool(Tool t) {
    if (_tool == t) return;
    _tool = t;
    notifyListeners();
  }

  /// Rail tap behavior: re-tapping the active tool toggles its settings
  /// panel; tapping a new tool selects it and opens the panel.
  void railTap(Tool t) {
    if (_tool == t) {
      settingsOpen = !settingsOpen;
    } else {
      _tool = t;
      settingsOpen = true;
    }
    notifyListeners();
  }

  void openSettings() {
    if (!settingsOpen) {
      settingsOpen = true;
      notifyListeners();
    }
  }

  void closeSettings() {
    if (settingsOpen) {
      settingsOpen = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------ pens

  /// Remembered color/size per pen kind, initialized from the v1.9.1
  /// [StrokeStyle.forKind] defaults (persisted via settings.penStates).
  Map<StrokeKind, PenState> pens = {
    for (final kind in StrokeKind.values)
      kind: PenState(
        color: _defaultColorFor(kind),
        size: StrokeStyle.forKind(kind, _defaultColorFor(kind)).size,
      ),
  };

  static int _defaultColorFor(StrokeKind kind) {
    switch (kind) {
      case StrokeKind.ballpoint:
        return 0xFF1E6FF2;
      case StrokeKind.highlighter:
        return 0xFFFFD84D;
      case StrokeKind.fountain:
      case StrokeKind.brush:
      case StrokeKind.fineliner:
        return 0xFF16233A;
    }
  }

  /// Per-pen state accessor (never null; falls back to fountain).
  PenState pen(StrokeKind kind) => pens[kind] ?? pens[StrokeKind.fountain]!;

  /// Favorite colors (ARGB ints, max 5).
  List<int> favoriteColors = [];

  /// Recently used colors, most recent first (max 8).
  List<int> recentColors = [];

  // ---------------------------------------------------------------- eraser

  EraserMode _eraserMode = EraserMode.stroke;

  /// Page-space eraser radius.
  double eraserRadius = 28;

  /// Eraser size presets (page-space radius).
  static const List<double> eraserPresets = [12, 28, 48];

  EraserMode get eraserMode => _eraserMode;

  set eraserMode(EraserMode m) {
    if (_eraserMode == m) return;
    _eraserMode = m;
    notifyListeners();
  }

  void setEraserRadius(double r) {
    final v = r < 6 ? 6.0 : (r > 96 ? 96.0 : r);
    if (v == eraserRadius) return;
    eraserRadius = v;
    notifyListeners();
  }

  /// Cycles the eraser radius through [eraserPresets].
  void cycleEraserPreset() {
    final idx = eraserPresets.indexOf(eraserRadius);
    eraserRadius = eraserPresets[(idx + 1) % eraserPresets.length];
    notifyListeners();
  }

  // ----------------------------------------------------------------- shape

  ShapeType shapeType = ShapeType.line;
  int shapeStrokeColor = 0xFF16233A;
  double shapeStrokeWidth = 2.4;
  int? shapeFillColor;
  double shapeFillOpacity = 0.25;
  bool shapeGridSnap = false;
  bool shapeAspectLock = false;
  int shapeSides = 5; // polygon 3..12

  void setShapeType(ShapeType t) {
    if (shapeType == t) return;
    shapeType = t;
    notifyListeners();
  }

  void setShapeStrokeColor(int c) {
    if (shapeStrokeColor == c) return;
    shapeStrokeColor = c;
    notifyListeners();
  }

  void setShapeStrokeWidth(double w) {
    final v = w < 0.5 ? 0.5 : (w > 24 ? 24.0 : w);
    if (v == shapeStrokeWidth) return;
    shapeStrokeWidth = v;
    notifyListeners();
  }

  void setShapeFillColor(int? c) {
    if (shapeFillColor == c) return;
    shapeFillColor = c;
    notifyListeners();
  }

  void setShapeFillOpacity(double o) {
    final v = o < 0.05 ? 0.05 : (o > 1 ? 1.0 : o);
    if (v == shapeFillOpacity) return;
    shapeFillOpacity = v;
    notifyListeners();
  }

  void setShapeGridSnap(bool v) {
    if (shapeGridSnap == v) return;
    shapeGridSnap = v;
    notifyListeners();
  }

  void setShapeAspectLock(bool v) {
    if (shapeAspectLock == v) return;
    shapeAspectLock = v;
    notifyListeners();
  }

  void setShapeSides(int n) {
    final v = n < 3 ? 3 : (n > 12 ? 12 : n);
    if (v == shapeSides) return;
    shapeSides = v;
    notifyListeners();
  }

  // ----------------------------------------------------------------- laser

  /// The laser pointer controller (laser settings live there).
  LaserController get laser => LaserController.I;

  // ------------------------------------------------------------------ text

  int textColor = 0xFF16233A;
  double textSize = 18;
  TextFontId textFont = TextFontId.system;
  bool textBold = false;
  bool textItalic = false;
  bool textUnderline = false;
  int textAlign = 0; // 0 start / 1 center / 2 end

  void setTextColor(int c) {
    if (textColor == c) return;
    textColor = c;
    notifyListeners();
  }

  void setTextSize(double s) {
    final v = s < 8 ? 8.0 : (s > 96 ? 96.0 : s);
    if (v == textSize) return;
    textSize = v;
    notifyListeners();
  }

  void setTextFont(TextFontId f) {
    if (textFont == f) return;
    textFont = f;
    notifyListeners();
  }

  void setTextBold(bool v) {
    if (textBold == v) return;
    textBold = v;
    notifyListeners();
  }

  void setTextItalic(bool v) {
    if (textItalic == v) return;
    textItalic = v;
    notifyListeners();
  }

  void setTextUnderline(bool v) {
    if (textUnderline == v) return;
    textUnderline = v;
    notifyListeners();
  }

  void setTextAlign(int a) {
    final v = a < 0 ? 0 : (a > 2 ? 2 : a);
    if (v == textAlign) return;
    textAlign = v;
    notifyListeners();
  }

  // ----------------------------------------------------------------- style

  /// Maps the current tool onto its pen kind. Non-pen tools fall back to the
  /// fountain pen (only pen tools actually begin strokes).
  StrokeKind _kindForTool(Tool t) {
    switch (t) {
      case Tool.fountain:
        return StrokeKind.fountain;
      case Tool.ballpoint:
        return StrokeKind.ballpoint;
      case Tool.brush:
        return StrokeKind.brush;
      case Tool.fineliner:
        return StrokeKind.fineliner;
      case Tool.highlighter:
        return StrokeKind.highlighter;
      case Tool.laser:
      case Tool.eraser:
      case Tool.lasso:
      case Tool.text:
      case Tool.shape:
      case Tool.image:
      case Tool.sticker:
      case Tool.pan:
        return StrokeKind.fountain;
    }
  }

  /// Full rendering style for new ink: current tool → pen kind → remembered
  /// color/size. The highlighter applies the global highlighter opacity.
  StrokeStyle currentStrokeStyle() {
    final kind = _kindForTool(_tool);
    final p = pen(kind);
    var style = StrokeStyle.forKind(kind, p.color).copyWith(size: p.size);
    if (kind == StrokeKind.highlighter) {
      final op = SettingsController.I.settings.highlighterOpacity;
      style = style.copyWith(opacity: op < 0.1 ? 0.1 : (op > 1.0 ? 1.0 : op));
    }
    return style;
  }

  // -------------------------------------------------------------- mutations

  /// Sets the color of the current pen (persists).
  void setPenColor(int color) {
    final p = pen(_kindForTool(_tool));
    if (p.color == color) return;
    p.color = color;
    notifyListeners();
    save();
  }

  /// Sets the size of the current pen (clamped 0.5..48, persists).
  void setPenSize(double size) {
    final p = pen(_kindForTool(_tool));
    final v = size < 0.5 ? 0.5 : (size > 48.0 ? 48.0 : size);
    if (p.size == v) return;
    p.size = v;
    notifyListeners();
    save();
  }

  /// Cycles to the next palette color for the current pen
  /// (INK_PALETTE for pens, HIGHLIGHTER_PALETTE for the highlighter).
  void cycleColorNext() {
    final kind = _kindForTool(_tool);
    final palette =
        kind == StrokeKind.highlighter ? HIGHLIGHTER_PALETTE : INK_PALETTE;
    final cur = pen(kind).color;
    var idx = -1;
    for (var i = 0; i < palette.length; i++) {
      if (palette[i].toARGB32() == cur) {
        idx = i;
        break;
      }
    }
    pen(kind).color = palette[(idx + 1) % palette.length].toARGB32();
    notifyListeners();
    save();
  }

  /// Increases the current pen width (step 0.4 below 5, else 1; 0.5..48).
  void widthUp() => _adjustWidth(1);

  /// Decreases the current pen width (step 0.4 below 5, else 1; 0.5..48).
  void widthDown() => _adjustWidth(-1);

  void _adjustWidth(int dir) {
    final p = pen(_kindForTool(_tool));
    final step = p.size < 5 ? 0.4 : 1.0;
    var next = p.size + dir * step;
    // Snap exactly onto the 5 boundary when stepping up across it.
    if (dir > 0 && p.size < 5 && next > 5) next = 5;
    next = (next * 10).roundToDouble() / 10;
    if (next < 0.5) next = 0.5;
    if (next > 48) next = 48;
    if (next == p.size) return;
    p.size = next;
    notifyListeners();
    save();
  }

  /// Pushes [color] to the front of the recent palette (dedupe, max 8).
  void addRecentColor(int color) {
    recentColors.removeWhere((c) => c == color);
    recentColors.insert(0, color);
    if (recentColors.length > 8) {
      recentColors.removeRange(8, recentColors.length);
    }
    notifyListeners();
    save();
  }

  /// Toggles [color] in the favorites (max 5; the oldest favorite is evicted
  /// first).
  void toggleFavoriteColor(int color) {
    if (favoriteColors.contains(color)) {
      favoriteColors.remove(color);
    } else {
      favoriteColors.add(color);
      if (favoriteColors.length > 5) {
        favoriteColors.removeRange(0, favoriteColors.length - 5);
      }
    }
    notifyListeners();
    save();
  }

  // ------------------------------------------------------------- persistence

  bool _loaded = false;
  Future<void>? _loading;

  /// Loads pen memory once (idempotent, memoized).
  Future<void> ensureLoaded() => _loading ??= load();

  /// Reads pen states + palettes from [SettingsController] settings.
  Future<void> load() async {
    try {
      await SettingsController.I.load();
    } catch (_) {
      // Settings unavailable — keep in-memory defaults.
    }
    final s = SettingsController.I.settings;
    try {
      final raw = s.penStates;
      for (final kind in StrokeKind.values) {
        final v = raw[kind.name];
        if (v is Map) {
          final c = v['c'];
          final sz = v['s'];
          if (c is num) pens[kind]?.color = c.toInt();
          if (sz is num) {
            final d = sz.toDouble();
            pens[kind]?.size = d < 0.5 ? 0.5 : (d > 48 ? 48 : d);
          }
        }
      }
      favoriteColors = List<int>.of(s.favoriteColors);
      if (favoriteColors.length > 5) {
        favoriteColors = favoriteColors.sublist(0, 5);
      }
      recentColors = List<int>.of(s.recentColors);
      if (recentColors.length > 8) {
        recentColors = recentColors.sublist(0, 8);
      }
    } catch (_) {
      // Corrupt entries — keep defaults for whatever failed to parse.
    }
    _loaded = true;
    notifyListeners();
  }

  /// Persists pen states + palettes. No-op before the first [load] completed
  /// so a racing mutation can never clobber stored settings with defaults.
  Future<void> save() async {
    if (!_loaded) return;
    final s = SettingsController.I.settings;
    s.penStates = {
      for (final e in pens.entries)
        e.key.name: {'c': e.value.color, 's': e.value.size},
    };
    s.favoriteColors = List<int>.of(favoriteColors);
    s.recentColors = List<int>.of(recentColors);
    await SettingsController.I.saveRaw();
  }
}
