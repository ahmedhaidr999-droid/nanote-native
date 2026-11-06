// Pure-Dart PDF text extractor for Nanote Native.
//
// The app renders PDF pages as RASTER images via pdfx (Android
// PdfRenderer) — there is no text layer, so long-press selection needs a
// separate extraction pass that recovers the text TOGETHER with the
// coordinates of every glyph.
//
// This file implements a minimal but robust PDF reader:
//   * object lexer/parser (numbers, names, strings, arrays, dicts, streams)
//   * cross-reference resolution — classic tables AND xref streams
//     (PDF 1.5+), hybrid files and object streams (/ObjStm)
//   * stream decoding — FlateDecode (zlib), ASCIIHexDecode, ASCII85Decode,
//     PNG predictors (xref streams)
//   * page-tree walk with resource/box/rotate inheritance
//   * font maps — simple fonts (WinAnsi/Standard/MacRoman encodings +
//     /Differences + glyph names incl. uniXXXX) and composite Type0 fonts
//     (Identity-H) with /ToUnicode CMaps (bfchar/bfrange) and /W widths
//   * content-stream interpreter for the text operators (BT/ET, Tf, Tm,
//     Td/TD/T*, Tj/TJ/'/") with full text-matrix tracking
//   * word/line grouping (column-aware, RTL-aware) and /Rotate-aware
//     mapping to the SAME oriented top-left coordinate space the raster
//     uses, so selection rectangles land exactly on the visible text.
//
// Everything runs inside a background isolate (see PdfTextService) — the
// UI is never blocked. All output types are plain data (no dart:ui types)
// so they cross isolate boundaries cheaply.

import 'dart:io';
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// Public data model (plain, isolate-sendable)
// ---------------------------------------------------------------------------

/// One selectable word. Coordinates are in VIEW POINTS: the page rotated
/// per /Rotate, origin at the TOP-LEFT, y down — the exact space the
/// raster tile occupies (pdfx/Android report page sizes in the same
/// space).
class PdfTWord {
  final String text;
  final double x, y, w, h;
  final bool rtl;

  const PdfTWord(this.text, this.x, this.y, this.w, this.h, this.rtl);
}

/// One text line: the word index range [start, end] (inclusive), the
/// baseline segment A→B (view points) and the union rect.
class PdfTLine {
  final int start, end;
  final double ax, ay, bx, by; // baseline A→B (view points)
  final double x, y, w, h;
  final bool rtl;

  /// True when the line's words sit in VISUAL order (correctly rendered
  /// RTL: the first logical word is the rightmost) — copying must reverse
  /// the word order to restore the logical sentence. False for naive
  /// unshaped storage, which keeps logical order left-to-right.
  final bool visualOrder;

  const PdfTLine(this.start, this.end, this.ax, this.ay, this.bx, this.by,
      this.x, this.y, this.w, this.h, this.rtl, this.visualOrder);
}

/// Extracted text of one page (empty when the page has no extractable
/// text — scanned pages, images, encrypted files).
class PdfTextPage {
  final List<PdfTWord> words;
  final List<PdfTLine> lines;

  /// The view size (points) the coordinates above are relative to — used
  /// to normalize against pdfx's reported page size.
  final double viewW, viewH;

  static const PdfTextPage empty =
      PdfTextPage(const [], const [], 1, 1);

  const PdfTextPage(this.words, this.lines, this.viewW, this.viewH);
}

bool _isRtlText(String s) {
  var rtl = 0, ltr = 0;
  for (final r in s.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) ||
        (r >= 0xFB50 && r <= 0xFDFF) ||
        (r >= 0xFE70 && r <= 0xFEFF)) {
      rtl++;
    } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) {
      ltr++;
    }
  }
  return rtl > ltr;
}

/// Extracts the text of EVERY page of the PDF in [bytes].
/// Returns {} for encrypted or unparseable files — never throws.
Map<int, PdfTextPage> extractPdfTextPages(Uint8List bytes) {
  try {
    final doc = _PdfDoc(bytes);
    if (doc.encrypted) return {};
    return doc.extractAll();
  } catch (_) {
    return const {};
  }
}

// ---------------------------------------------------------------------------
// Byte reader + PDF object lexer
// ---------------------------------------------------------------------------

bool _isWsByte(int c) =>
    c == 0x00 ||
    c == 0x09 ||
    c == 0x0A ||
    c == 0x0C ||
    c == 0x0D ||
    c == 0x20;

bool _isDelimiter(int c) =>
    c == 0x28 || c == 0x29 || c == 0x3C || c == 0x3E || c == 0x5B ||
    c == 0x5D || c == 0x7B || c == 0x7D || c == 0x2F || c == 0x25;

bool _isTokenBreak(int c) => _isWsByte(c) || _isDelimiter(c);

class _Bytes {
  final Uint8List data;
  int pos = 0;
  _Bytes(this.data);

  bool get eof => pos >= data.length;
  int peek() => eof ? -1 : data[pos];
  int read() => eof ? -1 : data[pos++];

  void skipWs() {
    while (!eof) {
      final c = data[pos];
      if (c == 0x25) {
        // comment → end of line
        while (!eof && data[pos] != 0x0A && data[pos] != 0x0D) {
          pos++;
        }
      } else if (_isWsByte(c)) {
        pos++;
      } else {
        return;
      }
    }
  }
}

/// Byte-safe keyword match at [pos] (used by the CMap parser).
bool _matchesAt(Uint8List d, int pos, String s) {
  if (pos < 0 || pos + s.length > d.length) return false;
  for (var i = 0; i < s.length; i++) {
    if (d[pos + i] != s.codeUnitAt(i)) return false;
  }
  return true;
}

/// A name object (without the leading slash).
class _PdfName {
  final String value;
  const _PdfName(this.value);
  @override
  bool operator ==(Object other) => other is _PdfName && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => '/$value';
}

/// Indirect reference "12 0 R".
class _Ref {
  final int num, gen;
  const _Ref(this.num, this.gen);
}

/// Stream object: dict + RAW (undecoded) bytes.
class _PStream {
  final Map<Object, Object> dict;
  final Uint8List raw;
  const _PStream(this.dict, this.raw);
}

/// Marker for an explicit null inside dicts (Dart maps can't distinguish
/// a null value from a missing key).
class _Null {
  const _Null();
}

/// Parses ONE object at the reader position. Returns: num | String
/// (literal) | Uint8List (hex) | _PdfName | _Ref | List | Map | _PStream
/// | bool | null | String keyword (bare word — callers interpret).
Object? _parseObject(_Bytes r) {
  r.skipWs();
  if (r.eof) return null;
  final c = r.peek();
  if (c == 0x28) return _parseLiteralString(r);
  if (c == 0x3C) {
    r.read();
    if (r.peek() == 0x3C) {
      r.read();
      return _parseDict(r);
    }
    return _parseHexString(r);
  }
  if (c == 0x5B) {
    r.read();
    final out = <Object?>[];
    while (true) {
      r.skipWs();
      if (r.eof) break;
      if (r.peek() == 0x5D) {
        r.read();
        break;
      }
      out.add(_parseObject(r));
    }
    return out;
  }
  if (c == 0x2F) {
    r.read();
    final sb = StringBuffer();
    while (!r.eof) {
      final ch = data_c(r);
      if (_isTokenBreak(ch)) break;
      if (ch == 0x23) {
        r.pos++;
        var hex = 0;
        var n = 0;
        while (n < 2 && !r.eof) {
          final h = _hexVal(r.data[r.pos]);
          if (h < 0) break;
          hex = hex * 16 + h;
          r.pos++;
          n++;
        }
        sb.writeCharCode(hex);
      } else {
        sb.writeCharCode(ch);
        r.pos++;
      }
    }
    return _PdfName(sb.toString());
  }
  if (c == 0x29 || c == 0x5D || c == 0x3E || c == 0x7D) {
    r.read(); // stray closer — skip defensively
    return null;
  }

  // Bare token: number or keyword.
  final start = r.pos;
  while (!r.eof && !_isTokenBreak(r.data[r.pos])) {
    r.pos++;
  }
  if (r.pos == start) return null;
  final tok = String.fromCharCodes(r.data.sublist(start, r.pos));
  final first = tok.codeUnitAt(0);
  final isNumeric = (first >= 0x30 && first <= 0x39) ||
      first == 0x2B ||
      first == 0x2D ||
      first == 0x2E;
  if (isNumeric) {
    final v = double.tryParse(tok);
    if (v != null) {
      // "N G R" indirect reference? (only in document bodies)
      final save = r.pos;
      r.skipWs();
      final t2 = _readToken(r);
      if (t2 != null) {
        final g = double.tryParse(t2);
        if (g != null) {
          r.skipWs();
          final t3 = _readToken(r);
          if (t3 == 'R') return _Ref(v.toInt(), g.toInt());
        }
      }
      r.pos = save;
      return v == v.roundToDouble() && v.abs() < 9e15 ? v.toInt() : v;
    }
  }
  switch (tok) {
    case 'true':
      return true;
    case 'false':
      return false;
    case 'null':
      return null;
  }
  return tok; // bare keyword — callers interpret
}

int data_c(_Bytes r) => r.data[r.pos];

/// Reads the next bare token WITHOUT indirect-ref lookahead.
String? _readToken(_Bytes r) {
  final start = r.pos;
  while (!r.eof && !_isTokenBreak(r.data[r.pos])) {
    r.pos++;
  }
  if (r.pos == start) return null;
  return String.fromCharCodes(r.data.sublist(start, r.pos));
}

Object? _parseLiteralString(_Bytes r) {
  r.read(); // (
  final out = BytesBuilder();
  var depth = 1;
  while (!r.eof) {
    final c = r.read();
    if (c == 0x5C) {
      final e = r.read();
      switch (e) {
        case 0x6E:
          out.addByte(0x0A);
          break;
        case 0x72:
          out.addByte(0x0D);
          break;
        case 0x74:
          out.addByte(0x09);
          break;
        case 0x62:
          out.addByte(0x08);
          break;
        case 0x66:
          out.addByte(0x0C);
          break;
        case 0x28:
          out.addByte(0x28);
          break;
        case 0x29:
          out.addByte(0x29);
          break;
        case 0x5C:
          out.addByte(0x5C);
          break;
        case 0x0D:
          if (r.peek() == 0x0A) r.read();
          break;
        case 0x0A:
          break;
        default:
          if (e >= 0x30 && e <= 0x37) {
            var oct = e - 0x30;
            var n = 1;
            while (n < 3) {
              final d = r.peek();
              if (d < 0x30 || d > 0x37) break;
              oct = oct * 8 + (r.read() - 0x30);
              n++;
            }
            out.addByte(oct & 0xFF);
          } else if (e >= 0) {
            out.addByte(e);
          }
      }
    } else if (c == 0x28) {
      depth++;
      out.addByte(c);
    } else if (c == 0x29) {
      depth--;
      if (depth == 0) break;
      out.addByte(c);
    } else {
      out.addByte(c);
    }
  }
  return String.fromCharCodes(out.takeBytes());
}

Uint8List _parseHexString(_Bytes r) {
  final out = BytesBuilder();
  var hi = -1;
  while (!r.eof) {
    final c = r.read();
    if (c == 0x3E) break;
    if (_isWsByte(c)) continue;
    final v = _hexVal(c);
    if (v < 0) continue;
    if (hi < 0) {
      hi = v;
    } else {
      out.addByte(hi * 16 + v);
      hi = -1;
    }
  }
  if (hi >= 0) out.addByte(hi * 16);
  return out.takeBytes();
}

int _hexVal(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  return -1;
}

Map<Object, Object>? _parseDict(_Bytes r) {
  final out = <Object, Object>{};
  while (true) {
    r.skipWs();
    if (r.eof) return null;
    if (r.peek() == 0x3E) {
      r.read();
      if (r.peek() == 0x3E) {
        r.read();
        break;
      }
      continue;
    }
    final key = _parseObject(r);
    if (key is! _PdfName) continue;
    final value = _parseObject(r);
    out[key] = value ?? const _Null();
  }
  return out;
}

// ---------------------------------------------------------------------------
// Document: xref, objects, streams
// ---------------------------------------------------------------------------

class _PageDef {
  final Map<Object, Object> dict;
  _PageDef(this.dict);
}

/// Placeholder for an object whose bytes sit at a file offset (type-1).
class _Unparsed {
  final String offset;
  const _Unparsed(this.offset);
}

/// Object stored inside an object stream (type-2).
class _InObjStm {
  final int stm, idx;
  const _InObjStm(this.stm, this.idx);
}

class _PdfDoc {
  final _Bytes r;
  final Map<int, Object?> _objects = {};
  final Set<int> _loading = {};
  bool encrypted = false;
  Map<Object, Object>? root;
  List<_PageDef> pages = [];
  Map<Object, Object>? _trailer;
  final Map<int, Map<int, Object?>> _objStmCache = {};

  _PdfDoc(Uint8List data) : r = _Bytes(data) {
    _loadXrefChain();
    if (encrypted) return;
    root = _resolveIndirect(_trailer?[_PdfName('Root')]) as Map<Object, Object>?;
    if (root == null) _scanForObjects();
    _collectPages();
  }

  // ------------------------------------------------------------ xref chain

  void _loadXrefChain() {
    final xrefOff = _findStartXref();
    if (xrefOff < 0) {
      _scanForObjects();
      return;
    }
    final visited = <int>{};
    var off = xrefOff;
    while (off > 0 && off < r.data.length && visited.add(off)) {
      final prev = _loadXrefAt(off);
      if (prev == null) break;
      off = prev;
    }
    if (_trailer == null) _scanForObjects();
    final enc = _trailer?[_PdfName('Encrypt')];
    if (enc != null && enc is! _Null && enc is! bool) encrypted = true;
  }

  int _findStartXref() {
    final d = r.data;
    var start = d.length - 2048;
    if (start < 0) start = 0;
    for (var i = d.length - 10; i >= start; i--) {
      if (d[i] == 0x73 && d[i + 1] == 0x74 && d[i + 2] == 0x61 &&
          d[i + 3] == 0x72 && d[i + 4] == 0x74 && d[i + 5] == 0x78 &&
          d[i + 6] == 0x72 && d[i + 7] == 0x65 && d[i + 8] == 0x66) {
        final rr = _Bytes(d);
        rr.pos = i + 9;
        rr.skipWs();
        final tok = _readToken(rr);
        return tok == null ? -1 : int.tryParse(tok) ?? -1;
      }
    }
    return -1;
  }

  /// Loads one xref section (classic table OR xref stream) at [offset].
  /// Returns the /Prev offset (0 when none), null on failure.
  int? _loadXrefAt(int offset) {
    final rr = _Bytes(r.data);
    rr.pos = offset;
    rr.skipWs();
    final save = rr.pos;
    final n1 = _readToken(rr);
    final n2 = _readToken(rr);
    final kw = _readToken(rr);
    var isObj = n1 != null && n2 != null && kw == 'obj';
    if (isObj) {
      final obj = _parseObject(rr);
      if (obj is _PStream) {
        final prev = _loadXrefStream(obj);
        _mergeTrailer(obj.dict);
        return prev;
      }
    }
    // Classic "xref" table (rewind to the section start).
    rr.pos = save;
    rr.skipWs();
    if (!_matchesAt(r.data, rr.pos, 'xref')) return null;
    rr.pos += 4;
    var prev = 0;
    while (true) {
      rr.skipWs();
      if (rr.eof) break;
      final peekS = rr.pos;
      final first = _readToken(rr);
      if (first == null) break;
      if (first == 'trailer') {
        // _parseDict expects the position right AFTER the opening '<<'
        // (it is normally called from _parseObject's map branch, which
        // consumes both '<' first).
        rr.skipWs();
        if (rr.peek() == 0x3C) {
          rr.read();
          if (rr.peek() == 0x3C) rr.read();
        }
        final t = _parseDict(rr);
        if (t != null) {
          _mergeTrailer(t);
          final xr = _resolveNum(t[_PdfName('XRefStm')]);
          if (xr != null && xr > 0) {
            // Hybrid file: also load the referenced xref stream.
            final rr2 = _Bytes(r.data)..pos = xr.toInt();
            final a = _readToken(rr2);
            final b = _readToken(rr2);
            final c = _readToken(rr2);
            if (a != null && b != null && c == 'obj') {
              final obj = _parseObject(rr2);
              if (obj is _PStream) {
                _loadXrefStream(obj);
                _mergeTrailer(obj.dict);
              }
            }
          }
          final p = _resolveNum(t[_PdfName('Prev')]);
          if (p != null) prev = p.toInt();
        }
        break;
      }
      final start = int.tryParse(first);
      if (start == null) {
        rr.pos = peekS + 1;
        continue;
      }
      rr.skipWs();
      final cntTok = _readToken(rr);
      final cnt = cntTok == null ? null : int.tryParse(cntTok);
      if (cnt == null) break;
      for (var i = 0; i < cnt; i++) {
        rr.skipWs();
        final offTok = _readToken(rr);
        rr.skipWs();
        final genTok = _readToken(rr);
        rr.skipWs();
        final typeTok = _readToken(rr);
        if (offTok == null || genTok == null || typeTok == null) break;
        final objNum = start + i;
        if (typeTok.startsWith('n')) {
          _objects.putIfAbsent(objNum, () => _Unparsed(offTok));
        } else {
          _objects.putIfAbsent(objNum, () => null);
        }
      }
    }
    return prev;
  }

  void _mergeTrailer(Map<Object, Object> t) {
    _trailer ??= {};
    _trailer!.addAll(t);
  }

  /// Parses an xref STREAM. Returns the /Prev offset (0 = none).
  int _loadXrefStream(_PStream s) {
    final dict = s.dict;
    final data = _decodeStream(s);
    if (data == null) return 0;
    final wArr = _resolveIndirect(dict[_PdfName('W')]);
    if (wArr is! List || wArr.length < 3) return 0;
    final w1 = _resolveNum(wArr[0])?.toInt() ?? 0;
    final w2 = _resolveNum(wArr[1])?.toInt() ?? 0;
    final w3 = _resolveNum(wArr[2])?.toInt() ?? 0;
    final size = _resolveNum(dict[_PdfName('Size')])?.toInt() ?? 0;
    var index = <int>[0, size];
    final idxArr = _resolveIndirect(dict[_PdfName('Index')]);
    if (idxArr is List && idxArr.length >= 2 && idxArr.length.isEven) {
      index = [for (final v in idxArr) _resolveNum(v)?.toInt() ?? 0];
    }
    final rowLen = w1 + w2 + w3;
    if (rowLen <= 0) return 0;
    var p = 0;
    for (var i = 0; i + 1 < index.length; i += 2) {
      final first = index[i];
      final count = index[i + 1];
      for (var j = 0; j < count; j++) {
        if (p + rowLen > data.length) break;
        final type = _readBE(data, p, w1);
        final f2 = _readBE(data, p + w1, w2);
        final f3 = _readBE(data, p + w1 + w2, w3);
        p += rowLen;
        final objNum = first + j;
        if (type == 0) {
          _objects.putIfAbsent(objNum, () => null);
        } else if (type == 1) {
          _objects.putIfAbsent(objNum, () => _Unparsed('$f2'));
        } else if (type == 2) {
          _objects.putIfAbsent(objNum, () => _InObjStm(f2, f3));
        }
      }
    }
    final prev = _resolveNum(dict[_PdfName('Prev')]);
    return prev?.toInt() ?? 0;
  }

  static int _readBE(Uint8List d, int off, int len) {
    var v = 0;
    for (var i = 0; i < len; i++) {
      v = v * 256 + d[off + i];
    }
    return v;
  }

  /// Brute-force "N G obj" scan (damaged files / missing xref).
  void _scanForObjects() {
    final d = r.data;
    for (var i = 0; i + 5 < d.length; i++) {
      if (d[i] != 0x6F || d[i + 1] != 0x62 || d[i + 2] != 0x6A) continue;
      final nums = _twoNumsBefore(d, i);
      if (nums == null) continue;
      final rr = _Bytes(d)..pos = i + 3;
      final parsed = _parseObject(rr);
      _objects[nums.$1] = parsed; // later (newer) duplicates win
      if (parsed is Map<Object, Object>) {
        final t = parsed[_PdfName('Type')];
        if (t == _PdfName('Catalog')) root ??= parsed;
      }
      if (parsed is _PStream) {
        final t = parsed.dict[_PdfName('Type')];
        if (t == _PdfName('XRef')) _mergeTrailer(parsed.dict);
      }
    }
  }

