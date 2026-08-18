import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'spool.dart';

/// Decides when the spool gets a chance to send.
///
/// Four moments, each covering a gap the others leave:
///
/// - **capture** — the common case, handled by the spool's own enqueue; the
///   spool's [Spool.onQueueChanged] then tells this class whether anything
///   was left behind
/// - **start-up** — a spool left over from a previous run
/// - **connectivity returning** — the tester walks back into signal without
///   restarting the app
/// - **a timer as a backstop**, which runs **only while something is
///   waiting**. A timer that wakes to find an empty queue is battery spent on
///   the host app's behalf, and Squawk has not earned that.
///
/// Survives being stopped and started again: the widget that owns it can be
/// remounted, and delivery picks up where it left off.
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

    spool.onQueueChanged = () => unawaited(_rescheduleTimer());
    _connectivity = _connectivityChanges.listen((event) {
      // Losing connectivity is also an event, and draining then can only
      // fail. Worse than pointless: enough of them would look like a report
      // that can never be sent.
      if (_isOffline(event)) return;
      _drainThenReschedule();
    });

    await spool.start();
    await _rescheduleTimer();
  }

  Future<void> stop() async {
    _started = false;
    spool.onQueueChanged = null;
    _timer?.cancel();
    _timer = null;
    // Detached before the await: a remount can call start() while the cancel
    // is in flight, and finishing with `_connectivity = null` here would
    // silently discard the new subscription.
    final connectivity = _connectivity;
    _connectivity = null;
    await connectivity?.cancel();
  }

  static bool _isOffline(Object? event) => switch (event) {
        ConnectivityResult.none => true,
        final List<ConnectivityResult> results =>
          results.every((r) => r == ConnectivityResult.none),
        _ => false,
      };

  Future<void> _drainThenReschedule() async {
    await spool.drain();
    await _rescheduleTimer();
  }

  /// Runs the timer only while the spool has something in it.
  Future<void> _rescheduleTimer() async {
    final idle = await spool.isEmpty;

    // Checked *after* the read: stop() can race the tail of an in-flight
    // drain — or arrive while the queue was being read — and without this
    // the timer stop() just cancelled would be recreated.
    if (!_started) return;

    if (idle) {
      _timer?.cancel();
      _timer = null;
      return;
    }

    _timer ??= Timer.periodic(interval, (_) => _drainThenReschedule());
  }
}
