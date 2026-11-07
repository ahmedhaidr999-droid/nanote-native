import 'dart:convert';

import 'package:drift/drift.dart';

import '../models/page_elements.dart';
import '../models/stroke.dart';
import 'app_db.dart';
import 'entities.dart';
import 'file_store.dart';

// The v2.x codebase defined these entities inside this file — keep the
// import surface identical for every consumer.
export 'entities.dart';
import 'library_repository.dart';

/// Ink + element persistence. Same public API as the Isar era — Drift-backed.
class StrokeRepository {
  StrokeRepository._();

  static final StrokeRepository I = StrokeRepository._();

  AppDb get _db => AppDb.db;

  Future<List<Stroke>> loadStrokes(int pageId) async {
    final rows = await (_db.select(_db.strokes)
          ..where((r) => r.pageId.equals(pageId))
          ..orderBy([(r) => OrderingTerm.asc(r.z)]))
        .get();
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
    final rows = await (_db.select(_db.elements)
          ..where((r) => r.pageId.equals(pageId))
          ..orderBy([(r) => OrderingTerm.asc(r.z)]))
        .get();
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
  Future<void> savePage(
      int pageId, List<Stroke> strokes, List<PageElement> elements) async {
    await _db.transaction(() async {
      await (_db.delete(_db.strokes)..where((r) => r.pageId.equals(pageId)))
          .go();
      await (_db.delete(_db.elements)..where((r) => r.pageId.equals(pageId)))
          .go();
      for (final s in strokes) {
        await _db.into(_db.strokes).insert(StrokesCompanion.insert(
              pageId: pageId,
              z: Value(s.z),
              data: Value(jsonEncode(s.toJson())),
            ));
      }
      for (final e in elements) {
        await _db.into(_db.elements).insert(ElementsCompanion.insert(
              pageId: pageId,
              z: Value(e.z),
              data: Value(jsonEncode(e.toJson())),
            ));
      }
    });
  }

  Future<void> deletePageInk(int pageId) async {
    await _db.transaction(() async {
      await (_db.delete(_db.strokes)..where((r) => r.pageId.equals(pageId)))
          .go();
      await (_db.delete(_db.elements)..where((r) => r.pageId.equals(pageId)))
          .go();
    });
  }

  /// Copies ink + elements from one page to another (page duplicate).
  /// New stroke ids avoid selection-id clashes; z is preserved.
  Future<void> duplicatePageInk(int fromPageId, int toPageId) async {
    final strokes = await loadStrokes(fromPageId);
    final elements = await loadElements(fromPageId);
    await _db.transaction(() async {
      for (final s in strokes) {
        final c = s.deepCopy();
        await _db.into(_db.strokes).insert(StrokesCompanion.insert(
              pageId: toPageId,
              z: Value(c.z),
              data: Value(jsonEncode(c.toJson())),
            ));
      }
      for (final e in elements) {
        final c = e.deepCopy();
        await _db.into(_db.elements).insert(ElementsCompanion.insert(
              pageId: toPageId,
              z: Value(c.z),
              data: Value(jsonEncode(c.toJson())),
            ));
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

  Future<List<StrokeEntity>> dumpStrokes() async {
    final rows = await (_db.select(_db.strokes)
          ..orderBy([(r) => OrderingTerm.asc(r.id)]))
        .get();
    return [for (final r in rows) r.toEntity()];
  }

  Future<List<ElementEntity>> dumpElements() async {
    final rows = await (_db.select(_db.elements)
          ..orderBy([(r) => OrderingTerm.asc(r.id)]))
        .get();
    return [for (final r in rows) r.toEntity()];
  }

  Future<void> restoreStrokes(List<StrokeEntity> rows) async {
    await _db.transaction(() async {
      for (final r in rows) {
        await _db.into(_db.strokes).insert(StrokesCompanion.insert(
              id: Value(r.id),
              pageId: r.pageId,
              z: Value(r.z),
              data: Value(r.data),
            ));
      }
    });
  }

  Future<void> restoreElements(List<ElementEntity> rows) async {
    await _db.transaction(() async {
      for (final r in rows) {
        await _db.into(_db.elements).insert(ElementsCompanion.insert(
              id: Value(r.id),
              pageId: r.pageId,
              z: Value(r.z),
              data: Value(r.data),
            ));
      }
    });
  }
}