  static (int, int)? _twoNumsBefore(Uint8List d, int objIdx) {
    var j = objIdx - 1;
    while (j >= 0 && d[j] == 0x20) {
      j--;
    }
    var gEnd = j;
    while (j >= 0 && d[j] >= 0x30 && d[j] <= 0x39) {
      j--;
    }
    final g = int.tryParse(
        j == gEnd ? '' : String.fromCharCodes(d.sublist(j + 1, gEnd + 1)));
    if (g == null) return null;
    j--;
    while (j >= 0 && d[j] == 0x20) {
      j--;
    }
    var nEnd = j;
    while (j >= 0 && d[j] >= 0x30 && d[j] <= 0x39) {
      j--;
    }
    final n = int.tryParse(
        j == nEnd ? '' : String.fromCharCodes(d.sublist(j + 1, nEnd + 1)));
    if (n == null) return null;
    return (n, g);
  }

  // ------------------------------------------------------------ object load

  double? _resolveNum(Object? v) {
    final x = _resolveIndirect(v);
    return x is num ? x.toDouble() : null;
  }

  Object? _resolveIndirect(Object? v) {
    var hops = 0;
    while (v is _Ref && hops++ < 32) {
      v = object(v.num);
    }
    return v;
  }

  Object? object(int num) {
    if (_loading.contains(num)) return null; // cycle guard
    final cached = _objects[num];
    if (cached is! _Unparsed && cached is! _InObjStm) return cached;
    _loading.add(num);
    try {
      if (cached is _Unparsed) {
        final off = int.tryParse(cached.offset);
        if (off == null || off < 0 || off >= r.data.length) {
          _objects[num] = null;
          return null;
        }
        final parsed = _parseAtOffset(off);
        _objects[num] = parsed;
        return parsed;
      }
      if (cached is _InObjStm) {
        final stmNum = cached.stm;
        var contained = _objStmCache[stmNum];
        if (contained == null) {
          contained = {};
          final stm = _parseAtOffset(_scanObjectOffset(stmNum));
          if (stm is _PStream) {
            final data = _decodeStream(stm);
            final n = _resolveNum(stm.dict[_PdfName('N')]);
            final first = _resolveNum(stm.dict[_PdfName('First')]);
            if (data != null && n != null && first != null) {
              contained = _parseObjStm(data, n.toInt(), first.toInt());
            }
          }
          _objStmCache[stmNum] = contained;
        }
        final v = contained[cached.idx];
        _objects[num] = v;
        return v;
      }
    } finally {
      _loading.remove(num);
    }
    return null;
  }

  /// Parses the object that starts at [off] ("N G obj" expected).
  Object? _parseAtOffset(int off) {
    if (off < 0 || off >= r.data.length) return null;
    final rr = _Bytes(r.data)..pos = off;
    rr.skipWs();
    _readToken(rr); // object number
    rr.skipWs();
    _readToken(rr); // generation
    rr.skipWs();
    final kw = _readToken(rr);
    if (kw != 'obj') return null;
    final parsed = _parseObject(rr);
    if (parsed is Map<Object, Object>) {
      final save = rr.pos;
      rr.skipWs();
      final skw = _readToken(rr);
      if (skw == 'stream') {
        if (rr.peek() == 0x0D) rr.read();
        if (rr.peek() == 0x0A) rr.read();
        var len = 0;
        final lenV = _resolveIndirect(parsed[_PdfName('Length')]);
        if (lenV is num && lenV >= 0) {
          len = lenV.toInt();
        } else {
          len = _findStreamEnd(rr);
        }
        final end = (rr.pos + len).clamp(0, r.data.length);
        return _PStream(
            parsed, Uint8List.sublistView(r.data, rr.pos, end));
      }
      rr.pos = save;
    }
    return parsed;
  }

  int _scanObjectOffset(int num) {
    final d = r.data;
    // Fast path: exact "num 0 obj".
    final target = '$num 0 obj';
    for (var i = 0; i + target.length <= d.length; i++) {
      if (d[i] != target.codeUnitAt(0)) continue;
      var ok = true;
      for (var j = 1; j < target.length; j++) {
        if (d[i + j] != target.codeUnitAt(j)) {
          ok = false;
          break;
        }
      }
      if (ok && (i == 0 || _isTokenBreak(d[i - 1]))) return i;
    }
    // Slow path: any generation.
    for (var i = 0; i + 5 < d.length; i++) {
      if (d[i] != 0x6F || d[i + 1] != 0x62 || d[i + 2] != 0x6A) continue;
      final nums = _twoNumsBefore(d, i);
      if (nums != null && nums.$1 == num) return i + 3;
    }
    return -1;
  }

  Map<int, Object?> _parseObjStm(Uint8List data, int count, int first) {
    final out = <int, Object?>{};
    final header = _Bytes(data);
    final pairs = <(int, int)>[];
    for (var i = 0; i < count; i++) {
      header.skipWs();
      final numTok = _readToken(header);
      header.skipWs();
      final offTok = _readToken(header);
      final num = numTok == null ? null : int.tryParse(numTok);
      final off = offTok == null ? null : int.tryParse(offTok);
      if (num == null || off == null) break;
      pairs.add((num, off));
    }
    for (final (num, off) in pairs) {
      try {
        final rr = _Bytes(data)..pos = first + off;
        out[num] = _parseObject(rr);
      } catch (_) {
        out[num] = null;
      }
    }
    return out;
  }

  int _findStreamEnd(_Bytes rr) {
    final d = r.data;
    for (var i = rr.pos; i + 9 <= d.length; i++) {
      if (d[i] == 0x65 && d[i + 1] == 0x6E && d[i + 2] == 0x64 &&
          d[i + 3] == 0x73 && d[i + 4] == 0x74 && d[i + 5] == 0x72 &&
          d[i + 6] == 0x65 && d[i + 7] == 0x61 && d[i + 8] == 0x6D) {
        var end = i;
        while (end > rr.pos &&
            (d[end - 1] == 0x0A || d[end - 1] == 0x0D || d[end - 1] == 0x20)) {
          end--;
        }
        return end - rr.pos;
      }
    }
    return d.length - rr.pos;
  }

  // ------------------------------------------------------------ page tree

  void _collectPages() {
    final rootPages = _resolveIndirect(root?[_PdfName('Pages')]);
    if (rootPages is Map<Object, Object>) {
      _walkPages(rootPages, {});
    }
  }

  void _walkPages(Map<Object, Object> node, Map<Object, Object> inherited) {
    // Inherited attributes (boxes, rotate, resources) under the node's own
    // values — the node itself carries /Contents, /Type etc.
    final merged = Map<Object, Object>.of(inherited);
    merged.addAll(node);
    final t = node[_PdfName('Type')];
    if (t == _PdfName('Page') || node.containsKey(_PdfName('Contents'))) {
      pages.add(_PageDef(merged));
      return;
    }
    final kids = _resolveIndirect(node[_PdfName('Kids')]);
    if (kids is List) {
      for (final k in kids) {
        final kid = _resolveIndirect(k);
        if (kid is Map<Object, Object>) _walkPages(kid, merged);
      }
    }
  }

  // ------------------------------------------------------------ extraction

  Map<int, PdfTextPage> extractAll() {
    final out = <int, PdfTextPage>{};
    for (var i = 0; i < pages.length; i++) {
      out[i + 1] = _extractPage(pages[i]);
    }
    return out;
  }

  PdfTextPage _extractPage(_PageDef page) {
    try {
      var box = _resolveIndirect(page.dict[_PdfName('CropBox')]);
      box ??= _resolveIndirect(page.dict[_PdfName('MediaBox')]);
      double bx = 0, by = 0, bw = 612, bh = 792;
      if (box is List && box.length == 4) {
        final v = [
          _resolveNum(box[0]) ?? 0,
          _resolveNum(box[1]) ?? 0,
          _resolveNum(box[2]) ?? 0,
          _resolveNum(box[3]) ?? 0
        ];
        final x0 = v[0] < v[2] ? v[0] : v[2];
        final x1 = v[0] < v[2] ? v[2] : v[0];
        final y0 = v[1] < v[3] ? v[1] : v[3];
        final y1 = v[1] < v[3] ? v[3] : v[1];
        bx = x0;
        by = y0;
        bw = x1 - x0;
        bh = y1 - y0;
      }
      final rotate =
          (((_resolveNum(page.dict[_PdfName('Rotate')]) ?? 0).toInt()) % 360 +
                  360) %
              360;

      final contents = _resolveIndirect(page.dict[_PdfName('Contents')]);
      final bytes = BytesBuilder();
      if (contents is _PStream) {
        final d = _decodeStream(contents);
        if (d != null) bytes.add(d);
      } else if (contents is List) {
        for (final c in contents) {
          final s = _resolveIndirect(c);
          if (s is _PStream) {
            final d = _decodeStream(s);
            if (d != null) bytes.add(d);
          }
        }
      }
      final content = bytes.takeBytes();
      if (content.isEmpty) return PdfTextPage.empty;

      final fonts = <String, _FontInfo>{};
      final xobjs = <String, _PStream>{};
      final res = _resolveIndirect(page.dict[_PdfName('Resources')]);
      if (res is Map<Object, Object>) {
        final fd = _resolveIndirect(res[_PdfName('Font')]);
        if (fd is Map<Object, Object>) {
          fd.forEach((k, v) {
            if (k is! _PdfName) return;
            final f = _resolveIndirect(v);
            if (f is Map<Object, Object>) {
              fonts[k.value] = _FontInfo.parse(this, f);
            }
          });
        }
        final xd = _resolveIndirect(res[_PdfName('XObject')]);
        if (xd is Map<Object, Object>) {
          xd.forEach((k, v) {
            if (k is! _PdfName) return;
            final s = _resolveIndirect(v);
            if (s is _PStream) xobjs[k.value] = s;
          });
        }
      }
      if (fonts.isEmpty && xobjs.isEmpty) return PdfTextPage.empty;

      final glyphs = _interpretContent(content, this, fonts, xobjs);
      if (glyphs.isEmpty) return PdfTextPage.empty;
      return _buildPage(glyphs, bx, by, bw, bh, rotate);
    } catch (_) {
      return PdfTextPage.empty;
    }
  }

  // -------------------------------------------------------- stream decoding

  Uint8List? _decodeStream(_PStream s) {
    Uint8List data = s.raw;
    final filters = _resolveIndirect(s.dict[_PdfName('Filter')]);
    final parms = s.dict[_PdfName('DecodeParms')] ?? s.dict[_PdfName('DP')];
    List<Object?> filterList;
    List<Object?> parmList;
    if (filters is List) {
      filterList = filters;
      parmList = parms is List ? parms : List.filled(filters.length, parms);
    } else if (filters is _PdfName) {
      filterList = [filters];
      parmList = [parms];
    } else {
      return data;
    }
    for (var i = 0; i < filterList.length; i++) {
      final f = filterList[i];
      if (f is! _PdfName) continue;
      final pr = _resolveIndirect(parmList.length > i ? parmList[i] : null);
      switch (f.value) {
        case 'FlateDecode':
        case 'Fl':
          try {
            data = Uint8List.fromList(
                ZLibDecoder().convert(data.toList(growable: false)));
          } catch (_) {
            try {
              data = Uint8List.fromList(
                  ZLibDecoder(raw: true).convert(data.toList(growable: false)));
            } catch (_) {
              return null;
            }
          }
          data = _applyPredictor(data, pr);
          break;
        case 'ASCIIHexDecode':
        case 'AHx':
          data = _asciiHexDecode(data);
          break;
        case 'ASCII85Decode':
        case 'A85':
          final d = _ascii85Decode(data);
          if (d == null) return null;
          data = d;
          break;
        default:
          return null; // LZW / DCT / CCITT / RunLength — unsupported
      }
    }
    return data;
  }

  Uint8List _applyPredictor(Uint8List data, Object? parms) {
    if (parms is! Map<Object, Object>) return data;
    final pred = _resolveNum(parms[_PdfName('Predictor')]);
    if (pred == null || pred < 10) return data;
    final cols =
        (_resolveNum(parms[_PdfName('Columns')]) ?? 1).toInt();
    final colors =
        (_resolveNum(parms[_PdfName('Colors')]) ?? 1).toInt();
    final bpc =
        (_resolveNum(parms[_PdfName('BitsPerComponent')]) ?? 8).toInt();
    final bpp = (colors * bpc + 7) ~/ 8;
    final rowLen = (cols * colors * bpc + 7) ~/ 8;
    if (rowLen <= 0 || data.isEmpty) return data;
    final rows = data.length ~/ (rowLen + 1);
    final out = Uint8List(rows * rowLen);
    var src = 0;
    var dst = 0;
    final prev = Uint8List(rowLen);
    for (var row = 0; row < rows; row++) {
      final ft = data[src++];
      for (var i = 0; i < rowLen; i++) {
        final cur = data[src++];
        var v = cur;
        switch (ft) {
          case 1:
            v = cur + (i >= bpp ? out[dst + i - bpp] : 0);
            break;
          case 2:
            v = cur + prev[i];
            break;
          case 3:
            v = cur + ((i >= bpp ? out[dst + i - bpp] : 0) + prev[i]) ~/ 2;
            break;
          case 4:
            final a = i >= bpp ? out[dst + i - bpp] : 0;
            final b = prev[i];
            final c = i >= bpp ? prev[i - bpp] : 0;
            final pp = a + b - c;
            final pa = (pp - a).abs(), pb = (pp - b).abs(), pc = (pp - c).abs();
            v = cur + ((pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c));
            break;
          default:
            v = cur;
        }
        out[dst + i] = v & 0xFF;
        prev[i] = v & 0xFF;
      }
      dst += rowLen;
    }
    return out;
  }

  static Uint8List _asciiHexDecode(Uint8List data) {
    final out = BytesBuilder();
    var hi = -1;
    for (final c in data) {
      if (c == 0x3E) break;
      if (_isWsByte(c)) continue;
      final v = _hexVal(c);
      if (v < 0) continue;
      if (hi < 0) {
        hi = v;
      } else {
        out.addByte(hi * 16 + v);
        hi = -1;
      }
    }
    return out.takeBytes();
  }

