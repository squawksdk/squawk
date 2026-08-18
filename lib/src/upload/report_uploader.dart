import 'spool_storage.dart';

/// What became of an attempt to send a report.
enum UploadOutcome {
  /// Accepted. Delete it.
  sent,

  /// The server answered "not now" — a 5xx, a 429, or (while the backend is
  /// new) a 401. Worth another attempt later, and counted against the
  /// entry's attempt limit.
  retryable,

  /// The server was never reached — no route, DNS failure, TLS error,
  /// timeout. Says nothing about the report, so it is retried without
  /// burning an attempt: a tester drifting in and out of signal must not
  /// spend the attempt budget on their own connectivity.
  unreachable,

  /// The server refused it and always will — a 4xx other than 429 and 401.
  /// Retrying spends battery on a result that cannot change, so the entry is
  /// dropped.
  rejected,
}

/// Sends a spooled report to the ingest endpoint.
///
/// A seam so the spool's rules can be exercised without a network, and so the
/// wire format lives in one place.
abstract interface class ReportUploader {
  Future<UploadOutcome> upload(SpooledReport report);
}
