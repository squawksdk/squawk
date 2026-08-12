import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';

void main() {
  List<FlutterErrorDetails> captureErrors() {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);
    return errors;
  }

  // A host app wires Squawk.show() to its own button. Getting the setup wrong
  // must not take their app down — the developer should see a clear error and
  // the app should carry on.
  test('show() without a mounted Squawk reports an error and does not throw',
      () async {
    final errors = captureErrors();

    await expectLater(Squawk.show(), completes);

    expect(errors, hasLength(1));
    expect(
      errors.single.exception.toString(),
      contains('No Squawk widget is mounted'),
    );
  });
}