  static Uint8List? _ascii85Decode(Uint8List data) {
    var start = 0;
    if (data.length >= 2 && data[0] == 0x3C && data[1] == 0x7E) start = 2;
    final out = BytesBuilder();
    final group = List<int>.filled(5, 0);
    var n = 0;
    for (var i = start; i < data.length; i++) {
      final c = data[i];
      if (c == 0x7E && i + 1 < data.length && data[i + 1] == 0x3E) break;
      if (_isWsByte(c)) continue;
      if (c == 0x7A && n == 0) {
        out.add([0, 0, 0, 0]);
        continue;
      }
      if (c < 0x21 || c > 0x75) return null;
      group[n++] = c - 0x21;
      if (n == 5) {
        var v = 0;
        for (final g in group) {
          v = v * 85 + g;
        }
        out.add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
        n = 0;
      }
    }
    if (n > 0) {
      for (var i = n; i < 5; i++) {
        group[i] = 0x54; // 'u'
      }
      var v = 0;
      for (final g in group) {
        v = v * 85 + g;
      }
      final b = [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
      out.add(b.sublist(0, n - 1));
    }
    return out.takeBytes();
  }
}

// ---------------------------------------------------------------------------
// Fonts
// ---------------------------------------------------------------------------

// Standard-font metrics (Adobe AFM): unicode codepoint -> width in
// 1/1000 em, for the 14 standard PDF fonts used WITHOUT /Widths.
// Non-embedded standard fonts rely on the viewer knowing these.
const Map<String, Map<int, int>> _stdFontUniWidths = {
  'Helvetica': {
    0x0020: 278, 0x0021: 278, 0x0022: 355, 0x0023: 556, 0x0024: 556, 0x0025: 889, 0x0026: 667, 0x0027: 191,
    0x0028: 333, 0x0029: 333, 0x002A: 389, 0x002B: 584, 0x002C: 278, 0x002D: 333, 0x002E: 278, 0x002F: 278,
    0x0030: 556, 0x0031: 556, 0x0032: 556, 0x0033: 556, 0x0034: 556, 0x0035: 556, 0x0036: 556, 0x0037: 556,
    0x0038: 556, 0x0039: 556, 0x003A: 278, 0x003B: 278, 0x003C: 584, 0x003D: 584, 0x003E: 584, 0x003F: 556,
    0x0040: 1015, 0x0041: 667, 0x0042: 667, 0x0043: 722, 0x0044: 722, 0x0045: 667, 0x0046: 611, 0x0047: 778,
    0x0048: 722, 0x0049: 278, 0x004A: 500, 0x004B: 667, 0x004C: 556, 0x004D: 833, 0x004E: 722, 0x004F: 778,
    0x0050: 667, 0x0051: 778, 0x0052: 722, 0x0053: 667, 0x0054: 611, 0x0055: 722, 0x0056: 667, 0x0057: 944,
    0x0058: 667, 0x0059: 667, 0x005A: 611, 0x005B: 278, 0x005C: 278, 0x005D: 278, 0x005E: 469, 0x005F: 556,
    0x0060: 333, 0x0061: 556, 0x0062: 556, 0x0063: 500, 0x0064: 556, 0x0065: 556, 0x0066: 278, 0x0067: 556,
    0x0068: 556, 0x0069: 222, 0x006A: 222, 0x006B: 500, 0x006C: 222, 0x006D: 833, 0x006E: 556, 0x006F: 556,
    0x0070: 556, 0x0071: 556, 0x0072: 333, 0x0073: 500, 0x0074: 278, 0x0075: 556, 0x0076: 500, 0x0077: 722,
    0x0078: 500, 0x0079: 500, 0x007A: 500, 0x007B: 334, 0x007C: 260, 0x007D: 334, 0x007E: 584, 0x00A0: 278,
    0x00A1: 333, 0x00A2: 556, 0x00A3: 556, 0x00A4: 556, 0x00A5: 556, 0x00A6: 260, 0x00A7: 556, 0x00A8: 333,
    0x00A9: 737, 0x00AA: 370, 0x00AB: 556, 0x00AC: 584, 0x00AD: 333, 0x00AE: 737, 0x00AF: 333, 0x00B0: 400,
    0x00B1: 584, 0x00B2: 333, 0x00B3: 333, 0x00B4: 333, 0x00B5: 556, 0x00B6: 537, 0x00B7: 278, 0x00B8: 333,
    0x00B9: 333, 0x00BA: 365, 0x00BB: 556, 0x00BC: 834, 0x00BD: 834, 0x00BE: 834, 0x00BF: 611, 0x00C0: 667,
    0x00C1: 667, 0x00C2: 667, 0x00C3: 667, 0x00C4: 667, 0x00C5: 667, 0x00C6: 1000, 0x00C7: 722, 0x00C8: 667,
    0x00C9: 667, 0x00CA: 667, 0x00CB: 667, 0x00CC: 278, 0x00CD: 278, 0x00CE: 278, 0x00CF: 278, 0x00D0: 722,
    0x00D1: 722, 0x00D2: 778, 0x00D3: 778, 0x00D4: 778, 0x00D5: 778, 0x00D6: 778, 0x00D7: 584, 0x00D8: 778,
    0x00D9: 722, 0x00DA: 722, 0x00DB: 722, 0x00DC: 722, 0x00DD: 667, 0x00DE: 667, 0x00DF: 611, 0x00E0: 556,
    0x00E1: 556, 0x00E2: 556, 0x00E3: 556, 0x00E4: 556, 0x00E5: 556, 0x00E6: 889, 0x00E7: 500, 0x00E8: 556,
    0x00E9: 556, 0x00EA: 556, 0x00EB: 556, 0x00EC: 278, 0x00ED: 278, 0x00EE: 278, 0x00EF: 278, 0x00F0: 556,
    0x00F1: 556, 0x00F2: 556, 0x00F3: 556, 0x00F4: 556, 0x00F5: 556, 0x00F6: 556, 0x00F7: 584, 0x00F8: 611,
    0x00F9: 556, 0x00FA: 556, 0x00FB: 556, 0x00FC: 556, 0x00FD: 500, 0x00FE: 556, 0x00FF: 500, 0x0152: 761,
    0x0153: 761, 0x0160: 761, 0x0161: 761, 0x0178: 761, 0x017D: 761, 0x017E: 761, 0x0192: 761, 0x02C6: 761,
    0x02DC: 761, 0x2013: 761, 0x2014: 761, 0x2018: 761, 0x2019: 761, 0x201A: 761, 0x201C: 761, 0x201D: 761,
    0x201E: 761, 0x2020: 761, 0x2021: 761, 0x2022: 761, 0x2026: 761, 0x2030: 761, 0x2039: 761, 0x203A: 761,
    0x20AC: 761, 0x2122: 761,
  },
  'Helvetica-Bold': {
    0x0020: 278, 0x0021: 333, 0x0022: 474, 0x0023: 556, 0x0024: 556, 0x0025: 889, 0x0026: 722, 0x0027: 238,
    0x0028: 333, 0x0029: 333, 0x002A: 389, 0x002B: 584, 0x002C: 278, 0x002D: 333, 0x002E: 278, 0x002F: 278,
    0x0030: 556, 0x0031: 556, 0x0032: 556, 0x0033: 556, 0x0034: 556, 0x0035: 556, 0x0036: 556, 0x0037: 556,
    0x0038: 556, 0x0039: 556, 0x003A: 333, 0x003B: 333, 0x003C: 584, 0x003D: 584, 0x003E: 584, 0x003F: 611,
    0x0040: 975, 0x0041: 722, 0x0042: 722, 0x0043: 722, 0x0044: 722, 0x0045: 667, 0x0046: 611, 0x0047: 778,
    0x0048: 722, 0x0049: 278, 0x004A: 556, 0x004B: 722, 0x004C: 611, 0x004D: 833, 0x004E: 722, 0x004F: 778,
    0x0050: 667, 0x0051: 778, 0x0052: 722, 0x0053: 667, 0x0054: 611, 0x0055: 722, 0x0056: 667, 0x0057: 944,
    0x0058: 667, 0x0059: 667, 0x005A: 611, 0x005B: 333, 0x005C: 278, 0x005D: 333, 0x005E: 584, 0x005F: 556,
    0x0060: 333, 0x0061: 556, 0x0062: 611, 0x0063: 556, 0x0064: 611, 0x0065: 556, 0x0066: 333, 0x0067: 611,
    0x0068: 611, 0x0069: 278, 0x006A: 278, 0x006B: 556, 0x006C: 278, 0x006D: 889, 0x006E: 611, 0x006F: 611,
    0x0070: 611, 0x0071: 611, 0x0072: 389, 0x0073: 556, 0x0074: 333, 0x0075: 611, 0x0076: 556, 0x0077: 778,
    0x0078: 556, 0x0079: 556, 0x007A: 500, 0x007B: 389, 0x007C: 280, 0x007D: 389, 0x007E: 584, 0x00A0: 278,
    0x00A1: 333, 0x00A2: 556, 0x00A3: 556, 0x00A4: 556, 0x00A5: 556, 0x00A6: 280, 0x00A7: 556, 0x00A8: 333,
    0x00A9: 737, 0x00AA: 370, 0x00AB: 556, 0x00AC: 584, 0x00AD: 333, 0x00AE: 737, 0x00AF: 333, 0x00B0: 400,
    0x00B1: 584, 0x00B2: 333, 0x00B3: 333, 0x00B4: 333, 0x00B5: 611, 0x00B6: 556, 0x00B7: 278, 0x00B8: 333,
    0x00B9: 333, 0x00BA: 365, 0x00BB: 556, 0x00BC: 834, 0x00BD: 834, 0x00BE: 834, 0x00BF: 611, 0x00C0: 722,
    0x00C1: 722, 0x00C2: 722, 0x00C3: 722, 0x00C4: 722, 0x00C5: 722, 0x00C6: 1000, 0x00C7: 722, 0x00C8: 667,
    0x00C9: 667, 0x00CA: 667, 0x00CB: 667, 0x00CC: 278, 0x00CD: 278, 0x00CE: 278, 0x00CF: 278, 0x00D0: 722,
    0x00D1: 722, 0x00D2: 778, 0x00D3: 778, 0x00D4: 778, 0x00D5: 778, 0x00D6: 778, 0x00D7: 584, 0x00D8: 778,
    0x00D9: 722, 0x00DA: 722, 0x00DB: 722, 0x00DC: 722, 0x00DD: 667, 0x00DE: 667, 0x00DF: 611, 0x00E0: 556,
    0x00E1: 556, 0x00E2: 556, 0x00E3: 556, 0x00E4: 556, 0x00E5: 556, 0x00E6: 889, 0x00E7: 556, 0x00E8: 556,
    0x00E9: 556, 0x00EA: 556, 0x00EB: 556, 0x00EC: 278, 0x00ED: 278, 0x00EE: 278, 0x00EF: 278, 0x00F0: 611,
    0x00F1: 611, 0x00F2: 611, 0x00F3: 611, 0x00F4: 611, 0x00F5: 611, 0x00F6: 611, 0x00F7: 584, 0x00F8: 611,
    0x00F9: 611, 0x00FA: 611, 0x00FB: 611, 0x00FC: 611, 0x00FD: 556, 0x00FE: 611, 0x00FF: 556, 0x0152: 761,
    0x0153: 761, 0x0160: 761, 0x0161: 761, 0x0178: 761, 0x017D: 761, 0x017E: 761, 0x0192: 761, 0x02C6: 761,
    0x02DC: 761, 0x2013: 761, 0x2014: 761, 0x2018: 761, 0x2019: 761, 0x201A: 761, 0x201C: 761, 0x201D: 761,
    0x201E: 761, 0x2020: 761, 0x2021: 761, 0x2022: 761, 0x2026: 761, 0x2030: 761, 0x2039: 761, 0x203A: 761,
    0x20AC: 761, 0x2122: 761,
  },
  'Helvetica-Oblique': {
    0x0020: 278, 0x0021: 278, 0x0022: 355, 0x0023: 556, 0x0024: 556, 0x0025: 889, 0x0026: 667, 0x0027: 191,
    0x0028: 333, 0x0029: 333, 0x002A: 389, 0x002B: 584, 0x002C: 278, 0x002D: 333, 0x002E: 278, 0x002F: 278,
    0x0030: 556, 0x0031: 556, 0x0032: 556, 0x0033: 556, 0x0034: 556, 0x0035: 556, 0x0036: 556, 0x0037: 556,
    0x0038: 556, 0x0039: 556, 0x003A: 278, 0x003B: 278, 0x003C: 584, 0x003D: 584, 0x003E: 584, 0x003F: 556,
    0x0040: 1015, 0x0041: 667, 0x0042: 667, 0x0043: 722, 0x0044: 722, 0x0045: 667, 0x0046: 611, 0x0047: 778,
    0x0048: 722, 0x0049: 278, 0x004A: 500, 0x004B: 667, 0x004C: 556, 0x004D: 833, 0x004E: 722, 0x004F: 778,
    0x0050: 667, 0x0051: 778, 0x0052: 722, 0x0053: 667, 0x0054: 611, 0x0055: 722, 0x0056: 667, 0x0057: 944,
    0x0058: 667, 0x0059: 667, 0x005A: 611, 0x005B: 278, 0x005C: 278, 0x005D: 278, 0x005E: 469, 0x005F: 556,
    0x0060: 333, 0x0061: 556, 0x0062: 556, 0x0063: 500, 0x0064: 556, 0x0065: 556, 0x0066: 278, 0x0067: 556,
    0x0068: 556, 0x0069: 222, 0x006A: 222, 0x006B: 500, 0x006C: 222, 0x006D: 833, 0x006E: 556, 0x006F: 556,
    0x0070: 556, 0x0071: 556, 0x0072: 333, 0x0073: 500, 0x0074: 278, 0x0075: 556, 0x0076: 500, 0x0077: 722,
    0x0078: 500, 0x0079: 500, 0x007A: 500, 0x007B: 334, 0x007C: 260, 0x007D: 334, 0x007E: 584, 0x00A0: 278,
    0x00A1: 333, 0x00A2: 556, 0x00A3: 556, 0x00A4: 556, 0x00A5: 556, 0x00A6: 260, 0x00A7: 556, 0x00A8: 333,
    0x00A9: 737, 0x00AA: 370, 0x00AB: 556, 0x00AC: 584, 0x00AD: 333, 0x00AE: 737, 0x00AF: 333, 0x00B0: 400,
    0x00B1: 584, 0x00B2: 333, 0x00B3: 333, 0x00B4: 333, 0x00B5: 556, 0x00B6: 537, 0x00B7: 278, 0x00B8: 333,
    0x00B9: 333, 0x00BA: 365, 0x00BB: 556, 0x00BC: 834, 0x00BD: 834, 0x00BE: 834, 0x00BF: 611, 0x00C0: 667,
    0x00C1: 667, 0x00C2: 667, 0x00C3: 667, 0x00C4: 667, 0x00C5: 667, 0x00C6: 1000, 0x00C7: 722, 0x00C8: 667,
    0x00C9: 667, 0x00CA: 667, 0x00CB: 667, 0x00CC: 278, 0x00CD: 278, 0x00CE: 278, 0x00CF: 278, 0x00D0: 722,
    0x00D1: 722, 0x00D2: 778, 0x00D3: 778, 0x00D4: 778, 0x00D5: 778, 0x00D6: 778, 0x00D7: 584, 0x00D8: 778,
    0x00D9: 722, 0x00DA: 722, 0x00DB: 722, 0x00DC: 722, 0x00DD: 667, 0x00DE: 667, 0x00DF: 611, 0x00E0: 556,
    0x00E1: 556, 0x00E2: 556, 0x00E3: 556, 0x00E4: 556, 0x00E5: 556, 0x00E6: 889, 0x00E7: 500, 0x00E8: 556,
    0x00E9: 556, 0x00EA: 556, 0x00EB: 556, 0x00EC: 278, 0x00ED: 278, 0x00EE: 278, 0x00EF: 278, 0x00F0: 556,
    0x00F1: 556, 0x00F2: 556, 0x00F3: 556, 0x00F4: 556, 0x00F5: 556, 0x00F6: 556, 0x00F7: 584, 0x00F8: 611,
    0x00F9: 556, 0x00FA: 556, 0x00FB: 556, 0x00FC: 556, 0x00FD: 500, 0x00FE: 556, 0x00FF: 500, 0x0152: 761,
    0x0153: 761, 0x0160: 761, 0x0161: 761, 0x0178: 761, 0x017D: 761, 0x017E: 761, 0x0192: 761, 0x02C6: 761,
    0x02DC: 761, 0x2013: 761, 0x2014: 761, 0x2018: 761, 0x2019: 761, 0x201A: 761, 0x201C: 761, 0x201D: 761,
    0x201E: 761, 0x2020: 761, 0x2021: 761, 0x2022: 761, 0x2026: 761, 0x2030: 761, 0x2039: 761, 0x203A: 761,
    0x20AC: 761, 0x2122: 761,
  },
  'Helvetica-BoldOblique': {
    0x0020: 278, 0x0021: 333, 0x0022: 474, 0x0023: 556, 0x0024: 556, 0x0025: 889, 0x0026: 722, 0x0027: 238,
    0x0028: 333, 0x0029: 333, 0x002A: 389, 0x002B: 584, 0x002C: 278, 0x002D: 333, 0x002E: 278, 0x002F: 278,
    0x0030: 556, 0x0031: 556, 0x0032: 556, 0x0033: 556, 0x0034: 556, 0x0035: 556, 0x0036: 556, 0x0037: 556,
    0x0038: 556, 0x0039: 556, 0x003A: 333, 0x003B: 333, 0x003C: 584, 0x003D: 584, 0x003E: 584, 0x003F: 611,
    0x0040: 975, 0x0041: 722, 0x0042: 722, 0x0043: 722, 0x0044: 722, 0x0045: 667, 0x0046: 611, 0x0047: 778,
    0x0048: 722, 0x0049: 278, 0x004A: 556, 0x004B: 722, 0x004C: 611, 0x004D: 833, 0x004E: 722, 0x004F: 778,
    0x0050: 667, 0x0051: 778, 0x0052: 722, 0x0053: 667, 0x0054: 611, 0x0055: 722, 0x0056: 667, 0x0057: 944,
    0x0058: 667, 0x0059: 667, 0x005A: 611, 0x005B: 333, 0x005C: 278, 0x005D: 333, 0x005E: 584, 0x005F: 556,
    0x0060: 333, 0x0061: 556, 0x0062: 611, 0x0063: 556, 0x0064: 611, 0x0065: 556, 0x0066: 333, 0x0067: 611,
    0x0068: 611, 0x0069: 278, 0x006A: 278, 0x006B: 556, 0x006C: 278, 0x006D: 889, 0x006E: 611, 0x006F: 611,
    0x0070: 611, 0x0071: 611, 0x0072: 389, 0x0073: 556, 0x0074: 333, 0x0075: 611, 0x0076: 556, 0x0077: 778,
    0x0078: 556, 0x0079: 556, 0x007A: 500, 0x007B: 389, 0x007C: 280, 0x007D: 389, 0x007E: 584, 0x00A0: 278,
    0x00A1: 333, 0x00A2: 556, 0x00A3: 556, 0x00A4: 556, 0x00A5: 556, 0x00A6: 280, 0x00A7: 556, 0x00A8: 333,
    0x00A9: 737, 0x00AA: 370, 0x00AB: 556, 0x00AC: 584, 0x00AD: 333, 0x00AE: 737, 0x00AF: 333, 0x00B0: 400,
    0x00B1: 584, 0x00B2: 333, 0x00B3: 333, 0x00B4: 333, 0x00B5: 611, 0x00B6: 556, 0x00B7: 278, 0x00B8: 333,
    0x00B9: 333, 0x00BA: 365, 0x00BB: 556, 0x00BC: 834, 0x00BD: 834, 0x00BE: 834, 0x00BF: 611, 0x00C0: 722,
    0x00C1: 722, 0x00C2: 722, 0x00C3: 722, 0x00C4: 722, 0x00C5: 722, 0x00C6: 1000, 0x00C7: 722, 0x00C8: 667,
    0x00C9: 667, 0x00CA: 667, 0x00CB: 667, 0x00CC: 278, 0x00CD: 278, 0x00CE: 278, 0x00CF: 278, 0x00D0: 722,
    0x00D1: 722, 0x00D2: 778, 0x00D3: 778, 0x00D4: 778, 0x00D5: 778, 0x00D6: 778, 0x00D7: 584, 0x00D8: 778,
    0x00D9: 722, 0x00DA: 722, 0x00DB: 722, 0x00DC: 722, 0x00DD: 667, 0x00DE: 667, 0x00DF: 611, 0x00E0: 556,
    0x00E1: 556, 0x00E2: 556, 0x00E3: 556, 0x00E4: 556, 0x00E5: 556, 0x00E6: 889, 0x00E7: 556, 0x00E8: 556,
    0x00E9: 556, 0x00EA: 556, 0x00EB: 556, 0x00EC: 278, 0x00ED: 278, 0x00EE: 278, 0x00EF: 278, 0x00F0: 611,
    0x00F1: 611, 0x00F2: 611, 0x00F3: 611, 0x00F4: 611, 0x00F5: 611, 0x00F6: 611, 0x00F7: 584, 0x00F8: 611,
    0x00F9: 611, 0x00FA: 611, 0x00FB: 611, 0x00FC: 611, 0x00FD: 556, 0x00FE: 611, 0x00FF: 556, 0x0152: 761,
    0x0153: 761, 0x0160: 761, 0x0161: 761, 0x0178: 761, 0x017D: 761, 0x017E: 761, 0x0192: 761, 0x02C6: 761,
    0x02DC: 761, 0x2013: 761, 0x2014: 761, 0x2018: 761, 0x2019: 761, 0x201A: 761, 0x201C: 761, 0x201D: 761,
    0x201E: 761, 0x2020: 761, 0x2021: 761, 0x2022: 761, 0x2026: 761, 0x2030: 761, 0x2039: 761, 0x203A: 761,
    0x20AC: 761, 0x2122: 761,
  },
  'Times-Roman': {
    0x0020: 250, 0x0021: 333, 0x0022: 408, 0x0023: 500, 0x0024: 500, 0x0025: 833, 0x0026: 778, 0x0027: 180,
    0x0028: 333, 0x0029: 333, 0x002A: 500, 0x002B: 564, 0x002C: 250, 0x002D: 333, 0x002E: 250, 0x002F: 278,
    0x0030: 500, 0x0031: 500, 0x0032: 500, 0x0033: 500, 0x0034: 500, 0x0035: 500, 0x0036: 500, 0x0037: 500,
    0x0038: 500, 0x0039: 500, 0x003A: 278, 0x003B: 278, 0x003C: 564, 0x003D: 564, 0x003E: 564, 0x003F: 444,
    0x0040: 921, 0x0041: 722, 0x0042: 667, 0x0043: 667, 0x0044: 722, 0x0045: 611, 0x0046: 556, 0x0047: 722,
    0x0048: 722, 0x0049: 333, 0x004A: 389, 0x004B: 722, 0x004C: 611, 0x004D: 889, 0x004E: 722, 0x004F: 722,
    0x0050: 556, 0x0051: 722, 0x0052: 667, 0x0053: 556, 0x0054: 611, 0x0055: 722, 0x0056: 722, 0x0057: 944,
    0x0058: 722, 0x0059: 722, 0x005A: 611, 0x005B: 333, 0x005C: 278, 0x005D: 333, 0x005E: 469, 0x005F: 500,
    0x0060: 333, 0x0061: 444, 0x0062: 500, 0x0063: 444, 0x0064: 500, 0x0065: 444, 0x0066: 333, 0x0067: 500,
    0x0068: 500, 0x0069: 278, 0x006A: 278, 0x006B: 500, 0x006C: 278, 0x006D: 778, 0x006E: 500, 0x006F: 500,
    0x0070: 500, 0x0071: 500, 0x0072: 333, 0x0073: 389, 0x0074: 278, 0x0075: 500, 0x0076: 500, 0x0077: 722,
    0x0078: 500, 0x0079: 500, 0x007A: 444, 0x007B: 480, 0x007C: 200, 0x007D: 480, 0x007E: 541, 0x00A0: 250,
    0x00A1: 333, 0x00A2: 500, 0x00A3: 500, 0x00A4: 500, 0x00A5: 500, 0x00A6: 200, 0x00A7: 500, 0x00A8: 333,
    0x00A9: 760, 0x00AA: 276, 0x00AB: 500, 0x00AC: 564, 0x00AD: 333, 0x00AE: 760, 0x00AF: 333, 0x00B0: 400,
    0x00B1: 564, 0x00B2: 300, 0x00B3: 300, 0x00B4: 333, 0x00B5: 500, 0x00B6: 453, 0x00B7: 250, 0x00B8: 333,
    0x00B9: 300, 0x00BA: 310, 0x00BB: 500, 0x00BC: 750, 0x00BD: 750, 0x00BE: 750, 0x00BF: 444, 0x00C0: 722,
    0x00C1: 722, 0x00C2: 722, 0x00C3: 722, 0x00C4: 722, 0x00C5: 722, 0x00C6: 889, 0x00C7: 667, 0x00C8: 611,
    0x00C9: 611, 0x00CA: 611, 0x00CB: 611, 0x00CC: 333, 0x00CD: 333, 0x00CE: 333, 0x00CF: 333, 0x00D0: 722,
    0x00D1: 722, 0x00D2: 722, 0x00D3: 722, 0x00D4: 722, 0x00D5: 722, 0x00D6: 722, 0x00D7: 564, 0x00D8: 722,
    0x00D9: 722, 0x00DA: 722, 0x00DB: 722, 0x00DC: 722, 0x00DD: 722, 0x00DE: 556, 0x00DF: 500, 0x00E0: 444,
    0x00E1: 444, 0x00E2: 444, 0x00E3: 444, 0x00E4: 444, 0x00E5: 444, 0x00E6: 667, 0x00E7: 444, 0x00E8: 444,
    0x00E9: 444, 0x00EA: 444, 0x00EB: 444, 0x00EC: 278, 0x00ED: 278, 0x00EE: 278, 0x00EF: 278, 0x00F0: 500,
    0x00F1: 500, 0x00F2: 500, 0x00F3: 500, 0x00F4: 500, 0x00F5: 500, 0x00F6: 500, 0x00F7: 564, 0x00F8: 500,
    0x00F9: 500, 0x00FA: 500, 0x00FB: 500, 0x00FC: 500, 0x00FD: 500, 0x00FE: 500, 0x00FF: 500, 0x0152: 761,
    0x0153: 761, 0x0160: 761, 0x0161: 761, 0x0178: 761, 0x017D: 761, 0x017E: 761, 0x0192: 761, 0x02C6: 761,
    0x02DC: 761, 0x2013: 761, 0x2014: 761, 0x2018: 761, 0x2019: 761, 0x201A: 761, 0x201C: 761, 0x201D: 761,
    0x201E: 761, 0x2020: 761, 0x2021: 761, 0x2022: 761, 0x2026: 761, 0x2030: 761, 0x2039: 761, 0x203A: 761,
    0x20AC: 761, 0x2122: 761,
  },
  'Times-Bold': {
    0x0020: 250, 0x0021: 333, 0x0022: 555, 0x0023: 500, 0x0024: 500, 0x0025: 1000, 0x0026: 833, 0x0027: 278,
    0x0028: 333, 0x0029: 333, 0x002A: 500, 0x002B: 570, 0x002C: 250, 0x002D: 333, 0x002E: 250, 0x002F: 278,
    0x0030: 500, 0x0031: 500, 0x0032: 500, 0x0033: 500, 0x0034: 500, 0x0035: 500, 0x0036: 500, 0x0037: 500,
    0x0038: 500, 0x0039: 500, 0x003A: 333, 0x003B: 333, 0x003C: 570, 0x003D: 570, 0x003E: 570, 0x003F: 500,
    0x0040: 930, 0x0041: 722, 0x0042: 667, 0x0043: 722, 0x0044: 722, 0x0045: 667, 0x0046: 611, 0x0047: 778,
    0x0048: 778, 0x0049: 389, 0x004A: 500, 0x004B: 778, 0x004C: 667, 0x004D: 944, 0x004E: 722, 0x004F: 778,
    0x0050: 611, 0x0051: 778, 0x0052: 722, 0x0053: 556, 0x0054: 667, 0x0055: 722, 0x0056: 722, 0x0057: 1000,
    0x0058: 722, 0x0059: 722, 0x005A: 667, 0x005B: 333, 0x005C: 278, 0x005D: 333, 0x005E: 581, 0x005F: 500,
    0x0060: 333, 0x0061: 500, 0x0062: 556, 0x0063: 444, 0x0064: 556, 0x0065: 444, 0x0066: 333, 0x0067: 500,
    0x0068: 556, 0x0069: 278, 0x006A: 333, 0x006B: 556, 0x006C: 278, 0x006D: 833, 0x006E: 556, 0x006F: 500,
    0x0070: 556, 0x0071: 556, 0x0072: 444, 0x0073: 389, 0x0074: 333, 0x0075: 556, 0x0076: 500, 0x0077: 722,
    0x0078: 500, 0x0079: 500, 0x007A: 444, 0x007B: 394, 0x007C: 220, 0x007D: 394, 0x007E: 520, 0x00A0: 250,
    0x00A1: 333, 0x00A2: 500, 0x00A3: 500, 0x00A4: 500, 0x00A5: 500, 0x00A6: 220, 0x00A7: 500, 0x00A8: 333,
    0x00A9: 747, 0x00AA: 300, 0x00AB: 500, 0x00AC: 570, 0x00AD: 333, 0x00AE: 747, 0x00AF: 333, 0x00B0: 400,
    0x00B1: 570, 0x00B2: 300, 0x00B3: 300, 0x00B4: 333, 0x00B5: 556, 0x00B6: 540, 0x00B7: 250, 0x00B8: 333,
    0x00B9: 300, 0x00BA: 330, 0x00BB: 500, 0x00BC: 750, 0x00BD: 750, 0x00BE: 750, 0x00BF: 500, 0x00C0: 722,
    0x00C1: 722, 0x00C2: 722, 0x00C3: 722, 0x00C4: 722, 0x00C5: 722, 0x00C6: 1000, 0x00C7: 722, 0x00C8: 667,
    0x00C9: 667, 0x00CA: 667, 0x00CB: 667, 0x00CC: 389, 0x00CD: 389, 0x00CE: 389, 0x00CF: 389, 0x00D0: 722,
    0x00D1: 722, 0x00D2: 778, 0x00D3: 778, 0x00D4: 778, 0x00D5: 778, 0x00D6: 778, 0x00D7: 570, 0x00D8: 778,
    0x00D9: 722, 0x00DA: 722, 0x00DB: 722, 0x00DC: 722, 0x00DD: 722, 0x00DE: 611, 0x00DF: 556, 0x00E0: 500,
    0x00E1: 500, 0x00E2: 500, 0x00E3: 500, 0x00E4: 500, 0x00E5: 500, 0x00E6: 722, 0x00E7: 444, 0x00E8: 444,
    0x00E9: 444, 0x00EA: 444, 0x00EB: 444, 0x00EC: 278, 0x00ED: 278, 0x00EE: 278, 0x00EF: 278, 0x00F0: 500,
    0x00F1: 556, 0x00F2: 500, 0x00F3: 500, 0x00F4: 500, 0x00F5: 500, 0x00F6: 500, 0x00F7: 570, 0x00F8: 500,
    0x00F9: 556, 0x00FA: 556, 0x00FB: 556, 0x00FC: 556, 0x00FD: 500, 0x00FE: 556, 0x00FF: 500, 0x0152: 761,
    0x0153: 761, 0x0160: 761, 0x0161: 761, 0x0178: 761, 0x017D: 761, 0x017E: 761, 0x0192: 761, 0x02C6: 761,
    0x02DC: 761, 0x2013: 761, 0x2014: 761, 0x2018: 761, 0x2019: 761, 0x201A: 761, 0x201C: 761, 0x201D: 761,
    0x201E: 761, 0x2020: 761, 0x2021: 761, 0x2022: 761, 0x2026: 761, 0x2030: 761, 0x2039: 761, 0x203A: 761,
    0x20AC: 761, 0x2122: 761,
  },
  'Times-Italic': {
    0x0020: 250, 0x0021: 333, 0x0022: 420, 0x0023: 500, 0x0024: 500, 0x0025: 833, 0x0026: 778, 0x0027: 214,
    0x0028: 333, 0x0029: 333, 0x002A: 500, 0x002B: 675, 0x002C: 250, 0x002D: 333, 0x002E: 250, 0x002F: 278,
    0x0030: 500, 0x0031: 500, 0x0032: 500, 0x0033: 500, 0x0034: 500, 0x0035: 500, 0x0036: 500, 0x0037: 500,
    0x0038: 500, 0x0039: 500, 0x003A: 333, 0x003B: 333, 0x003C: 675, 0x003D: 675, 0x003E: 675, 0x003F: 500,
    0x0040: 920, 0x0041: 611, 0x0042: 611, 0x0043: 667, 0x0044: 722, 0x0045: 611, 0x0046: 611, 0x0047: 722,
    0x0048: 722, 0x0049: 333, 0x004A: 444, 0x004B: 667, 0x004C: 556, 0x004D: 833, 0x004E: 667, 0x004F: 722,
    0x0050: 611, 0x0051: 722, 0x0052: 611, 0x0053: 500, 0x0054: 556, 0x0055: 722, 0x0056: 611, 0x0057: 833,
    0x0058: 611, 0x0059: 556, 0x005A: 556, 0x005B: 389, 0x005C: 278, 0x005D: 389, 0x005E: 422, 0x005F: 500,
    0x0060: 333, 0x0061: 500, 0x0062: 500, 0x0063: 444, 0x0064: 500, 0x0065: 444, 0x0066: 278, 0x0067: 500,
    0x0068: 500, 0x0069: 278, 0x006A: 278, 0x006B: 444, 0x006C: 278, 0x006D: 722, 0x006E: 500, 0x006F: 500,
    0x0070: 500, 0x0071: 500, 0x0072: 389, 0x0073: 389, 0x0074: 278, 0x0075: 500, 0x0076: 444, 0x0077: 667,
    0x0078: 444, 0x0079: 444, 0x007A: 389, 0x007B: 400, 0x007C: 275, 0x007D: 400, 0x007E: 541, 0x00A0: 250,
    0x00A1: 389, 0x00A2: 500, 0x00A3: 500, 0x00A4: 500, 0x00A5: 500, 0x00A6: 275, 0x00A7: 500, 0x00A8: 333,
    0x00A9: 760, 0x00AA: 276, 0x00AB: 500, 0x00AC: 675, 0x00AD: 333, 0x00AE: 760, 0x00AF: 333, 0x00B0: 400,
    0x00B1: 675, 0x00B2: 300, 0x00B3: 300, 0x00B4: 333, 0x00B5: 500, 0x00B6: 523, 0x00B7: 250, 0x00B8: 333,
    0x00B9: 300, 0x00BA: 310, 0x00BB: 500, 0x00BC: 750, 0x00BD: 750, 0x00BE: 750, 0x00BF: 500, 0x00C0: 611,
    0x00C1: 611, 0x00C2: 611, 0x00C3: 611, 0x00C4: 611, 0x00C5: 611, 0x00C6: 889, 0x00C7: 667, 0x00C8: 611,
    0x00C9: 611, 0x00CA: 611, 0x00CB: 611, 0x00CC: 333, 0x00CD: 333, 0x00CE: 333, 0x00CF: 333, 0x00D0: 722,
    0x00D1: 667, 0x00D2: 722, 0x00D3: 722, 0x00D4: 722, 0x00D5: 722, 0x00D6: 722, 0x00D7: 675, 0x00D8: 722,
    0x00D9: 722, 0x00DA: 722, 0x00DB: 722, 0x00DC: 722, 0x00DD: 556, 0x00DE: 611, 0x00DF: 500, 0x00E0: 500,
    0x00E1: 500, 0x00E2: 500, 0x00E3: 500, 0x00E4: 500, 0x00E5: 500, 0x00E6: 667, 0x00E7: 444, 0x00E8: 444,
    0x00E9: 444, 0x00EA: 444, 0x00EB: 444, 0x00EC: 278, 0x00ED: 278, 0x00EE: 278, 0x00EF: 278, 0x00F0: 500,
    0x00F1: 500, 0x00F2: 500, 0x00F3: 500, 0x00F4: 500, 0x00F5: 500, 0x00F6: 500, 0x00F7: 675, 0x00F8: 500,
    0x00F9: 500, 0x00FA: 500, 0x00FB: 500, 0x00FC: 500, 0x00FD: 444, 0x00FE: 500, 0x00FF: 444, 0x0152: 761,
    0x0153: 761, 0x0160: 761, 0x0161: 761, 0x0178: 761, 0x017D: 761, 0x017E: 761, 0x0192: 761, 0x02C6: 761,
    0x02DC: 761, 0x2013: 761, 0x2014: 761, 0x2018: 761, 0x2019: 761, 0x201A: 761, 0x201C: 761, 0x201D: 761,
    0x201E: 761, 0x2020: 761, 0x2021: 761, 0x2022: 761, 0x2026: 761, 0x2030: 761, 0x2039: 761, 0x203A: 761,
    0x20AC: 761, 0x2122: 761,
  },
  'Times-BoldItalic': {
    0x0020: 250, 0x0021: 389, 0x0022: 555, 0x0023: 500, 0x0024: 500, 0x0025: 833, 0x0026: 778, 0x0027: 278,
    0x0028: 333, 0x0029: 333, 0x002A: 500, 0x002B: 570, 0x002C: 250, 0x002D: 333, 0x002E: 250, 0x002F: 278,
    0x0030: 500, 0x0031: 500, 0x0032: 500, 0x0033: 500, 0x0034: 500, 0x0035: 500, 0x0036: 500, 0x0037: 500,
    0x0038: 500, 0x0039: 500, 0x003A: 333, 0x003B: 333, 0x003C: 570, 0x003D: 570, 0x003E: 570, 0x003F: 500,
    0x0040: 832, 0x0041: 667, 0x0042: 667, 0x0043: 667, 0x0044: 722, 0x0045: 667, 0x0046: 667, 0x0047: 722,
    0x0048: 778, 0x0049: 389, 0x004A: 500, 0x004B: 667, 0x004C: 611, 0x004D: 889, 0x004E: 722, 0x004F: 722,
    0x0050: 611, 0x0051: 722, 0x0052: 667, 0x0053: 556, 0x0054: 611, 0x0055: 722, 0x0056: 667, 0x0057: 889,
    0x0058: 667, 0x0059: 611, 0x005A: 611, 0x005B: 333, 0x005C: 278, 0x005D: 333, 0x005E: 570, 0x005F: 500,
    0x0060: 333, 0x0061: 500, 0x0062: 500, 0x0063: 444, 0x0064: 500, 0x0065: 444, 0x0066: 333, 0x0067: 500,
    0x0068: 556, 0x0069: 278, 0x006A: 278, 0x006B: 500, 0x006C: 278, 0x006D: 778, 0x006E: 556, 0x006F: 500,
    0x0070: 500, 0x0071: 500, 0x0072: 389, 0x0073: 389, 0x0074: 278, 0x0075: 556, 0x0076: 444, 0x0077: 667,
    0x0078: 500, 0x0079: 444, 0x007A: 389, 0x007B: 348, 0x007C: 220, 0x007D: 348, 0x007E: 570, 0x00A0: 250,
    0x00A1: 389, 0x00A2: 500, 0x00A3: 500, 0x00A4: 500, 0x00A5: 500, 0x00A6: 220, 0x00A7: 500, 0x00A8: 333,
    0x00A9: 747, 0x00AA: 266, 0x00AB: 500, 0x00AC: 606, 0x00AD: 333, 0x00AE: 747, 0x00AF: 333, 0x00B0: 400,
    0x00B1: 570, 0x00B2: 300, 0x00B3: 300, 0x00B4: 333, 0x00B5: 576, 0x00B6: 500, 0x00B7: 250, 0x00B8: 333,
    0x00B9: 300, 0x00BA: 300, 0x00BB: 500, 0x00BC: 750, 0x00BD: 750, 0x00BE: 750, 0x00BF: 500, 0x00C0: 667,
    0x00C1: 667, 0x00C2: 667, 0x00C3: 667, 0x00C4: 667, 0x00C5: 667, 0x00C6: 944, 0x00C7: 667, 0x00C8: 667,
    0x00C9: 667, 0x00CA: 667, 0x00CB: 667, 0x00CC: 389, 0x00CD: 389, 0x00CE: 389, 0x00CF: 389, 0x00D0: 722,
    0x00D1: 722, 0x00D2: 722, 0x00D3: 722, 0x00D4: 722, 0x00D5: 722, 0x00D6: 722, 0x00D7: 570, 0x00D8: 722,
    0x00D9: 722, 0x00DA: 722, 0x00DB: 722, 0x00DC: 722, 0x00DD: 611, 0x00DE: 611, 0x00DF: 500, 0x00E0: 500,
    0x00E1: 500, 0x00E2: 500, 0x00E3: 500, 0x00E4: 500, 0x00E5: 500, 0x00E6: 722, 0x00E7: 444, 0x00E8: 444,
    0x00E9: 444, 0x00EA: 444, 0x00EB: 444, 0x00EC: 278, 0x00ED: 278, 0x00EE: 278, 0x00EF: 278, 0x00F0: 500,
    0x00F1: 556, 0x00F2: 500, 0x00F3: 500, 0x00F4: 500, 0x00F5: 500, 0x00F6: 500, 0x00F7: 570, 0x00F8: 500,
    0x00F9: 556, 0x00FA: 556, 0x00FB: 556, 0x00FC: 556, 0x00FD: 444, 0x00FE: 500, 0x00FF: 444, 0x0152: 761,
    0x0153: 761, 0x0160: 761, 0x0161: 761, 0x0178: 761, 0x017D: 761, 0x017E: 761, 0x0192: 761, 0x02C6: 761,
    0x02DC: 761, 0x2013: 761, 0x2014: 761, 0x2018: 761, 0x2019: 761, 0x201A: 761, 0x201C: 761, 0x201D: 761,
    0x201E: 761, 0x2020: 761, 0x2021: 761, 0x2022: 761, 0x2026: 761, 0x2030: 761, 0x2039: 761, 0x203A: 761,
    0x20AC: 761, 0x2122: 761,
  },
  'Symbol': {
    0x0020: 250, 0x0021: 333, 0x0022: 761, 0x0023: 500, 0x0024: 761, 0x0025: 833, 0x0026: 778, 0x0027: 761,
    0x0028: 333, 0x0029: 333, 0x002A: 761, 0x002B: 549, 0x002C: 250, 0x002D: 761, 0x002E: 250, 0x002F: 278,
    0x0030: 500, 0x0031: 500, 0x0032: 500, 0x0033: 500, 0x0034: 500, 0x0035: 500, 0x0036: 500, 0x0037: 500,
    0x0038: 500, 0x0039: 500, 0x003A: 278, 0x003B: 278, 0x003C: 549, 0x003D: 549, 0x003E: 549, 0x003F: 444,
    0x0040: 761, 0x0041: 761, 0x0042: 761, 0x0043: 761, 0x0044: 761, 0x0045: 761, 0x0046: 761, 0x0047: 761,
    0x0048: 761, 0x0049: 761, 0x004A: 761, 0x004B: 761, 0x004C: 761, 0x004D: 761, 0x004E: 761, 0x004F: 761,
    0x0050: 761, 0x0051: 761, 0x0052: 761, 0x0053: 761, 0x0054: 761, 0x0055: 761, 0x0056: 761, 0x0057: 761,
    0x0058: 761, 0x0059: 761, 0x005A: 761, 0x005B: 333, 0x005C: 761, 0x005D: 333, 0x005E: 761, 0x005F: 500,
    0x0060: 761, 0x0061: 761, 0x0062: 761, 0x0063: 761, 0x0064: 761, 0x0065: 761, 0x0066: 761, 0x0067: 761,
    0x0068: 761, 0x0069: 761, 0x006A: 761, 0x006B: 761, 0x006C: 761, 0x006D: 761, 0x006E: 761, 0x006F: 761,
    0x0070: 761, 0x0071: 761, 0x0072: 761, 0x0073: 761, 0x0074: 761, 0x0075: 761, 0x0076: 761, 0x0077: 761,
    0x0078: 761, 0x0079: 761, 0x007A: 761, 0x007B: 480, 0x007C: 200, 0x007D: 480, 0x007E: 761, 0x007F: 761,
    0x0080: 761, 0x0081: 761, 0x0082: 761, 0x0083: 761, 0x0084: 761, 0x0085: 761, 0x0086: 761, 0x0087: 761,
    0x0088: 761, 0x0089: 761, 0x008A: 761, 0x008B: 761, 0x008C: 761, 0x008D: 761, 0x008E: 761, 0x008F: 761,
    0x0090: 761, 0x0091: 761, 0x0092: 761, 0x0093: 761, 0x0094: 761, 0x0095: 761, 0x0096: 761, 0x0097: 761,
    0x0098: 761, 0x0099: 761, 0x009A: 761, 0x009B: 761, 0x009C: 761, 0x009D: 761, 0x009E: 761, 0x009F: 761,
    0x00A0: 761, 0x00A1: 761, 0x00A2: 761, 0x00A3: 761, 0x00A4: 761, 0x00A5: 761, 0x00A6: 761, 0x00A7: 761,
    0x00A8: 761, 0x00A9: 761, 0x00AA: 761, 0x00AB: 761, 0x00AC: 713, 0x00AD: 761, 0x00AE: 761, 0x00AF: 761,
    0x00B0: 400, 0x00B1: 549, 0x00B2: 761, 0x00B3: 761, 0x00B4: 761, 0x00B5: 576, 0x00B6: 761, 0x00B7: 761,
    0x00B8: 761, 0x00B9: 761, 0x00BA: 761, 0x00BB: 761, 0x00BC: 761, 0x00BD: 761, 0x00BE: 761, 0x00BF: 761,
    0x00C0: 761, 0x00C1: 761, 0x00C2: 761, 0x00C3: 761, 0x00C4: 761, 0x00C5: 761, 0x00C6: 761, 0x00C7: 761,
    0x00C8: 761, 0x00C9: 761, 0x00CA: 761, 0x00CB: 761, 0x00CC: 761, 0x00CD: 761, 0x00CE: 761, 0x00CF: 761,
    0x00D0: 761, 0x00D1: 761, 0x00D2: 761, 0x00D3: 761, 0x00D4: 761, 0x00D5: 761, 0x00D6: 761, 0x00D7: 549,
    0x00D8: 761, 0x00D9: 761, 0x00DA: 761, 0x00DB: 761, 0x00DC: 761, 0x00DD: 761, 0x00DE: 761, 0x00DF: 761,
    0x00E0: 761, 0x00E1: 761, 0x00E2: 761, 0x00E3: 761, 0x00E4: 761, 0x00E5: 761, 0x00E6: 761, 0x00E7: 761,
    0x00E8: 761, 0x00E9: 761, 0x00EA: 761, 0x00EB: 761, 0x00EC: 761, 0x00ED: 761, 0x00EE: 761, 0x00EF: 761,
    0x00F0: 761, 0x00F1: 761, 0x00F2: 761, 0x00F3: 761, 0x00F4: 761, 0x00F5: 761, 0x00F6: 761, 0x00F7: 549,
    0x00F8: 761, 0x00F9: 761, 0x00FA: 761, 0x00FB: 761, 0x00FC: 761, 0x00FD: 761, 0x00FE: 761, 0x00FF: 761,
  },
  'ZapfDingbats': {
    0x0020: 278, 0x0021: 761, 0x0022: 761, 0x0023: 761, 0x0024: 761, 0x0025: 761, 0x0026: 761, 0x0027: 761,
    0x0028: 761, 0x0029: 761, 0x002A: 761, 0x002B: 761, 0x002C: 761, 0x002D: 761, 0x002E: 761, 0x002F: 761,
    0x0030: 761, 0x0031: 761, 0x0032: 761, 0x0033: 761, 0x0034: 761, 0x0035: 761, 0x0036: 761, 0x0037: 761,
    0x0038: 761, 0x0039: 761, 0x003A: 761, 0x003B: 761, 0x003C: 761, 0x003D: 761, 0x003E: 761, 0x003F: 761,
    0x0040: 761, 0x0041: 761, 0x0042: 761, 0x0043: 761, 0x0044: 761, 0x0045: 761, 0x0046: 761, 0x0047: 761,
    0x0048: 761, 0x0049: 761, 0x004A: 761, 0x004B: 761, 0x004C: 761, 0x004D: 761, 0x004E: 761, 0x004F: 761,
    0x0050: 761, 0x0051: 761, 0x0052: 761, 0x0053: 761, 0x0054: 761, 0x0055: 761, 0x0056: 761, 0x0057: 761,
    0x0058: 761, 0x0059: 761, 0x005A: 761, 0x005B: 761, 0x005C: 761, 0x005D: 761, 0x005E: 761, 0x005F: 761,
    0x0060: 761, 0x0061: 761, 0x0062: 761, 0x0063: 761, 0x0064: 761, 0x0065: 761, 0x0066: 761, 0x0067: 761,
    0x0068: 761, 0x0069: 761, 0x006A: 761, 0x006B: 761, 0x006C: 761, 0x006D: 761, 0x006E: 761, 0x006F: 761,
    0x0070: 761, 0x0071: 761, 0x0072: 761, 0x0073: 761, 0x0074: 761, 0x0075: 761, 0x0076: 761, 0x0077: 761,
    0x0078: 761, 0x0079: 761, 0x007A: 761, 0x007B: 761, 0x007C: 761, 0x007D: 761, 0x007E: 761, 0x007F: 761,
    0x0080: 761, 0x0081: 761, 0x0082: 761, 0x0083: 761, 0x0084: 761, 0x0085: 761, 0x0086: 761, 0x0087: 761,
    0x0088: 761, 0x0089: 761, 0x008A: 761, 0x008B: 761, 0x008C: 761, 0x008D: 761, 0x008E: 761, 0x008F: 761,
    0x0090: 761, 0x0091: 761, 0x0092: 761, 0x0093: 761, 0x0094: 761, 0x0095: 761, 0x0096: 761, 0x0097: 761,
    0x0098: 761, 0x0099: 761, 0x009A: 761, 0x009B: 761, 0x009C: 761, 0x009D: 761, 0x009E: 761, 0x009F: 761,
    0x00A0: 761, 0x00A1: 761, 0x00A2: 761, 0x00A3: 761, 0x00A4: 761, 0x00A5: 761, 0x00A6: 761, 0x00A7: 761,
    0x00A8: 761, 0x00A9: 761, 0x00AA: 761, 0x00AB: 761, 0x00AC: 761, 0x00AD: 761, 0x00AE: 761, 0x00AF: 761,
    0x00B0: 761, 0x00B1: 761, 0x00B2: 761, 0x00B3: 761, 0x00B4: 761, 0x00B5: 761, 0x00B6: 761, 0x00B7: 761,
    0x00B8: 761, 0x00B9: 761, 0x00BA: 761, 0x00BB: 761, 0x00BC: 761, 0x00BD: 761, 0x00BE: 761, 0x00BF: 761,
    0x00C0: 761, 0x00C1: 761, 0x00C2: 761, 0x00C3: 761, 0x00C4: 761, 0x00C5: 761, 0x00C6: 761, 0x00C7: 761,
    0x00C8: 761, 0x00C9: 761, 0x00CA: 761, 0x00CB: 761, 0x00CC: 761, 0x00CD: 761, 0x00CE: 761, 0x00CF: 761,
    0x00D0: 761, 0x00D1: 761, 0x00D2: 761, 0x00D3: 761, 0x00D4: 761, 0x00D5: 761, 0x00D6: 761, 0x00D7: 761,
    0x00D8: 761, 0x00D9: 761, 0x00DA: 761, 0x00DB: 761, 0x00DC: 761, 0x00DD: 761, 0x00DE: 761, 0x00DF: 761,
    0x00E0: 761, 0x00E1: 761, 0x00E2: 761, 0x00E3: 761, 0x00E4: 761, 0x00E5: 761, 0x00E6: 761, 0x00E7: 761,
    0x00E8: 761, 0x00E9: 761, 0x00EA: 761, 0x00EB: 761, 0x00EC: 761, 0x00ED: 761, 0x00EE: 761, 0x00EF: 761,
    0x00F0: 761, 0x00F1: 761, 0x00F2: 761, 0x00F3: 761, 0x00F4: 761, 0x00F5: 761, 0x00F6: 761, 0x00F7: 761,
    0x00F8: 761, 0x00F9: 761, 0x00FA: 761, 0x00FB: 761, 0x00FC: 761, 0x00FD: 761, 0x00FE: 761, 0x00FF: 761,
  },
};

// Metric-compatible substitution for common non-standard base names.
const Map<String, String> _stdFontAliases = {
  'Arial': 'Helvetica', 'Arial-Bold': 'Helvetica-Bold',
  'Arial-Italic': 'Helvetica-Oblique', 'Arial-BoldItalic': 'Helvetica-BoldOblique',
  'TimesNewRoman': 'Times-Roman', 'TimesNewRoman-Bold': 'Times-Bold',
  'TimesNewRoman-Italic': 'Times-Italic', 'TimesNewRoman-BoldItalic': 'Times-BoldItalic',
  'CourierNew': 'Courier', 'CourierNew-Bold': 'Courier-Bold',
  'CourierNew-Italic': 'Courier-Oblique', 'CourierNew-BoldItalic': 'Courier-BoldOblique',
};

class _FontInfo {
  final bool composite; // Type0
  final int codeBytes; // 1 (simple) or 2 (Identity-H)
  final Map<int, String> toUnicode; // code → unicode string
  final Map<int, int> widths; // code/CID → width (1000/em)
  final int defaultWidth;
  final Map<int, String> diffNames; // Differences: code → glyph name
  final String? baseEncoding;
  final bool symbolicSkip; // Symbol / Dingbats → no text

