import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/capture/squawk_feedback_form.dart';
import 'package:squawk/src/squawk_controller.dart';

import 'support/fakes.dart';

/// Drives the real `feedback` UI rather than a fake.
///
/// The other tests prove the SDK's own logic through the capture seam; these
/// prove the adapter behind it is actually wired to a working sheet. They are
/// the tests that would catch `feedback` breaking on a future Flutter.
void main() {
  setUp(() => resetSquawk());

  Widget hostApp() => const Squawk(
        apiKey: 'sq_test_key',
        child: MaterialApp(
          home: Scaffold(body: Center(child: Text('host app'))),
        ),
      );

  testWidgets('show() opens the real feedback sheet over the host app',
      (tester) async {
    await tester.pumpWidget(hostApp());
    expect(find.text('host app'), findsOneWidget);
    expect(find.text('Submit'), findsNothing);

    unawaited(Squawk.show());
    await tester.pumpAndSettle();

    expect(find.text("What's wrong?"), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);
  });

  // Found on a real device: the sheet opened once and then never again.
  // `feedback` only invokes its callback on submit — "if the user aborts the
  // process of giving feedback, onFeedback is not called" — so dismissing left
  // the capture pending forever and the re-entrancy guard swallowed every
  // later shake.
  testWidgets('dismissing the sheet completes the capture and re-arms',
      (tester) async {
    await tester.pumpWidget(hostApp());

    var completed = false;
    SquawkReport? report;
    SquawkController.instance.show().then((r) {
      report = r;
      completed = true;
    });
    await tester.pumpAndSettle();
    expect(find.text('Submit'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(completed, isTrue, reason: 'the capture must not hang on dismiss');
    expect(report, isNull);
    expect(SquawkController.instance.isCapturing.value, isFalse);

    // The whole point: the trigger has to work a second time.
    unawaited(SquawkController.instance.show());
    await tester.pumpAndSettle();
    expect(find.text('Submit'), findsOneWidget);
  });

  testWidgets('submitting returns a report carrying real screenshot bytes',
      (tester) async {
    await tester.pumpWidget(hostApp());

    SquawkReport? report;
    unawaited(SquawkController.instance.show().then((r) => report = r));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(SquawkFeedbackForm.textKey),
      'the button is red',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(SquawkFeedbackForm.submitKey));

    // `feedback` submits across two clocks: a Future.delayed on the fake test
    // clock, then RepaintBoundary.toImage() which only resolves against the
    // real one. Pumping advances the first; runAsync serves the second.
    await tester.pump(const Duration(milliseconds: 300));
    await waitReal(tester, () => report != null);
    await tester.pumpAndSettle();

    expect(report, isNotNull);
    expect(report!.text, 'the button is red');
    expect(report!.screenshot, isNotEmpty);
    // PNG magic number — proves real encoded image bytes, not a placeholder.
    expect(report!.screenshot.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });
}

void unawaited(Future<void> future) {}
