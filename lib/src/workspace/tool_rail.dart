import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../controllers/stroke_engine.dart';
import '../controllers/tool_controller.dart';
import '../i18n/strings.dart';
import '../models/stroke.dart';
import '../models/tool.dart';
import '../theme/nanote_theme.dart';
import 'ruler_overlay.dart';

/// Where the floating tool rail is docked.
///
/// * [RailDock.bottom] — horizontal capsule, bottom-center of the canvas.
/// * [RailDock.start] / [RailDock.end] — vertical capsule on the logical
///   start/end edge (flips with RTL). The user DRAGS the rail between docks
///   via the grab handle.
enum RailDock { bottom, start, end }

/// The floating tool capsule (v1.9.1 Tool Rail).
///
/// A rounded-2xl capsule of `card/95` + backdrop blur + hairline border +
/// `inkShadow2`, 6px inner padding. Buttons are 44×44 rounded-xl tiles with
/// 20px Lucide icons; the ACTIVE tool is a solid primary tile; groups are
/// separated by a hairline. A drag handle at the capsule's top edge moves the
/// whole rail: release near the bottom → horizontal dock; near a side →
/// vertical dock on that side.
///
/// Layout: [pan · pen · highlighter · laser · eraser] | [lasso · text ·
/// shape · image · sticker] | [undo · redo · ruler · color]. The pen button
/// reflects the selected pen KIND (the four pens are grouped — tap the pen,
/// choose the kind in its settings panel).
class ToolRail extends StatefulWidget {
  const ToolRail({
    super.key,
    required this.tools,
    required this.engine,
    required this.ruler,
    required this.dock,
    this.hidden = false,
    this.onDockChange,
    this.onColorTap,
    this.onUndo,
    this.onRedo,
  });

  final ToolController tools;
  final StrokeEngine engine;
  final RulerState ruler;

  /// Current dock (drives the capsule orientation).
  final RailDock dock;

  final bool hidden;

  /// Fired when a drag ends on a new dock.
  final ValueChanged<RailDock>? onDockChange;

  final VoidCallback? onColorTap;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  static const Map<Tool, IconData> _toolIcons = {
    Tool.pan: LucideIcons.hand,
    Tool.pen: LucideIcons.pen_tool,
    Tool.highlighter: LucideIcons.highlighter,
    Tool.laser: LucideIcons.laser,
    Tool.eraser: LucideIcons.eraser,
    Tool.lasso: LucideIcons.lasso,
    Tool.text: LucideIcons.type,
    Tool.shape: LucideIcons.shapes,
    Tool.image: LucideIcons.image,
    Tool.sticker: LucideIcons.sticker,
  };

  /// The pen button reflects the selected pen KIND.
  static const Map<PenKind, IconData> _penKindIcons = {
    PenKind.fountain: LucideIcons.pen_tool,
    PenKind.ballpoint: LucideIcons.pen,
    PenKind.brush: LucideIcons.brush,
    PenKind.fineliner: LucideIcons.pen_line,
  };

  /// Frosted-glass blur for the capsule (card/95 + blur per spec).
  static final ui.ImageFilter _frosted =
      ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14);

    @override
  State<ToolRail> createState() => _ToolRailState();
}

class _ToolRailState extends State<ToolRail> {
  Offset _dragOffset = Offset.zero;
  bool _dragging = false;

  bool get _vertical => widget.dock != RailDock.bottom;

  @override
  Widget build(BuildContext context) {
    if (widget.hidden) return const SizedBox.shrink();
    return AnimatedScale(
      scale: _dragging ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Transform.translate(
        offset: _dragOffset,
        child: _capsule(context),
      ),
    );
  }

