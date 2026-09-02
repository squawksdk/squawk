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
    this.enabled = true,
    this.shakeToReport = true,
    this.shakeSensitivity = ShakeSensitivity.medium,
    this.feedbackButton = false,
    this.captureLogs = true,
    this.askReporterEmail = true,
    this.theme,
    this.darkTheme,
  });

  /// Whether Squawk does anything at all.
  ///
  /// When false, [Squawk] renders its child and nothing else: no shake
  /// listener, no floating button, no log capture, and no upload of
  /// anything a previous run left in the spool. [Squawk.show] returns
  /// without opening a sheet and without reporting an error.
  ///
  /// It is a plain runtime value, so it can come from a build-time define
  /// or from something only known once the app is running, such as whether
  /// this install came from TestFlight. It is not a remote kill switch:
  /// a build reads it once, when [Squawk] is built.
  final bool enabled;

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
