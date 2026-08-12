import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/src/device_context.dart';

void main() {
  group('build mode', () {
    // The dashboard filters on this, so it is stamped by the SDK rather than
    // supplied by the host app. A wrong value would quietly misfile every
    // report from a production build as a debug one.
    test('reflects the mode the SDK is compiled in', () {
      final mode = BuildMode.current();

      expect(
        mode,
        kDebugMode
            ? BuildMode.debug
            : kProfileMode
                ? BuildMode.profile
                : BuildMode.release,
      );
    });

    test('tests run in debug, so the stamp is debug here', () {
      expect(BuildMode.current(), BuildMode.debug);
    });
  });

  group('collection failure', () {
    // A report is worth far more than the field that failed. Losing one
    // because an OS version lookup threw would be absurd.
    test('a throwing collector yields empty context, not an exception',
        () async {
      final collector = DeviceContextCollector(
        readDevice: () async => throw StateError('no platform channel'),
        readApp: () async => throw StateError('missing plugin'),
      );

      final context = await collector.collect();

      expect(context.deviceModel, isNull);
      expect(context.osVersion, isNull);
      expect(context.appVersion, isNull);
      // Build mode never depends on a plugin, so it survives regardless.
      expect(context.buildMode, BuildMode.debug);
    });

    test('one failing source does not lose the other', () async {
      final collector = DeviceContextCollector(
        readDevice: () async => throw StateError('boom'),
        readApp: () async => const AppInfo(version: '1.2.3', build: '42'),
      );

      final context = await collector.collect();

      expect(context.deviceModel, isNull);
      expect(context.appVersion, '1.2.3+42');
    });
  });

  group('collected values', () {
    test('device and app details are read through the collector', () async {
      final collector = DeviceContextCollector(
        readDevice: () async => const DeviceInfo(
          model: 'Pixel 8',
          osName: 'Android',
          osVersion: '16',
        ),
        readApp: () async => const AppInfo(version: '2.0.1', build: '77'),
      );

      final context = await collector.collect();

      expect(context.deviceModel, 'Pixel 8');
      expect(context.osName, 'Android');
      expect(context.osVersion, '16');
      expect(context.appVersion, '2.0.1+77');
    });
  });
}
