import 'package:flutter_test/flutter_test.dart';

import 'package:nanote_native/main.dart';
import 'package:nanote_native/src/controllers/stroke_engine.dart';
import 'package:nanote_native/src/models/page_elements.dart';
import 'package:nanote_native/src/models/paper.dart';
import 'package:nanote_native/src/models/stroke.dart';

void main() {
  test('app entry point compiles', () {
    expect(NanoteApp, isNotNull);
  });

  test('stroke outline generation works', () {
    final s = Stroke(
      id: 1,
      style: StrokeStyle.forKind(StrokeKind.fountain, 0xFF16233A),
      pts: <double>[],
    );
    s.append(const Offset(0, 0), 0.5);
    s.append(const Offset(10, 2), 0.6);
    s.append(const Offset(24, 6), 0.5);
    s.append(const Offset(40, 4), 0.4);
    expect(s.pointCount, 4);
    expect(s.outline.length, greaterThan(4));
    expect(s.bbox.width, greaterThan(30));
    expect(s.distanceTo(const Offset(20, 3)) < 6, isTrue);
  });

  test('element json roundtrip', () {
    final el = TextEl(
      id: 't1',
      z: 3,
      text: 'مرحبا Hello',
      x: 10,
      y: 20,
      w: 200,
      size: 18,
      font: TextFontId.system,
      color: 0xFF16233A,
    );
    final back = elementFromJson(el.toJson().cast<String, dynamic>());
    expect(back, isA<TextEl>());
    expect((back as TextEl).text, el.text);
    expect(back.z, 3);
  });

  test('engine initial state', () {
    final engine = StrokeEngine.I;
    expect(engine.isOpen, isFalse);
    expect(engine.canUndo, isFalse);
  });
}
