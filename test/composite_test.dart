import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/src/capture/annotations.dart';
import 'package:squawk/src/capture/composite.dart';

/// Proves what actually ends up in the uploaded PNG, pixel by pixel — the
/// composite is the last place drift could sneak back in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const white = Color(0xFFFFFFFF);
  const red = Color(0xFFFF0000);

  Future<ui.Image> solidImage(int width, int height, Color color) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = color,
    );
    return recorder.endRecording().toImage(width, height);
  }

  Future<Color> pixelAt(Uint8List png, int x, int y) async {
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    final data =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final offset = (y * image.width + x) * 4;
    final bytes = data.buffer.asUint8List();
    image.dispose();
    return Color.fromARGB(
      bytes[offset + 3],
      bytes[offset],
      bytes[offset + 1],
      bytes[offset + 2],
    );
  }

  test('a stroke lands on exactly the pixels it was drawn at', () async {
    final screenshot = await solidImage(100, 100, white);
    final stroke = StrokeAnnotation(
      start: const Offset(10, 50),
      color: red,
      strokeWidth: 8,
    )..extend(const Offset(90, 50));

    final png = await annotatedPng(
      screenshot: screenshot,
      annotations: [stroke],
    );

    expect(await pixelAt(png!, 50, 50), red,
        reason: 'the line runs through here');
    expect(await pixelAt(png, 50, 10), white,
        reason: 'above the line the screenshot is untouched');
  });

  test('a tap leaves a visible dot, not nothing', () async {
    final screenshot = await solidImage(100, 100, white);
    final dot = StrokeAnnotation(
      start: const Offset(30, 30),
      color: red,
      strokeWidth: 8,
    );

    final png = await annotatedPng(screenshot: screenshot, annotations: [dot]);

    expect(await pixelAt(png!, 30, 30), red);
  });

  test('an arrow lands shaft, head and all where it was drawn', () async {
    final screenshot = await solidImage(100, 100, white);
    final arrow = ArrowAnnotation(
      start: const Offset(10, 50),
      end: const Offset(90, 50),
      color: red,
      strokeWidth: 4,
    );

    final png = await annotatedPng(
      screenshot: screenshot,
      annotations: [arrow],
    );

    expect(await pixelAt(png!, 40, 50), red, reason: 'the shaft runs here');
    expect(await pixelAt(png, 85, 50), red, reason: 'inside the head');
    expect(await pixelAt(png, 40, 20), white,
        reason: 'away from the arrow the screenshot is untouched');
  });

  test('no annotations means the screenshot goes out untouched', () async {
    final screenshot = await solidImage(60, 40, red);

    final png = await annotatedPng(screenshot: screenshot, annotations: []);

    expect(png, isNotNull);
    expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(await pixelAt(png, 30, 20), red);
  });

  test('the composite keeps the screenshot dimensions', () async {
    final screenshot = await solidImage(120, 80, white);
    final stroke = StrokeAnnotation(
      start: Offset.zero,
      color: red,
      strokeWidth: 4,
    )..extend(const Offset(500, 500));

    final png = await annotatedPng(
      screenshot: screenshot,
      annotations: [stroke],
    );

    final codec = await ui.instantiateImageCodec(png!);
    final image = (await codec.getNextFrame()).image;
    expect(image.width, 120);
    expect(image.height, 80);
    image.dispose();
  });
}
