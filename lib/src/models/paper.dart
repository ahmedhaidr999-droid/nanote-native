import 'package:flutter/material.dart';

/// The 12 built-in paper templates.
enum TemplateId {
  blank,
  ruled,
  college,
  grid,
  dots,
  graph,
  isometric,
  hex,
  staff,
  crossGrid,
  diagonal,
  manuscript,
}

extension TemplateIdX on TemplateId {
  int get id => index;

  static TemplateId fromId(int id) =>
      TemplateId.values[id.clamp(0, TemplateId.values.length - 1)];

  String get key => 'template.${name}';
}

/// Page sizes (logical px at 1x). A5 was APPENDED (indices are persisted in
/// the DB — never reorder or insert). v2.4.0 APPENDED the INFINITE paper
/// (794 wide, grows forever while you write — see doc_geometry.dart).
enum PageSizeId {
  a4Portrait,
  a4Landscape,
  letterPortrait,
  letterLandscape,
  a5Portrait,
  a5Landscape,
  infinityPaper,
}

class PageSizeDef {
  final PageSizeId id;
  final double w;
  final double h;

  const PageSizeDef(this.id, this.w, this.h);

  Size get size => Size(w, h);
}

const Map<PageSizeId, PageSizeDef> PAGE_SIZES = {
  PageSizeId.a4Portrait: PageSizeDef(PageSizeId.a4Portrait, 794, 1123),
  PageSizeId.a4Landscape: PageSizeDef(PageSizeId.a4Landscape, 1123, 794),
  PageSizeId.letterPortrait:
      PageSizeDef(PageSizeId.letterPortrait, 816, 1054),
  PageSizeId.letterLandscape:
      PageSizeDef(PageSizeId.letterLandscape, 1054, 816),
  PageSizeId.a5Portrait: PageSizeDef(PageSizeId.a5Portrait, 559, 794),
  PageSizeId.a5Landscape: PageSizeDef(PageSizeId.a5Landscape, 794, 559),
  // §1 Infinity Paper: fixed 794-wide base that grows forever. The stored
  // h (1123) is only the OPENING height — layout uses per-page growth.
  PageSizeId.infinityPaper:
      PageSizeDef(PageSizeId.infinityPaper, 794, 1123),
};

PageSizeDef pageSizeDef(PageSizeId id) =>
    PAGE_SIZES[id] ?? PAGE_SIZES[PageSizeId.a4Portrait]!;

PageSizeId pageSizeIdFrom(int id) =>
    PageSizeId.values[id.clamp(0, PageSizeId.values.length - 1)];

/// §2 true when the (persisted) page-size id is the INFINITE paper.
bool isInfinitySize(int id) => id == PageSizeId.infinityPaper.index;

/// §2 Infinity-paper growth constants (doc units):
///  * [kInfiniteChase] — the margin the paper keeps BEYOND new content
///    before it grows ("the paper chases the pen").
///  * [kInfiniteStep] — growth is rounded UP to multiples of this.
///  * [kInfiniteGap] — vertical gap between consecutive infinite pages.
const double kInfiniteChase = 140.0;
const double kInfiniteStep = 512.0;
const double kInfiniteGap = 28.0;

/// Base grid pitch for grid snap / rulers (pt).
const double GRID_PITCH = 24.0;

/// The 16-color ink palette (v1.9.1).
const List<Color> INK_PALETTE = [
  Color(0xFF16233A),
  Color(0xFF1E6FF2),
  Color(0xFF0A3A8F),
  Color(0xFF5A6B85),
  Color(0xFF22A06B),
  Color(0xFF0E7A5F),
  Color(0xFFE5484D),
  Color(0xFFC2410C),
  Color(0xFFFF9F1C),
  Color(0xFFCA8A04),
  Color(0xFF9333EA),
  Color(0xFFDB2777),
  Color(0xFFFFFFFF),
  Color(0xFF94A3B8),
  Color(0xFF6FE38B),
  Color(0xFF7CC4FF),
];

