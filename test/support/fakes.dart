import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shake_gesture_platform_interface/shake_gesture_platform_interface.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/capture/report_capture.dart';
import 'package:squawk/src/device_context.dart';
import 'package:squawk/src/reporter_email_store.dart';
import 'package:squawk/src/upload/report_uploader.dart';
import 'package:squawk/src/upload/spool_storage.dart';
import 'package:squawk/src/squawk_controller.dart';

/// Stands in for the real capture UI, so the SDK can be exercised end to end
/// without driving a third-party widget tree.
class FakeCapture implements ReportCapture {
  FakeCapture({this.result, this.completeImmediately = true});

  final SquawkReport? result;

  /// When false, [capture] hangs until [complete] is called — which is how a
  /// sheet that is still open gets simulated.
  final bool completeImmediately;

  int captureCount = 0;
  final List<Completer<SquawkReport?>> _pending = [];

  @override
  Widget wrap(Widget child) => child;

  @override
  Future<SquawkReport?> capture(BuildContext context) {
    captureCount++;
    if (completeImmediately) return Future.value(result);

    final completer = Completer<SquawkReport?>();
    _pending.add(completer);
    return completer.future;
  }

  /// Resolves every capture left hanging by [completeImmediately] being false.
  void complete() {
    for (final completer in _pending) {
      if (!completer.isCompleted) completer.complete(result);
    }
    _pending.clear();
  }
}

/// Replaces the real shake plugin so a shake can be fired from a test.
///
/// `shake_gesture` ships no simulate helper, but the platform interface has a
/// public setter, which makes the trigger testable without a device.
class FakeShakePlatform extends ShakeGesturePlatform {
  final List<VoidCallback> callbacks = [];

  @override
  void registerCallback({required VoidCallback onShake}) =>
      callbacks.add(onShake);

  @override
  void unregisterCallback({required VoidCallback onShake}) =>
      callbacks.remove(onShake);

  void simulateShake() {
    for (final callback in [...callbacks]) {
      callback();
    }
  }
}

SquawkReport reportWith({String? text}) =>
    SquawkReport(screenshot: Uint8List.fromList([1, 2, 3]), text: text);

/// Waits on the *real* clock until [until] holds.
///
/// `feedback` finishes a submit through RepaintBoundary.toImage(), which only
/// resolves against real time. A fixed delay is a coin flip once the whole
/// suite is running in parallel — poll instead.
Future<void> waitReal(
  WidgetTester tester,
  bool Function() until, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!until() && DateTime.now().isBefore(deadline)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

/// Resets global SDK state and installs a device-context collector that never
/// touches a platform channel.
///
/// Without this, every widget test reaches for the real plugins and hangs:
/// there is no channel implementation in a unit test, and the call neither
/// answers nor throws.
void resetSquawk({DeviceContextCollector? collector}) {
  SquawkController.instance
    ..reset()
    // Without this every test that submits or calls clearUser reaches for
    // shared_preferences, where there is no platform channel to answer.
    ..emailStore = InMemoryEmailStore()
    ..collector = collector ??
        DeviceContextCollector(
          readDevice: () async => const DeviceInfo(
            model: 'Test Device',
            osName: 'TestOS',
            osVersion: '1.0',
          ),
          readApp: () async => const AppInfo(version: '1.0.0', build: '1'),
        );
}

/// Stands in for disk. The real store is exercised on a device; these tests
/// are about the rules around it.
class InMemoryEmailStore implements ReporterEmailStore {
  InMemoryEmailStore({String? initial, this.throwOnEverything = false})
      : _value = initial;

  String? _value;
  final bool throwOnEverything;
  int writes = 0;

  @override
  Future<String?> read() async {
    if (throwOnEverything) throw StateError('storage unavailable');
    return _value;
  }

  @override
  Future<void> write(String email) async {
    if (throwOnEverything) throw StateError('storage unavailable');
    writes++;
    _value = email;
  }

  @override
  Future<void> clear() async {
    if (throwOnEverything) throw StateError('storage unavailable');
    _value = null;
  }
}


/// Spool storage that lives in a map. Lets the spool's rules be tested
/// without a filesystem.
class InMemorySpoolStorage implements SpoolStorage {
  final Map<String, SpooledReport> _entries = {};

  /// Ids standing in for entries a crash left half-written.
  final Set<String> incomplete = {};

  @override
  Future<List<SpooledReport>> list() async {
    final all = _entries.values.toList()
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    return all;
  }

  @override
  Future<void> save(SpooledReport report) async => _entries[report.id] = report;

  @override
  Future<void> delete(String id) async => _entries.remove(id);

  @override
  Future<void> sweepIncomplete() async => incomplete.clear();
}

/// Uploader that records what it was asked to send.
class FakeUploader implements ReportUploader {
  final List<SpooledReport> sent = [];

  /// Applied to every report unless its id is in [failIds].
  UploadOutcome outcome = UploadOutcome.sent;

  /// Ids that should fail retryably regardless of [outcome].
  Set<String> failIds = {};

  @override
  Future<UploadOutcome> upload(SpooledReport report) async {
    if (failIds.contains(report.id)) return UploadOutcome.retryable;
    if (outcome == UploadOutcome.sent) sent.add(report);
    return outcome;
  }
}
