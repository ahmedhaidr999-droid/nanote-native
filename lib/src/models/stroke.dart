import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';


/// The pen kinds that commit ink to the document.
enum StrokeKind { fountain, ballpoint, brush, fineliner, highlighter }

extension StrokeKindX on StrokeKind {
  static StrokeKind fromId(int id) =>
      StrokeKind.values[id.clamp(0, StrokeKind.values.length - 1)];

  String get key => 'tool.${name}';
}

/// Full rendering style of an ink stroke.
///
/// Only [size], [thinning], [smoothing], [streamline], [simulatePressure] and
/// [isComplete] map to perfect-freehand options; [taperStart]/[taperEnd] are
/// expressed as a 0..1 fraction of the stroke length; [opacity] is used by the
/// highlighter compositing (never self-darkens — see InkPainter).
class StrokeStyle {
  int color; // 0xAARRGGBB
  double size;
  StrokeKind kind;

  double thinning;
  double smoothing;
  double streamline;
  bool simulatePressure;

  double taperStart; // 0..1 fraction of stroke length
  double taperEnd; // 0..1 fraction of stroke length
  double opacity; // 0..1 (highlighter)

  StrokeStyle({
    required this.color,
    required this.size,
    required this.kind,
    this.thinning = 0.5,
    this.smoothing = 0.5,
    this.streamline = 0.5,
    this.simulatePressure = true,
    this.taperStart = 0,
    this.taperEnd = 0,
    this.opacity = 1,
  });

  /// v1.9.1 pen defaults.
  factory StrokeStyle.forKind(StrokeKind kind, int color) {
    switch (kind) {
      case StrokeKind.fountain:
        return StrokeStyle(
          color: color,
          size: 5,
          kind: kind,
          thinning: 0.6,
          smoothing: 0.5,
          streamline: 0.5,
          simulatePressure: true,
          taperStart: 0.55,
          taperEnd: 0.25,
        );
      case StrokeKind.ballpoint:
        return StrokeStyle(
          color: color,
          size: 2.4,
          kind: kind,
          thinning: 0.12,
          smoothing: 0.5,
          streamline: 0.5,
          simulatePressure: true,
        );
      case StrokeKind.brush:
        return StrokeStyle(
          color: color,
          size: 9,
          kind: kind,
          thinning: 0.85,
          smoothing: 0.5,
          streamline: 0.5,
          simulatePressure: true,
          taperStart: 1,
          taperEnd: 1,
        );
      case StrokeKind.fineliner:
        return StrokeStyle(
          color: color,
          size: 1.8,
          kind: kind,
          thinning: 0,
          smoothing: 0.5,
          streamline: 0.5,
          simulatePressure: false,
        );
      case StrokeKind.highlighter:
        return StrokeStyle(
          color: color,
          size: 18,
          kind: kind,
          thinning: 0,
          smoothing: 0.05,
          streamline: 0.28,
          simulatePressure: false,
          opacity: 0.4,
        );
    }
  }

  Color get flutterColor => Color(color);

  StrokeStyle copyWith({
    int? color,
    double? size,
    StrokeKind? kind,
    double? thinning,
    double? smoothing,
    double? streamline,
    bool? simulatePressure,
    double? taperStart,
    double? taperEnd,
    double? opacity,
  }) =>
      StrokeStyle(
        color: color ?? this.color,
        size: size ?? this.size,
        kind: kind ?? this.kind,
        thinning: thinning ?? this.thinning,
        smoothing: smoothing ?? this.smoothing,
        streamline: streamline ?? this.streamline,
        simulatePressure: simulatePressure ?? this.simulatePressure,
        taperStart: taperStart ?? this.taperStart,
        taperEnd: taperEnd ?? this.taperEnd,
        opacity: opacity ?? this.opacity,
      );

