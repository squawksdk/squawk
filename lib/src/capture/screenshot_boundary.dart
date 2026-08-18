// Derived from the `feedback` package (https://pub.dev/packages/feedback),
// Copyright the feedback authors, Apache License 2.0. Modified for Squawk:
// captures a ui.Image after the end of the current frame instead of PNG
// bytes after a fixed delay, and fails soft. See NOTICE.
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Marks the part of the tree a capture photographs — the host app, and
/// nothing of Squawk's own UI.
class ScreenshotBoundary extends StatelessWidget {
  const ScreenshotBoundary({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScreenshotController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: controller._boundaryKey, child: child);
}

/// Takes the picture.
class ScreenshotController {
  final GlobalKey _boundaryKey =
      GlobalKey(debugLabel: 'squawk_screenshot_boundary');

  /// The boundary as a [ui.Image], or null when it cannot be captured.
  ///
  /// Waits for the end of the frame first, so anything that just hid itself
  /// for the photo — the floating report button — is genuinely gone from the
  /// raster before it is taken.
  ///
  /// Null rather than a throw: capture failing is a Squawk problem, and the
  /// caller's job is to stand down quietly, not to surface an exception in
  /// the host app.
  Future<ui.Image?> capture({required double pixelRatio}) async {
    try {
      await WidgetsBinding.instance.endOfFrame;

      final renderObject = _boundaryKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary ||
          renderObject.size.isEmpty) {
        _reportNotCapturable();
        return null;
      }

      return await renderObject.toImage(pixelRatio: pixelRatio);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'squawk',
          context: ErrorDescription('while taking the screenshot'),
        ),
      );
      return null;
    }
  }

  void _reportNotCapturable() {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError(
          'Squawk could not take a screenshot: the capture boundary is not '
          'mounted or has no size.',
        ),
        library: 'squawk',
        context: ErrorDescription('while taking the screenshot'),
      ),
    );
  }
}
