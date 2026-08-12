/// Optional configuration for [Squawk].
///
/// Every field has a default that suits most apps, so passing no options at
/// all is the expected case.
class SquawkOptions {
  const SquawkOptions({
    this.shakeToReport = true,
    this.feedbackButton = false,
    this.captureLogs = true,
    this.askReporterEmail = true,
  });

  /// Whether shaking the device opens the report sheet.
  final bool shakeToReport;

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
