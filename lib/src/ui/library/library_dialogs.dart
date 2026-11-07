import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../controllers/library_controller.dart';
import '../../i18n/strings.dart';
import '../../models/paper.dart';
import '../../persistence/file_store.dart';
import '../../persistence/library_repository.dart';
import '../../theme/nanote_theme.dart';
import '../widgets/cover_art.dart';

/// Fixed 8-color row used by the tab picker.
const List<Color> kPickerColors = [
  Color(0xFF1E6FF2),
  Color(0xFF0E7A5F),
  Color(0xFF9333EA),
  Color(0xFFE5484D),
  Color(0xFFC2410C),
  Color(0xFFCA8A04),
  Color(0xFFDB2777),
  Color(0xFF5A6B85),
];

/// Emoji choices for folders and tabs.
const List<String> kEmojiChoices = [
  '📁', '📂', '📓', '📘', '📗', '📕', '📙', '📝', '💡', '⭐', '🎯', '🧠',
];

// ---------------------------------------------------------------------------
// Reusable picker widgets
// ---------------------------------------------------------------------------

/// A circular color swatch with a selection check.
class ColorDot extends StatelessWidget {
  const ColorDot({
    super.key,
    required this.color,
    this.selected = false,
    this.size = 32,
    this.onTap,
  });

  final Color color;
  final bool selected;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(
          color: selected ? cs.primary : nc.mutedFg.withValues(alpha: 0.35),
          width: selected ? 2.5 : 1,
        ),
      ),
      child: selected
          ? Center(
              child: Icon(
                LucideIcons.check,
                size: size * 0.45,
                color: color.computeLuminance() > 0.5
                    ? const Color(0xFF16233A)
                    : Colors.white,
              ),
            )
          : null,
    );
    if (onTap == null) return dot;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: EdgeInsets.all(math.max(0.0, (44 - size) / 2)),
        child: dot,
      ),
    );
  }
}

