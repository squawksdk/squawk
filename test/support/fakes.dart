import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:shake_gesture_platform_interface/shake_gesture_platform_interface.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/capture/report_capture.dart';

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
