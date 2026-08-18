import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

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
/// Gestures are converted to image pixels on the way in, and painting applies
/// the single image-to-viewport transform on the way out — preview and final
/// composite are the same drawing.
class AnnotationCanvas extends StatelessWidget {
  const AnnotationCanvas({
    super.key,
    required this.image,
    required this.controller,
  });

  final ui.Image image;
  final AnnotationController controller;

  Size get _imageSize =>
      Size(image.width.toDouble(), image.height.toDouble());

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final display = displayRectFor(_imageSize, constraints.biggest);
        if (display.isEmpty) return const SizedBox.expand();

        Offset toImage(Offset local) =>
            toImagePoint(local, display, _imageSize);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => controller.startStroke(toImage(d.localPosition)),
          onPanUpdate: (d) => controller.extendStroke(toImage(d.localPosition)),
          onPanEnd: (_) => controller.endStroke(),
          onPanCancel: controller.endStroke,
          child: CustomPaint(
            size: constraints.biggest,
            painter: _AnnotatedImagePainter(
              image: image,
              controller: controller,
              displayRect: display,
            ),
          ),
        );
      },
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
      ..scale(scale);

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

    canvas.restore();
  }

  @override
  bool shouldRepaint(_AnnotatedImagePainter old) =>
      old.image != image ||
      old.displayRect != displayRect ||
      old.controller != controller;
}
