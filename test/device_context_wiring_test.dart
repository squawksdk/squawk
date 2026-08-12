import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/device_context.dart';
import 'package:squawk/src/squawk_controller.dart';

import 'support/fakes.dart';

void main() {
  setUp(resetSquawk);

  Widget app(FakeCapture capture) => Squawk(
        apiKey: 'k',
        capture: capture,
        child: const SizedBox(),
      );

  testWidgets('device and app details reach the report', (tester) async {
    await tester.pumpWidget(app(FakeCapture(result: reportWith())));

    final report = await SquawkController.instance.show();

    expect(report!.device, isNotNull);
    expect(report.device!.deviceModel, 'Test Device');
    expect(report.device!.osName, 'TestOS');
    expect(report.device!.osVersion, '1.0');
    expect(report.device!.appVersion, '1.0.0+1');
  });

  testWidgets('the build mode is stamped on every report', (tester) async {
    await tester.pumpWidget(app(FakeCapture(result: reportWith())));

    final report = await SquawkController.instance.show();

    // Tests compile in debug; the value is derived by the SDK, never passed
    // in by the host app.
    expect(report!.device!.buildMode, BuildMode.debug);
  });

  testWidgets('a report still sends when every plugin fails', (tester) async {
    resetSquawk(
      collector: DeviceContextCollector(
        readDevice: () async => throw StateError('no channel'),
        readApp: () async => throw StateError('no plugin'),
      ),
    );
    await tester.pumpWidget(app(FakeCapture(result: reportWith(text: 'hi'))));

    final report = await SquawkController.instance.show();

    expect(report, isNotNull, reason: 'the report matters more than a field');
    expect(report!.text, 'hi');
    expect(report.device!.deviceModel, isNull);
    expect(report.device!.buildMode, BuildMode.debug);
  });
}
