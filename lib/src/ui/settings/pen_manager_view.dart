import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../controllers/pen_bus.dart';
import '../../controllers/settings_controller.dart';
import '../../i18n/strings.dart';
import '../../models/settings.dart';
import '../../theme/nanote_theme.dart';

/// Electronic pen manager ('/pen'): connected-pen live telemetry, a test pad
/// (live trace colored by pressure + meters), and the button-shortcut editor
/// (4 buttons × 4 patterns → PenAction).
class PenManagerView extends StatefulWidget {
  const PenManagerView({super.key});

  @override
  State<PenManagerView> createState() => _PenManagerViewState();
}

class _PenManagerViewState extends State<PenManagerView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.t('penManager'))),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
        children: [
          _connectedPenCard(context),
          _testPadCard(context),
          ListenableBuilder(
            listenable: SettingsController.I,
            builder: (context, _) {
              final s = SettingsController.I.settings;
              return _card(
                context,
                icon: LucideIcons.sliders_horizontal,
                title: S.t('shortcuts'),
                children: [
                  const SizedBox(height: 6),
                  _switchRow(
                    context,
                    icon: LucideIcons.pen_line,
                    title: S.t('shortcutsMaster'),
                    subtitle: S.t('shortcuts'),
                    value: s.penShortcutsEnabled,
                    onChanged: (v) =>
                        SettingsController.I.setPenShortcutsEnabled(v),
                  ),
                  for (final button in PenButton.values)
                    _shortcutSection(context, s, button),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- section card

  Widget _card(
    BuildContext context, {
    IconData? icon,
    required String title,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(NANOTE_RADIUS_LG),
        border: Border.all(color: cs.outline),
        boxShadow: nc.inkShadow1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: nc.mutedFg),
                const SizedBox(width: 7),
              ],
              Text(
                title,
                style: nanoteText(TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: nc.mutedFg,
                )),
              ),
            ],
          ),
          ...children,
        ],
      ),
    );
  }

  // ---------------------------------------------------------- connected pen

  Widget _connectedPenCard(BuildContext context) {
    final nc = nanoteColors(context);
    return _card(
      context,
      icon: LucideIcons.activity,
      title: S.t('penConnected'),
      children: [
        const SizedBox(height: 6),
        ValueListenableBuilder<PenInfo?>(
          valueListenable: PenBus.I.notifier,
          builder: (context, pen, _) {
            if (pen == null) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(LucideIcons.pen, size: 15, color: nc.mutedFg),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        S.t('noPenDetected'),
                        style: nanoteText(TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: nc.mutedFg)),
                      ),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: [
                _infoRow(context, S.t('penKind'), pen.kind.name),
                _infoRow(context, S.t('pressure'),
                    '${S.num((pen.pressure * 100).round())}%'),
                _infoRow(
                    context,
                    S.t('tilt'),
                    '${S.num((pen.tilt * 180 / 3.141592653589793).toStringAsFixed(0))}° / '
                    '${S.num((pen.orientation * 180 / 3.141592653589793).toStringAsFixed(0))}°'),
                _infoRow(
                    context, S.t('buttons'), _penButtonsLabel(pen.buttons)),
                _infoRow(context, S.t('reportRate'),
                    '${S.num(pen.reportRateHz.round())} Hz'),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final nc = nanoteColors(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: nanoteText(
                    TextStyle(fontSize: 12.5, color: nc.mutedFg))),
          ),
          Text(value,
              style: nanoteText(const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- test pad

  Widget _testPadCard(BuildContext context) {
    final nc = nanoteColors(context);
    return _card(
      context,
      icon: LucideIcons.brush,
      title: S.t('testPad'),
      children: [
        const SizedBox(height: 4),
        Text(S.t('testPadHint'),
            style: nanoteText(
                TextStyle(fontSize: 11, height: 1.3, color: nc.mutedFg))),
        const SizedBox(height: 12),
        const _TestPad(),
      ],
    );
  }

  // ------------------------------------------------------------- shortcuts

  Widget _shortcutSection(
      BuildContext context, AppSettings s, PenButton button) {
    final nc = nanoteColors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 17, thickness: 1, indent: 4, endIndent: 4),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
          child: Text(
            S.t(button.key),
            style: nanoteText(TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: nc.mutedFg,
            )),
          ),
        ),
        for (final pattern in PenPattern.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    S.t(pattern.key),
                    style: nanoteText(const TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                _actionDropdown(context, s, button, pattern),
              ],
            ),
          ),
      ],
    );
  }

  Widget _actionDropdown(
      BuildContext context, AppSettings s, PenButton button, PenPattern pattern) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return Container(
      height: 40,
      alignment: AlignmentDirectional.centerStart,
      padding: const EdgeInsetsDirectional.only(start: 10, end: 6),
      decoration: BoxDecoration(
        color: nc.surfaceVariant,
        borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
        border: Border.all(color: cs.outline),
      ),
      child: DropdownButton<PenAction>(
        value: s.actionFor(button, pattern),
        isDense: true,
        underline: const SizedBox.shrink(),
        borderRadius: BorderRadius.circular(NANOTE_RADIUS),
        dropdownColor: cs.surface,
        icon: Icon(LucideIcons.chevron_down, size: 16, color: nc.mutedFg),
        padding: EdgeInsets.zero,
        style: nanoteText(
            TextStyle(fontSize: 13, color: cs.onSurface)),
        items: [
          for (final action in PenAction.values)
            DropdownMenuItem(
              value: action,
              child: SizedBox(
                width: 190,
                child: Text(
                  S.t(action.key),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
        onChanged: (action) {
          if (action != null) {
            SettingsController.I.setPenAction(button, pattern, action);
          }
        },
      ),
    );
  }

  Widget _switchRow(
    BuildContext context, {
    IconData? icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(NANOTE_RADIUS),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: nc.accent,
                  borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
                ),
                child: Icon(icon, size: 17, color: cs.primary),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: nanoteText(const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600))),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: nanoteText(TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: nc.mutedFg)),
                    ),
                  ],
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Test pad
// ---------------------------------------------------------------------------

