import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'annotations.dart';

/// Where the screenshot lands inside a viewport: fitted whole and centred,
/// letterboxed on whichever axis has room to spare.
///
/// A separate function so the display-to-image mapping — the heart of the
/// no-drift guarantee — can be tested as arithmetic.
Rect displayRectFor(Size imageSize, Size viewport) {
  if (imageSize.isEmpty || viewport.isEmpty) return Rect.zero;

  final scale = math.min(
    viewport.width / imageSize.width,
    viewport.height / imageSize.height,
  );
  final size = imageSize * scale;
  return Offset(
        (viewport.width - size.width) / 2,
        (viewport.height - size.height) / 2,
      ) &
      size;
}

/// The fitted rectangle enlarged by [zoom] about the viewport's centre and
/// shifted by [pan]. Zoom 1 with no pan is [displayRectFor] exactly.
Rect zoomedDisplayRect(Size imageSize, Size viewport, double zoom, Offset pan) {
  final fit = displayRectFor(imageSize, viewport);
  if (fit.isEmpty) return Rect.zero;
  return Rect.fromCenter(
    center: viewport.center(Offset.zero) + pan,
    width: fit.width * zoom,
    height: fit.height * zoom,
  );
}

/// Keeps a zoomed picture over the viewport: on an axis it overflows it may
/// not be dragged so far that a letterbox opens; on an axis it does not fill
/// it stays centred. At zoom 1 every pan collapses to zero.
Offset clampPan(Size imageSize, Size viewport, double zoom, Offset pan) {
  final fit = displayRectFor(imageSize, viewport);
  double axis(double value, double extent, double room) {
    final slack = (extent - room) / 2;
    return slack <= 0 ? 0 : value.clamp(-slack, slack);
  }

  return Offset(
    axis(pan.dx, fit.width * zoom, viewport.width),
    axis(pan.dy, fit.height * zoom, viewport.height),
  );
}

/// A viewport point in image pixels, clamped inside the image.
///
/// Clamping matters at the letterbox: a stroke that wanders off the picture
/// should hug its edge, not paint on pixels that do not exist.
Offset toImagePoint(Offset viewportPoint, Rect displayRect, Size imageSize) {
  final scale = displayRect.width / imageSize.width;
  final unclamped = (viewportPoint - displayRect.topLeft) / scale;
  return Offset(
    unclamped.dx.clamp(0.0, imageSize.width),
    unclamped.dy.clamp(0.0, imageSize.height),
  );
}

/// The still screenshot with the reporter's annotations over it.
///
/// One finger draws, two fingers zoom and pan, and a second finger landing
/// mid-stroke cancels that stroke rather than leaving a dot. Gestures are
/// converted to image pixels on the way in, and painting applies the single
/// image-to-viewport transform on the way out — preview and final composite
/// are the same drawing, whatever the zoom.
class AnnotationCanvas extends StatefulWidget {
  const AnnotationCanvas({
    super.key,
    required this.image,
    required this.controller,
    this.onLabelRequested,
  });

  final ui.Image image;
  final AnnotationController controller;

  /// A tap while the text tool is in hand, in image pixels. The owner shows
  /// the editor; the canvas only knows where.
  final ValueChanged<Offset>? onLabelRequested;

  static const Key resetZoomKey = Key('squawk_reset_zoom');

  /// Four times the fitted size. Enough to circle a 20pt control with a
  /// finger; more and the picture turns to pixels.
  static const double maxZoom = 4;

  /// How far a finger may wander before a tap becomes a drag, in viewport
  /// pixels. Below the platform slop on purpose: a label placed by a tap
  /// should land where the finger first touched.
  static const double tapSlop = 8;

  @override
  State<AnnotationCanvas> createState() => _AnnotationCanvasState();
}

/// What the finger or fingers on the canvas are currently doing.
enum _Gesture {
  none,

  /// One finger down with the move or text tool, not yet past the slop:
  /// still a tap unless it travels.
  pending,
  drawing,
  moving,
  pinching,

  /// A pinch ended with a finger still down. That finger draws nothing;
  /// it was half of a zoom, not the start of a stroke.
  spent,
}

class _AnnotationCanvasState extends State<AnnotationCanvas> {
  Size get _imageSize =>
      Size(widget.image.width.toDouble(), widget.image.height.toDouble());

