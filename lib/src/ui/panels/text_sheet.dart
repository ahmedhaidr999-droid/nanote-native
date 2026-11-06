import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../controllers/stroke_engine.dart';
import '../../controllers/tool_controller.dart';
import '../../i18n/strings.dart';
import '../../models/page_elements.dart';
import '../../models/paper.dart';
import '../../theme/nanote_theme.dart';

/// Text element editor: content, 6 fonts, size slider, color, bold / italic /
/// underline and alignment.
///
/// The workspace normally pre-creates the element (via engine.addElement) and
/// passes it as [existing] — in that case this sheet only UPDATES (or removes
/// on empty text). When [existing] is null a fresh element is created at a
/// fallback position using the ToolController text defaults.
///
/// v1.9.1 restyle: rounded-top-16 sheet, 16px w700 title, segmented font
/// grid, tabular size value beside the section title, 5-column color grid
/// with ringed selection, B/I/U toggle chips + align segmented, pill Apply.
Future<void> showTextSheet(BuildContext context, StrokeEngine engine,
    int pageId,
    {TextEl? existing}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _TextSheet(engine: engine, pageId: pageId, existing: existing),
    ),
  );
}

class _TextSheet extends StatefulWidget {
  const _TextSheet({
    required this.engine,
    required this.pageId,
    required this.existing,
  });

  final StrokeEngine engine;
  final int pageId;
  final TextEl? existing;

  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  late final TextEditingController _controller;

  late double _size;
  late TextFontId _font;
  late int _color;
  late bool _bold;
  late bool _italic;
  late bool _underline;
  late int _align;

