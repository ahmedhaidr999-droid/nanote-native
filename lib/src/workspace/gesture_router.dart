import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/page_elements.dart';
import '../models/paper.dart';
import '../models/settings.dart';
import '../models/tool.dart';
import 'pdf_text_layer.dart';
import '../workspace/doc_geometry.dart';
import '../workspace/ruler_overlay.dart';
import '../controllers/audio_controller.dart';
import '../controllers/pdf_document_controller.dart';
import '../controllers/pen_bus.dart';
import '../controllers/settings_controller.dart';
import '../controllers/shape_recognizer.dart';
import '../controllers/stroke_engine.dart';
import '../controllers/tool_controller.dart';
import '../controllers/viewport_controller.dart';

/// Raw-Listener input routing. NO GestureDetector / GestureArena.
///
/// v2.0.1 CRITICAL FIX: every spatial computation uses the pointer's
/// LOCAL position relative to the canvas Listener — `e.localPosition`.
/// (Previously `e.position` — GLOBAL window coordinates — was mixed with the
/// canvas-local viewport transform, offsetting all ink, taps, lassos, the
/// pinch focal and the eraser cursor by the app-bar height and rail width,
/// i.e. ink appeared ~56px away from the pen.)
///
/// Routing rules (v1.9.1 solved patterns):
///  * stylus → always draws (or erases in eraser mode)
///  * invertedStylus OR buttons bit 32 (kPrimaryEraserButton) → eraser
///  * barrel button (kSecondaryStylusButton):
///      - press while hovering → action (e.g. temporary eraser until release)
///      - press while writing → pressWriting action
///      - double press <350ms → double action
///      - held ≥650ms → long action
///  * finger: draws only when "draw with finger" is enabled (default OFF);
///    1 finger = pan (with inertial fling on release); 2 fingers = pinch
///    zoom + pan (focal preserved)
///  * palm rejection: ANY touch while a stylus stroke is active is ignored
///  * 2nd pointer during finger-draw → cancel stroke, convert to pinch
///  * finger double-tap → configurable (default zoom toggle 1x/2x at point)
///  * two-finger quick tap (<400ms, <26px move, no pinch) → configurable
///    (default undo)
///  * wheel/trackpad: zoom + pan
class GestureRouter {
  GestureRouter({
    required this.viewport,
    required this.engine,
    required this.tools,
    required this.settings,
    required this.audio,
    required this.geometry,
    required this.textSel,
    this.ruler,
    this.onToggleToolbar,
    this.onQuickExport,
    this.onTextTap,
    this.onTextSelectTap,
    this.onPickImage,
    this.onPickSticker,
    this.onPageChanged,
  }) {
    tools.addListener(_onToolsChanged);
  }

  final ViewportController viewport;
  final StrokeEngine engine;
  final ToolController tools;
  final SettingsController settings;
  final AudioController audio;
  final DocGeometry geometry;
  final RulerState? ruler;

  /// PDF text selection state (long-press → select → action bar).
  final PdfTextSelectionController textSel;

  final VoidCallback? onToggleToolbar;
  final VoidCallback? onQuickExport;
  final void Function(int pageId, Offset pagePoint)? onTextTap;

  /// §7 text-select tool: tap a TextEl on a PDF/text page → the workspace
  /// opens the translation popup for it.
  final void Function(int pageId, Offset pagePoint)? onTextSelectTap;
  final void Function(int pageId, Offset pagePoint)? onPickImage;
  final void Function(int pageId, Offset pagePoint)? onPickSticker;
  final ValueChanged<int>? onPageChanged;

  /// Screen size of the workspace (set by the workspace each frame).
  Size screenSize = Size.zero;

  /// Live eraser preview: while the eraser tool (or hover-erase) is active,
  /// a circle follows the hovering pen / mouse. Cleared when the tool changes.
  bool _hoverCursorShown = false;

  /// Pan velocity samples for the release fling (recent last).
  final List<_VelSample> _velSamples = [];

  /// True while a pan gesture with real movement is active.
  int _panMoveCount = 0;

  /// Total pan travel (screen px) — a pan that stayed under ~18px is a TAP.
  double _panDistance = 0;

  void dispose() {
    _barrelLongTimer?.cancel();
    _cancelTextHold();
    tools.removeListener(_onToolsChanged);
    cropSession.value?.dispose();
    cropSession.dispose();
    shapePreview.dispose();
  }

  void _onToolsChanged() {
    // Leaving the eraser (or hover-erase) removes the preview circle.
    if (!_isEraserTool && !_hoverEraseActive && _erase == null) {
      if (_hoverCursorShown) {
        _hoverCursorShown = false;
        engine.eraserCursor.value = null;
      }
    }
  }

  // ------------------------------------------------------------- pointers

  final Map<int, _Ptr> _pointers = {};

  _Draw? _draw;
  _Erase? _erase;
  _Lasso? _lasso;
  _SelGesture? _selGesture;
  _Pinch? _pinch;
  _ShapeDrag? _shapeDrag;
  int _panPointer = -1;

  // Crop-session drag state (§5).
  int _cropPointer = -1;
  CropCorner? _cropCorner;
  Offset? _cropLastLocal;

  /// Live shape-drag preview (§8) — the workspace paints this overlay.
  final ValueNotifier<ShapeDragPreview?> shapePreview =
      ValueNotifier<ShapeDragPreview?>(null);

  /// Active image-crop session (§5) — non-null while the crop editor is
  /// open; the workspace overlay paints from it and it swallows all
  /// pointer input while active (modal).
  final ValueNotifier<CropSession?> cropSession = ValueNotifier<CropSession?>(
    null,
  );

  DateTime? _lastTapUp;
  Offset _lastTapScreen = Offset.zero;
  DateTime? _twoFingerDownAt;

  // Barrel state.
  int _hoverButtons = 0;
  DateTime? _barrelDownAt;
  Timer? _barrelLongTimer;
  DateTime? _lastBarrelPress;
  bool _barrelLongFired = false;
  bool _hoverEraseActive = false;

  // Shape-hold (draw & hold recognition).
  DateTime? _holdSince;

  bool get _stylusDrawActive =>
      (_draw != null && _draw!.stylus) ||
      (_shapeDrag != null && _shapeDrag!.stylus);

  // ------------------------------------------------------------- helpers

  Offset _toDoc(Offset screen) => viewport.toDoc(screen);

  int? _pageIdAtDoc(Offset doc) {
    final page = geometry.pageAt(doc);
    return page?.id;
  }

  Offset _toPage(Offset doc, int pageId) => geometry.toPage(doc, pageId);

  Tool get _tool => tools.tool;

  bool get _isEraserTool => _tool == Tool.eraser;

  bool _wantsInk(Tool t) => t.producesInk;

  // ------------------------------------------------------------- Listener

