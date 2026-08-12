import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shake_gesture_platform_interface/shake_gesture_platform_interface.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/squawk_controller.dart';

import 'support/fakes.dart';

void main() {
  late FakeShakePlatform shake;

  setUp(() {
    SquawkController.instance.reset();
    shake = FakeShakePlatform();
    ShakeGesturePlatform.instance = shake;
  });

  // The reporter is holding the phone when the sheet opens, so a second shake
  // is likely. Without a guard it would stack sheets and send two reports for
  // one bug.
  testWidgets('shaking while the sheet is open does nothing', (tester) async {
    final capture = FakeCapture(
      result: reportWith(),
      completeImmediately: false,
    );
    await tester.pumpWidget(
      Squawk(apiKey: 'k', capture: capture, child: const SizedBox()),
    );

    shake.simulateShake();
    await tester.pump();
    expect(capture.captureCount, 1);

    shake.simulateShake();
    shake.simulateShake();
    await tester.pump();

    expect(capture.captureCount, 1, reason: 'the sheet was already open');
  });

  testWidgets('the trigger works again once the sheet closes', (tester) async {
    final capture = FakeCapture(
      result: reportWith(),
      completeImmediately: false,
    );
    await tester.pumpWidget(
      Squawk(apiKey: 'k', capture: capture, child: const SizedBox()),
    );

    shake.simulateShake();
    await tester.pump();
    capture.complete();
    await tester.pumpAndSettle();

    shake.simulateShake();
    await tester.pump();

    expect(capture.captureCount, 2);
  });
}