/// A paper-template picker chip with a tiny live preview.
class TemplateChip extends StatelessWidget {
  const TemplateChip({
    super.key,
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final TemplateId template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 66,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
              border: Border.all(
                color: selected ? cs.primary : cs.outline,
                width: selected ? 2 : 1,
              ),
            ),
            child: CustomPaint(
              painter: _TemplatePreviewPainter(template),
              size: const Size(52, 66),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            S.t(template.key),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? cs.primary : nc.mutedFg,
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplatePreviewPainter extends CustomPainter {
  _TemplatePreviewPainter(this.template);

  final TemplateId template;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    final line = Paint()
      ..color = const Color(0x4D5A6B85)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    void hLine(double y, [Paint? p]) =>
        canvas.drawLine(Offset(4, y), Offset(w - 4, y), p ?? line);
    void vLine(double x, [Paint? p]) =>
        canvas.drawLine(Offset(x, 4), Offset(x, h - 4), p ?? line);

    switch (template) {
      case TemplateId.blank:
        break;
      case TemplateId.ruled:
        for (var y = 12.0; y <= h - 10; y += 10) {
          hLine(y);
        }
        break;
      case TemplateId.college:
        for (var y = 12.0; y <= h - 10; y += 10) {
          hLine(y);
        }
        vLine(
          12,
          Paint()
            ..color = const Color(0x66E5484D)
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke,
        );
        break;
      case TemplateId.grid:
        for (var x = 12.0; x <= w - 6; x += 10) {
          vLine(x);
        }
        for (var y = 12.0; y <= h - 10; y += 10) {
          hLine(y);
        }
        break;
      case TemplateId.dots:
        final dot = Paint()
          ..color = const Color(0x805A6B85)
          ..style = PaintingStyle.fill;
        for (var x = 10.0; x <= w - 6; x += 10) {
          for (var y = 12.0; y <= h - 8; y += 10) {
            canvas.drawCircle(Offset(x, y), 1, dot);
          }
        }
        break;
      case TemplateId.graph:
        for (var x = 9.0; x <= w - 5; x += 7) {
          vLine(x);
        }
        for (var y = 9.0; y <= h - 6; y += 7) {
          hLine(y);
        }
        break;
      case TemplateId.isometric:
        for (var x = -h; x < w; x += 11) {
          canvas.drawLine(Offset(x, h - 2), Offset(x + h * 0.6, 2), line);
          canvas.drawLine(Offset(x, 2), Offset(x + h * 0.6, h - 2), line);
        }
        break;
      case TemplateId.hex:
        const r = 7.0;
        final dx = math.sqrt(3) * r;
        const dy = r * 1.5;
        var row = 0;
        for (var cy = 6.0; cy < h - 4; cy += dy) {
          final offset = row.isOdd ? dx / 2 : 0.0;
          for (var cx = 6.0 + offset; cx < w - 4; cx += dx) {
            final path = Path();
            for (var i = 0; i < 6; i++) {
              final a = math.pi / 3 * i;
              final pt = Offset(
                cx + r * math.sin(a),
                cy + r * math.cos(a),
              );
              if (i == 0) {
                path.moveTo(pt.dx, pt.dy);
              } else {
                path.lineTo(pt.dx, pt.dy);
              }
            }
            path.close();
            canvas.drawPath(path, line);
          }
          row++;
        }
        break;
      case TemplateId.staff:
        for (final base in [16.0, 42.0]) {
          for (var i = 0; i < 5; i++) {
            hLine(base + i * 3.5);
          }
        }
        break;
      case TemplateId.crossGrid:
        for (var x = 10.0; x <= w - 6; x += 11) {
          for (var y = 12.0; y <= h - 8; y += 11) {
            canvas.drawLine(Offset(x - 2.5, y), Offset(x + 2.5, y), line);
            canvas.drawLine(Offset(x, y - 2.5), Offset(x, y + 2.5), line);
          }
        }
        break;
      case TemplateId.diagonal:
        for (var x = -h; x < w; x += 10) {
          canvas.drawLine(Offset(x, h - 2), Offset(x + h * 0.75, 2), line);
        }
        break;
      case TemplateId.manuscript:
        for (var y = 16.0; y <= h - 10; y += 14) {
          hLine(y);
          for (var x = 5.0; x < w - 6; x += 6) {
            canvas.drawLine(Offset(x, y - 5), Offset(x + 3, y - 5), line);
          }
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _TemplatePreviewPainter oldDelegate) =>
      oldDelegate.template != template;
}

// ---------------------------------------------------------------------------
// Sheet / dialog scaffolding
// ---------------------------------------------------------------------------

/// Nanote bottom-sheet scaffold: rounded top (16), ink-2 floating shadow and
/// a slim drag handle. Show with `showModalBottomSheet(backgroundColor:
/// Colors.transparent, showDragHandle: false)`.
class NanoteSheet extends StatelessWidget {
  const NanoteSheet({super.key, required this.child, this.title});

  final Widget child;

  /// Optional bold sheet title under the drag handle.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nc = nanoteColors(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(NANOTE_RADIUS_LG),
        ),
        boxShadow: nc.inkShadow2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: nc.mutedFg.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 10),
              child: Text(
                title!,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// A 52px-tall sheet/menu row: leading icon on an accent tile + bold label.
/// Destructive rows tint icon and label with the error color.
Widget sheetActionRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  required VoidCallback onTap,
  bool destructive = false,
}) {
  final cs = Theme.of(context).colorScheme;
  final nc = nanoteColors(context);
  final fg = destructive ? cs.error : nc.secondaryFg;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(NANOTE_RADIUS),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NANOTE_RADIUS),
        hoverColor: nc.accent,
        splashColor: nc.accent,
        highlightColor: nc.accent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: destructive
                      ? cs.error.withValues(alpha: 0.10)
                      : nc.accent,
                  borderRadius: BorderRadius.circular(NANOTE_RADIUS_MD),
                ),
                child:
                    Icon(icon, size: 20, color: destructive ? cs.error : cs.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Standard confirmation dialog (pill CTA; destructive confirm uses the
/// error color on the filled button). Pops with `true` when confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmKey = 'delete',
  bool destructive = true,
}) async {
  final cs = Theme.of(context).colorScheme;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(S.t('cancel')),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: cs.onError,
                    )
                  : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(S.t(confirmKey)),
            ),
          ],
        ),
      ) ==
      true;
}

// ---------------------------------------------------------------------------
// Shared create-notebook form
// ---------------------------------------------------------------------------

/// The full set of create-notebook fields (name, cover, template, page size,
/// paper color). Read the current values through a
/// `GlobalKey<NotebookFormFieldsState>`.
class NotebookFormFields extends StatefulWidget {
  const NotebookFormFields({super.key, this.onValidityChanged});

