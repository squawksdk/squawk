import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'squawk_options.dart';

/// The native side sends one event per detected shake. Listening starts the
/// platform's detector; cancelling releases it.
@visibleForTesting
const EventChannel shakeEventChannel = EventChannel('squawk/shake');

/// The acceleration beyond gravity, in m/s², that the Android detector
/// counts as "accelerating". Part of the channel contract with the native
/// code; iOS uses the system shake gesture and ignores it.
///
/// medium is the force `shake_gesture` shipped with, so the default feel
/// does not change under anyone's thumb when they upgrade.
const _forceFor = {
  ShakeSensitivity.light: 4.0,
  ShakeSensitivity.medium: 6.0,
  ShakeSensitivity.firm: 10.0,
};

/// Fires [onShake] when the device is shaken.
///
/// Holds the accelerometer only while the app is foregrounded. On platforms
/// where the plugin does not exist (web and desktop builds) the channel is
/// never touched: activation failures bypass a stream's onError and land in
/// [FlutterError.reportError], so they cannot be caught, only avoided.
class ShakeTrigger extends StatefulWidget {
  const ShakeTrigger({
    super.key,
    required this.sensitivity,
    required this.onShake,
    required this.child,
  });

  final ShakeSensitivity sensitivity;
  final VoidCallback onShake;
  final Widget child;

  @override
  State<ShakeTrigger> createState() => _ShakeTriggerState();
}

class _ShakeTriggerState extends State<ShakeTrigger> {
  StreamSubscription<Object?>? _subscription;
  late final AppLifecycleListener _lifecycle;

  /// Set on the first channel error and never cleared: the one error the
  /// native side sends, no accelerometer on the device, does not go away by
  /// trying again on the next foregrounding.
  var _unsupported = false;

  bool get _supportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycleChange);
    // Null means no lifecycle event has arrived yet, which is how every app
    // starts: foregrounded.
    final state = SchedulerBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) _listen();
  }

  @override
  void didUpdateWidget(ShakeTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sensitivity != oldWidget.sensitivity &&
        _subscription != null) {
      _cancel();
      _listen();
    }
  }

  void _onLifecycleChange(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _listen();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _cancel();
      case AppLifecycleState.inactive:
        // Transient: the app switcher, a permission dialog, a phone call.
        // Cancelling here would churn the sensor on every system overlay.
        break;
    }
  }

  void _listen() {
    if (_unsupported || !_supportedPlatform || _subscription != null) return;
    _subscription = shakeEventChannel
        .receiveBroadcastStream({'force': _forceFor[widget.sensitivity]!})
        .listen(
          (_) => widget.onShake(),
          onError: (Object error) {
            _unsupported = true;
            _cancel();
            assert(() {
              debugPrint('squawk: shake trigger unavailable ($error)');
              return true;
            }());
          },
        );
  }

  void _cancel() {
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
