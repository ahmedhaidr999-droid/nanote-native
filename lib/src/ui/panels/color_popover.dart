import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../controllers/tool_controller.dart';
import '../../i18n/strings.dart';
import '../../models/paper.dart';
import '../../models/stroke.dart';
import '../../models/tool.dart';
import '../../theme/nanote_theme.dart';

/// Color picker for the CURRENT tool: palette (ink / highlighter / laser by
/// scope), per-scope FAVORITE slots (tap to apply, star to save the picked
/// color), the spectrum color wheel with a brightness slider, and recents.
///
/// v1.9.1 restyle: rounded-top-16 sheet with drag handle + 20px padding,
/// 5-column rounded-lg swatch grid (44px targets), 8 favorite slots + star
/// toggle, tabular hex readout and a pill Apply button.
Future<void> showColorPopover(BuildContext context, ToolController tools) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _ColorSheet(tools: tools),
  );
}

/// Palette for a color scope.
///
/// Laser palette (v1.9.1): destructive red default first — no blues/sky.
List<Color> paletteFor(ColorScope scope) => switch (scope) {
      ColorScope.highlighter => HIGHLIGHTER_PALETTE,
      ColorScope.laser => const [
          Color(0xFFE5484D),
          Color(0xFFFF9F1C),
          Color(0xFF22A06B),
          Color(0xFF9333EA),
          Color(0xFFDB2777),
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
    final scope = tools.colorScope;
    final palette = paletteFor(scope);
    return SafeArea(
      child: SingleChildScrollView(
        padding:
            const EdgeInsetsDirectional.only(start: 20, end: 20, bottom: 20),
        child: AnimatedBuilder(
          animation: tools,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                S.t('color'),
                style: nanoteText(TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                )),
              ),
              const SizedBox(height: 14),
              _swatchGrid(
                context,
                palette,
                selected: _selected.toARGB32(),
                onTap: _apply,
              ),
              const SizedBox(height: 18),
              _favoritesRow(context),
              const SizedBox(height: 18),
              _sectionTitle(context, S.t('customColor')),
              const SizedBox(height: 8),
              _wheelSection(context),
              if (tools.recentColors.isNotEmpty) ...[
                const SizedBox(height: 18),
                _sectionTitle(context, S.t('recentColors')),
                const SizedBox(height: 8),
                _swatchGrid(
                  context,
                  [for (final v in tools.recentColors) Color(v)],
                  selected: _selected.toARGB32(),
                  onTap: _apply,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    final cs = nanoteColors(context);
    return Text(
      text,
      style: nanoteText(TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: cs.mutedFg,
      )),
    );
  }

  /// Per-scope favorites + star toggle for the picked color.
  Widget _favoritesRow(BuildContext context) {
    final tools = widget.tools;
    final favs = tools.favoritesOf(tools.colorScope);
    final isFav = favs.contains(_selected.toARGB32());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, S.t('favorites')),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < 8; i++)
              Expanded(child: _favoriteSlot(context, i, favs)),
            const SizedBox(width: 6),
            _starToggle(context, isFav),
          ],
        ),
      ],
    );
  }

  Widget _starToggle(BuildContext context, bool isFav) {
    final scheme = Theme.of(context).colorScheme;
    final cs = nanoteColors(context);
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: S.t(isFav ? 'removeFavorite' : 'addFavorite'),
        onPressed: _toggleFavorite,
        icon: const Icon(LucideIcons.star, size: 22),
        color: isFav ? scheme.primary : cs.mutedFg,
      ),
    );
  }

  /// Exactly-5-column grid of 36px rounded-lg swatches (44px targets).
  Widget _swatchGrid(
    BuildContext context,
    List<Color> colors, {
    required int selected,
    required ValueChanged<Color> onTap,
  }) {
    Widget row(List<Color> chunk) => Row(
          children: [
            for (var j = 0; j < 5; j++)
              Expanded(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: j == 0 ? 0 : 3,
                    end: j == 4 ? 0 : 3,
                  ),
                  child: j < chunk.length
                      ? _swatch(
                          context,
                          chunk[j],
                          selected: chunk[j].toARGB32() == selected,
                          onTap: () => onTap(chunk[j]),
                        )
                      : const SizedBox(height: 44),
                ),
              ),
          ],
        );
    final rows = <Widget>[];
    for (var i = 0; i < colors.length; i += 5) {
      final end = i + 5 > colors.length ? colors.length : i + 5;
      rows.add(row(colors.sublist(i, end)));
      if (end < colors.length) rows.add(const SizedBox(height: 6));
    }
    return Column(children: rows);
  }

  Widget _swatch(
    BuildContext context,
    Color color, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final cs = nanoteColors(context);
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Center(
          child: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(NANOTE_RADIUS),
              border: Border.all(
                width: 2,
                color: selected
                    ? cs.ring.withValues(alpha: 0.45)
                    : Colors.transparent,
              ),
            ),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
                border: Border.all(
                  width: selected ? 2 : 1,
                  color: selected ? scheme.primary : scheme.outline,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _favoriteSlot(BuildContext context, int i, List<int> favs) {
    final has = i < favs.length;
    final color = has ? Color(favs[i]) : null;
    final scheme = Theme.of(context).colorScheme;
    final cs = nanoteColors(context);
    return Pressable(
      onTap: has ? () => _apply(color!) : _toggleFavorite,
      child: SizedBox(
        height: 44,
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
              color: color,
              border: Border.all(
                width: has ? 1 : 1.4,
                color: has ? scheme.outline : cs.mutedFg.withValues(alpha: 0.7),
              ),
            ),
            child: has
                ? null
                : Icon(LucideIcons.plus, size: 16, color: cs.mutedFg),
          ),
        ),
      ),
    );
  }

  Widget _wheelSection(BuildContext context) {
    final cs = nanoteColors(context);
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
                      borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
                      border: Border.all(color: cs.mutedFg.withValues(alpha: 0.4)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _hex(_selected),
                      style: nanoteText(TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.mutedFg,
                      )),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(LucideIcons.sun_medium, size: 18, color: cs.mutedFg),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Slider(
                      // Clamped: the sheet is seeded with the CURRENT tool
                      // color — a dark legacy color (HSV value < 0.15) would
                      // otherwise trip the Slider "value >= min" assertion.
                      value: _hsv.value.clamp(0.15, 1.0).toDouble(),
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
                icon: const Icon(LucideIcons.check, size: 16),
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
