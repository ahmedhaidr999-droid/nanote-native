import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../controllers/laser_controller.dart';
import '../controllers/settings_controller.dart';
import '../controllers/tool_controller.dart';
import '../i18n/strings.dart';
import '../models/paper.dart';
import '../models/stroke.dart';
import '../models/tool.dart';
import '../theme/nanote_theme.dart';
import '../ui/panels/color_popover.dart'
    show ColorWheel, paletteFor, showColorPopover;

/// Floating per-tool settings popover, shown next to the tool rail.
///
/// Behavior (user request): tapping a tool in the rail selects it AND opens
/// its own settings (color, kind, properties); tapping the ACTIVE tool again
/// closes the panel. Everything edits live through [ToolController].
///
/// v1.9.1 restyle: 256px card popover (radius 12, 1px border, ink-2 shadow),
/// equal-width segmented controls on a surfaceVariant track, 5-column color
/// grids with ringed selection, tabular values beside each section title,
/// an INLINE mini spectrum wheel plus a "more colors" button that opens the
/// full color popover, and per-scope FAVORITES with a star toggle.
class ToolSettingsPanel extends StatelessWidget {
  const ToolSettingsPanel({
    super.key,
    required this.tools,
    this.maxWidth = 256,
    this.maxHeight = 470,
    this.onClearPage,
  });

  final ToolController tools;

  /// §0-constrained panel box (the workspace passes the available room).
  final double maxWidth;
  final double maxHeight;