  /// Standard-font AFM metrics (unicode → 1/1000 em) when this is one of
  /// the 14 standard fonts used WITHOUT /Widths — the viewer is expected
  /// to know them (PDF 32000 §9.6.2.2). Null for everything else.
  final Map<int, int>? stdUniWidths;

  _FontInfo({
    required this.composite,
    required this.codeBytes,
    required this.toUnicode,
    required this.widths,
    required this.defaultWidth,
    required this.diffNames,
    required this.baseEncoding,
    required this.symbolicSkip,
    this.stdUniWidths,
  });

  /// Resolves a /BaseFont name to the standard-font metrics family —
  /// strips the subset tag ("ABCDEF+Helvetica") and applies common
  /// metric-compatible aliases (Arial ↔ Helvetica, Times New Roman ↔
  /// Times, Courier New ↔ Courier).
  static Map<int, int>? _stdWidthsFor(String baseName) {
    var n = baseName;
    final plus = n.indexOf('+');
    if (plus >= 0 && plus <= 7) n = n.substring(plus + 1);
    n = n.trim();
    var w = _stdFontUniWidths[n] ?? _stdFontUniWidths[_stdFontAliases[n] ?? ''];
    if (w != null) return w;
    // Courier family: every glyph is 600.
    final lower = n.toLowerCase();
    if (lower.startsWith('courier')) return const {0x20: 600};
    return null;
  }