  Map<String, dynamic> toJson() => {
        'c': color,
        's': size,
        'k': kind.index,
        't': thinning,
        'sm': smoothing,
        'sl': streamline,
        'sp': simulatePressure,
        'ts': taperStart,
        'te': taperEnd,
        'op': opacity,
      };

  factory StrokeStyle.fromJson(Map<String, dynamic> json) => StrokeStyle(
        color: (json['c'] as num?)?.toInt() ?? 0xFF16233A,
        size: (json['s'] as num?)?.toDouble() ?? 2.4,
        kind: StrokeKindX.fromId((json['k'] as num?)?.toInt() ?? 1),
        thinning: (json['t'] as num?)?.toDouble() ?? 0.5,
        smoothing: (json['sm'] as num?)?.toDouble() ?? 0.5,
        streamline: (json['sl'] as num?)?.toDouble() ?? 0.5,
        simulatePressure: json['sp'] as bool? ?? true,
        taperStart: (json['ts'] as num?)?.toDouble() ?? 0,
        taperEnd: (json['te'] as num?)?.toDouble() ?? 0,
        opacity: (json['op'] as num?)?.toDouble() ?? 1,
      );
}

/// Global pressure curve (gamma) applied to stylus pressure before outline
/// generation. 0.4 = firm, 1.0 = linear, 2.5 = soft. Managed by
/// [../controllers/settings_controller.dart].
class PressureCurve {
  static double gamma = 1.0;

  static double apply(double p) {
    if (p <= 0) return 0;
    if (p >= 1) return 1;
    return math.pow(p, gamma).toDouble();
  }
}

/// A committed (or in-progress) ink stroke.
///
/// Points live in PAGE-POINT space (page coordinates, y down). The stroke is
/// never stored in screen space — the viewport matrix converts on the fly, so
/// ink can never drift under zoom/pan.
class Stroke {
  int id;
  int z; // global z-order within the page (shared with elements)

  StrokeStyle style;

  /// Flat point buffer: x, y, pressure per point (stride 3).
  final List<double> pts;

  /// Audio sync: ms from recording start when the stroke began / ended.
  int? tStart;
  int? tEnd;

  /// Selection group (lasso auto-expands to all members of a group).
  int? groupId;

  Stroke({
    required this.id,
    required this.style,
    required this.pts,
    this.z = 0,
    this.tStart,
    this.tEnd,
    this.groupId,
  });

  int get pointCount => pts.length ~/ 3;

  bool get isEmpty => pointCount == 0;

  Offset point(int i) => Offset(pts[i * 3], pts[i * 3 + 1]);

  double pressure(int i) => pts[i * 3 + 2];

  void append(Offset p, double pressure) {
    pts..add(p.dx)..add(p.dy)..add(pressure.clamp(0.0, 1.0));
    _outline = null;
    _bbox = null;
  }

  // ---- transient caches -------------------------------------------------

  List<Offset>? _outline;
  Rect? _bbox;

  void invalidateCaches() {
    _outline = null;
    _bbox = null;
  }