  /// "Clear page" (eraser section): wipes the CURRENT page's ink + elements.
  /// Two-stage confirm — the button arms first, a second tap within 3s fires.
  final VoidCallback? onClearPage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cs = nanoteColors(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        tools,
        SettingsController.I,
        LaserController.I,
      ]),
      builder: (context, _) {
        final t = tools.tool;
        return Container(
          width: maxWidth,
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(NANOTE_RADIUS),
            border: Border.all(color: scheme.outline),
            boxShadow: cs.inkShadow2,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, t),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.only(
                    start: 12,
                    end: 12,
                    bottom: 12,
                  ),
                  child: _body(context, t),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- header

  Widget _header(BuildContext context, Tool t) {
    final cs = nanoteColors(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: 12,
        end: 2,
        top: 4,
        bottom: 4,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              S.t(t.key),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: nanoteText(TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              )),
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: S.t('close'),
              onPressed: tools.closeSettings,
              icon: Icon(LucideIcons.x, size: 18, color: cs.mutedFg),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- body

  Widget _body(BuildContext context, Tool t) {
    switch (t) {
      case Tool.pen:
        return _penBody(context);
      case Tool.highlighter:
        return _highlighterBody(context);
      case Tool.eraser:
        return _eraserBody(context);
      case Tool.laser:
        return _laserBody(context);
      case Tool.text:
        return _textBody(context);
      case Tool.shape:
        return _shapeBody(context);
      case Tool.lasso:
        return _hintBody(context, 'lassoHint');
      case Tool.image:
        return _hintBody(context, 'imageHint');
      case Tool.sticker:
        return _hintBody(context, 'stickerHint');
      case Tool.pan:
        return _hintBody(context, 'panHint');
      case Tool.textSelect:
        return _hintBody(context, 'textSelectHint');
    }
  }

  // ---------------------------------------------------------------- pieces

  Widget _hintBody(BuildContext context, String key) {
    final cs = nanoteColors(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        S.t(key),
        style: nanoteText(
          TextStyle(fontSize: 12.5, height: 1.5, color: cs.mutedFg),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ pens

  static const Map<PenKind, IconData> _penKindIcons = {
    PenKind.fountain: LucideIcons.pen_tool,
    PenKind.ballpoint: LucideIcons.pen,
    PenKind.brush: LucideIcons.brush,
    PenKind.fineliner: LucideIcons.pen_line,
  };

  Widget _penBody(BuildContext context) {
    final pen = tools.pen(tools.penKind.strokeKind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionRow(context, 'penType'),
        _segmented<PenKind>(
          context: context,
          current: tools.penKind,
          values: PenKind.values,
          tooltip: (k) => S.t(k.key),
          childBuilder: (ctx, k, sel) => Icon(
            _penKindIcons[k],
            size: 18,
            color: sel
                ? Theme.of(ctx).colorScheme.primary
                : nanoteColors(ctx).mutedFg,
          ),
          onChanged: (k) => tools.penKind = k,
        ),
        _sectionRow(context, 'color'),
        _ColorSection(
          tools: tools,
          scope: ColorScope.pen,
          current: pen.color,
          onPick: tools.setPenColor,
        ),
        _sectionRow(
          context,
          'width',
          value: S.num(pen.size.toStringAsFixed(1)),
        ),
        _panelSlider(
          value: pen.size,
          min: 0.5,
          max: 24,
          onChanged: (v) => tools.setPenSize(v),
        ),
      ],
    );
  }

  Widget _highlighterBody(BuildContext context) {
    final pen = tools.pen(StrokeKind.highlighter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionRow(context, 'color'),
        _ColorSection(
          tools: tools,
          scope: ColorScope.highlighter,
          current: pen.color,
          onPick: tools.setPenColor,
        ),
        _sectionRow(
          context,
          'width',
          value: S.num(pen.size.toStringAsFixed(1)),
        ),
        _panelSlider(
          value: pen.size,
          min: 0.5,
          max: 48,
          onChanged: (v) => tools.setPenSize(v),
        ),
        _sectionRow(
          context,
          'highlighterOpacity',
          value: '${S.num(
            (SettingsController.I.settings.highlighterOpacity * 100).round(),
          )}%',
        ),
        _panelSlider(
          value: SettingsController.I.settings.highlighterOpacity,
          min: 0.1,
          max: 1.0,
          divisions: 9,
          onChanged: (v) => SettingsController.I.setHighlighterOpacity(v),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- eraser

  Widget _eraserBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionRow(context, 'eraserMode'),
        _segmented<EraserMode>(
          context: context,
          current: tools.eraserMode,
          values: EraserMode.values,
          childBuilder: (ctx, m, sel) => _segmentLabel(
            ctx,
            S.t(m == EraserMode.stroke ? 'eraserStroke' : 'eraserArea'),
            sel,
          ),
          onChanged: (m) => tools.eraserMode = m,
        ),
        _sectionRow(
          context,
          'eraserSize',
          value: S.num(tools.eraserRadius.round().toString()),
        ),
        _panelSlider(
          value: tools.eraserRadius,
          min: 6,
          max: 96,
          onChanged: (v) => tools.setEraserRadius(v),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (var i = 0; i < ToolController.eraserPresets.length; i++)
              _presetPill(
                context,
                S.num(ToolController.eraserPresets[i].round().toString()),
                tools.eraserRadius == ToolController.eraserPresets[i],
                () => tools.setEraserRadius(ToolController.eraserPresets[i]),
              ),
          ],
        ),
        if (onClearPage != null) ...[
          const SizedBox(height: 14),
          _ClearPageButton(onClearPage: onClearPage!),
        ],
      ],
    );
  }

  // ----------------------------------------------------------------- laser

  Widget _laserBody(BuildContext context) {
    final laser = LaserController.I;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionRow(context, 'laserColor'),
        _ColorSection(
          tools: tools,
          scope: ColorScope.laser,
          current: laser.color,
          onPick: (c) {
            laser.color = c;
            laser.tick();
          },
        ),
        _sectionRow(context, 'laserMode'),
        _segmented<LaserMode>(
          context: context,
          current: laser.mode,
          values: LaserMode.values,
          childBuilder: (ctx, m, sel) => _segmentLabel(
            ctx,
            S.t(m == LaserMode.normal ? 'laserNormal' : 'laserTimed'),
            sel,
          ),
          onChanged: (m) {
            laser.mode = m;
            laser.tick();
          },
        ),
        if (laser.mode == LaserMode.timed) ...[
          _sectionRow(
            context,
            'laserSeconds',
            value: '${S.num(laser.seconds)}${S.t('seconds')}',
          ),
          _panelSlider(
            value: laser.seconds.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            onChanged: (v) {
              laser.seconds = v.round();
              laser.tick();
            },
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------------ text

  Widget _textBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cs = nanoteColors(context);
    Widget styleGlyph(bool active, Widget child, String tooltip,
            VoidCallback onTap) =>
        Tooltip(
          message: tooltip,
          child: Pressable(
            onTap: onTap,
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: active ? cs.accent : cs.surfaceVariant,
                borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
              ),
              child: Center(child: child),
            ),
          ),
        );
    Color glyphColor(bool active) => active ? scheme.primary : cs.mutedFg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionRow(
          context,
          'textSize',
          value: S.num(tools.textSize.round().toString()),
        ),
        _panelSlider(
          value: tools.textSize,
          min: 8,
          max: 96,
          onChanged: (v) => tools.setTextSize(v),
        ),
        _sectionRow(context, 'font'),
        _trackedGrid(
          context,
          [
            for (final f in TextFontId.values) _fontTile(context, f),
          ],
          3,
        ),
        _sectionRow(context, 'textColor'),
        _ColorSection(
          tools: tools,
          scope: ColorScope.pen,
          current: tools.textColor,
          onPick: tools.setTextColor,
        ),
        _sectionRow(context, 'style'),
        Row(
          children: [
            Expanded(
              child: styleGlyph(
                tools.textBold,
                Text(
                  'B',
                  style: nanoteText(TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: glyphColor(tools.textBold),
                  )),
                ),
                S.t('bold'),
                () => tools.setTextBold(!tools.textBold),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: styleGlyph(
                tools.textItalic,
                Icon(LucideIcons.italic,
                    size: 18, color: glyphColor(tools.textItalic)),
                S.t('italic'),
                () => tools.setTextItalic(!tools.textItalic),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: styleGlyph(
                tools.textUnderline,
                Icon(LucideIcons.underline,
                    size: 18, color: glyphColor(tools.textUnderline)),
                S.t('underline'),
                () => tools.setTextUnderline(!tools.textUnderline),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _segmented<int>(
          context: context,
          current: tools.textAlign,
          values: const [0, 1, 2],
          tooltip: (a) => S.t(
            a == 0 ? 'alignStart' : (a == 1 ? 'alignCenter' : 'alignEnd'),
          ),
          childBuilder: (ctx, a, sel) => Icon(
            a == 0
                ? LucideIcons.text_align_start
                : (a == 1
                    ? LucideIcons.text_align_center
                    : LucideIcons.text_align_end),
            size: 17,
            color: sel
                ? Theme.of(ctx).colorScheme.primary
                : nanoteColors(ctx).mutedFg,
          ),
          onChanged: tools.setTextAlign,
        ),
      ],
    );
  }

  Widget _fontTile(BuildContext context, TextFontId f) {
    final selected = tools.textFont == f;
    final scheme = Theme.of(context).colorScheme;
    final cs = nanoteColors(context);
    return Pressable(
      onTap: () => tools.setTextFont(f),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: selected ? scheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
          boxShadow: selected ? cs.inkShadow1 : null,
        ),
        child: Center(
          child: Text(
            S.t(f.key),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: nanoteText(TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? scheme.primary : cs.mutedFg,
            )).copyWith(fontFamily: f.fontFamily),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- shape

  static const Map<ShapeType, IconData> _shapeIcons = {
    ShapeType.line: LucideIcons.minus,
    ShapeType.arrow: LucideIcons.arrow_right,
    ShapeType.doubleArrow: LucideIcons.arrow_left_right,
    ShapeType.arc: LucideIcons.spline,
    ShapeType.rect: LucideIcons.square,
    ShapeType.roundedRect: LucideIcons.square_round_corner,
    ShapeType.ellipse: LucideIcons.circle,
    ShapeType.triangle: LucideIcons.triangle,
    ShapeType.star: LucideIcons.star,
    ShapeType.hexagon: LucideIcons.hexagon,
    ShapeType.polygon: LucideIcons.pentagon,
    ShapeType.freeform: LucideIcons.signature,
  };

  Widget _shapeTile(BuildContext context, MapEntry<ShapeType, IconData> e) {
    final selected = tools.shapeType == e.key;
    final scheme = Theme.of(context).colorScheme;
    final cs = nanoteColors(context);
    return Tooltip(
      message: S.t(e.key.key),
      child: Pressable(
        onTap: () => tools.setShapeType(e.key),
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: selected ? scheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
            boxShadow: selected ? cs.inkShadow1 : null,
          ),
          child: Center(
            child: Icon(
              e.value,
              size: 16,
              color: selected ? scheme.primary : cs.mutedFg,
            ),
          ),
        ),
      ),
    );
  }

  Widget _shapeBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionRow(context, 'tool.shape'),
        _trackedGrid(
          context,
          [for (final e in _shapeIcons.entries) _shapeTile(context, e)],
          6,
          gap: 5,
        ),
        _sectionRow(context, 'shape.strokeColor'),
        _ColorSection(
          tools: tools,
          scope: ColorScope.pen,
          current: tools.shapeStrokeColor,
          onPick: tools.setShapeStrokeColor,
        ),
        _sectionRow(
          context,
          'shape.strokeWidth',
          value: S.num(tools.shapeStrokeWidth.toStringAsFixed(1)),
        ),
        _panelSlider(
          value: tools.shapeStrokeWidth,
          min: 0.5,
          max: 24,
          onChanged: (v) => tools.setShapeStrokeWidth(v),
        ),
        _switchRow(context, 'shape.fill', tools.shapeFillColor != null, (v) {
          tools.setShapeFillColor(v ? tools.shapeStrokeColor : null);
        }),
        if (tools.shapeFillColor != null) ...[
          _ColorSection(
            tools: tools,
            scope: ColorScope.pen,
            current: tools.shapeFillColor ?? tools.shapeStrokeColor,
            onPick: tools.setShapeFillColor,
          ),
          _sectionRow(
            context,
            'shape.fillOpacity',
            value:
                '${S.num((tools.shapeFillOpacity * 100).round())}%',
          ),
          _panelSlider(
            value: tools.shapeFillOpacity,
            min: 0.05,
            max: 1.0,
            divisions: 19,
            onChanged: (v) => tools.setShapeFillOpacity(v),
          ),
        ],
        _switchRow(
            context, 'shape.gridSnap', tools.shapeGridSnap, tools.setShapeGridSnap),
        _switchRow(context, 'shape.aspectLock', tools.shapeAspectLock,
            tools.setShapeAspectLock),
        if (tools.shapeType == ShapeType.polygon) ...[
          _sectionRow(context, 'shape.sides', value: S.num(tools.shapeSides)),
          _stepperRow(
            context,
            tools.shapeSides,
            () => tools.setShapeSides(tools.shapeSides - 1),
            () => tools.setShapeSides(tools.shapeSides + 1),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared v1.9.1 panel building blocks (library-private).
// ---------------------------------------------------------------------------

/// Section title row: 12px w700 muted label + optional tabular value on the
/// end side (e.g. "السماكة 2.4" / "Size 2.4").
Widget _sectionRow(BuildContext context, String key, {String? value}) {
  final cs = nanoteColors(context);
  return Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            S.t(key),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: nanoteText(TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.mutedFg,
            )),
          ),
        ),
        if (value != null)
          Text(
            value,
            style: nanoteText(TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: cs.mutedFg,
            )),
          ),
      ],
    ),
  );
}

