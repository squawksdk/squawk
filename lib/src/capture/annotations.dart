import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

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

  /// Whether an image-space point lands on this annotation, padded enough
  /// for a finger.
  bool hitTest(Offset point);

  /// Shifts the whole annotation. The controller clamps the delta so nothing
  /// can be dragged off the picture and silently lost.
  void moveBy(Offset delta);

  /// Scales the annotation about [anchor]. The controller clamps the factor
  /// so nothing shrinks into an ungrabbable speck or grows past the picture.
  void scaleBy(double factor, Offset anchor);

  /// The image-space box the annotation occupies.
  Rect get bounds;
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
  Path _path;

  /// The points of the stroke, in image pixels.
  List<Offset> get points => List.unmodifiable(_points);

  void extend(Offset point) {
    _points.add(point);
    _path.lineTo(point.dx, point.dy);
  }

  /// How far a touch may miss the line and still count. Generous on
  /// purpose: the line is thin and the finger grabbing it is not.
  double get _slop => strokeWidth * 4;

  @override
  bool hitTest(Offset point) {
    if (_points.length == 1) {
      return (point - _points.single).distance <= _slop;
    }
    for (var i = 0; i < _points.length - 1; i++) {
      if (distanceToSegment(point, _points[i], _points[i + 1]) <= _slop) {
        return true;
      }
    }
    return false;
  }

  @override
  void moveBy(Offset delta) {
    for (var i = 0; i < _points.length; i++) {
      _points[i] += delta;
    }
    _path = _path.shift(delta);
  }

  /// Scales the shape only: the line keeps its weight, like resizing a
  /// drawing rather than zooming into one.
  @override
  void scaleBy(double factor, Offset anchor) {
    final path = Path()..moveTo(_points.first.dx, _points.first.dy);
    for (var i = 0; i < _points.length; i++) {
      _points[i] = anchor + (_points[i] - anchor) * factor;
      if (i == 0) {
        path.reset();
        path.moveTo(_points[i].dx, _points[i].dy);
      } else {
        path.lineTo(_points[i].dx, _points[i].dy);
      }
    }
    _path = path;
  }

  @override
  Rect get bounds {
    var rect = Rect.fromCircle(center: _points.first, radius: strokeWidth);
    for (final point in _points.skip(1)) {
      rect = rect.expandToInclude(
        Rect.fromCircle(center: point, radius: strokeWidth),
      );
    }
    return rect;
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
    required Offset start,
    required Offset end,
    required this.color,
    required this.strokeWidth,
  })  : _start = start,
        _end = end;

  Offset _start;

  /// The tail — where the drag began.
  Offset get start => _start;

  final Color color;

  /// In image pixels, like every annotation measurement.
  final double strokeWidth;

  Offset _end;

  /// The head — follows the finger while the drag is live.
  Offset get end => _end;

  void moveHead(Offset point) => _end = point;

  @override
  bool hitTest(Offset point) =>
      distanceToSegment(point, _start, _end) <= strokeWidth * 4;

  @override
  void moveBy(Offset delta) {
    _start += delta;
    _end += delta;
  }

  @override
  void scaleBy(double factor, Offset anchor) {
    _start = anchor + (_start - anchor) * factor;
    _end = anchor + (_end - anchor) * factor;
  }

  @override
  Rect get bounds => Rect.fromPoints(_start, _end).inflate(strokeWidth * 2);

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

/// Words placed on the screenshot, naming the problem where it happens.
final class TextAnnotation implements Annotation {
  TextAnnotation({
    required Offset position,
    required String text,
    required this.color,
    required double fontSize,
  })  : _position = position,
        _fontSize = fontSize,
        _text = text;

  Offset _position;

  /// Top-left corner of the words, in image pixels.
  Offset get position => _position;

  final Color color;

  double _fontSize;

  /// In image pixels, like every annotation measurement. Resizing a note
  /// means changing this.
  double get fontSize => _fontSize;

