import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/settings.dart';

/// Settings persistence: one JSON file in the app documents directory.
class SettingsStore {
  SettingsStore._();

  static final SettingsStore I = SettingsStore._();

  File? _file;

  Future<File> _resolve() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    final f = File(p.join(dir.path, 'nanote_settings.json'));
    if (!await f.exists()) {
      await f.writeAsString(jsonEncode(AppSettings().toJson()));
    }
    _file = f;
    return f;
  }

  Future<AppSettings> load() async {
    try {
      final f = await _resolve();
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return AppSettings();
      return AppSettings.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return AppSettings();
    }
  }

  Future<void> save(AppSettings s) async {
    try {
      final f = await _resolve();
      await f.writeAsString(jsonEncode(s.toJson()));
    } catch (_) {
      // Best effort.
    }
  }
}
