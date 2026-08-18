import '../log_buffer.dart';
import '../squawk_report.dart';

/// Turns a report into the JSON the ingest endpoint receives.
///
/// Together with [HttpReportUploader] this is the whole wire contract. The
/// server is TypeScript in another repository with no shared types, so every
/// key here is matched by hand on the other side.
///
/// Keys are omitted when absent rather than sent as null, so an empty report
/// stays small — screenshots already dominate the payload.
Map<String, Object?> wireMetadata(SquawkReport report) {
  final device = report.device;

  return {
    if (report.text != null) 'text': report.text,
    if (report.reporterEmail != null) 'reporterEmail': report.reporterEmail,
    if (report.userId != null) 'userId': report.userId,
    if (report.userEmail != null) 'userEmail': report.userEmail,
    if (report.metadata.isNotEmpty) 'metadata': report.metadata,
    if (device != null) ...device.toJson(),
    if (report.logs.isNotEmpty)
      'logs': [for (final entry in report.logs) _logJson(entry)],
  };
}

Map<String, Object?> _logJson(LogEntry entry) => {
      'at': entry.timestamp.toUtc().toIso8601String(),
      'message': entry.message,
      // Only marked when true: most lines are not errors, and the flag costs
      // bytes on every one of up to a hundred entries.
      if (entry.isError) 'error': true,
    };
