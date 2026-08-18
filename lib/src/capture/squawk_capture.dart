import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../squawk_report.dart';
import 'annotations.dart';
import 'capture_overlay.dart';
import 'capture_shell.dart';
import 'composite.dart';
import 'report_capture.dart';
import 'screenshot_boundary.dart';

/// [ReportCapture] owned entirely by Squawk.
///
/// The screenshot is taken the moment capture starts, and everything after —
/// drawing, the form, submitting — happens over that still image. Pixels and
/// annotations share one coordinate space from the first stroke, which is
/// what makes drift (SQUAW-34) impossible rather than merely fixed.
class SquawkCapture implements ReportCapture {
  const SquawkCapture({this.askReporterEmail = true});

  final bool askReporterEmail;

  /// Screenshots above this are wasted bytes: the capture is capped so a
  /// high-density tablet does not spool 20 MB images.
  static const double maxPixelRatio = 3.0;

  @override
  Widget wrap(Widget child) =>
      CaptureHost(askReporterEmail: askReporterEmail, child: child);

  @override
  Future<SquawkReport?> capture(BuildContext context) {
    final host = context.findAncestorStateOfType<CaptureHostState>();
    if (host == null) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError(
            'Squawk capture was requested outside its own widget tree. '
            'This is a Squawk bug.',
          ),
          library: 'squawk',
          context: ErrorDescription('while starting a capture'),
        ),
      );
      return Future.value(null);
    }
    return host.beginSession();
  }
}

/// Everything one capture holds while it is on screen.
class _CaptureSession {
  _CaptureSession({required this.image, required this.annotations});

  final ui.Image image;
  final AnnotationController annotations;
  final Completer<SquawkReport?> completer = Completer();
}

/// Hosts the screenshot boundary and, while a session runs, the overlay.
///
/// The overlay is a sibling of the boundary, not a child — it can never
/// appear in its own screenshot, whatever the timing.
class CaptureHost extends StatefulWidget {
  const CaptureHost({
    super.key,
    required this.askReporterEmail,
    required this.child,
  });

  final bool askReporterEmail;
  final Widget child;

  @override
  State<CaptureHost> createState() => CaptureHostState();
}

class CaptureHostState extends State<CaptureHost> {
  final _screenshot = ScreenshotController();
  _CaptureSession? _session;

  /// Covers the window between a session being requested and its screenshot
  /// arriving — [_session] is not set yet, but a second capture must not
  /// start either.
  bool _starting = false;

  /// Captures the screen and shows the overlay; resolves when the reporter
  /// submits (a report) or walks away (null).
  Future<SquawkReport?> beginSession() async {
    // The controller's isCapturing guard runs first; this is the backstop
    // for any other path to the seam.
    if (_starting || _session != null) return null;
    _starting = true;

    try {
      final pixelRatio = math.min(
        View.of(context).devicePixelRatio,
        SquawkCapture.maxPixelRatio,
      );

      final image = await _screenshot.capture(pixelRatio: pixelRatio);
      if (image == null) return null;
      if (!mounted) {
        image.dispose();
        return null;
      }

      final session = _CaptureSession(
        image: image,
        // Stroke weight in image pixels, so it looks the same on screen and
        // in the uploaded PNG.
        annotations: AnnotationController(strokeWidth: 4 * pixelRatio),
      );
      setState(() => _session = session);

      return session.completer.future;
    } finally {
      _starting = false;
    }
  }

  Future<void> _submit(String text, String? email) async {
    final session = _session;
    if (session == null) return;

    // A submit can land mid-drag; the stroke under the finger is kept.
    session.annotations.endStroke();

    final bytes = await annotatedPng(
      screenshot: session.image,
      annotations: session.annotations.annotations,
    );

    // Null means even the plain screenshot could not be encoded — already
    // reported inside annotatedPng. Nothing sendable remains.
    if (bytes == null) {
      _endSession(null);
      return;
    }

    final trimmed = text.trim();
    _endSession(
      SquawkReport(
        screenshot: bytes,
        text: trimmed.isEmpty ? null : trimmed,
        reporterEmail: email,
      ),
    );
  }

  void _endSession(SquawkReport? result) {
    final session = _session;
    if (session == null) return;

    setState(() => _session = null);
    // The overlay's painter may still hold the image for the frame that
    // removes it; dispose once that frame is done.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      session.image.dispose();
      session.annotations.dispose();
    });

    if (!session.completer.isCompleted) session.completer.complete(result);
  }

  @override
  void dispose() {
    // The host can be unmounted mid-session; the caller must get its answer,
    // not hang forever.
    final session = _session;
    if (session != null) {
      _session = null;
      if (!session.completer.isCompleted) session.completer.complete(null);
      session.image.dispose();
      session.annotations.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;

    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.passthrough,
      children: [
        ScreenshotBoundary(controller: _screenshot, child: widget.child),
        if (session != null)
          CaptureShell(
            child: CaptureOverlay(
              image: session.image,
              annotations: session.annotations,
              askReporterEmail: widget.askReporterEmail,
              onSubmit: _submit,
              onDismiss: () => _endSession(null),
            ),
          ),
      ],
    );
  }
}
