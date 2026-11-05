import 'package:flutter/material.dart';

import '../../models/paper.dart';
import '../../theme/nanote_theme.dart';

/// A notebook cover (always 3:4 portrait): gradient / flat / pattern, with
/// the cover's own text color. Used by the library grid, the notebook card
/// and the create-notebook preview.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.cover,
    this.width,
    this.height,
    this.borderRadius = NANOTE_RADIUS_LG,
  });

  final CoverDef cover;

  /// Width; height defaults to width × 4/3 (3:4 portrait).
  final double? width;

  final double? height;

  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: CustomPaint(
        size: width != null
            ? Size(width!, width! * 4 / 3)
            : (height != null ? Size(height! * 3 / 4, height!) : Size.zero),
        foregroundPainter: cover.hasPattern
            ? _CoverPatternPainter(cover.style, borderRadius)
            : null,
        child: Container(
          decoration: BoxDecoration(
            gradient: cover.buildGradient(),
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: nanoteColors(context).inkShadow1,
          ),
        ),
      ),
    );
  }
}

/// Dots (18px spacing) / horizontal translucent lines (every 12px) painted
/// in white over the cover gradient — covers `dots` and `lines`.
class _CoverPatternPainter extends CustomPainter {
  const _CoverPatternPainter(this.style, this.radius);

  final CoverStyle style;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.22);
    if (style == CoverStyle.dots) {
      const spacing = 18.0;
      // Offset so the pattern is centered.
      final cols = (size.width / spacing).floor();
      final rows = (size.height / spacing).floor();
      final ox = (size.width - (cols - 1) * spacing) / 2;
      final oy = (size.height - (rows - 1) * spacing) / 2;
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          canvas.drawCircle(
            Offset(ox + c * spacing, oy + r * spacing),
            1.3,
            paint,
          );
        }
      }
    } else if (style == CoverStyle.lines) {
      const spacing = 12.0;
      final rows = (size.height / spacing).floor();
      final oy = (size.height - (rows - 1) * spacing) / 2;
      for (var r = 0; r < rows; r++) {
        canvas.drawLine(
          Offset(10, oy + r * spacing),
          Offset(size.width - 10, oy + r * spacing),
          paint
            ..strokeWidth = 1
            ..strokeCap = StrokeCap.round,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CoverPatternPainter oldDelegate) =>
      oldDelegate.style != style;
}
