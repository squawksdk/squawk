import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/feedback_button.dart';
import 'package:squawk/src/shake_trigger.dart';
import 'package:squawk/src/squawk_controller.dart';

import 'support/fakes.dart';

/// `enabled: false` is how an app keeps Squawk out of the build the public
/// gets while shipping the same code to testers. Off has to mean off: not
/// listening, not buffering, not uploading, and not complaining.
void main() {
  setUp(() => resetSquawk());

  List<FlutterErrorDetails> captureErrors() {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);
    return errors;
  }

  Widget app({
    required bool enabled,
    FakeCapture? capture,
    bool feedbackButton = false,
  }) =>
      Squawk(
        apiKey: 'sq_test_key',
        capture: capture ?? FakeCapture(),
        options: SquawkOptions(
          enabled: enabled,
          feedbackButton: feedbackButton,
        ),
        child: const Text('host app', textDirection: TextDirection.ltr),
      );

  testWidgets('renders the child and nothing else', (tester) async {
    await tester.pumpWidget(app(enabled: false, feedbackButton: true));

    expect(find.text('host app'), findsOneWidget);
    expect(find.byType(ShakeTrigger), findsNothing,
        reason: 'no shake listener may be installed');
    expect(find.byType(FeedbackButton), findsNothing,
        reason: 'the button must stay off even when asked for');
  });

  // The spool outlives any one build. A tester who reported on TestFlight
  // and then updated from the store must not have that report quietly
  // upload from the production build.
  testWidgets('does not start delivery', (tester) async {
    final storage =
        SquawkController.instance.spool!.storage as InMemorySpoolStorage;

    await tester.pumpWidget(app(enabled: false));
    await tester.pump();

    expect(storage.sweeps, 0, reason: 'nothing may be sent while disabled');
  });

  testWidgets('does not capture logs', (tester) async {
    final original = debugPrint;

    await tester.pumpWidget(app(enabled: false));

    expect(debugPrint, same(original), reason: 'no log hook may be installed');
  });

  // A production build with a "Report a bug" menu item calls show() on
  // every tap. Reporting an error there means an error in crash reporting
  // for every user who tries it, which is worse than doing nothing.
  testWidgets('show() does nothing and reports no error', (tester) async {
    final errors = captureErrors();
    final capture = FakeCapture(result: reportWith());
    await tester.pumpWidget(app(enabled: false, capture: capture));

    await expectLater(Squawk.show(), completes);

    expect(errors, isEmpty);
    expect(capture.captureCount, 0, reason: 'no sheet may open');
  });

  // The same message as before must still reach a developer who forgot to
  // mount Squawk at all. Disabled and missing are different situations.
  test('show() with nothing mounted still reports the error', () async {
    final errors = captureErrors();

    await expectLater(Squawk.show(), completes);

    expect(errors, hasLength(1));
  });

  testWidgets('enabled by default, so existing apps see no change',
      (tester) async {
    await tester.pumpWidget(
      Squawk(
        apiKey: 'sq_test_key',
        capture: FakeCapture(),
        child: const SizedBox(),
      ),
    );

    expect(find.byType(ShakeTrigger), findsOneWidget);
  });

  // The value is read at build time, so an app that learns late whether it
  // is a test install can rebuild with the answer, and the answer sticks.
  testWidgets('flipping to disabled stops what was running', (tester) async {
    final storage =
        SquawkController.instance.spool!.storage as InMemorySpoolStorage;
    await tester.pumpWidget(app(enabled: true));
    await tester.pump();
    expect(storage.sweeps, 1, reason: 'enabled starts delivery');

    await tester.pumpWidget(app(enabled: false));
    await tester.pump();

    expect(find.byType(ShakeTrigger), findsNothing);
    expect(SquawkController.instance.delivery!.isTimerRunning, isFalse,
        reason: 'delivery must stop when the host unmounts');
    expect(SquawkController.instance.disabled, isTrue);
  });

  testWidgets('flipping back to enabled starts again', (tester) async {
    await tester.pumpWidget(app(enabled: false));
    await tester.pumpWidget(app(enabled: true));
    await tester.pump();

    expect(find.byType(ShakeTrigger), findsOneWidget);
    expect(SquawkController.instance.disabled, isFalse,
        reason: 'mounting the real host must clear the disabled mark');
  });

  test('setUser and setMetadata still work, so context is ready if enabled',
      () {
    SquawkController.instance.disabled = true;

    Squawk.setUser(id: 'u_1', email: 'jo@example.com');
    Squawk.setMetadata('plan', 'trial');

    // Nothing to assert on directly without a report; the point is that
    // neither call throws or is swallowed while disabled.
    expect(() => Squawk.clearUser(), returnsNormally);
  });
}
