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

  group('zoomedDisplayRect', () {
    const image = Size(1000, 2000);
    const viewport = Size(400, 800);

    test('at zoom 1 with no pan it is the fitted rectangle', () {
      expect(
        zoomedDisplayRect(image, viewport, 1, Offset.zero),
        displayRectFor(image, viewport),
      );
    });

    test('zoom grows the picture about the viewport centre', () {
      final rect = zoomedDisplayRect(image, viewport, 2, Offset.zero);
      expect(rect.size, const Size(800, 1600));
      expect(rect.center, const Offset(200, 400));
    });

    test('pan moves the picture by that much', () {
      final rect = zoomedDisplayRect(image, viewport, 2, const Offset(-50, 30));
      expect(rect.center, const Offset(150, 430));
    });
  });

  group('clampPan', () {
    const image = Size(1000, 2000);
    const viewport = Size(400, 800);

    test('at zoom 1 every pan is zero', () {
      expect(clampPan(image, viewport, 1, const Offset(90, -90)), Offset.zero);
    });

    test('a zoomed picture may not open a letterbox', () {
      // Twice the size: 800x1600 in a 400x800 viewport, so 200 and 400 of
      // slack each way.
      expect(
        clampPan(image, viewport, 2, const Offset(500, -900)),
        const Offset(200, -400),
      );
      expect(
        clampPan(image, viewport, 2, const Offset(-10, 10)),
        const Offset(-10, 10),
      );
    });

    test('an axis the picture does not fill stays centred', () {
      // A wide viewport: the fitted picture is 400 wide in 1000, and at
      // zoom 2 still only 800, so no sideways pan is possible.
      expect(
        clampPan(image, const Size(1000, 800), 2, const Offset(300, 100)),
        const Offset(0, 100),
      );
    });
  });
}
