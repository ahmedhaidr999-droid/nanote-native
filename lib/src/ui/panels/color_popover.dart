import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../controllers/tool_controller.dart';
import '../../i18n/strings.dart';
import '../../models/paper.dart';
import '../../models/stroke.dart';
import '../../models/tool.dart';
import '../../theme/nanote_theme.dart';

/// Color picker for the CURRENT tool: palette (ink / highlighter / laser by
/// scope), per-scope FAVORITE slots (tap to apply, star to save the picked
/// color), the spectrum color wheel with a brightness slider, and recents.
Future<void> showColorPopover(BuildContext context, ToolController tools) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _ColorSheet(tools: tools),
  );
}

/// Palette for a color scope.
List<Color> paletteFor(ColorScope scope) => switch (scope) {
      ColorScope.highlighter => HIGHLIGHTER_PALETTE,
      ColorScope.laser => const [
          Color(0xFFE5484D),
          Color(0xFFF59E0B),
          Color(0xFF10B981),
          Color(0xFF0EA5E9),
          Color(0xFF8B5CF6),
        ],
      ColorScope.pen => INK_PALETTE,
    };

class _ColorSheet extends StatefulWidget {
  const _ColorSheet({required this.tools});

  final ToolController tools;

  @override
  State<_ColorSheet> createState() => _ColorSheetState();
}

