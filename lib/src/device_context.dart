import 'package:flutter/foundation.dart';

/// Which kind of build a report came from.
///
/// Stamped by the SDK rather than supplied by the host app: the dashboard
/// filters on it, and a value the app could set would be a value the app
/// could get wrong.
enum BuildMode {
  debug,
  profile,
  release;

  static BuildMode current() {
    if (kDebugMode) return BuildMode.debug;
    if (kProfileMode) return BuildMode.profile;
    return BuildMode.release;
  }
}

/// What the device plugin told us. Squawk's own type, so swapping the plugin
/// — or dropping it on an unsupported platform — never reaches the report.
class DeviceInfo {
  const DeviceInfo({this.model, this.osName, this.osVersion});

  final String? model;
  final String? osName;
  final String? osVersion;
}

class AppInfo {
  const AppInfo({this.version, this.build});

  final String? version;
  final String? build;
}

/// Everything about the device and app that ships with a report.
class DeviceContext {
  const DeviceContext({
    required this.buildMode,
    this.deviceModel,
    this.osName,
    this.osVersion,
    this.appVersion,
  });

  final BuildMode buildMode;
  final String? deviceModel;
  final String? osName;
  final String? osVersion;

  /// Version and build number joined, e.g. `2.0.1+77`.
  final String? appVersion;

  Map<String, Object?> toJson() => {
        'buildMode': buildMode.name,
        if (deviceModel != null) 'deviceModel': deviceModel,
        if (osName != null) 'osName': osName,
        if (osVersion != null) 'osVersion': osVersion,
        if (appVersion != null) 'appVersion': appVersion,
      };
}

typedef DeviceReader = Future<DeviceInfo> Function();
typedef AppReader = Future<AppInfo> Function();

/// Gathers device and app details, tolerating failure in either.
///
/// Each source is read independently and a failure yields nothing rather than
/// propagating: a report is worth far more than the field that could not be
/// collected, and losing one because an OS lookup threw would be absurd.
class DeviceContextCollector {
  DeviceContextCollector({required this.readDevice, required this.readApp});

  final DeviceReader readDevice;
  final AppReader readApp;

  /// How long a single source gets before it is abandoned.
  ///
  /// A plugin that never answers — a wedged platform channel, an unsupported
  /// platform — must not hold a report hostage. Two seconds is far longer
  /// than either plugin needs and far shorter than a reporter will wait.
  static const Duration timeout = Duration(seconds: 2);

  Future<DeviceContext> collect() async {
    final device = await _tryRead(readDevice);
    final app = await _tryRead(readApp);

    return DeviceContext(
      buildMode: BuildMode.current(),
      deviceModel: device?.model,
      osName: device?.osName,
      osVersion: device?.osVersion,
      appVersion: _joinVersion(app),
    );
  }

  static Future<T?> _tryRead<T>(Future<T> Function() read) async {
    try {
      return await read().timeout(timeout);
    } catch (_) {
      // Includes TimeoutException: a missing field is a far smaller loss
      // than a report that never sends.
      return null;
    }
  }

  static String? _joinVersion(AppInfo? app) {
    if (app?.version == null) return null;
    final build = app!.build;
    return build == null || build.isEmpty
        ? app.version
        : '${app.version}+$build';
  }
}
