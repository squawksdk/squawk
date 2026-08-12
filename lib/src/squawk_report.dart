import 'dart:typed_data';

import 'device_context.dart';
import 'log_buffer.dart';

/// A single report on its way to the Squawk backend.
///
/// This is Squawk's own type by design. Nothing from the underlying capture
/// package appears here, so the capture implementation can be replaced
/// without touching the upload path or the public API.
class SquawkReport {
  const SquawkReport({
    required this.screenshot,
    this.text,
    this.reporterEmail,
    this.userId,
    this.userEmail,
    this.metadata = const {},
    this.logs = const [],
    this.device,
  });

  /// The annotated screenshot, as PNG bytes.
  final Uint8List screenshot;

  /// What the reporter typed, if anything.
  final String? text;

  /// The email the reporter gave on the sheet, if asked and provided.
  final String? reporterEmail;

  /// Identity set by the host app via `Squawk.setUser`.
  final String? userId;
  final String? userEmail;

  /// Arbitrary key/value context set via `Squawk.setMetadata`.
  final Map<String, Object?> metadata;

  /// Device, OS, app version and build mode. Null only if collection has not
  /// run yet — individual fields are nullable so a partial failure still
  /// leaves a usable report.
  final DeviceContext? device;

  /// Recent log output and Flutter errors, oldest first.
  ///
  /// Empty when the host app opted out with `captureLogs: false`.
  final List<LogEntry> logs;

  SquawkReport copyWith({
    String? userId,
    String? userEmail,
    Map<String, Object?>? metadata,
    List<LogEntry>? logs,
    DeviceContext? device,
  }) {
    return SquawkReport(
      screenshot: screenshot,
      text: text,
      reporterEmail: reporterEmail,
      userId: userId ?? this.userId,
      userEmail: userEmail ?? this.userEmail,
      metadata: metadata ?? this.metadata,
      logs: logs ?? this.logs,
      device: device ?? this.device,
    );
  }
}