  @override
  void initState() {
    super.initState();
    final tools = ToolController.I;
    final e = widget.existing;
    _controller = TextEditingController(text: e?.text ?? '');
    _size = e?.size ?? tools.textSize;
    _font = e?.font ?? tools.textFont;
    _color = e?.color ?? tools.textColor;
    _bold = e?.bold ?? tools.textBold;
    _italic = e?.italic ?? tools.textItalic;
    _underline = e?.underline ?? tools.textUnderline;
    _align = e?.align ?? tools.textAlign;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    final engine = widget.engine;
    final pageId = widget.pageId;
    final existing = widget.existing;
    if (text.isEmpty) {
      if (existing != null) {
        engine.removeElement(pageId, existing);
      }
    } else if (existing != null) {
      existing
        ..text = text
        ..size = _size
        ..font = _font
        ..color = _color
        ..bold = _bold
        ..italic = _italic
        ..underline = _underline
        ..align = _align;
      engine.updateElement(pageId, existing);
    } else {
      engine.addElement(
        pageId,
        TextEl(
          id: ElementIdGen.next(),
          z: 0,
          text: text,
          x: 100,
          y: 100,
          w: 220,
          size: _size,
          font: _font,
          color: _color,
          bold: _bold,
          italic: _italic,
          underline: _underline,
          align: _align,
        ),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  // ------------------------------------------------------------- sections

  Widget _sectionTitle(BuildContext context, String key, {String? value}) {
    final cs = nanoteColors(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              S.t(key),
              style: nanoteText(TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.mutedFg,
              )),
            ),
          ),
          if (value != null)
            Text(
              value,
              style: nanoteText(TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: cs.mutedFg,
              )),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = nanoteColors(context);
    final scheme = Theme.of(context).colorScheme;
    final previewSize = _size.clamp(10.0, 26.0).toDouble();
    final swatches = <int>{
      for (final c in INK_PALETTE.sublist(0, 10)) c.toARGB32(),
      _color,
    }.toList();

    Widget styleToggle(bool active, Widget child, String tooltip,
            VoidCallback onTap) =>
        Expanded(
          child: Tooltip(
            message: tooltip,
            child: Pressable(
              onTap: onTap,
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: active ? cs.accent : cs.surfaceVariant,
                  borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
                ),
                child: Center(child: child),
              ),
            ),
          ),
        );
    Color glyphColor(bool active) => active ? scheme.primary : cs.mutedFg;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.only(start: 20, end: 20, bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.t('textEdit'),
              style: nanoteText(TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              )),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: widget.existing == null,
              maxLines: null,
              minLines: 2,
              textAlign: _align == 1
                  ? TextAlign.center
                  : _align == 2
                      ? TextAlign.end
                      : TextAlign.start,
              style: TextStyle(
                color: Color(_color),
                fontSize: previewSize,
                fontFamily: _font.fontFamily,
                fontWeight: _bold ? FontWeight.w700 : FontWeight.w400,
                fontStyle: _italic ? FontStyle.italic : FontStyle.normal,
                decoration:
                    _underline ? TextDecoration.underline : TextDecoration.none,
              ),
              decoration: InputDecoration(hintText: S.t('textHint')),
            ),
            _sectionTitle(context, 'font'),
            _fontGrid(context),
            _sectionTitle(
                context, 'textSize', value: S.num(_size.round().toString())),
            SizedBox(
              height: 44,
              child: Slider(
                value: _size,
                min: 8,
                max: 72,
                divisions: 64,
                onChanged: (v) => setState(() => _size = v),
              ),
            ),
            _sectionTitle(context, 'textColor'),
            _colorGrid(context, swatches, cs, scheme),
            const SizedBox(height: 16),
            Row(
              children: [
                styleToggle(
                  _bold,
                  Text(
                    'B',
                    style: nanoteText(TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: glyphColor(_bold),
                    )),
                  ),
                  S.t('bold'),
                  () => setState(() => _bold = !_bold),
                ),
                const SizedBox(width: 8),
                styleToggle(
                  _italic,
                  Icon(LucideIcons.italic,
                      size: 18, color: glyphColor(_italic)),
                  S.t('italic'),
                  () => setState(() => _italic = !_italic),
                ),
                const SizedBox(width: 8),
                styleToggle(
                  _underline,
                  Icon(LucideIcons.underline,
                      size: 18, color: glyphColor(_underline)),
                  S.t('underline'),
                  () => setState(() => _underline = !_underline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _alignSegment(context),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(LucideIcons.check, size: 18),
                label: Text(S.t('done')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 3-column font grid (2 rows) on a surfaceVariant track; the selected
  /// font is lifted to the card surface (ink-1 shadow, primary label).
  Widget _fontGrid(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cs = nanoteColors(context);
    Widget tile(TextFontId f) => Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 2),
          child: Pressable(
            onTap: () => setState(() => _font = f),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: _font == f ? scheme.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
                boxShadow: _font == f ? cs.inkShadow1 : null,
              ),
              child: Center(
                child: Text(
                  S.t('font.${f.name}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: nanoteText(TextStyle(
                    fontSize: 12,
                    fontWeight: _font == f ? FontWeight.w700 : FontWeight.w600,
                    color: _font == f ? scheme.primary : cs.mutedFg,
                  )).copyWith(fontFamily: f.fontFamily),
                ),
              ),
            ),
          ),
        );
    const fonts = TextFontId.values;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (var i = 0; i < 3; i++) Expanded(child: tile(fonts[i])),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 3; i < 6; i++) Expanded(child: tile(fonts[i])),
            ],
          ),
        ],
      ),
    );
  }

  /// Exactly-5-column grid of 36px rounded-lg swatches (44px targets);
  /// selected = 2px primary border + ring.
  Widget _colorGrid(
      BuildContext context, List<int> values, NanoteColors cs, ColorScheme scheme) {
    Widget cell(int j, List<int> chunk) => Expanded(
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: j == 0 ? 0 : 3,
              end: j == 4 ? 0 : 3,
            ),
            child: j < chunk.length
                ? Pressable(
                    onTap: () => setState(() => _color = chunk[j]),
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(NANOTE_RADIUS),
                            border: Border.all(
                              width: 2,
                              color: chunk[j] == _color
                                  ? cs.ring.withValues(alpha: 0.45)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Color(chunk[j]),
                              borderRadius:
                                  BorderRadius.circular(NANOTE_RADIUS_MD),
                              border: Border.all(
                                width: chunk[j] == _color ? 2 : 1,
                                color: chunk[j] == _color
                                    ? scheme.primary
                                    : scheme.outline,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox(height: 44),
          ),
        );
    final rows = <Widget>[];
    for (var i = 0; i < values.length; i += 5) {
      final end = i + 5 > values.length ? values.length : i + 5;
      final chunk = values.sublist(i, end);
      rows.add(Row(
        children: [for (var j = 0; j < 5; j++) cell(j, chunk)],
      ));
      if (end < values.length) rows.add(const SizedBox(height: 6));
    }
    return Column(children: rows);
  }

  /// 3-icon start/center/end alignment segmented control.
  Widget _alignSegment(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cs = nanoteColors(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.surfaceVariant,
        borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
      ),
      child: Row(
        children: [
          for (var a = 0; a < 3; a++)
            Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: a == 0 ? 0 : 2,
                  end: a == 2 ? 0 : 2,
                ),
                child: Tooltip(
                  message: S.t(a == 0
                      ? 'alignStart'
                      : (a == 1 ? 'alignCenter' : 'alignEnd')),
                  child: Pressable(
                    onTap: () => setState(() => _align = a),
                    child: Container(
                      height: 34,
                      decoration: BoxDecoration(
                        color:
                            _align == a ? scheme.surface : Colors.transparent,
                        borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
                        boxShadow: _align == a ? cs.inkShadow1 : null,
                      ),
                      child: Center(
                        child: Icon(
                          a == 0
                              ? LucideIcons.text_align_start
                              : (a == 1
                                  ? LucideIcons.text_align_center
                                  : LucideIcons.text_align_end),
                          size: 15,
                          color: _align == a ? scheme.primary : cs.mutedFg,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