  static _FontInfo parse(_PdfDoc doc, Map<Object, Object> dict) {
    final sub = doc._resolveIndirect(dict[_PdfName('Subtype')]);
    final baseFont = doc._resolveIndirect(dict[_PdfName('BaseFont')]);
    final baseName = baseFont is _PdfName ? baseFont.value : '';
    final symbolic =
        baseName.contains('Symbol') || baseName.contains('Dingbat');

    var composite = false;
    var codeBytes = 1;
    final toUnicode = <int, String>{};
    final widths = <int, int>{};
    var defaultWidth = 500;
    final diffNames = <int, String>{};
    String? baseEncoding;
    var skip = false;
    Map<int, int>? stdW; // standard-font AFM metrics fallback

    if (sub == _PdfName('Type0')) {
      composite = true;
      codeBytes = 2;
      defaultWidth = 1000;
      final enc = doc._resolveIndirect(dict[_PdfName('Encoding')]);
      var identity = false;
      if (enc is _PdfName) {
        identity = enc.value.contains('Identity');
      }
      if (!identity) {
        // Only Identity-H/V encodings are supported (the overwhelmingly
        // common case); a custom CMap stream encoding is skipped.
        return _FontInfo(
          composite: true,
          codeBytes: 2,
          toUnicode: const {},
          widths: const {},
          defaultWidth: 1000,
          diffNames: const {},
          baseEncoding: null,
          symbolicSkip: true,
        );
      }
      final kids = doc._resolveIndirect(dict[_PdfName('DescendantFonts')]);
      if (kids is List && kids.isNotEmpty) {
        final kid = doc._resolveIndirect(kids.first);
        if (kid is Map<Object, Object>) {
          final dw = doc._resolveNum(kid[_PdfName('DW')]);
          if (dw != null) defaultWidth = dw.toInt();
          final wArr = doc._resolveIndirect(kid[_PdfName('W')]);
          if (wArr is List) _parseCidWidths(doc, wArr, widths);
        }
      }
    } else if (sub == _PdfName('Type3')) {
      skip = true; // Type3 glyphs have no usable encoding
    } else {
      // Simple font (Type1 / TrueType / MMType1).
      final fc = doc._resolveNum(dict[_PdfName('FirstChar')]);
      final wArr = doc._resolveIndirect(dict[_PdfName('Widths')]);
      if (wArr is List && fc != null) {
        for (var i = 0; i < wArr.length; i++) {
          final w = doc._resolveNum(wArr[i]);
          if (w != null) widths[fc.toInt() + i] = w.toInt();
        }
      }
      // No /Widths (or empty): one of the 14 standard fonts used
      // non-embedded — fall back to the built-in Adobe AFM metrics so
      // glyph advances, word boxes and selection rectangles are correct
      // (v2.5.0 silently used 500 for every glyph, inflating every box).
      if (widths.isEmpty) {
        stdW = _stdWidthsFor(baseName);
        if (stdW != null) {
          defaultWidth = stdW[0x20] ?? 500;
        }
      }
      final enc = doc._resolveIndirect(dict[_PdfName('Encoding')]);
      if (enc is _PdfName) {
        baseEncoding = enc.value;
      } else if (enc is Map<Object, Object>) {
        final be = doc._resolveIndirect(enc[_PdfName('BaseEncoding')]);
        if (be is _PdfName) baseEncoding = be.value;
        final diffs = doc._resolveIndirect(enc[_PdfName('Differences')]);
        if (diffs is List) {
          var code = 0;
          for (final d in diffs) {
            final v = doc._resolveIndirect(d);
            if (v is num) {
              code = v.toInt();
            } else if (v is _PdfName) {
              diffNames[code] = v.value;
              code++;
            }
          }
        }
      } else if (!symbolic) {
        baseEncoding = 'StandardEncoding';
      }
    }

    // ToUnicode CMap (both simple and composite).
    final tu = doc._resolveIndirect(dict[_PdfName('ToUnicode')]);
    if (tu is _PStream) {
      final data = doc._decodeStream(tu);
      if (data != null) _parseToUnicode(data, toUnicode);
    }

    return _FontInfo(
      composite: composite,
      codeBytes: codeBytes,
      toUnicode: toUnicode,
      widths: widths,
      defaultWidth: defaultWidth,
      diffNames: diffNames,
      baseEncoding: baseEncoding,
      symbolicSkip: (symbolic || skip) && toUnicode.isEmpty,
      stdUniWidths: stdW,
    );
  }

  static void _parseCidWidths(_PdfDoc doc, List wArr, Map<int, int> out) {
    var i = 0;
    while (i < wArr.length) {
      final c = doc._resolveNum(wArr[i]);
      if (c == null) {
        i++;
        continue;
      }
      if (i + 1 >= wArr.length) break;
      final next = doc._resolveIndirect(wArr[i + 1]);
      if (next is List) {
        // c [w1 w2 ...]
        for (var j = 0; j < next.length; j++) {
          final w = doc._resolveNum(next[j]);
          if (w != null) out[c.toInt() + j] = w.toInt();
        }
        i += 2;
      } else if (next is num && i + 2 < wArr.length) {
        final w = doc._resolveNum(wArr[i + 2]);
        if (w != null) {
          for (var cid = c.toInt(); cid <= next.toInt(); cid++) {
            out[cid] = w.toInt();
          }
        }
        i += 3;
      } else {
        i += 2;
      }
    }
  }

  /// Parses a ToUnicode CMap (bfchar + bfrange sections).
  static void _parseToUnicode(Uint8List data, Map<int, String> out) {
    final r = _Bytes(data);
    String? prevTok;
    while (!r.eof) {
      r.skipWs();
      if (r.eof) break;
      final c = r.peek();
      if (c == 0x3C) {
        // '<' — hex string, or a '<< dict >>' (e.g. /CIDSystemInfo).
        r.read();
        if (r.peek() == 0x3C) {
          r.read();
          _parseDict(r);
        } else {
          _parseHexString(r);
        }
        prevTok = null;
        continue;
      }
      if (c == 0x2F) {
        // '/Name' — read including the slash.
        r.read();
        prevTok = _readToken(r) ?? '';
        continue;
      }
      if (c == 0x28) {
        // '(literal string)' — skip.
        _parseLiteralString(r);
        prevTok = null;
        continue;
      }
      if (_isDelimiter(c)) {
        // Stray '[', ']' … — skip one byte.
        r.read();
        prevTok = null;
        continue;
      }
      final tok = _readToken(r);
      if (tok == null) break;
      if (tok == 'beginbfchar') {
        final count = int.tryParse(prevTok ?? '') ?? 0;
        for (var i = 0; i < count; i++) {
          r.skipWs();
          if (_matchesAt(data, r.pos, 'endbfchar')) break;
          final src = _readHex(r);
          final dst = _readHex(r);
          if (src == null || dst == null) continue;
          final code = _beBytesToInt(src);
          if (code != null) out[code] = _utf16BytesToString(dst);
        }
        prevTok = null;
      } else if (tok == 'beginbfrange') {
        final count = int.tryParse(prevTok ?? '') ?? 0;
        for (var i = 0; i < count; i++) {
          r.skipWs();
          if (_matchesAt(data, r.pos, 'endbfrange')) break;
          final lo = _readHex(r);
          final hi = _readHex(r);
          if (lo == null || hi == null) continue;
          r.skipWs();
          if (r.peek() == 0x5B) {
            r.read(); // [
            final code = _beBytesToInt(lo);
            final codeEnd = _beBytesToInt(hi);
            if (code == null || codeEnd == null) continue;
            var c = code;
            while (r.peek() != 0x5D && !r.eof) {
              r.skipWs();
              final d = _readHex(r);
              if (d == null) break;
              if (c <= codeEnd) {
                out[c] = _utf16BytesToString(d);
              }
              c++;
            }
            if (r.peek() == 0x5D) r.read();
          } else {
            final dst = _readHex(r);
            if (dst == null || dst.isEmpty) continue;
            final loI = _beBytesToInt(lo);
            final hiI = _beBytesToInt(hi);
            if (loI == null || hiI == null) continue;
            var dstInt = 0;
            for (final b in dst) {
              dstInt = dstInt * 256 + b;
            }
            final dstLen = dst.length;
            for (var c = loI;
                c <= hiI && c - loI < 65536 && c >= 0;
                c++) {
              var v = dstInt + (c - loI);
              final bytes = Uint8List(dstLen);
              for (var k = dstLen - 1; k >= 0; k--) {
                bytes[k] = v & 0xFF;
                v >>= 8;
              }
              out[c] = _utf16BytesToString(bytes);
            }
          }
        }
        prevTok = null;
      } else {
        prevTok = tok;
      }
    }
  }

  static Uint8List? _readHex(_Bytes r) {
    r.skipWs();
    if (r.eof) return null;
    if (r.peek() == 0x3C) {
      r.read();
      return _parseHexString(r);
    }
    if (r.peek() == 0x28) {
      return Uint8List.fromList(
          ((_parseLiteralString(r) as String?) ?? '').codeUnits);
    }
    _readToken(r); // skip a foreign token
    return null;
  }

  /// ToUnicode destination strings are UTF-16BE (per PDF 9.10.2) — an
  /// even byte count decodes as UTF-16BE, odd as 1-byte chars. A BOM, when
  /// present, is honored and stripped.
  static String _utf16BytesToString(Uint8List b) {
    if (b.isEmpty) return '';
    if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
      return _decodeUtf16(b.sublist(2), bigEndian: true);
    }
    if (b.length.isEven) return _decodeUtf16(b, bigEndian: true);
    return String.fromCharCodes(b);
  }

  static String _decodeUtf16(Uint8List b, {required bool bigEndian}) {
    final sb = StringBuffer();
    for (var i = 0; i + 1 < b.length; i += 2) {
      final u = bigEndian ? b[i] * 256 + b[i + 1] : b[i + 1] * 256 + b[i];
      if (u >= 0xD800 && u <= 0xDBFF && i + 3 < b.length) {
        final lo =
            bigEndian ? b[i + 2] * 256 + b[i + 3] : b[i + 3] * 256 + b[i + 2];
        if (lo >= 0xDC00 && lo <= 0xDFFF) {
          sb.writeCharCode(0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00));
          i += 2;
          continue;
        }
      }
      sb.writeCharCode(u);
    }
    return sb.toString();
  }

  static int? _beBytesToInt(Uint8List b) {
    if (b.isEmpty || b.length > 4) return null;
    var v = 0;
    for (final x in b) {
      v = v * 256 + x;
    }
    return v;
  }

  // ------------------------------------------------------------ lookups

  int widthOf(int code) {
    final w = widths[code];
    if (w != null) return w;
    final std = stdUniWidths;
    if (std != null) {
      // Map the code to its unicode (ToUnicode / Differences / base
      // encoding) and look the AFM width up by codepoint. Courier uses the
      // sentinel {0x20: 600} — every glyph is 600.
      if (std.length == 1) return std.values.first;
      final t = textOf(code);
      final r = t.runes.isEmpty ? 0 : t.runes.first;
      return std[r] ?? defaultWidth;
    }
    return defaultWidth;
  }

  String textOf(int code) {
    final tu = toUnicode[code];
    if (tu != null) return tu;
    final dn = diffNames[code];
    if (dn != null) return _glyphNameToUnicode(dn);
    switch (baseEncoding) {
      case 'WinAnsiEncoding':
        return _winAnsiChar(code);
      case 'MacRomanEncoding':
        return _macRomanChar(code);
      case 'StandardEncoding':
      default:
        return _standardChar(code);
    }
  }
}

// ---------------------------------------------------------------------------
// Encoding tables + glyph names
// ---------------------------------------------------------------------------

String _winAnsiChar(int c) {
  if (c >= 0x20 && c <= 0x7E) return String.fromCharCode(c);
  const high = <int, int>{
    0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026,
    0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160,
    0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019,
    0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
    0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153,
    0x9E: 0x017E, 0x9F: 0x0178,
  };
  final h = high[c];
  if (h != null) return String.fromCharCode(h);
  if (c >= 0xA0 && c <= 0xFF) return String.fromCharCode(c);
  return '';
}

