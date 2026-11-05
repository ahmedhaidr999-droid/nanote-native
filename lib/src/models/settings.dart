/// App settings + electronic-pen shortcut bindings (20 actions).
///
/// Everything serializes to JSON (settings_store.dart).

enum PenAction {
  none,
  eraserHold,
  eraserToggle,
  pen,
  highlighter,
  laser,
  lasso,
  text,
  shape,
  pan,
  undo,
  redo,
  pagePrev,
  pageNext,
  colorNext,
  widthUp,
  widthDown,
  zoomIn,
  zoomOut,
  toggleToolbar,
  quickExport,
}

extension PenActionX on PenAction {
  static PenAction fromName(String? s) {
    for (final a in PenAction.values) {
      if (a.name == s) return a;
    }
    return PenAction.none;
  }

  String get key => 'penAction.${name}';
}

/// The four physical buttons of an electronic pen.
enum PenButton { barrel, barrel2, eraserEnd, doubleTap }

extension PenButtonX on PenButton {
  String get key => 'penButton.${name}';
}

/// Button press patterns.
enum PenPattern { press, pressWriting, double, long }

extension PenPatternX on PenPattern {
  String get key => 'penPattern.${name}';
}

class AppSettings {
  // Appearance
  String themeMode; // light | dark | system
  String lang; // ar | en
  String numerals; // latin (default) | hindi (٠١٢٣)
  bool leftHanded;

  // Writing
  double pressureCurve; // gamma 0.4..2.5
  bool drawWithFinger;
  bool shapeDetection;
  double highlighterOpacity; // 0.1..1.0
  int autosaveDelayMs; // 0 | 1000 | 5000

  // Pen shortcuts: "<button>.<pattern>" -> action name
  Map<String, String> penActions;
  bool penShortcutsEnabled;

  // Translation
  String translateEngine; // nanote | google
  String translateTarget; // auto | ar | en
  String aiService; // chatgpt | gemini | claude

  // Remembered pen states (kind name -> {color, size}) + palette memory
  Map<String, dynamic> penStates;

  /// Selected KIND inside the grouped pen tool (fountain/ballpoint/…).
  String penKind;

  /// Favorite colors PER tool group (pens / highlighter / laser), up to 8.
  List<int> penFavorites;
  List<int> highlighterFavorites;
  List<int> laserFavorites;

  List<int> favoriteColors; // legacy — migrates into penFavorites
  List<int> recentColors;

  AppSettings({
    this.themeMode = 'system',
    this.lang = 'en',
    this.numerals = 'latin',
    this.leftHanded = false,
    this.pressureCurve = 1.0,
    this.drawWithFinger = false,
    this.shapeDetection = true,
    this.highlighterOpacity = 0.4,
    this.autosaveDelayMs = 1000,
    Map<String, String>? penActions,
    this.penShortcutsEnabled = true,
    this.translateEngine = 'nanote',
    this.translateTarget = 'auto',
    this.aiService = 'chatgpt',
    Map<String, dynamic>? penStates,
    String? penKind,
    List<int>? penFavorites,
    List<int>? highlighterFavorites,
    List<int>? laserFavorites,
    List<int>? favoriteColors,
    List<int>? recentColors,
  })  : penActions = penActions ?? _defaults(),
        penStates = penStates ?? {},
        penKind = penKind ?? 'fountain',
        penFavorites = penFavorites ?? [],
        highlighterFavorites = highlighterFavorites ?? [],
        laserFavorites = laserFavorites ?? [],
        favoriteColors = favoriteColors ?? [],
        recentColors = recentColors ?? [];

  static Map<String, String> _defaults() => {
        'barrel.press': 'eraserHold',
        'barrel.pressWriting': 'eraserHold',
        'barrel.double': 'eraserToggle',
        'barrel.long': 'undo',
        'barrel2.press': 'pan',
        'barrel2.pressWriting': 'none',
        'barrel2.double': 'redo',
        'barrel2.long': 'none',
        'eraserEnd.press': 'eraserToggle',
        'eraserEnd.pressWriting': 'eraserToggle',
        'eraserEnd.double': 'none',
        'eraserEnd.long': 'none',
        'doubleTap.press': 'none',
        'doubleTap.pressWriting': 'none',
        'doubleTap.double': 'pan',
        'doubleTap.long': 'none',
      };

  PenAction actionFor(PenButton button, PenPattern pattern) =>
      PenActionX.fromName(penActions['${button.name}.${pattern.name}']);

  void setAction(PenButton button, PenPattern pattern, PenAction action) {
    penActions['${button.name}.${pattern.name}'] = action.name;
  }

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode,
        'lang': lang,
        'numerals': numerals,
        'leftHanded': leftHanded,
        'pressureCurve': pressureCurve,
        'drawWithFinger': drawWithFinger,
        'shapeDetection': shapeDetection,
        'highlighterOpacity': highlighterOpacity,
        'autosaveDelayMs': autosaveDelayMs,
        'penActions': penActions,
        'penShortcutsEnabled': penShortcutsEnabled,
        'translateEngine': translateEngine,
        'translateTarget': translateTarget,
        'aiService': aiService,
        'penStates': penStates,
        'penKind': penKind,
        'penFavorites': penFavorites,
        'highlighterFavorites': highlighterFavorites,
        'laserFavorites': laserFavorites,
        'favoriteColors': favoriteColors,
        'recentColors': recentColors,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        themeMode: (j['themeMode'] as String?) ?? 'system',
        lang: (j['lang'] as String?) ?? 'en',
        numerals: (j['numerals'] as String?) ?? 'latin',
        leftHanded: j['leftHanded'] as bool? ?? false,
        pressureCurve: (j['pressureCurve'] as num?)?.toDouble() ?? 1.0,
        drawWithFinger: j['drawWithFinger'] as bool? ?? false,
        shapeDetection: j['shapeDetection'] as bool? ?? true,
        highlighterOpacity: (j['highlighterOpacity'] as num?)?.toDouble() ?? 0.4,
        autosaveDelayMs: (j['autosaveDelayMs'] as num?)?.toInt() ?? 1000,
        penActions: ((j['penActions'] as Map?)?.cast<String, String>() ?? _defaults()),
        penShortcutsEnabled: j['penShortcutsEnabled'] as bool? ?? true,
        translateEngine: (j['translateEngine'] as String?) ?? 'nanote',
        translateTarget: (j['translateTarget'] as String?) ?? 'auto',
        aiService: (j['aiService'] as String?) ?? 'chatgpt',
        penStates: (j['penStates'] as Map?)?.cast<String, dynamic>() ?? {},
        penKind: (j['penKind'] as String?) ?? 'fountain',
        penFavorites: ((j['penFavorites'] as List?) ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
        highlighterFavorites: ((j['highlighterFavorites'] as List?) ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
        laserFavorites: ((j['laserFavorites'] as List?) ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
        favoriteColors: ((j['favoriteColors'] as List?) ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
        recentColors: ((j['recentColors'] as List?) ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
      );
}
