import 'dart:convert';
import 'package:isar/isar.dart';

import '../models/page_elements.dart';
import '../models/stroke.dart';
import 'app_db.dart';
import 'file_store.dart';
import 'library_repository.dart';

part 'stroke_repository.g.dart';

/// One committed ink stroke, stored as JSON for full fidelity
/// (style + points + audio sync + group).
@collection
class StrokeEntity {
  Id id = Isar.autoIncrement;

  /// The STABLE ink slot: PageEntity.id (never the visual index).
  int pageId = 0;

  /// Global z-order within the page (shared with elements).
  int z = 0;

  String data = '';

  StrokeEntity();

  StrokeEntity.of(this.pageId, this.z, this.data);
}

/// One page element (text / shape / image / sticker), stored as JSON.
@collection
class ElementEntity {
  Id id = Isar.autoIncrement;

  int pageId = 0;

  int z = 0;

  String data = '';

  ElementEntity();

  ElementEntity.of(this.pageId, this.z, this.data);
}

/// Ink + element persistence.
class StrokeRepository {
  StrokeRepository._();

  static final StrokeRepository I = StrokeRepository._();

  Isar get _db => AppDb.db;

  Future<List<Stroke>> loadStrokes(int pageId) async {
    final rows = await _db.strokeEntitys
        .filter()
        .pageIdEqualTo(pageId)
        .sortByZ()
        .findAll();
    final out = <Stroke>[];
    for (final r in rows) {
      try {
        final s = Stroke.fromJson(
            (jsonDecode(r.data) as Map).cast<String, dynamic>());
        StrokeIdGen.seedAbove(s.id);
        out.add(s);
      } catch (_) {
        // Corrupt row: skip rather than crash.
      }
    }
    return out;
  }

  Future<List<PageElement>> loadElements(int pageId) async {
    final rows = await _db.elementEntitys
        .filter()
        .pageIdEqualTo(pageId)
        .sortByZ()
        .findAll();
    final out = <PageElement>[];
    for (final r in rows) {
      try {
        final el = elementFromJson(
            (jsonDecode(r.data) as Map).cast<String, dynamic>());
        if (el != null) out.add(el);
      } catch (_) {
        // Corrupt row: skip.
      }
    }
    return out;
  }

  /// Full replace of a page's ink + elements.
  Future<void> savePage(int pageId, List<Stroke> strokes,
      List<PageElement> elements) async {
    await _db.writeTxn(() async {
      await _db.strokeEntitys.filter().pageIdEqualTo(pageId).deleteAll();
      await _db.elementEntitys.filter().pageIdEqualTo(pageId).deleteAll();
      for (final s in strokes) {
        await _db.strokeEntitys.put(StrokeEntity.of(pageId, s.z, jsonEncode(s.toJson())));
      }
      for (final e in elements) {
        await _db.elementEntitys.put(ElementEntity.of(pageId, e.z, jsonEncode(e.toJson())));
      }
    });
  }

  Future<void> deletePageInk(int pageId) async {
    await _db.writeTxn(() async {
      await _db.strokeEntitys.filter().pageIdEqualTo(pageId).deleteAll();
      await _db.elementEntitys.filter().pageIdEqualTo(pageId).deleteAll();
    });
  }

  /// Copies ink + elements from one page to another (page duplicate).
  /// New stroke ids avoid selection-id clashes; z is preserved.
  Future<void> duplicatePageInk(int fromPageId, int toPageId) async {
    final strokes = await loadStrokes(fromPageId);
    final elements = await loadElements(fromPageId);
    await _db.writeTxn(() async {
      for (final s in strokes) {
        final c = s.deepCopy();
        await _db.strokeEntitys
            .put(StrokeEntity.of(toPageId, c.z, jsonEncode(c.toJson())));
      }
      for (final e in elements) {
        final c = e.deepCopy();
        await _db.elementEntitys
            .put(ElementEntity.of(toPageId, c.z, jsonEncode(c.toJson())));
      }
    });
  }

  /// Removes files owned by a purged notebook (custom covers, imported pdf,
  /// recordings). Images referenced by ImageEls are also removed.
  Future<void> deleteNotebookFiles(
    NotebookEntity n,
    List<PageEntity> pages,
    List<RecordingEntity> recordings,
  ) async {
    try {
      if (n.coverImagePath != null) {
        await FileStore.deleteRelative(n.coverImagePath!);
      }
      if (n.pdfPath != null) {
        await FileStore.deleteRelative(n.pdfPath!);
      }
      for (final r in recordings) {
        await FileStore.deleteRelative(r.path);
      }
      // Delete images/stickers placed on the notebook's pages.
      for (final p in pages) {
        final elements = await loadElements(p.id);
        for (final e in elements) {
          if (e is ImageEl && e.src != null) {
            await FileStore.deleteRelative(e.src!);
          }
        }
      }
    } catch (_) {
      // Best effort.
    }
  }

  // ---------------------------------------------------------- backup dump

  Future<List<StrokeEntity>> dumpStrokes() async =>
      _db.strokeEntitys.filter().idGreaterThan(-1).findAll();

  Future<List<ElementEntity>> dumpElements() async =>
      _db.elementEntitys.filter().idGreaterThan(-1).findAll();

  Future<void> restoreStrokes(List<StrokeEntity> rows) async {
    await _db.writeTxn(() async {
      for (final r in rows) {
        await _db.strokeEntitys.put(r);
      }
    });
  }

  Future<void> restoreElements(List<ElementEntity> rows) async {
    await _db.writeTxn(() async {
      for (final r in rows) {
        await _db.elementEntitys.put(r);
      }
    });
  }
}
