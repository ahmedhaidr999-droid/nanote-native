import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../controllers/pdf_document_controller.dart';
import '../controllers/viewport_controller.dart';

/// One PDF background page. Positioned per page by the workspace (inside the
/// doc transform); paints the rendered [ui.Image] fitted into [pageSize].
///
/// Renders nothing while the document is closed. Re-requests a render at the
/// current quality bucket whenever it becomes visible
/// (didChangeDependencies) and whenever [PdfDocumentController.renderTick] or
/// [ViewportController.renderTick] fire (new images ready / zoom settled).
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
  double _requestedScale = 0;
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    widget.pdf.renderTick.addListener(_onTick);
    widget.viewport.renderTick.addListener(_onTick);
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
      widget.pdf.renderTick.addListener(_onTick);
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

  void _onTick() => _request();

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
    try {
      final img = await widget.pdf.pageImage(widget.pageNumber, hint);
      // Guard setState after dispose.
      if (!mounted || img == null) return;
      setState(() => _image = img);
    } finally {
      _pending = false;
    }
  }

  @override
  void dispose() {
    widget.pdf.renderTick.removeListener(_onTick);
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
      // Subtle placeholder until the render arrives.
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0x14808898),
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
