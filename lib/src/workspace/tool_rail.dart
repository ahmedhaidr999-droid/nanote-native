import 'package:flutter/material.dart';

import '../controllers/stroke_engine.dart';
import '../controllers/tool_controller.dart';
import '../i18n/strings.dart';
import '../models/stroke.dart';
import '../models/tool.dart';
import '../theme/nanote_theme.dart';
import 'ruler_overlay.dart';

/// Vertical tool rail (width 56) of the editor.
///
/// v2.1: the four writing pens are grouped into ONE pen button (the kind is
/// chosen in the pen settings panel). 10 tools total:
/// pen · highlighter · laser · eraser · lasso · text · shape · image ·
/// sticker · pan.
///
/// * The ACTIVE tool is highlighted with the sky accent background +
///   primary color; the pen button shows the selected pen KIND icon.
/// * Undo / redo (disabled states driven by the engine's history).
/// * Ruler toggle (active state).
/// * Current color dot (tap → [onColorTap], opens the color popover).
///
/// All targets are ≥44px (default IconButton minimum 48). The tools column is
/// scrollable so the rail works on short screens; the color swatch is pinned
/// at the bottom. Looks correct on both edges (left-handed and RTL) — the
/// border side follows the [leftHanded] flag.
class ToolRail extends StatelessWidget {
  const ToolRail({
    super.key,
    required this.tools,
    required this.engine,
    required this.ruler,
    this.leftHanded = false,
    this.onColorTap,
    this.onUndo,
    this.onRedo,
    this.hidden = false,
  });

  final ToolController tools;
  final StrokeEngine engine;
  final RulerState ruler;
  final bool leftHanded;
  final VoidCallback? onColorTap;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final bool hidden;

  static const Map<Tool, IconData> _toolIcons = {
    Tool.pen: Icons.edit,
    Tool.highlighter: Icons.highlight,
    Tool.laser: Icons.flashlight_on,
    Tool.eraser: Icons.auto_fix_normal,
    Tool.lasso: Icons.rounded_corner,
    Tool.text: Icons.text_fields,
    Tool.shape: Icons.category,
    Tool.image: Icons.image,
    Tool.sticker: Icons.emoji_emotions,
    Tool.pan: Icons.pan_tool,
  };

  /// The pen button reflects the selected pen KIND.
  static const Map<PenKind, IconData> _penKindIcons = {
    PenKind.fountain: Icons.edit,
    PenKind.ballpoint: Icons.draw,
    PenKind.brush: Icons.brush,
    PenKind.fineliner: Icons.edit_note,
  };

  @override
  Widget build(BuildContext context) {
    if (hidden) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final colors = nanoteColors(context);
    final side = BorderSide(color: scheme.outline);
    return Container(
      width: 56,
      decoration: BoxDecoration(
        color: scheme.surface,
        // Rail sits at the Row's END by default (border faces the canvas),
        // at the START when left-handed.
        border: leftHanded ? Border(right: side) : Border(left: side),
      ),
      child: ListenableBuilder(
        listenable: tools,
        builder: (context, _) {
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final t in Tool.values)
                        _toolButton(context, t, scheme, colors),
                      Divider(height: 1, color: scheme.outline),
                      ListenableBuilder(
                        listenable: engine.historyChanged,
                        builder: (context, _) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.undo, size: 22),
                              tooltip: S.t('undo'),
                              onPressed: engine.canUndo
                                  ? (onUndo ?? engine.undo)
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.redo, size: 22),
                              tooltip: S.t('redo'),
                              onPressed: engine.canRedo
                                  ? (onRedo ?? engine.redo)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.straighten, size: 22),
                        tooltip: S.t('ruler'),
                        color: ruler.active ? scheme.primary : colors.mutedFg,
                        onPressed: ruler.toggle,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 10),
                child: IconButton(
                  tooltip: S.t('color'),
                  onPressed: onColorTap,
                  icon: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(_activeColor()),
                      border: Border.all(color: scheme.outline, width: 2),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _toolButton(
    BuildContext context,
    Tool t,
    ColorScheme scheme,
    NanoteColors colors,
  ) {
    final active = tools.tool == t;
    final icon = t == Tool.pen ? _penKindIcons[tools.penKind]! : _toolIcons[t]!;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        // Lively accent: a soft sky gradient wash behind the active tool.
        gradient: active
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.accent,
                  Color.lerp(colors.accent, scheme.primary, 0.18)!,
                ],
              )
            : null,
        color: active ? colors.accent : null,
        borderRadius: BorderRadius.circular(NANOTE_RADIUS),
      ),
      child: IconButton(
        icon: Icon(icon, size: 22),
        color: active ? scheme.primary : colors.mutedFg,
        tooltip: t == Tool.pen
            ? '${S.t('tool.pen')} · ${S.t(tools.penKind.key)}'
            : S.t(t.key),
        // Tap inactive tool → select + open its settings panel.
        // Tap the ACTIVE tool again → toggle the panel closed/open.
        onPressed: () => tools.railTap(t),
      ),
    );
  }

  /// The color swatch shows the color the ACTIVE tool would draw with.
  int _activeColor() {
    switch (tools.tool) {
      case Tool.pen:
        return tools.pen(tools.penKind.strokeKind).color;
      case Tool.highlighter:
        return tools.pen(StrokeKind.highlighter).color;
      case Tool.laser:
        return tools.laser.color;
      case Tool.text:
        return tools.textColor;
      case Tool.shape:
        return tools.shapeStrokeColor;
      default:
        return tools.pen(tools.penKind.strokeKind).color;
    }
  }
}