  void onPointerDown(PointerDownEvent e) {
    PenBus.I.publish(e, hover: false);
    final kind = e.kind;

    // Modal crop session: every pointer only manipulates (or ignores) the
    // crop window while the editor is open.
    if (_handleCropDown(e)) return;

    // Any new pointer stops an in-flight inertial scroll.
    if (viewport.isFlinging) viewport.stopFling();

    // Palm rejection: any touch while a stylus stroke is active.
    if (_stylusDrawActive && kind == PointerDeviceKind.touch) {
      _pointers[e.pointer] = _Ptr(e.pointer, kind, rejected: true);
      return;
    }

    // Inverted stylus / eraser-end button bit.
    final isEraserKind = kind == PointerDeviceKind.invertedStylus ||
        (e.buttons & kEraserButtonBit) != 0;

    if (kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus) {
      _pointers[e.pointer] = _Ptr(e.pointer, kind);
      // Barrel press combined with down while writing?
      if ((e.buttons & kSecondaryStylusButton) != 0) {
        _barrelPressed(pattern: engine.liveStroke.value != null ? PenPattern.pressWriting : PenPattern.press);
      }
      // SELECTION-CONTROL FIX: handles are grabbable by ANY tool — the pen
      // previously never hit-tested the selection, so inserted images could
      // not be resized/rotated with the stylus at all.
      if (_tryBeginTextSelectionControl(e)) {
        // PDF text-selection handle / body grab begun.
      } else if (_tryBeginSelectionControl(e)) {
        // selection grab begun.
      } else if (isEraserKind || _hoverEraseActive || _isEraserTool) {
        _beginErase(e, stylus: true);
      } else if (_wantsInk(_tool)) {
        _beginDraw(e, stylus: true);
      } else if (_tool == Tool.lasso) {
        _beginLasso(e);
      } else if (_tool == Tool.shape) {
        // §8: the shape tool DRAGS a shape out (it previously fell through
        // to pan — the tool was completely dead).
        _beginShapeDrag(e, stylus: true);
      } else if (_tool == Tool.pan) {
        _beginPan(e);
      } else if (_tool == Tool.text) {
        _deferredTap = _DeferredTap(e.localPosition, e.pointer);
      } else if (_tool == Tool.textSelect) {
        _deferredTap = _DeferredTap(e.localPosition, e.pointer);
      } else if (_tool == Tool.image) {
        _deferredTap = _DeferredTap(e.localPosition, e.pointer);
      } else if (_tool == Tool.sticker) {
        _deferredTap = _DeferredTap(e.localPosition, e.pointer);
      } else {
        _beginPan(e);
      }
      // Long-press → PDF text selection (any non-eraser tool; the live
      // stroke is cancelled when it fires, so nothing unwanted is drawn).
      if (!(isEraserKind || _hoverEraseActive || _isEraserTool)) {
        _maybeStartTextHold(e);
      }
      return;
    }

    if (kind == PointerDeviceKind.touch) {
      // Second finger during finger-draw → cancel stroke, convert to pinch.
      if (_draw != null && !_draw!.stylus) {
        final keep = _draw!;
        _cancelDraw();
        _pointers[e.pointer] = _Ptr(e.pointer, kind);
        _startPinchFromDraw(keep, e);
        return;
      }
      if (_erase != null && !_erase!.stylus) {
        _endErase();
      }

      final activeTouches =
          _pointers.values.where((p) => p.kind == PointerDeviceKind.touch && !p.rejected).length;
      _pointers[e.pointer] = _Ptr(e.pointer, kind);

      if (activeTouches == 0) {
        // First finger.
        //
        // SELECTION-CONTROL FIX: handles (and the selection body with the
        // non-drawing tools) are grabbable by the finger too.
        if (!_tryBeginTextSelectionControl(e)) {
          if (!_tryBeginSelectionControl(e)) {
            if (_isEraserTool) {
              // §12 (user report): the eraser obeys the SAME finger rule as
              // the pens — a finger erases ONLY while “draw with finger” is
              // enabled; otherwise the finger pans, exactly like the pens.
              if (settings.settings.drawWithFinger) {
                _beginErase(e, stylus: false);
              } else {
                _beginPan(e);
              }
            } else if (_wantsInk(_tool) && settings.settings.drawWithFinger) {
              _beginDraw(e, stylus: false);
            } else if (_tool == Tool.shape) {
              // §8 shape drag: same finger rule as the pens.
              if (settings.settings.drawWithFinger) {
                _beginShapeDrag(e, stylus: false);
              } else {
                _beginPan(e);
              }
            } else if (_tool == Tool.lasso) {
              _beginLasso(e);
            } else if (ruler != null &&
                ruler!.active &&
                _hitRuler(_toDoc(e.localPosition))) {
              _beginRulerDrag(e);
            } else if (_tool == Tool.text ||
                _tool == Tool.textSelect ||
                _tool == Tool.image ||
                _tool == Tool.sticker) {
              // Tap-tools work with a FINGER too (devices without a stylus):
              // a quick tap fires the tool; a drag beyond 18px becomes a pan
              // (see the deferred-tap guard in onPointerMove).
              _deferredTap = _DeferredTap(e.localPosition, e.pointer);
            } else {
              _beginPan(e);
            }
          }
        }
        // Long-press → PDF text selection (works with touch, no stylus
        // needed — the pan/draw this finger started is cancelled when it
        // fires, so nothing unwanted happens).
        _maybeStartTextHold(e);
      } else if (activeTouches == 1) {
        // Second finger → pinch (focal stays under fingers); it also
        // cancels any pending text-selection hold.
        _cancelTextHold();
        final first = _pointers.values
            .firstWhere((p) => p.kind == PointerDeviceKind.touch && !p.rejected && p.pointer != e.pointer);
        if (_panPointer == first.pointer) _panPointer = -1;
        _velSamples.clear();
        _cancelLasso();
        _cancelSelGesture();
        _startPinch(first.lastPos, e.localPosition, first.pointer, e.pointer);
        _twoFingerDownAt ??= DateTime.now();
      }
      return;
    }

    if (kind == PointerDeviceKind.mouse) {
      _pointers[e.pointer] = _Ptr(e.pointer, kind);
      final secondary = (e.buttons & kSecondaryMouseButton) != 0;
      if (secondary) {
        _beginPan(e);
      } else if (_tryBeginTextSelectionControl(e)) {
        // PDF text-selection handle / body grab begun.
      } else if (_tryBeginSelectionControl(e)) {
        // selection grab begun.
      } else if (_wantsInk(_tool) || _isEraserTool) {
        if (_isEraserTool) {
          _beginErase(e, stylus: false);
        } else {
          _beginDraw(e, stylus: false, mouse: true);
        }
      } else if (_tool == Tool.lasso) {
        _beginLasso(e);
      } else if (_tool == Tool.shape) {
        _beginShapeDrag(e, stylus: true);
      } else {
        _beginPan(e);
      }
      _maybeStartTextHold(e);
    }
  }

  void onPointerMove(PointerMoveEvent e) {
    final p = _pointers[e.pointer];
    if (p == null) return;
    if (p.rejected) return;
    p.lastPos = e.localPosition;
    PenBus.I.publish(e, hover: false);

    // A pending text-selection hold dies as soon as the pointer really
    // moves (it must stay a press-and-hold).
    if (_textHoldPointer == e.pointer &&
        (_textHoldTimer != null || _pendingTextPick != null) &&
        (e.localPosition - _textHoldScreen).distance > 18) {
      _cancelTextHold();
    }

    // Modal crop session swallows pointer moves.
    if (_handleCropMove(e)) return;

    if (_textSelDrag != null && _textSelDrag!.pointer == e.pointer) {
      _extendTextSelDrag(e.localPosition);
      return;
    }
    if (_shapeDrag != null && _shapeDrag!.pointer == e.pointer) {
      _extendShapeDrag(e);
      return;
    }
    if (_draw != null && _draw!.pointer == e.pointer) {
      _extendDraw(e);
      return;
    }
    if (_erase != null && _erase!.pointer == e.pointer) {
      _extendErase(e);
      return;
    }
    if (_lasso != null && _lasso!.pointer == e.pointer) {
      _extendLasso(e);
      return;
    }
    if (_selGesture != null && _selGesture!.pointer == e.pointer) {
      _extendSelGesture(e);
      return;
    }
    if (_rulerDrag != null && _rulerDrag!.pointer == e.pointer) {
      ruler!.moveTo(_toDoc(e.localPosition));
      return;
    }
    if (_pinch != null && (e.pointer == _pinch!.a || e.pointer == _pinch!.b)) {
      _extendPinch(e);
      return;
    }
    if (_panPointer == e.pointer) {
      viewport.panBy(e.delta);
      _trackPanVelocity(e);
      return;
    }
    if (_deferredTap != null && _deferredTap!.pointer == e.pointer) {
      // Moved too far → it's a drag, not a tap.
      if ((e.localPosition - _deferredTap!.screen).distance > 18) {
        _deferredTap = null;
        _beginPan(e);
      }
    }
  }

