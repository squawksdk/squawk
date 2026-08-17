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

  /// Fraction of the screen the sheet occupies when it opens.
  ///
  /// The package defaults to 0.25, which fits one text box. Squawk's form has
  /// a description, a comment box, an optional email field and a button, and
  /// at 0.25 the scrollable area collapses to nothing — the comment box, the
  /// primary input, does not render at all.
  double get _sheetHeight => askReporterEmail ? 0.34 : 0.28;

  @override
  Widget wrap(Widget child) => BetterFeedback(
        theme: FeedbackThemeData.light()
            .copyWith(feedbackSheetHeight: _sheetHeight),
        darkTheme: FeedbackThemeData.dark()
            .copyWith(feedbackSheetHeight: _sheetHeight),
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
