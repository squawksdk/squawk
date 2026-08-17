import 'dart:async';

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
    Future<void> Function(Duration)? delay,
    DateTime Function()? now,
  })  : _delay = delay ?? Future<void>.delayed,
        _now = now ?? DateTime.now;

  final SpoolStorage storage;
  final ReportUploader uploader;
  final Backoff backoff;

  /// Most reports kept. Beyond this the oldest are discarded: a device full of
  /// screenshots is a reason to uninstall the SDK.
  final int maxEntries;

  /// A report older than this describes a build nobody is running now.
  final Duration maxAge;

  /// Attempts before an entry is abandoned, so one report the server always
  /// rejects cannot follow the reporter around forever.
  final int maxAttempts;

  final Future<void> Function(Duration) _delay;
  final DateTime Function() _now;

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

  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      for (final report in await storage.list()) {
        if (_isExpired(report)) {
          await storage.delete(report.id);
          continue;
        }

        if (report.attempts > 0) await _delay(backoff.delayFor(report.attempts));

        final outcome = await uploader.upload(report);
        switch (outcome) {
          case UploadOutcome.sent:
          case UploadOutcome.rejected:
            await storage.delete(report.id);
          case UploadOutcome.retryable:
            final tried = report.withAttempt();
            // Move on to the next entry either way: one report the server
            // keeps refusing must not stop everything queued behind it.
            if (tried.attempts >= maxAttempts) {
              await storage.delete(report.id);
            } else {
              await storage.save(tried);
            }
        }
      }
    } finally {
      _draining = false;
    }
  }

  /// Whether anything is waiting, so callers can avoid scheduling work that
  /// has nothing to do.
  Future<bool> get isEmpty async => (await storage.list()).isEmpty;

  /// How many reports are still undelivered.
  Future<int> get pendingCount async => (await storage.list()).length;

  bool _isExpired(SpooledReport report) =>
      _now().difference(report.capturedAt) > maxAge;

  Future<void> _evictOverflow() async {
    final entries = await storage.list();
    if (entries.length <= maxEntries) return;

    for (final stale in entries.take(entries.length - maxEntries)) {
      await storage.delete(stale.id);
    }
  }
}