  void onPointerUp(PointerUpEvent e) {
    PenBus.I.publish(e, hover: false);

    // Modal crop session swallows pointer ups.
    if (_endCrop(e.pointer)) return;

    _cancelTextHold();

    final p = _pointers.remove(e.pointer);

    if (_textSelDrag != null && _textSelDrag!.pointer == e.pointer) {
      final d = _textSelDrag!;
      _textSelDrag = null;
      // A tap INSIDE the selection toggles the action bar back on.
      if (d.insideTap && textSel.hasSelection) {
        textSel.toggleMenu();
      }
      // Early return: never feed a text-selection release to the tap
      // detectors (no accidental double-tap zoom after selecting).
      return;
    }

    if (_shapeDrag != null && _shapeDrag!.pointer == e.pointer) {
      _endShapeDrag();
      return;
    }
    if (_draw != null && _draw!.pointer == e.pointer) {
      _endDraw();
      return;
    }
    if (_erase != null && _erase!.pointer == e.pointer) {
      _endErase();
      return;
    }
    if (_lasso != null && _lasso!.pointer == e.pointer) {
      _endLasso();
      return;
    }
    if (_selGesture != null && _selGesture!.pointer == e.pointer) {
      _endSelGesture();
      return;
    }
    if (_rulerDrag != null && _rulerDrag!.pointer == e.pointer) {
      _rulerDrag = null;
      return;
    }
    if (_pinch != null && (e.pointer == _pinch!.a || e.pointer == _pinch!.b)) {
      _endPinch(e.pointer);
      return;
    }
    if (_panPointer == e.pointer) {
      // A pan that never really moved is a TAP — feed the double-tap
      // detector (previously the early return made finger double-tap zoom
      // unreachable) and dismiss a lingering text selection.
      final wasTap = _endPan(e, p);
      if (wasTap && textSel.hasSelection) {
        textSel.clear();
      }
      if (wasTap && p != null && p.kind == PointerDeviceKind.touch) {
        _handleTapSequences(e.localPosition);
      }
      return;
    }
    if (_deferredTap != null && _deferredTap!.pointer == e.pointer) {
      _fireDeferredTap(e.localPosition);
      _deferredTap = null;
      return;
    }

    // Finger double-tap detection (single finger, never rejected palms).
    if (p != null && !p.rejected && p.kind == PointerDeviceKind.touch) {
      _handleTapSequences(e.localPosition);
    }
  }

  void onPointerCancel(PointerCancelEvent e) {
    if (_endCrop(e.pointer)) return;
    _cancelTextHold();
    if (_textSelDrag != null && _textSelDrag!.pointer == e.pointer) {
      _textSelDrag = null;
    }
    _pointers.remove(e.pointer);
    if (_draw != null && _draw!.pointer == e.pointer) _cancelDraw();
    if (_erase != null && _erase!.pointer == e.pointer) _endErase();
    if (_lasso != null && _lasso!.pointer == e.pointer) _cancelLasso();
    if (_selGesture != null && _selGesture!.pointer == e.pointer) _cancelSelGesture();
    if (_shapeDrag != null && _shapeDrag!.pointer == e.pointer) {
      _cancelShapeDrag();
    }
    if (_pinch != null && (e.pointer == _pinch!.a || e.pointer == _pinch!.b)) {
      _endPinch(e.pointer);
    }
    if (_panPointer == e.pointer) {
      _panPointer = -1;
      _velSamples.clear();
    }
    _deferredTap = null;
  }

  void onPointerHover(PointerHoverEvent e) {
    PenBus.I.publish(e, hover: true);

    // Live eraser preview: circle follows the hovering pen / mouse whenever
    // the eraser tool (or hover-erase) is active.
    //
    // CURSOR RADIUS = the SCREEN-space erase radius (tools.eraserRadius —
    // constant on screen at any zoom, mirroring _applyErase). Previously
    // this was `eraserRadius * scale`, which at high zoom drew a HUGE faint
    // circle that looked like a gray film covering the whole page.
    if (_isEraserTool || _hoverEraseActive) {
      _hoverCursorShown = true;
      engine.eraserCursor.value = EraserCursor(
        screenPos: e.localPosition,
        radius: tools.eraserRadius,
      );
    }

    if (e.kind != PointerDeviceKind.stylus &&
        e.kind != PointerDeviceKind.invertedStylus) {
      return;
    }

    final prev = _hoverButtons;
    _hoverButtons = e.buttons;

    final barrelNow = (e.buttons & kSecondaryStylusButton) != 0;
    final barrelWas = (prev & kSecondaryStylusButton) != 0;

    if (barrelNow && !barrelWas) {
      // Barrel press while hovering.
      _barrelDownAt = DateTime.now();
      _barrelLongFired = false;
      final now = DateTime.now();
      if (_lastBarrelPress != null &&
          now.difference(_lastBarrelPress!).inMilliseconds < 350) {
        _fireAction(PenButton.barrel, PenPattern.double);
        _lastBarrelPress = null;
        _barrelDownAt = null;
      } else {
        _lastBarrelPress = now;
      }
      _barrelLongTimer?.cancel();
      _barrelLongTimer = Timer(const Duration(milliseconds: 650), () {
        if (_barrelDownAt != null && !_barrelLongFired) {
          _barrelLongFired = true;
          _fireAction(PenButton.barrel, PenPattern.long);
        }
      });
      // "press" pattern fires immediately (e.g. temporary eraser).
      _fireAction(PenButton.barrel, PenPattern.press);
    } else if (!barrelNow && barrelWas) {
      _barrelLongTimer?.cancel();
      _barrelDownAt = null;
    }

    // Track hover-erase (eraserHold) state.
    final holdErase = settings.settings.actionFor(PenButton.barrel, PenPattern.press) == PenAction.eraserHold;
    _hoverEraseActive = barrelNow && holdErase && settings.settings.penShortcutsEnabled;
  }