/// Thin-track slider on a 44px touch row (colors come from the theme).
Widget _panelSlider({
  required double value,
  required double min,
  required double max,
  int? divisions,
  required ValueChanged<double> onChanged,
}) {
  return SizedBox(
    height: 44,
    child: Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      onChanged: onChanged,
    ),
  );
}

/// Equal-width segmented control: surfaceVariant track (radius 10) with the
/// selected segment lifted to the card surface (ink-1 shadow, primary
/// content) and unselected content in mutedFg.
Widget _segmented<T>({
  required BuildContext context,
  required T current,
  required List<T> values,
  required Widget Function(BuildContext, T, bool) childBuilder,
  String Function(T)? tooltip,
  required ValueChanged<T> onChanged,
}) {
  return Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: nanoteColors(context).surfaceVariant,
      borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
    ),
    child: Row(
      children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: i == 0 ? 0 : 2,
                end: i == values.length - 1 ? 0 : 2,
              ),
              child: _segmentTile(
                context,
                selected: current == values[i],
                tooltip: tooltip?.call(values[i]),
                onTap: () => onChanged(values[i]),
                child: childBuilder(context, values[i], current == values[i]),
              ),
            ),
          ),
      ],
    ),
  );
}

Widget _segmentTile(
  BuildContext context, {
  required bool selected,
  String? tooltip,
  required VoidCallback onTap,
  required Widget child,
}) {
  final scheme = Theme.of(context).colorScheme;
  final cs = nanoteColors(context);
  Widget tile = Pressable(
    onTap: onTap,
    child: Container(
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? scheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
        boxShadow: selected ? cs.inkShadow1 : null,
      ),
      child: child,
    ),
  );
  if (tooltip != null) tile = Tooltip(message: tooltip, child: tile);
  return tile;
}

