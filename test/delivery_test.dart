import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
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
  late Spool spool;

  /// Advanced by tests where an entry must come off backoff; never slept on.
  var clock = DateTime(2026, 8, 17, 12);

  SpooledReport entry(String id) => SpooledReport(
        id: id,
        capturedAt: DateTime(2026, 8, 17, 11),
        metadata: const {},
        screenshot: Uint8List.fromList([1]),
      );

  Delivery deliveryWith({Duration interval = const Duration(minutes: 5)}) =>
      Delivery(
        spool: spool,
        interval: interval,
        connectivityChanges: connectivity.stream,
      );

  /// Lets the event queue turn over so stream events and the unawaited tails
  /// of drains can run.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    storage = InMemorySpoolStorage();
    uploader = FakeUploader();
    connectivity = StreamController<Object?>.broadcast();
    clock = DateTime(2026, 8, 17, 12);
    spool = Spool(storage: storage, uploader: uploader, now: () => clock);
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
    clock = clock.add(const Duration(minutes: 1));
    connectivity.add('wifi');
    await settle();

    expect(uploader.sent.map((r) => r.id), ['a']);
  });

  // Losing connectivity is also an event. A drain then can only fail, and a
  // tester toggling in and out of signal must not look like a report the
  // server keeps refusing.
  test('an offline event does not trigger a drain', () async {
    final delivery = deliveryWith();
    addTearDown(delivery.stop);
    await delivery.start();
    await storage.save(entry('a'));

    connectivity.add(<ConnectivityResult>[ConnectivityResult.none]);
    await settle();

    expect(uploader.sent, isEmpty);

    connectivity.add(<ConnectivityResult>[ConnectivityResult.wifi]);
    await settle();

    expect(uploader.sent.map((r) => r.id), ['a']);
  });

  // The widget that owns delivery can be unmounted and mounted again — a hot
  // reload restructure must not end retries for the rest of the process.
  test('can be started again after being stopped', () async {
    final delivery = deliveryWith();
    await delivery.start();
    await delivery.stop();

    await storage.save(entry('a'));
    await delivery.start();
    addTearDown(delivery.stop);

    expect(uploader.sent.map((r) => r.id), ['a']);
    expect(storage.sweeps, 2);
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

    // The gap the review found: a report captured *after* start whose first
    // send fails. Nothing else will fire on a quietly bad network, so the
    // enqueue itself must start the backstop.
    test('starts when a report is queued after start', () async {
      final delivery = deliveryWith();
      addTearDown(delivery.stop);
      await delivery.start();
      expect(delivery.isTimerRunning, isFalse);

      uploader.outcome = UploadOutcome.retryable;
      await spool.enqueue(entry('a'));
      await settle();

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
      clock = clock.add(const Duration(minutes: 1));
      connectivity.add('wifi');
      await settle();

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

    // stop() can race a drain already in flight; its tail must not recreate
    // the timer stop() just cancelled.
    test('a drain in flight when stop() runs cannot resurrect it', () async {
      final delivery = deliveryWith();
      await delivery.start();

      uploader.outcome = UploadOutcome.retryable;
      uploader.gate = Completer<void>();
      await storage.save(entry('a'));
      connectivity.add('wifi');
      await settle();

      await delivery.stop();
      uploader.gate!.complete();
      await settle();

      expect(delivery.isTimerRunning, isFalse);
    });
  });
}