  void onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      if (e.scrollDelta.dy.abs() > 0.5) {
        viewport.zoomBy(math.pow(2, -e.scrollDelta.dy / 400).toDouble(), e.localPosition);
      }
    }
  }

  // Trackpad two-finger pan + pinch (Listener.onPointerPanZoom*).
  double _lastTrackpadScale = 1.0;

  void onPointerPanZoomStart(PointerPanZoomStartEvent e) {
    _lastTrackpadScale = 1.0;
  }

  void onPointerPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    viewport.panBy(e.pan);
    if ((e.scale - _lastTrackpadScale).abs() > 0.001) {
      viewport.zoomBy(e.scale / _lastTrackpadScale, e.localPosition);
      _lastTrackpadScale = e.scale;
    }
  }

  void onPointerPanZoomEnd(PointerPanZoomEndEvent e) {
    _lastTrackpadScale = 1.0;
    viewport.endInteraction();
  }

  // ------------------------------------------------------------- draw

  void _beginDraw(PointerDownEvent e, {required bool stylus, bool mouse = false}) {
    // Drawing over the canvas dismisses a PDF text selection (its handles
    // and action bar make room for the new ink).
    if (textSel.hasSelection) textSel.clear();
    // Laser never commits to the document.
    if (_tool == Tool.laser) {
      final doc = _toDoc(e.localPosition);
      final pageId = _pageIdAtDoc(doc);
      if (pageId == null) return;
      _draw = _Draw(e.pointer, stylus,
          laser: true, pageId: pageId, lastDoc: doc)
        ..lastScreen = e.localPosition
        ..lastMoveScreen = e.localPosition;
      tools.laser.beginStroke(pageId);
      tools.laser.addPoint(geometry.toPage(doc, pageId));
      return;
    }
    final doc = _toDoc(e.localPosition);
    final pageId = _pageIdAtDoc(doc);
    if (pageId == null) return;
    engine.ensureLoaded(pageId);
    final pagePoint = _toPage(doc, pageId);
    final style = tools.currentStrokeStyle();
    engine.beginStroke(pageId, style);
    _draw = _Draw(e.pointer, stylus,
        pageId: pageId, lastDoc: doc, mouse: mouse)
      ..lastScreen = e.localPosition
      ..lastMoveScreen = e.localPosition;
    final pressure = mouse ? 0.5 : e.pressure;
    final realPressure = stylus && !mouse;
    if (ruler != null && ruler!.active) {
      // Ruler lives in DOC space; ink is extended in PAGE space.
      final snappedDoc = ruler!.snap(doc);
      final snappedPage =
          snappedDoc == null ? null : geometry.toPage(snappedDoc, pageId);
      engine.extendStroke(snappedPage ?? pagePoint, pressure,
          realPressure: realPressure);
    } else {
      engine.extendStroke(pagePoint, pressure, realPressure: realPressure);
    }
    _startHoldTimer();
  }

  void _extendDraw(PointerMoveEvent e) {
    final d = _draw!;
    final doc = _toDoc(e.localPosition);
    // Laser: page was fixed at gesture start.
    if (d.laser) {
      tools.laser.addPoint(geometry.toPage(doc, d.pageId!));
      d.lastDoc = doc;
      return;
    }
    // Keep drawing on the page where the stroke started (ink slots!).
    final pageId = d.pageId ?? _pageIdAtDoc(doc);
    if (pageId == null) return;
    if (d.pageId == null) {
      d.pageId = pageId;
      engine.beginStroke(pageId, tools.currentStrokeStyle());
    }
    final pagePoint = _toPage(doc, pageId);
    final pressure = d.mouse ? 0.5 : e.pressure;
    final realPressure = d.stylus && !d.mouse;

    if (ruler != null && ruler!.active) {
      // Ruler lives in DOC space; ink is extended in PAGE space.
      final snappedDoc = ruler!.snap(doc);
      final snappedPage =
          snappedDoc == null ? null : geometry.toPage(snappedDoc, pageId);
      if (snappedPage != null) {
        engine.extendStroke(snappedPage, pressure, realPressure: realPressure);
        d.snappedLast = true;
        d.lastDoc = doc;
        _cancelHoldTimer();
        return;
      }
      d.snappedLast = false;
    }

    engine.extendStroke(pagePoint, pressure, realPressure: realPressure);
    d.lastDoc = doc;
    d.lastScreen = e.localPosition;

    // Draw & hold recognition.
    if (d.stylus &&
        settings.settings.shapeDetection &&
        tools.tool.isDrawingPen &&
        tools.tool != Tool.highlighter) {
      final dist = (e.localPosition - d.lastMoveScreen).distance;
      if (dist < 2.2) {
        if (_holdSince == null) {
          _holdSince = DateTime.now();
        } else if (DateTime.now().difference(_holdSince!).inMilliseconds >= 650) {
          _tryRecognize();
        }
      } else {
        _holdSince = DateTime.now();
      }
      d.lastMoveScreen = e.localPosition;
    }
  }

  void _endDraw() {
    final d = _draw!;
    _draw = null;
    _cancelHoldTimer();
    if (d.laser) {
      tools.laser.endStroke();
      return;
    }
    engine.endStroke();
  }

  void _cancelDraw() {
    final d = _draw!;
    _draw = null;
    _cancelHoldTimer();
    if (d.laser) {
      tools.laser.endStroke();
    } else {
      engine.cancelStroke();
    }
  }

  // Draw & hold → shape recognition.
  void _tryRecognize() {
    final d = _draw;
    if (d == null || d.pageId == null) return;
    final s = engine.liveStroke.value;
    if (s == null || s.pointCount < 3) return;
    final pts = <Offset>[];
    for (var i = 0; i < s.pointCount; i++) {
      pts.add(s.point(i));
    }
    final result = ShapeRecognizer.recognize(pts);
    if (result.element == null || result.confidence < 0.55) return;

    _cancelHoldTimer();
    // Commit current ink then replace — simplest correct flow: cancel live
    // stroke, add stroke directly, replace with shape.
    engine.cancelStroke();
    s.z = engine.pageInk(d.pageId!).nextZ();
    final ink = engine.pageInk(d.pageId!);
    ink.strokes.add(s);
    ink.sortInk();
    ink.touch();
    engine.replaceStrokeWithShape(d.pageId!, s, result.element!);

    // Start a fresh stroke from the current position.
    final style = tools.currentStrokeStyle();
    engine.beginStroke(d.pageId!, style);
    final doc = d.lastDoc;
    engine.extendStroke(_toPage(doc, d.pageId!), 0.5);
    _holdSince = DateTime.now();
  }

  // ------------------------------------------------------------- eraser

  void _beginErase(PointerDownEvent e, {required bool stylus}) {
    if (textSel.hasSelection) textSel.clear();
    final doc = _toDoc(e.localPosition);
    final pageId = _pageIdAtDoc(doc);
    if (pageId == null) return;
    engine.ensureLoaded(pageId);
    engine.beginEraserGesture(pageId);
    _erase = _Erase(e.pointer, stylus, pageId);
    _applyErase(e.localPosition);
  }

  void _extendErase(PointerMoveEvent e) => _applyErase(e.localPosition);

  void _applyErase(Offset screen) {
    final er = _erase!;
    final doc = _toDoc(screen);
    final pagePoint = _toPage(doc, er.pageId);
    final radius = tools.eraserRadius / viewport.scale;
    if (tools.eraserMode == EraserMode.stroke) {
      engine.eraseStrokeAt(er.pageId, pagePoint, radius);
    } else {
      engine.eraseAreaAt(er.pageId, pagePoint, radius);
    }
    // Cursor radius is SCREEN space and matches the erase area exactly:
    // doc radius (eraserRadius / scale) × scale == eraserRadius — constant
    // at any zoom (previously ×scale made the circle gigantic when zoomed
    // in, reading as a gray film over the page).
    engine.eraserCursor.value =
        EraserCursor(screenPos: screen, radius: tools.eraserRadius);
  }

  void _endErase() {
    engine.endEraserGesture();
    engine.eraserCursor.value = null;
    _erase = null;
  }

  // ------------------------------------------------------------- lasso

  void _beginLasso(PointerDownEvent e) {
    if (textSel.hasSelection) textSel.clear();
    final doc = _toDoc(e.localPosition);
    final pageId = _pageIdAtDoc(doc);
    if (pageId == null) return;
    engine.ensureLoaded(pageId);
    _lasso = _Lasso(e.pointer, pageId);
    engine.lassoPreview.value = [_toPage(doc, pageId)];
  }

  void _extendLasso(PointerMoveEvent e) {
    final l = _lasso!;
    final doc = _toDoc(e.localPosition);
    final pts = List<Offset>.of(engine.lassoPreview.value)
      ..add(_toPage(doc, l.pageId));
    engine.lassoPreview.value = pts;
  }

  void _endLasso() {
    final l = _lasso!;
    _lasso = null;
    engine.selectInLasso(l.pageId, engine.lassoPreview.value);
    engine.lassoPreview.value = const [];
  }

  void _cancelLasso() {
    _lasso = null;
    engine.lassoPreview.value = const [];
  }

  // ---------------------------------------------------- selection gestures

  SelHandle? _selectionHit(Offset screen) {
    if (!engine.hasSelection) return null;
    final doc = _toDoc(screen);
    final pageId = geometry.pageAt(doc)?.id;
    if (pageId == null || pageId != engine.selectionPageId) return null;
    final pagePoint = geometry.toPage(doc, pageId);
    final tol = 22 / viewport.scale;
    final h = engine.hitSelectionHandle(pagePoint, tol);
    if (h != SelHandle.none) return h;
    final b = engine.selectionBBox();
    if (b != null && b.inflate(10 / viewport.scale).contains(pagePoint)) {
      return SelHandle.none; // inside → move (via beginSelGesture)
    }
    return null;
  }

  void _beginSelGesture(PointerDownEvent e) {
    final doc = _toDoc(e.localPosition);
    final pageId = engine.selectionPageId!;
    final pagePoint = geometry.toPage(doc, pageId);
    final tol = 22 / viewport.scale;
    final handle = engine.hitSelectionHandle(pagePoint, tol);
    final startBBox = engine.selectionBBox();
    _selGesture = _SelGesture(e.pointer, handle, pagePoint)
      ..startBBox = startBBox
      ..handleBBox = startBBox;
    engine.beginSelectionTransform();
  }

  void _extendSelGesture(PointerMoveEvent e) {
    final g = _selGesture!;
    final doc = _toDoc(e.localPosition);
    final pagePoint = geometry.toPage(doc, g.pageId);
    switch (g.handle) {
      case SelHandle.none:
        engine.moveSelectionBy(pagePoint - g.lastPage);
        g.lastPage = pagePoint;
        break;
      case SelHandle.rotate:
        final center = engine.selectionBBox()!.center;
        final a = (g.lastPage - center).direction;
        final b = (pagePoint - center).direction;
        engine.rotateSelectionBy(g.rotation + (b - a), snap: true);
        g.rotation += b - a;
        break;
      default:
        // Corner scale: anchor = OPPOSITE corner.
        final b = engine.selectionBBox()!;
        final anchor = switch (g.handle) {
          SelHandle.topLeft => b.bottomRight,
          SelHandle.topRight => b.bottomLeft,
          SelHandle.bottomLeft => b.topRight,
          SelHandle.bottomRight => b.topLeft,
          _ => b.center,
        };
        final base = switch (g.handle) {
          SelHandle.topLeft => g.startBBox!.bottomRight,
          SelHandle.topRight => g.startBBox!.bottomLeft,
          SelHandle.bottomLeft => g.startBBox!.topRight,
          SelHandle.bottomRight => g.startBBox!.topLeft,
          _ => g.startBBox!.center,
        };
        var fx = (pagePoint.dx - base.dx) / (g.handleBBox!.width).abs();
        var fy = (pagePoint.dy - base.dy) / (g.handleBBox!.height).abs();
        if (fx.abs() < 0.02) fx = 0.02 * fx.sign;
        if (fy.abs() < 0.02) fy = 0.02 * fy.sign;
        engine.scaleSelectionBy(fx, fy, anchor);
        break;
    }
  }

  void _endSelGesture() {
    engine.endSelectionTransform();
    _selGesture = null;
  }

  void _cancelSelGesture() {
    if (_selGesture != null) {
      engine.cancelSelectionTransform();
    }
    _selGesture = null;
  }

  /// SELECTION-CONTROL routing (§5 + user report): selection handles are
  /// grabbable by ANY tool and ANY pointer (pen, finger, mouse) — the
  /// selection BODY moves with the non-drawing tools (lasso / pan / image /
  /// sticker). Drawing tools keep drawing over the selection interior and
  /// the eraser keeps erasing it; only the corner/rotate handles override
  /// them.
  bool _tryBeginSelectionControl(PointerDownEvent e) {
    if (!engine.hasSelection) return false;
    final hit = _selectionHit(e.localPosition);
    if (hit == null) return false;
    if (hit != SelHandle.none) {
      _beginSelGesture(e);
      return true;
    }
    switch (_tool) {
      case Tool.lasso:
      case Tool.pan:
      case Tool.image:
      case Tool.sticker:
        _beginSelGesture(e);
        return true;
      default:
        return false;
    }
  }

  // ------------------------------------------------------------- shapes (§8)

  void _beginShapeDrag(PointerDownEvent e, {required bool stylus}) {
    if (textSel.hasSelection) textSel.clear();
    final doc = _toDoc(e.localPosition);
    final pageId = _pageIdAtDoc(doc);
    if (pageId == null) return;
    engine.ensureLoaded(pageId);
    final pagePoint = _toPage(doc, pageId);
    _shapeDrag = _ShapeDrag(e.pointer, pageId, pagePoint, stylus);
    _updateShapePreview(pagePoint);
  }

  void _extendShapeDrag(PointerMoveEvent e) {
    final d = _shapeDrag!;
    final doc = _toDoc(e.localPosition);
    final pagePoint = _toPage(doc, d.pageId);
    if (tools.shapeType == ShapeType.freeform &&
        (pagePoint - d.last).distance > 3) {
      d.freePts.add(pagePoint);
    }
    d.last = pagePoint;
    _updateShapePreview(pagePoint);
  }

  void _updateShapePreview(Offset current) {
    final d = _shapeDrag!;
    shapePreview.value = ShapeDragPreview(d.pageId, _buildShapeEl(d, current));
  }

  /// Builds the live shape element from the drag state (§8: type, color,
  /// width, fill, polygon sides, grid snap, aspect lock).
  ShapeEl _buildShapeEl(_ShapeDrag d, Offset current) {
    final t = tools;
    final type = t.shapeType;
    final el = ShapeEl(
      id: d.shapeId,
      z: 0,
      type: type,
      strokeColor: t.shapeStrokeColor,
      strokeWidth: t.shapeStrokeWidth,
      fillColor: t.shapeFillColor,
      fillOpacity: t.shapeFillOpacity,
      sides: t.shapeSides,
    );
    if (type.isPolylineLike) {
      el.pts = t.shapeGridSnap
          ? [for (final p in [d.start, current]) _snapToGrid(p)]
          : [d.start, current];
    } else if (type == ShapeType.freeform) {
      el.pts = d.freePts.isEmpty
          ? [d.start, current]
          : [...d.freePts, current];
    } else {
      var a = d.start;
      var b = current;
      if (t.shapeGridSnap) {
        a = _snapToGrid(a);
        b = _snapToGrid(b);
      }
      if (t.shapeAspectLock) {
        // Square-locked: the larger extent becomes both.
        final w = b.dx - a.dx;
        final h = b.dy - a.dy;
        final size = math.max(w.abs(), h.abs());
        b = Offset(
          a.dx + (w == 0 ? size : w.sign * size),
          a.dy + (h == 0 ? size : h.sign * size),
        );
      }
      el.x = math.min(a.dx, b.dx);
      el.y = math.min(a.dy, b.dy);
      el.w = math.max(2, (a.dx - b.dx).abs());
      el.h = math.max(2, (a.dy - b.dy).abs());
    }
    return el;
  }

  Offset _snapToGrid(Offset p) {
    const pitch = GRID_PITCH;
    return Offset(
      (p.dx / pitch).roundToDouble() * pitch,
      (p.dy / pitch).roundToDouble() * pitch,
    );
  }

  void _endShapeDrag() {
    final d = _shapeDrag!;
    _shapeDrag = null;
    final el = shapePreview.value?.el;
    shapePreview.value = null;
    if (el == null) return;
    // Discard degenerate drags (a tap, not a drag).
    if ((d.last - d.start).distance < 4) return;
    engine.addElement(d.pageId, el);
  }

  void _cancelShapeDrag() {
    _shapeDrag = null;
    shapePreview.value = null;
  }

  // ------------------------------------------------------------- crop (§5)

  /// Opens the crop editor for [el] on [pageId] (called from the selection
  /// bar). While open, the crop session is MODAL: all canvas pointers
  /// manipulate the crop window.
  void beginCrop(int pageId, ImageEl el) {
    cropSession.value?.dispose();
    cropSession.value = CropSession(pageId: pageId, el: el);
  }

  void cancelCrop() {
    cropSession.value?.dispose();
    cropSession.value = null;
  }

  /// Commits the crop window: maps it to a normalized source crop, keeps
  /// the remaining content EXACTLY in place, and pushes ONE undoable
  /// element update.
  void commitCrop() {
    final s = cropSession.value;
    if (s == null) return;
    cropSession.value = null;
    final el = s.el;
    final pageId = s.pageId;
    s.dispose();

    final cur = el.crop ?? const [0.0, 0.0, 1.0, 1.0];
    double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
    // Window (element-local page coords) → absolute normalized crop.
    final l = clamp01(cur[0] +
        (s.window.left - el.x) / el.w * (cur[2] - cur[0]));
    final t = clamp01(cur[1] +
        (s.window.top - el.y) / el.h * (cur[3] - cur[1]));
    final r = clamp01(cur[2] +
        (s.window.right - el.x) / el.w * (cur[2] - cur[0]));
    final b = clamp01(cur[3] +
        (s.window.bottom - el.y) / el.h * (cur[3] - cur[1]));
    if (r - l < 0.02 || b - t < 0.02) return; // degenerate → no-op

    final updated = el.deepCopy();
    updated.x = s.window.left;
    updated.y = s.window.top;
    updated.w = math.max(2, s.window.width);
    updated.h = math.max(2, s.window.height);
    updated.crop = [l, t, r, b];
    engine.updateElement(pageId, updated);
  }

  bool _handleCropDown(PointerDownEvent e) {
    final s = cropSession.value;
    if (s == null) return false;
    _pointers[e.pointer] = _Ptr(e.pointer, e.kind);
    if (_cropPointer != -1) return true; // one manipulator at a time
    final doc = _toDoc(e.localPosition);
    final pagePoint = geometry.toPage(doc, s.pageId);
    final local = s.toLocal(pagePoint);
    final corner = s.hitCorner(local);
    if (corner != null) {
      _cropCorner = corner;
      _cropPointer = e.pointer;
      _cropLastLocal = local;
    } else if (s.window.inflate(24).contains(local)) {
      _cropCorner = null; // body → move the window
      _cropPointer = e.pointer;
      _cropLastLocal = local;
    }
    return true;
  }

  bool _handleCropMove(PointerMoveEvent e) {
    final s = cropSession.value;
    if (s == null) return false;
    if (e.pointer != _cropPointer) return true; // swallow other pointers
    final doc = _toDoc(e.localPosition);
    final pagePoint = geometry.toPage(doc, s.pageId);
    final local = s.toLocal(pagePoint);
    if (_cropCorner != null) {
      s.dragCorner(_cropCorner!, local);
    } else if (_cropLastLocal != null) {
      s.dragBy(local - _cropLastLocal!);
    }
    _cropLastLocal = local;
    return true;
  }

  bool _endCrop(int pointer) {
    final s = cropSession.value;
    if (s == null) return false;
    _pointers.remove(pointer);
    if (pointer == _cropPointer) {
      _cropPointer = -1;
      _cropCorner = null;
      _cropLastLocal = null;
    }
    return true;
  }

  // ------------------------------------------------------------- ruler

  _RulerDrag? _rulerDrag;

  bool _hitRuler(Offset doc) => ruler != null && ruler!.hitBody(doc);

  void _beginRulerDrag(PointerDownEvent e) {
    _rulerDrag = _RulerDrag(e.pointer);
    ruler!.beginDrag(_toDoc(e.localPosition));
  }

  // ------------------------------------------------------------- pinch

  void _startPinch(Offset a, Offset b, int ptrA, int ptrB) {
    _pinch = _Pinch(ptrA, ptrB, a, b, viewport.scale, viewport.pan);
  }

  void _startPinchFromDraw(_Draw keep, PointerDownEvent second) {
    _pinch = _Pinch(
        keep.pointer, second.pointer, keep.lastScreen, second.localPosition, viewport.scale, viewport.pan);
  }

  void _extendPinch(PointerMoveEvent e) {
    final p = _pinch!;
    if (e.pointer == p.a) {
      p.posA = e.localPosition;
    } else {
      p.posB = e.localPosition;
    }
    // Focal point stays under the fingers; focal movement pans.
    final focal = (p.posA + p.posB) / 2;
    final dist = (p.posA - p.posB).distance;
    if (dist < 8 || p.startDist < 8) return;
    final factor = dist / p.startDist;
    final newScale = (p.startScale * factor).clamp(ViewportController.minScale, ViewportController.maxScale);
    viewport.setMatrix(newScale, focal - p.startFocalDoc * newScale);
  }

  void _endPinch(int pointer) {
    if (_pinch == null) return;
    final p = _pinch!;
    // Two-finger quick tap? (<400ms, <26px move, no pinch)
    final quickTap = _twoFingerDownAt != null &&
        DateTime.now().difference(_twoFingerDownAt!).inMilliseconds < 400 &&
        (p.posA - p.startA).distance < 26 &&
        (p.posB - p.startB).distance < 26 &&
        ((p.posA - p.posB).distance - p.startDist).abs() < 8;
    _pinch = null;
    _twoFingerDownAt = null;
    viewport.endInteraction();
    if (quickTap) {
      _fireFingerAction(FingerAction.twoFingerTap);
    }
  }

  // ------------------------------------------------------------- pan

  void _beginPan(PointerEvent e) {
    _panPointer = e.pointer;
    _pointers[e.pointer] ??= _Ptr(e.pointer, e.kind);
    _pointers[e.pointer]!.lastPos = e.localPosition;
    _velSamples.clear();
    _velSamples.add(_VelSample(e.timeStamp, e.localPosition));
    _panMoveCount = 0;
    _panDistance = 0;
  }

  void _trackPanVelocity(PointerMoveEvent e) {
    _panMoveCount++;
    _panDistance += e.delta.distance;
    _velSamples.add(_VelSample(e.timeStamp, e.localPosition));
    // Keep a ~120ms window.
    while (_velSamples.length > 6) {
      _velSamples.removeAt(0);
    }
  }

  /// Pan released. Starts the inertial fling when the finger was moving;
  /// returns true when the "pan" never really moved (i.e. it was a TAP).
  bool _endPan(PointerUpEvent e, _Ptr? p) {
    _panPointer = -1;
    final wasTap = _panDistance < 18;
    final samples = _velSamples;
    if (p != null &&
        p.kind == PointerDeviceKind.touch &&
        samples.length >= 2 &&
        _panMoveCount >= 2) {
      final first = samples.first;
      final last = samples.last;
      final dt =
          last.timeStamp.inMicroseconds - first.timeStamp.inMicroseconds;
      if (dt > 8000) {
        final v = (last.position - first.position) * (1e6 / dt);
        final speed = v.distance;
        if (speed > 120) {
          final capped = speed > 6500 ? v * (6500 / speed) : v;
          viewport.startFling(capped);
          samples.clear();
          return false;
        }
      }
    }
    samples.clear();
    return wasTap;
  }

  // ------------------------------------------------------------- taps

  _DeferredTap? _deferredTap;

  void _fireDeferredTap(Offset screen) {
    final doc = _toDoc(screen);
    final pageId = _pageIdAtDoc(doc);
    if (pageId == null) return;
    final pagePoint = _toPage(doc, pageId);
    if (textSel.hasSelection) textSel.clear();
    if (_tool == Tool.text) {
      onTextTap?.call(pageId, pagePoint);
    } else if (_tool == Tool.textSelect) {
      onTextSelectTap?.call(pageId, pagePoint);
    } else if (_tool == Tool.image) {
      onPickImage?.call(pageId, pagePoint);
    } else if (_tool == Tool.sticker) {
      onPickSticker?.call(pageId, pagePoint);
    }
  }

  // ------------------------------------------------------- PDF text select

  static const Duration _textHoldDelay = Duration(milliseconds: 480);
  Timer? _textHoldTimer;
  int _textHoldPointer = -1;
  Offset _textHoldScreen = Offset.zero;
  int _textHoldPageId = -1;
  int _textHoldPageNumber = 0;
  _PdfSelDrag? _textSelDrag;

  /// Long-press pick that is waiting for the background text extraction
  /// to finish (the workspace completes it when the service notifies).
  ({int pageId, int pageNumber, Offset screen, int pointer})?
      _pendingTextPick;

  bool get _pdfOpen => PdfDocumentController.I.isOpen;

  int? _pdfPageNumberOf(int pageId) {
    if (!_pdfOpen) return null;
    final meta = engine.metaOf(pageId);
    if (meta == null) return null;
    final idx = engine.pages.indexOf(meta);
    if (idx < 0 || idx >= PdfDocumentController.I.pageCount) return null;
    return idx + 1;
  }

  /// Starts the long-press hold for [e] when it landed on a PDF-backed
  /// page with a non-eraser tool. The hold is cancelled by movement,
  /// lift, a second finger (pinch) or a modal session.
  void _maybeStartTextHold(PointerDownEvent e) {
    _cancelTextHold();
    if (cropSession.value != null) return;
    if (_tool == Tool.eraser) return;
    if (!_pdfOpen) return;
    // Never hijack an active text-selection drag or an ink selection.
    if (_textSelDrag != null) return;
    if (engine.hasSelection) return;
    if (textSel.hasSelection) {
      // A press ON the active selection (handles or body) is consumed by
      // _tryBeginTextSelectionControl — starting a hold for it would
      // reset the selection the user is adjusting.
      final selPageId = textSel.pageId;
      if (selPageId != null) {
        final doc = _toDoc(e.localPosition);
        final meta = geometry.pageAt(doc);
        if (meta != null && meta.id == selPageId) {
          final pagePoint = geometry.toPage(doc, selPageId);
          final tolPage = 26 / viewport.scale;
          final handles = textSel.handlePositionsPage();
          final onHandle = handles != null &&
              ((handles.$1 - pagePoint).distance <= tolPage ||
                  (handles.$2 - pagePoint).distance <= tolPage);
          final box = textSel.selectionBBoxPage();
          if (onHandle ||
              (box != null && box.inflate(6).contains(pagePoint))) {
            return;
          }
        }
      }
    }
    final doc = _toDoc(e.localPosition);
    final meta = geometry.pageAt(doc);
    if (meta == null) return;
    final pageNum = _pdfPageNumberOf(meta.id);
    if (pageNum == null) return;
    _textHoldPointer = e.pointer;
    _textHoldScreen = e.localPosition;
    _textHoldPageId = meta.id;
    _textHoldPageNumber = pageNum;
    _textHoldTimer = Timer(_textHoldDelay, _tryBeginTextSelection);
  }

  void _cancelTextHold() {
    _textHoldTimer?.cancel();
    _textHoldTimer = null;
    _textHoldPointer = -1;
    _pendingTextPick = null;
  }

  void _tryBeginTextSelection() {
    _textHoldTimer = null;
    final pointer = _textHoldPointer;
    if (pointer < 0) return;
    final p = _pointers[pointer];
    if (p == null || p.rejected) {
      _cancelTextHold();
      return;
    }
    if (cropSession.value != null || _pinch != null) {
      _cancelTextHold();
      return;
    }
    if (_tool == Tool.eraser) {
      _cancelTextHold();
      return;
    }
    // Abort whatever quiet gesture this pointer was holding (a stationary
    // pan, a one-point "dot" stroke, a pending tap) — the long-press now
    // owns the pointer and must NOT leave any ink behind.
    if (_draw != null && _draw!.pointer == pointer) _cancelDraw();
    if (_erase != null && _erase!.pointer == pointer) _endErase();
    if (_panPointer == pointer) {
      _panPointer = -1;
      _velSamples.clear();
    }
    if (_deferredTap != null && _deferredTap!.pointer == pointer) {
      _deferredTap = null;
    }
    _cancelHoldTimer();

    final pageId = _textHoldPageId;
    final pageNum = _textHoldPageNumber;
    final screen = _textHoldScreen;
    if (!PdfTextService.I.isReady) {
      // Extraction still running — the workspace completes the pick when
      // it lands (see completePendingTextPick).
      _pendingTextPick = (
        pageId: pageId,
        pageNumber: pageNum,
        screen: screen,
        pointer: pointer
      );
      return;
    }
    _beginTextSelectionAt(pageId, pageNum, screen, pointer);
    _cancelTextHold();
  }

  /// Called by the workspace when the text service finished loading —
  /// completes a long-press that was waiting for extraction.
  void completePendingTextPick() {
    final pp = _pendingTextPick;
    if (pp == null) return;
    final p = _pointers[pp.pointer];
    if (p == null || p.rejected) {
      _cancelTextHold();
      return;
    }
    _beginTextSelectionAt(pp.pageId, pp.pageNumber, pp.screen, pp.pointer);
    _cancelTextHold();
  }

  void _beginTextSelectionAt(
      int pageId, int pageNumber, Offset screen, int pointer) {
    final doc = _toDoc(screen);
    final meta = engine.metaOf(pageId);
    if (meta == null) return;
    final idx = engine.pages.indexOf(meta);
    if (idx < 0) return;
    final rect = geometry.pageRect(idx);
    final pdfPts = PdfDocumentController.I.pageSize(pageNumber);
    if (pdfPts == null || pdfPts.width <= 0 || rect.width <= 0) return;
    final scale = rect.width / pdfPts.width;
    final pagePoint = geometry.toPage(doc, pageId);
    final viewPoint = Offset(pagePoint.dx / scale, pagePoint.dy / scale);
    final page = PdfTextService.I.page(pageNumber);
    if (page == null || page.words.isEmpty) return;
    final hit = PdfTextSelectionController.hitWordInPage(page, viewPoint);
    if (hit == null) return; // empty area / image → no menu (spec)
    textSel.begin(
      pageId: pageId,
      pageNumber: pageNumber,
      scale: scale,
      wordIndex: hit,
      pdfxW: pdfPts.width,
      pdfxH: pdfPts.height,
    );
    // The same pointer keeps extending the selection word by word.
    _textSelDrag = _PdfSelDrag(
      pointer: pointer,
      handle: PdfSelHandle.end,
      insideTap: false,
    );
  }

  /// Pointer-down routing for an EXISTING text selection: grab a handle
  /// (extend that boundary) or tap inside the selection (toggle the
  /// action bar). Returns true when consumed.
  bool _tryBeginTextSelectionControl(PointerDownEvent e) {
    if (!textSel.hasSelection) return false;
    if (cropSession.value != null) return false;
    final pageId = textSel.pageId;
    if (pageId == null) return false;
    final doc = _toDoc(e.localPosition);
    final meta = geometry.pageAt(doc);
    if (meta == null || meta.id != pageId) return false;

    const tol = 26.0; // screen px
    final handles = textSel.handlePositionsPage();
    if (handles == null) return false;
    final origin = geometry.pageOrigin(pageId);
    final sPos = viewport.toScreen(handles.$1 + origin);
    final ePos = viewport.toScreen(handles.$2 + origin);
    if ((e.localPosition - sPos).distance <= tol) {
      textSel.beginHandleDrag(leftSide: true);
      _textSelDrag = _PdfSelDrag(
        pointer: e.pointer,
        handle: PdfSelHandle.start,
        insideTap: false,
      );
      return true;
    }
    if ((e.localPosition - ePos).distance <= tol) {
      textSel.beginHandleDrag(leftSide: false);
      _textSelDrag = _PdfSelDrag(
        pointer: e.pointer,
        handle: PdfSelHandle.end,
        insideTap: false,
      );
      return true;
    }
    // Tap INSIDE the selection body → toggle the action bar (consumed; a
    // drag from here does nothing until release).
    final pagePoint = geometry.toPage(doc, pageId);
    final box = textSel.selectionBBoxPage();
    if (box != null && box.inflate(6).contains(pagePoint)) {
      _textSelDrag = _PdfSelDrag(
        pointer: e.pointer,
        handle: PdfSelHandle.none,
        insideTap: true,
      );
      return true;
    }
    return false;
  }

  void _extendTextSelDrag(Offset screen) {
    final d = _textSelDrag!;
    if (d.handle == PdfSelHandle.none) return; // inside-tap: no drag action
    final sel = textSel;
    final pageId = sel.pageId;
    if (pageId == null) {
      _textSelDrag = null;
      return;
    }
    final doc = _toDoc(screen);
    final meta = geometry.pageAt(doc);
    if (meta == null || meta.id != pageId) return;
    final pagePoint = geometry.toPage(doc, pageId);
    final viewPoint =
        Offset(pagePoint.dx / sel.scale, pagePoint.dy / sel.scale);
    final hit = sel.hitWord(viewPoint);
    if (hit != null) sel.dragFocusTo(hit);
  }

  void _handleTapSequences(Offset screen) {
    final now = DateTime.now();
    if (_lastTapUp != null &&
        now.difference(_lastTapUp!).inMilliseconds < 350 &&
        (screen - _lastTapScreen).distance < 26) {
      _lastTapUp = null;
      _fireFingerAction(FingerAction.doubleTap);
    } else {
      _lastTapUp = now;
      _lastTapScreen = screen;
    }
  }

  // ------------------------------------------------------------- actions

  void _fireAction(PenButton button, PenPattern pattern) {
    if (!settings.settings.penShortcutsEnabled) return;
    final action = settings.settings.actionFor(button, pattern);
    _runAction(action);
  }

  void _fireFingerAction(FingerAction a) {
    switch (a) {
      case FingerAction.doubleTap:
        // Default: zoom toggle 1x/2x at tap point.
        final target = viewport.scale >= 1.95 ? 1.0 : 2.0;
        viewport.zoomTo(target, _lastTapScreen);
        break;
      case FingerAction.twoFingerTap:
        // Default: undo.
        engine.undo();
        break;
    }
  }

  void _runAction(PenAction action) {
    switch (action) {
      case PenAction.none:
        break;
      case PenAction.eraserHold:
        // Handled via hover state.
        _hoverEraseActive = true;
        break;
      case PenAction.eraserToggle:
        tools.tool = _tool == Tool.eraser ? Tool.pen : Tool.eraser;
        break;
      case PenAction.pen:
        tools.tool = Tool.pen;
        break;
      case PenAction.highlighter:
        tools.tool = Tool.highlighter;
        break;
      case PenAction.laser:
        tools.tool = Tool.laser;
        break;
      case PenAction.lasso:
        tools.tool = Tool.lasso;
        break;
      case PenAction.text:
        tools.tool = Tool.text;
        break;
      case PenAction.shape:
        tools.tool = Tool.shape;
        break;
      case PenAction.pan:
        tools.tool = Tool.pan;
        break;
      case PenAction.undo:
        engine.undo();
        break;
      case PenAction.redo:
        engine.redo();
        break;
      case PenAction.pagePrev:
        _jumpPage(-1);
        break;
      case PenAction.pageNext:
        _jumpPage(1);
        break;
      case PenAction.colorNext:
        tools.cycleColorNext();
        break;
      case PenAction.widthUp:
        tools.widthUp();
        break;
      case PenAction.widthDown:
        tools.widthDown();
        break;
      case PenAction.zoomIn:
        viewport.zoomBy(1.25, screenSize.center(Offset.zero));
        viewport.endInteraction();
        break;
      case PenAction.zoomOut:
        viewport.zoomBy(0.8, screenSize.center(Offset.zero));
        viewport.endInteraction();
        break;
      case PenAction.toggleToolbar:
        onToggleToolbar?.call();
        break;
      case PenAction.quickExport:
        onQuickExport?.call();
        break;
    }
  }

  void _jumpPage(int delta) {
    final current = geometry.pageIndexAtDoc(viewport.toDoc(screenSize.center(Offset.zero)));
    if (current == null) return;
    final target = (current + delta)
        .clamp(0, math.max(0, engine.pages.length - 1))
        .toInt();
    final page = engine.pages[target];
    onPageChanged?.call(page.id);
  }

  void _startHoldTimer() {
    _cancelHoldTimer();
    _holdSince = DateTime.now();
  }

  void _cancelHoldTimer() {
    _holdSince = null;
  }

  // Barrel press during a down event (writing or not).
  void _barrelPressed({required PenPattern pattern}) {
    _fireAction(PenButton.barrel, pattern);
  }
}

