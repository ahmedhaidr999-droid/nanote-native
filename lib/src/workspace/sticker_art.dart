import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Vector art of the built-in stickers, scaled into a size box.
///
/// Convention used by the painters (see ElementsPainter._paintImage):
/// the FIRST path is the sticker "body" (painted with the primary blue
/// 0xFF1E6FF2) and every following path is an "accent" (painted white).
/// A missing/unknown id yields a rounded-square placeholder — never throws.
class StickerArt {
  const StickerArt();

  static const List<String> builtinIds = [
    'heart',
    'star',
    'smiley',
    'check',
    'cross',
    'arrow',
    'bulb',
    'flag',
  ];

  /// 1–3 filled paths drawn nicely inside [size].
  List<Path> paths(String id, Size size) {
    final w = math.max(1.0, size.width);
    final h = math.max(1.0, size.height);
    switch (id) {
      case 'heart':
        return [_heart(w, h)];
      case 'star':
        return [_star(w, h)];
      case 'smiley':
        return _smiley(w, h);
      case 'check':
        return [_check(w, h)];
      case 'cross':
        return [_cross(w, h)];
      case 'arrow':
        return [_arrow(w, h)];
      case 'bulb':
        return _bulb(w, h);
      case 'flag':
        return _flag(w, h);
      default:
        return [_placeholder(w, h)];
    }
  }

  // ------------------------------------------------------------------ heart

  Path _heart(double w, double h) {
    final cx = w / 2;
    final p = Path();
    p.moveTo(cx, h * 0.88);
    p.cubicTo(w * 0.02, h * 0.60, w * 0.08, h * 0.16, cx, h * 0.30);
    p.cubicTo(w * 0.92, h * 0.16, w * 0.98, h * 0.60, cx, h * 0.88);
    p.close();
    return p;
  }

  // ------------------------------------------------------------------- star

  Path _star(double w, double h) {
    final cx = w / 2;
    final cy = h / 2;
    final rx = w * 0.48;
    final ry = h * 0.48;
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final frac = i.isEven ? 1.0 : 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final x = cx + math.cos(a) * rx * frac;
      final y = cy + math.sin(a) * ry * frac;
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    p.close();
    return p;
  }

  // ----------------------------------------------------------------- smiley

  /// Face circle (body) + both eyes (accent) + smile crescent (accent).
  List<Path> _smiley(double w, double h) {
    final face = Path()
      ..addOval(Rect.fromLTWH(w * 0.04, h * 0.04, w * 0.92, h * 0.92));
    final eyes = Path()
      ..addOval(Rect.fromCenter(
        center: Offset(w * 0.36, h * 0.38),
        width: w * 0.12,
        height: h * 0.12,
      ))
      ..addOval(Rect.fromCenter(
        center: Offset(w * 0.64, h * 0.38),
        width: w * 0.12,
        height: h * 0.12,
      ));
    final mouth = Path()
      ..moveTo(w * 0.28, h * 0.58)
      ..quadraticBezierTo(w * 0.50, h * 0.86, w * 0.72, h * 0.58)
      ..quadraticBezierTo(w * 0.50, h * 0.70, w * 0.28, h * 0.58)
      ..close();
    return [face, eyes, mouth];
  }

  // ------------------------------------------------------------------ check

  Path _check(double w, double h) {
    final p = Path();
    p.moveTo(w * 0.14, h * 0.52);
    p.lineTo(w * 0.38, h * 0.76);
    p.lineTo(w * 0.88, h * 0.26);
    p.lineTo(w * 0.74, h * 0.12);
    p.lineTo(w * 0.38, h * 0.50);
    p.lineTo(w * 0.28, h * 0.38);
    p.close();
    return p;
  }

  // ------------------------------------------------------------------ cross

  Path _cross(double w, double h) {
    final cx = w / 2;
    final cy = h / 2;
    final arm = math.min(w, h) * 0.42;
    final thick = math.min(w, h) * 0.13;
    final p = Path();
    for (final rot in <double>[math.pi / 4, -math.pi / 4]) {
      final dx = math.cos(rot);
      final dy = math.sin(rot);
      final px = -dy;
      final py = dx; // perpendicular
      p.moveTo(cx - dx * arm + px * thick, cy - dy * arm + py * thick);
      p.lineTo(cx + dx * arm + px * thick, cy + dy * arm + py * thick);
      p.lineTo(cx + dx * arm - px * thick, cy + dy * arm - py * thick);
      p.lineTo(cx - dx * arm - px * thick, cy - dy * arm - py * thick);
      p.close();
    }
    return p;
  }

  // ------------------------------------------------------------------ arrow

  Path _arrow(double w, double h) {
    final p = Path();
    p.moveTo(w * 0.04, h * 0.36);
    p.lineTo(w * 0.60, h * 0.36);
    p.lineTo(w * 0.60, h * 0.14);
    p.lineTo(w * 0.96, h * 0.50);
    p.lineTo(w * 0.60, h * 0.86);
    p.lineTo(w * 0.60, h * 0.64);
    p.lineTo(w * 0.04, h * 0.64);
    p.close();
    return p;
  }

  // ------------------------------------------------------------------- bulb

  /// Bulb glass (body) + screw base (accent).
  List<Path> _bulb(double w, double h) {
    final r = math.min(w, h * 0.72) * 0.42;
    final glass = Path()
      ..addOval(Rect.fromCircle(center: Offset(w / 2, h * 0.36), radius: r));
    final base = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(w / 2 - r * 0.42, h * 0.62, r * 0.84, h * 0.24),
        Radius.circular(r * 0.12),
      ));
    return [glass, base];
  }

  // ------------------------------------------------------------------- flag

  /// Pole (body) + triangular cloth (accent).
  List<Path> _flag(double w, double h) {
    final pole = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.20, h * 0.04, w * 0.09, h * 0.92),
        Radius.circular(w * 0.045),
      ));
    final cloth = Path()
      ..moveTo(w * 0.32, h * 0.10)
      ..lineTo(w * 0.86, h * 0.30)
      ..lineTo(w * 0.32, h * 0.50)
      ..close();
    return [pole, cloth];
  }

  // ------------------------------------------------------------- placeholder

  Path _placeholder(double w, double h) {
    final r = math.min(12.0, math.min(w, h) / 4);
    return Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, w - 2, h - 2),
        Radius.circular(r),
      ));
  }
}
