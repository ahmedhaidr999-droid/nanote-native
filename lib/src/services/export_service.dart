import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../controllers/pdf_document_controller.dart';
import '../controllers/stroke_engine.dart';
import '../i18n/strings.dart';
import '../models/page_elements.dart';
import '../models/paper.dart';
import '../persistence/file_store.dart';
import '../workspace/elements_painter.dart';
import 'image_cache.dart';

/// Renders pages through the shared painters (PaperPainter +
/// PageContentPainter) and shares them as PNG / PDF files.
///
/// Both methods let exceptions propagate (after cleaning up intermediate
/// raster resources) so the caller can surface an error snackbar.
class ExportService {
  ExportService._();

  /// Renders one page at 2x (paper + template + PDF background + ink +
  /// elements) and shares it as a PNG.
  static Future<void> sharePagePng(StrokeEngine engine, PageMeta page) async {
    await engine.ensureLoaded(page.id);
    final file = await _writePagePng(engine, page);
    await Share.shareXFiles([XFile(file.path)], text: S.t('exportPng'));
  }

  /// Renders every page at 2x and shares a one-sheet-per-page PDF.
  static Future<void> shareNotebookPdf(StrokeEngine engine) async {
    await sharePagesPdf(engine, engine.pages);
  }

  /// Renders the given pages at 2x and shares a one-sheet-per-page PDF
  /// (used by the pages manager for SELECTED pages).
  static Future<void> sharePagesPdf(
      StrokeEngine engine, List<PageMeta> pages) async {
    if (pages.isEmpty) return;
    for (final p in pages) {
      await engine.ensureLoaded(p.id);
    }
    final pdf = pw.Document();
    final rendered = <ui.Image>[];
    try {
      for (final meta in pages) {
        final size = meta.effectiveSize;
        final image = await _rasterPage(engine, meta, 2.0);
        rendered.add(image);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) continue;
        final pngBytes = data.buffer.asUint8List();
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(size.width * 0.75, size.height * 0.75),
            margin: pw.EdgeInsets.zero,
            build: (_) =>
                pw.Image(pw.MemoryImage(pngBytes), fit: pw.BoxFit.fill),
          ),
        );
      }
      final bytes = await pdf.save();
      final file = File(p.join(
        Directory.systemTemp.path,
        'nanote_${engine.notebook?.id ?? 'notebook'}_pages.pdf',
      ));
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: S.t('exportPdf'));
    } finally {
      for (final image in rendered) {
        image.dispose();
      }
    }
  }

  // ---------------------------------------------------------------- private

  static Future<File> _writePagePng(StrokeEngine engine, PageMeta page) async {
    final image = await _rasterPage(engine, page, 2.0);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('PNG encoding failed for page ${page.id}');
      }
      final file = File(
        p.join(Directory.systemTemp.path, 'nanote_page_${page.id}.png'),
      );
      await file.writeAsBytes(data.buffer.asUint8List());
      return file;
    } finally {
      image.dispose();
    }
  }

  /// Draws one page into a fresh picture at [scale] and rasterizes it.
  /// The canvas is pre-scaled so painters keep working in 1x page units.
  static Future<ui.Image> _rasterPage(
      StrokeEngine engine, PageMeta page, double scale) async {
    final size = page.effectiveSize;
    final ink = engine.pageInk(page.id);
    await _prewarmImages(ink);

    // Make sure elements can resolve their images synchronously while the
    // content painter runs (the workspace normally installs this hook).
    ElementsPainter.resolveImage ??= AppImageCache.peekSync;

    final paperColor = paperColorFrom(page.paperColor);
    final template = TemplateIdX.fromId(page.template);
    final pdfImage = await _pdfBackground(engine, page);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale, scale);

    if (pdfImage != null) {
      // PDF render as the background; PageContentPainter(paintPaper: false)
      // then draws the template lines + ink above it (mirrors the on-screen
      // layering for imported-PDF notebooks).
      canvas.drawImageRect(
        pdfImage,
        Rect.fromLTWH(
            0, 0, pdfImage.width.toDouble(), pdfImage.height.toDouble()),
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..filterQuality = FilterQuality.medium,
      );
      PageContentPainter(
        template: template,
        paperColor: paperColor,
        pageSize: size,
        ink: ink,
        paintPaper: false,
      ).paint(canvas, size);
    } else {
      // PageContentPainter paints the paper + template + ink itself.
      PageContentPainter(
        template: template,
        paperColor: paperColor,
        pageSize: size,
        ink: ink,
      ).paint(canvas, size);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (size.width * scale).round(),
      (size.height * scale).round(),
    );
    // toImage() rasterizes from its own reference; release the Dart-side
    // picture so its native display list is not held until the next GC.
    picture.dispose();
    return image;
  }

  /// Decodes every image element of the page so the content painter finds
  /// them in the cache during its (synchronous) paint pass.
  static Future<void> _prewarmImages(PageInk ink) async {
    for (final el in ink.elements) {
      if (el is ImageEl && el.src != null) {
        if (AppImageCache.peekSync(el.src!) != null) continue;
        try {
          await AppImageCache.loadByRel(el.src!);
        } catch (e, st) {
          // Broken image: the painter will simply skip it — but leave a
          // trace so a missing file is debuggable.
          debugPrint('ExportService: image "${el.src}" failed to load: '
              '$e\n$st');
        }
      }
    }
  }

  /// Best-effort PDF background for imported-PDF notebooks: the pdfrx page
  /// image (from PdfDocumentController), drawn under the ink. Skips silently
  /// when unavailable.
  static Future<ui.Image?> _pdfBackground(
      StrokeEngine engine, PageMeta page) async {
    final pdfPath = engine.notebook?.pdfPath;
    if (pdfPath == null) return null;
    try {
      final ctrl = PdfDocumentController.I;
      final abs = await FileStore.tryResolve(pdfPath);
      if (abs == null) return null;
      if (ctrl.currentPath != abs.path || !ctrl.isOpen) {
        final opened = await ctrl.open(abs.path);
        if (!opened) return null;
      }
      final index = engine.pages.indexOf(page);
      if (index < 0 || index + 1 > ctrl.pageCount) return null;
      final bmp = await ctrl.pageImage(index + 1, 2.0);
      return bmp?.image;
    } catch (e, st) {
      debugPrint('ExportService: PDF background unavailable for page '
          '${page.id}: $e\n$st');
      return null;
    }
  }
}
