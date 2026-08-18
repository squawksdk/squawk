import 'backoff.dart';
import 'report_uploader.dart';
import 'spool_storage.dart';

/// Holds captured reports until they reach the backend.
///
/// A report that cannot be sent immediately must survive the app being closed
/// and the device being restarted. Testers work on bad networks, and a
/// silently dropped report is worse than no SDK at all.
class Spool {
  Spool({
    required this.storage,
    required this.uploader,
    this.backoff = const Backoff(),
    this.maxEntries = 50,
    this.maxAge = const Duration(days: 7),
    this.maxAttempts = 10,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SpoolStorage storage;
  final ReportUploader uploader;
  final Backoff backoff;

  /// Most reports kept. Beyond this the oldest are discarded: a device full of
  /// screenshots is a reason to uninstall the SDK.
  final int maxEntries;

  /// A report older than this describes a build nobody is running now.
  final Duration maxAge;

  /// Server refusals before an entry is abandoned, so one report the server
  /// always answers "not now" to cannot follow the reporter around forever.
  final int maxAttempts;

  final DateTime Function() _now;

  /// Told after every drain, so whoever schedules retries can see whether the
  /// queue emptied or something is still waiting.
  void Function()? onQueueChanged;

  /// Guards against two triggers draining at once — capture, start-up,
  /// connectivity and the timer can all fire together, and without this the
  /// same report would be sent twice.
  bool _draining = false;

  /// Sweeps crash debris, then sends whatever is waiting.
  Future<void> start() async {
    await storage.sweepIncomplete();
    await drain();
  }

  /// Queues a report and tries to send straight away.
  Future<void> enqueue(SpooledReport report) async {
    await storage.save(report);
    await _evictOverflow();
    await drain();
  }

  /// Tries to send everything that is due.
  ///
  /// Never sleeps: an entry whose backoff has not passed is skipped, not
  /// waited for, so a drain finishes promptly whatever the queue holds and a
  /// fresh report never waits behind an older one's backoff.
  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      for (final entry in await storage.list()) {
        if (_isExpired(entry)) {
          await storage.delete(entry.id);
          continue;
        }
        if (!_isDue(entry)) continue;

        final report = await storage.load(entry.id);
        if (report == null) {
          await storage.delete(entry.id);
          continue;
        }

        switch (await uploader.upload(report)) {
          case UploadOutcome.sent:
          case UploadOutcome.rejected:
            await storage.delete(entry.id);
          case UploadOutcome.retryable:
            final attempts = entry.attempts + 1;
            // Move on to the next entry either way: one report the server
            // keeps refusing must not stop everything queued behind it.
            if (attempts >= maxAttempts) {
              await storage.delete(entry.id);
            } else {
              await storage.recordAttempt(
                entry.id,
                attempts: attempts,
                at: _now(),
              );
            }
          case UploadOutcome.unreachable:
            // The server never saw it, so the attempt is not counted — only
            // the time is, so one connectivity storm cannot retry the same
            // entry over and over.
            await storage.recordAttempt(
              entry.id,
              attempts: entry.attempts,
              at: _now(),
            );
        }
      }
    } finally {
      _draining = false;
      onQueueChanged?.call();
    }
  }

  /// Whether anything is waiting, so callers can avoid scheduling work that
  /// has nothing to do.
  Future<bool> get isEmpty async => (await storage.list()).isEmpty;

  /// How many reports are still undelivered.
  Future<int> get pendingCount async => (await storage.list()).length;

  bool _isExpired(SpoolEntry entry) =>
      _now().difference(entry.capturedAt) > maxAge;

  bool _isDue(SpoolEntry entry) {
    final last = entry.lastAttemptAt;
    if (last == null) return true;
    return !_now().isBefore(last.add(backoff.delayFor(entry.attempts)));
  }

  Future<void> _evictOverflow() async {
    final entries = await storage.list();
    if (entries.length <= maxEntries) return;

    for (final stale in entries.take(entries.length - maxEntries)) {
      await storage.delete(stale.id);
    }
  }
}