enum FingerAction { doubleTap, twoFingerTap }

/// Active PDF text-selection drag: which pointer owns it, which handle
/// (start/end, none for an inside tap) moves.
class _PdfSelDrag {
  final int pointer;
  final PdfSelHandle handle;
  final bool insideTap;
  _PdfSelDrag({
    required this.pointer,
    required this.handle,
    required this.insideTap,
  });
}

/// Eraser-end button bit (value 32) reported by stylus events.
const int kEraserButtonBit = 0x20;

class _Ptr {
  final int pointer;
  final PointerDeviceKind kind;
  bool rejected;
  Offset lastPos;

  _Ptr(this.pointer, this.kind, {this.rejected = false})
      : lastPos = Offset.zero;
}

class _Draw {
  final int pointer;
  final bool stylus;
  final bool laser;
  final bool mouse;
  int? pageId;
  Offset lastDoc = Offset.zero;

  /// Last CANVAS-LOCAL screen position (for pinch conversion).
  Offset lastScreen = Offset.zero;
  Offset lastMoveScreen = Offset.zero;
  bool snappedLast = false;

  _Draw(this.pointer, this.stylus,
      {this.laser = false, this.pageId, this.lastDoc = Offset.zero, this.mouse = false});
}

class _Erase {
  final int pointer;
  final bool stylus;
  final int pageId;

