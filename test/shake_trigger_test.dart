import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/capture/report_capture.dart';

import 'support/fakes.dart';

void main() {
  late FakeShakeChannel shake;

  setUp(resetSquawk);

  // AppLifecycleListener asserts on state jumps, so tests walk the same
  // sequences a real platform sends.
  void background(WidgetTester tester) {
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }

  void foreground(WidgetTester tester) {
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  Widget app(ReportCapture capture, {SquawkOptions? options}) => Squawk(
        apiKey: 'sq_test_key',
        capture: capture,
        options: options ?? const SquawkOptions(),
        child: const SizedBox(),
      );

  testWidgets('a shake opens the report sheet', (tester) async {
    shake = FakeShakeChannel()..install(tester);
    final capture = FakeCapture(result: reportWith());
    await tester.pumpWidget(app(capture));

    shake.simulateShake();
    await tester.pumpAndSettle();

    expect(capture.captureCount, 1);
  });

  testWidgets('shakeToReport: false never touches the channel', (tester) async {
    shake = FakeShakeChannel()..install(tester);
    final capture = FakeCapture(result: reportWith());
    await tester.pumpWidget(
      app(capture, options: const SquawkOptions(shakeToReport: false)),
    );

    expect(shake.listenArgs, isEmpty);

    shake.simulateShake();
    await tester.pumpAndSettle();

    expect(capture.captureCount, 0);
  });

  testWidgets('unmounting stops the trigger listening', (tester) async {
    shake = FakeShakeChannel()..install(tester);
    await tester.pumpWidget(app(FakeCapture(result: reportWith())));
    expect(shake.listening, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(shake.listening, isFalse);
  });

  // The force number is the contract with the native detector: acceleration
  // beyond gravity, in m/s². These pin the enum-to-number mapping so a
  // refactor cannot silently change how hard every customer has to shake.
  testWidgets('the default sensitivity sends the force shake_gesture used',
      (tester) async {
    shake = FakeShakeChannel()..install(tester);
    await tester.pumpWidget(app(FakeCapture(result: reportWith())));

    expect(shake.listenArgs.single, {'force': 6.0});
  });

  testWidgets('light and firm map to their forces', (tester) async {
    shake = FakeShakeChannel()..install(tester);
    await tester.pumpWidget(app(
      FakeCapture(result: reportWith()),
      options: const SquawkOptions(shakeSensitivity: ShakeSensitivity.light),
    ));
    expect(shake.listenArgs.single, {'force': 4.0});

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    await tester.pumpWidget(app(
      FakeCapture(result: reportWith()),
      options: const SquawkOptions(shakeSensitivity: ShakeSensitivity.firm),
    ));
    expect(shake.listenArgs.last, {'force': 10.0});
  });

  testWidgets('backgrounding releases the sensor, resuming re-arms it',
      (tester) async {
    shake = FakeShakeChannel()..install(tester);
    final capture = FakeCapture(result: reportWith());
    await tester.pumpWidget(app(capture));
    expect(shake.listening, isTrue);

    background(tester);
    await tester.pump();
    expect(shake.listening, isFalse,
        reason: 'a backgrounded app must not hold the accelerometer');

    foreground(tester);
    await tester.pump();
    expect(shake.listening, isTrue);

    shake.simulateShake();
    await tester.pumpAndSettle();
    expect(capture.captureCount, 1);
  });

  testWidgets('a channel error disables the trigger for good', (tester) async {
    shake = FakeShakeChannel()..install(tester);
    final capture = FakeCapture(result: reportWith());
    await tester.pumpWidget(app(capture));

    shake.simulateError('unavailable', 'no accelerometer on this device');
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'a device without an accelerometer is not a crash');

    // No accelerometer at resume time means none later either; re-listening
    // would just error again on every foregrounding.
    background(tester);
    await tester.pump();
    foreground(tester);
    await tester.pump();

    expect(shake.listenArgs, hasLength(1));
  });

  testWidgets('platforms without the plugin never touch the channel',
      (tester) async {
    // A channel activation failure cannot be caught (it bypasses onError and
    // lands in FlutterError.reportError), so on platforms where the plugin
    // does not exist the trigger must not listen at all.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    shake = FakeShakeChannel()..install(tester);
    final capture = FakeCapture(result: reportWith());
    await tester.pumpWidget(app(capture));
    await tester.pumpAndSettle();

    expect(shake.listenArgs, isEmpty);
    expect(tester.takeException(), isNull);

    // Everything else still works without the shake trigger.
    await Squawk.show();
    await tester.pumpAndSettle();
    expect(capture.captureCount, 1);

    // Inline rather than addTearDown: the binding checks this is unset
    // before tear-down callbacks get a chance to run.
    debugDefaultTargetPlatformOverride = null;
  });
}