  Rect get bbox {
    if (_bbox != null) return _bbox!;
    if (isEmpty) return Rect.zero;
    var minX = pts[0];
    var maxX = pts[0];
    var minY = pts[1];
    var maxY = pts[1];
    for (var i = 0; i < pts.length; i += 3) {
      final x = pts[i];
      final y = pts[i + 1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
    final pad = math.max(style.size, 2.0);
    _bbox = Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
    return _bbox!;
  }

  double get pathLength {
    var len = 0.0;
    for (var i = 1; i < pointCount; i++) {
      len += (point(i) - point(i - 1)).distance;
    }
    return len;
  }

  /// Perfect-freehand outline polygon in page space.
  List<Offset> get outline {
    if (_outline != null) return _outline!;
    if (isEmpty) return const [];
    final total = pathLength;

    StrokeEndOptions start;
    if (style.taperStart > 0) {
      start = StrokeEndOptions.start(
        cap: false,
        customTaper: style.taperStart >= 0.999 ? -1.0 : style.taperStart * total,
      );
    } else {
      final square = style.kind == StrokeKind.highlighter;
      start = StrokeEndOptions.start(cap: !square);
    }

    StrokeEndOptions end;
    if (style.taperEnd > 0) {
      end = StrokeEndOptions.end(
        cap: false,
        customTaper: style.taperEnd >= 0.999 ? -1.0 : style.taperEnd * total,
      );
    } else {
      final square = style.kind == StrokeKind.highlighter;
      end = StrokeEndOptions.end(cap: !square);
    }

    final inputs = <PointVector>[];
    for (var i = 0; i < pointCount; i++) {
      final p = style.simulatePressure ? 0.5 : pressure(i);
      inputs.add(PointVector(pts[i * 3], pts[i * 3 + 1], PressureCurve.apply(p)));
    }

    _outline = getStroke(
      inputs,
      options: StrokeOptions(
        size: style.size,
        thinning: style.thinning,
        smoothing: style.smoothing,
        streamline: style.streamline,
        simulatePressure: style.simulatePressure,
        isComplete: true,
        start: start,
        end: end,
      ),
    );
    return _outline!;
  }

  /// Path built from the outline polygon.
  Path buildPath() {
    final path = Path();
    final o = outline;
    if (o.isEmpty) return path;
    path.moveTo(o[0].dx, o[0].dy);
    for (var i = 1; i < o.length; i++) {
      path.lineTo(o[i].dx, o[i].dy);
    }
    path.close();
    return path;
  }

  /// Distance from [p] to the nearest segment of the stroke.
  double distanceTo(Offset p) {
    if (isEmpty) return double.infinity;
    var best = double.infinity;
    for (var i = 0; i < pointCount; i++) {
      final a = point(i);
      if (i == 0) {
        best = (p - a).distance;
        continue;
      }
      final b = point(i - 1);
      best = math.min(best, _distToSegment(p, b, a));
    }
    return best;
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    var t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    final proj = a + ab * t;
    return (p - proj).distance;
  }

  /// Maps every point through [f] (used by selection transforms).
  Stroke transformed(Offset Function(Offset p) f) {
    final out = Stroke(
      id: id,
      z: z,
      style: style,
      tStart: tStart,
      tEnd: tEnd,
      groupId: groupId,
      pts: List<double>.of(pts),
    );
    for (var i = 0; i < out.pointCount; i++) {
      final p = f(out.point(i));
      out.pts[i * 3] = p.dx;
      out.pts[i * 3 + 1] = p.dy;
    }
    return out;
  }

  Stroke deepCopy() => Stroke(
        id: id,
        z: z,
        style: style.copyWith(),
        tStart: tStart,
        tEnd: tEnd,
        groupId: groupId,
        pts: List<double>.of(pts),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'z': z,
        'st': style.toJson(),
        'p': pts,
        if (tStart != null) 't0': tStart,
        if (tEnd != null) 't1': tEnd,
        if (groupId != null) 'g': groupId,
      };

  factory Stroke.fromJson(Map<String, dynamic> json) => Stroke(
        id: (json['id'] as num?)?.toInt() ?? 0,
        z: (json['z'] as num?)?.toInt() ?? 0,
        style: StrokeStyle.fromJson((json['st'] as Map?)?.cast<String, dynamic>() ?? {}),
        pts: ((json['p'] as List?) ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(growable: false),
        tStart: (json['t0'] as num?)?.toInt(),
        tEnd: (json['t1'] as num?)?.toInt(),
        groupId: (json['g'] as num?)?.toInt(),
      );
}

/// Monotonic stroke-id generator (stable within a session; persisted inside
/// the stroke JSON so selection / undo references survive reloads).
class StrokeIdGen {
  static int _next = 1;

  static int next() => _next++;

  /// Ensure future ids never collide with ids loaded from storage.
  static void seedAbove(int id) {
    if (id >= _next) _next = id + 1;
  }
}
