import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../controllers/pdf_document_controller.dart';
import '../controllers/viewport_controller.dart';

/// A rendered PDF page: the decoded image, its cache key ('page@widthPx')
/// and its UNIQUE live handle. The tile retains/releases by HANDLE
/// (v2.6.0) — a same-key re-render can never collide with the ref-count
/// of the image a visible tile is still painting.
class PdfPageBitmap {
  const PdfPageBitmap(this.image, this.key, this.handle);

  final ui.Image image;

  /// Cache/dedupe key: 'pageNumber@widthPx'.
  final String key;

  /// Unique live-image handle the controller ref-counts.
  final String handle;
}

/// One PDF background page. Positioned per page by the workspace (inside the
/// doc transform); paints the rendered [ui.Image] fitted into [pageSize].
///
/// v2.1 hardening:
///  * WHITE paper placeholder while a render is pending/missing — the page
///    always looks like paper, never a gray block.
///  * Retains its current image in the controller (ref-counted) — the LRU
///    can evict logically, but pixels in use are never disposed (painting a
///    disposed image kills the rasterizer → page went gray/blank).
///  * Retry timer: a render that came back null retries a few times with a
///    short backoff (the controller retries transient pdfx failures too).
///  * Priority requests: the tile is on screen, its render jumps the queue.
class PdfPageTile extends StatefulWidget {
  const PdfPageTile({
    super.key,
    required this.pdf,
    required this.pageNumber,
    required this.scale,
    required this.viewport,
    required this.pageSize,
  });

  final PdfDocumentController pdf;

  /// 1-BASED pdfx page number.
  final int pageNumber;

  /// Current viewport scale (screen zoom, not ×dpr — dpr is added here).
  final double scale;

  final ViewportController viewport;

  /// Page size in logical doc units the image is fitted into.
  final Size pageSize;

  @override
  State<PdfPageTile> createState() => _PdfPageTileState();
}

class _PdfPageTileState extends State<PdfPageTile> {
  ui.Image? _image;
  String? _retainedHandle;
  double _requestedScale = 0;
  bool _pending = false;
  Timer? _retryTimer;
  int _retries = 0;

  @override
  void initState() {
    super.initState();
    widget.pdf.renderTick.addListener(_onTick);
    widget.viewport.renderTick.addListener(_onTick);
    // The controller itself: doc open/close transitions wake the tile even
    // when no render tick fired (e.g. it exhausted its retries while the
    // document was still opening).
    widget.pdf.addListener(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _request();
  }

  @override
  void didUpdateWidget(covariant PdfPageTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdf != widget.pdf) {
      oldWidget.pdf.renderTick.removeListener(_onTick);
      oldWidget.pdf.removeListener(_onTick);
      widget.pdf.renderTick.addListener(_onTick);
      widget.pdf.addListener(_onTick);
      _dropRetained();
      _image = null;
      _requestedScale = 0;
    }
    if (oldWidget.viewport != widget.viewport) {
      oldWidget.viewport.renderTick.removeListener(_onTick);
      widget.viewport.renderTick.addListener(_onTick);
    }
    if (oldWidget.pageNumber != widget.pageNumber ||
        oldWidget.scale != widget.scale ||
        oldWidget.pageSize != widget.pageSize) {
      _request();
    }
  }

  void _onTick() {
    // A fresh document opened → give the render loop a clean slate.
    if (widget.pdf.isOpen) _retries = 0;
    _request();
  }

  void _dropRetained() {
    final handle = _retainedHandle;
    if (handle != null) {
      widget.pdf.release(handle);
      _retainedHandle = null;
    }
  }

  Future<void> _request() async {
    if (!mounted || !widget.pdf.isOpen || _pending) return;
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    final hint = widget.scale * dpr;
    // Same quality bucket as the last request → nothing to do (the
    // controller buckets internally; this avoids redundant traffic when
    // renderTick fires for OTHER pages).
    if (_image != null && (hint - _requestedScale).abs() < 0.2) return;

    _pending = true;
    _requestedScale = hint;
    _retryTimer?.cancel();
    try {
      final bmp =
          await widget.pdf.pageImage(widget.pageNumber, hint, priority: true);
      // Guard setState after dispose.
      if (!mounted) return;
      if (bmp == null) {
        // Render failed (transient pdfx error or queue hiccup): retry with a
        // short backoff — the page must not stay blank.
        if (_retries < 5) {
          _retries++;
          _retryTimer = Timer(
            Duration(milliseconds: 350 * _retries),
            _request,
          );
        }
        return;
      }
      _retries = 0;
      if (bmp.handle != _retainedHandle) {
        _dropRetained();
        _retainedHandle = bmp.handle;
        widget.pdf.retain(bmp.handle);
      }
      setState(() => _image = bmp.image);
    } finally {
      _pending = false;
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _dropRetained();
    widget.pdf.renderTick.removeListener(_onTick);
    widget.pdf.removeListener(_onTick);
    widget.viewport.renderTick.removeListener(_onTick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pdf.isOpen) return const SizedBox.shrink();
    return CustomPaint(
      size: widget.pageSize,
      painter: _PdfTilePainter(image: _image, size: widget.pageSize),
    );
  }
}

class _PdfTilePainter extends CustomPainter {
  _PdfTilePainter({required this.image, required this.size});

  final ui.Image? image;
  final Size size;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final img = image;
    if (img == null) {
      // WHITE paper-like placeholder until the render arrives — never a
      // gray block (a page that is still loading must look like paper).
      final r = RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(4),
      );
      canvas.drawRRect(r, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawRRect(
        r,
        Paint()
          ..color = const Color(0x140EA5E9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      return;
    }
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _PdfTilePainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.size != size;
  }
}