  /// The drag handle: a generous invisible grab area around the visual bar.
  /// DRAGGING IS HANDLE-ONLY — pen strokes started anywhere else (buttons,
  /// scroll body) never move the rail.
  Widget _handle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => setState(() => _dragging = true),
      onPanUpdate: (d) => setState(() => _dragOffset += d.delta),
      onPanEnd: (_) => _release(),
      onPanCancel: () => setState(() {
        _dragging = false;
        _dragOffset = Offset.zero;
      }),
      child: SizedBox(
        width: 64,
        height: 26,
        child: Center(
          child: Container(
            width: 40,
            height: 10,
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: scheme.outline),
            ),
          ),
        ),
      ),
    );
  }

  /// Snaps the capsule to the nearest dock on release: bottom third →
  /// [RailDock.bottom]; otherwise the side nearest the release point.
  void _release() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      // The state's render box sits ABOVE the drag Transform, so its global
      // rect is the DOCKED position — add the accumulated drag translation
      // (logical px == global px here) to get where the capsule really is.
      final railRect =
          (box.localToGlobal(Offset.zero) + _dragOffset) & box.size;
      final mq = MediaQuery.of(context);
      final screen = Offset.zero & mq.size;
      final center = railRect.center;
      RailDock next;
      if (center.dy > screen.height * 0.72) {
        next = RailDock.bottom;
      } else {
        next =
            center.dx < screen.width / 2 ? RailDock.start : RailDock.end;
      }
      setState(() {
        _dragging = false;
        _dragOffset = Offset.zero;
      });
      if (next != widget.dock) widget.onDockChange?.call(next);
    } else {
      setState(() {
        _dragging = false;
        _dragOffset = Offset.zero;
      });
    }
  }

  Widget _capsule(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = nanoteColors(context);
    final horizontal = !_vertical;

    return ClipRRect(
      borderRadius: BorderRadius.circular(NANOTE_RADIUS_LG),
      child: BackdropFilter(
        filter: ToolRail._frosted,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(NANOTE_RADIUS_LG),
            border: Border.all(color: scheme.outline),
            boxShadow: colors.inkShadow2,
          ),
          padding: const EdgeInsets.all(6),
          child: horizontal ? _horizontalBody(context) : _verticalBody(context),
        ),
      ),
    );
  }

  Widget _horizontalBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _handle(context),
        ListenableBuilder(
          listenable: Listenable.merge([widget.tools, widget.engine.historyChanged, widget.ruler]),
          builder: (context, _) => ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final t in _groupA) _toolButton(context, t),
                  _separator(context),
                  for (final t in _groupB) _toolButton(context, t),
                  _separator(context),
                  _undoRedoRuler(context),
                  _colorButton(context),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _verticalBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _handle(context),
        ListenableBuilder(
          listenable: Listenable.merge([widget.tools, widget.engine.historyChanged, widget.ruler]),
          builder: (context, _) => Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final t in _groupA) _toolButton(context, t),
                  _separator(context),
                  for (final t in _groupB) _toolButton(context, t),
                  _separator(context),
                  _undoRedoRuler(context),
                  _colorButton(context),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static const List<Tool> _groupA = [
    Tool.pan,
    Tool.pen,
    Tool.highlighter,
    Tool.laser,
    Tool.eraser,
  ];

  static const List<Tool> _groupB = [
    Tool.lasso,
    Tool.text,
    Tool.shape,
    Tool.image,
    Tool.sticker,
  ];

  Widget _separator(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: _vertical ? 44 : 1,
      height: _vertical ? 1 : 44,
      margin: EdgeInsets.symmetric(
        horizontal: _vertical ? 0 : 5,
        vertical: _vertical ? 5 : 0,
      ),
      color: scheme.outline,
    );
  }

  Widget _toolButton(BuildContext context, Tool t) {
    final active = widget.tools.tool == t;
    final icon = t == Tool.pen ? ToolRail._penKindIcons[widget.tools.penKind]! : ToolRail._toolIcons[t]!;
    return _RailButton(
      icon: icon,
      active: active,
      tooltip: t == Tool.pen
          ? '${S.t('tool.pen')} · ${S.t(widget.tools.penKind.key)}'
          : S.t(t.key),
      onTap: () => widget.tools.railTap(t),
    );
  }

  Widget _undoRedoRuler(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.engine.historyChanged,
      builder: (context, _) => _vertical
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RailButton(
                  icon: LucideIcons.undo,
                  tooltip: S.t('undo'),
                  onTap: widget.engine.canUndo ? (widget.onUndo ?? widget.engine.undo) : null,
                ),
                _RailButton(
                  icon: LucideIcons.redo,
                  tooltip: S.t('redo'),
                  onTap: widget.engine.canRedo ? (widget.onRedo ?? widget.engine.redo) : null,
                ),
                _RailButton(
                  icon: LucideIcons.ruler,
                  tooltip: S.t('ruler'),
                  active: widget.ruler.active,
                  onTap: widget.ruler.toggle,
                ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RailButton(
                  icon: LucideIcons.undo,
                  tooltip: S.t('undo'),
                  onTap: widget.engine.canUndo ? (widget.onUndo ?? widget.engine.undo) : null,
                ),
                _RailButton(
                  icon: LucideIcons.redo,
                  tooltip: S.t('redo'),
                  onTap: widget.engine.canRedo ? (widget.onRedo ?? widget.engine.redo) : null,
                ),
                _RailButton(
                  icon: LucideIcons.ruler,
                  tooltip: S.t('ruler'),
                  active: widget.ruler.active,
                  onTap: widget.ruler.toggle,
                ),
              ],
            ),
    );
  }

  /// Current color dot — tap → color popover.
  Widget _colorButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _RailButton(
      icon: null,
      tooltip: S.t('color'),
      onTap: widget.onColorTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color(_activeColor()),
          border: Border.all(color: scheme.outline, width: 2),
        ),
      ),
    );
  }

  /// The color swatch shows the color the ACTIVE tool would draw with.
  int _activeColor() {
    switch (widget.tools.tool) {
      case Tool.pen:
        return widget.tools.pen(widget.tools.penKind.strokeKind).color;
      case Tool.highlighter:
        return widget.tools.pen(StrokeKind.highlighter).color;
      case Tool.laser:
        return widget.tools.laser.color;
      case Tool.text:
        return widget.tools.textColor;
      case Tool.shape:
        return widget.tools.shapeStrokeColor;
      default:
        return widget.tools.pen(widget.tools.penKind.strokeKind).color;
    }
  }
}

/// A 44×44 rounded-xl rail tile: 20px Lucide icon (or [child]), solid
/// primary background + ink-1 shadow when active, plain (accent on press)
/// otherwise. Tooltips describe the action.
class _RailButton extends StatelessWidget {
  const _RailButton({
    this.icon,
    this.child,
    required this.tooltip,
    this.onTap,
    this.active = false,
  });

  final IconData? icon;
  final Widget? child;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  static const Duration _pressMs = Duration(milliseconds: 120);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = nanoteColors(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: _PressTile(
          onTap: onTap,
          child: AnimatedContainer(
            duration: _pressMs,
            curve: Curves.easeOut,
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: active ? scheme.primary : colors.surfaceVariant,
              borderRadius: BorderRadius.circular(NANOTE_RADIUS),
              boxShadow: active ? colors.inkShadow1 : null,
            ),
            child: child ??
            Icon(
              icon,
              size: 20,
              color: active ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Press feedback for a rail tile: accent wash + 0.96 scale, 120ms.
class _PressTile extends StatefulWidget {
  const _PressTile({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_PressTile> createState() => _PressTileState();
}

class _PressTileState extends State<_PressTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
