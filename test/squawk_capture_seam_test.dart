import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/capture/report_capture.dart';
import 'package:squawk/src/squawk_controller.dart';

/// Stands in for the real capture UI. Its existence is the point of the seam:
/// the SDK can be exercised end to end without driving a third-party widget.
class FakeCapture implements ReportCapture {
  FakeCapture({this.result});

  final SquawkReport? result;
  int captureCount = 0;

  @override
  Widget wrap(Widget child) => child;

  @override
  Future<SquawkReport?> capture(BuildContext context) async {
    captureCount++;
    return result;
  }
}

SquawkReport reportWith({String? text}) =>
    SquawkReport(screenshot: Uint8List.fromList([1, 2, 3]), text: text);

Widget app(ReportCapture capture) => Squawk(
      apiKey: 'sq_test_key',
      capture: capture,
      child: const SizedBox(),
    );

void main() {
  setUp(() => SquawkController.instance.reset());

  testWidgets('show() routes to the capture adapter once mounted',
      (tester) async {
    final capture = FakeCapture(result: reportWith(text: 'the button is red'));
    await tester.pumpWidget(app(capture));

    await Squawk.show();

    expect(capture.captureCount, 1);
  });

  testWidgets('user context set before mounting still reaches the report',
      (tester) async {
    // Apps call this during start-up, before the first frame. Dropping it
    // would be a silent bug: reports arrive with no idea who sent them.
    Squawk.setUser(id: 'u_42', email: 'jo@client.com');
    Squawk.setMetadata('plan', 'trial');

    final capture = FakeCapture(result: reportWith());
    await tester.pumpWidget(app(capture));

    final report = await SquawkController.instance.show();

    expect(report!.userId, 'u_42');
    expect(report.userEmail, 'jo@client.com');
    expect(report.metadata, {'plan': 'trial'});
  });

  testWidgets('clearUser drops identity and metadata from later reports',
      (tester) async {
    Squawk.setUser(id: 'u_42', email: 'jo@client.com');
    Squawk.setMetadata('plan', 'trial');
    Squawk.clearUser();

    await tester.pumpWidget(app(FakeCapture(result: reportWith())));
    final report = await SquawkController.instance.show();

    expect(report!.userId, isNull);
    expect(report.userEmail, isNull);
    expect(report.metadata, isEmpty);
  });

  testWidgets('the last report is published for every trigger', (tester) async {
    await tester.pumpWidget(app(FakeCapture(result: reportWith(text: 'hi'))));
    expect(SquawkController.instance.lastReport.value, isNull);

    await Squawk.show();

    expect(SquawkController.instance.lastReport.value?.text, 'hi');
  });

  testWidgets('a dismissed sheet produces no report', (tester) async {
    await tester.pumpWidget(app(FakeCapture(result: null)));

    expect(await SquawkController.instance.show(), isNull);
  });

  testWidgets('unmounting releases the host', (tester) async {
    final capture = FakeCapture(result: reportWith());
    await tester.pumpWidget(app(capture));
    await tester.pumpWidget(const SizedBox());

    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    await Squawk.show();

    expect(capture.captureCount, 0);
    expect(errors, hasLength(1));
  });
}
