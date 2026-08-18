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
  StrokeAnnotation? _active;
  Color _color = annotationColors.first;

  List<Annotation> get annotations => List.unmodifiable(_annotations);

  bool get hasAnnotations => _annotations.isNotEmpty;

  bool get canUndo => _annotations.isNotEmpty && _active == null;

  Color get color => _color;
  set color(Color value) {
    if (_color == value) return;
    _color = value;
    notifyListeners();
  }

  void startStroke(Offset imagePoint) {
    // A second start before the first ended: a stray extra pointer. The
    // stroke in progress wins; starting another would corrupt it.
    if (_active != null) return;

    final stroke = StrokeAnnotation(
      start: imagePoint,
      color: _color,
      strokeWidth: strokeWidth,
    );
    _active = stroke;
    _annotations.add(stroke);
    notifyListeners();
  }

  void extendStroke(Offset imagePoint) {
    _active?.extend(imagePoint);
    if (_active != null) notifyListeners();
  }

  void endStroke() {
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