/// Segment text label (scales down instead of overflowing).
Widget _segmentLabel(BuildContext context, String text, bool selected) {
  final scheme = Theme.of(context).colorScheme;
  final cs = nanoteColors(context);
  return Padding(
    padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        style: nanoteText(TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          color: selected ? scheme.primary : cs.mutedFg,
        )),
      ),
    ),
  );
}

/// Full pill preset chip (eraser sizes): filled primary when active.
Widget _presetPill(
    BuildContext context, String label, bool active, VoidCallback onTap) {
  final scheme = Theme.of(context).colorScheme;
  final cs = nanoteColors(context);
  return Pressable(
    onTap: onTap,
    child: Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: active ? scheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: active ? null : Border.all(color: scheme.outline),
      ),
      child: Center(
        child: Text(
          label,
          style: nanoteText(TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            color: active ? scheme.onPrimary : cs.mutedFg,
          )),
        ),
      ),
    ),
  );
}

/// 44px labeled row with a trailing switch.
Widget _switchRow(
    BuildContext context, String label, bool value, ValueChanged<bool> onChanged) {
  return SizedBox(
    height: 44,
    child: Row(
      children: [
        Expanded(
          child: Text(
            S.t(label),
            style: nanoteText(const TextStyle(fontSize: 13)),
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    ),
  );
}

/// −/+ stepper (e.g. polygon sides) with tabular center readout.
Widget _stepperRow(
    BuildContext context, int value, VoidCallback onMinus, VoidCallback onPlus) {
  final scheme = Theme.of(context).colorScheme;
  final cs = nanoteColors(context);
  Widget step(IconData icon, VoidCallback onTap) => Pressable(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: cs.surfaceVariant,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Icon(icon, size: 16, color: scheme.onSurface),
          ),
        ),
      );
  return Row(
    children: [
      step(LucideIcons.minus, onMinus),
      Expanded(
        child: Center(
          child: Text(
            S.num(value),
            style: nanoteText(TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            )),
          ),
        ),
      ),
      step(LucideIcons.plus, onPlus),
    ],
  );
}

