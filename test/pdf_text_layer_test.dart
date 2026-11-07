// PDF text layer tests — the v1.0.0 word/line building on top of pdfrx's
// REAL PdfTextFormatter, fed with fake pdfium raw text (word fragments,
// directions, per-char rects, bottom-left origin). Verifies:
//   * view-space conversion (y flip),
//   * line grouping across \n,
//   * RTL visual-order detection (first stored word leftmost → reverse on
//     copy) vs logical storage (keep order),
//   * hit-testing.

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanote_native/src/workspace/pdf_text_layer.dart';
import 'package:pdfrx/pdfrx.dart';

/// Builds fake raw text exactly the way pdfium produces it: words in
/// CONTENT order, each with its rect in unrotated PDF space (origin
/// bottom-left, y up), separated by single spaces.
PdfPageRawText _rawText(
  List<({String text, PdfRect rect, PdfTextDirection dir})> words,
) {
  final full = StringBuffer();
  final charRects = <PdfRect>[];
  var first = true;
  for (final w in words) {
    if (!first) {
      full.write(' ');
      charRects.add(
          PdfRect(w.rect.left - 4, w.rect.top, w.rect.left - 4, w.rect.bottom));
    }
    first = false;
    for (final c in w.text.characters) {
      full.write(c);
      charRects.add(w.rect);
    }
  }
  return PdfPageRawText(full.toString(), charRects);
}

/// Minimal fake page serving raw text; `loadStructuredText()` (the REAL
/// pdfrx extension) runs the production formatter on it, then the service's
/// real page builder runs on the result.
class _FakeTextPage implements PdfPage {
  _FakeTextPage(this.w, this.h, this.raw);

  final double w;
  final double h;
  final PdfPageRawText raw;

  @override
  double get width => w;

  @override
  double get height => h;

  @override
  int get pageNumber => 1;

  @override
  PdfPageRotation get rotation => PdfPageRotation.none;

  @override
  bool get isLoaded => true;

  @override
  Future<PdfPageRawText?> loadText() async => raw;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<PdfTextPage> _build(PdfPageRawText raw,
    {double w = 595, double h = 842}) async {
  final page = _FakeTextPage(w, h, raw);
  final structured = await page.loadStructuredText();
  return PdfTextService.buildPageForTest(page, structured);
}

void main() {
  test('LTR line: words in view space, y flipped', () async {
    final page = await _build(_rawText([
      (
        text: 'Hello',
        rect: const PdfRect(50, 700, 120, 680),
        dir: PdfTextDirection.ltr
      ),
      (
        text: 'world',
        rect: const PdfRect(130, 700, 200, 680),
        dir: PdfTextDirection.ltr
      ),
    ]));

    expect(page.viewW, 595);
    expect(page.viewH, 842);
    expect(page.words.length, 2);
    final hello = page.words.first;
    expect(hello.text, 'Hello');
    expect(hello.x, closeTo(50, 0.5));
    // y flip: pdf top=700 → view top = 842-700 = 142
    expect(hello.y, closeTo(142, 0.5));
    expect(page.lines.length, 1);
    expect(page.lines.first.rtl, isFalse);

    // Hit-testing lands on the first word.
    final hit =
        PdfTextSelectionController.hitWordInPage(page, const Offset(60, 150));
    expect(hit, 0);
  });

  test('RTL VISUAL storage: line.rtl + visualOrder → copy reverses words',
      () async {
    // Visual storage: content order runs left→right on screen; the first
    // stored word is the LEFTMOST (a shaped-Arabic PDF written visually).
    final page = await _build(_rawText([
      (
        text: 'عالميا',
        rect: const PdfRect(50, 700, 110, 680),
        dir: PdfTextDirection.rtl
      ),
      (
        text: 'مرحبا',
        rect: const PdfRect(120, 700, 190, 680),
        dir: PdfTextDirection.rtl
      ),
    ]));

    expect(page.lines.length, 1);
    final line = page.lines.first;
    expect(line.rtl, isTrue);
    expect(line.visualOrder, isTrue,
        reason: 'first stored word (x=50) is LEFT of last (x=120) → visual');
    expect(page.words.first.text, 'عالميا');
    expect(page.words.last.text, 'مرحبا');
  });

  test('RTL LOGICAL storage: visualOrder false → copy keeps stored order',
      () async {
    // Logical storage: reading order; the first stored word is the
    // RIGHTMOST (how Chrome/Word export Arabic).
    final page = await _build(_rawText([
      (
        text: 'مرحبا',
        rect: const PdfRect(120, 700, 190, 680),
        dir: PdfTextDirection.rtl
      ),
      (
        text: 'عالميا',
        rect: const PdfRect(50, 700, 110, 680),
        dir: PdfTextDirection.rtl
      ),
    ]));

    final line = page.lines.first;
    expect(line.rtl, isTrue);
    expect(line.visualOrder, isFalse,
        reason: 'first stored word (x=120) is RIGHT of last (x=50) → logical');
  });

  test('multiple lines split at \\n and group words correctly', () async {
    final withNewlines = PdfPageRawText(
      'one\ntwo\nthree',
      [
        for (var i = 0; i < 3; i++) const PdfRect(50, 700, 90, 680),
        const PdfRect(50, 600, 50, 580), // the \n rect
        for (var i = 0; i < 3; i++) const PdfRect(50, 600, 90, 580),
        const PdfRect(50, 500, 50, 480), // the \n rect
        for (var i = 0; i < 5; i++) const PdfRect(50, 500, 110, 480),
      ],
    );
    final page = await _build(withNewlines);
    expect(page.words.length, 3);
    expect(page.lines.length, 3);
    expect(page.words.map((w) => w.text).toList(), ['one', 'two', 'three']);
  });

  test('empty page (scanned/image PDF) yields no words, no lines', () async {
    final page = await _build(PdfPageRawText('', const []));
    expect(page.words, isEmpty);
    expect(page.lines, isEmpty);
  });
}