class _PadPoint {
  const _PadPoint(this.pos, this.pressure);

  final Offset pos;
  final double pressure;
}

/// A drawing surface that captures pointer events, draws a live trace
/// (colored by pressure) and shows live pressure / tilt / button meters.
/// Stylus events are also published to [PenBus] so the connected-pen card
/// above stays live.
class _TestPad extends StatefulWidget {
  const _TestPad();

  @override
  State<_TestPad> createState() => _TestPadState();
}

class _TestPadState extends State<_TestPad> {
  final List<List<_PadPoint>> _strokes = [];
  PointerEvent? _last;
  bool _hover = false;

  bool _isPen(PointerEvent e) =>
      e.kind == PointerDeviceKind.stylus ||
      e.kind == PointerDeviceKind.invertedStylus;

  void _publish(PointerEvent e, {required bool hover}) {
    PenBus.I.publish(e, hover: hover);
  }

  void _onDown(PointerDownEvent e) {
    _publish(e, hover: false);
    if (_isPen(e)) _strokes.add([]);
    setState(() {
      _last = e;
      _hover = false;
    });
  }

  void _onMove(PointerMoveEvent e) {
    _publish(e, hover: false);
    if (_isPen(e)) {
      if (_strokes.isEmpty) _strokes.add([]);
      _strokes.last.add(_PadPoint(e.localPosition, e.pressure));
    }
    setState(() {
      _last = e;
      _hover = false;
    });
  }

  void _onUp(PointerUpEvent e) {
    _publish(e, hover: false);
    setState(() {
      _last = e;
      _hover = false;
    });
  }

  void _onCancel(PointerCancelEvent e) {
    _publish(e, hover: false);
    setState(() {
      _last = e;
      _hover = false;
    });
  }

  void _onHover(PointerHoverEvent e) {
    _publish(e, hover: true);
    if (_isPen(e)) {
      setState(() {
        _last = e;
        _hover = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    final last = _last;
    final double pressure =
        (last?.pressure ?? 0).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 220,
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(NANOTE_RADIUS),
            border: Border.all(color: cs.outline),
          ),
          child: Stack(
            children: [
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onDown,
                onPointerMove: _onMove,
                onPointerUp: _onUp,
                onPointerCancel: _onCancel,
                onPointerHover: _onHover,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _PadPainter(
                    strokes: [
                      for (final s in _strokes) List<_PadPoint>.of(s),
                    ],
                    baseColor: nc.mutedFg,
                    activeColor: cs.primary,
                  ),
                ),
              ),
              PositionedDirectional(
                top: 8,
                start: 8,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _hover ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: nc.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.crosshair,
                              size: 12, color: nc.accentFg),
                          const SizedBox(width: 4),
                          Text('hover',
                              style: nanoteText(TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: nc.accentFg,
                              ))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.t('pressure'),
                      style:
                          TextStyle(fontSize: 11, color: nc.mutedFg)),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: pressure,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 4),
                  Text('${S.num((pressure * 100).round())}%',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.t('tilt'),
                    style: TextStyle(fontSize: 11, color: nc.mutedFg)),
                const SizedBox(height: 6),
                Text(
                  '${S.num(((last?.orientation ?? 0) * 180 / 3.141592653589793).toStringAsFixed(0))}° / '
                  '${S.num(((last?.tilt ?? 0) * 180 / 3.141592653589793).toStringAsFixed(0))}°',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.t('buttons'),
                      style:
                          TextStyle(fontSize: 11, color: nc.mutedFg)),
                  const SizedBox(height: 6),
                  Text(
                    _penButtonsLabel(last?.buttons ?? 0),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                last == null ? '' : last.kind.name,
                style: TextStyle(fontSize: 11, color: nc.mutedFg),
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(_strokes.clear),
              icon: const Icon(LucideIcons.eraser, size: 16),
              label: Text(S.t('clearPad')),
            ),
          ],
        ),
      ],
    );
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter({
    required this.strokes,
    required this.baseColor,
    required this.activeColor,
  });

  final List<List<_PadPoint>> strokes;
  final Color baseColor;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      for (var i = 1; i < stroke.length; i++) {
        final a = stroke[i - 1];
        final b = stroke[i];
        final double p =
            ((a.pressure + b.pressure) / 2).clamp(0.0, 1.0).toDouble();
        paint.color = Color.lerp(baseColor, activeColor, p)!;
        paint.strokeWidth = 1.5 + p * 6;
        canvas.drawLine(a.pos, b.pos, paint);
      }
      if (stroke.length == 1) {
        final pt = stroke.first;
        final double p = pt.pressure.clamp(0.0, 1.0).toDouble();
        canvas.drawCircle(
          pt.pos,
          1.5 + p * 3,
          Paint()..color = Color.lerp(baseColor, activeColor, p)!,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PadPainter oldDelegate) => true;
}

/// Human-readable button bitmask (kPrimaryButton & friends).
String _penButtonsLabel(int buttons) {
  if (buttons == 0) return S.t('none');
  final names = <String>[];
  if (buttons & kPrimaryButton != 0) names.add('primary');
  if (buttons & kSecondaryButton != 0) names.add('barrel');
  if (buttons & kMiddleMouseButton != 0) names.add('middle');
  if (buttons & kBackMouseButton != 0) names.add('back');
  if (buttons & kForwardMouseButton != 0) names.add('forward');
  return names.isEmpty ? S.t('none') : names.join(', ');
}
