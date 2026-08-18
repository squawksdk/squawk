import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/src/capture/annotation_canvas.dart';

/// The display-to-image mapping is the whole no-drift guarantee, so it is
/// pinned here as arithmetic — the coordinates in a report depend on nothing
/// but the image and where it was fitted.
void main() {
  group('fitting the image into the viewport', () {
    test('letterboxes left and right when the viewport is wider', () {
      final rect = displayRectFor(const Size(200, 100), const Size(600, 200));

      expect(rect, const Rect.fromLTWH(100, 0, 400, 200));
    });

    test('letterboxes top and bottom when the viewport is taller', () {
      final rect = displayRectFor(const Size(200, 100), const Size(200, 400));

      expect(rect, const Rect.fromLTWH(0, 150, 200, 100));
    });

    test('a zero-sized viewport or image yields nothing to draw on', () {
      expect(displayRectFor(Size.zero, const Size(100, 100)), Rect.zero);
      expect(displayRectFor(const Size(100, 100), Size.zero), Rect.zero);
    });
  });

  group('mapping a touch to an image pixel', () {
    const image = Size(200, 100);

    test('hits the same pixel whatever size or shape the viewport is', () {
      // The drift bug, restated as arithmetic: a touch over a given pixel
      // must resolve to that pixel at any display size — including when the
      // letterbox sits on different sides.
      final wide = displayRectFor(image, const Size(600, 200));
      final tall = displayRectFor(image, const Size(200, 400));

      // Image pixel (50, 25), as displayed in each viewport.
      expect(toImagePoint(const Offset(200, 50), wide, image),
          const Offset(50, 25));
      expect(toImagePoint(const Offset(50, 175), tall, image),
          const Offset(50, 25));
    });

    test('accounts for the letterbox offset', () {
      final rect = displayRectFor(image, const Size(600, 200));

      expect(toImagePoint(const Offset(100, 0), rect, image), Offset.zero);
      expect(toImagePoint(const Offset(500, 200), rect, image),
          const Offset(200, 100));
    });

    test('a touch off the picture clamps to its edge', () {
      final rect = displayRectFor(image, const Size(600, 200));

      expect(toImagePoint(const Offset(0, 50), rect, image),
          const Offset(0, 25));
      expect(toImagePoint(const Offset(599, 300), rect, image),
          const Offset(200, 100));
    });
  });
}