  _Erase(this.pointer, this.stylus, this.pageId);
}

class _Lasso {
  final int pointer;
  final int pageId;

  _Lasso(this.pointer, this.pageId);
}

class _SelGesture {
  final int pointer;
  final SelHandle handle;
  final int pageId;
  Offset lastPage;
  double rotation = 0;
  Rect? startBBox;
  Rect? handleBBox;

  _SelGesture(this.pointer, this.handle, this.lastPage)
      : pageId = StrokeEngine.I.selectionPageId ?? -1;
}

class _Pinch {
  final int a;
  final int b;
  final Offset startA;
  final Offset startB;
  final double startScale;
  final Offset startFocalDoc;
  final double startDist;
  Offset posA;
  Offset posB;

  _Pinch(this.a, this.b, this.startA, this.startB, this.startScale, Offset startPan)
      : startFocalDoc = ((startA + startB) / 2 - startPan) / startScale,
        startDist = (startA - startB).distance,
        posA = startA,
        posB = startB;
}

class _RulerDrag {
  final int pointer;

  _RulerDrag(this.pointer);
}

class _DeferredTap {
  final Offset screen;
  final int pointer;

  _DeferredTap(this.screen, this.pointer);
}

/// One pan velocity sample (event timestamp + canvas-local position).
class _VelSample {
  final Duration timeStamp;
  final Offset position;

