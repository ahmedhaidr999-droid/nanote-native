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

  const PdfTLine(this.start, this.end, this.ax, this.ay, this.bx, this.by,
      this.x, this.y, this.w, this.h, this.rtl);
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
      }
      if (fonts.isEmpty) return PdfTextPage.empty;

      final glyphs = _interpretContent(content, fonts);
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

class _FontInfo {
  final bool composite; // Type0
  final int codeBytes; // 1 (simple) or 2 (Identity-H)
  final Map<int, String> toUnicode; // code → unicode string
  final Map<int, int> widths; // code/CID → width (1000/em)
  final int defaultWidth;
  final Map<int, String> diffNames; // Differences: code → glyph name
  final String? baseEncoding;
  final bool symbolicSkip; // Symbol / Dingbats → no text

  _FontInfo({
    required this.composite,
    required this.codeBytes,
    required this.toUnicode,
    required this.widths,
    required this.defaultWidth,
    required this.diffNames,
    required this.baseEncoding,
    required this.symbolicSkip,
  });

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

  int widthOf(int code) => widths[code] ?? defaultWidth;

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

List<_Glyph> _interpretContent(
    Uint8List content, Map<String, _FontInfo> fonts) {
  final glyphs = <_Glyph>[];
  final r = _Bytes(content);
  final stack = <_GState>[];
  var gs = _GState();
  var tlm = _M.id; // text line matrix
  var tm = _M.id; // text matrix
  var inText = false;
  final operands = <Object?>[];

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
      final text = font.textOf(code);
      final w0 = font.widthOf(code);
      final adv = (w0 / 1000.0) * gs.fontSize * th + gs.tc / 1000.0 +
          (code == 0x20 && !font.composite ? gs.tw / 1000.0 : 0);
      // Text rendering matrix: [fs*th 0 0 fs 0 ts] × Tm × CTM.
      final trm = _M(gs.fontSize * th, 0, 0, gs.fontSize, 0, gs.ts)
          .mul(tm)
          .mul(gs.ctm);
      final asc = 0.85, desc = -0.22; // em fractions (generous tap boxes)
      final xs = [
        trm.applyX(0, desc),
        trm.applyX(adv, desc),
        trm.applyX(adv, asc),
        trm.applyX(0, asc),
      ];
      final ys = [
        trm.applyY(0, desc),
        trm.applyY(adv, desc),
        trm.applyY(adv, asc),
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
      tm = _M(1, 0, 0, 1, adv, 0).mul(tm);
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
  _Word(this.text, this.x0, this.y0, this.x1, this.y1);
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
      // buf is in VISUAL left→right order. For RTL words:
      //  * VISUAL storage (proper generators): the leftmost glyph is the
      //    LAST logical character (earliest seq sits rightmost) → flip.
      //  * NAIVE left-to-right storage (unshaped generators): the leftmost
      //    glyph is already the FIRST logical character → keep.
      var text = buf.map((g) => g.text).join();
      if (_isRtlText(text) && buf.first.seq > buf.last.seq) {
        text = buf.reversed.map((g) => g.text).join();
      }
      if (text.trim().isNotEmpty) {
        words.add(_Word(text, wx0, wy0, wx1, wy1));
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
    for (var i = l.start; i <= l.end && !rtl; i++) {
      rtl = _isRtlText(words[i].text);
    }
    tLines.add(PdfTLine(l.start, l.end, ax, ay, bx2, by2, rx0, ry0,
        rx1 - rx0, ry1 - ry0, rtl));
  }

  return PdfTextPage(tWords, tLines, viewW, viewH);
}
