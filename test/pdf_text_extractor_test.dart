import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:nanote_native/src/services/pdf_text_extractor.dart';

/// Builds a minimal valid single-page PDF: standard Helvetica WITHOUT
/// /Widths (the case that needs the built-in AFM metrics), [differences]
/// optionally added to the font's encoding.
List<int> _buildSimplePdf(String contentOps, {String? differences}) {
  final enc = differences == null
      ? '/WinAnsiEncoding'
      : '<< /Differences $differences >>';
  final objs = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    'STREAM_PLACEHOLDER',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
        '/Encoding $enc >>',
  ];
  objs[3] = '<< /Length ${contentOps.length} >>\nstream\n$contentOps\nendstream';
  final out = StringBuffer();
  out.write('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objs.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objs[i]}\nendobj\n');
  }
  final xrefPos = out.length;
  out.write('xref\n0 ${objs.length + 1}\n');
  out.write('0000000000 65535 f \n');
  for (final o in offsets) {
    out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\n');
  out.write('startxref\n$xrefPos\n%%EOF\n');
  return out.toString().codeUnits;
}

void main() {
  test('extracts plain Latin text with correct word boxes', () {
    final pdf = _buildSimplePdf(
        'BT /F1 14 Tf 1 0 0 1 72 720 Tm (The quick brown fox.) Tj ET\n');
    final pages = extractPdfTextPages(Uint8List.fromList(pdf));
    expect(pages.length, 1);
    final p = pages[1]!;
    expect(p.viewW, closeTo(595, 0.5));
    expect(p.viewH, closeTo(842, 0.5));
    expect(p.words.length, 4);
    expect(p.words[0].text, 'The');
    expect(p.words[0].x, closeTo(72, 0.2));
    // Standard-font metrics: 'The' at 14pt Helvetica = 24.12pt wide. The
    // v2.5.0 bug (default 500 width + font-size-scaled boxes) reported 112.
    expect(p.words[0].w, closeTo(24.1, 0.6));
    expect(p.words[1].text, 'quick');
    expect(p.words[1].x, closeTo(100, 0.3));
    expect(p.words[3].text, 'fox.');
    expect(p.lines.length, 1);
    expect(p.lines[0].rtl, isFalse);
  });

  test('word spacing, char spacing, Tz and TJ kerning land exactly', () {
    final pdf = _buildSimplePdf(
        'BT /F1 14 Tf 5 Tw 2 Tc 1 0 0 1 72 720 Tm (a b c) Tj ET\n'
        'BT /F1 14 Tf 0 Tc 0 Tw 50 Tz 1 0 0 1 72 690 Tm (wide) Tj ET\n'
        'BT /F1 14 Tf 0 Tc 0 Tw 100 Tz 1 0 0 1 72 660 Tm '
            '[(ker)-40(ned)] TJ ET\n');
    final pages = extractPdfTextPages(Uint8List.fromList(pdf));
    final p = pages[1]!;
    final texts = p.words.map((w) => w.text).toSet();
    expect(texts, containsAll(['a', 'b', 'c', 'wide', 'kerned']));
    final wide = p.words.firstWhere((w) => w.text == 'wide');
    // 50% horizontal scale: 28.78pt advance × 0.5.
    expect(wide.w, closeTo(14.4, 0.8));
    final kerned = p.words.firstWhere((w) => w.text == 'kerned');
    expect(kerned.w, lessThan(45)); // kerning pulls glyphs together
  });

  test('visual-order shaped Arabic normalizes to logical text', () {
    // The shaped word مرحبا stored VISUAL left-to-right (the classic
    // arabic-reshaper/bidi generator output), delivered through
    // /Differences uniXXXX glyph names like real subset fonts.
    final pdf = _buildSimplePdf(
        'BT /F1 12 Tf 72 720 Td <8283848586> Tj ET\n',
        differences:
            '[130 /uniFE8D /uniFE91 /uniFEA3 /uniFEAE /uniFEE1]');
    final pages = extractPdfTextPages(Uint8List.fromList(pdf));
    final p = pages[1]!;
    expect(p.words, isNotEmpty);
    expect(p.words.first.text, 'مرحبا'); // logical, base letters
    expect(p.words.first.rtl, isTrue);
  });

  test('empty page and garbage input never throw', () {
    expect(extractPdfTextPages(Uint8List.fromList('not a pdf'.codeUnits)),
        isEmpty);
    final empty = _buildSimplePdf('1 0 0 1 0 0 cm\n');
    final pages = extractPdfTextPages(Uint8List.fromList(empty));
    expect(pages[1]!.words, isEmpty);
  });

  test('form xobjects are recursed (Chrome/Word style pages)', () {
    // Page content just invokes /Fx; the text lives INSIDE the form with
    // its own font resource and a translation matrix.
    final objs = <String>[
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
          '/Resources << /XObject << /Fx 6 0 R >> >> /Contents 4 0 R >>',
      '<< /Length 12 >>\nstream\nq /Fx Do Q\nendstream',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica '
          '/Encoding /WinAnsiEncoding >>',
      '<< /Type /XObject /Subtype /Form /BBox [0 0 400 100] '
          '/Matrix [1 0 0 1 50 600] /Resources << /Font << /F2 5 0 R >> >> '
          '/Length 52 >>\nstream\nBT /F2 12 Tf 0 0 Td (Nested form text) Tj '
          'ET\nendstream',
    ];
    final out = StringBuffer();
    out.write('%PDF-1.4\n');
    final offsets = <int>[];
    for (var i = 0; i < objs.length; i++) {
      offsets.add(out.length);
      out.write('${i + 1} 0 obj\n${objs[i]}\nendobj\n');
    }
    final xrefPos = out.length;
    out.write('xref\n0 ${objs.length + 1}\n');
    out.write('0000000000 65535 f \n');
    for (final o in offsets) {
      out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
    }
    out.write('trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\n');
    out.write('startxref\n$xrefPos\n%%EOF\n');
    final pages =
        extractPdfTextPages(Uint8List.fromList(out.toString().codeUnits));
    final p = pages[1]!;
    expect(p.words.map((w) => w.text).join(' '), 'Nested form text');
    // The form /Matrix translation (50, 600) must be reflected.
    expect(p.words.first.x, closeTo(50, 0.5));
  });
}