/// The 5-color highlighter palette.
const List<Color> HIGHLIGHTER_PALETTE = [
  Color(0xFFFFD84D),
  Color(0xFF6FE38B),
  Color(0xFFFF7EB6),
  Color(0xFF7CC4FF),
  Color(0xFFC9A6FF),
];

/// Paper colors (8).
const List<Color> PAPER_COLORS = [
  Color(0xFFFFFFFF),
  Color(0xFFFFFDF5),
  Color(0xFFF7F4EC),
  Color(0xFFF4F7FC),
  Color(0xFFFBF7F2),
  Color(0xFF1A1F2E),
  Color(0xFF232936),
  Color(0xFF2B2440),
];

Color paperColorFrom(int value) {
  for (final c in PAPER_COLORS) {
    if (c.toARGB32() == value) return c;
  }
  return Color(value);
}

bool isDarkPaper(Color c) => c.computeLuminance() < 0.45;

/// Template line color: rgba(90,107,133,.30) on light paper,
/// rgba(255,255,255,.14) on dark paper.
Color templateLineColor(Color paper) => isDarkPaper(paper)
    ? const Color(0x24FFFFFF)
    : const Color(0x4D5A6B85);

/// The 12 shape types of the shape tool.
enum ShapeType {
  line,
  arrow,
  doubleArrow,
  arc,
  rect,
  roundedRect,
  ellipse,
  triangle,
  star,
  hexagon,
  polygon,
  freeform,
}

extension ShapeTypeX on ShapeType {
  static ShapeType fromId(int id) =>
      ShapeType.values[id.clamp(0, ShapeType.values.length - 1)];

  String get key => 'shape.${name}';

  /// Shape types whose geometry is a list of free points rather than a bbox.
  bool get isPolylineLike => this == ShapeType.line || this == ShapeType.arrow || this == ShapeType.doubleArrow || this == ShapeType.arc;
}

/// The 6 text fonts. All are Arabic-capable on Android via system fallback.
enum TextFontId { system, serif, sansCondensed, mono, medium, cursive }

extension TextFontIdX on TextFontId {
  static TextFontId fromId(int id) =>
      TextFontId.values[id.clamp(0, TextFontId.values.length - 1)];

  String? get fontFamily {
    switch (this) {
      case TextFontId.system:
        return null;
      case TextFontId.serif:
        return 'serif';
      case TextFontId.sansCondensed:
        return 'sans-serif-condensed';
      case TextFontId.mono:
        return 'monospace';
      case TextFontId.medium:
        return 'sans-serif-medium';
      case TextFontId.cursive:
        return 'cursive';
    }
  }

  String get key => 'font.${name}';
}

// ---------------------------------------------------------------------------
// Notebook covers — the 12 v1.9.1 covers (3:4 portrait).
// ---------------------------------------------------------------------------

/// How a cover paints.
enum CoverStyle { gradient, flat, dots, lines }

class CoverDef {
  /// Stable id ('c1'..'c12' — persisted on notebooks, never rename).
  final String id;

  /// i18n key for the cover name (`cover.<name>`).
  final String nameKey;

  final CoverStyle style;

  /// Gradient stops (top-start → bottom-end, 160°). For [CoverStyle.flat]
  /// this holds exactly one color.
  final List<Color> colors;

  /// Title/text color on top of the cover.
  final Color textColor;

  const CoverDef({
    required this.id,
    required this.nameKey,
    required this.style,
    required this.colors,
    required this.textColor,
  });

  /// First color (flat fills + gradient start).
  Color get baseColor => colors.first;

  bool get hasPattern =>
      style == CoverStyle.dots || style == CoverStyle.lines;

  /// The 160° gradient (or a flat fill) for this cover.
  Gradient buildGradient() {
    if (style == CoverStyle.flat || colors.length == 1) {
      return LinearGradient(colors: [colors.first, colors.first]);
    }
    return LinearGradient(
      begin: const Alignment(-0.6, -1),
      end: const Alignment(0.6, 1),
      colors: colors,
    );
  }
}

