import 'dart:typed_data';

/// One report waiting to be sent.
class SpooledReport {
  const SpooledReport({
    required this.id,
    required this.capturedAt,
    required this.metadata,
    required this.screenshot,
    this.attempts = 0,
  });

  /// Sort key as well as identity: ids are time-ordered so the spool drains
  /// oldest-first without reading every entry's contents.
  final String id;

  final DateTime capturedAt;

  /// Everything except the image, as it will be sent.
  final Map<String, Object?> metadata;

  final Uint8List screenshot;

  /// Failed sends so far. The spool gives up on an entry past a limit so one
  /// report the server always rejects cannot follow the reporter around.
  final int attempts;

  SpooledReport withAttempt() => SpooledReport(
        id: id,
        capturedAt: capturedAt,
        metadata: metadata,
        screenshot: screenshot,
        attempts: attempts + 1,
      );
}

/// Where reports wait between capture and delivery.
///
/// A seam so the spool's rules can be exercised without touching a disk, and
/// so a future storage change never reaches the sending logic.
abstract interface class SpoolStorage {
  /// Entries oldest first.
  Future<List<SpooledReport>> list();

  Future<void> save(SpooledReport report);

  Future<void> delete(String id);

  /// Removes anything a crash left half-written.
  ///
  /// Called at start-up: an entry whose image landed but whose metadata did
  /// not is not a report, it is debris, and uploading it would send a
  /// screenshot with nothing attached.
  Future<void> sweepIncomplete();
}
