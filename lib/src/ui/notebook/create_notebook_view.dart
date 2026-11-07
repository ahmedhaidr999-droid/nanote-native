import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../controllers/library_controller.dart';
import '../../i18n/strings.dart';
import '../../models/paper.dart';
import '../../persistence/file_store.dart';
import '../../theme/nanote_theme.dart';
import '../library/library_dialogs.dart' show TemplateChip;
import '../widgets/cover_art.dart';

/// Full-screen notebook creation flow ('/create'). Live 3:4 cover preview
/// (start side on wide screens, top on phones) beside section cards: name,
/// cover, template, page size (family + orientation) and paper color. Pops
/// with the created notebook — same [LibraryController.createNotebook] call
/// as before.
class CreateNotebookView extends StatefulWidget {
  const CreateNotebookView({super.key, this.folderId});

  final int? folderId;

  @override
  State<CreateNotebookView> createState() => _CreateNotebookViewState();
}

class _CreateNotebookViewState extends State<CreateNotebookView> {
  final TextEditingController _name = TextEditingController();

  String? _coverId = 'c1';
  String? _coverImagePath;
  TemplateId _template = TemplateId.blank;
  PageSizeId _pageSize = PageSizeId.a4Portrait;
  Color _paperColor = PAPER_COLORS.first;

  bool _valid = false;
  int? _folderId;
  bool _resolved = false;

  // The three page-size families, spec order A4 / A5 / Letter.
  static const List<String> _families = ['a4', 'a5', 'letter'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolved) return;
    _resolved = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    _folderId = widget.folderId ??
        (args is int ? args : null) ??
        LibraryController.I.currentFolderId;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canCreate => _name.text.trim().isNotEmpty;

  String get _family =>
      _pageSize.name.replaceFirst(RegExp('(Portrait|Landscape)\$'), '');

  /// §1 the fourth paper kind: the INFINITE paper.
  bool get _isInfinite => _pageSize == PageSizeId.infinityPaper;

  bool get _portrait => _pageSize.name.endsWith('Portrait');

  void _setSize(String family, bool portrait) => setState(
      () => _pageSize = PageSizeId.values
          .byName('$family${portrait ? 'Portrait' : 'Landscape'}'));

  Future<void> _create() async {
    if (!_canCreate) return;
    final nb = await LibraryController.I.createNotebook(
      title: _name.text.trim(),
      coverId: _coverId,
      coverImagePath: _coverImagePath,
      folderId: _folderId ?? LibraryController.I.currentFolderId,
      template: _template.index,
      pageSize: _pageSize.index,
      paperColor: _paperColor.toARGB32(),
    );
    if (mounted) Navigator.pop(context, nb);
  }