/// Grid of tiles laid out as [perRow]-per-row Rows (equal widths), sitting on
/// a surfaceVariant track like the segmented control.
Widget _trackedGrid(
    BuildContext context, List<Widget> cells, int perRow,
    {double gap = 6}) {
  final cs = nanoteColors(context);
  return Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: cs.surfaceVariant,
      borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
    ),
    child: Column(
      children: _gridCells(cells, perRow, gap: gap),
    ),
  );
}

/// Splits [cells] into equal-width rows of [perRow] items.
List<Widget> _gridCells(List<Widget> cells, int perRow, {double gap = 6}) {
  final rows = <Widget>[];
  for (var i = 0; i < cells.length; i += perRow) {
    final end = i + perRow > cells.length ? cells.length : i + perRow;
    final chunk = cells.sublist(i, end);
    rows.add(Row(
      children: [
        for (var j = 0; j < perRow; j++)
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: j == 0 ? 0 : gap / 2,
                end: j == perRow - 1 ? 0 : gap / 2,
              ),
              child: j < chunk.length ? chunk[j] : const SizedBox.shrink(),
            ),
          ),
      ],
    ));
    if (end < cells.length) rows.add(SizedBox(height: gap));
  }
  return rows;
}

/// Exactly-5-column color grid of 36px rounded-lg swatches (44px targets).
Widget _colorGrid(
  BuildContext context,
  List<Color> colors, {
  required int current,
  required ValueChanged<int> onTap,
}) {
  return Column(
    children: _gridCells(
      [
        for (final c in colors)
          _colorSwatch(
            context,
            c,
            selected: c.toARGB32() == current,
            onTap: () => onTap(c.toARGB32()),
          ),
      ],
      5,
      gap: 6,
    ),
  );
}

