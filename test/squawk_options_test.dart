import 'package:flutter/material.dart';
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
    expect(options.theme, isNull);
    expect(options.darkTheme, isNull);
  });

  test('is const-constructible so it can sit in a const widget tree', () {
    const a = SquawkOptions();
    const b = SquawkOptions();

    expect(identical(a, b), isTrue);
  });

  // ThemeData has no const constructor, so setting one costs the caller
  // their `const`. The no-argument form above must keep working regardless —
  // that is the case every app that passes no options relies on.
  test('carries a theme when one is given', () {
    final theme = ThemeData(colorSchemeSeed: Colors.teal);
    final options = SquawkOptions(theme: theme, darkTheme: ThemeData.dark());

    expect(options.theme, same(theme));
    expect(options.darkTheme, isNotNull);
  });
}
