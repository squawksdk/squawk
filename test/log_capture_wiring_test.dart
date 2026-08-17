import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/squawk_controller.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => resetSquawk());

  Widget app(FakeCapture capture, {required bool captureLogs}) => Squawk(
        apiKey: 'k',
        capture: capture,
        options: SquawkOptions(captureLogs: captureLogs),
        child: const SizedBox(),
      );

  testWidgets('recent log lines reach the report', (tester) async {
    final capture = FakeCapture(result: reportWith());
    await tester.pumpWidget(app(capture, captureLogs: true));

    debugPrint('checkout tapped');
    debugPrint('payment failed');

    final report = await SquawkController.instance.show();

    expect(
      report!.logs.map((e) => e.message),
      containsAllInOrder(['checkout tapped', 'payment failed']),
    );
  });

  // The opt-out has to mean nothing is captured at all, not "captured but
  // withheld". An app handling patient or financial data cannot be told we
  // buffered their logs in memory and chose not to send them.
  testWidgets('captureLogs: false installs no hooks and buffers nothing',
      (tester) async {
    final original = debugPrint;

    final capture = FakeCapture(result: reportWith());
    await tester.pumpWidget(app(capture, captureLogs: false));

    expect(debugPrint, same(original), reason: 'no hook should be installed');

    debugPrint('something sensitive');
    final report = await SquawkController.instance.show();

    expect(report!.logs, isEmpty);
  });

  testWidgets('unmounting restores the original debugPrint', (tester) async {
    final original = debugPrint;

    await tester.pumpWidget(
      app(FakeCapture(result: reportWith()), captureLogs: true),
    );
    expect(debugPrint, isNot(same(original)));

    await tester.pumpWidget(const SizedBox());

    expect(debugPrint, same(original));
  });
}