class _ColorSheetState extends State<_ColorSheet> {
  late Color _selected;
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _selected = Color(_currentToolColor());
    _hsv = HSVColor.fromColor(_selected);
  }

  int _currentToolColor() {
    final t = widget.tools;
    switch (t.tool) {
      case Tool.pen:
        return t.pen(t.penKind.strokeKind).color;
      case Tool.highlighter:
        return t.pen(StrokeKind.highlighter).color;
      case Tool.laser:
        return t.laser.color;
      case Tool.text:
        return t.textColor;
      case Tool.shape:
        return t.shapeStrokeColor;
      default:
        return t.pen(t.penKind.strokeKind).color;
    }
  }

  void _apply(Color color) {
    final t = widget.tools;
    final argb = color.toARGB32();
    switch (t.tool) {
      case Tool.laser:
        t.laser.color = argb;
        t.laser.tick();
      case Tool.text:
        t.setTextColor(argb);
      case Tool.shape:
        t.setShapeStrokeColor(argb);
      case Tool.highlighter:
        t.setPenColor(argb);
      default:
        t.setPenColor(argb);
    }
    t.addRecentColor(argb);
    Navigator.of(context).pop();
  }

  void _toggleFavorite() {
    widget.tools.toggleFavoriteColor(_selected.toARGB32());
  }

  void _setWheel(HSVColor hsv) {
    setState(() {
      _hsv = hsv;
      _selected = hsv.toColor();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tools = widget.tools;
    final cs = nanoteColors(context);
    final scope = tools.colorScope;
    final palette = paletteFor(scope);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: AnimatedBuilder(
          animation: tools,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.t('color'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in palette)
                    _swatch(
                      context,
                      color: c,
                      selected: c.toARGB32() == _selected.toARGB32(),
                      onTap: () => _apply(c),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _favoritesRow(context, cs),
              const SizedBox(height: 16),
              Text(S.t('customColor'),
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _wheelSection(context, cs),
              if (tools.recentColors.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(S.t('recentColors'),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final v in tools.recentColors)
                      _swatch(
                        context,
                        color: Color(v),
                        selected: v == _selected.toARGB32(),
                        size: 32,
                        onTap: () => _apply(Color(v)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Per-scope favorites + star toggle for the picked color.
  Widget _favoritesRow(BuildContext context, NanoteColors cs) {
    final tools = widget.tools;
    final favs = tools.favoritesOf(tools.colorScope);
    final isFav = favs.contains(_selected.toARGB32());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.t('favorites'), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < 8; i++)
              Expanded(child: _favoriteSlot(context, i, favs, cs)),
            const SizedBox(width: 6),
            _starToggle(isFav, cs),
          ],
        ),
      ],
    );
  }

  Widget _starToggle(bool isFav, NanoteColors cs) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: S.t(isFav ? 'removeFavorite' : 'addFavorite'),
        onPressed: _toggleFavorite,
        icon: Icon(isFav ? Icons.star : Icons.star_border, size: 24),
        color: isFav ? scheme.primary : cs.mutedFg,
      ),
    );
  }

  Widget _swatch(
    BuildContext context, {
    required Color color,
    required bool selected,
    required VoidCallback onTap,
    double size = 40,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Container(
            width: size + (selected ? 8 : 4),
            height: size + (selected ? 8 : 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                width: selected ? 2.5 : 1,
                color: selected ? primary : const Color(0x33000000),
              ),
            ),
            child: Center(
              child: Container(
                width: size - 2,
                height: size - 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(color: const Color(0x1A000000)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _favoriteSlot(
      BuildContext context, int i, List<int> favs, NanoteColors cs) {
    final has = i < favs.length;
    final color = has ? Color(favs[i]) : null;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: has ? () => _apply(color!) : _toggleFavorite,
      child: SizedBox(
        height: 44,
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                width: 1.5,
                color: has ? const Color(0x33000000) : cs.mutedFg,
              ),
            ),
            child: has
                ? null
                : Icon(Icons.add, size: 18, color: cs.mutedFg),
          ),
        ),
      ),
    );
  }

  Widget _wheelSection(BuildContext context, NanoteColors cs) {
    final side =
        (MediaQuery.of(context).size.width * 0.42).clamp(150.0, 210.0).toDouble();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: side,
          height: side,
          child: ColorWheel(hsv: _hsv, onChanged: _setWheel),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _hsv.toColor(),
                      borderRadius: BorderRadius.circular(NANOTE_RADIUS),
                      border: Border.all(color: const Color(0x33000000)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _hex(_selected),
                      style: TextStyle(color: cs.mutedFg, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.brightness_6, size: 18, color: cs.mutedFg),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Slider(
                      value: _hsv.value,
                      min: 0.15,
                      max: 1,
                      onChanged: (v) => _setWheel(
                        HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, v),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              FilledButton.icon(
                onPressed: () => _apply(_hsv.toColor()),
                icon: const Icon(Icons.check),
                label: Text(S.t('done')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _hex(Color c) =>
      c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
}

/// Draggable spectrum color wheel: conic hue sweep + radial white overlay
/// (saturation), with the current position shown as a thumb. Shared by the
/// color popover and the tool settings panel.
class ColorWheel extends StatelessWidget {
  const ColorWheel({super.key, required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => _update(d.localPosition, side),
          onPanUpdate: (d) => _update(d.localPosition, side),
          child: CustomPaint(
            size: Size.square(side),
            painter: _WheelPainter(hsv),
          ),
        );
      },
    );
  }

  void _update(Offset pos, double side) {
    if (side <= 0) return;
    final center = Offset(side / 2, side / 2);
    final radius = side / 2;
    final dx = pos.dx - center.dx;
    final dy = pos.dy - center.dy;
    var hue = math.atan2(dy, dx) * 180 / math.pi;
    if (hue < 0) hue += 360;
    final saturation =
        (math.sqrt(dx * dx + dy * dy) / radius).clamp(0.0, 1.0).toDouble();
    onChanged(HSVColor.fromAHSV(1, hue, saturation, hsv.value));
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Conic hue sweep (12 steps + wrap).
    final hues = <Color>[
      for (var i = 0; i < 12; i++)
        HSVColor.fromAHSV(1, i * 30.0, 1, 1).toColor(),
    ];
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(colors: [...hues, hues.first])
            .createShader(rect),
    );

    // Radial saturation: white center fading out.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Colors.white, Color(0x00FFFFFF)],
        ).createShader(rect),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x33000000),
    );

    // Thumb.
    final angle = hsv.hue * math.pi / 180;
    final r = hsv.saturation * radius;
    final thumb = Offset(
      center.dx + r * math.cos(angle),
      center.dy + r * math.sin(angle),
    );
    canvas.drawCircle(
      thumb,
      10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
    canvas.drawCircle(
      thumb,
      10,
      Paint()
        ..style = PaintingStyle.fill
        ..color = hsv.toColor(),
    );
    canvas.drawCircle(
      thumb,
      10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x66000000),
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      oldDelegate.hsv != hsv;
}
