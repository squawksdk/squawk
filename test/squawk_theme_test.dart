import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/src/capture/squawk_theme.dart';

void main() {
  final light = ThemeData(colorSchemeSeed: Colors.teal);
  final dark = ThemeData.dark();

  ThemeData resolve({
    ThemeData? theme,
    ThemeData? darkTheme,
    required Brightness platform,
  }) =>
      resolveSquawkTheme(
        theme: theme,
        darkTheme: darkTheme,
        platformBrightness: platform,
      );

  group('neither theme set', () {
    test('follows the device', () {
      expect(
        resolve(platform: Brightness.light).brightness,
        Brightness.light,
      );
      expect(
        resolve(platform: Brightness.dark).brightness,
        Brightness.dark,
      );
    });
  });

  group('both themes set', () {
    test('follows the device, the way ThemeMode.system does', () {
      expect(
        resolve(theme: light, darkTheme: dark, platform: Brightness.light),
        same(light),
      );
      expect(
        resolve(theme: light, darkTheme: dark, platform: Brightness.dark),
        same(dark),
      );
    });
  });

  // The reason this option exists. An app pinned to one themeMode does not
  // change with the device, so neither may Squawk: a dark app on a
  // light-mode phone was the original bug.
  group('one theme set', () {
    test('theme alone wins at both brightnesses', () {
      expect(resolve(theme: light, platform: Brightness.light), same(light));
      expect(resolve(theme: light, platform: Brightness.dark), same(light));
    });

    test('darkTheme alone wins at both brightnesses', () {
      expect(resolve(darkTheme: dark, platform: Brightness.light), same(dark));
      expect(resolve(darkTheme: dark, platform: Brightness.dark), same(dark));
    });
  });

  test('hands the theme back untouched', () {
    // Never copyWith(brightness:) on the host's theme — that trips the
    // ColorScheme brightness assertion. Identity is the guarantee.
    final custom = ThemeData(
      brightness: Brightness.dark,
      fontFamily: 'HostFont',
    );

    expect(
      resolve(theme: custom, platform: Brightness.light),
      same(custom),
    );
  });
}
