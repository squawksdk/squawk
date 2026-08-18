import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shake_gesture/shake_gesture.dart';

import 'capture/feedback_capture.dart';
import 'capture/report_capture.dart';
import 'device_context.dart';
import 'feedback_button.dart';
import 'squawk_controller.dart';
import 'platform_readers.dart';
import 'upload/delivery.dart';
import 'upload/disk_spool_storage.dart';
import 'upload/http_report_uploader.dart';
import 'upload/spool.dart';
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
    @visibleForTesting Uri? endpoint,
  })  : _capture = capture,
        _endpoint = endpoint;

  /// The project's publishable API key, from project settings on
  /// squawksdk.com.
  final String apiKey;

  final SquawkOptions options;
  final Widget child;

  final ReportCapture? _capture;
  final Uri? _endpoint;

  /// Where reports are sent.
  ///
  /// Not configurable by the host app on purpose: there is no self-hosted
  /// backend, so an option here would only be a way to point reports
  /// somewhere they cannot arrive.
  static final Uri defaultEndpoint =
      Uri.parse('https://ingest.squawksdk.com/v1/squawks');

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
    final capture =
        _capture ?? FeedbackCapture(askReporterEmail: options.askReporterEmail);
    return capture.wrap(
      _SquawkHost(
        capture: capture,
        options: options,
        apiKey: apiKey,
        endpoint: _endpoint ?? defaultEndpoint,
        child: child,
      ),
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
    required this.apiKey,
    required this.endpoint,
    required this.child,
  });

  final ReportCapture capture;
  final SquawkOptions options;
  final String apiKey;
  final Uri endpoint;
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
    _startDelivery();
  }

  /// Starts delivery and sends anything a previous run left behind.
  ///
  /// Deliberately not awaited: the host app's first frame must not wait on
  /// disk or on a network call, and a failure here is a Squawk problem rather
  /// than something their app should notice.
  ///
  /// The spool and delivery live on the controller, not this state: they must
  /// survive a remount, or queued reports would lose their retries for the
  /// rest of the process.
  void _startDelivery() {
    final controller = SquawkController.instance;
    final spool = controller.spool ??= Spool(
      storage: DiskSpoolStorage(),
      uploader: HttpReportUploader(
        apiKey: widget.apiKey,
        endpoint: widget.endpoint,
      ),
    );
    final delivery = controller.delivery ??= Delivery(spool: spool);
    unawaited(delivery.start());
  }

  @override
  void dispose() {
    unawaited(SquawkController.instance.delivery?.stop());
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