  String _text;
  String get text => _text;
  set text(String value) {
    _text = value;
    _painter = null;
  }

  /// Laying text out is not free, and the canvas repaints every frame of a
  /// drag; the layout is kept until the words change.
  TextPainter? _painter;

  TextPainter get _laidOut => _painter ??= TextPainter(
        text: TextSpan(
          text: _text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            // A screenshot can be any color; a subtle shadow keeps the
            // words legible on all of them without shouting.
            shadows: [
              Shadow(
                color: const Color(0x59000000),
                blurRadius: fontSize * 0.1,
                offset: Offset(0, fontSize * 0.04),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: fontSize * 16);

  /// Whether an image-space point lands on these words. Padded by half the
  /// font size: fingers are fat and labels are small.
  @override
  bool hitTest(Offset point) =>
      (position & _laidOut.size).inflate(fontSize / 2).contains(point);

  @override
  void moveBy(Offset delta) => _position += delta;

  @override
  void scaleBy(double factor, Offset anchor) {
    _fontSize *= factor;
    _position = anchor + (_position - anchor) * factor;
    _painter = null;
  }

  @override
  Rect get bounds => position & _laidOut.size;

  @override
  void draw(Canvas canvas) => _laidOut.paint(canvas, position);
}

/// Distance from [p] to the segment [a]–[b], in image pixels.
@visibleForTesting
double distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSquared == 0) return (p - a).distance;

  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lengthSquared)
      .clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// What a tap or drag on the canvas produces.
enum AnnotationTool { pen, arrow, text, move }

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
  AnnotationController({required this.strokeWidth, required this.imageSize});

  /// In image pixels — chosen by the session from the capture's pixel ratio.
  final double strokeWidth;

  /// The screenshot's dimensions, so a move can be stopped at the edge
  /// instead of letting a drawing be dragged off the picture and lost.
  final Size imageSize;

  final List<Annotation> _annotations = [];
  Annotation? _active;

  /// The annotation being dragged in move mode, and where the finger last
  /// was — deltas are applied incrementally so the drag can be stopped at
  /// the image edge mid-gesture.
  Annotation? _moving;
  Offset _movePoint = Offset.zero;

  Annotation? _selected;
  bool _resizing = false;

  /// The annotation whose selection box and resize handle are showing.
  Annotation? get selected => _selected;

  /// Where the resize handle sits, in image pixels — the selection box's
  /// bottom-right corner. The painter draws it here and the controller
  /// hit-tests it here, so the dot the reporter sees is the dot that works.
  Offset? get selectionHandle => _selected == null
      ? null
      : selectionRectOf(_selected!).bottomRight;

  /// The fixed corner a resize scales about — opposite the handle.
  Offset? get selectionAnchor =>
      _selected == null ? null : selectionRectOf(_selected!).topLeft;

  /// The box drawn around a selected annotation, padded off its edges.
  Rect selectionRectOf(Annotation annotation) =>
      annotation.bounds.inflate(strokeWidth * 1.5);

  void select(Annotation? annotation) {
    if (_selected == annotation) return;
    _selected = annotation;
    notifyListeners();
  }

  bool _isOnHandle(Offset point) {
    final handle = selectionHandle;
    return handle != null && (point - handle).distance <= strokeWidth * 5;
  }
  Color _color = annotationColors.first;
  AnnotationTool _tool = AnnotationTool.pen;

  List<Annotation> get annotations => List.unmodifiable(_annotations);

  bool get hasAnnotations => _annotations.isNotEmpty;

