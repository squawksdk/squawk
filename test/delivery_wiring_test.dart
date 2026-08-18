import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/squawk_controller.dart';

import 'support/fakes.dart';

/// The widget owns *starting* delivery, but delivery itself belongs to the
/// process: queued reports and their retries must survive the widget being
/// unmounted and mounted again.
void main() {
  setUp(resetSquawk);

  Widget app() => Squawk(
        apiKey: 'sq_test_key',
        capture: FakeCapture(),
        child: const SizedBox(),
      );

  testWidgets('delivery survives the Squawk widget being remounted',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    final storage =
        SquawkController.instance.spool!.storage as InMemorySpoolStorage;
    expect(storage.sweeps, 1, reason: 'mounting starts delivery');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pump();

    expect(storage.sweeps, 2,
        reason: 'a remount must restart delivery, not orphan it');
  });
}
