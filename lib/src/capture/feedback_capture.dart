import 'dart:async';

import 'package:feedback/feedback.dart';
import 'package:flutter/widgets.dart';

import '../squawk_report.dart';
import 'report_capture.dart';

/// [ReportCapture] backed by the OSS `feedback` package.
///
/// This is the only file in the SDK that knows `feedback` exists. Everything
/// it produces is converted to [SquawkReport] here, so no `feedback` type
/// reaches the public API or the upload path.
class FeedbackCapture implements ReportCapture {
  @override
  Widget wrap(Widget child) => BetterFeedback(child: child);

  @override
  Future<SquawkReport?> capture(BuildContext context) {
    final completer = Completer<SquawkReport?>();

    BetterFeedback.of(context).show((UserFeedback feedback) {
      if (completer.isCompleted) return;
      completer.complete(
        SquawkReport(
          screenshot: feedback.screenshot,
          text: feedback.text.isEmpty ? null : feedback.text,
        ),
      );
    });

    return completer.future;
  }
}