  _VelSample(this.timeStamp, this.position);
}

/// In-progress §8 shape drag: the page it started on, the anchor point and
/// the freehand trail (freeform only). The live element is REBUILT from the
/// drag state on every move (see GestureRouter._buildShapeEl).
class _ShapeDrag {
  _ShapeDrag(this.pointer, this.pageId, this.start, this.stylus)
      : shapeId = ElementIdGen.next(),
        last = start,
        freePts = [start];

  final int pointer;
  final int pageId;
  final String shapeId;
  final bool stylus;
  final Offset start;
  Offset last;
  final List<Offset> freePts;
}

/// Live shape-drag preview (pageId + the element built so far) — painted by
/// the workspace's doc-space overlay.
class ShapeDragPreview {
  ShapeDragPreview(this.pageId, this.el);

  final int pageId;
  final ShapeEl el;
}

/// §5 image-crop editor session. The crop window lives in the element's
/// LOCAL page coordinates (before its rotation) — the workspace overlay
/// rotates it with the image when painting, and the router inverse-rotates
/// pointer positions when hit-testing.
class CropSession extends ChangeNotifier {
  CropSession({required this.pageId, required this.el})
      : window = Rect.fromLTWH(el.x, el.y, el.w, el.h);

  final int pageId;
  final ImageEl el;

