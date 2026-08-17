import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shake_gesture_platform_interface/shake_gesture_platform_interface.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/capture/report_capture.dart';

import 'support/fakes.dart';

void main() {
  late FakeShakePlatform shake;

  setUp(() {
    resetSquawk();
    shake = FakeShakePlatform();
    ShakeGesturePlatform.instance = shake;
  });

  Widget app(ReportCapture capture, {SquawkOptions? options}) => Squawk(
        apiKey: 'sq_test_key',
        capture: capture,
        options: options ?? const SquawkOptions(),
        child: const SizedBox(),
      );

  testWidgets('a shake opens the report sheet', (tester) async {
    final capture = FakeCapture(result: reportWith());
    await tester.pumpWidget(app(capture));

    shake.simulateShake();
    await tester.pumpAndSettle();

    expect(capture.captureCount, 1);
  });

  testWidgets('shakeToReport: false leaves the trigger unregistered',
      (tester) async {
    final capture = FakeCapture(result: reportWith());
    await tester.pumpWidget(
      app(capture, options: const SquawkOptions(shakeToReport: false)),
    );

    expect(shake.callbacks, isEmpty);

    shake.simulateShake();
    await tester.pumpAndSettle();

    expect(capture.captureCount, 0);
  });

  testWidgets('unmounting stops the trigger listening', (tester) async {
    await tester.pumpWidget(app(FakeCapture(result: reportWith())));
    expect(shake.callbacks, hasLength(1));

    await tester.pumpWidget(const SizedBox());

    expect(shake.callbacks, isEmpty);
  });
}
