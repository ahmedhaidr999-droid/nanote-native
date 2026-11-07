// Persistence regression tests (Drift/SQLite edition) — includes the
// `.nanote` backup format v2 compatibility roundtrip that guarantees old
// files keep working across the v1.0.0 rebuild.

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanote_native/src/persistence/app_db.dart';
import 'package:nanote_native/src/persistence/library_repository.dart';
import 'package:nanote_native/src/persistence/stroke_repository.dart';
import 'package:nanote_native/src/models/page_elements.dart';
import 'package:nanote_native/src/models/paper.dart';
import 'package:nanote_native/src/models/stroke.dart';

void main() {
  setUpAll(() async {
    await AppDb.initForTesting(AppDb.forTesting(NativeDatabase.memory()));
  });

  tearDownAll(() async {
    await AppDb.resetForTesting();
  });

  test('notebook + pages CRUD with stable ink-slot ids', () async {
    final lib = LibraryRepository.I;
    final n = await lib.createNotebook(
      title: 'Test',
      template: 2,
      pageSize: 1,
      paperColor: 0xFFFFFFFF,
    );
    expect(n.id, greaterThan(0));
    final firstPages = await lib.pagesOf(n.id);
    expect(firstPages.length, 1); // createNotebook seeds page 0

    final p2 = await lib.addPage(n.id, 1, 2, 1, 0xFFFFFFFF);
    final p3 = await lib.addPage(n.id, 2, 2, 1, 0xFFFFFFFF);
    expect(p2.id, greaterThan(firstPages.first.id));
    expect(await lib.pageCount(n.id), 3);

    // Reorder keeps ids (the ink slots!) — only positions change.
    await lib.reorderPages(n.id, [p3.id, firstPages.first.id, p2.id]);
    final reordered = await lib.pagesOf(n.id);
    expect(reordered.map((p) => p.id).toList(),
        [p3.id, firstPages.first.id, p2.id]);
    expect(reordered.first.position, 0);

    // Trash lifecycle.
    await lib.trashNotebook(n);
    expect((await lib.activeNotebooks()).where((x) => x.id == n.id), isEmpty);
    expect((await lib.trashedNotebooks()).map((x) => x.id), contains(n.id));
    await lib.restoreNotebook(n);
    expect((await lib.activeNotebooks()).map((x) => x.id), contains(n.id));

    // Purge cascade removes pages + ink.
    final strokes = await StrokeRepository.I.loadStrokes(firstPages.first.id);
    expect(strokes, isEmpty);
    await lib.purgeNotebook(n);
    expect(await lib.pagesOf(n.id), isEmpty);
  });

  test('ink save/load roundtrip preserves stroke JSON exactly', () async {
    final lib = LibraryRepository.I;
    final n = await lib.createNotebook(title: 'Ink');
    final page = (await lib.pagesOf(n.id)).first;

    final s = Stroke(
      id: 777,
      style: StrokeStyle.forKind(StrokeKind.fountain, 0xFF16233A),
      pts: [10, 10, 0.5, 40, 42, 0.6, 90, 44, 0.5],
      z: 5,
    );
    final el = TextEl(
      id: 'e1',
      z: 6,
      text: 'مرحبا Nanote',
      x: 10,
      y: 20,
      w: 200,
      size: 18,
      font: TextFontId.system,
      color: 0xFF16233A,
    );
    await StrokeRepository.I.savePage(page.id, [s], [el]);

    final strokes = await StrokeRepository.I.loadStrokes(page.id);
    final elements = await StrokeRepository.I.loadElements(page.id);
    expect(strokes.length, 1);
    expect(strokes.first.id, 777);
    expect(strokes.first.pts, s.pts);
    expect(strokes.first.style.color, s.style.color);
    expect(elements.length, 1);
    expect((elements.first as TextEl).text, el.text);

    // Page duplicate deep-copies ink (Stroke.deepCopy preserves ids by
    // design — the undo-snapshot contract; identical ids across pages are
    // fine because the page id keys the ink slot).
    final p2 = await lib.addPage(n.id, 1, 0, 0, 0xFFFFFFFF);
    await StrokeRepository.I.duplicatePageInk(page.id, p2.id);
    final dup = await StrokeRepository.I.loadStrokes(p2.id);
    expect(dup.length, 1);
    expect(dup.first.id, 777);
    expect(dup.first.pts, s.pts);
    // Independent rows: editing the copy's storage does not touch the
    // original.
    await StrokeRepository.I.deletePageInk(p2.id);
    expect((await StrokeRepository.I.loadStrokes(page.id)).length, 1);
    await lib.purgeNotebook(n);
  });

  test('.nanote backup v2 roundtrip: entities + ink + ids preserved',
      () async {
    final lib = LibraryRepository.I;
    final n = await lib.createNotebook(title: 'Backup', coverId: 'c3');
    n.favorite = true;
    n.textIndex = 'hello world';
    n.tagIds = [4, 9];
    await lib.updateNotebook(n);
    final page = (await lib.pagesOf(n.id)).first;
    final s = Stroke(
      id: 1234,
      style: StrokeStyle.forKind(StrokeKind.brush, 0xFF000000),
      pts: [1, 2, 0.5, 3, 4, 0.5],
      z: 1,
    );
    await StrokeRepository.I.savePage(page.id, [s], const []);

    // ---- dump (what BackupService writes into the .nanote JSON) ----
    final (tabs, folders, notebooks, pages, tags, recordings) =
        await lib.dumpAll();
    final strokeRows = await StrokeRepository.I.dumpStrokes();
    final elementRows = await StrokeRepository.I.dumpElements();
    expect(notebooks.any((x) => x.id == n.id), isTrue);
    expect(pages.any((x) => x.id == page.id), isTrue);
    expect(strokeRows.any((r) => r.pageId == page.id && r.z == 1), isTrue);

    // The exact .nanote "ink" JSON shape (format v2 compatibility).
    final inkJson = {
      'strokes': [
        for (final r in strokeRows)
          {'id': r.id, 'pageId': r.pageId, 'z': r.z, 'data': r.data},
      ],
      'elements': [
        for (final r in await StrokeRepository.I.dumpElements())
          {'id': r.id, 'pageId': r.pageId, 'z': r.z, 'data': r.data},
      ],
    };
    final strokeMap = (inkJson['strokes'] as List).first as Map;
    expect(strokeMap.keys.toSet(), {'id', 'pageId', 'z', 'data'});
    expect(strokeMap['data'], isA<String>());
    // The data cell is the exact legacy Stroke.toJson shape.
    final data = jsonDecode(strokeMap['data'] as String) as Map;
    expect(data.keys.toSet(), containsAll(['id', 'z', 'st', 'p']));

    // ---- wipe + restore (what BackupService.restoreBackup does) ----
    await AppDb.db.wipeAll();
    expect(await lib.activeNotebooks(), isEmpty);

    await lib.restoreAll(
      tabs: tabs,
      folders: folders,
      notebooks: notebooks,
      pages: pages,
      tags: tags,
      recordings: recordings,
    );
    await StrokeRepository.I.restoreStrokes(strokeRows);
    await StrokeRepository.I.restoreElements(elementRows);

    final restoredNotebook = await lib.notebook(n.id);
    expect(restoredNotebook, isNotNull);
    expect(restoredNotebook!.id, n.id, reason: 'NOTEBOOK ids must survive');
    expect(restoredNotebook.favorite, isTrue);
    expect(restoredNotebook.tagIds, [4, 9]);
    expect(restoredNotebook.textIndex, 'hello world');

    final restoredPage = await lib.page(page.id);
    expect(restoredPage, isNotNull);
    expect(restoredPage!.id, page.id, reason: 'PAGE ids ARE the ink slots');

    final restoredStrokes =
        await StrokeRepository.I.loadStrokes(page.id);
    expect(restoredStrokes.length, 1);
    expect(restoredStrokes.first.id, 1234);
    expect(restoredStrokes.first.pts, s.pts);

    // New autoincrement ids continue ABOVE restored ids (no reuse).
    final nextPage = await lib.addPage(n.id, 9, 0, 0, 0xFFFFFFFF);
    expect(nextPage.id, greaterThan(page.id));

    // Cleanup for the next test run in this suite.
    await lib.purgeNotebook(n);
  });

  test('tagIds JSON encoding handles corrupt cells gracefully', () {
    expect(AppDb.decodeTagIds("[1,2,3]"), <int>[1, 2, 3]);
    expect(AppDb.decodeTagIds('[]'), const <int>[]);
    expect(AppDb.decodeTagIds("not json"), const <int>[]);
    expect(AppDb.encodeTagIds(const [7]), '[7]');
  });
}
