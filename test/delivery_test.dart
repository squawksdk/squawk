import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/src/upload/delivery.dart';
import 'package:squawk/src/upload/report_uploader.dart';
import 'package:squawk/src/upload/spool.dart';
import 'package:squawk/src/upload/spool_storage.dart';

import 'support/fakes.dart';

void main() {
  late InMemorySpoolStorage storage;
  late FakeUploader uploader;
  late StreamController<Object?> connectivity;

  SpooledReport entry(String id) => SpooledReport(
        id: id,
        capturedAt: DateTime(2026, 8, 17, 12),
        metadata: const {},
        screenshot: Uint8List.fromList([1]),
      );

  Delivery deliveryWith({Duration interval = const Duration(minutes: 5)}) =>
      Delivery(
        spool: Spool(
          storage: storage,
          uploader: uploader,
          delay: (_) async {},
          now: () => DateTime(2026, 8, 17, 12),
        ),
        interval: interval,
        connectivityChanges: connectivity.stream,
      );

  setUp(() {
    storage = InMemorySpoolStorage();
    uploader = FakeUploader();
    connectivity = StreamController<Object?>.broadcast();
  });

  tearDown(() => connectivity.close());

  test('start sweeps and sends what a previous run left behind', () async {
    storage.incomplete.add('debris');
    await storage.save(entry('a'));
    final delivery = deliveryWith();
    addTearDown(delivery.stop);

    await delivery.start();

    expect(storage.incomplete, isEmpty);
    expect(uploader.sent.map((r) => r.id), ['a']);
  });

  test('regained connectivity sends without waiting for a restart', () async {
    uploader.outcome = UploadOutcome.retryable;
    await storage.save(entry('a'));
    final delivery = deliveryWith();
    addTearDown(delivery.stop);
    await delivery.start();

    uploader.outcome = UploadOutcome.sent;
    connectivity.add('wifi');
    await Future<void>.delayed(Duration.zero);

    expect(uploader.sent.map((r) => r.id), ['a']);
  });

  group('the backstop timer', () {
    // A timer that wakes to find an empty queue is battery spent on the host
    // app's behalf, and the SDK has not earned that.
    test('does not run while there is nothing to send', () async {
      final delivery = deliveryWith();
      addTearDown(delivery.stop);

      await delivery.start();

      expect(delivery.isTimerRunning, isFalse);
    });

    test('runs once something is waiting', () async {
      uploader.outcome = UploadOutcome.retryable;
      await storage.save(entry('a'));
      final delivery = deliveryWith();
      addTearDown(delivery.stop);

      await delivery.start();

      expect(delivery.isTimerRunning, isTrue);
    });

    test('stops again once the queue drains', () async {
      uploader.outcome = UploadOutcome.retryable;
      await storage.save(entry('a'));
      final delivery = deliveryWith();
      addTearDown(delivery.stop);
      await delivery.start();
      expect(delivery.isTimerRunning, isTrue);

      uploader.outcome = UploadOutcome.sent;
      connectivity.add('wifi');
      await Future<void>.delayed(Duration.zero);

      expect(delivery.isTimerRunning, isFalse);
    });

    test('stop releases the timer and the connectivity listener', () async {
      uploader.outcome = UploadOutcome.retryable;
      await storage.save(entry('a'));
      final delivery = deliveryWith();
      await delivery.start();

      await delivery.stop();

      expect(delivery.isTimerRunning, isFalse);
      expect(connectivity.hasListener, isFalse);
    });
  });
}
