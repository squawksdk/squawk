import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/squawk_controller.dart';

/// Drives the real `feedback` UI rather than a fake.
///
/// The other tests prove the SDK's own logic through the capture seam; these
/// prove the adapter behind it is actually wired to a working sheet. They are
/// the tests that would catch `feedback` breaking on a future Flutter.
void main() {
  setUp(() => SquawkController.instance.reset());

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

  testWidgets('submitting returns a report carrying real screenshot bytes',
      (tester) async {
    await tester.pumpWidget(hostApp());

    SquawkReport? report;
    unawaited(SquawkController.instance.show().then((r) => report = r));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'the button is red');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submit_feedback_button')));

    // `feedback` submits across two clocks: a Future.delayed on the fake test
    // clock, then RepaintBoundary.toImage() which only resolves against the
    // real one. Pumping advances the first; runAsync serves the second.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pumpAndSettle();

    expect(report, isNotNull);
    expect(report!.text, 'the button is red');
    expect(report!.screenshot, isNotEmpty);
    // PNG magic number — proves real encoded image bytes, not a placeholder.
    expect(report!.screenshot.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });
}

void unawaited(Future<void> future) {}
