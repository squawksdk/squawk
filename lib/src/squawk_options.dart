/// How hard the device must be shaken to open the report sheet.
///
/// Android only. iOS rides the system shake gesture, which Apple does not
/// make tunable, so this setting has no effect there.
enum ShakeSensitivity {
  /// A light shake is enough. For testers who report often and would rather
  /// not rattle the phone.
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
}
