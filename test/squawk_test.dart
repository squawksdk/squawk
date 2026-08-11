import 'package:flutter_test/flutter_test.dart';

import 'package:squawk/squawk.dart';

void main() {
  test('placeholder release exposes no working API', () {
    expect(isPlaceholder, isTrue);
  });
}
