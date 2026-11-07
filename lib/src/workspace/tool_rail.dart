import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../controllers/audio_controller.dart';
import '../controllers/settings_controller.dart';
import '../controllers/stroke_engine.dart';
import '../controllers/tool_controller.dart';
import '../i18n/strings.dart';
import '../models/stroke.dart';
import '../models/tool.dart';
import '../theme/nanote_theme.dart';
import 'ruler_overlay.dart';

/// Where the FIXED tool rail is docked. The position comes from
/// Settings.railPosition ONLY (§0) — the rail is NEVER dragged.
///
/// * [RailDock.start] / [RailDock.end] — vertical capsule on the logical
///   start/end edge (flips with RTL).
/// * [RailDock.top] / [RailDock.bottom] — horizontal capsule.
enum RailDock { start, end, top, bottom }

extension RailDockX on RailDock {
  bool get isVertical => this == RailDock.start || this == RailDock.end;
}

/// Resolves the settings string ('start' | 'end' | 'top' | 'bottom') into a
/// dock. `leftHanded` mirrors the vertical side (start ↔ end).
RailDock resolveRailDock(String railPosition, bool leftHanded) {
  switch (railPosition) {
    case 'top':
      return RailDock.top;
    case 'bottom':
      return RailDock.bottom;
    case 'start':
      return leftHanded ? RailDock.end : RailDock.start;
    case 'end':
    default:
      return leftHanded ? RailDock.start : RailDock.end;
  }
}

/// The FIXED tool capsule (v1.9.1 Tool Rail, §0–§17).
///
/// A rounded-2xl capsule of `card/95` + backdrop blur + hairline border +
/// `inkShadow2`, 6px inner padding. Buttons are 44×44 rounded-xl tiles with
/// 20px Lucide icons; the ACTIVE tool is a solid primary tile; groups are
/// separated by a hairline.
///
/// §0 (fixed, not draggable):
///  * Position comes from Settings.railPosition ONLY — never dragged. The
///    rail rebuilds (ListenableBuilder on the tool bus) the moment the
///    active tool changes, so what you SEE is what you WRITE WITH.
///  * A collapse arrow at the rail's far end folds it completely; while
///    folded, a small floating pill handle on the same edge brings it back
///    (see DocumentWorkspace._railReturnHandle).
///
/// Tool order (§1, FIXED): pen · highlighter · laser · eraser · lasso |
/// text · text-select · shape · image · sticker | pan · finger · ruler ·
/// mic. The pen button reflects the selected pen KIND.
class ToolRail extends StatefulWidget {
  const ToolRail({
    super.key,
    required this.tools,
    required this.engine,
    required this.ruler,
    required this.dock,
    this.hidden = false,
    this.onCollapse,
    this.onToggleFinger,
    this.onMicTap,
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

  /// Fired when the collapse arrow folds the rail.
  final VoidCallback? onCollapse;

  /// §12 finger-writing toggle (tap or long-press the finger tile).
  final ValueChanged<bool>? onToggleFinger;

  /// Opens the audio panel (mic tile).
  final VoidCallback? onMicTap;

  final VoidCallback? onColorTap;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  static const Map<Tool, IconData> _toolIcons = {
    Tool.pen: LucideIcons.pen_tool,
    Tool.highlighter: LucideIcons.highlighter,
    Tool.laser: LucideIcons.laser,
    Tool.eraser: LucideIcons.eraser,
    Tool.lasso: LucideIcons.lasso,
    Tool.text: LucideIcons.type,
    Tool.textSelect: LucideIcons.text_cursor_input,
    Tool.shape: LucideIcons.shapes,
    Tool.image: LucideIcons.image,
    Tool.sticker: LucideIcons.sticker,
    Tool.pan: LucideIcons.hand,
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
  bool get _vertical => widget.dock.isVertical;

  @override
  Widget build(BuildContext context) {
    if (widget.hidden) return const SizedBox.shrink();
    return _capsule(context);
  }

  Widget _capsule(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = nanoteColors(context);

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
          child: _vertical ? _verticalBody(context) : _horizontalBody(context),
        ),
      ),
    );
  }

