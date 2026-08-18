import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/src/upload/report_uploader.dart';
import 'package:squawk/src/upload/spool.dart';
import 'package:squawk/src/upload/spool_storage.dart';

import 'support/fakes.dart';

SpooledReport entry(
  String id, {
  DateTime? at,
  int attempts = 0,
  DateTime? lastAttemptAt,
}) =>
    SpooledReport(
      id: id,
      capturedAt: at ?? DateTime(2026, 8, 17, 12),
      metadata: {'text': id},
      screenshot: Uint8List.fromList([1, 2, 3]),
      attempts: attempts,
      lastAttemptAt: lastAttemptAt,
    );

void main() {
  late InMemorySpoolStorage storage;
  late FakeUploader uploader;

  /// The clock every spool in this file reads. Tests advance it instead of
  /// sleeping: backoff here is a question of arithmetic, not of time passing.
  var clock = DateTime(2026, 8, 17, 12);

  Spool spoolWith({
    int maxEntries = 50,
    Duration maxAge = const Duration(days: 7),
    int maxAttempts = 10,
  }) =>
      Spool(
        storage: storage,
        uploader: uploader,
        maxEntries: maxEntries,
        maxAge: maxAge,
        maxAttempts: maxAttempts,
        now: () => clock,
      );

  setUp(() {
    storage = InMemorySpoolStorage();
    uploader = FakeUploader();
    clock = DateTime(2026, 8, 17, 12);
  });

  group('draining', () {
    test('sends what is queued and removes it on success', () async {
      await storage.save(entry('a'));
      await storage.save(entry('b'));

      await spoolWith().drain();

      expect(uploader.sent.map((r) => r.id), ['a', 'b']);
      expect(await storage.list(), isEmpty);
    });

    test('a failure keeps the report for another day', () async {
      await storage.save(entry('a'));
      uploader.outcome = UploadOutcome.retryable;

      await spoolWith().drain();

      final remaining = await storage.list();
      expect(remaining.single.id, 'a');
      expect(remaining.single.attempts, 1, reason: 'the attempt was counted');
      expect(remaining.single.lastAttemptAt, clock);
    });

    // A payload the server rejects can never succeed. Retrying it burns
    // battery for a result that will not change.
    test('a rejected report is dropped rather than retried', () async {
      await storage.save(entry('a'));
      uploader.outcome = UploadOutcome.rejected;

      await spoolWith().drain();

      expect(await storage.list(), isEmpty);
    });

    // One bad entry at the front must not stop everything behind it.
    test('a failing report does not block the ones behind it', () async {
      await storage.save(entry('bad'));
      await storage.save(entry('good'));
      uploader.failIds = {'bad'};

      await spoolWith().drain();

      expect(uploader.sent.map((r) => r.id), contains('good'));
      expect((await storage.list()).map((r) => r.id), ['bad']);
    });

    test('two drains at once do not send anything twice', () async {
      await storage.save(entry('a'));
      final spool = spoolWith();

      await Future.wait([spool.drain(), spool.drain()]);

      expect(uploader.sent, hasLength(1));
    });

    // A file corrupted on disk must not fail every future drain on it.
    test('an entry that cannot be loaded is dropped', () async {
      await storage.save(entry('a'));
      storage.unreadable.add('a');

      await spoolWith().drain();

      expect(uploader.sent, isEmpty);
      expect(await storage.list(), isEmpty);
    });
  });

  // Backoff never sleeps. An entry that is not due yet is skipped, so a drain
  // always finishes promptly and every trigger — connectivity, timer, a new
  // capture — gets an immediate answer instead of queueing behind a wait.
  group('backoff without sleeping', () {
    test('an entry is left alone until its backoff has passed', () async {
      await storage.save(
        entry('a', attempts: 1, lastAttemptAt: clock),
      );

      await spoolWith().drain();

      expect(uploader.sent, isEmpty);
      expect((await storage.list()).single.attempts, 1,
          reason: 'skipping is not attempting');
    });

    test('an entry whose backoff has passed is retried', () async {
      await storage.save(
        entry(
          'a',
          attempts: 1,
          lastAttemptAt: clock.subtract(const Duration(hours: 1)),
        ),
      );

      await spoolWith().drain();

      expect(uploader.sent.map((r) => r.id), ['a']);
    });

    // The whole point of not sleeping: a fresh report behind a backed-off one
    // goes out now, not after the older entry's wait.
    test('a fresh report is not held up by a backed-off one in front',
        () async {
      await storage.save(
        entry('old', at: DateTime(2026, 8, 17, 6), attempts: 5,
            lastAttemptAt: clock),
      );
      await storage.save(entry('fresh', at: DateTime(2026, 8, 17, 11)));

      await spoolWith().drain();

      expect(uploader.sent.map((r) => r.id), ['fresh']);
    });
  });

  // A tester drifting in and out of signal generates transport failures that
  // say nothing about the report. They must not eat into the attempt budget,
  // or ordinary bad connectivity would get reports silently deleted.
  group('transport failures', () {
    test('do not burn an attempt', () async {
      await storage.save(entry('a'));
      uploader.outcome = UploadOutcome.unreachable;

      await spoolWith().drain();

      final remaining = (await storage.list()).single;
      expect(remaining.attempts, 0);
      expect(remaining.lastAttemptAt, clock,
          reason: 'the time is still recorded, so the entry backs off');
    });

    test('still back the entry off before the next try', () async {
      await storage.save(entry('a'));
      uploader.outcome = UploadOutcome.unreachable;
      final spool = spoolWith();
      await spool.drain();

      uploader.outcome = UploadOutcome.sent;
      await spool.drain();

      expect(uploader.sent, isEmpty,
          reason: 'the same connectivity storm must not retry immediately');

      clock = clock.add(const Duration(seconds: 10));
      await spool.drain();

      expect(uploader.sent.map((r) => r.id), ['a']);
    });
  });

  group('giving up', () {
    test('an entry is dropped once it has burned its attempts', () async {
      await storage.save(entry('a', attempts: 9));
      uploader.outcome = UploadOutcome.retryable;

      await spoolWith(maxAttempts: 10).drain();

      expect(await storage.list(), isEmpty);
    });

    test('an entry below the limit survives', () async {
      await storage.save(entry('a', attempts: 8));
      uploader.outcome = UploadOutcome.retryable;

      await spoolWith(maxAttempts: 10).drain();

      expect(await storage.list(), hasLength(1));
    });
  });

  group('bounds', () {
    // A tester offline for a week against a broken endpoint would otherwise
    // fill the device with multi-megabyte screenshots.
    test('the oldest is evicted past the entry limit', () async {
      for (var i = 0; i < 4; i++) {
        await storage.save(entry('r$i', at: DateTime(2026, 8, 17, i)));
      }
      // Nothing must send, or the assertion would be measuring delivery
      // rather than eviction.
      uploader.outcome = UploadOutcome.retryable;

      await spoolWith(maxEntries: 2).enqueue(entry('new'));

      final ids = (await storage.list()).map((r) => r.id).toList();
      expect(ids, hasLength(2));
      expect(ids, contains('new'));
      expect(ids, isNot(contains('r0')));
    });

    test('entries past the age limit are discarded, not sent', () async {
      await storage.save(entry('stale', at: DateTime(2026, 8, 1)));
      await storage.save(entry('fresh', at: DateTime(2026, 8, 17, 11)));

      await spoolWith(maxAge: const Duration(days: 7)).drain();

      expect(uploader.sent.map((r) => r.id), ['fresh']);
      expect(await storage.list(), isEmpty);
    });
  });

  group('start-up', () {
    test('debris from a crash is swept before anything is sent', () async {
      storage.incomplete.add('half-written');
      await storage.save(entry('a'));

      await spoolWith().start();

      expect(storage.incomplete, isEmpty);
      expect(uploader.sent.map((r) => r.id), ['a']);
    });
  });

  group('telling the scheduler', () {
    test('every drain reports back, so retries can be scheduled', () async {
      await storage.save(entry('a'));
      uploader.outcome = UploadOutcome.retryable;
      final spool = spoolWith();
      var told = 0;
      spool.onQueueChanged = () => told++;

      await spool.drain();

      expect(told, 1);
    });
  });
}
