import 'package:flutter/material.dart';

/// How hard the device must be shaken to open the report sheet.
///
/// Android only. iOS rides the system shake gesture, which Apple does not
/// make tunable, so this setting has no effect there.
enum ShakeSensitivity {
  /// A light shake is enough. For testers who report often and would rather
  /// not rattle the phone.
  ///
  /// Vigorous movement such as running or jumping can trigger it. Prefer
  /// [medium] or [firm] for apps used in motion.
  light,

  /// The default, and the same feel as versions before this setting existed.
  medium,

  /// Takes a deliberate, forceful shake. For apps whose normal use involves
  /// movement, where [medium] would fire on its own.
  firm,
}

/// Optional configuration for [Squawk].
///
/// Every field has a default that suits most apps, so passing no options at
/// all is the expected case.
class SquawkOptions {
  const SquawkOptions({
    this.shakeToReport = true,
    this.shakeSensitivity = ShakeSensitivity.medium,
    this.feedbackButton = false,
    this.captureLogs = true,
    this.askReporterEmail = true,
    this.theme,
    this.darkTheme,
  });

  /// Whether shaking the device opens the report sheet.
  final bool shakeToReport;

  /// How hard the shake must be. See [ShakeSensitivity].
  final ShakeSensitivity shakeSensitivity;

  /// Whether to show a floating button that opens the report sheet.
  ///
  /// Off by default — it covers part of the host app's UI, so it is opt-in.
  final bool feedbackButton;

  /// Whether recent log output is attached to reports.
  ///
  /// On by default. Apps handling sensitive data should turn this off; see
  /// the "your obligations" section of the README.
  final bool captureLogs;

  /// Whether the report sheet asks the reporter for an email address.
  final bool askReporterEmail;

  /// The theme Squawk's own UI uses.
  ///
  /// Squawk renders above your `MaterialApp`, so it cannot read your theme
  /// and falls back to a plain light or dark one matching the device. Pass
  /// yours here and the report sheet, the sent note and the floating button
  /// all match your app instead.
  ///
  /// Set this alone and it is used whatever the device is set to, which is
  /// what an app pinned to one `themeMode` wants. Set [darkTheme] as well to
  /// follow the device the way `ThemeMode.system` does.
  ///
  /// `ThemeData` has no const constructor, so [SquawkOptions] cannot be
  /// `const` once this is set.
  final ThemeData? theme;

  /// The theme Squawk's own UI uses while the device is in dark mode.
  ///
  /// Only consulted when [theme] is set too. On its own it behaves exactly
  /// like [theme] — used at both brightnesses.
  final ThemeData? darkTheme;
}
