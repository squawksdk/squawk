import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/src/capture/annotations.dart';

void main() {
  AnnotationController controllerWith() => AnnotationController(
        strokeWidth: 8,
        imageSize: const Size(1000, 1000),
      );

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

  group('the move tool', () {
    test('drags a stroke by any point along it', () {
      final controller = controllerWith();
      controller.startStroke(const Offset(100, 100));
      controller.extendStroke(const Offset(200, 100));
      controller.endStroke();

      controller.tool = AnnotationTool.move;
      controller.startStroke(const Offset(150, 100));
      controller.extendStroke(const Offset(150, 160));
      controller.endStroke();

      final stroke = controller.annotations.single as StrokeAnnotation;
      expect(stroke.points, const [Offset(100, 160), Offset(200, 160)]);
    });

    test('drags an arrow by its shaft, tail and head together', () {
      final controller = controllerWith()..tool = AnnotationTool.arrow;
      controller.startStroke(const Offset(100, 100));
      controller.extendStroke(const Offset(300, 100));
      controller.endStroke();

      controller.tool = AnnotationTool.move;
      controller.startStroke(const Offset(200, 100));
      controller.extendStroke(const Offset(250, 150));
      controller.endStroke();

      final arrow = controller.annotations.single as ArrowAnnotation;
      expect(arrow.start, const Offset(150, 150));
      expect(arrow.end, const Offset(350, 150));
    });

    test('drags a label wherever the finger goes', () {
      final controller = controllerWith()..tool = AnnotationTool.text;
      final label = controller.addLabel(const Offset(100, 100), 'here');

      controller.tool = AnnotationTool.move;
      controller.startStroke(const Offset(110, 110));
      controller.extendStroke(const Offset(400, 300));
      controller.endStroke();

      expect(label!.position, const Offset(390, 290));
    });

    test('a drag on empty canvas moves nothing and draws nothing', () {
      final controller = controllerWith();
      controller.startStroke(const Offset(100, 100));
      controller.endStroke();

      controller.tool = AnnotationTool.move;
      controller.startStroke(const Offset(600, 600));
      controller.extendStroke(const Offset(700, 700));
      controller.endStroke();

      final dot = controller.annotations.single as StrokeAnnotation;
      expect(dot.points.single, const Offset(100, 100));
      expect(controller.annotations, hasLength(1));
    });

    // Dragging a drawing off the picture would lose it invisibly: it stays
    // in the report's annotation list but marks nothing.
    test('a drawing stops at the image edge instead of leaving', () {
      final controller = controllerWith()..tool = AnnotationTool.text;
      final label = controller.addLabel(const Offset(900, 900), 'stay');

      controller.tool = AnnotationTool.move;
      controller.startStroke(const Offset(910, 910));
      controller.extendStroke(const Offset(999, 999));
      controller.extendStroke(const Offset(999, 999));
      controller.endStroke();

      expect(
        label!.bounds.overlaps(const Rect.fromLTWH(0, 0, 1000, 1000)),
        isTrue,
        reason: 'some part of the label must still be on the picture',
      );
    });

    test('overlapping drawings move the one on top', () {
      final controller = controllerWith()..tool = AnnotationTool.text;
      final under = controller.addLabel(const Offset(100, 100), 'under');
      final over = controller.addLabel(const Offset(105, 105), 'over');

      controller.tool = AnnotationTool.move;
      controller.startStroke(const Offset(110, 110));
      controller.extendStroke(const Offset(310, 110));
      controller.endStroke();

      expect(over!.position.dx, 305);
      expect(under!.position, const Offset(100, 100));
    });

    test('undo is refused while a drawing is mid-move', () {
      final controller = controllerWith();
      controller.startStroke(const Offset(100, 100));
      controller.endStroke();

      controller.tool = AnnotationTool.move;
      controller.startStroke(const Offset(100, 100));

      expect(controller.canUndo, isFalse);
      controller.endStroke();
      expect(controller.canUndo, isTrue);
    });
  });

  group('selecting and resizing', () {
    AnnotationController moveController() =>
        controllerWith()..tool = AnnotationTool.move;

    ArrowAnnotation arrowAcross(AnnotationController controller) {
      controller.tool = AnnotationTool.arrow;
      controller.startStroke(const Offset(200, 300));
      controller.extendStroke(const Offset(400, 300));
      controller.endStroke();
      controller.tool = AnnotationTool.move;
      return controller.annotations.single as ArrowAnnotation;
    }

    test('grabbing a drawing selects it; tapping empty space clears', () {
      final controller = moveController();
      final arrow = arrowAcross(controller);

      controller.startStroke(const Offset(300, 300));
      controller.endStroke();
      expect(controller.selected, same(arrow));

      controller.select(null);
      expect(controller.selected, isNull);
    });

    test('leaving move mode drops the selection', () {
      final controller = moveController();
      final arrow = arrowAcross(controller);
      controller.select(arrow);

      controller.tool = AnnotationTool.pen;

      expect(controller.selected, isNull);
    });

    test('undoing the selected drawing deselects it', () {
      final controller = moveController();
      final arrow = arrowAcross(controller);
      controller.select(arrow);

      controller.undo();

      expect(controller.selected, isNull);
      expect(controller.hasAnnotations, isFalse);
    });

    test('dragging the corner handle grows the drawing', () {
      final controller = moveController();
      final arrow = arrowAcross(controller);
      controller.select(arrow);
      final lengthBefore = arrow.length;
      final handle = controller.selectionHandle!;

      controller.startStroke(handle);
      controller.extendStroke(
        controller.selectionAnchor! +
            (handle - controller.selectionAnchor!) * 1.5,
      );
      controller.endStroke();

      expect(arrow.length, greaterThan(lengthBefore));
    });

    test('dragging the handle inward shrinks it', () {
      final controller = moveController();
      final arrow = arrowAcross(controller);
      controller.select(arrow);
      final lengthBefore = arrow.length;
      final handle = controller.selectionHandle!;

      controller.startStroke(handle);
      controller.extendStroke(
        controller.selectionAnchor! +
            (handle - controller.selectionAnchor!) * 0.6,
      );
      controller.endStroke();

      expect(arrow.length, lessThan(lengthBefore));
    });

    test('a drawing cannot be shrunk into an ungrabbable speck', () {
      final controller = moveController();
      final arrow = arrowAcross(controller);
      controller.select(arrow);
      final handle = controller.selectionHandle!;

      controller.startStroke(handle);
      controller.extendStroke(
        controller.selectionAnchor! +
            (handle - controller.selectionAnchor!) * 0.01,
      );
      controller.endStroke();

      expect(arrow.length, greaterThanOrEqualTo(controller.strokeWidth * 3),
          reason: 'the resize stops at a grabbable minimum');
    });

    test('a drawing cannot be grown past the picture', () {
      final controller = moveController();
      final arrow = arrowAcross(controller);
      controller.select(arrow);
      final handle = controller.selectionHandle!;

      controller.startStroke(handle);
      controller.extendStroke(
        controller.selectionAnchor! +
            (handle - controller.selectionAnchor!) * 50,
      );
      controller.endStroke();

      expect(
        arrow.bounds.longestSide,
        lessThanOrEqualTo(const Size(1000, 1000).longestSide),
      );
    });

    test('resizing a note changes its text size', () {
      final controller = controllerWith()..tool = AnnotationTool.text;
      final label = controller.addLabel(const Offset(400, 400), 'resize me');
      final sizeBefore = label!.fontSize;
      controller.tool = AnnotationTool.move;
      controller.select(label);
      final handle = controller.selectionHandle!;

      controller.startStroke(handle);
      controller.extendStroke(
        controller.selectionAnchor! +
            (handle - controller.selectionAnchor!) * 1.5,
      );
      controller.endStroke();

      expect(label.fontSize, greaterThan(sizeBefore));
    });

    test('resizing a stroke scales its shape, not its line weight', () {
      final controller = controllerWith();
      controller.startStroke(const Offset(300, 300));
      controller.extendStroke(const Offset(500, 300));
      controller.endStroke();
      final stroke = controller.annotations.single as StrokeAnnotation;
      controller.tool = AnnotationTool.move;
      controller.select(stroke);
      final handle = controller.selectionHandle!;

      controller.startStroke(handle);
      controller.extendStroke(
        controller.selectionAnchor! +
            (handle - controller.selectionAnchor!) * 2,
      );
      controller.endStroke();

      final width =
          stroke.points.last.dx - stroke.points.first.dx;
      expect(width, greaterThan(300), reason: 'the shape grew');
      expect(stroke.strokeWidth, controller.strokeWidth,
          reason: 'the line weight did not');
    });

    test('undo is refused mid-resize', () {
      final controller = moveController();
      final arrow = arrowAcross(controller);
      controller.select(arrow);

      controller.startStroke(controller.selectionHandle!);
      expect(controller.canUndo, isFalse);
      controller.endStroke();
      expect(controller.canUndo, isTrue);
    });
  });

  test('distance to a segment measures perpendicular or to the ends', () {
    const a = Offset(0, 0);
    const b = Offset(100, 0);

    expect(distanceToSegment(const Offset(50, 30), a, b), 30);
    expect(distanceToSegment(const Offset(-40, 0), a, b), 40);
    expect(distanceToSegment(const Offset(130, 40), a, b), 50);
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
