import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../persistence/file_store.dart';
import '../../theme/nanote_theme.dart';

/// The 8 built-in stickers (non-deletable), drawn with simple icons.
const List<IconData> _builtinStickerIcons = [
  Icons.favorite,
  Icons.star,
  Icons.sentiment_satisfied,
  Icons.check,
  Icons.close,
  Icons.arrow_forward,
  Icons.lightbulb,
  Icons.flag,
];

/// Sticker manager ('/stickers'): user PNG stickers grid with import
/// (FilePicker) and delete (long-press, with confirm), plus the 8 built-in
/// stickers at the top as a non-deletable section.
class StickerManagerView extends StatefulWidget {
  const StickerManagerView({super.key});

  @override
  State<StickerManagerView> createState() => _StickerManagerViewState();
}

class _StickerManagerViewState extends State<StickerManagerView> {
  List<String> _stickers = [];

  /// Resolved sticker file cache (avoids re-hitting the disk on rebuilds).
  final Map<String, Future<File?>> _fileFutures = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await FileStore.listStickers();
    if (!mounted) return;
    setState(() {
      _stickers = list;
      _fileFutures.removeWhere((k, v) => !list.contains(k));
    });
  }

  Future<void> _import() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png'],
    );
    final files = res?.files;
    final path = (files != null && files.isNotEmpty) ? files.first.path : null;
    if (path == null) return;
    await FileStore.importFile(File(path), 'stickers');
    await _reload();
  }

  Future<void> _delete(String rel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.t('deleteSticker')),
        content: Text(S.t('confirmDeleteSticker')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.t('delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await FileStore.deleteRelative(rel);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final nc = nanoteColors(context);
    return Scaffold(
      appBar: AppBar(title: Text(S.t('stickerManager'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _import,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(S.t('importSticker')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Text(
              S.t('tool.sticker'),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final icon in _builtinStickerIcons)
                    _builtinCell(context, icon),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_stickers.isEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.emoji_emotions_outlined,
                        size: 40, color: nc.mutedFg),
                    const SizedBox(height: 10),
                    Text(
                      S.t('noCustomStickers'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: nc.mutedFg),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final rel in _stickers) _userCell(context, rel),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 88),
        ],
      ),
    );
  }

  Widget _builtinCell(BuildContext context, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: cs.secondary,
        border: Border.all(color: cs.outline),
      ),
      child:
          Icon(icon, size: 30, color: cs.primary),
    );
  }

  Widget _userCell(BuildContext context, String rel) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _delete(rel),
      child: Container(
        width: 64,
        height: 64,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outline),
        ),
        child: FutureBuilder<File?>(
          future:
              _fileFutures.putIfAbsent(rel, () => FileStore.tryResolve(rel)),
          builder: (context, snap) {
            final f = snap.data;
            if (f != null) {
              return Image.file(
                f,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined,
                    color: nc.mutedFg),
              );
            }
            return Icon(Icons.image_outlined, color: nc.mutedFg);
          },
        ),
      ),
    );
  }
}
