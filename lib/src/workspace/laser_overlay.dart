import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/laser_controller.dart';
import '../controllers/stroke_engine.dart';

/// Per-page laser pointer overlay (rendered inside the page transform, in
/// page space). Owns a ~30fps timer that drives the controller's fading while
/// mounted; only THIS page's strokes are painted.
class LaserOverlay extends StatefulWidget {
  const LaserOverlay({super.key, required this.laser, required this.pageId});

  final LaserController laser;
  final int pageId;

  @override
  State<LaserOverlay> createState() => _LaserOverlayState();
}

class _LaserOverlayState extends State<LaserOverlay> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => widget.laser.tick(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _LaserPainter(widget.laser, widget.pageId),
    );
  }
}

class _LaserPainter extends CustomPainter {
  _LaserPainter(this.laser, this.pageId) : super(repaint: laser);

  final LaserController laser;
  final int pageId;

  /// Normal (comet) mode: per-point fade over 600ms.
  static const int _cometFadeMs = 600;

  /// Timed mode: fade-out duration after the stay window.
  static const int _timedFadeMs = 400;

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final base = Color(laser.color);

    // §2 laser points are page-local (anchor-relative) — translate onto
    // the grown paper widget.
    final pad = StrokeEngine.I.padOffsetOf(pageId);
    canvas.translate(pad.dx, pad.dy);

    for (final s in laser.strokes) {
      if (s.pageId != pageId) continue;
      final pts = s.points;
      if (pts.length < 2) continue;

      if (laser.mode == LaserMode.timed) {
        // Whole stroke stays at full alpha until `seconds` elapsed after
        // release, then fades over 400ms.
        var alpha = 1.0;
        if (s.released && s.pointTimesMs.isNotEmpty) {
          final sinceRelease = now - s.pointTimesMs.last;
          final stayMs = laser.seconds * 1000;
          if (sinceRelease > stayMs) {
            alpha = 1 - (sinceRelease - stayMs) / _timedFadeMs;
          }
        }
        if (alpha <= 0) continue;
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (var i = 1; i < pts.length; i++) {
          path.lineTo(pts[i].dx, pts[i].dy);
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = base.withValues(alpha: alpha.clamp(0.0, 1.0))
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke,
        );
      } else {
        // Comet trail: each segment's alpha comes from the age of its newer
        // point (1 - age/600, clamped).
        for (var i = 1; i < pts.length; i++) {
          final t = i < s.pointTimesMs.length ? s.pointTimesMs[i] : s.createdAtMs;
          final age = (now - t).toDouble();
          final alpha = (1 - age / _cometFadeMs).clamp(0.0, 1.0);
          if (alpha <= 0) continue;
          canvas.drawLine(
            pts[i - 1],
            pts[i],
            Paint()
              ..color = base.withValues(alpha: alpha)
              ..strokeWidth = 4
              ..strokeCap = StrokeCap.round
              ..style = PaintingStyle.stroke,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LaserPainter oldDelegate) => true;
}
