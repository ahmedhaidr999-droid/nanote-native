import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'paper.dart';

/// Base of all page elements (text boxes, shapes, images/stickers).
sealed class PageElement {
  String get id;

  int get z;

  set z(int value);

  /// Bounding box in page space (ignores rotation for hit-testing simplicity;
  /// the painter applies rotation around the box center).
  Rect bbox();

  PageElement deepCopy();

  Map<String, dynamic> toJson();
}

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

class TextEl extends PageElement {
  @override
  final String id;
  @override
  int z;

  String text;
  double x;
  double y;
  double w; // wrap width in page units

  double size;
  TextFontId font;
  int color;
  bool bold;
  bool italic;
  bool underline;
  int align; // 0 start, 1 center, 2 end

  TextEl({
    required this.id,
    required this.z,
    required this.text,
    required this.x,
    required this.y,
    required this.w,
    required this.size,
    required this.font,
    required this.color,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.align = 0,
  });

  TextAlign get textAlign => align == 1
      ? TextAlign.center
      : align == 2
          ? TextAlign.end
          : TextAlign.start;

  @override
  Rect bbox() => Rect.fromLTWH(x, y, w, _estimatedHeight());

  double _estimatedHeight() {
    if (w <= 0) return size * 1.6;
    final charW = size * 0.55;
    final perLine = math.max(1, (w / charW).floor());
    final lines = math.max(1, (text.characters.length / perLine).ceil());
    return lines * size * 1.45;
  }

  @override
  TextEl deepCopy() => TextEl(
        id: id,
        z: z,
        text: text,
        x: x,
        y: y,
        w: w,
        size: size,
        font: font,
        color: color,
        bold: bold,
        italic: italic,
        underline: underline,
        align: align,
      );

  @override
  Map<String, dynamic> toJson() => {
        't': 'text',
        'id': id,
        'z': z,
        'tx': text,
        'x': x,
        'y': y,
        'w': w,
        'sz': size,
        'f': font.index,
        'c': color,
        'b': bold,
        'i': italic,
        'u': underline,
        'al': align,
      };

  factory TextEl.fromJson(Map<String, dynamic> j) => TextEl(
        id: j['id'] as String,
        z: (j['z'] as num?)?.toInt() ?? 0,
        text: (j['tx'] as String?) ?? '',
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        w: (j['w'] as num?)?.toDouble() ?? 220,
        size: (j['sz'] as num?)?.toDouble() ?? 18,
        font: TextFontIdX.fromId((j['f'] as num?)?.toInt() ?? 0),
        color: (j['c'] as num?)?.toInt() ?? 0xFF16233A,
        bold: j['b'] as bool? ?? false,
        italic: j['i'] as bool? ?? false,
        underline: j['u'] as bool? ?? false,
        align: (j['al'] as num?)?.toInt() ?? 0,
      );
}

// ---------------------------------------------------------------------------
// Shape
// ---------------------------------------------------------------------------

class ShapeEl extends PageElement {
  @override
  final String id;
  @override
  int z;

  ShapeType type;
  int strokeColor;
  int? fillColor;
  double fillOpacity; // 0..1
  double strokeWidth;

  /// Geometry: either a bbox (rect-like shapes) or explicit points
  /// (line / arrow / doubleArrow / arc / freeform), all in page space.
  double x, y, w, h;
  double rotation; // radians
  int sides; // polygon 3..12

  List<Offset>? pts;

  ShapeEl({
    required this.id,
    required this.z,
    required this.type,
    required this.strokeColor,
    required this.strokeWidth,
    this.fillColor,
    this.fillOpacity = 0.25,
    this.x = 0,
    this.y = 0,
    this.w = 0,
    this.h = 0,
    this.rotation = 0,
    this.sides = 5,
    this.pts,
  });

  @override
  Rect bbox() {
    if (type.isPolylineLike && pts != null && pts!.isNotEmpty) {
      var minX = pts!.first.dx, maxX = pts!.first.dx;
      var minY = pts!.first.dy, maxY = pts!.first.dy;
      for (final p in pts!) {
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
      }
      final pad = strokeWidth + 6;
      return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
    }
    return Rect.fromLTWH(x, y, w, h);
  }

  Offset get center => bbox().center;

  @override
  ShapeEl deepCopy() => ShapeEl(
        id: id,
        z: z,
        type: type,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        fillColor: fillColor,
        fillOpacity: fillOpacity,
        x: x,
        y: y,
        w: w,
        h: h,
        rotation: rotation,
        sides: sides,
        pts: pts == null ? null : List<Offset>.of(pts!),
      );

  @override
  Map<String, dynamic> toJson() => {
        't': 'shape',
        'id': id,
        'z': z,
        'ty': type.index,
        'sc': strokeColor,
        'sw': strokeWidth,
        if (fillColor != null) 'fc': fillColor,
        'fo': fillOpacity,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'r': rotation,
        'n': sides,
        if (pts != null) 'p': [for (final p in pts!) ...[p.dx, p.dy]],
      };

