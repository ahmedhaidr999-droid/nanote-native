import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final cs = nanoteColors(context);
    final primary = Theme.of(context).colorScheme.primary;
    final previewSize = _size.clamp(10.0, 26.0).toDouble();
    final swatches = <int>{
      for (final c in INK_PALETTE.sublist(0, 10)) c.toARGB32(),
      _color,
    }.toList();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.t('textEdit'),
                style: Theme.of(context).textTheme.titleMedium),
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
            const SizedBox(height: 12),
            Text(S.t('font'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final f in TextFontId.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          S.t('font.${f.name}'),
                          style: TextStyle(fontFamily: f.fontFamily),
                        ),
                        selected: _font == f,
                        onSelected: (_) => setState(() => _font = f),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(S.t('textSize')),
                Expanded(
                  child: Slider(
                    value: _size,
                    min: 8,
                    max: 72,
                    divisions: 64,
                    label: S.num(_size.round()),
                    onChanged: (v) => setState(() => _size = v),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    S.num(_size.round()),
                    textAlign: TextAlign.end,
                    style: TextStyle(color: cs.mutedFg),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(S.t('textColor'),
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in swatches)
                  _colorDot(context, v, primary),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: S.t('bold'),
                  icon: const Icon(Icons.format_bold),
                  color: _bold ? primary : cs.mutedFg,
                  onPressed: () => setState(() => _bold = !_bold),
                ),
                IconButton(
                  tooltip: S.t('italic'),
                  icon: const Icon(Icons.format_italic),
                  color: _italic ? primary : cs.mutedFg,
                  onPressed: () => setState(() => _italic = !_italic),
                ),
                IconButton(
                  tooltip: S.t('underline'),
                  icon: const Icon(Icons.format_underline),
                  color: _underline ? primary : cs.mutedFg,
                  onPressed: () => setState(() => _underline = !_underline),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: S.t('alignStart'),
                  icon: const Icon(Icons.format_align_left),
                  color: _align == 0 ? primary : cs.mutedFg,
                  onPressed: () => setState(() => _align = 0),
                ),
                IconButton(
                  tooltip: S.t('alignCenter'),
                  icon: const Icon(Icons.format_align_center),
                  color: _align == 1 ? primary : cs.mutedFg,
                  onPressed: () => setState(() => _align = 1),
                ),
                IconButton(
                  tooltip: S.t('alignEnd'),
                  icon: const Icon(Icons.format_align_right),
                  color: _align == 2 ? primary : cs.mutedFg,
                  onPressed: () => setState(() => _align = 2),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: Text(S.t('done')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorDot(BuildContext context, int value, Color primary) {
    final selected = value == _color;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => setState(() => _color = value),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Container(
            width: selected ? 38 : 32,
            height: selected ? 38 : 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(value),
              border: Border.all(
                width: selected ? 2.5 : 1,
                color: selected ? primary : const Color(0x33000000),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
