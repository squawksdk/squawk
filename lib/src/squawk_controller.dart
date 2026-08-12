import 'package:flutter/widgets.dart';

import 'capture/report_capture.dart';
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

  /// Opens the capture UI and returns the report, with user context attached.
  ///
  /// Reports a Flutter error and returns null when no widget is mounted — a
  /// misconfigured SDK must not take the host app down.
  Future<SquawkReport?> show() async {
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

    final report = await host.capture.capture(host.context);
    return report?.copyWith(
      userId: _userId,
      userEmail: _userEmail,
      metadata: Map.unmodifiable(_metadata),
    );
  }

  @visibleForTesting
  void reset() {
    _host = null;
    clearUser();
  }
}

class _MountedHost {
  _MountedHost(this.context, this.capture);

  final BuildContext context;
  final ReportCapture capture;
}