String _macRomanChar(int c) {
  if (c >= 0x20 && c <= 0x7E) return String.fromCharCode(c);
  const high = <int, int>{
    0x80: 0x00C4, 0x81: 0x00C5, 0x82: 0x00C7, 0x83: 0x00C9, 0x84: 0x00D1,
    0x85: 0x00D6, 0x86: 0x00DC, 0x87: 0x00E1, 0x88: 0x00E0, 0x89: 0x00E2,
    0x8A: 0x00E4, 0x8B: 0x00E3, 0x8C: 0x00E5, 0x8D: 0x00E7, 0x8E: 0x00E9,
    0x8F: 0x00E8, 0x90: 0x00EA, 0x91: 0x00EB, 0x92: 0x00ED, 0x93: 0x00EC,
    0x94: 0x00EE, 0x95: 0x00EF, 0x96: 0x00F1, 0x97: 0x00F3, 0x98: 0x00F2,
    0x99: 0x00F4, 0x9A: 0x00F6, 0x9B: 0x00F5, 0x9C: 0x00FA, 0x9D: 0x00F9,
    0x9E: 0x00FB, 0x9F: 0x00FC, 0xA0: 0x2020, 0xA1: 0x00B0, 0xA2: 0x00A2,
    0xA3: 0x00A3, 0xA4: 0x00A7, 0xA5: 0x2022, 0xA6: 0x00B6, 0xA7: 0x00DF,
    0xA8: 0x00AE, 0xA9: 0x00A9, 0xAA: 0x2122, 0xAB: 0x00B4, 0xAC: 0x00A8,
    0xAD: 0x2260, 0xAE: 0x00C6, 0xAF: 0x00D8, 0xB0: 0x221E, 0xB1: 0x00B1,
    0xB2: 0x2264, 0xB3: 0x2265, 0xB4: 0x00A5, 0xB5: 0x00B5, 0xB6: 0x2202,
    0xB7: 0x2211, 0xB8: 0x220F, 0xB9: 0x03C0, 0xBA: 0x222B, 0xBB: 0x00AA,
    0xBC: 0x00BA, 0xBD: 0x03A9, 0xBE: 0x00E6, 0xBF: 0x00F8, 0xC0: 0x00BF,
    0xC1: 0x00A1, 0xC2: 0x00AC, 0xC3: 0x221A, 0xC4: 0x0192, 0xC5: 0x2248,
    0xC6: 0x2206, 0xC7: 0x00AB, 0xC8: 0x00BB, 0xC9: 0x2026, 0xCA: 0x2020,
    0xCB: 0x2021, 0xCC: 0x00C5, 0xCD: 0x2032, 0xCE: 0x2033, 0xCF: 0x2039,
    0xD0: 0x203A, 0xD1: 0x00C0, 0xD2: 0x00C3, 0xD3: 0x00D5, 0xD4: 0x0152,
    0xD5: 0x0153, 0xD6: 0x2013, 0xD7: 0x2014, 0xD8: 0x201C, 0xD9: 0x201D,
    0xDA: 0x2018, 0xDB: 0x2019, 0xDC: 0x00CA, 0xDD: 0x00CB, 0xDE: 0x00C8,
    0xDF: 0x00CD, 0xE0: 0x00CE, 0xE1: 0x00CF, 0xE2: 0x00CC, 0xE3: 0x00D3,
    0xE4: 0x00D4, 0xE5: 0xF8FF, 0xE6: 0x00D2, 0xE7: 0x00DA, 0xE8: 0x00DB,
    0xE9: 0x00D9, 0xEA: 0x0131, 0xEB: 0x02C6, 0xEC: 0x02DC, 0xED: 0x00AF,
    0xEE: 0x02D8, 0xEF: 0x02D9, 0xF0: 0x02DA, 0xF1: 0x00B8, 0xF2: 0x02DD,
    0xF3: 0x02DB, 0xF4: 0x02C7, 0xF5: 0x00B7, 0xF6: 0x00F7, 0xF7: 0x00B2,
    0xF8: 0x00B0, 0xF9: 0x2022, 0xFA: 0x00A0, 0xFB: 0x00E1, 0xFC: 0x00E0,
  };
  final h = high[c];
  if (h != null) return String.fromCharCode(h);
  return '';
}

String _standardChar(int c) {
  if (c >= 0x20 && c <= 0x7E) {
    if (c == 0x27) return '\u2019';
    if (c == 0x60) return '\u2018';
    return String.fromCharCode(c);
  }
  const high = <int, int>{
    0xA1: 0x00A1, 0xA2: 0x00A2, 0xA3: 0x00A3, 0xA5: 0x00A5, 0xA7: 0x00A7,
    0xA9: 0x0027, 0xAA: 0x201A, 0xAB: 0x00AB, 0xAC: 0x2122, 0xAD: 0x00AD,
    0xAE: 0x00AE, 0xB0: 0x00B0, 0xB1: 0x00B1, 0xB2: 0x2032, 0xB3: 0x2033,
    0xB4: 0x2039, 0xB5: 0x203A, 0xB6: 0x00B6, 0xB7: 0x00B7, 0xB8: 0x00B8,
    0xB9: 0x00B9, 0xBA: 0x00BA, 0xBB: 0x00BB, 0xBC: 0x201C, 0xBD: 0x201D,
    0xBE: 0x201E, 0xBF: 0x2019, 0xD0: 0x2013, 0xD1: 0x2014, 0xD2: 0x2015,
    0xD3: 0x00B2, 0xD4: 0x00B3, 0xD5: 0x00B4, 0xD6: 0x201C, 0xD8: 0x201E,
    0xD9: 0x2020, 0xDA: 0x2021, 0xDB: 0x00B7, 0xE3: 0x2039, 0xE4: 0x203A,
    0xF1: 0x2013, 0xF2: 0x2014,
  };
  final h = high[c];
  if (h != null) return String.fromCharCode(h);
  return '';
}

/// Adobe Glyph List subset (everyday Latin + common symbols).
const Map<String, String> _glyphNames = {
  'space': ' ', 'exclam': '!', 'quotedbl': '"', 'numbersign': '#',
  'dollar': '\$', 'percent': '%', 'ampersand': '&', 'quoteright': '\u2019',
  'parenleft': '(', 'parenright': ')', 'asterisk': '*', 'plus': '+',
  'comma': ',', 'hyphen': '-', 'period': '.', 'slash': '/',
  'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4',
  'five': '5', 'six': '6', 'seven': '7', 'eight': '8', 'nine': '9',
  'colon': ':', 'semicolon': ';', 'less': '<', 'equal': '=', 'greater': '>',
  'question': '?', 'at': '@', 'bracketleft': '[', 'backslash': '\\',
  'bracketright': ']', 'asciicircum': '^', 'underscore': '_',
  'quoteleft': '\u2018', 'braceleft': '{', 'bar': '|', 'braceright': '}',
  'asciitilde': '~', 'exclamdown': '\u00A1', 'cent': '\u00A2',
  'sterling': '\u00A3', 'currency': '\u00A4', 'yen': '\u00A5',
  'brokenbar': '\u00A6', 'section': '\u00A7', 'dieresis': '\u00A8',
  'copyright': '\u00A9', 'ordfeminine': '\u00AA', 'guillemotleft': '\u00AB',
  'logicalnot': '\u00AC', 'registered': '\u00AE', 'macron': '\u00AF',
  'degree': '\u00B0', 'plusminus': '\u00B1', 'acute': '\u00B4',
  'mu': '\u00B5', 'paragraph': '\u00B6', 'periodcentered': '\u00B7',
  'cedilla': '\u00B8', 'ordmasculine': '\u00BA', 'guillemotright': '\u00BB',
  'onequarter': '\u00BC', 'onehalf': '\u00BD', 'threequarters': '\u00BE',
  'questiondown': '\u00BF', 'Agrave': '\u00C0', 'Aacute': '\u00C1',
  'Acircumflex': '\u00C2', 'Atilde': '\u00C3', 'Adieresis': '\u00C4',
  'Aring': '\u00C5', 'AE': '\u00C6', 'Ccedilla': '\u00C7', 'Egrave': '\u00C8',
  'Eacute': '\u00C9', 'Ecircumflex': '\u00CA', 'Edieresis': '\u00CB',
  'Igrave': '\u00CC', 'Iacute': '\u00CD', 'Icircumflex': '\u00CE',
  'Idieresis': '\u00CF', 'Eth': '\u00D0', 'Ntilde': '\u00D1', 'Ograve': '\u00D2',
  'Oacute': '\u00D3', 'Ocircumflex': '\u00D4', 'Otilde': '\u00D5',
  'Odieresis': '\u00D6', 'multiply': '\u00D7', 'Oslash': '\u00D8',
  'Ugrave': '\u00D9', 'Uacute': '\u00DA', 'Ucircumflex': '\u00DB',
  'Udieresis': '\u00DC', 'Yacute': '\u00DD', 'Thorn': '\u00DE',
  'germandbls': '\u00DF', 'agrave': '\u00E0', 'aacute': '\u00E1',
  'acircumflex': '\u00E2', 'atilde': '\u00E3', 'adieresis': '\u00E4',
  'aring': '\u00E5', 'ae': '\u00E6', 'ccedilla': '\u00E7', 'egrave': '\u00E8',
  'eacute': '\u00E9', 'ecircumflex': '\u00EA', 'edieresis': '\u00EB',
  'igrave': '\u00EC', 'iacute': '\u00ED', 'icircumflex': '\u00EE',
  'idieresis': '\u00EF', 'eth': '\u00F0', 'ntilde': '\u00F1', 'ograve': '\u00F2',
  'oacute': '\u00F3', 'ocircumflex': '\u00F4', 'otilde': '\u00F5',
  'odieresis': '\u00F6', 'divide': '\u00F7', 'oslash': '\u00F8',
  'ugrave': '\u00F9', 'uacute': '\u00FA', 'ucircumflex': '\u00FB',
  'udieresis': '\u00FC', 'yacute': '\u00FD', 'thorn': '\u00FE',
  'ydieresis': '\u00FF', 'fi': '\uFB01', 'fl': '\uFB02', 'ffi': '\uFB03',
  'ffl': '\uFB04', 'quotesinglbase': '\u201A', 'quotedblbase': '\u201E',
  'quotedblleft': '\u201C', 'quotedblright': '\u201D', 'endash': '\u2013',
  'emdash': '\u2014', 'bullet': '\u2022', 'ellipsis': '\u2026',
  'perthousand': '\u2030', 'guilsinglleft': '\u2039',
  'guilsinglright': '\u203A', 'fraction': '\u2044', 'Euro': '\u20AC',
  'trademark': '\u2122', 'Omega': '\u03A9', 'alpha': '\u03B1',
  'beta': '\u03B2', 'pi': '\u03C0', 'Sigma': '\u03A3', 'sigma': '\u03C3',
  'micro': '\u00B5', 'Delta': '\u0394', 'nabla': '\u2207',
  'infinity': '\u221E', 'partialdiff': '\u2202', 'summation': '\u2211',
  'radical': '\u221A', 'approxequal': '\u2248', 'notequal': '\u2260',
  'lessequal': '\u2264', 'greaterequal': '\u2265', 'lozenge': '\u25CA',
  'arrowup': '\u2191', 'arrowdown': '\u2193', 'arrowleft': '\u2190',
  'arrowright': '\u2192', 'arrowboth': '\u2194', 'minute': '\u2032',
  'second': '\u2033', 'middot': '\u00B7', 'Lslash': '\u0141',
  'lslash': '\u0142', 'OE': '\u0152', 'oe': '\u0153', 'Scaron': '\u0160',
  'scaron': '\u0161', 'Ydieresis': '\u0178', 'Zcaron': '\u017D',
  'zcaron': '\u017E', 'dotlessi': '\u0131', 'circumflex': '\u02C6',
  'caron': '\u02C7', 'breve': '\u02D8', 'tilde': '\u02DC',
  'twosuperior': '\u00B2', 'threesuperior': '\u00B3', 'onesuperior': '\u00B9',
};

String _glyphNameToUnicode(String name) {
  // uniXXXX pattern → direct codepoint (AGL).
  if (name.length == 7 && name.startsWith('uni')) {
    final v = int.tryParse(name.substring(3), radix: 16);
    if (v != null && v > 0 && v != 0xFFFD) return String.fromCharCode(v);
  }
  // uXXXX[XX] pattern (AGL 1.2).
  if (name.length >= 5 && name.startsWith('u')) {
    final hex = name.substring(1).split('.').first;
    if (hex.length >= 4 && hex.length <= 6) {
      final v = int.tryParse(hex, radix: 16);
      if (v != null && v > 0 && v != 0xFFFD) return String.fromCharCode(v);
    }
  }
  if (name.length == 1) return name; // single-letter names ('a'..'z')
  return _glyphNames[name] ?? '';
}

// ---------------------------------------------------------------------------
// Content-stream interpreter
// ---------------------------------------------------------------------------

