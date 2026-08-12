import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/feedback_button.dart';
import 'package:squawk/src/squawk_controller.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => SquawkController.instance.reset());

  Widget app(FakeCapture capture, {required bool feedbackButton}) => Squawk(
        apiKey: 'k',
        capture: capture,
        options: SquawkOptions(feedbackButton: feedbackButton),
        child: const MaterialApp(home: Scaffold(body: Text('host app'))),
      );

  testWidgets('hidden by default', (tester) async {
    await tester.pumpWidget(
      app(FakeCapture(result: reportWith()), feedbackButton: false),
    );

    expect(find.byKey(FeedbackButton.buttonKey), findsNothing);
  });

  testWidgets('shown and tappable when enabled', (tester) async {
    final capture = FakeCapture(result: reportWith());
    await tester.pumpWidget(app(capture, feedbackButton: true));

    expect(find.byKey(FeedbackButton.buttonKey), findsOneWidget);

    await tester.tap(find.byKey(FeedbackButton.buttonKey));
    await tester.pumpAndSettle();

    expect(capture.captureCount, 1);
  });

  // The button sits inside the capture boundary, so if it were still on screen
  // when the screenshot is taken it would appear in the reporter's own report.
  testWidgets('hides itself while the sheet is open', (tester) async {
    final capture = FakeCapture(
      result: reportWith(),
      completeImmediately: false,
    );
    await tester.pumpWidget(app(capture, feedbackButton: true));

    await tester.tap(find.byKey(FeedbackButton.buttonKey));
    await tester.pump();

    expect(find.byKey(FeedbackButton.buttonKey), findsNothing);

    capture.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(FeedbackButton.buttonKey), findsOneWidget);
  });
}
