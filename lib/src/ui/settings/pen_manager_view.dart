import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

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
        padding: const EdgeInsets.all(12),
        children: [
          _connectedPenCard(context),
          const SizedBox(height: 12),
          _testPadCard(context),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: SettingsController.I,
            builder: (context, _) {
              final s = SettingsController.I.settings;
              return Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      value: s.penShortcutsEnabled,
                      onChanged: (v) =>
                          SettingsController.I.setPenShortcutsEnabled(v),
                      title: Text(S.t('shortcutsMaster')),
                      subtitle: Text(S.t('shortcuts')),
                    ),
                    for (final button in PenButton.values)
                      _shortcutCard(context, s, button),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- connected pen

  Widget _connectedPenCard(BuildContext context) {
    final nc = nanoteColors(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.t('penConnected'),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            ValueListenableBuilder<PenInfo?>(
              valueListenable: PenBus.I.notifier,
              builder: (context, pen, _) {
                if (pen == null) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      S.t('noPenDetected'),
                      style: TextStyle(fontSize: 13, color: nc.mutedFg),
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
                        '${((pen.tilt * 180 / 3.141592653589793)).toStringAsFixed(0)}° / '
                        '${((pen.orientation * 180 / 3.141592653589793)).toStringAsFixed(0)}°'),
                    _infoRow(
                        context, S.t('buttons'), _penButtonsLabel(pen.buttons)),
                    _infoRow(context, S.t('reportRate'),
                        '${S.num(pen.reportRateHz.round())} Hz'),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final nc = nanoteColors(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 13, color: nc.mutedFg)),
          ),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- test pad

  Widget _testPadCard(BuildContext context) {
    final nc = nanoteColors(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.t('testPad'),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(S.t('testPadHint'),
                style: TextStyle(fontSize: 11, color: nc.mutedFg)),
            const SizedBox(height: 12),
            const _TestPad(),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- shortcuts

  Widget _shortcutCard(BuildContext context, AppSettings s, PenButton button) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, indent: 16, endIndent: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Text(
            S.t(button.key),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        for (final pattern in PenPattern.values)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    S.t(pattern.key),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                DropdownButton<PenAction>(
                  value: s.actionFor(button, pattern),
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
                      SettingsController.I.setPenAction(
                          button, pattern, action);
                    }
                  },
                ),
              ],
            ),
          ),
      ],
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
              Positioned(
                top: 8,
                left: 8,
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
                          Icon(Icons.gps_fixed,
                              size: 12, color: nc.accentFg),
                          const SizedBox(width: 4),
                          Text('hover',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: nc.accentFg,
                              )),
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
                  '${(((last?.orientation ?? 0) * 180 / 3.141592653589793).toStringAsFixed(0))}° / '
                  '${(((last?.tilt ?? 0) * 180 / 3.141592653589793).toStringAsFixed(0))}°',
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
              icon: const Icon(Icons.delete_outline, size: 18),
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
