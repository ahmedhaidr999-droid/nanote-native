import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// Live electronic-pen telemetry, fed by the gesture router (and the pen
/// manager's test pad). The pen manager screen listens to [notifier].
class PenInfo {
  const PenInfo({
    required this.kind,
    required this.pressure,
    required this.tilt,
    required this.orientation,
    required this.buttons,
    required this.hover,
    required this.lastSeen,
    required this.reportRateHz,
  });

  final PointerDeviceKind kind;
  final double pressure;

  /// Tilt away from the surface normal, radians (0 = vertical pen).
  final double tilt;

  /// Direction of the projected stylus axis, radians (-π..π).
  final double orientation;
  final int buttons;
  final bool hover;
  final DateTime lastSeen;
  final double reportRateHz;
}

/// Aggregated knowledge about the connected pen (which button bits it
/// actually reports, mean report rate…).
class PenStats {
  final Set<int> seenButtonBits = {};
  final List<double> intervalsMs = [];
  double lastEventMs = 0;
  int eventCount = 0;

  void record(PointerEvent e) {
    eventCount++;
    seenButtonBits.add(e.buttons);
    final now = e.timeStamp.inMicroseconds / 1000.0;
    if (lastEventMs > 0) {
      final dt = now - lastEventMs;
      if (dt > 0.5 && dt < 500) {
        intervalsMs.add(dt);
        if (intervalsMs.length > 60) intervalsMs.removeAt(0);
      }
    }
    lastEventMs = now;
  }

  double get reportRateHz {
    if (intervalsMs.isEmpty) return 0;
    final mean = intervalsMs.reduce((a, b) => a + b) / intervalsMs.length;
    if (mean <= 0) return 0;
    return 1000.0 / mean;
  }
}

class PenBus {
  PenBus._();

  static final PenBus I = PenBus._();

  /// Latest stylus event info (null until a stylus/stylus-pen is seen).
  final ValueNotifier<PenInfo?> notifier = ValueNotifier<PenInfo?>(null);

  final PenStats stats = PenStats();

  void publish(PointerEvent e, {required bool hover}) {
    final kind = e.kind;
    final isPen = kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
    if (!isPen) return;
    stats.record(e);
    notifier.value = PenInfo(
      kind: kind,
      pressure: e.pressure,
      tilt: e.tilt,
      orientation: e.orientation,
      buttons: e.buttons,
      hover: hover,
      lastSeen: DateTime.now(),
      reportRateHz: stats.reportRateHz,
    );
  }
}
