import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../i18n/strings.dart';
import '../../persistence/file_store.dart';
import '../../theme/nanote_theme.dart';

/// The 8 built-in stickers (non-deletable), drawn with simple icons.
const List<IconData> _builtinStickerIcons = [
  LucideIcons.heart,
  LucideIcons.star,
  LucideIcons.face_grinning,
  LucideIcons.check,
  LucideIcons.x,
  LucideIcons.arrow_right,
  LucideIcons.lightbulb,
  LucideIcons.flag,
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
    try {
      // v1.0.0: file_picker 13 — static pickFiles, non-null list.
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png'],
      );
      final path = files.isNotEmpty ? files.first.path : null;
      if (path == null) return;
      await FileStore.importFile(File(path), 'stickers');
      await _reload();
    } catch (e, st) {
      // Picker / copy failures (unreadable source, storage full) must not
      // surface as unhandled async errors — log and keep the old grid.
      debugPrint('StickerManagerView: import failed: $e\n$st');
    }
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
        icon: const Icon(LucideIcons.image_plus),
        label: Text(S.t('importSticker')),
      ),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 100),
        children: [
          _section(
            context,
            icon: LucideIcons.sticker,
            title: S.t('tool.sticker'),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final icon in _builtinStickerIcons)
                  _builtinCell(context, icon),
              ],
            ),
          ),
          _section(
            context,
            icon: LucideIcons.image_plus,
            title: S.t('customStickers'),
            child: _stickers.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      children: [
                        Icon(LucideIcons.face_grinning,
                            size: 40, color: nc.mutedFg),
                        const SizedBox(height: 10),
                        Text(
                          S.t('noCustomStickers'),
                          textAlign: TextAlign.center,
                          style: nanoteText(TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: nc.mutedFg)),
                        ),
                      ],
                    ),
                  )
                : Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final rel in _stickers) _userCell(context, rel),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- section card

  Widget _section(
    BuildContext context, {
    IconData? icon,
    required String title,
    required Widget child,
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
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- cells

  Widget _builtinCell(BuildContext context, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
        color: cs.secondary,
        border: Border.all(color: cs.outline),
      ),
      child: Icon(icon, size: 28, color: cs.primary),
    );
  }

  Widget _userCell(BuildContext context, String rel) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return Pressable(
      onLongPress: () => _delete(rel),
      child: Container(
        width: 64,
        height: 64,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
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
                errorBuilder: (_, __, ___) =>
                    Icon(LucideIcons.image_off, color: nc.mutedFg),
              );
            }
            return Icon(LucideIcons.image, color: nc.mutedFg);
          },
        ),
      ),
    );
  }
}