  /// Current crop window (element-local page coords).
  Rect window;

  /// Inverse-rotates a page point into the element's local frame.
  Offset toLocal(Offset pagePoint) =>
      rotatePoint(pagePoint, el.center, -el.rotation);

  static const double cornerTol = 22;

  CropCorner? hitCorner(Offset local) {
    if ((local - window.topLeft).distance <= cornerTol) {
      return CropCorner.topLeft;
    }
    if ((local - window.topRight).distance <= cornerTol) {
      return CropCorner.topRight;
    }
    if ((local - window.bottomLeft).distance <= cornerTol) {
      return CropCorner.bottomLeft;
    }
    if ((local - window.bottomRight).distance <= cornerTol) {
      return CropCorner.bottomRight;
    }
    return null;
  }

  static double _clamp(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);

  /// Corner drag: the opposite edges stay anchored; the window keeps a
  /// minimum size of 8 page units.
  void dragCorner(CropCorner c, Offset local) {
    var l = window.left;
    var t = window.top;
    var r = window.right;
    var b = window.bottom;
    switch (c) {
      case CropCorner.topLeft:
        l = _clamp(local.dx, el.x, math.max(el.x, r - 8));
        t = _clamp(local.dy, el.y, math.max(el.y, b - 8));
      case CropCorner.topRight:
        r = _clamp(local.dx, math.min(l + 8, el.x + el.w), el.x + el.w);
        t = _clamp(local.dy, el.y, math.max(el.y, b - 8));
      case CropCorner.bottomLeft:
        l = _clamp(local.dx, el.x, math.max(el.x, r - 8));
        b = _clamp(local.dy, math.min(t + 8, el.y + el.h), el.y + el.h);
      case CropCorner.bottomRight:
        r = _clamp(local.dx, math.min(l + 8, el.x + el.w), el.x + el.w);
        b = _clamp(local.dy, math.min(t + 8, el.y + el.h), el.y + el.h);
    }
    window = Rect.fromLTRB(l, t, r, b);
    notifyListeners();
  }

  /// Body drag: move the window, clamped inside the element rect.
  void dragBy(Offset deltaLocal) {
    final nx = _clamp(
      window.left + deltaLocal.dx,
      el.x,
      math.max(el.x, el.x + el.w - window.width),
    );
    final ny = _clamp(
      window.top + deltaLocal.dy,
      el.y,
      math.max(el.y, el.y + el.h - window.height),
    );
    window = Rect.fromLTWH(nx, ny, window.width, window.height);
    notifyListeners();
  }

  /// Expands the window back to the whole visible image.
  void reset() {
    window = Rect.fromLTWH(el.x, el.y, el.w, el.h);
    notifyListeners();
  }
}

enum CropCorner { topLeft, topRight, bottomLeft, bottomRight }

