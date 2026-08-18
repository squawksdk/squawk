import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'annotations.dart';

/// The screenshot with the annotations burned in, as PNG bytes.
///
/// Falls back in steps rather than failing: if compositing breaks, the plain
/// screenshot still goes out — a report without the drawings beats no report,
/// because the reporter already tapped send and will not do it again. Null
/// only when even the plain screenshot cannot be encoded.
Future<Uint8List?> annotatedPng({
  required ui.Image screenshot,
  required List<Annotation> annotations,
}) async {
  if (annotations.isNotEmpty) {
    try {
      return await _encodeAnnotated(screenshot, annotations);
    } catch (error, stack) {
      _report(error, stack, 'while compositing annotations');
    }
  }

  try {
    return await _encode(screenshot);
  } catch (error, stack) {
    _report(error, stack, 'while encoding the screenshot');
    return null;
  }
}

Future<Uint8List?> _encodeAnnotated(
  ui.Image screenshot,
  List<Annotation> annotations,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  canvas.drawImage(screenshot, ui.Offset.zero, ui.Paint());
  for (final annotation in annotations) {
    annotation.draw(canvas);
  }

  final picture = recorder.endRecording();
  try {
    final composed = await picture.toImage(
      screenshot.width,
      screenshot.height,
    );
    try {
      return await _encode(composed);
    } finally {
      composed.dispose();
    }
  } finally {
    picture.dispose();
  }
}

Future<Uint8List?> _encode(ui.Image image) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes?.buffer.asUint8List();
}

void _report(Object error, StackTrace stack, String doing) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'squawk',
      context: ErrorDescription(doing),
    ),
  );
}
