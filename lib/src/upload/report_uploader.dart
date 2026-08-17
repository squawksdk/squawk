import 'spool_storage.dart';

/// What became of an attempt to send a report.
enum UploadOutcome {
  /// Accepted. Delete it.
  sent,

  /// A network error, a 5xx, or a 429. Worth another attempt later.
  retryable,

  /// The server refused it and always will — a 4xx other than 429. Retrying
  /// spends battery on a result that cannot change, so the entry is dropped.
  rejected,
}

/// Sends a spooled report to the ingest endpoint.
///
/// A seam so the spool's rules can be exercised without a network, and so the
/// wire format lives in one place.
abstract interface class ReportUploader {
  Future<UploadOutcome> upload(SpooledReport report);
}
