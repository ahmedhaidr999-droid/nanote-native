/// The 13 tools of the editor.
enum Tool {
  fountain,
  ballpoint,
  brush,
  fineliner,
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

  bool get isDrawingPen =>
      this == Tool.fountain ||
      this == Tool.ballpoint ||
      this == Tool.brush ||
      this == Tool.fineliner ||
      this == Tool.highlighter;
}
