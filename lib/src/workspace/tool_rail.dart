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
/// * 13 tool buttons — the ACTIVE tool is highlighted with the accent
///   background + primary color.
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
    Tool.fountain: Icons.edit,
    Tool.ballpoint: Icons.draw,
    Tool.brush: Icons.brush,
    Tool.fineliner: Icons.edit_note,
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
    return Container(
      decoration: BoxDecoration(
        color: active ? colors.accent : null,
        borderRadius: BorderRadius.circular(NANOTE_RADIUS),
      ),
      child: IconButton(
        icon: Icon(_toolIcons[t], size: 22),
        color: active ? scheme.primary : colors.mutedFg,
        tooltip: S.t(t.key),
        onPressed: () => tools.tool = t,
      ),
    );
  }

  static StrokeKind? _penKind(Tool t) {
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

  /// The color swatch shows the color the ACTIVE tool would draw with.
  int _activeColor() {
    final kind = _penKind(tools.tool);
    if (kind != null) return tools.pen(kind).color;
    switch (tools.tool) {
      case Tool.laser:
        return tools.laser.color;
      case Tool.text:
        return tools.textColor;
      case Tool.shape:
        return tools.shapeStrokeColor;
      default:
        return tools.pen(StrokeKind.fountain).color;
    }
  }
}
