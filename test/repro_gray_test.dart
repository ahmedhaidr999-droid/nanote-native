// TEMPORARY reproduction harness for the v2.5.1 gray-screen report.
// Full fidelity: real Isar DB, real PDF bytes on disk, mocked pdfx
// platform channel (page count/sizes/renders), real isolate extraction.
import 'dart:convert' show base64Decode;
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:nanote_native/src/controllers/pdf_document_controller.dart';
import 'package:nanote_native/src/controllers/settings_controller.dart';
import 'package:nanote_native/src/controllers/stroke_engine.dart';
import 'package:nanote_native/src/persistence/app_db.dart';
import 'package:nanote_native/src/persistence/file_store.dart';
import 'package:nanote_native/src/persistence/library_repository.dart';
import 'package:nanote_native/src/theme/nanote_theme.dart';
import 'package:nanote_native/src/workspace/document_workspace.dart';
import 'package:nanote_native/src/workspace/pdf_page_tile.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;

  @override
  Future<String?> getTemporaryPath() async => dir;

  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

/// A small PNG with visible content (white page + dark corner mark).
const String _pngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAHgAAACqCAYAAABmkov2AAABqklEQVR4nO3asQnAMBAEQVXhBtSF++9LrkA4MhbLDFz+sOmPRdr4+wC+JXCcwHECxwkctw18zfv48U7gOIHjBI4TOE7gOIHjBI4TOE7gOIHjBI4TOE7gOIHjBI4TOE7gOIHjBI4TOM5XZZzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHCRwncJzAcQLHPWO/CTpFj7NCAAAAAElFTkSuQmCC';

Uint8List _renderBytes() => Uint8List.fromList(base64Decode(_pngB64));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tmp = Directory.systemTemp.createTempSync('nanote_repro_gray');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    await Isar.initializeIsarCore(
      libraries: {Abi.linuxX64: '/tmp/isarlib/libisar.so'},
    );
    await AppDb.init();
    await SettingsController.I.load();
  });

  testWidgets('opening a PDF notebook renders page tiles', (tester) async {
    final bytes = _renderBytes();
    var docCounter = 0;
    var openCalls = 0;
    var renderCalls = 0;

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('io.scer.pdf_renderer'),
      (call) async {
        switch (call.method) {
          case 'open.document.file':
            openCalls++;
            docCounter++;
            return <dynamic, dynamic>{
              'id': 'doc$docCounter',
              'pagesCount': 3,
            };
          case 'open.page':
            final args = call.arguments as Map;
            return <dynamic, dynamic>{
              'id': 'p${args['documentId']}-${args['page']}',
              'width': 595.0,
              'height': 842.0,
            };
          case 'render':
            renderCalls++;
            return <dynamic, dynamic>{
              'width': 120,
              'height': 170,
              'data': bytes,
            };
          case 'close.page':
          case 'close.document':
            return null;
        }
        return null;
      },
    );

    final nbId = await tester.runAsync(() async {
      final pdfSrc = File('/tmp/pdfcorpus/reportlab_latin.pdf');
      final rel = await FileStore.importFile(pdfSrc, 'pdfs');
      final nb = await LibraryRepository.I.createNotebook(
        title: 'Repro',
        coverId: 'c1',
        folderId: null,
        template: 0,
        pageSize: 0,
        paperColor: 0xFFFFFFFF,
      );
      nb.pdfPath = rel;
      await LibraryRepository.I.updateNotebook(nb);
      return nb.id;
    });
    debugPrint('PHASE: notebook ready id=$nbId');

    // The REAL app shell (theme extensions included).
    Widget app() => MaterialApp(
          theme: NanoteTheme.light(),
          darkTheme: NanoteTheme.dark(),
          home: DocumentWorkspace(notebookId: nbId!),
        );

    await tester.pumpWidget(app());
    debugPrint('PHASE: first pump done (exception check next)');
    debugPrint('EXCEPTION1: ${tester.takeException()}');

    // Run the open pipeline under REAL time: pdfx channel, Isar, the
    // extraction isolate — then pump the frames it schedules.
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    });
    debugPrint('PHASE: waits done');
    debugPrint('EXCEPTION2: ${tester.takeException()}');
    debugPrint('PHASE: openCalls=$openCalls renderCalls=$renderCalls '
        'pdfOpen=${PdfDocumentController.I.isOpen} '
        'pages=${StrokeEngine.I.pages.length}');

    final tiles =
        tester.widgetList<PdfPageTile>(find.byType(PdfPageTile)).toList();
    debugPrint('PHASE: tile count=${tiles.length}');

    expect(tester.takeException(), isNull,
        reason: 'the workspace threw during build');
    expect(PdfDocumentController.I.isOpen, isTrue,
        reason: 'PDF controller failed to open the document');
    expect(StrokeEngine.I.pages.length, 3,
        reason: 'pages were not synced to the PDF count');
    expect(tiles, isNotEmpty, reason: 'no page tiles in the tree');
    expect(renderCalls, greaterThan(0), reason: 'no page was rendered');
  });
}
