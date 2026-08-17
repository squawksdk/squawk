import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'spool.dart';

/// Decides when the spool gets a chance to send.
///
/// Three moments, each covering a gap the others leave:
///
/// - **capture** — the common case, handled by the spool's own enqueue
/// - **start-up** — a spool left over from a previous run
/// - **connectivity returning** — the tester walks back into signal without
///   restarting the app
///
/// Plus a timer as a backstop, which runs **only while something is waiting**.
/// A timer that wakes to find an empty queue is battery spent on the host
/// app's behalf, and Squawk has not earned that.
class Delivery {
  Delivery({
    required this.spool,
    this.interval = const Duration(minutes: 5),
    Stream<Object?>? connectivityChanges,
  }) : _connectivityChanges = connectivityChanges ??
            Connectivity().onConnectivityChanged;

  final Spool spool;

  /// How often to retry while reports are waiting.
  final Duration interval;

  final Stream<Object?> _connectivityChanges;

  StreamSubscription<Object?>? _connectivity;
  Timer? _timer;
  bool _started = false;

  /// Whether the backstop is currently ticking. Exposed so a test can assert
  /// the SDK is not burning battery on an empty queue.
  @visibleForTesting
  bool get isTimerRunning => _timer?.isActive ?? false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _connectivity = _connectivityChanges.listen((_) => _drainThenReschedule());

    await spool.start();
    await _rescheduleTimer();
  }

  Future<void> stop() async {
    _started = false;
    _timer?.cancel();
    _timer = null;
    await _connectivity?.cancel();
    _connectivity = null;
  }

  /// Called after anything is queued, so the backstop starts running.
  Future<void> onEnqueued() => _rescheduleTimer();

  Future<void> _drainThenReschedule() async {
    await spool.drain();
    await _rescheduleTimer();
  }

  /// Runs the timer only while the spool has something in it.
  Future<void> _rescheduleTimer() async {
    final idle = await spool.isEmpty;

    if (idle) {
      _timer?.cancel();
      _timer = null;
      return;
    }

    _timer ??= Timer.periodic(interval, (_) => _drainThenReschedule());
  }
}
