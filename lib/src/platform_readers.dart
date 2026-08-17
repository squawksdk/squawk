import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'device_context.dart';

/// Reads device details through `device_info_plus`.
///
/// Values come from the plugin's untyped `data` map rather than its typed
/// classes. The map keys are stable across the plugin's major versions, which
/// is what lets the package accept a range wide enough to resolve on both
/// older and current Flutter versions.
Future<DeviceInfo> readDeviceInfo() async {
  final data = (await DeviceInfoPlugin().deviceInfo).data;

  if (Platform.isAndroid) {
    return DeviceInfo(
      model: _join(data['manufacturer'], data['model']),
      osName: 'Android',
      osVersion: _string((data['version'] as Map?)?['release']),
    );
  }

  if (Platform.isIOS) {
    return DeviceInfo(
      // `utsname.machine` is the hardware identifier, e.g. iPhone16,2 —
      // more precise than `model`, which is just "iPhone".
      model: _string((data['utsname'] as Map?)?['machine']) ??
          _string(data['model']),
      osName: 'iOS',
      osVersion: _string(data['systemVersion']),
    );
  }

  return DeviceInfo(
    model: _string(data['model']) ?? _string(data['computerName']),
    osName: Platform.operatingSystem,
    osVersion: Platform.operatingSystemVersion,
  );
}

Future<AppInfo> readAppInfo() async {
  final info = await PackageInfo.fromPlatform();
  return AppInfo(version: info.version, build: info.buildNumber);
}

String? _string(Object? value) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty) ? null : text;
}

String? _join(Object? first, Object? second) {
  final a = _string(first);
  final b = _string(second);
  if (a == null) return b;
  if (b == null) return a;
  // Android reports these separately; "samsung SM-A566B" reads better than
  // either half alone.
  return b.toLowerCase().startsWith(a.toLowerCase()) ? b : '$a $b';
}
