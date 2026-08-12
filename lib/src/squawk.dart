import 'package:flutter/widgets.dart';
import 'package:shake_gesture/shake_gesture.dart';

import 'capture/feedback_capture.dart';
import 'capture/report_capture.dart';
import 'device_context.dart';
import 'feedback_button.dart';
import 'squawk_controller.dart';
import 'platform_readers.dart';
import 'squawk_options.dart';

/// Wrap your app in this and a shake opens the report sheet.
///
/// ```dart
/// runApp(
///   Squawk(
///     apiKey: 'sq_live_xxxxxxxx',
///     child: const MyApp(),
///   ),
/// );
/// ```
///
/// The class doubles as the static namespace for the rest of the API:
/// [show], [setUser], [setMetadata] and [clearUser].
class Squawk extends StatelessWidget {
  const Squawk({
    super.key,
    required this.apiKey,
    required this.child,
    this.options = const SquawkOptions(),
    @visibleForTesting ReportCapture? capture,
  }) : _capture = capture;

  /// The project's publishable API key, from project settings on
  /// squawksdk.com.
  final String apiKey;

  final SquawkOptions options;
  final Widget child;

  final ReportCapture? _capture;

  /// Opens the report sheet.
  ///
  /// Safe to call from anywhere. If no [Squawk] widget is mounted this
  /// reports a Flutter error and returns without throwing, so a
  /// misconfigured SDK cannot take the host app down.
  static Future<void> show() => SquawkController.instance.show();

  /// Attaches an identity to every subsequent report.
  ///
  /// Safe to call before the widget mounts, including before `runApp`.
  static void setUser({String? id, String? email}) =>
      SquawkController.instance.setUser(id: id, email: email);

  /// Attaches an arbitrary key/value to every subsequent report.
  static void setMetadata(String key, Object? value) =>
      SquawkController.instance.setMetadata(key, value);

  /// Forgets the user set by [setUser] and everything from [setMetadata].
  static void clearUser() => SquawkController.instance.clearUser();

  @override
  Widget build(BuildContext context) {
    final capture = _capture ?? FeedbackCapture();
    return capture.wrap(
      _SquawkHost(capture: capture, options: options, child: child),
    );
  }
}

/// Registers the mounted context with the controller.
///
/// Separate from [Squawk] so that its context sits *below* whatever
/// [ReportCapture.wrap] inserted, which is where the capture implementation
/// needs to be looked up from.
class _SquawkHost extends StatefulWidget {
  const _SquawkHost({
    required this.capture,
    required this.options,
    required this.child,
  });

  final ReportCapture capture;
  final SquawkOptions options;
  final Widget child;

  @override
  State<_SquawkHost> createState() => _SquawkHostState();
}

class _SquawkHostState extends State<_SquawkHost> {
  @override
  void initState() {
    super.initState();
    SquawkController.instance
      ..mount(context, widget.capture)
      ..collector ??= DeviceContextCollector(
        readDevice: readDeviceInfo,
        readApp: readAppInfo,
      );
    if (widget.options.captureLogs) {
      SquawkController.instance.startCapturingLogs();
    }
  }

  @override
  void dispose() {
    SquawkController.instance.stopCapturingLogs();
    SquawkController.instance.unmount(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var content = widget.child;

    if (widget.options.feedbackButton) {
      content = FeedbackButton(child: content);
    }

    if (widget.options.shakeToReport) {
      content = ShakeGesture(
        // Deliberately no sensitivity setting: iOS exposes none, and Android
        // only through a manifest entry, which would break "zero native
        // setup".
        onShake: () => Squawk.show(),
        child: content,
      );
    }

    return content;
  }
}