// Arabic presentation forms (Arabic Presentation Forms-A/B as
// stored by shaped PDF text) normalized to base letters, so that
// copied / translated / searched text reads 'اختبار' not 'ﺧﺘﺒﺎﺭ'.
// Generated from the Unicode NFKC decompositions (leading spaces of
// isolated marks removed; non-Arabic and multi-word results skipped).
const Map<int, String> _arabicPresentationForms = {
  0xFB50: 'ٱ', 0xFB51: 'ٱ', 0xFB52: 'ٻ', 0xFB53: 'ٻ', 0xFB54: 'ٻ', 0xFB55: 'ٻ',
  0xFB56: 'پ', 0xFB57: 'پ', 0xFB58: 'پ', 0xFB59: 'پ', 0xFB5A: 'ڀ', 0xFB5B: 'ڀ',
  0xFB5C: 'ڀ', 0xFB5D: 'ڀ', 0xFB5E: 'ٺ', 0xFB5F: 'ٺ', 0xFB60: 'ٺ', 0xFB61: 'ٺ',
  0xFB62: 'ٿ', 0xFB63: 'ٿ', 0xFB64: 'ٿ', 0xFB65: 'ٿ', 0xFB66: 'ٹ', 0xFB67: 'ٹ',
  0xFB68: 'ٹ', 0xFB69: 'ٹ', 0xFB6A: 'ڤ', 0xFB6B: 'ڤ', 0xFB6C: 'ڤ', 0xFB6D: 'ڤ',
  0xFB6E: 'ڦ', 0xFB6F: 'ڦ', 0xFB70: 'ڦ', 0xFB71: 'ڦ', 0xFB72: 'ڄ', 0xFB73: 'ڄ',
  0xFB74: 'ڄ', 0xFB75: 'ڄ', 0xFB76: 'ڃ', 0xFB77: 'ڃ', 0xFB78: 'ڃ', 0xFB79: 'ڃ',
  0xFB7A: 'چ', 0xFB7B: 'چ', 0xFB7C: 'چ', 0xFB7D: 'چ', 0xFB7E: 'ڇ', 0xFB7F: 'ڇ',
  0xFB80: 'ڇ', 0xFB81: 'ڇ', 0xFB82: 'ڍ', 0xFB83: 'ڍ', 0xFB84: 'ڌ', 0xFB85: 'ڌ',
  0xFB86: 'ڎ', 0xFB87: 'ڎ', 0xFB88: 'ڈ', 0xFB89: 'ڈ', 0xFB8A: 'ژ', 0xFB8B: 'ژ',
  0xFB8C: 'ڑ', 0xFB8D: 'ڑ', 0xFB8E: 'ک', 0xFB8F: 'ک', 0xFB90: 'ک', 0xFB91: 'ک',
  0xFB92: 'گ', 0xFB93: 'گ', 0xFB94: 'گ', 0xFB95: 'گ', 0xFB96: 'ڳ', 0xFB97: 'ڳ',
  0xFB98: 'ڳ', 0xFB99: 'ڳ', 0xFB9A: 'ڱ', 0xFB9B: 'ڱ', 0xFB9C: 'ڱ', 0xFB9D: 'ڱ',
  0xFB9E: 'ں', 0xFB9F: 'ں', 0xFBA0: 'ڻ', 0xFBA1: 'ڻ', 0xFBA2: 'ڻ', 0xFBA3: 'ڻ',
  0xFBA4: 'ۀ', 0xFBA5: 'ۀ', 0xFBA6: 'ہ', 0xFBA7: 'ہ', 0xFBA8: 'ہ', 0xFBA9: 'ہ',
  0xFBAA: 'ھ', 0xFBAB: 'ھ', 0xFBAC: 'ھ', 0xFBAD: 'ھ', 0xFBAE: 'ے', 0xFBAF: 'ے',
  0xFBB0: 'ۓ', 0xFBB1: 'ۓ', 0xFBD3: 'ڭ', 0xFBD4: 'ڭ', 0xFBD5: 'ڭ', 0xFBD6: 'ڭ',
  0xFBD7: 'ۇ', 0xFBD8: 'ۇ', 0xFBD9: 'ۆ', 0xFBDA: 'ۆ', 0xFBDB: 'ۈ', 0xFBDC: 'ۈ',
  0xFBDD: 'ٴۇ', 0xFBDE: 'ۋ', 0xFBDF: 'ۋ', 0xFBE0: 'ۅ', 0xFBE1: 'ۅ', 0xFBE2: 'ۉ',
  0xFBE3: 'ۉ', 0xFBE4: 'ې', 0xFBE5: 'ې', 0xFBE6: 'ې', 0xFBE7: 'ې', 0xFBE8: 'ى',
  0xFBE9: 'ى', 0xFBEA: 'ائ', 0xFBEB: 'ائ', 0xFBEC: 'ەئ', 0xFBED: 'ەئ', 0xFBEE: 'وئ',
  0xFBEF: 'وئ', 0xFBF0: 'ۇئ', 0xFBF1: 'ۇئ', 0xFBF2: 'ۆئ', 0xFBF3: 'ۆئ', 0xFBF4: 'ۈئ',
  0xFBF5: 'ۈئ', 0xFBF6: 'ېئ', 0xFBF7: 'ېئ', 0xFBF8: 'ېئ', 0xFBF9: 'ىئ', 0xFBFA: 'ىئ',
  0xFBFB: 'ىئ', 0xFBFC: 'ی', 0xFBFD: 'ی', 0xFBFE: 'ی', 0xFBFF: 'ی', 0xFC00: 'جئ',
  0xFC01: 'حئ', 0xFC02: 'مئ', 0xFC03: 'ىئ', 0xFC04: 'يئ', 0xFC05: 'جب', 0xFC06: 'حب',
  0xFC07: 'خب', 0xFC08: 'مب', 0xFC09: 'ىب', 0xFC0A: 'يب', 0xFC0B: 'جت', 0xFC0C: 'حت',
  0xFC0D: 'خت', 0xFC0E: 'مت', 0xFC0F: 'ىت', 0xFC10: 'يت', 0xFC11: 'جث', 0xFC12: 'مث',
  0xFC13: 'ىث', 0xFC14: 'يث', 0xFC15: 'حج', 0xFC16: 'مج', 0xFC17: 'جح', 0xFC18: 'مح',
  0xFC19: 'جخ', 0xFC1A: 'حخ', 0xFC1B: 'مخ', 0xFC1C: 'جس', 0xFC1D: 'حس', 0xFC1E: 'خس',
  0xFC1F: 'مس', 0xFC20: 'حص', 0xFC21: 'مص', 0xFC22: 'جض', 0xFC23: 'حض', 0xFC24: 'خض',
  0xFC25: 'مض', 0xFC26: 'حط', 0xFC27: 'مط', 0xFC28: 'مظ', 0xFC29: 'جع', 0xFC2A: 'مع',
  0xFC2B: 'جغ', 0xFC2C: 'مغ', 0xFC2D: 'جف', 0xFC2E: 'حف', 0xFC2F: 'خف', 0xFC30: 'مف',
  0xFC31: 'ىف', 0xFC32: 'يف', 0xFC33: 'حق', 0xFC34: 'مق', 0xFC35: 'ىق', 0xFC36: 'يق',
  0xFC37: 'اك', 0xFC38: 'جك', 0xFC39: 'حك', 0xFC3A: 'خك', 0xFC3B: 'لك', 0xFC3C: 'مك',
  0xFC3D: 'ىك', 0xFC3E: 'يك', 0xFC3F: 'جل', 0xFC40: 'حل', 0xFC41: 'خل', 0xFC42: 'مل',
  0xFC43: 'ىل', 0xFC44: 'يل', 0xFC45: 'جم', 0xFC46: 'حم', 0xFC47: 'خم', 0xFC48: 'مم',
  0xFC49: 'ىم', 0xFC4A: 'يم', 0xFC4B: 'جن', 0xFC4C: 'حن', 0xFC4D: 'خن', 0xFC4E: 'من',
  0xFC4F: 'ىن', 0xFC50: 'ين', 0xFC51: 'جه', 0xFC52: 'مه', 0xFC53: 'ىه', 0xFC54: 'يه',
  0xFC55: 'جي', 0xFC56: 'حي', 0xFC57: 'خي', 0xFC58: 'مي', 0xFC59: 'ىي', 0xFC5A: 'يي',
  0xFC5B: 'ٰذ', 0xFC5C: 'ٰر', 0xFC5D: 'ٰى', 0xFC5E: 'ٌّ', 0xFC5F: 'ٍّ', 0xFC60: 'َّ',
  0xFC61: 'ُّ', 0xFC62: 'ِّ', 0xFC63: 'ّٰ', 0xFC64: 'رئ', 0xFC65: 'زئ', 0xFC66: 'مئ',
  0xFC67: 'نئ', 0xFC68: 'ىئ', 0xFC69: 'يئ', 0xFC6A: 'رب', 0xFC6B: 'زب', 0xFC6C: 'مب',
  0xFC6D: 'نب', 0xFC6E: 'ىب', 0xFC6F: 'يب', 0xFC70: 'رت', 0xFC71: 'زت', 0xFC72: 'مت',
  0xFC73: 'نت', 0xFC74: 'ىت', 0xFC75: 'يت', 0xFC76: 'رث', 0xFC77: 'زث', 0xFC78: 'مث',
  0xFC79: 'نث', 0xFC7A: 'ىث', 0xFC7B: 'يث', 0xFC7C: 'ىف', 0xFC7D: 'يف', 0xFC7E: 'ىق',
  0xFC7F: 'يق', 0xFC80: 'اك', 0xFC81: 'لك', 0xFC82: 'مك', 0xFC83: 'ىك', 0xFC84: 'يك',
  0xFC85: 'مل', 0xFC86: 'ىل', 0xFC87: 'يل', 0xFC88: 'ام', 0xFC89: 'مم', 0xFC8A: 'رن',
  0xFC8B: 'زن', 0xFC8C: 'من', 0xFC8D: 'نن', 0xFC8E: 'ىن', 0xFC8F: 'ين', 0xFC90: 'ٰى',
  0xFC91: 'ري', 0xFC92: 'زي', 0xFC93: 'مي', 0xFC94: 'ني', 0xFC95: 'ىي', 0xFC96: 'يي',
  0xFC97: 'جئ', 0xFC98: 'حئ', 0xFC99: 'خئ', 0xFC9A: 'مئ', 0xFC9B: 'هئ', 0xFC9C: 'جب',
  0xFC9D: 'حب', 0xFC9E: 'خب', 0xFC9F: 'مب', 0xFCA0: 'هب', 0xFCA1: 'جت', 0xFCA2: 'حت',
  0xFCA3: 'خت', 0xFCA4: 'مت', 0xFCA5: 'هت', 0xFCA6: 'مث', 0xFCA7: 'حج', 0xFCA8: 'مج',
  0xFCA9: 'جح', 0xFCAA: 'مح', 0xFCAB: 'جخ', 0xFCAC: 'مخ', 0xFCAD: 'جس', 0xFCAE: 'حس',
  0xFCAF: 'خس', 0xFCB0: 'مس', 0xFCB1: 'حص', 0xFCB2: 'خص', 0xFCB3: 'مص', 0xFCB4: 'جض',
  0xFCB5: 'حض', 0xFCB6: 'خض', 0xFCB7: 'مض', 0xFCB8: 'حط', 0xFCB9: 'مظ', 0xFCBA: 'جع',
  0xFCBB: 'مع', 0xFCBC: 'جغ', 0xFCBD: 'مغ', 0xFCBE: 'جف', 0xFCBF: 'حف', 0xFCC0: 'خف',
  0xFCC1: 'مف', 0xFCC2: 'حق', 0xFCC3: 'مق', 0xFCC4: 'جك', 0xFCC5: 'حك', 0xFCC6: 'خك',
  0xFCC7: 'لك', 0xFCC8: 'مك', 0xFCC9: 'جل', 0xFCCA: 'حل', 0xFCCB: 'خل', 0xFCCC: 'مل',
  0xFCCD: 'هل', 0xFCCE: 'جم', 0xFCCF: 'حم', 0xFCD0: 'خم', 0xFCD1: 'مم', 0xFCD2: 'جن',
  0xFCD3: 'حن', 0xFCD4: 'خن', 0xFCD5: 'من', 0xFCD6: 'هن', 0xFCD7: 'جه', 0xFCD8: 'مه',
  0xFCD9: 'ٰه', 0xFCDA: 'جي', 0xFCDB: 'حي', 0xFCDC: 'خي', 0xFCDD: 'مي', 0xFCDE: 'هي',
  0xFCDF: 'مئ', 0xFCE0: 'هئ', 0xFCE1: 'مب', 0xFCE2: 'هب', 0xFCE3: 'مت', 0xFCE4: 'هت',
  0xFCE5: 'مث', 0xFCE6: 'هث', 0xFCE7: 'مس', 0xFCE8: 'هس', 0xFCE9: 'مش', 0xFCEA: 'هش',
  0xFCEB: 'لك', 0xFCEC: 'مك', 0xFCED: 'مل', 0xFCEE: 'من', 0xFCEF: 'هن', 0xFCF0: 'مي',
  0xFCF1: 'هي', 0xFCF2: 'َّـ', 0xFCF3: 'ُّـ', 0xFCF4: 'ِّـ', 0xFCF5: 'ىط', 0xFCF6: 'يط',
  0xFCF7: 'ىع', 0xFCF8: 'يع', 0xFCF9: 'ىغ', 0xFCFA: 'يغ', 0xFCFB: 'ىس', 0xFCFC: 'يس',
  0xFCFD: 'ىش', 0xFCFE: 'يش', 0xFCFF: 'ىح', 0xFD00: 'يح', 0xFD01: 'ىج', 0xFD02: 'يج',
  0xFD03: 'ىخ', 0xFD04: 'يخ', 0xFD05: 'ىص', 0xFD06: 'يص', 0xFD07: 'ىض', 0xFD08: 'يض',
  0xFD09: 'جش', 0xFD0A: 'حش', 0xFD0B: 'خش', 0xFD0C: 'مش', 0xFD0D: 'رش', 0xFD0E: 'رس',
  0xFD0F: 'رص', 0xFD10: 'رض', 0xFD11: 'ىط', 0xFD12: 'يط', 0xFD13: 'ىع', 0xFD14: 'يع',
  0xFD15: 'ىغ', 0xFD16: 'يغ', 0xFD17: 'ىس', 0xFD18: 'يس', 0xFD19: 'ىش', 0xFD1A: 'يش',
  0xFD1B: 'ىح', 0xFD1C: 'يح', 0xFD1D: 'ىج', 0xFD1E: 'يج', 0xFD1F: 'ىخ', 0xFD20: 'يخ',
  0xFD21: 'ىص', 0xFD22: 'يص', 0xFD23: 'ىض', 0xFD24: 'يض', 0xFD25: 'جش', 0xFD26: 'حش',
  0xFD27: 'خش', 0xFD28: 'مش', 0xFD29: 'رش', 0xFD2A: 'رس', 0xFD2B: 'رص', 0xFD2C: 'رض',
  0xFD2D: 'جش', 0xFD2E: 'حش', 0xFD2F: 'خش', 0xFD30: 'مش', 0xFD31: 'هس', 0xFD32: 'هش',
  0xFD33: 'مط', 0xFD34: 'جس', 0xFD35: 'حس', 0xFD36: 'خس', 0xFD37: 'جش', 0xFD38: 'حش',
  0xFD39: 'خش', 0xFD3A: 'مط', 0xFD3B: 'مظ', 0xFD3C: 'ًا', 0xFD3D: 'ًا', 0xFD50: 'مجت',
  0xFD51: 'جحت', 0xFD52: 'جحت', 0xFD53: 'محت', 0xFD54: 'مخت', 0xFD55: 'جمت', 0xFD56: 'حمت',
  0xFD57: 'خمت', 0xFD58: 'حمج', 0xFD59: 'حمج', 0xFD5A: 'يمح', 0xFD5B: 'ىمح', 0xFD5C: 'جحس',
  0xFD5D: 'حجس', 0xFD5E: 'ىجس', 0xFD5F: 'حمس', 0xFD60: 'حمس', 0xFD61: 'جمس', 0xFD62: 'ممس',
  0xFD63: 'ممس', 0xFD64: 'ححص', 0xFD65: 'ححص', 0xFD66: 'ممص', 0xFD67: 'محش', 0xFD68: 'محش',
  0xFD69: 'يجش', 0xFD6A: 'خمش', 0xFD6B: 'خمش', 0xFD6C: 'ممش', 0xFD6D: 'ممش', 0xFD6E: 'ىحض',
  0xFD6F: 'مخض', 0xFD70: 'مخض', 0xFD71: 'حمط', 0xFD72: 'حمط', 0xFD73: 'ممط', 0xFD74: 'يمط',
  0xFD75: 'مجع', 0xFD76: 'ممع', 0xFD77: 'ممع', 0xFD78: 'ىمع', 0xFD79: 'ممغ', 0xFD7A: 'يمغ',
  0xFD7B: 'ىمغ', 0xFD7C: 'مخف', 0xFD7D: 'مخف', 0xFD7E: 'حمق', 0xFD7F: 'ممق', 0xFD80: 'محل',
  0xFD81: 'يحل', 0xFD82: 'ىحل', 0xFD83: 'ججل', 0xFD84: 'ججل', 0xFD85: 'مخل', 0xFD86: 'مخل',
  0xFD87: 'حمل', 0xFD88: 'حمل', 0xFD89: 'جحم', 0xFD8A: 'محم', 0xFD8B: 'يحم', 0xFD8C: 'حجم',
  0xFD8D: 'مجم', 0xFD8E: 'جخم', 0xFD8F: 'مخم', 0xFD92: 'خجم', 0xFD93: 'جمه', 0xFD94: 'ممه',
  0xFD95: 'محن', 0xFD96: 'ىحن', 0xFD97: 'مجن', 0xFD98: 'مجن', 0xFD99: 'ىجن', 0xFD9A: 'يمن',
  0xFD9B: 'ىمن', 0xFD9C: 'ممي', 0xFD9D: 'ممي', 0xFD9E: 'يخب', 0xFD9F: 'يجت', 0xFDA0: 'ىجت',
  0xFDA1: 'يخت', 0xFDA2: 'ىخت', 0xFDA3: 'يمت', 0xFDA4: 'ىمت', 0xFDA5: 'يمج', 0xFDA6: 'ىحج',
  0xFDA7: 'ىمج', 0xFDA8: 'ىخس', 0xFDA9: 'يحص', 0xFDAA: 'يحش', 0xFDAB: 'يحض', 0xFDAC: 'يجل',
  0xFDAD: 'يمل', 0xFDAE: 'يحي', 0xFDAF: 'يجي', 0xFDB0: 'يمي', 0xFDB1: 'يمم', 0xFDB2: 'يمق',
  0xFDB3: 'يحن', 0xFDB4: 'حمق', 0xFDB5: 'محل', 0xFDB6: 'يمع', 0xFDB7: 'يمك', 0xFDB8: 'حجن',
  0xFDB9: 'يخم', 0xFDBA: 'مجل', 0xFDBB: 'ممك', 0xFDBC: 'مجل', 0xFDBD: 'حجن', 0xFDBE: 'يحج',
  0xFDBF: 'يجح', 0xFDC0: 'يجم', 0xFDC1: 'يمف', 0xFDC2: 'يحب', 0xFDC3: 'ممك', 0xFDC4: 'مجع',
  0xFDC5: 'ممص', 0xFDC6: 'يخس', 0xFDC7: 'يجن', 0xFDF0: 'ےلص', 0xFDF1: 'ےلق', 0xFDF2: 'هللا',
  0xFDF3: 'ربكا', 0xFDF4: 'دمحم', 0xFDF5: 'معلص', 0xFDF6: 'لوسر', 0xFDF7: 'هيلع', 0xFDF8: 'ملسو',
  0xFDF9: 'ىلص', 0xFDFC: 'لایر', 0xFE70: 'ً', 0xFE71: 'ًـ', 0xFE72: 'ٌ', 0xFE74: 'ٍ',
  0xFE76: 'َ', 0xFE77: 'َـ', 0xFE78: 'ُ', 0xFE79: 'ُـ', 0xFE7A: 'ِ', 0xFE7B: 'ِـ',
  0xFE7C: 'ّ', 0xFE7D: 'ّـ', 0xFE7E: 'ْ', 0xFE7F: 'ْـ', 0xFE80: 'ء', 0xFE81: 'آ',
  0xFE82: 'آ', 0xFE83: 'أ', 0xFE84: 'أ', 0xFE85: 'ؤ', 0xFE86: 'ؤ', 0xFE87: 'إ',
  0xFE88: 'إ', 0xFE89: 'ئ', 0xFE8A: 'ئ', 0xFE8B: 'ئ', 0xFE8C: 'ئ', 0xFE8D: 'ا',
  0xFE8E: 'ا', 0xFE8F: 'ب', 0xFE90: 'ب', 0xFE91: 'ب', 0xFE92: 'ب', 0xFE93: 'ة',
  0xFE94: 'ة', 0xFE95: 'ت', 0xFE96: 'ت', 0xFE97: 'ت', 0xFE98: 'ت', 0xFE99: 'ث',
  0xFE9A: 'ث', 0xFE9B: 'ث', 0xFE9C: 'ث', 0xFE9D: 'ج', 0xFE9E: 'ج', 0xFE9F: 'ج',
  0xFEA0: 'ج', 0xFEA1: 'ح', 0xFEA2: 'ح', 0xFEA3: 'ح', 0xFEA4: 'ح', 0xFEA5: 'خ',
  0xFEA6: 'خ', 0xFEA7: 'خ', 0xFEA8: 'خ', 0xFEA9: 'د', 0xFEAA: 'د', 0xFEAB: 'ذ',
  0xFEAC: 'ذ', 0xFEAD: 'ر', 0xFEAE: 'ر', 0xFEAF: 'ز', 0xFEB0: 'ز', 0xFEB1: 'س',
  0xFEB2: 'س', 0xFEB3: 'س', 0xFEB4: 'س', 0xFEB5: 'ش', 0xFEB6: 'ش', 0xFEB7: 'ش',
  0xFEB8: 'ش', 0xFEB9: 'ص', 0xFEBA: 'ص', 0xFEBB: 'ص', 0xFEBC: 'ص', 0xFEBD: 'ض',
  0xFEBE: 'ض', 0xFEBF: 'ض', 0xFEC0: 'ض', 0xFEC1: 'ط', 0xFEC2: 'ط', 0xFEC3: 'ط',
  0xFEC4: 'ط', 0xFEC5: 'ظ', 0xFEC6: 'ظ', 0xFEC7: 'ظ', 0xFEC8: 'ظ', 0xFEC9: 'ع',
  0xFECA: 'ع', 0xFECB: 'ع', 0xFECC: 'ع', 0xFECD: 'غ', 0xFECE: 'غ', 0xFECF: 'غ',
  0xFED0: 'غ', 0xFED1: 'ف', 0xFED2: 'ف', 0xFED3: 'ف', 0xFED4: 'ف', 0xFED5: 'ق',
  0xFED6: 'ق', 0xFED7: 'ق', 0xFED8: 'ق', 0xFED9: 'ك', 0xFEDA: 'ك', 0xFEDB: 'ك',
  0xFEDC: 'ك', 0xFEDD: 'ل', 0xFEDE: 'ل', 0xFEDF: 'ل', 0xFEE0: 'ل', 0xFEE1: 'م',
  0xFEE2: 'م', 0xFEE3: 'م', 0xFEE4: 'م', 0xFEE5: 'ن', 0xFEE6: 'ن', 0xFEE7: 'ن',
  0xFEE8: 'ن', 0xFEE9: 'ه', 0xFEEA: 'ه', 0xFEEB: 'ه', 0xFEEC: 'ه', 0xFEED: 'و',
  0xFEEE: 'و', 0xFEEF: 'ى', 0xFEF0: 'ى', 0xFEF1: 'ي', 0xFEF2: 'ي', 0xFEF3: 'ي',
  0xFEF4: 'ي', 0xFEF5: 'آل', 0xFEF6: 'آل', 0xFEF7: 'أل', 0xFEF8: 'أل', 0xFEF9: 'إل',
  0xFEFA: 'إل', 0xFEFB: 'ال', 0xFEFC: 'ال',
};

/// Normalizes shaped-Arabic presentation forms to base letters. Multi-char
/// expansions (lam-alef ligatures etc.) come in [ligaturesVisual] order when
/// the word was stored visually (leftmost expansion char first), or logical
/// order for logically-stored words.
String _mapArabicForms(String s, {required bool ligaturesVisual}) {
  if (!s.codeUnits.any((c) => c >= 0xFB50 && c <= 0xFEFF)) return s;
  final sb = StringBuffer();
  for (final r in s.runes) {
    final m = _arabicPresentationForms[r];
    if (m == null) {
      sb.writeCharCode(r);
    } else if (m.length == 1 || ligaturesVisual) {
      sb.write(m);
    } else {
      // Logical ligature order = reverse of the stored visual order.
      for (final c in m.runes.toList().reversed) {
        sb.writeCharCode(c);
      }
    }
  }
  return sb.toString();
}

bool _hasPresentationForms(String s) =>
    s.codeUnits.any((c) => c >= 0xFB50 && c <= 0xFEFF);

String _reverseCodepoints(String s) {
  final rs = s.runes.toList();
  final sb = StringBuffer();
  for (final r in rs.reversed) {
    sb.writeCharCode(r);
  }
  return sb.toString();
}

class _Glyph {
  final String text;
  final double x0, y0, x1, y1; // user space (unrotated, y-up)
  final double baselineY;
  final double size;
  final bool isSpace;

  /// Extraction (content-stream) order — used to detect whether an RTL
  /// word was stored visually (right-to-left) or naively left-to-right.
  final int seq;

  const _Glyph(this.text, this.x0, this.y0, this.x1, this.y1, this.baselineY,
      this.size, this.isSpace, this.seq);
}

/// 2×3 affine matrix [a b c d e f]; row-vector: p' = p × M.
class _M {
  final double a, b, c, d, e, f;
  const _M(this.a, this.b, this.c, this.d, this.e, this.f);
  static const _M id = _M(1, 0, 0, 1, 0, 0);

  _M mul(_M o) => _M(
        a * o.a + b * o.c,
        a * o.b + b * o.d,
        c * o.a + d * o.c,
        c * o.b + d * o.d,
        e * o.a + f * o.c + o.e,
        e * o.b + f * o.d + o.f,
      );

  double applyX(double x, double y) => a * x + c * y + e;
  double applyY(double x, double y) => b * x + d * y + f;
}

class _GState {
  _M ctm = _M.id;
  _FontInfo? font;
  double fontSize = 0;
  double tc = 0, tw = 0, tz = 100, tl = 0, ts = 0;
  _GState clone() {
    final s = _GState();
    s.ctm = ctm;
    s.font = font;
    s.fontSize = fontSize;
    s.tc = tc;
    s.tw = tw;
    s.tz = tz;
    s.tl = tl;
    s.ts = ts;
    return s;
  }
}

