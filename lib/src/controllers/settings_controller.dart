import 'package:flutter/foundation.dart';

import '../i18n/strings.dart';
import '../models/settings.dart';
import '../models/stroke.dart';
import '../persistence/settings_store.dart';

/// App-wide settings state.
class SettingsController extends ChangeNotifier {
  SettingsController._();

  static final SettingsController I = SettingsController._();

  AppSettings settings = AppSettings();

  bool _loaded = false;

  bool get loaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    settings = await SettingsStore.I.load();
    S.lang.value = settings.lang == 'ar' ? Lang.ar : Lang.en;
    S.hindiDigits = settings.numerals == 'hindi';
    PressureCurve.gamma = settings.pressureCurve;
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    await SettingsStore.I.save(settings);
  }

  Future<void> setThemeMode(String mode) async {
    settings.themeMode = mode;
    await _persist();
    notifyListeners();
  }

  Future<void> setLang(String lang) async {
    settings.lang = lang;
    S.lang.value = lang == 'ar' ? Lang.ar : Lang.en;
    await _persist();
    notifyListeners();
  }

  /// Numerals: 'latin' (default) or 'hindi' (٠١٢٣) for Arabic display.
  Future<void> setNumerals(String v) async {
    settings.numerals = v == 'hindi' ? 'hindi' : 'latin';
    S.hindiDigits = settings.numerals == 'hindi';
    await _persist();
    notifyListeners();
  }

  Future<void> setLeftHanded(bool v) async {
    settings.leftHanded = v;
    await _persist();
    notifyListeners();
  }

  /// §0 rail dock ('start' | 'end' | 'top' | 'bottom').
  Future<void> setRailPosition(String v) async {
    settings.railPosition = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setPressureCurve(double gamma) async {
    settings.pressureCurve = gamma;
    PressureCurve.gamma = gamma;
    await _persist();
    notifyListeners();
  }

  Future<void> setDrawWithFinger(bool v) async {
    settings.drawWithFinger = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setShapeDetection(bool v) async {
    settings.shapeDetection = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setHighlighterOpacity(double v) async {
    settings.highlighterOpacity = v.clamp(0.1, 1.0);
    await _persist();
    notifyListeners();
  }

  Future<void> setAutosaveDelayMs(int v) async {
    settings.autosaveDelayMs = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setPenAction(PenButton button, PenPattern pattern, PenAction action) async {
    settings.setAction(button, pattern, action);
    await _persist();
    notifyListeners();
  }

  Future<void> setPenShortcutsEnabled(bool v) async {
    settings.penShortcutsEnabled = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setTranslateEngine(String v) async {
    settings.translateEngine = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setTranslateTarget(String v) async {
    settings.translateTarget = v;
    await _persist();
    notifyListeners();
  }

  Future<void> setAiService(String v) async {
    settings.aiService = v;
    await _persist();
    notifyListeners();
  }

  /// Saves pen/palette memory owned by the tool controller.
  Future<void> saveRaw() async {
    await _persist();
  }
}
