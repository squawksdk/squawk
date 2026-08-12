import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'capture/report_capture.dart';
import 'log_buffer.dart';
import 'squawk_report.dart';

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

  void startCapturingLogs() => (_logs ??= LogBuffer()).start();

  void stopCapturingLogs() {
    _logs?.stop();
    _logs = null;
  }

  void setUser({String? id, String? email}) {
    _userId = id;
    _userEmail = email;
  }

  void setMetadata(String key, Object? value) => _metadata[key] = value;

  void clearUser() {
    _userId = null;
    _userEmail = null;
    _metadata.clear();
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
  /// This is the stubbed sink: reports currently stop here. The example app
  /// watches it to show what was captured. It goes away once the spool and
  /// upload land and reports have a real destination.
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
      );
      if (report != null) _lastReport.value = report;
      return report;
    } finally {
      _isCapturing.value = false;
    }
  }

  @visibleForTesting
  void reset() {
    _host = null;
    _isCapturing.value = false;
    _lastReport.value = null;
    stopCapturingLogs();
    clearUser();
  }
}

class _MountedHost {
  _MountedHost(this.context, this.capture);

  final BuildContext context;
  final ReportCapture capture;
}