  bool get canUndo =>
      _annotations.isNotEmpty &&
      _active == null &&
      _moving == null &&
      !_resizing;

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
    // The selection box belongs to the move tool; a drawing tool showing it
    // would suggest drags affect the selected shape when they draw instead.
    if (value != AnnotationTool.move) _selected = null;
    notifyListeners();
  }

  void startStroke(Offset imagePoint) {
    // A second start before the first ended: a stray extra pointer. The
    // drawing in progress wins; starting another would corrupt it.
    if (_active != null || _moving != null) return;

    if (_tool == AnnotationTool.move) {
      if (_isOnHandle(imagePoint)) {
        _resizing = true;
        _movePoint = imagePoint;
        notifyListeners();
        return;
      }
      _moving = annotationAt(imagePoint);
      // Grabbing is selecting: the box follows the drawing under the
      // finger. A drag on empty canvas leaves the selection alone.
      if (_moving != null && _moving != _selected) {
        _selected = _moving;
      }
      _movePoint = imagePoint;
      notifyListeners();
      return;
    }

    final Annotation? annotation = switch (_tool) {
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
      // Labels are placed by tap, not drawn by drag; moving is handled
      // above before anything is created.
      AnnotationTool.text || AnnotationTool.move => null,
    };
    if (annotation == null) return;
    _active = annotation;
    _annotations.add(annotation);
    notifyListeners();
  }

  void extendStroke(Offset imagePoint) {
    if (_resizing && _selected != null) {
      final anchor = selectionAnchor!;
      final before = (_movePoint - anchor).distance;
      final after = (imagePoint - anchor).distance;
      _movePoint = imagePoint;
      if (before < strokeWidth) return;

      final selected = _selected!;
      final factor = after / before;
      selected.scaleBy(factor, anchor);
      // Undone rather than clamped: reverting the step the moment the size
      // leaves the acceptable range stops it exactly at the limit.
      if (!_acceptableSize(selected.bounds)) {
        selected.scaleBy(1 / factor, anchor);
      }
      notifyListeners();
      return;
    }

    if (_moving case final moving?) {
      final delta = imagePoint - _movePoint;
      _movePoint = imagePoint;
      moving.moveBy(delta);
      // Undone rather than clamped: reverting the step the moment the
      // drawing would leave the picture stops it exactly at the edge.
      if (!moving.bounds.overlaps(Offset.zero & imageSize)) {
        moving.moveBy(-delta);
      }
      notifyListeners();
      return;
    }

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
    _moving = null;
    _resizing = false;
    notifyListeners();
  }

  /// Small enough to stay on the picture, big enough to grab again.
  bool _acceptableSize(Rect bounds) =>
      bounds.longestSide >= strokeWidth * 5 &&
      bounds.longestSide <= imageSize.longestSide &&
      bounds.overlaps(Offset.zero & imageSize);

  /// The topmost annotation of any kind under an image-space point.
  Annotation? annotationAt(Offset imagePoint) {
    for (final annotation in _annotations.reversed) {
      if (annotation.hitTest(imagePoint)) return annotation;
    }
    return null;
  }

  /// Words the label tool renders, sized to read like body text whatever
  /// the capture's pixel ratio.
  double get labelFontSize => strokeWidth * 4;

  /// Places a label, or refuses one with nothing to say.
  TextAnnotation? addLabel(Offset imagePoint, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final label = TextAnnotation(
      position: imagePoint,
      text: trimmed,
      color: _color,
      fontSize: labelFontSize,
    );
    _annotations.add(label);
    notifyListeners();
    return label;
  }

  /// Rewords a label; rewording it down to nothing removes it, because an
  /// empty label marks nothing.
  void updateLabel(TextAnnotation label, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _annotations.remove(label);
    } else {
      label.text = trimmed;
    }
    notifyListeners();
  }

  /// The topmost label under an image-space point, if any — so a tap can
  /// mean "edit these words" rather than "add more".
  TextAnnotation? labelAt(Offset imagePoint) {
    for (final annotation in _annotations.reversed) {
      if (annotation case final TextAnnotation label
          when label.hitTest(imagePoint)) {
        return label;
      }
    }
    return null;
  }

  /// Removes the most recent annotation. Ignored mid-drag: undoing the stroke
  /// under the reporter's finger would leave the drag orphaned.
  void undo() {
    if (!canUndo) return;
    final removed = _annotations.removeLast();
    if (_selected == removed) _selected = null;
    notifyListeners();
  }
}
