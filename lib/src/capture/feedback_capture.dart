import 'dart:async';

import 'package:feedback/feedback.dart';
import 'package:flutter/widgets.dart';

import '../squawk_report.dart';
import 'report_capture.dart';
import 'squawk_feedback_form.dart';

/// [ReportCapture] backed by the OSS `feedback` package.
///
/// This is the only file in the SDK that knows `feedback` exists. Everything
/// it produces is converted to [SquawkReport] here, so no `feedback` type
/// reaches the public API or the upload path.
class FeedbackCapture implements ReportCapture {
  const FeedbackCapture({this.askReporterEmail = true});

  final bool askReporterEmail;

  @override
  Widget wrap(Widget child) => BetterFeedback(
        feedbackBuilder: (context, onSubmit, scrollController) =>
            SquawkFeedbackForm(
          onSubmit: onSubmit,
          scrollController: scrollController,
          askReporterEmail: askReporterEmail,
        ),
        child: child,
      );

  @override
  Future<SquawkReport?> capture(BuildContext context) {
    final controller = BetterFeedback.of(context);
    final completer = Completer<SquawkReport?>();

    // `feedback` calls its callback on submit only — per its own docs, "if
    // the user aborts the process of giving feedback, onFeedback is not
    // called". Watching the controller is the only way to learn the sheet was
    // dismissed; without it the capture hangs and the caller can never open
    // another one.
    void onVisibilityChanged() {
      if (!controller.isVisible && !completer.isCompleted) {
        completer.complete(null);
      }
    }

    controller.addListener(onVisibilityChanged);
    completer.future
        .whenComplete(() => controller.removeListener(onVisibilityChanged));

    controller.show((UserFeedback feedback) {
      if (completer.isCompleted) return;
      completer.complete(
        SquawkReport(
          screenshot: feedback.screenshot,
          text: feedback.text.isEmpty ? null : feedback.text,
          reporterEmail:
              feedback.extra?[SquawkFeedbackForm.emailExtraKey] as String?,
        ),
      );
    });

    return completer.future;
  }
}
