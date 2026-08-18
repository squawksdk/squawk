import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/src/upload/report_uploader.dart';
import 'package:squawk/src/upload/spool.dart';
import 'package:squawk/src/upload/spool_storage.dart';

import 'support/fakes.dart';

SpooledReport entry(String id, {DateTime? at, int attempts = 0}) =>
    SpooledReport(
      id: id,
      capturedAt: at ?? DateTime(2026, 8, 17, 12),
      metadata: {'text': id},
      screenshot: Uint8List.fromList([1, 2, 3]),
      attempts: attempts,
    );

void main() {
  late InMemorySpoolStorage storage;
  late FakeUploader uploader;

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
        // Tests must never sleep: a fixed real-clock wait already cost this
        // suite a failure in one run out of four.
        delay: (_) async {},
        now: () => DateTime(2026, 8, 17, 12),
      );

  setUp(() {
    storage = InMemorySpoolStorage();
    uploader = FakeUploader();
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
}
