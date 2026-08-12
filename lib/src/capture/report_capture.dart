import 'package:flutter/widgets.dart';

import '../squawk_report.dart';

/// Opens the capture experience and returns what the reporter produced.
///
/// This is the seam that keeps the annotation implementation replaceable. The
/// SDK ships on the OSS `feedback` package today and is expected to move to a
/// vendored painter once arrows and text labels are needed; only an
/// implementation of this interface should have to change.
abstract interface class ReportCapture {
  /// Wraps the host app with whatever the implementation needs above it.
  ///
  /// Capture packages typically insert their own widget at the app root, so
  /// the adapter owns that placement rather than [Squawk] assuming it.
  Widget wrap(Widget child);

  /// Shows the capture UI. Completes with `null` if the reporter dismissed it
  /// without submitting.
  ///
  /// [context] sits below the widget returned by [wrap].
  Future<SquawkReport?> capture(BuildContext context);
}
