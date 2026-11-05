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

/// Page sizes (logical px at 1x).
enum PageSizeId { a4Portrait, a4Landscape, letterPortrait, letterLandscape }

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
  PageSizeId.letterPortrait: PageSizeDef(PageSizeId.letterPortrait, 816, 1054),
  PageSizeId.letterLandscape: PageSizeDef(PageSizeId.letterLandscape, 1054, 816),
};

PageSizeDef pageSizeDef(PageSizeId id) => PAGE_SIZES[id] ?? PAGE_SIZES[PageSizeId.a4Portrait]!;

PageSizeId pageSizeIdFrom(int id) =>
    PageSizeId.values[id.clamp(0, PageSizeId.values.length - 1)];

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

/// Built-in notebook covers — 8 gradient covers, drawn programmatically.
class CoverDef {
  final String id;
  final List<Color> colors;

  const CoverDef(this.id, this.colors);
}

const List<CoverDef> BUILTIN_COVERS = [
  CoverDef('c1', [Color(0xFF1E6FF2), Color(0xFF6BA6FF)]),
  CoverDef('c2', [Color(0xFF0E7A5F), Color(0xFF6FE38B)]),
  CoverDef('c3', [Color(0xFF9333EA), Color(0xFFC9A6FF)]),
  CoverDef('c4', [Color(0xFFE5484D), Color(0xFFFF9F1C)]),
  CoverDef('c5', [Color(0xFF16233A), Color(0xFF5A6B85)]),
  CoverDef('c6', [Color(0xFFDB2777), Color(0xFFFF7EB6)]),
  CoverDef('c7', [Color(0xFFCA8A04), Color(0xFFFFD84D)]),
  CoverDef('c8', [Color(0xFF2B2440), Color(0xFF7CC4FF)]),
];

CoverDef? coverById(String? id) {
  if (id == null) return null;
  for (final c in BUILTIN_COVERS) {
    if (c.id == id) return c;
  }
  return null;
}
