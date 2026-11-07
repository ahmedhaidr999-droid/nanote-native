import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../controllers/stroke_engine.dart';
import '../../i18n/strings.dart';
import '../../models/page_elements.dart';
import '../../persistence/file_store.dart';
import '../../theme/nanote_theme.dart';

/// Sticker picker: 8 built-in vector stickers + the user's imported PNGs
/// (FileStore `stickers/`). Tapping inserts a 96×96 ImageEl centered on
/// [centerDoc].
///
/// v1.9.1 restyle: rounded-12 accent tiles with press feedback, pill import
/// button, Lucide icons.
Future<void> showStickerPicker(
    BuildContext context, StrokeEngine engine, int pageId, Offset centerDoc) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _StickerPicker(
      engine: engine,
      pageId: pageId,
      centerDoc: centerDoc,
    ),
  );
}

const List<(String, IconData)> _builtinStickers = [
  ('heart', LucideIcons.heart),
  ('star', LucideIcons.star),
  ('smiley', LucideIcons.face_grinning),
  ('check', LucideIcons.circle_check_big),
  ('cross', LucideIcons.circle_x),
  ('arrow', LucideIcons.circle_arrow_right),
  ('bulb', LucideIcons.lightbulb),
  ('flag', LucideIcons.flag),
];

class _StickerPicker extends StatefulWidget {
  const _StickerPicker({
    required this.engine,
    required this.pageId,
    required this.centerDoc,
  });

  final StrokeEngine engine;
  final int pageId;
  final Offset centerDoc;

  @override
  State<_StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<_StickerPicker> {
  late Future<List<String>> _stickers;

  /// Resolved sticker files by relative path — memoized so the per-cell
  /// FutureBuilder does NOT re-run FileStore.tryResolve (file IO) on every
  /// rebuild, which used to flash the missing-image placeholder.
  final Map<String, Future<File?>> _resolved = {};

  @override
  void initState() {
    super.initState();
    _stickers = FileStore.listStickers();
  }

  Future<File?> _resolve(String rel) =>
      _resolved.putIfAbsent(rel, () => FileStore.tryResolve(rel));

  void _insert({String? builtinId, String? src}) {
    widget.engine.addElement(
      widget.pageId,
      ImageEl(
        id: ElementIdGen.next(),
        z: 0,
        builtinId: builtinId,
        src: src,
        x: widget.centerDoc.dx - 48,
        y: widget.centerDoc.dy - 48,
        w: 96,
        h: 96,
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _import() async {
    // v1.0.0: file_picker 13 — static pickFiles, non-null list.
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png'],
    );
    final path = result.isNotEmpty ? result.first.path : null;
    if (path == null) return;
    try {
      await FileStore.importFile(File(path), 'stickers');
    } catch (_) {
      return;
    }
    if (mounted) {
      setState(() => _stickers = FileStore.listStickers());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = nanoteColors(context);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.only(start: 20, end: 20, bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.t('stickerPicker'),
              style: nanoteText(TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              )),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (id, icon) in _builtinStickers)
                  Pressable(
                    onTap: () => _insert(builtinId: id),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: cs.accent,
                        borderRadius: BorderRadius.circular(NANOTE_RADIUS),
                      ),
                      child: Icon(icon, size: 30, color: cs.accentFg),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _import,
              icon: const Icon(LucideIcons.image_plus, size: 18),
              label: Text(S.t('importSticker')),
            ),
            const SizedBox(height: 14),
            FutureBuilder<List<String>>(
              future: _stickers,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 72,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final stickers = snapshot.data ?? const <String>[];
                if (stickers.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      S.t('noCustomStickers'),
                      style: nanoteText(
                          TextStyle(color: cs.mutedFg, fontSize: 13)),
                    ),
                  );
                }
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final rel in stickers) _userCell(context, rel, cs),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _userCell(BuildContext context, String rel, NanoteColors cs) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<File?>(
      future: _resolve(rel),
      builder: (context, snapshot) {
        final file = snapshot.data;
        return Pressable(
          onTap: file != null ? () => _insert(src: rel) : null,
          child: Container(
            width: 64,
            height: 64,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(NANOTE_RADIUS),
              border: Border.all(color: scheme.outline),
            ),
            child: file == null
                ? Icon(LucideIcons.image_off, size: 24, color: cs.mutedFg)
                : Image.file(
                    file,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Icon(LucideIcons.image_off, size: 24, color: cs.mutedFg),
                  ),
          ),
        );
      },
    );
  }
}
