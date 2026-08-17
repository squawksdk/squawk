import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/upload/report_payload.dart';

/// The other half of the wire contract. Every key asserted here is matched by
/// hand in a TypeScript service in another repository.
void main() {
  SquawkReport reportWith({
    String? text,
    String? reporterEmail,
    String? userId,
    Map<String, Object?> metadata = const {},
    List<LogEntry> logs = const [],
    DeviceContext? device,
  }) =>
      SquawkReport(
        screenshot: Uint8List.fromList([1]),
        text: text,
        reporterEmail: reporterEmail,
        userId: userId,
        metadata: metadata,
        logs: logs,
        device: device,
      );

  test('a bare report sends almost nothing', () {
    expect(wireMetadata(reportWith()), isEmpty);
  });

  // Absent fields are omitted rather than sent as null. Screenshots already
  // dominate the payload; empty keys are pure waste on a mobile network.
  test('absent fields are left out, not sent as null', () {
    final payload = wireMetadata(reportWith(text: 'the button is red'));

    expect(payload.keys, ['text']);
  });

  test('carries what the reporter and the app supplied', () {
    final payload = wireMetadata(
      reportWith(
        text: 'crashed on checkout',
        reporterEmail: 'jo@client.com',
        userId: 'u_42',
        metadata: {'plan': 'trial'},
      ),
    );

    expect(payload['text'], 'crashed on checkout');
    expect(payload['reporterEmail'], 'jo@client.com');
    expect(payload['userId'], 'u_42');
    expect(payload['metadata'], {'plan': 'trial'});
  });

  test('device context is flattened alongside the rest', () {
    final payload = wireMetadata(
      reportWith(
        device: const DeviceContext(
          buildMode: BuildMode.release,
          deviceModel: 'Pixel 8',
          osName: 'Android',
          osVersion: '16',
          appVersion: '1.2.0+7',
        ),
      ),
    );

    expect(payload['buildMode'], 'release');
    expect(payload['deviceModel'], 'Pixel 8');
    expect(payload['osVersion'], '16');
    expect(payload['appVersion'], '1.2.0+7');
  });

  test('logs carry a UTC timestamp and mark only the errors', () {
    final payload = wireMetadata(
      reportWith(
        logs: [
          LogEntry(
            message: 'tapped checkout',
            timestamp: DateTime.utc(2026, 8, 17, 12),
          ),
          LogEntry(
            message: 'payment failed',
            timestamp: DateTime.utc(2026, 8, 17, 12, 1),
            isError: true,
          ),
        ],
      ),
    );

    final logs = payload['logs']! as List;
    expect(logs, hasLength(2));
    expect(logs.first, {
      'at': '2026-08-17T12:00:00.000Z',
      'message': 'tapped checkout',
    });
    expect((logs.last as Map)['error'], isTrue);
  });
}
