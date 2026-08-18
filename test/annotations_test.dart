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

  group('the text label tool', () {
    AnnotationController labelController() =>
        controllerWith()..tool = AnnotationTool.text;

    test('a label lands where it was placed, in the selected color', () {
      final controller = labelController()..color = annotationColors.last;

      final label = controller.addLabel(const Offset(40, 60), 'wrong price');

      expect(label, same(controller.annotations.single));
      expect(label!.position, const Offset(40, 60));
      expect(label.text, 'wrong price');
      expect(label.color, annotationColors.last);
    });

    test('an empty or whitespace label is refused', () {
      final controller = labelController();

      expect(controller.addLabel(Offset.zero, ''), isNull);
      expect(controller.addLabel(Offset.zero, '   '), isNull);
      expect(controller.hasAnnotations, isFalse);
    });

    test('surrounding whitespace is trimmed away', () {
      final controller = labelController();

      final label = controller.addLabel(Offset.zero, '  too small  ');

      expect(label!.text, 'too small');
    });

    // The text tool places on tap; a drag must not paint anything.
    test('dragging in text mode draws nothing', () {
      final controller = labelController();

      controller.startStroke(Offset.zero);
      controller.extendStroke(const Offset(50, 50));
      controller.endStroke();

      expect(controller.hasAnnotations, isFalse);
    });

    test('editing replaces the words and nothing else', () {
      final controller = labelController();
      final label = controller.addLabel(const Offset(10, 10), 'first');

      controller.updateLabel(label!, 'second thoughts');

      expect(label.text, 'second thoughts');
      expect(controller.annotations.single, same(label));
    });

    test('editing a label down to nothing removes it', () {
      final controller = labelController();
      final label = controller.addLabel(const Offset(10, 10), 'oops');

      controller.updateLabel(label!, '   ');

      expect(controller.hasAnnotations, isFalse);
    });

    test('a tap on an existing label finds it, with finger slop', () {
      final controller = labelController();
      final label = controller.addLabel(const Offset(100, 100), 'here');

      expect(controller.labelAt(const Offset(105, 105)), same(label));
      expect(
        controller.labelAt(const Offset(95, 95)),
        same(label),
        reason: 'a near miss just outside the box still counts',
      );
      expect(controller.labelAt(const Offset(600, 600)), isNull);
    });

    test('overlapping labels resolve to the one drawn on top', () {
      final controller = labelController();
      controller.addLabel(const Offset(100, 100), 'under');
      final top = controller.addLabel(const Offset(102, 102), 'over');

      expect(controller.labelAt(const Offset(104, 104)), same(top));
    });

    test('undo removes a label like any other annotation', () {
      final controller = labelController();
      controller.addLabel(Offset.zero, 'gone soon');

      controller.undo();

      expect(controller.hasAnnotations, isFalse);
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