  double _zoom = 1;
  Offset _pan = Offset.zero;

  /// The viewport as of the last layout, so a rotation can reset the zoom
  /// instead of leaving the pan pointing at a place that no longer exists.
  Size? _viewport;

  _Gesture _gesture = _Gesture.none;
  final _pointers = <int, Offset>{};
  int? _leadPointer;
  Offset _downPoint = Offset.zero;

  /// The focal point and finger spacing at the last pinch update, so each
  /// move is applied as a delta from the one before.
  Offset _pinchFocal = Offset.zero;
  double _pinchSpan = 0;

  Rect get _display =>
      zoomedDisplayRect(_imageSize, _viewport ?? Size.zero, _zoom, _pan);

  Offset _toImage(Offset local) => toImagePoint(local, _display, _imageSize);

  void _resetZoom() => setState(() {
    _zoom = 1;
    _pan = Offset.zero;
  });

  // ---- pointers ----

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;

    switch (_gesture) {
      case _Gesture.none:
        _leadPointer = event.pointer;
        _downPoint = event.localPosition;
        switch (widget.controller.tool) {
          case AnnotationTool.pen || AnnotationTool.arrow:
            // Started on touch, not after a slop: a stroke begins exactly
            // where the finger landed, and a bare tap leaves the dot the
            // pen has always left.
            widget.controller.startStroke(_toImage(event.localPosition));
            _gesture = _Gesture.drawing;
          case AnnotationTool.move || AnnotationTool.text:
            _gesture = _Gesture.pending;
        }
      case _Gesture.drawing:
        // A second finger means a zoom, and the half-drawn stroke was never
        // meant: it goes, rather than staying as a smear under the pinch.
        widget.controller.cancelStroke();
        _beginPinch();
      case _Gesture.moving:
        widget.controller.endStroke();
        _beginPinch();
      case _Gesture.pending:
        _beginPinch();
      case _Gesture.pinching || _Gesture.spent:
        break;
    }
  }

  void _beginPinch() {
    _gesture = _Gesture.pinching;
    _leadPointer = null;
    final pair = _pointers.values.take(2).toList();
    _pinchFocal = (pair[0] + pair[1]) / 2;
    _pinchSpan = (pair[0] - pair[1]).distance;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;

    switch (_gesture) {
      case _Gesture.drawing || _Gesture.moving:
        if (event.pointer == _leadPointer) {
          widget.controller.extendStroke(_toImage(event.localPosition));
        }
      case _Gesture.pending:
        if (event.pointer != _leadPointer) return;
        if ((event.localPosition - _downPoint).distance <=
            AnnotationCanvas.tapSlop) {
          return;
        }
        if (widget.controller.tool == AnnotationTool.move) {
          // The drag is reported from where the finger first touched, so
          // grabbing a thin line does not miss by the slop.
          widget.controller
            ..startStroke(_toImage(_downPoint))
            ..extendStroke(_toImage(event.localPosition));
          _gesture = _Gesture.moving;
        } else {
          // A text tap that travelled is nothing.
          _gesture = _Gesture.spent;
        }
      case _Gesture.pinching:
        _updatePinch();
      case _Gesture.none || _Gesture.spent:
        break;
    }
  }

  void _updatePinch() {
    final pair = _pointers.values.take(2).toList();
    if (pair.length < 2) return;
    final focal = (pair[0] + pair[1]) / 2;
    final span = (pair[0] - pair[1]).distance;
    if (_pinchSpan <= 0 || span <= 0) {
      _pinchFocal = focal;
      _pinchSpan = span;
      return;
    }

    final viewport = _viewport ?? Size.zero;
    final nextZoom = (_zoom * span / _pinchSpan).clamp(
      1.0,
      AnnotationCanvas.maxZoom,
    );

    // The image point under the old focal stays under the new one, so the
    // picture zooms about the fingers and follows them when they slide.
    final before = _display;
    final imagePoint =
        (_pinchFocal - before.topLeft) / (before.width / _imageSize.width);
    final fit = displayRectFor(_imageSize, viewport);
    final nextSize = fit.size * nextZoom;
    final nextScale = nextSize.width / _imageSize.width;
    final nextTopLeft = focal - imagePoint * nextScale;
    final nextCentre = nextTopLeft + nextSize.center(Offset.zero);
    final nextPan = nextCentre - viewport.center(Offset.zero);

    setState(() {
      _zoom = nextZoom;
      _pan = clampPan(_imageSize, viewport, nextZoom, nextPan);
    });
    _pinchFocal = focal;
    _pinchSpan = span;
  }

  void _onPointerEnd(PointerEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers.remove(event.pointer);

    switch (_gesture) {
      case _Gesture.drawing || _Gesture.moving:
        if (event.pointer != _leadPointer) return;
        widget.controller.endStroke();
        _gesture = _Gesture.none;
      case _Gesture.pending:
        if (event.pointer != _leadPointer) return;
        _gesture = _Gesture.none;
        if (event is PointerCancelEvent) return;
        final point = _toImage(_downPoint);
        switch (widget.controller.tool) {
          case AnnotationTool.text:
            widget.onLabelRequested?.call(point);
          case AnnotationTool.move:
            widget.controller.select(widget.controller.annotationAt(point));
          case AnnotationTool.pen || AnnotationTool.arrow:
            break;
        }
      case _Gesture.pinching:
        if (_pointers.length >= 2) {
          _beginPinch();
        } else {
          _gesture = _pointers.isEmpty ? _Gesture.none : _Gesture.spent;
        }
      case _Gesture.spent:
        if (_pointers.isEmpty) _gesture = _Gesture.none;
      case _Gesture.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        if (viewport != _viewport) {
          // Any zoom was relative to the old frame. Rebuild the fit and
          // start again rather than show a pan into nowhere.
          _viewport = viewport;
          _zoom = 1;
          _pan = Offset.zero;
        }
        final display = _display;
        if (display.isEmpty) return const SizedBox.expand();

        return Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerEnd,
              onPointerCancel: _onPointerEnd,
              child: ClipRect(
                child: CustomPaint(
                  size: viewport,
                  painter: _AnnotatedImagePainter(
                    image: widget.image,
                    controller: widget.controller,
                    displayRect: display,
                  ),
                ),
              ),
            ),
            // The way back to the whole picture, only while there is a way
            // back to offer.
            if (_zoom > 1)
              Positioned(
                right: 12,
                bottom: 12,
                child: _ResetZoomButton(
                  key: AnnotationCanvas.resetZoomKey,
                  onTap: _resetZoom,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ResetZoomButton extends StatelessWidget {
  const _ResetZoomButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.inverseSurface.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Semantics(
          button: true,
          label: 'Show the whole screenshot',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.fullscreen,
                  size: 18,
                  color: theme.colorScheme.onInverseSurface,
                ),
                const SizedBox(width: 6),
                Text(
                  'Fit',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onInverseSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnnotatedImagePainter extends CustomPainter {
  _AnnotatedImagePainter({
    required this.image,
    required this.controller,
    required this.displayRect,
  }) : super(repaint: controller);

  final ui.Image image;
  final AnnotationController controller;
  final Rect displayRect;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = displayRect.width / image.width;

    canvas
      ..save()
      ..translate(displayRect.left, displayRect.top)
      ..scale(scale)
      // The composite is cropped to the image, so the preview must be too —
      // a label running past the edge has to look cut off before it is sent.
      ..clipRect(
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      );

    // Drawn through the same transform as the annotations so the two can
    // never disagree about where a pixel is.
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.medium,
    );
    for (final annotation in controller.annotations) {
      annotation.draw(canvas);
    }
    _drawSelection(canvas);

    canvas.restore();
  }

  /// The selection box and its resize handle. Preview chrome only — the
  /// composite draws annotations and nothing else, so none of this can ever
  /// reach the uploaded PNG.
  void _drawSelection(Canvas canvas) {
    final selected = controller.selected;
    if (selected == null) return;

    final rect = controller.selectionRectOf(selected);
    final line = controller.strokeWidth * 0.45;
    const blue = Color(0xFF448AFF);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(line * 3)),
      Paint()
        ..color = blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = line,
    );

    final handle = rect.bottomRight;
    canvas.drawCircle(
      handle,
      controller.strokeWidth * 1.6,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      handle,
      controller.strokeWidth * 1.6,
      Paint()
        ..color = blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = line,
    );
  }

  @override
  bool shouldRepaint(_AnnotatedImagePainter old) =>
      old.image != image ||
      old.displayRect != displayRect ||
      old.controller != controller;
}
