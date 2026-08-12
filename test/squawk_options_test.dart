import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';

void main() {
  // The defaults are a published contract, not an implementation choice —
  // they are what the pub.dev README promises. Changing one silently changes
  // behaviour for every app that never passed options.
  test('defaults match the documented contract', () {
    const options = SquawkOptions();

    expect(options.shakeToReport, isTrue);
    expect(options.feedbackButton, isFalse);
    expect(options.captureLogs, isTrue);
    expect(options.askReporterEmail, isTrue);
  });

  test('is const-constructible so it can sit in a const widget tree', () {
    const a = SquawkOptions();
    const b = SquawkOptions();

    expect(identical(a, b), isTrue);
  });
}