/// One swatch: 36px rounded-lg chip; selected = 2px primary border + a
/// ring in the ring color.
Widget _colorSwatch(
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

/// Palette + favorites (per scope, with a star toggle) + the INLINE mini
/// spectrum wheel with a brightness slider, plus a "more colors" button that
/// opens the full color popover. Applies live.
class _ColorSection extends StatefulWidget {
  const _ColorSection({
    required this.tools,
    required this.scope,
    required this.current,
    required this.onPick,
  });

  final ToolController tools;
  final ColorScope scope;
  final int current;
  final ValueChanged<int> onPick;

  @override
  State<_ColorSection> createState() => _ColorSectionState();
}

class _ColorSectionState extends State<_ColorSection> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(Color(widget.current));
  }

  @override
  void didUpdateWidget(covariant _ColorSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow external color changes (palette swatch taps) unless the user is
    // mid-wheel-drag (thumb stays where it is; the apply button uses _hsv).
    if (oldWidget.current != widget.current &&
        widget.current != _hsv.toColor().toARGB32()) {
      _hsv = HSVColor.fromColor(Color(widget.current));
    }
  }

  void _pick(int argb) {
    widget.onPick(argb);
    widget.tools.addRecentColor(argb);
  }

  void _setWheel(HSVColor hsv) {
    setState(() => _hsv = hsv);
    widget.onPick(hsv.toColor().toARGB32());
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tools;
    final palette = paletteFor(widget.scope);
    final favs = t.favoritesOf(widget.scope);
    final wheelColor = _hsv.toColor().toARGB32();
    final isFav = favs.contains(wheelColor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _colorGrid(
          context,
          palette,
          current: widget.current,
          onTap: _pick,
        ),
        const SizedBox(height: 8),
        _moreColorsButton(context),
        if (favs.isNotEmpty) ...[
          _sectionRow(context, 'favorites'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in favs)
                _colorSwatch(
                  context,
                  Color(c),
                  selected: c == widget.current,
                  onTap: () {
                    setState(() => _hsv = HSVColor.fromColor(Color(c)));
                    _pick(c);
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              height: 110,
              child: ColorWheel(hsv: _hsv, onChanged: _setWheel),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Color(wheelColor),
                          borderRadius:
                              BorderRadius.circular(NANOTE_RADIUS_SM),
                          border: Border.all(
                              color: Theme.of(context).colorScheme.outline),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          wheelColor
                              .toRadixString(16)
                              .padLeft(8, '0')
                              .toUpperCase(),
                          style: nanoteText(TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: nanoteColors(context).mutedFg,
                          )),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 40,
                    child: Row(
                      children: [
                        Icon(LucideIcons.sun_medium,
                            size: 14, color: nanoteColors(context).mutedFg),
                        Expanded(
                          child: Slider(
                            value: _hsv.value,
                            min: 0.15,
                            max: 1,
                            onChanged: (v) => _setWheel(
                              HSVColor.fromAHSV(
                                  1, _hsv.hue, _hsv.saturation, v),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(child: _starButton(context, isFav)),
                      const SizedBox(width: 8),
                      Expanded(child: _applyButton(context, wheelColor)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Small full-width button that opens the full-screen color popover (the
  /// same sheet the rail's color chip opens).
  Widget _moreColorsButton(BuildContext context) {
    final cs = nanoteColors(context);
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: () => showColorPopover(context, widget.tools),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
          border: Border.all(color: scheme.outline),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.swatch_book, size: 14, color: cs.mutedFg),
            const SizedBox(width: 6),
            Text(
              S.t('customColor'),
              style: nanoteText(TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.mutedFg,
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _starButton(BuildContext context, bool isFav) {
    final scheme = Theme.of(context).colorScheme;
    final cs = nanoteColors(context);
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(36, 36),
        side: BorderSide(color: isFav ? scheme.primary : scheme.outline),
      ),
      onPressed: () {
        final argb = _hsv.toColor().toARGB32();
        widget.tools.toggleFavoriteColor(argb, scope: widget.scope);
        if (!widget.tools.favoritesOf(widget.scope).contains(argb)) {
          // It was removed — nothing else to do.
        } else {
          _pick(argb);
        }
      },
      child: Icon(
        LucideIcons.star,
        size: 14,
        color: isFav ? scheme.primary : cs.mutedFg,
      ),
    );
  }

  Widget _applyButton(BuildContext context, int wheelColor) {
    return FilledButton(
      style: FilledButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(36, 36),
        textStyle: nanoteText(
            const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      ),
      onPressed: () => _pick(wheelColor),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.check, size: 14),
          const SizedBox(width: 4),
          Text(S.t('done')),
        ],
      ),
    );
  }
}


/// "Clear page" with a TWO-STAGE confirm: the first tap ARMS the button
/// (destructive styling + 3s window), the second tap fires [onClearPage].
class _ClearPageButton extends StatefulWidget {
  const _ClearPageButton({required this.onClearPage});

  final VoidCallback onClearPage;

  @override
  State<_ClearPageButton> createState() => _ClearPageButtonState();
}

class _ClearPageButtonState extends State<_ClearPageButton> {
  bool _armed = false;
  Timer? _disarm;

  @override
  void dispose() {
    _disarm?.cancel();
    super.dispose();
  }

  void _tap() {
    if (!_armed) {
      setState(() => _armed = true);
      _disarm?.cancel();
      _disarm = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    _disarm?.cancel();
    setState(() => _armed = false);
    widget.onClearPage();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cs = nanoteColors(context);
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: _armed ? scheme.onError : scheme.error,
          backgroundColor: _armed ? scheme.error : null,
          side: BorderSide(color: scheme.error),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NANOTE_RADIUS),
          ),
        ),
        onPressed: _tap,
        icon: Icon(LucideIcons.trash_2, size: 16),
        label: Text(
          S.t(_armed ? 'confirmClearPage' : 'clearPage'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: nanoteText(TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          )),
        ),
      ),
    );
  }
}
