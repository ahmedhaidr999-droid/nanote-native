import 'package:flutter/material.dart';

import '../controllers/laser_controller.dart';
import '../controllers/settings_controller.dart';
import '../controllers/tool_controller.dart';
import '../i18n/strings.dart';
import '../models/paper.dart';
import '../models/stroke.dart';
import '../models/tool.dart';
import '../theme/nanote_theme.dart';

/// Floating per-tool settings panel, shown next to the tool rail.
///
/// Behavior (user request): tapping a tool in the rail selects it AND opens
/// its own settings (color, kind, properties); tapping the ACTIVE tool again
/// closes the panel. Everything edits live through [ToolController].
class ToolSettingsPanel extends StatelessWidget {
  ToolSettingsPanel({super.key, required this.tools});

  final ToolController tools;

  StrokeKind? _kindFor(Tool t) {
    switch (t) {
      case Tool.fountain:
        return StrokeKind.fountain;
      case Tool.ballpoint:
        return StrokeKind.ballpoint;
      case Tool.brush:
        return StrokeKind.brush;
      case Tool.fineliner:
        return StrokeKind.fineliner;
      case Tool.highlighter:
        return StrokeKind.highlighter;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([
        tools,
        SettingsController.I,
        LaserController.I,
      ]),
      builder: (context, _) {
        final t = tools.tool;
        return Container(
          width: 268,
          constraints: const BoxConstraints(maxHeight: 460),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(NANOTE_RADIUS + 2),
            border: Border.all(color: scheme.outline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, scheme, t),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  child: _body(context, scheme, t),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- header

  Widget _header(BuildContext context, ColorScheme scheme, Tool t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: nanoteColors(context).accent,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(NANOTE_RADIUS + 2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              S.t(t.key),
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: tools.closeSettings,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close, size: 18, color: scheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- body

  Widget _body(BuildContext context, ColorScheme scheme, Tool t) {
    final kind = _kindFor(t);
    if (kind != null) return _penBody(context, scheme, kind);
    switch (t) {
      case Tool.eraser:
        return _eraserBody(scheme);
      case Tool.laser:
        return _laserBody(scheme);
      case Tool.text:
        return _textBody(context, scheme);
      case Tool.shape:
        return _shapeBody(context, scheme);
      case Tool.lasso:
        return _hintBody('lassoHint');
      case Tool.image:
        return _hintBody('imageHint');
      case Tool.sticker:
        return _hintBody('stickerHint');
      case Tool.pan:
        return _hintBody('panHint');
      default:
        return _hintBody('panHint');
    }
  }
  // ---------------------------------------------------------------- pieces

  Widget _label(String key) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        S.t(key),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _hintBody(String key) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        S.t(key),
        style: const TextStyle(fontSize: 12.5, height: 1.5),
      ),
    );
  }

  /// Color swatch grid + favorites/recent rows.
  Widget _colorPalette({
    required List<Color> palette,
    required int current,
    required ValueChanged<int> onPick,
    bool compact = false,
  }) {
    final favorites = tools.favoriteColors;
    final recents = tools.recentColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in palette)
              _swatch(c.toARGB32() == current, c, () {
                onPick(c.toARGB32());
                tools.addRecentColor(c.toARGB32());
              }),
          ],
        ),
        if (!compact && favorites.isNotEmpty) ...[
          _label('favorites'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in favorites)
                _swatch(c == current, Color(c), () => onPick(c)),
            ],
          ),
        ],
        if (!compact && recents.isNotEmpty) ...[
          _label('recentColors'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in recents)
                _swatch(c == current, Color(c), () => onPick(c)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _swatch(bool selected, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected ? Colors.black : Colors.white.withValues(alpha: 0.9),
            width: selected ? 3 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider({
    required double value,
    required double min,
    required double max,
    int? divisions,
    String Function(double)? label,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: label?.call(value),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            label?.call(value) ?? '',
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _segmented<T>({
    required T current,
    required List<T> values,
    required String Function(T) label,
    required ValueChanged<T> onChanged,
    required ColorScheme scheme,
  }) {
    return Wrap(
      spacing: 6,
      children: [
        for (final v in values)
          _chip(label(v), current == v, () => onChanged(v), scheme),
      ],
    );
  }

  Widget _chip(String text, bool active, VoidCallback onTap, ColorScheme scheme) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? scheme.primary.withValues(alpha: 0.14)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? scheme.primary.withValues(alpha: 0.6)
                : scheme.outline.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5))),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ pens

  Widget _penBody(BuildContext context, ColorScheme scheme, StrokeKind kind) {
    final isHighlighter = kind == StrokeKind.highlighter;
    final palette =
        isHighlighter ? HIGHLIGHTER_PALETTE : INK_PALETTE;
    final pen = tools.pen(kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('color'),
        _colorPalette(
          palette: palette,
          current: pen.color,
          onPick: (c) => tools.setPenColor(c),
        ),
        _label('width'),
        _slider(
          value: pen.size,
          min: 0.5,
          max: isHighlighter ? 48 : 24,
          label: (v) => v.toStringAsFixed(1),
          onChanged: (v) => tools.setPenSize(v),
        ),
        if (isHighlighter) ...[
          _label('highlighterOpacity'),
          _slider(
            value: SettingsController.I.settings.highlighterOpacity,
            min: 0.1,
            max: 1.0,
            divisions: 9,
            label: (v) => '${(v * 100).round()}%',
            onChanged: (v) =>
                SettingsController.I.setHighlighterOpacity(v),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- eraser

  Widget _eraserBody(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('eraserMode'),
        _segmented<EraserMode>(
          current: tools.eraserMode,
          values: EraserMode.values,
          label: (m) => S.t(m == EraserMode.stroke ? 'eraserStroke' : 'eraserArea'),
          onChanged: (m) => tools.eraserMode = m,
          scheme: scheme,
        ),
        _label('eraserSize'),
        _slider(
          value: tools.eraserRadius,
          min: 6,
          max: 96,
          label: (v) => v.round().toString(),
          onChanged: (v) => tools.setEraserRadius(v),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: [
            for (var i = 0; i < ToolController.eraserPresets.length; i++)
              _chip(
                S.t(['small', 'medium', 'large'][i]),
                tools.eraserRadius == ToolController.eraserPresets[i],
                () => tools.setEraserRadius(ToolController.eraserPresets[i]),
                scheme,
              ),
          ],
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- laser

  Widget _laserBody(ColorScheme scheme) {
    final laser = LaserController.I;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('laserColor'),
        _colorPalette(
          palette: const [
            Color(0xFFE5484D),
            Color(0xFFFF9F1C),
            Color(0xFF22A06B),
            Color(0xFF1E6FF2),
            Color(0xFF9333EA),
          ],
          current: laser.color,
          onPick: (c) {
            laser.color = c;
            laser.tick();
          },
          compact: true,
        ),
        _label('laserMode'),
        _segmented<LaserMode>(
          current: laser.mode,
          values: LaserMode.values,
          label: (m) => S.t(m == LaserMode.normal ? 'laserNormal' : 'laserTimed'),
          onChanged: (m) {
            laser.mode = m;
            laser.tick();
          },
          scheme: scheme,
        ),
        if (laser.mode == LaserMode.timed) ...[
          _label('laserSeconds'),
          _slider(
            value: laser.seconds.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            label: (v) => '${v.round()}${S.t('seconds')}',
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

  Widget _textBody(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('textSize'),
        _slider(
          value: tools.textSize,
          min: 8,
          max: 96,
          label: (v) => v.round().toString(),
          onChanged: (v) => tools.setTextSize(v),
        ),
        _label('font'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final f in TextFontId.values)
              _chip(S.t(f.key), tools.textFont == f, () => tools.setTextFont(f), scheme),
          ],
        ),
        _label('textColor'),
        _colorPalette(
          palette: INK_PALETTE,
          current: tools.textColor,
          onPick: (c) => tools.setTextColor(c),
          compact: true,
        ),
        _label('style'),
        Wrap(
          spacing: 6,
          children: [
            _chip('B', tools.textBold, () => tools.setTextBold(!tools.textBold), scheme),
            _chip('I', tools.textItalic, () => tools.setTextItalic(!tools.textItalic), scheme),
            _chip('U', tools.textUnderline, () => tools.setTextUnderline(!tools.textUnderline), scheme),
          ],
        ),
        const SizedBox(height: 6),
        _segmented<int>(
          current: tools.textAlign,
          values: const [0, 1, 2],
          label: (a) => S.t(
            a == 0 ? 'alignStart' : (a == 1 ? 'alignCenter' : 'alignEnd'),
          ),
          onChanged: tools.setTextAlign,
          scheme: scheme,
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- shape

  static const Map<ShapeType, IconData> _shapeIcons = {
    ShapeType.line: Icons.horizontal_rule,
    ShapeType.arrow: Icons.arrow_forward,
    ShapeType.doubleArrow: Icons.sync_alt,
    ShapeType.arc: Icons.gradient,
    ShapeType.rect: Icons.crop_square,
    ShapeType.roundedRect: Icons.rounded_corner,
    ShapeType.ellipse: Icons.circle_outlined,
    ShapeType.triangle: Icons.change_history,
    ShapeType.star: Icons.star_border,
    ShapeType.hexagon: Icons.hexagon_outlined,
    ShapeType.polygon: Icons.pentagon_outlined,
    ShapeType.freeform: Icons.gesture,
  };

  Widget _shapeBody(BuildContext context, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('tool.shape'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in _shapeIcons.entries)
              _iconChip(
                e.value,
                tools.shapeType == e.key,
                S.t(e.key.key),
                () => tools.setShapeType(e.key),
                scheme,
              ),
          ],
        ),
        _label('shape.strokeColor'),
        _colorPalette(
          palette: INK_PALETTE,
          current: tools.shapeStrokeColor,
          onPick: (c) => tools.setShapeStrokeColor(c),
          compact: true,
        ),
        _label('shape.strokeWidth'),
        _slider(
          value: tools.shapeStrokeWidth,
          min: 0.5,
          max: 24,
          label: (v) => v.toStringAsFixed(1),
          onChanged: (v) => tools.setShapeStrokeWidth(v),
        ),
        _toggle('shape.fill', tools.shapeFillColor != null, (v) {
          tools.setShapeFillColor(v ? tools.shapeStrokeColor : null);
        }),
        if (tools.shapeFillColor != null) ...[
          _colorPalette(
            palette: INK_PALETTE,
            current: tools.shapeFillColor ?? tools.shapeStrokeColor,
            onPick: (c) => tools.setShapeFillColor(c),
            compact: true,
          ),
          _label('shape.fillOpacity'),
          _slider(
            value: tools.shapeFillOpacity,
            min: 0.05,
            max: 1.0,
            divisions: 19,
            label: (v) => '${(v * 100).round()}%',
            onChanged: (v) => tools.setShapeFillOpacity(v),
          ),
        ],
        _toggle('shape.gridSnap', tools.shapeGridSnap, tools.setShapeGridSnap),
        _toggle('shape.aspectLock', tools.shapeAspectLock, tools.setShapeAspectLock),
        if (tools.shapeType == ShapeType.polygon) ...[
          _label('shape.sides'),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => tools.setShapeSides(tools.shapeSides - 1),
              ),
              Text(
                S.num(tools.shapeSides),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => tools.setShapeSides(tools.shapeSides + 1),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _iconChip(IconData icon, bool active, String tooltip,
      VoidCallback onTap, ColorScheme scheme) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active
                ? scheme.primary.withValues(alpha: 0.14)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(NANOTE_RADIUS),
            border: Border.all(
              color: active
                  ? scheme.primary.withValues(alpha: 0.6)
                  : scheme.outline.withValues(alpha: 0.4),
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: active ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