  /// Notified with "title is non-empty" on every name change.
  final ValueChanged<bool>? onValidityChanged;

  @override
  State<NotebookFormFields> createState() => NotebookFormFieldsState();
}

class NotebookFormFieldsState extends State<NotebookFormFields> {
  final TextEditingController _name = TextEditingController();
  String? _coverId = 'c1';
  String? _coverImagePath;
  TemplateId _template = TemplateId.blank;
  PageSizeId _pageSize = PageSizeId.a4Portrait;
  Color _paperColor = PAPER_COLORS.first;

  String get title => _name.text.trim();
  String? get coverId => _coverId;
  String? get coverImagePath => _coverImagePath;
  int get template => _template.index;
  int get pageSize => _pageSize.index;
  int get paperColor => _paperColor.toARGB32();
  bool get canCreate => title.isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: S.t('notebookName'),
            hintText: S.t('nameHint'),
          ),
          onChanged: (_) => widget.onValidityChanged?.call(canCreate),
        ),
        const SizedBox(height: 20),
        _label(context, S.t('chooseCover')),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final cover in BUILTIN_COVERS) _coverChip(context, cover),
            _customCoverChip(context),
          ],
        ),
        const SizedBox(height: 20),
        _label(context, S.t('paperTemplate')),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: [
            for (final t in TemplateId.values)
              TemplateChip(
                template: t,
                selected: _template == t,
                onTap: () => setState(() => _template = t),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _label(context, S.t('pageSize')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // §1 the INFINITE paper is a notebook-creation kind, not a
            // per-page size — keep it out of this dialog.
            for (final ps in PageSizeId.values
                .where((p) => p != PageSizeId.infinityPaper))
              ChoiceChip(
                label: Text(S.t('size.${ps.name}')),
                selected: _pageSize == ps,
                onSelected: (_) => setState(() => _pageSize = ps),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _label(context, S.t('paperColor')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final col in PAPER_COLORS)
              ColorDot(
                color: col,
                selected: col == _paperColor,
                onTap: () => setState(() => _paperColor = col),
              ),
          ],
        ),
      ],
    );
  }

  Widget _label(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: nanoteColors(context).mutedFg,
        ),
      ),
    );
  }

  Widget _coverChip(BuildContext context, CoverDef cover) {
    final cs = Theme.of(context).colorScheme;
    final selected = _coverId == cover.id && _coverImagePath == null;
    return Pressable(
      onTap: () => setState(() {
        _coverId = cover.id;
        _coverImagePath = null;
      }),
      child: Container(
        width: 52,
        height: 68,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
              child: CoverArt(cover: cover, borderRadius: NANOTE_RADIUS_SM),
            ),
            if (selected)
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
        ),
      ),
    );
  }

  Widget _customCoverChip(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
              width: 52,
              height: 68,
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
      child: Container(
        width: 52,
        height: 68,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
          child: SizedBox(
            width: 47,
            height: 63,
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
      ),
    );
  }

  Widget _customCoverPlaceholder(BuildContext context) {
    final nc = nanoteColors(context);
    return ColoredBox(
      color: nc.surfaceVariant,
      child: Column(
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
              style: TextStyle(fontSize: 9, color: nc.mutedFg),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialogs / sheets
// ---------------------------------------------------------------------------

/// Small pill chip used for breadcrumbs and folder chips.
Widget _pill(
  BuildContext context, {
  required String label,
  IconData? icon,
  required bool highlighted,
  VoidCallback? onTap,
  VoidCallback? onLongPress,
}) {
  final cs = Theme.of(context).colorScheme;
  final nc = nanoteColors(context);
  final bg = highlighted ? nc.accent : nc.surfaceVariant;
  final fg = highlighted ? cs.primary : nc.secondaryFg;
  return Pressable(
    onTap: onTap,
    onLongPress: onLongPress,
    enabled: onTap != null || onLongPress != null,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The create-notebook quick sheet. Pops with the created [NotebookEntity]
/// so the caller can open the editor right away.
Future<NotebookEntity?> showCreateNotebookSheet(
  BuildContext context, {
  int? folderId,
}) async {
  final key = GlobalKey<NotebookFormFieldsState>();
  return showModalBottomSheet<NotebookEntity>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setSheet) {
          return NanoteSheet(
            title: S.t('newNotebook'),
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      NotebookFormFields(
                        key: key,
                        onValidityChanged: (_) => setSheet(() {}),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed:
                            (key.currentState?.canCreate ?? false)
                                ? () async {
                                    final state = key.currentState;
                                    if (state == null) return;
                                    final nb =
                                        await LibraryController.I.createNotebook(
                                      title: state.title,
                                      coverId: state.coverId,
                                      coverImagePath: state.coverImagePath,
                                      folderId: folderId ??
                                          LibraryController.I.currentFolderId,
                                      template: state.template,
                                      pageSize: state.pageSize,
                                      paperColor: state.paperColor,
                                    );
                                    if (context.mounted) {
                                      Navigator.pop(context, nb);
                                    }
                                  }
                                : null,
                        child: Text(S.t('create')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

/// Generic rename dialog (notebooks / folders / tabs / tags).
Future<void> showRenameDialog(
  BuildContext context,
  String initial,
  String titleKey,
  Future<void> Function(String) onConfirm,
) async {
  final controller = TextEditingController(text: initial);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(S.t(titleKey)),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: S.t('nameHint')),
        onSubmitted: (v) => Navigator.pop(context, v.trim().isNotEmpty),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(S.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(S.t('save')),
        ),
      ],
    ),
  );
  if (ok == true) {
    final name = controller.text.trim();
    if (name.isNotEmpty) await onConfirm(name);
  }
  controller.dispose();
}

/// Folder tree picker for moving a notebook. The sheet browses via the
/// controller's own navigation state (breadcrumbs + child folder chips),
/// offers "no folder", inline folder creation and a "move here" action.
Future<void> showMoveToFolderSheet(
  BuildContext context,
  NotebookEntity n,
) async {
  final c = LibraryController.I;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (context) => ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final nc = nanoteColors(context);
        final children = c.childFolders(c.currentFolderId);
        return SafeArea(
          child: NanoteSheet(
            title: S.t('moveTo'),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _breadcrumbChips(context, c),
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: children.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              S.t('emptyLibraryHint'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 13, color: nc.mutedFg),
                            ),
                          )
                        : ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            children: [
                              for (final f in children)
                                ListTile(
                                  leading: Text(
                                    f.emoji,
                                    style: const TextStyle(fontSize: 22),
                                  ),
                                  title: Text(
                                    f.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: _dirChevron(context),
                                  onTap: () => c.enterFolder(f.id),
                                ),
                            ],
                          ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await c.moveNotebook(n, null);
                              if (context.mounted) Navigator.pop(context);
                            },
                            icon: const Icon(LucideIcons.folder_x, size: 20),
                            label: Text(S.t('noFolder')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => showCreateFolderDialog(
                            context,
                            parentId: c.currentFolderId,
                          ),
                          icon: const Icon(LucideIcons.folder_plus, size: 20),
                          tooltip: S.t('newFolder'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 16),
                    child: FilledButton.icon(
                      onPressed: () async {
                        await c.moveNotebook(n, c.currentFolderId);
                        if (context.mounted) Navigator.pop(context);
                      },
                      icon: const Icon(LucideIcons.folder_input, size: 20),
                      label: Text(S.t('moveTo')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// A chevron pointing "forward" (flips with the text direction).
Widget _dirChevron(BuildContext context) {
  final flip = Directionality.of(context) == TextDirection.rtl;
  return Icon(
    flip ? LucideIcons.chevron_left : LucideIcons.chevron_right,
    size: 20,
  );
}

List<Widget> _breadcrumbChips(BuildContext context, LibraryController c) {
  // Ancestor chain of the current folder, outermost first (cycle-safe).
  final chain = <FolderEntity>[];
  final visited = <int>{};
  var id = c.currentFolderId;
  while (id != null && visited.add(id)) {
    FolderEntity? f;
    for (final x in c.folders) {
      if (x.id == id) {
        f = x;
        break;
      }
    }
    if (f == null) break;
    chain.insert(0, f);
    id = f.parentId;
  }

  final widgets = <Widget>[
    _pill(
      context,
      label: S.t('rootFolder'),
      icon: LucideIcons.house,
      highlighted: c.currentFolderId == null,
      onTap:
          c.currentFolderId == null ? null : () => c.enterFolder(null),
    ),
  ];
  for (final f in chain) {
    final isCurrent = f.id == c.currentFolderId;
    widgets.add(_pill(
      context,
      label: '${f.emoji} ${f.name}',
      highlighted: isCurrent,
      onTap: isCurrent ? null : () => c.enterFolder(f.id),
    ));
  }
  return widgets;
}

/// Tag editor: toggle assignment, create tags (name + [TAG_COLORS] row),
/// delete tags (with confirm).
Future<void> showTagEditor(BuildContext context, NotebookEntity n) async {
  final c = LibraryController.I;
  final nameCtrl = TextEditingController();
  var color = TAG_COLORS.first;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final cs = Theme.of(context).colorScheme;
          final nc = nanoteColors(context);
          return SafeArea(
            child: NanoteSheet(
              title: S.t('assignTags'),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        child: c.tags.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  S.t('untagged'),
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(fontSize: 13, color: nc.mutedFg),
                                ),
                              )
                            : ListView(
                                shrinkWrap: true,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                children: [
                                  for (final t in c.tags)
                                    ListTile(
                                      leading:
                                          ColorDot(color: Color(t.color), size: 22),
                                      title: Text(
                                        t.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(LucideIcons.trash,
                                                size: 20),
                                            tooltip: S.t('delete'),
                                            onPressed: () async {
                                              final ok = await showConfirmDialog(
                                                context,
                                                title: S.t('delete'),
                                                message: t.name,
                                              );
                                              if (ok) await c.deleteTag(t);
                                            },
                                          ),
                                          Icon(
                                            n.tagIds.contains(t.id)
                                                ? LucideIcons.circle_check
                                                : LucideIcons.circle,
                                            size: 22,
                                            color: n.tagIds.contains(t.id)
                                                ? cs.primary
                                                : nc.mutedFg,
                                          ),
                                        ],
                                      ),
                                      onTap: () => n.tagIds.contains(t.id)
                                          ? c.unassignTag(n, t)
                                          : c.assignTag(n, t),
                                    ),
                                ],
                              ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding:
                            const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 4),
                        child: Text(
                          S.t('newTag'),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: TextField(
                          controller: nameCtrl,
                          decoration: InputDecoration(hintText: S.t('tagName')),
                        ),
                      ),
                      Padding(
                        padding:
                            const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 0),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final col in TAG_COLORS)
                              ColorDot(
                                color: col,
                                selected: col == color,
                                onTap: () => setSheet(() => color = col),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding:
                            const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 20),
                        child: FilledButton.tonalIcon(
                          onPressed: () async {
                            final name = nameCtrl.text.trim();
                            if (name.isEmpty) return;
                            final t =
                                await c.createTag(name, color.toARGB32());
                            await c.assignTag(n, t);
                            // The sheet can be dismissed while the writes
                            // are in flight — nameCtrl is disposed right
                            // after the sheet future completes, so don't
                            // touch it once unmounted.
                            if (context.mounted) nameCtrl.clear();
                          },
                          icon: const Icon(LucideIcons.plus, size: 20),
                          label: Text(S.t('newTag')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  nameCtrl.dispose();
}

/// Standalone tag creation sheet (Tags tab): name + [TAG_COLORS].
Future<void> showCreateTagSheet(BuildContext context) async {
  final c = LibraryController.I;
  final nameCtrl = TextEditingController();
  var color = TAG_COLORS.first;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: NanoteSheet(
          title: S.t('newTag'),
          child: Padding(
            padding:
                const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: InputDecoration(hintText: S.t('tagName')),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final col in TAG_COLORS)
                      ColorDot(
                        color: col,
                        selected: col == color,
                        onTap: () => setSheet(() => color = col),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    await c.createTag(name, color.toARGB32());
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(LucideIcons.plus, size: 20),
                  label: Text(S.t('create')),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  nameCtrl.dispose();
}

/// The notebook context menu. In the trash section it offers restore/purge;
/// otherwise open / favorite / rename / move / tags / delete (to trash).
Future<void> showNotebookMenuSheet(
  BuildContext context,
  NotebookEntity n,
) async {
  final c = LibraryController.I;
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    showDragHandle: false,
    builder: (context) {
      final nc = nanoteColors(context);
      return SafeArea(
        child: NanoteSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding:
                    const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 12),
                child: Row(
                  children: [
                    _menuCoverThumb(n),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${S.num(c.pageCountOf(n.id) ?? 0)} ${S.t('pagesCount')}',
                            style:
                                TextStyle(fontSize: 12, color: nc.mutedFg),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: 6),
              if (n.deleted) ...[
                sheetActionRow(
                  context,
                  icon: LucideIcons.rotate_ccw,
                  label: S.t('restore'),
                  onTap: () => Navigator.pop(context, 'restore'),
                ),
                sheetActionRow(
                  context,
                  icon: LucideIcons.flame,
                  label: S.t('purge'),
                  destructive: true,
                  onTap: () => Navigator.pop(context, 'purge'),
                ),
              ] else ...[
                sheetActionRow(
                  context,
                  icon: LucideIcons.book_open,
                  label: S.t('open'),
                  onTap: () => Navigator.pop(context, 'open'),
                ),
                sheetActionRow(
                  context,
                  icon: LucideIcons.star,
                  label: S.t(n.favorite ? 'unfavorite' : 'favorite'),
                  onTap: () => Navigator.pop(context, 'favorite'),
                ),
                sheetActionRow(
                  context,
                  icon: LucideIcons.pencil,
                  label: S.t('rename'),
                  onTap: () => Navigator.pop(context, 'rename'),
                ),
                sheetActionRow(
                  context,
                  icon: LucideIcons.folder_input,
                  label: S.t('moveTo'),
                  onTap: () => Navigator.pop(context, 'move'),
                ),
                sheetActionRow(
                  context,
                  icon: LucideIcons.tag,
                  label: S.t('assignTags'),
                  onTap: () => Navigator.pop(context, 'tags'),
                ),
                sheetActionRow(
                  context,
                  icon: LucideIcons.trash,
                  label: S.t('delete'),
                  destructive: true,
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'open':
      await Navigator.pushNamed(context, '/notebook', arguments: n.id);
      await c.reload();
      break;
    case 'favorite':
      await c.toggleFavorite(n);
      break;
    case 'rename':
      await showRenameDialog(
          context, n.title, 'rename', (s) => c.renameNotebook(n, s));
      break;
    case 'move':
      await showMoveToFolderSheet(context, n);
      break;
    case 'tags':
      await showTagEditor(context, n);
      break;
    case 'delete':
      await c.trashNotebook(n);
      break;
    case 'restore':
      await c.restoreNotebook(n);
      break;
    case 'purge':
      final ok = await showConfirmDialog(
        context,
        title: S.t('purge'),
        message: S.t('confirmDeleteNotebook'),
      );
      if (ok) await c.purgeNotebook(n);
      break;
  }
}

Widget _menuCoverThumb(NotebookEntity n) {
  final cover = coverById(n.coverId) ?? BUILTIN_COVERS.first;
  return SizedBox(
    width: 28,
    height: 38,
    child: CoverArt(cover: cover, borderRadius: 6),
  );
}

/// Folder creation dialog (name + emoji + color from [FOLDER_COLORS]). The
/// folder is created inside the folder the user is currently browsing.
Future<FolderEntity?> showCreateFolderDialog(
  BuildContext context, {
  int? parentId,
}) async {
  final c = LibraryController.I;
  final nameCtrl = TextEditingController();
  var emoji = kEmojiChoices.first;
  var color = FOLDER_COLORS.first;
  final result = await showDialog<FolderEntity>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setD) => AlertDialog(
        title: Text(S.t('newFolder')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                c.folderPath(parentId),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: nanoteColors(context).mutedFg,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(hintText: S.t('nameHint')),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in kEmojiChoices)
                    InkWell(
                      onTap: () => setD(() => emoji = e),
                      borderRadius: BorderRadius.circular(NANOTE_RADIUS_SM),
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(NANOTE_RADIUS_SM),
                          border: Border.all(
                            color: emoji == e
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                            width: emoji == e ? 2 : 1,
                          ),
                        ),
                        child: Text(e,
                            style: const TextStyle(fontSize: 20)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final col in FOLDER_COLORS)
                    ColorDot(
                      color: col,
                      selected: col == color,
                      onTap: () => setD(() => color = col),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.t('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final f = await c.createFolder(
                  name, color.toARGB32(), emoji);
              if (context.mounted) Navigator.pop(context, f);
            },
            child: Text(S.t('create')),
          ),
        ],
      ),
    ),
  );
  nameCtrl.dispose();
  return result;
}
