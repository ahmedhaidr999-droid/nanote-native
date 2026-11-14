/// The tools of the editor.
///
/// v2.1: the four writing pens (fountain / ballpoint / brush / fineliner)
/// are grouped into ONE [pen] tool — its KIND is chosen inside the pen
/// settings panel (user request). The highlighter stays a dedicated tool.
enum Tool {
  pen,
  highlighter,
  laser,
  eraser,
  lasso,
  text,
  shape,
  image,
  sticker,
  pan,
}

extension ToolX on Tool {
  String get key => 'tool.${name}';

  bool get isDrawingPen => this == Tool.pen || this == Tool.highlighter;

  /// Tools that produce ink strokes (pens + laser).
  bool get producesInk => isDrawingPen || this == Tool.laser;
}