  Future<void> _pickCoverImage() async {
    // v1.0.0: file_picker 13 removed `FilePicker.platform` — pickFiles is
    // now static and returns a non-null list (empty when the user cancels).
    final files = await FilePicker.pickFiles(type: FileType.image);
    final path = files.isNotEmpty ? files.first.path : null;
    if (path == null) return;
    final rel = await FileStore.importFile(File(path), 'covers');
    if (!mounted) return;
    setState(() {
      _coverImagePath = rel;
      _coverId = null;
    });
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('newNotebook')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.t('cancel')),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        if (!wide) {
          // Phones: smaller preview on top, centered, form scrolls below.
          return ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 24),
            children: [
              Center(child: _coverPreview(context, 180)),
              const SizedBox(height: 16),
              ..._formCards(context),
            ],
          );
        }
        // Wide: sticky preview pinned to the START edge (flips in RTL),
        // form scrolls beside it.
        final h = (constraints.maxHeight - 32).clamp(180.0, 280.0);
        return Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: h * 3 / 4,
                height: double.infinity,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _coverPreview(context, h),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: ListView(
                  padding: const EdgeInsetsDirectional.only(bottom: 8),
                  children: _formCards(context),
                ),
              ),
            ],
          ),
        );
      }),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _valid ? _create : null,
              child: Text(S.t('create')),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------- live preview

  Widget _coverPreview(BuildContext context, double height) {
    final nc = nanoteColors(context);
    final width = height * 3 / 4;
    final radius = BorderRadius.circular(NANOTE_RADIUS_LG);
    final cover = coverById(_coverId);

    final Widget art;
    var nameColor = Colors.white;
    var shadowed = false;
    if (cover != null) {
      art = CoverArt(cover: cover, height: height);
      nameColor = cover.textColor;
    } else {
      // Custom image cover.
      shadowed = true;
      art = FutureBuilder<File?>(
        future: _coverImagePath == null
            ? Future.value(null)
            : FileStore.tryResolve(_coverImagePath!),
        builder: (context, snap) {
          final f = snap.data;
          if (f != null) {
            return Image.file(
              f,
              fit: BoxFit.cover,
              width: width,
              height: height,
              errorBuilder: (_, __, ___) => _previewFallback(context),
            );
          }
          return _previewFallback(context);
        },
      );
    }

    final hasName = _name.text.trim().isNotEmpty;
    final baseStyle = nanoteText(TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      height: 1.15,
      color: nameColor,
      shadows: shadowed
          ? const [Shadow(color: Colors.black38, blurRadius: 10)]
          : null,
    ));

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: nc.inkShadow1,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            art,
            PositionedDirectional(
              bottom: 14,
              start: 14,
              end: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasName ? _name.text.trim() : S.t('nameHint'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: hasName
                        ? baseStyle
                        : baseStyle.copyWith(
                            color: nameColor.withValues(alpha: 0.6),
                          ),
                  ),
                  const SizedBox(height: 8),
                  // Selected paper color as a subtle strip under the name.
                  Container(
                    width: 34,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _paperColor,
                      borderRadius: BorderRadius.circular(999),
                      border:
                          Border.all(color: Colors.white.withValues(alpha: .4)),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 2)
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewFallback(BuildContext context) {
    final nc = nanoteColors(context);
    return Container(
      color: nc.surfaceVariant,
      alignment: Alignment.center,
      child: Icon(LucideIcons.image_off, size: 24, color: nc.mutedFg),
    );
  }

  // ----------------------------------------------------------- form cards

  List<Widget> _formCards(BuildContext context) {
    return [
      _section(context, S.t('notebookName'), [
        TextField(
          controller: _name,
          decoration: InputDecoration(hintText: S.t('nameHint')),
          style: nanoteText(const TextStyle(fontSize: 15)),
          // Rebuild on EVERY keystroke — the live cover preview shows the
          // name as typed (only rebuilding on validity flips froze the
          // preview after the first character).
          onChanged: (_) => setState(() => _valid = _canCreate),
        ),
      ]),
      _section(context, S.t('covers'), [
        Wrap(
          spacing: 10,
          runSpacing: 12,
          children: [
            for (final cover in BUILTIN_COVERS) _coverSwatch(context, cover),
            _customCoverSwatch(context),
          ],
        ),
        const SizedBox(height: 10),
        _selectedCoverCaption(context),
      ]),
      _section(context, S.t('paperTemplate'), [
        Wrap(
          spacing: 8,
          runSpacing: 12,
          children: [
            for (final t in TemplateId.values)
              TemplateChip(
                template: t,
                selected: _template == t,
                onTap: () => setState(() => _template = t),
              ),
          ],
        ),
      ]),
      _section(context, S.t('pageSize'), [
        Row(
          children: [
            for (final family in _families) ...[
              Expanded(child: _familyCard(context, family)),
              const SizedBox(width: 8),
            ],
            Expanded(child: _infinityCard(context)),
          ],
        ),
        const SizedBox(height: 12),
        // §1 infinite paper has no orientation — show its hint instead.
        if (_isInfinite)
          _infinityHint(context)
        else
          _orientationToggle(context),
      ]),
      _section(context, S.t('paperColor'), [
        Wrap(
          spacing: 10,
          runSpacing: 12,
          children: [
            for (final col in PAPER_COLORS) _paperSwatch(context, col),
          ],
        ),
      ]),
    ];
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
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
          Text(
            title,
            style: nanoteText(TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: nc.mutedFg,
            )),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  // -------------------------------------------------------------- covers

  Widget _coverSwatch(BuildContext context, CoverDef cover) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    final selected = _coverId == cover.id && _coverImagePath == null;
    return Pressable(
      onTap: () => setState(() {
        _coverId = cover.id;
        _coverImagePath = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM + 3),
          border: Border.all(
            color: selected ? cs.primary : cs.outline,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected ? nc.inkShadow1 : const <BoxShadow>[],
        ),
        child: SizedBox(
          width: 54,
          height: 72,
          child: CoverArt(
            cover: cover,
            width: 54,
            borderRadius: NANOTE_RADIUS_SM,
          ),
        ),
      ),
    );
  }

  Widget _customCoverSwatch(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    final selected = _coverImagePath != null;
    final Widget inner;
    if (selected) {
      inner = FutureBuilder<File?>(
        future: FileStore.tryResolve(_coverImagePath!),
        builder: (context, snap) {
          final f = snap.data;
          if (f != null) {
            return Image.file(
              f,
              fit: BoxFit.cover,
              width: 54,
              height: 72,
              errorBuilder: (_, __, ___) => _customCoverPlaceholder(context),
            );
          }
          return _customCoverPlaceholder(context);
        },
      );
    } else {
      inner = _customCoverPlaceholder(context);
    }
    return Pressable(
      onTap: _pickCoverImage,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM + 3),
          border: Border.all(
            color: selected ? cs.primary : cs.outline,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected ? nc.inkShadow1 : const <BoxShadow>[],
        ),
        child: Container(
          width: 54,
          height: 72,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: nc.surfaceVariant,
            borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
          ),
          child: selected
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    inner,
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.check,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                )
              : inner,
        ),
      ),
    );
  }

  Widget _customCoverPlaceholder(BuildContext context) {
    final nc = nanoteColors(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(LucideIcons.image_plus, size: 20, color: nc.mutedFg),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Text(
            S.t('coverCustom'),
            maxLines: 1,
            overflow: TextOverflow.clip,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9, color: nc.mutedFg),
          ),
        ),
      ],
    );
  }

  Widget _selectedCoverCaption(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    final cover = coverById(_coverId);
    final label =
        cover != null ? S.t(cover.nameKey) : S.t('coverCustom');
    return Row(
      children: [
        Icon(LucideIcons.check, size: 14, color: cs.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: nanoteText(TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: nc.mutedFg,
            )),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------- page size

  /// §1 The INFINITE paper card: «794 × ∞» with the continuous-scroll
  /// hint when selected.
  Widget _infinityCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    final selected = _isInfinite;
    return Pressable(
      onTap: () => setState(() => _pageSize = PageSizeId.infinityPaper),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? nc.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(NANOTE_RADIUS),
          border: Border.all(
            color: selected ? cs.primary : cs.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.infinity,
                  size: 16,
                  color: selected ? nc.accentFg : cs.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    S.t('size.infinity'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: nanoteText(TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected ? nc.accentFg : cs.onSurface,
                    )),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${S.num(794)} × ∞',
              style: nanoteText(TextStyle(
                fontSize: 11,
                color: selected
                    ? nc.accentFg.withValues(alpha: 0.8)
                    : nc.mutedFg,
              )),
            ),
          ],
        ),
      ),
    );
  }

  /// §1 the hint shown while the infinite paper is selected.
  Widget _infinityHint(BuildContext context) {
    final nc = nanoteColors(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: nc.surfaceVariant,
        borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.infinity, size: 14, color: nc.mutedFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              S.t('size.infinityHint'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: nanoteText(TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: nc.mutedFg,
              )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _familyCard(BuildContext context, String family) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    final selected = _family == family;
    final def = PAGE_SIZES[
        PageSizeId.values.byName('${family}Portrait')]!;
    final label =
        family == 'a4' ? 'A4' : (family == 'a5' ? 'A5' : 'Letter');
    return Pressable(
      onTap: () => _setSize(family, _portrait),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? nc.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(NANOTE_RADIUS),
          border: Border.all(
            color: selected ? cs.primary : cs.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.file,
                  size: 16,
                  color: selected ? nc.accentFg : cs.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: nanoteText(TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selected ? nc.accentFg : cs.onSurface,
                    )),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${S.num(def.w.toInt())} × ${S.num(def.h.toInt())}',
              style: nanoteText(TextStyle(
                fontSize: 11,
                color: selected
                    ? nc.accentFg.withValues(alpha: 0.8)
                    : nc.mutedFg,
              )),
            ),
          ],
        ),
      ),
    );
  }

  /// Portrait / landscape words derived from the localized size names
  /// ("A4 Portrait" → "Portrait", "A4 طولي" → "طولي") — no dedicated keys.
  String _orientLabel(bool portrait) => S
      .t('size.a4${portrait ? 'Portrait' : 'Landscape'}')
      .replaceFirst(RegExp(r'^\S+\s*'), '');

  Widget _orientationToggle(BuildContext context) {
    final nc = nanoteColors(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: nc.surfaceVariant,
        borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segChip(
              context,
              icon: LucideIcons.rectangle_vertical,
              label: _orientLabel(true),
              selected: _portrait,
              onTap: () => _setSize(_family, true),
            ),
          ),
          Expanded(
            child: _segChip(
              context,
              icon: LucideIcons.rectangle_horizontal,
              label: _orientLabel(false),
              selected: !_portrait,
              onTap: () => _setSize(_family, false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segChip(
    BuildContext context, {
    IconData? icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? cs.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
          border: selected ? Border.all(color: cs.outline) : null,
          boxShadow: selected ? nc.inkShadow1 : const <BoxShadow>[],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 15, color: selected ? cs.primary : nc.mutedFg),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: nanoteText(TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? cs.primary : nc.mutedFg,
                )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------- paper color

  Widget _paperSwatch(BuildContext context, Color color) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    final selected = color == _paperColor;
    return Pressable(
      onTap: () => setState(() => _paperColor = color),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
          border: Border.all(
            color: selected ? cs.primary : cs.outline,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: nc.ring.withValues(alpha: 0.28),
                    blurRadius: 6,
                    spreadRadius: 1,
                  )
                ]
              : const <BoxShadow>[],
        ),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
          ),
        ),
      ),
    );
  }
}