List<_Glyph> _interpretContent(Uint8List content, _PdfDoc doc,
    Map<String, _FontInfo> fonts, Map<String, _PStream> xobjs,
    {_M? baseCtm, int depth = 0, Set<_PStream>? inProgress}) {
  final glyphs = <_Glyph>[];
  final r = _Bytes(content);
  final stack = <_GState>[];
  var gs = _GState()..ctm = baseCtm ?? _M.id;
  var tlm = _M.id; // text line matrix
  var tm = _M.id; // text matrix
  var inText = false;
  final operands = <Object?>[];
  final forms = inProgress ?? <_PStream>{};

  /// FORM XOBJECT RECURSION ('/Fx Do'): Chrome print-to-PDF, wkhtmltopdf,
  /// Word exports and pymupdf's htmlbox all wrap the page text inside
  /// Form XObjects — without recursing into them NO text is found on
  /// such pages (v2.5.0 returned an empty page). The form's own
  /// /Resources overlay the caller's; its /Matrix composes with the
  /// current CTM; cycles and deep nesting are guarded.
  void runForm(String name) {
    if (depth >= 8) return;
    final xobj = xobjs[name];
    if (xobj == null || forms.contains(xobj)) return;
    final sub = doc._resolveIndirect(xobj.dict[_PdfName('Subtype')]);
    if (sub != _PdfName('Form')) return; // image XObject → nothing to do
    final mArr = doc._resolveIndirect(xobj.dict[_PdfName('Matrix')]);
    var m = _M.id;
    if (mArr is List && mArr.length == 6) {
      m = _M(
        _opNum(mArr, 0),
        _opNum(mArr, 1),
        _opNum(mArr, 2),
        _opNum(mArr, 3),
        _opNum(mArr, 4),
        _opNum(mArr, 5),
      );
    }
    final data = doc._decodeStream(xobj);
    if (data == null || data.isEmpty) return;
    // Resources: the form's own, overlaid on the caller's (inheritance
    // per PDF 32000 §7.8.3 when /Resources is absent).
    var fFonts = fonts;
    var fXobjs = xobjs;
    final rObj = doc._resolveIndirect(xobj.dict[_PdfName('Resources')]);
    if (rObj is Map<Object, Object>) {
      final nf = Map<String, _FontInfo>.of(fonts);
      final nx = Map<String, _PStream>.of(xobjs);
      final fd = doc._resolveIndirect(rObj[_PdfName('Font')]);
      if (fd is Map<Object, Object>) {
        fd.forEach((k, v) {
          if (k is! _PdfName) return;
          final f = doc._resolveIndirect(v);
          if (f is Map<Object, Object>) {
            nf[k.value] = _FontInfo.parse(doc, f);
          }
        });
      }
      final xd = doc._resolveIndirect(rObj[_PdfName('XObject')]);
      if (xd is Map<Object, Object>) {
        xd.forEach((k, v) {
          if (k is! _PdfName) return;
          final s = doc._resolveIndirect(v);
          if (s is _PStream) nx[k.value] = s;
        });
      }
      fFonts = nf;
      fXobjs = nx;
    }
    final savedCtm = gs.ctm;
    final composedCtm = m.mul(gs.ctm);
    final savedInText = inText;
    inText = false;
    forms.add(xobj);
    glyphs.addAll(_interpretContent(data, doc, fFonts, fXobjs,
        baseCtm: composedCtm, depth: depth + 1, inProgress: forms));
    forms.remove(xobj);
    inText = savedInText;
    gs.ctm = savedCtm;
  }

  void showString(Object? s) {
    Uint8List bytes;
    if (s is String) {
      bytes = Uint8List.fromList(s.codeUnits);
    } else if (s is Uint8List) {
      bytes = s;
    } else {
      return;
    }
    final font = gs.font;
    if (font == null || font.symbolicSkip || gs.fontSize <= 0) return;
    final th = gs.tz / 100.0;
    var i = 0;
    while (i + font.codeBytes <= bytes.length) {
      var code = bytes[i];
      if (font.codeBytes == 2) {
        code = bytes[i] * 256 + bytes[i + 1];
        i += 2;
      } else {
        i += 1;
      }
      var text = font.textOf(code);
      final w0 = font.widthOf(code);
      // PDF 32000-1:2008 §9.4.3 — the per-glyph displacement in USER
      // units: Tx = ((w0/1000)×Tfs + Tc + Tw)×Th. Tc/Tw are UNSCALED text
      // space units (NOT divided by 1000, NOT multiplied by the size), and
      // Th scales the whole displacement.
      final spaceTw = code == 0x20 && !font.composite ? gs.tw : 0.0;
      final txUser =
          ((w0 / 1000.0) * gs.fontSize + gs.tc + spaceTw) * th;
      // The glyph quad spans the advance in TEXT-SPACE units: trm maps text
      // space through (Tfs×Th × Tm × CTM), so passing the USER-space Tx
      // here would scale it by the font size AGAIN — the v2.5.0 bug that
      // made every word box ~fontSize× too wide (selection rects and
      // highlights landed far beyond the visible text).
      final scaleDen = gs.fontSize * th;
      final boxAdv = scaleDen > 1e-6 ? txUser / scaleDen : txUser;
      // Text rendering matrix: [fs*th 0 0 fs 0 ts] × Tm × CTM.
      final trm = _M(gs.fontSize * th, 0, 0, gs.fontSize, 0, gs.ts)
          .mul(tm)
          .mul(gs.ctm);
      const asc = 0.85, desc = -0.22; // em fractions (generous tap boxes)
      final xs = [
        trm.applyX(0, desc),
        trm.applyX(boxAdv, desc),
        trm.applyX(boxAdv, asc),
        trm.applyX(0, asc),
      ];
      final ys = [
        trm.applyY(0, desc),
        trm.applyY(boxAdv, desc),
        trm.applyY(boxAdv, asc),
        trm.applyY(0, asc),
      ];
      final q = _Quad(
        _min4(xs), _min4(ys), _max4(xs), _max4(ys),
      );
      final isSpace = text.trim().isEmpty && text.isNotEmpty;
      if (text.isNotEmpty) {
        glyphs.add(_Glyph(text, q.x0, q.y0, q.x1, q.y1,
            trm.applyY(0, 0), gs.fontSize, isSpace, glyphs.length));
      }
      tm = _M(1, 0, 0, 1, txUser, 0).mul(tm);
    }
  }

  while (!r.eof) {
    r.skipWs();
    if (r.eof) break;
    final c = r.peek();
    if (c == 0x28 || c == 0x3C || c == 0x5B || c == 0x2F || c == 0x7B) {
      // Delimited object: string / hex string / array / name / dict.
      operands.add(_parseObject(r));
      if (operands.length > 96) operands.removeAt(0);
      continue;
    }
    // Bare token: number or operator keyword.
    final tok = _readToken(r);
    if (tok == null) break;
    final v = double.tryParse(tok);
    if (v != null) {
      operands.add(v == v.roundToDouble() && v.abs() < 9e15 ? v.toInt() : v);
      if (operands.length > 96) operands.removeAt(0);
      continue;
    }
    switch (tok) {
      case 'q':
        stack.add(gs.clone());
        if (stack.length > 32) stack.removeAt(0);
        break;
      case 'Q':
        if (stack.isNotEmpty) gs = stack.removeLast();
        break;
      case 'cm':
        if (operands.length >= 6) {
          final m = _M(
            _opNum(operands, operands.length - 6),
            _opNum(operands, operands.length - 5),
            _opNum(operands, operands.length - 4),
            _opNum(operands, operands.length - 3),
            _opNum(operands, operands.length - 2),
            _opNum(operands, operands.length - 1),
          );
          gs.ctm = m.mul(gs.ctm);
        }
        break;
      case 'BT':
        inText = true;
        tlm = _M.id;
        tm = _M.id;
        break;
      case 'ET':
        inText = false;
        break;
      case 'Tf':
        if (operands.length >= 2) {
          final name = operands[operands.length - 2];
          final size = operands.last;
          gs.font = name is _PdfName ? fonts[name.value] : null;
          gs.fontSize = size is num ? size.toDouble() : 0;
        }
        break;
      case 'Tc':
        if (operands.isNotEmpty && operands.last is num) {
          gs.tc = (operands.last as num).toDouble();
        }
        break;
      case 'Tw':
        if (operands.isNotEmpty && operands.last is num) {
          gs.tw = (operands.last as num).toDouble();
        }
        break;
      case 'Tz':
        if (operands.isNotEmpty && operands.last is num) {
          gs.tz = (operands.last as num).toDouble();
        }
        break;
      case 'TL':
        if (operands.isNotEmpty && operands.last is num) {
          gs.tl = (operands.last as num).toDouble();
        }
        break;
      case 'Ts':
        if (operands.isNotEmpty && operands.last is num) {
          gs.ts = (operands.last as num).toDouble();
        }
        break;
      case 'Td':
        if (operands.length >= 2) {
          tlm = _M(1, 0, 0, 1, _opNum(operands, operands.length - 2),
                  _opNum(operands, operands.length - 1))
              .mul(tlm);
          tm = tlm;
        }
        break;
      case 'TD':
        if (operands.length >= 2) {
          final tx = _opNum(operands, operands.length - 2);
          final ty = _opNum(operands, operands.length - 1);
          gs.tl = -ty;
          tlm = _M(1, 0, 0, 1, tx, ty).mul(tlm);
          tm = tlm;
        }
        break;
      case 'Tm':
        if (operands.length >= 6) {
          tlm = _M(
            _opNum(operands, operands.length - 6),
            _opNum(operands, operands.length - 5),
            _opNum(operands, operands.length - 4),
            _opNum(operands, operands.length - 3),
            _opNum(operands, operands.length - 2),
            _opNum(operands, operands.length - 1),
          );
          tm = tlm;
        }
        break;
      case 'T*':
        tlm = _M(1, 0, 0, 1, 0, -gs.tl).mul(tlm);
        tm = tlm;
        break;
      case 'Tj':
        if (inText && operands.isNotEmpty) showString(operands.last);
        break;
      case "'":
        if (inText && operands.isNotEmpty) {
          tlm = _M(1, 0, 0, 1, 0, -gs.tl).mul(tlm);
          tm = tlm;
          showString(operands.last);
        }
        break;
      case '"':
        if (inText && operands.length >= 3) {
          gs.tw = _opNum(operands, operands.length - 3);
          gs.tc = _opNum(operands, operands.length - 2);
          tlm = _M(1, 0, 0, 1, 0, -gs.tl).mul(tlm);
          tm = tlm;
          showString(operands.last);
        }
        break;
      case 'TJ':
        if (inText && operands.isNotEmpty) {
          final arr = operands.last;
          if (arr is List) {
            final th = gs.tz / 100.0;
            for (final el in arr) {
              if (el is String || el is Uint8List) {
                showString(el);
              } else if (el is num) {
                tm = _M(
                        1, 0, 0, 1,
                        -(el.toDouble() / 1000.0) * gs.fontSize * th,
                        0)
                    .mul(tm);
              }
            }
          }
        }
        break;
      case 'BI':
        _skipInlineImage(r);
        break;
      case 'Do':
        if (operands.isNotEmpty && operands.last is _PdfName) {
          runForm((operands.last as _PdfName).value);
        }
        break;
      default:
        break; // irrelevant operators
    }
    operands.clear();
  }
  return glyphs;
}

double _min4(List<double> v) =>
    v[0] < v[1] && v[0] < v[2] && v[0] < v[3]
        ? v[0]
        : (v[1] < v[2] && v[1] < v[3] ? v[1] : (v[2] < v[3] ? v[2] : v[3]));

double _max4(List<double> v) =>
    v[0] > v[1] && v[0] > v[2] && v[0] > v[3]
        ? v[0]
        : (v[1] > v[2] && v[1] > v[3] ? v[1] : (v[2] > v[3] ? v[2] : v[3]));

double _opNum(List<Object?> ops, int idx) =>
    idx >= 0 && idx < ops.length && ops[idx] is num
        ? (ops[idx] as num).toDouble()
        : 0;

void _skipInlineImage(_Bytes r) {
  // Skip the image dict tokens until ID, then raw bytes until EI.
  while (!r.eof) {
    r.skipWs();
    final save = r.pos;
    final tok = _readToken(r);
    if (tok == null) return;
    if (tok == 'ID') {
      if (r.peek() == 0x0D || r.peek() == 0x20 || r.peek() == 0x0A) r.read();
      final d = r.data;
      var i = r.pos;
      while (i + 3 < d.length) {
        if ((d[i] == 0x20 || d[i] == 0x0A || d[i] == 0x0D || d[i] == 0x09) &&
            d[i + 1] == 0x45 &&
            d[i + 2] == 0x49) {
          r.pos = i + 3;
          return;
        }
        i++;
      }
      r.pos = d.length;
      return;
    } else if (tok == 'EI') {
      return;
    } else {
      r.pos = save;
      if (r.peek() == 0x28 || r.peek() == 0x3C || r.peek() == 0x5B ||
          r.peek() == 0x2F) {
        _parseObject(r);
      } else {
        _readToken(r);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Word / line grouping + rotation mapping
// ---------------------------------------------------------------------------

class _Quad {
  final double x0, y0, x1, y1;
  const _Quad(this.x0, this.y0, this.x1, this.y1);
}

class _Word {
  final String text;
  final double x0, y0, x1, y1; // user space (y-up)
  final bool shaped; // involved presentation forms (shaped rendering)
  _Word(this.text, this.x0, this.y0, this.x1, this.y1, this.shaped);
}

class _LineOut {
  final int start, end; // word index range
  final double baseline;
  final double x0, y0, x1, y1;
  _LineOut(this.start, this.end, this.baseline, this.x0, this.y0, this.x1,
      this.y1);
}

PdfTextPage _buildPage(List<_Glyph> glyphs, double bx, double by, double bw,
    double bh, int rotate) {
  if (glyphs.isEmpty) return PdfTextPage.empty;

  // ---- sort: top lines first (y-up → descending y), then left→right.
  glyphs.sort((g1, g2) {
    final dy = g2.baselineY - g1.baselineY;
    if (dy.abs() > 0.01) return dy > 0 ? 1 : -1;
    return g1.x0.compareTo(g2.x0);
  });

  // ---- line clustering (baseline proximity + column gaps).
  final lineGroups = <List<_Glyph>>[];
  var curBase = 0.0;
  var curSize = 0.0;
  var prevX1 = -1e9;
  for (final g in glyphs) {
    final sz = g.size > 0.1 ? g.size : curSize;
    if (lineGroups.isEmpty) {
      lineGroups.add([g]);
      curBase = g.baselineY;
      curSize = sz;
      prevX1 = g.x1;
      continue;
    }
    final tol = 0.45 * (sz > 0 ? sz : curSize);
    final columnGap =
        prevX1 > -1e8 && (g.x0 - prevX1) > 2.8 * (sz > 0 ? sz : 10);
    final last = lineGroups.last;
    if ((g.baselineY - curBase).abs() > tol || columnGap) {
      lineGroups.add([g]);
      curBase = g.baselineY;
      curSize = sz;
      prevX1 = g.x1;
    } else {
      last.add(g);
      curBase = (curBase * (last.length - 1) + g.baselineY) / last.length;
      if (g.x1 > prevX1) prevX1 = g.x1;
    }
  }

  // ---- words within each line.
  final words = <_Word>[];
  final outLines = <_LineOut>[];
  for (final lineGlyphs in lineGroups) {
    lineGlyphs.sort((a, b) => a.x0.compareTo(b.x0));
    final start = words.length;
    var buf = <_Glyph>[];
    var maxX1 = -1e9;
    double? lineBase;
    double wx0 = 0, wy0 = 0, wx1 = 0, wy1 = 0;
    double lx0 = 1e18, ly0 = 1e18, lx1 = -1e18, ly1 = -1e18;

    void flush() {
      if (buf.isEmpty) return;
      // buf is in VISUAL left→right order. RTL words:
      //  * LOGICAL storage (per-glyph RTL emission — Chrome/Word exports,
      //    first.stream glyph is the RIGHTMOST): the x-sorted join is the
      //    reverse of the stream, so re-joining in stream order restores
      //    the logical text.
      //  * VISUAL storage (one LTR string of shaped glyphs — the classic
      //    arabic-reshaper/bidi generators): presentation forms in LTR
      //    order → normalize with visual ligature order and REVERSE the
      //    codepoints to get the logical word.
      //  * NAIVE unshaped logical storage (plain drawString of the logical
      //    string): base letters, seq increases with x → keep as-is.
      var text = buf.map((g) => g.text).join();
      final rtl = _isRtlText(text);
      final shaped = _hasPresentationForms(text);
      if (rtl && buf.first.seq > buf.last.seq) {
        // Logical per-glyph storage — restore the stream (logical) order.
        text = _mapArabicForms(buf.reversed.map((g) => g.text).join(),
            ligaturesVisual: false);
      } else if (rtl && shaped) {
        // Visual LTR storage of shaped text — reverse to logical.
        text = _reverseCodepoints(
            _mapArabicForms(text, ligaturesVisual: true));
      }
      if (text.trim().isNotEmpty) {
        words.add(_Word(text, wx0, wy0, wx1, wy1, shaped));
      }
      buf = [];
    }

    for (final g in lineGlyphs) {
      lineBase ??= g.baselineY;
      final sz = g.size > 0.1 ? g.size : 10;
      if (g.x0 < lx0) lx0 = g.x0;
      if (g.y0 < ly0) ly0 = g.y0;
      if (g.x1 > lx1) lx1 = g.x1;
      if (g.y1 > ly1) ly1 = g.y1;
      if (g.isSpace) {
        flush();
        maxX1 = g.x1;
        continue;
      }
      if (maxX1 > -1e8) {
        final gap = g.x0 - maxX1;
        if (gap > 0.28 * sz) flush();
      }
      if (buf.isEmpty) {
        wx0 = g.x0;
        wy0 = g.y0;
        wx1 = g.x1;
        wy1 = g.y1;
      } else {
        if (g.x0 < wx0) wx0 = g.x0;
        if (g.y0 < wy0) wy0 = g.y0;
        if (g.x1 > wx1) wx1 = g.x1;
        if (g.y1 > wy1) wy1 = g.y1;
      }
      buf.add(g);
      if (g.x1 > maxX1) maxX1 = g.x1;
    }
    flush();
    if (words.length > start && lx0 < 1e17) {
      outLines.add(_LineOut(start, words.length - 1, lineBase ?? 0, lx0, ly0,
          lx1, ly1));
    }
  }
  if (words.isEmpty) return PdfTextPage.empty;

  // ---- map user space → view space (rotation + y-flip).
  double mapX(double x, double y) {
    final ux = x - bx, uy = y - by;
    switch (rotate) {
      case 90:
        return uy;
      case 180:
        return bw - ux;
      case 270:
        return bh - uy;
      default:
        return ux;
    }
  }

  double mapY(double x, double y) {
    final ux = x - bx, uy = y - by;
    switch (rotate) {
      case 90:
        return ux;
      case 180:
        return uy;
      case 270:
        return bw - ux;
      default:
        return bh - uy;
    }
  }

  final viewW = rotate == 90 || rotate == 270 ? bh : bw;
  final viewH = rotate == 90 || rotate == 270 ? bw : bh;

  final tWords = <PdfTWord>[];
  for (final w in words) {
    final x0 = mapX(w.x0, w.y1); // user y1 = top (y-up)
    final y0 = mapY(w.x0, w.y1);
    final x1 = mapX(w.x1, w.y0);
    final y1 = mapY(w.x1, w.y0);
    final rx0 = x0 < x1 ? x0 : x1;
    final rx1 = x0 < x1 ? x1 : x0;
    final ry0 = y0 < y1 ? y0 : y1;
    final ry1 = y0 < y1 ? y1 : y0;
    tWords.add(PdfTWord(
        w.text, rx0, ry0, rx1 - rx0, ry1 - ry0, _isRtlText(w.text)));
  }

  final tLines = <PdfTLine>[];
  for (final l in outLines) {
    final w0 = words[l.start];
    final w1 = words[l.end];
    final ax = mapX(w0.x0, l.baseline);
    final ay = mapY(w0.x0, l.baseline);
    final bx2 = mapX(w1.x1, l.baseline);
    final by2 = mapY(w1.x1, l.baseline);
    final x0 = mapX(l.x0, l.y1);
    final y0 = mapY(l.x0, l.y1);
    final x1 = mapX(l.x1, l.y0);
    final y1 = mapY(l.x1, l.y0);
    final rx0 = x0 < x1 ? x0 : x1;
    final rx1 = x0 < x1 ? x1 : x0;
    final ry0 = y0 < y1 ? y0 : y1;
    final ry1 = y0 < y1 ? y1 : y0;
    var rtl = false;
    var shaped = 0;
    var rtlWords = 0;
    for (var i = l.start; i <= l.end; i++) {
      if (_isRtlText(words[i].text)) {
        rtl = true;
        rtlWords++;
      }
      if (words[i].shaped) shaped++;
    }
    // Word ORDER on the line: shaped (correctly rendered) RTL lines place
    // the FIRST logical word at the RIGHT — copying must reverse the word
    // order. Naive unshaped storage (mirrored rendering) keeps logical
    // order left-to-right — no reversal.
    final visualOrder = rtl && shaped > rtlWords / 2;
    tLines.add(PdfTLine(l.start, l.end, ax, ay, bx2, by2, rx0, ry0,
        rx1 - rx0, ry1 - ry0, rtl, visualOrder));
  }

  return PdfTextPage(tWords, tLines, viewW, viewH);
}
