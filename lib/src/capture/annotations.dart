import 'dart:ui';

import 'package:flutter/foundation.dart';

/// One thing the reporter placed on the screenshot.
///
/// Coordinates are **image pixels**, never screen pixels. The screenshot is a
/// still image by the time anything is drawn on it, so a point on an
/// annotation and the pixel it refers to can never drift apart — which was
/// the bug that made owning this stack necessary (SQUAW-34).
///
/// Sealed so each tool is a small class of its own: arrows (SQUAW-28) and
/// text labels (SQUAW-29) are additions here, not surgery on a painter.
sealed class Annotation {
  /// Draws onto a canvas whose coordinate space is the image's own pixels.
  /// The on-screen preview and the final composite apply the same transform,
  /// so what the reporter sees is exactly what is uploaded.
  void draw(Canvas canvas);
}

/// A freehand pen stroke.
final class StrokeAnnotation implements Annotation {
  StrokeAnnotation({
    required Offset start,
    required this.color,
    required this.strokeWidth,
  })  : _points = [start],
        _path = Path()..moveTo(start.dx, start.dy);

  final Color color;

  /// In image pixels, so the stroke keeps its visual weight from preview to
  /// composite regardless of how the image was scaled on screen.
  final double strokeWidth;

  final List<Offset> _points;

  /// Kept alongside [_points] so extending a stroke is O(1) per point rather
  /// than rebuilding the whole path every frame of the drag.
  final Path _path;

  /// The points of the stroke, in image pixels.
  List<Offset> get points => List.unmodifiable(_points);

  void extend(Offset point) {
    _points.add(point);
    _path.lineTo(point.dx, point.dy);
  }

  @override
  void draw(Canvas canvas) {
    // A tap leaves a dot. A path with a single moveTo draws nothing, and a
    // reporter who taps the screen expects a mark, not silence.
    if (_points.length == 1) {
      canvas.drawCircle(
        _points.single,
        strokeWidth / 2,
        Paint()..color = color,
      );
      return;
    }

    canvas.drawPath(
      _path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }
}

/// A straight arrow from where the drag started to where it ended.
///
/// The tool for pointing at one specific element — freehand circling works,
/// but reads as scribble in a client-facing report.
final class ArrowAnnotation implements Annotation {
  ArrowAnnotation({
    required this.start,
    required Offset end,
    required this.color,
    required this.strokeWidth,
  }) : _end = end;

  /// The tail — where the drag began.
  final Offset start;

  final Color color;

  /// In image pixels, like every annotation measurement.
  final double strokeWidth;

  Offset _end;

  /// The head — follows the finger while the drag is live.
  Offset get end => _end;

  void moveHead(Offset point) => _end = point;

  double get length => (end - start).distance;

  /// Shorter than this and the arrow marks nothing; the controller discards
  /// it rather than leave a speck the reporter has to undo.
  double get minLength => strokeWidth * 3;

  @override
  void draw(Canvas canvas) {
    if (length < minLength) return;

    final direction = (end - start) / length;
    final headLength = strokeWidth * 3.5;
    final headBase = end - direction * headLength;
    final across =
        Offset(-direction.dy, direction.dx) * (headLength * 0.55);

    // The shaft stops at the head's base so the line never pokes through
    // the tip.
    canvas.drawLine(
      start,
      headBase,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawPath(
      Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(headBase.dx + across.dx, headBase.dy + across.dy)
        ..lineTo(headBase.dx - across.dx, headBase.dy - across.dy)
        ..close(),
      Paint()..color = color,
    );
  }
}

/// What a drag on the canvas produces.
enum AnnotationTool { pen, arrow }

/// The marker colors offered to the reporter. Red first: it is what people
/// reach for to point at a problem.
const List<Color> annotationColors = [
  Color(0xFFE53935), // red
  Color(0xFFFDD835), // yellow
  Color(0xFF43A047), // green
  Color(0xFF1E88E5), // blue
];

/// The color's name, so a screen reader can tell the markers apart.
String colorNameOf(Color color) => switch (color) {
      const Color(0xFFE53935) => 'Red',
      const Color(0xFFFDD835) => 'Yellow',
      const Color(0xFF43A047) => 'Green',
      const Color(0xFF1E88E5) => 'Blue',
      _ => 'Colored',
    };

/// Holds what has been drawn during one capture session.
class AnnotationController extends ChangeNotifier {
  AnnotationController({required this.strokeWidth});

  /// In image pixels — chosen by the session from the capture's pixel ratio.
  final double strokeWidth;

  final List<Annotation> _annotations = [];
  Annotation? _active;
  Color _color = annotationColors.first;
  AnnotationTool _tool = AnnotationTool.pen;

  List<Annotation> get annotations => List.unmodifiable(_annotations);

  bool get hasAnnotations => _annotations.isNotEmpty;

  bool get canUndo => _annotations.isNotEmpty && _active == null;

  Color get color => _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    notifyListeners();
  }

  AnnotationTool get tool => _tool;
  set tool(AnnotationTool value) {
    if (_tool == value) return;
    _tool = value;
    notifyListeners();
  }

  void startStroke(Offset imagePoint) {
    // A second start before the first ended: a stray extra pointer. The
    // drawing in progress wins; starting another would corrupt it.
    if (_active != null) return;

    final annotation = switch (_tool) {
      AnnotationTool.pen => StrokeAnnotation(
          start: imagePoint,
          color: _color,
          strokeWidth: strokeWidth,
        ),
      AnnotationTool.arrow => ArrowAnnotation(
          start: imagePoint,
          end: imagePoint,
          color: _color,
          strokeWidth: strokeWidth,
        ),
    };
    _active = annotation;
    _annotations.add(annotation);
    notifyListeners();
  }

  void extendStroke(Offset imagePoint) {
    switch (_active) {
      case StrokeAnnotation stroke:
        stroke.extend(imagePoint);
      case ArrowAnnotation arrow:
        arrow.moveHead(imagePoint);
      case _:
        return;
    }
    notifyListeners();
  }

  void endStroke() {
    // An arrow too short to have a direction marks nothing — dropping it
    // beats leaving a speck the reporter has to undo.
    if (_active case final ArrowAnnotation arrow
        when arrow.length < arrow.minLength) {
      _annotations.remove(arrow);
    }
    _active = null;
    notifyListeners();
  }

  /// Removes the most recent annotation. Ignored mid-drag: undoing the stroke
  /// under the reporter's finger would leave the drag orphaned.
  void undo() {
    if (!canUndo) return;
    _annotations.removeLast();
    notifyListeners();
  }
}