/// The 12 built-in covers (v1.9.1). Ids stay 'c1'..'c12' — legacy notebooks
/// keep whatever they had saved.
const List<CoverDef> BUILTIN_COVERS = [
  CoverDef(
    id: 'c1',
    nameKey: 'cover.nanoteBlue',
    style: CoverStyle.gradient,
    colors: [Color(0xFF2B7BFF), Color(0xFF1E6FF2), Color(0xFF0D47C4)],
    textColor: Color(0xFFFFFFFF),
  ),
  CoverDef(
    id: 'c2',
    nameKey: 'cover.midnight',
    style: CoverStyle.gradient,
    colors: [Color(0xFF2B3A55), Color(0xFF16233A)],
    textColor: Color(0xFFFFFFFF),
  ),
  CoverDef(
    id: 'c3',
    nameKey: 'cover.sunset',
    style: CoverStyle.gradient,
    colors: [Color(0xFFFF9F1C), Color(0xFFE5484D)],
    textColor: Color(0xFFFFFFFF),
  ),
  CoverDef(
    id: 'c4',
    nameKey: 'cover.meadow',
    style: CoverStyle.gradient,
    colors: [Color(0xFF34C98B), Color(0xFF0E7A5F)],
    textColor: Color(0xFFFFFFFF),
  ),
  CoverDef(
    id: 'c5',
    nameKey: 'cover.orchid',
    style: CoverStyle.gradient,
    colors: [Color(0xFFC9A6FF), Color(0xFF9333EA)],
    textColor: Color(0xFFFFFFFF),
  ),
  CoverDef(
    id: 'c6',
    nameKey: 'cover.rosewater',
    style: CoverStyle.gradient,
    colors: [Color(0xFFFF7EB6), Color(0xFFDB2777)],
    textColor: Color(0xFFFFFFFF),
  ),
  CoverDef(
    id: 'c7',
    nameKey: 'cover.paperWhite',
    style: CoverStyle.flat,
    colors: [Color(0xFFF7F9FC)],
    textColor: Color(0xFF16233A),
  ),
  CoverDef(
    id: 'c8',
    nameKey: 'cover.kraft',
    style: CoverStyle.flat,
    colors: [Color(0xFFE8D5B5)],
    textColor: Color(0xFF5A4632),
  ),
  CoverDef(
    id: 'c9',
    nameKey: 'cover.inkBlack',
    style: CoverStyle.flat,
    colors: [Color(0xFF16202E)],
    textColor: Color(0xFFE8EEF7),
  ),
  CoverDef(
    id: 'c10',
    nameKey: 'cover.forest',
    style: CoverStyle.flat,
    colors: [Color(0xFF1F4E3D)],
    textColor: Color(0xFFE8F5EE),
  ),
  CoverDef(
    id: 'c11',
    nameKey: 'cover.dots',
    style: CoverStyle.dots,
    colors: [Color(0xFF1E6FF2), Color(0xFF0D47C4)],
    textColor: Color(0xFFFFFFFF),
  ),
  CoverDef(
    id: 'c12',
    nameKey: 'cover.lines',
    style: CoverStyle.lines,
    colors: [Color(0xFF16233A), Color(0xFF0E1622)],
    textColor: Color(0xFFFFFFFF),
  ),
];

CoverDef? coverById(String? id) {
  if (id == null) return null;
  for (final c in BUILTIN_COVERS) {
    if (c.id == id) return c;
  }
  return null;
}

/// Folder colors (10) — folders only get the last two extra colors.
const List<Color> FOLDER_COLORS = [
  Color(0xFF1E6FF2),
  Color(0xFF22A06B),
  Color(0xFFFF9F1C),
  Color(0xFFE5484D),
  Color(0xFF9333EA),
  Color(0xFFDB2777),
  Color(0xFF0E7A5F),
  Color(0xFF5A6B85),
  Color(0xFFCA8A04),
  Color(0xFF16233A),
];

/// Tag colors (8).
const List<Color> TAG_COLORS = [
  Color(0xFF1E6FF2),
  Color(0xFF22A06B),
  Color(0xFFFF9F1C),
  Color(0xFFE5484D),
  Color(0xFF9333EA),
  Color(0xFFDB2777),
  Color(0xFF0E7A5F),
  Color(0xFF5A6B85),
];