  Widget _horizontalBody(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.tools,
        widget.engine.historyChanged,
        widget.ruler,
        SettingsController.I,
      ]),
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
              for (final e in _groupC) _extraButton(context, e),
              _separator(context),
              _undoRedo(context),
              _colorButton(context),
              _collapseButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _verticalBody(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.tools,
        widget.engine.historyChanged,
        widget.ruler,
        SettingsController.I,
      ]),
      // GRAY-SCREEN FIX (v2.5.2): this capsule sits inside
      // Align > SafeArea > Container — there is NO Flex ancestor, so the
      // old `Flexible` wrapper threw
      // "type 'BoxParentData' is not a subtype of 'FlexParentData'"
      // on EVERY build in RELEASE mode (asserts hide it in debug), which
      // replaced most of the workspace with the gray release ErrorWidget.
      // Cap the scroll height to the viewport instead — long rails
      // scroll exactly like before, without needing a Flex parent.
      builder: (context, _) {
        final safe = MediaQuery.paddingOf(context);
        final maxH = MediaQuery.sizeOf(context).height -
            safe.vertical -
            140; // app bar + capsule padding + dock margins
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH < 120 ? 120 : maxH),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final t in _groupA) _toolButton(context, t),
                _separator(context),
                for (final t in _groupB) _toolButton(context, t),
                _separator(context),
                for (final e in _groupC) _extraButton(context, e),
                _separator(context),
                _undoRedo(context),
                _colorButton(context),
                _collapseButton(context),
              ],
            ),
          ),
        );
      },
    );
  }

  /// §1 fixed tool order — group A (drawing).
  static const List<Tool> _groupA = [
    Tool.pen,
    Tool.highlighter,
    Tool.laser,
    Tool.eraser,
    Tool.lasso,
  ];

  /// §1 fixed tool order — group B (content).
  static const List<Tool> _groupB = [
    Tool.text,
    Tool.textSelect,
    Tool.shape,
    Tool.image,
    Tool.sticker,
  ];

  /// §1 fixed tool order — group C (navigation / extras).
  static const List<_ExtraRail> _groupC = [
    _ExtraRail.pan,
    _ExtraRail.finger,
    _ExtraRail.ruler,
    _ExtraRail.mic,
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
    final icon = t == Tool.pen
        ? ToolRail._penKindIcons[widget.tools.penKind]!
        : ToolRail._toolIcons[t]!;
    return _RailButton(
      icon: icon,
      active: active,
      tooltip: t == Tool.pen
          ? '${S.t('tool.pen')} · ${S.t(widget.tools.penKind.key)}'
          : S.t(t.key),
      onTap: () => widget.tools.railTap(t),
    );
  }

  Widget _extraButton(BuildContext context, _ExtraRail extra) {
    switch (extra) {
      case _ExtraRail.pan:
        return _RailButton(
          icon: ToolRail._toolIcons[Tool.pan],
          active: widget.tools.tool == Tool.pan,
          tooltip: S.t('tool.pan'),
          onTap: () => widget.tools.railTap(Tool.pan),
        );
      case _ExtraRail.finger:
        final on = SettingsController.I.settings.drawWithFinger;
        return _RailButton(
          icon: LucideIcons.pointer,
          active: on,
          tooltip: S.t(on ? 'fingerWriteOn' : 'fingerWriteOff'),
          onTap: () => widget.onToggleFinger?.call(!on),
          onLongPress: () => widget.onToggleFinger?.call(!on),
        );
      case _ExtraRail.ruler:
        return _RailButton(
          icon: LucideIcons.ruler,
          active: widget.ruler.active,
          tooltip: S.t('ruler'),
          onTap: widget.ruler.toggle,
        );
      case _ExtraRail.mic:
        // BUGFIX (port): the rail bodies listen to tools / history / ruler /
        // settings — but NOT to AudioController, so the mic tile's
        // "recording" highlight went stale the moment a session started or
        // stopped inside the audio panel. Rebuild just this tile from the
        // controller instead of the whole rail (it also notifies at the
        // 100ms level-polling rate while recording).
        return AnimatedBuilder(
          animation: AudioController.I,
          builder: (context, _) => _RailButton(
            icon: LucideIcons.mic,
            active: AudioController.I.isRecording,
            tooltip: S.t('audio'),
            onTap: widget.onMicTap,
          ),
        );
    }
  }

  Widget _undoRedo(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.engine.historyChanged,
      builder: (context, _) => _vertical
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RailButton(
                  icon: LucideIcons.undo,
                  tooltip: S.t('undo'),
                  onTap: widget.engine.canUndo
                      ? (widget.onUndo ?? widget.engine.undo)
                      : null,
                ),
                _RailButton(
                  icon: LucideIcons.redo,
                  tooltip: S.t('redo'),
                  onTap: widget.engine.canRedo
                      ? (widget.onRedo ?? widget.engine.redo)
                      : null,
                ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RailButton(
                  icon: LucideIcons.undo,
                  tooltip: S.t('undo'),
                  onTap: widget.engine.canUndo
                      ? (widget.onUndo ?? widget.engine.undo)
                      : null,
                ),
                _RailButton(
                  icon: LucideIcons.redo,
                  tooltip: S.t('redo'),
                  onTap: widget.engine.canRedo
                      ? (widget.onRedo ?? widget.engine.redo)
                      : null,
                ),
              ],
            ),
    );
  }

  /// §0: the collapse arrow at the rail's far end folds it completely.
  Widget _collapseButton(BuildContext context) {
    return _RailButton(
      icon: _vertical ? LucideIcons.chevron_right : LucideIcons.chevron_down,
      tooltip: S.t('hideToolbar'),
      onTap: widget.onCollapse,
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

/// The non-Tool rail tiles (§1 group C).
enum _ExtraRail { pan, finger, ruler, mic }

/// A 44×44 rounded-xl rail tile: 20px Lucide icon (or [child]), solid
/// primary background + ink-1 shadow when active, plain (accent on press)
/// otherwise. Tooltips describe the action.
class _RailButton extends StatelessWidget {
  const _RailButton({
    this.icon,
    this.child,
    required this.tooltip,
    this.onTap,
    this.onLongPress,
    this.active = false,
  });

  final IconData? icon;
  final Widget? child;
  final String tooltip;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
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
          onLongPress: onLongPress,
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
  const _PressTile({
    required this.onTap,
    required this.child,
    this.onLongPress,
  });

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  @override
  State<_PressTile> createState() => _PressTileState();
}

class _PressTileState extends State<_PressTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
