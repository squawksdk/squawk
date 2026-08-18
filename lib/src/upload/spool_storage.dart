import 'dart:typed_data';

/// What listing the spool returns: enough to decide whether an entry should
/// be sent, and nothing that costs real memory.
///
/// Screenshots run to megabytes each, and the queue is *checked* far more
/// often than it is sent — every connectivity change, timer tick and
/// enqueue. Keeping the image out of the listing keeps those checks nearly
/// free; the full report is loaded one at a time, only at the moment of
/// upload.
class SpoolEntry {
  const SpoolEntry({
    required this.id,
    required this.capturedAt,
    this.attempts = 0,
    this.lastAttemptAt,
  });

  /// Sort key as well as identity: ids are time-ordered so the spool drains
  /// oldest-first without reading every entry's contents.
  final String id;

  final DateTime capturedAt;

  /// Sends the server has answered "not now" to so far. The spool gives up
  /// on an entry past a limit so one report the server always refuses cannot
  /// follow the reporter around. Transport failures are not counted — they
  /// say nothing about the report.
  final int attempts;

  /// When a send was last tried, however it ended. Null until the first try.
  ///
  /// Backoff is computed from this rather than by sleeping, so a drain
  /// always finishes promptly and a report is never made to wait behind an
  /// older one's backoff.
  final DateTime? lastAttemptAt;
}

/// One report waiting to be sent, in full.
class SpooledReport extends SpoolEntry {
  const SpooledReport({
    required super.id,
    required super.capturedAt,
    required this.metadata,
    required this.screenshot,
    super.attempts,
    super.lastAttemptAt,
  });

  /// Everything except the image, as it will be sent.
  final Map<String, Object?> metadata;

  final Uint8List screenshot;
}

/// Where reports wait between capture and delivery.
///
/// A seam so the spool's rules can be exercised without touching a disk, and
/// so a future storage change never reaches the sending logic.
abstract interface class SpoolStorage {
  /// Entries oldest first, without their screenshots.
  Future<List<SpoolEntry>> list();

  /// The full report, or null when the entry has become unreadable — the
  /// caller should delete it rather than fail every future drain on it.
  Future<SpooledReport?> load(String id);

  Future<void> save(SpooledReport report);

  /// Updates an entry's attempt count and last-attempt time without
  /// rewriting its screenshot.
  Future<void> recordAttempt(
    String id, {
    required int attempts,
    required DateTime at,
  });

  Future<void> delete(String id);

  /// Removes anything a crash left half-written.
  ///
  /// Called at start-up: an entry whose image landed but whose metadata did
  /// not is not a report, it is debris, and uploading it would send a
  /// screenshot with nothing attached.
  Future<void> sweepIncomplete();
}