  factory ShapeEl.fromJson(Map<String, dynamic> j) {
    final flat = (j['p'] as List?)?.map((e) => (e as num).toDouble()).toList();
    return ShapeEl(
      id: j['id'] as String,
      z: (j['z'] as num?)?.toInt() ?? 0,
      type: ShapeTypeX.fromId((j['ty'] as num?)?.toInt() ?? 0),
      strokeColor: (j['sc'] as num?)?.toInt() ?? 0xFF16233A,
      strokeWidth: (j['sw'] as num?)?.toDouble() ?? 2,
      fillColor: (j['fc'] as num?)?.toInt(),
      fillOpacity: (j['fo'] as num?)?.toDouble() ?? 0.25,
      x: (j['x'] as num?)?.toDouble() ?? 0,
      y: (j['y'] as num?)?.toDouble() ?? 0,
      w: (j['w'] as num?)?.toDouble() ?? 0,
      h: (j['h'] as num?)?.toDouble() ?? 0,
      rotation: (j['r'] as num?)?.toDouble() ?? 0,
      sides: (j['n'] as num?)?.toInt() ?? 5,
      pts: flat == null
          ? null
          : [
              for (var i = 0; i + 1 < flat.length; i += 2) Offset(flat[i], flat[i + 1]),
            ],
    );
  }
}

// ---------------------------------------------------------------------------
// Image / sticker
// ---------------------------------------------------------------------------

class ImageEl extends PageElement {
  @override
  final String id;
  @override
  int z;

  /// Relative path (under the app files dir) for user images; null for
  /// built-in stickers.
  String? src;

  /// Built-in sticker id (heart, star, smiley, check, cross, arrow, bulb,
  /// flag) — see [../workspace/sticker_art.dart].
  String? builtinId;

  double x, y, w, h;
  double rotation; // radians
  bool flipH, flipV;

  ImageEl({
    required this.id,
    required this.z,
    this.src,
    this.builtinId,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.rotation = 0,
    this.flipH = false,
    this.flipV = false,
  });

  @override
  Rect bbox() => Rect.fromLTWH(x, y, w, h);

  Offset get center => bbox().center;

  @override
  ImageEl deepCopy() => ImageEl(
        id: id,
        z: z,
        src: src,
        builtinId: builtinId,
        x: x,
        y: y,
        w: w,
        h: h,
        rotation: rotation,
        flipH: flipH,
        flipV: flipV,
      );

  @override
  Map<String, dynamic> toJson() => {
        't': 'img',
        'id': id,
        'z': z,
        if (src != null) 's': src,
        if (builtinId != null) 'b': builtinId,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'r': rotation,
        'fh': flipH,
        'fv': flipV,
      };

  factory ImageEl.fromJson(Map<String, dynamic> j) => ImageEl(
        id: j['id'] as String,
        z: (j['z'] as num?)?.toInt() ?? 0,
        src: j['s'] as String?,
        builtinId: j['b'] as String?,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        w: (j['w'] as num).toDouble(),
        h: (j['h'] as num).toDouble(),
        rotation: (j['r'] as num?)?.toDouble() ?? 0,
        flipH: j['fh'] as bool? ?? false,
        flipV: j['fv'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

PageElement? elementFromJson(Map<String, dynamic> j) {
  switch (j['t']) {
    case 'text':
      return TextEl.fromJson(j);
    case 'shape':
      return ShapeEl.fromJson(j);
    case 'img':
      return ImageEl.fromJson(j);
  }
  return null;
}

Map<String, dynamic> elementToJson(PageElement el) => el.toJson();

/// Translates an element in page space by (dx, dy).
void translateElement(PageElement el, double dx, double dy) {
  if (el is TextEl) {
    el.x += dx;
    el.y += dy;
  } else if (el is ShapeEl) {
    el.x += dx;
    el.y += dy;
    if (el.pts != null) {
      el.pts = [for (final p in el.pts!) p.translate(dx, dy)];
    }
  } else if (el is ImageEl) {
    el.x += dx;
    el.y += dy;
  }
}

/// Rotates a page point [p] around [center] by [r] radians.
Offset rotatePoint(Offset p, Offset center, double r) {
  final s = math.sin(r);
  final c = math.cos(r);
  final dx = p.dx - center.dx;
  final dy = p.dy - center.dy;
  return Offset(dx * c - dy * s + center.dx, dx * s + dy * c + center.dy);
}

/// Monotonic element-id generator.
class ElementIdGen {
  static int _next = 1;

  static String next() => 'e${_next++}${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

  /// Ensure future ids never collide with loaded ones (loaded ids embed a
  /// timestamp prefix so collisions are practically impossible; kept simple).
  static void seedAbove(List<String> existingIds) {
    // no-op: ids contain time component
  }
}
