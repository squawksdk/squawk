import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/src/capture/annotations.dart';

void main() {
  AnnotationController controllerWith() =>
      AnnotationController(strokeWidth: 8);

  group('drawing strokes', () {
    test('a drag becomes one stroke carrying its points', () {
      final controller = controllerWith();

      controller.startStroke(const Offset(10, 10));
      controller.extendStroke(const Offset(20, 20));
      controller.extendStroke(const Offset(30, 30));
      controller.endStroke();

      final stroke = controller.annotations.single as StrokeAnnotation;
      expect(stroke.points, const [
        Offset(10, 10),
        Offset(20, 20),
        Offset(30, 30),
      ]);
    });

    test('strokes take the color selected when they started', () {
      final controller = controllerWith();

      controller.startStroke(Offset.zero);
      controller.endStroke();
      controller.color = annotationColors[2];
      controller.startStroke(Offset.zero);
      controller.endStroke();

      final strokes = controller.annotations.cast<StrokeAnnotation>();
      expect(strokes.first.color, annotationColors.first);
      expect(strokes.last.color, annotationColors[2]);
    });

    // A stray second pointer mid-drag must not corrupt the stroke in
    // progress.
    test('a second start mid-drag is ignored', () {
      final controller = controllerWith();

      controller.startStroke(const Offset(1, 1));
      controller.startStroke(const Offset(99, 99));
      controller.extendStroke(const Offset(2, 2));
      controller.endStroke();

      final stroke = controller.annotations.single as StrokeAnnotation;
      expect(stroke.points.first, const Offset(1, 1));
      expect(stroke.points, hasLength(2));
    });

    test('extending without a started stroke does nothing', () {
      final controller = controllerWith();

      controller.extendStroke(const Offset(5, 5));

      expect(controller.hasAnnotations, isFalse);
    });
  });

  group('undo', () {
    test('removes the latest annotation only', () {
      final controller = controllerWith();
      controller.startStroke(const Offset(1, 1));
      controller.endStroke();
      controller.startStroke(const Offset(2, 2));
      controller.endStroke();

      controller.undo();

      final stroke = controller.annotations.single as StrokeAnnotation;
      expect(stroke.points.single, const Offset(1, 1));
    });

    // Undoing the stroke under the reporter's finger would orphan the drag.
    test('is refused mid-drag', () {
      final controller = controllerWith();
      controller.startStroke(const Offset(1, 1));

      expect(controller.canUndo, isFalse);
      controller.undo();

      expect(controller.hasAnnotations, isTrue);
    });

    test('with nothing drawn there is nothing to undo', () {
      final controller = controllerWith();

      expect(controller.canUndo, isFalse);
      controller.undo();

      expect(controller.hasAnnotations, isFalse);
    });
  });

  group('the arrow tool', () {
    AnnotationController arrowController() =>
        controllerWith()..tool = AnnotationTool.arrow;

    test('a drag becomes an arrow from tail to head', () {
      final controller = arrowController();

      controller.startStroke(const Offset(10, 10));
      controller.extendStroke(const Offset(60, 40));
      controller.extendStroke(const Offset(90, 80));
      controller.endStroke();

      final arrow = controller.annotations.single as ArrowAnnotation;
      expect(arrow.start, const Offset(10, 10));
      expect(arrow.end, const Offset(90, 80),
          reason: 'the head follows the finger to wherever it ends');
    });

    // An arrow with no direction marks nothing. A stray tap in arrow mode
    // must not leave a speck the reporter then has to undo.
    test('a tap leaves no arrow behind', () {
      final controller = arrowController();

      controller.startStroke(const Offset(30, 30));
      controller.endStroke();

      expect(controller.hasAnnotations, isFalse);
    });

    test('a drag shorter than the head is discarded too', () {
      final controller = arrowController();

      controller.startStroke(const Offset(30, 30));
      controller.extendStroke(const Offset(33, 33));
      controller.endStroke();

      expect(controller.hasAnnotations, isFalse);
    });

    test('arrows take the selected color', () {
      final controller = arrowController()..color = annotationColors.last;

      controller.startStroke(Offset.zero);
      controller.extendStroke(const Offset(100, 0));
      controller.endStroke();

      final arrow = controller.annotations.single as ArrowAnnotation;
      expect(arrow.color, annotationColors.last);
    });

    test('switching tools mid-drag does not change the drawing in progress',
        () {
      final controller = arrowController();
      controller.startStroke(Offset.zero);

      controller.tool = AnnotationTool.pen;
      controller.extendStroke(const Offset(100, 0));
      controller.endStroke();

      expect(controller.annotations.single, isA<ArrowAnnotation>());
    });

    test('undo works across mixed annotation types', () {
      final controller = controllerWith();
      controller.startStroke(Offset.zero);
      controller.endStroke();
      controller.tool = AnnotationTool.arrow;
      controller.startStroke(Offset.zero);
      controller.extendStroke(const Offset(100, 0));
      controller.endStroke();

      controller.undo();
      expect(controller.annotations.single, isA<StrokeAnnotation>());

      controller.undo();
      expect(controller.hasAnnotations, isFalse);
    });

    test('changing tool notifies listeners', () {
      final controller = controllerWith();
      var notified = 0;
      controller.addListener(() => notified++);

      controller.tool = AnnotationTool.arrow;
      controller.tool = AnnotationTool.arrow;

      expect(notified, 1, reason: 'setting the same tool again is silent');
    });
  });

  test('the annotation list cannot be mutated from outside', () {
    final controller = controllerWith();
    controller.startStroke(Offset.zero);
    controller.endStroke();

    expect(() => controller.annotations.clear(), throwsUnsupportedError);
  });

  test('listeners hear every change that alters what is on screen', () {
    final controller = controllerWith();
    var notified = 0;
    controller.addListener(() => notified++);

    controller.startStroke(Offset.zero);
    controller.extendStroke(const Offset(1, 1));
    controller.endStroke();
    controller.undo();
    controller.color = annotationColors.last;

    expect(notified, 5);
  });
}
