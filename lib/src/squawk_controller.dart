import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'capture/report_capture.dart';
import 'device_context.dart';
import 'log_buffer.dart';
import 'reporter_email_store.dart';
import 'squawk_report.dart';
import 'upload/delivery.dart';
import 'upload/disk_spool_storage.dart';
import 'upload/report_payload.dart';
import 'upload/spool.dart';
import 'upload/spool_storage.dart';

/// Holds the state the static API needs, independent of the widget tree.
///
/// User context lives here rather than in the widget's state because apps set
/// it during start-up, often before the first frame. Storing it on the widget
/// would silently drop those calls.
class SquawkController {
  SquawkController();

  static final SquawkController instance = SquawkController();

  String? _userId;
  String? _userEmail;
  final Map<String, Object?> _metadata = {};

  /// Set while a [Squawk] widget is mounted. Null otherwise.
  _MountedHost? _host;

  /// Present only while log capture is enabled — `captureLogs: false` must
  /// leave nothing buffered in memory, not merely withhold it from reports.
  LogBuffer? _logs;

  /// Swapped in tests so the plugins are never touched.
  DeviceContextCollector? collector;

  /// Where reports wait until they reach the backend. Null before a [Squawk]
  /// widget has mounted, since it needs the app's API key to exist.
  ///
  /// Outlives the widget on purpose: a remount must not lose queued reports.
  Spool? spool;

  /// Schedules when the spool sends. Kept here beside the spool so a
  /// remounted widget restarts the same delivery instead of orphaning it.
  Delivery? delivery;

  /// Remembers the reporter's address between reports. Swapped in tests.
  ReporterEmailStore emailStore =
      SafeReporterEmailStore(InProcessReporterEmailStore());

  /// The address to offer on the sheet: whatever the app already told us
  /// about the signed-in user, else whatever the reporter last typed.
  ///
  /// Asking a signed-in tester for an email is asking a question the app has
  /// already answered.
  Future<String?> suggestedReporterEmail() async =>
      _userEmail ?? await emailStore.read();

  Future<void> rememberReporterEmail(String? email) async {
    if (email == null) return;
    await emailStore.write(email);
  }

  void startCapturingLogs() => (_logs ??= LogBuffer()).start();

  void stopCapturingLogs() {
    _logs?.stop();
    _logs = null;
  }

  void setUser({String? id, String? email}) {
    _userId = id;
    _userEmail = email;
  }

  /// A value JSON cannot carry would otherwise throw while saving the
  /// report — after the reporter has tapped submit — and lose it. Falling
  /// back to toString here keeps the report and still says something useful.
  void setMetadata(String key, Object? value) =>
      _metadata[key] = _jsonEncodable(value);

  static Object? _jsonEncodable(Object? value) {
    try {
      jsonEncode(value);
      return value;
    } catch (_) {
      return value.toString();
    }
  }

  /// Forgets the identity, the metadata, and the remembered reporter address.
  ///
  /// The address matters here: QA devices get passed around, and without this
  /// a logout would leave the previous tester's email prefilled on the next
  /// person's report.
  void clearUser() {
    _userId = null;
    _userEmail = null;
    _metadata.clear();
    emailStore.clear();
  }

  void mount(BuildContext context, ReportCapture capture) {
    assert(
      _host == null,
      'Two Squawk widgets are mounted at once. Squawk should wrap your app '
      'exactly once, at the root.',
    );
    _host = _MountedHost(context, capture);
  }

  void unmount(BuildContext context) {
    if (_host?.context == context) _host = null;
  }

  /// Whether a capture is currently on screen.
  ///
  /// The floating button watches this so it can hide itself: it lives inside
  /// the capture boundary, so a visible button would appear in the very
  /// screenshot it produced.
  ValueListenable<bool> get isCapturing => _isCapturing;
  final ValueNotifier<bool> _isCapturing = ValueNotifier(false);

  /// The last completed report, whichever trigger produced it.
  ///
  /// Delivery does not read this — reports reach the inbox through the
  /// spool. It exists for the example's dev harness, which watches it to
  /// show on a device what was just captured.
  ValueListenable<SquawkReport?> get lastReport => _lastReport;
  final ValueNotifier<SquawkReport?> _lastReport = ValueNotifier(null);

  /// Opens the capture UI and returns the report, with user context attached.
  ///
  /// Does nothing while a capture is already on screen. The reporter is
  /// holding the phone when the sheet opens, so a second shake is likely;
  /// without this guard it would stack sheets and send two reports for one bug.
  ///
  /// Reports a Flutter error and returns null when no widget is mounted — a
  /// misconfigured SDK must not take the host app down.
  Future<SquawkReport?> show() async {
    if (_isCapturing.value) return null;

    final host = _host;
    if (host == null) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError(
            'No Squawk widget is mounted, so there is nothing to capture. '
            'Wrap your app in Squawk(apiKey: ..., child: ...) before calling '
            'Squawk.show().',
          ),
          library: 'squawk',
          context: ErrorDescription('while opening the report sheet'),
        ),
      );
      return null;
    }

    _isCapturing.value = true;
    try {
      final captured = await host.capture.capture(host.context);
      final report = captured?.copyWith(
        userId: _userId,
        userEmail: _userEmail,
        metadata: Map.unmodifiable(_metadata),
        logs: _logs?.entries ?? const [],
        device: await collector?.collect(),
      );
      if (report != null) {
        _lastReport.value = report;
        // Remembered only after a real submission — a dismissed sheet should
        // not leave an address behind.
        await rememberReporterEmail(report.reporterEmail);
        await _spoolForSending(report);
      }
      return report;
    } finally {
      _isCapturing.value = false;
    }
  }

  /// Hands the report to the spool, which owns delivery from here.
  ///
  /// Failing to queue must not surface to the reporter: they have already
  /// tapped submit and moved on, and a dialog about disk errors helps nobody.
  Future<void> _spoolForSending(SquawkReport report) async {
    final queue = spool;
    if (queue == null) return;

    try {
      final capturedAt = DateTime.now();
      await queue.enqueue(
        SpooledReport(
          id: spoolId(capturedAt),
          capturedAt: capturedAt,
          metadata: wireMetadata(report),
          screenshot: report.screenshot,
        ),
      );
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'squawk',
          context: ErrorDescription('while queueing a report for delivery'),
        ),
      );
    }
  }

  @visibleForTesting
  void reset() {
    _host = null;
    _isCapturing.value = false;
    _lastReport.value = null;
    spool = null;
    delivery = null;
    stopCapturingLogs();
    clearUser();
  }
}

class _MountedHost {
  _MountedHost(this.context, this.capture);

  final BuildContext context;
  final ReportCapture capture;
}
