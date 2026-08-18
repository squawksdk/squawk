import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:squawk/src/upload/http_report_uploader.dart';
import 'package:squawk/src/upload/report_uploader.dart';
import 'package:squawk/src/upload/spool_storage.dart';

void main() {
  final report = SpooledReport(
    id: 'r1',
    capturedAt: DateTime.utc(2026, 8, 17, 12, 30),
    metadata: {'text': 'the button is red', 'buildMode': 'release'},
    screenshot: Uint8List.fromList([137, 80, 78, 71]),
  );

  HttpReportUploader uploaderReturning(
    int status, {
    void Function(http.Request)? capture,
  }) =>
      HttpReportUploader(
        apiKey: 'sq_live_key',
        endpoint: Uri.parse('https://example.test/v1/squawks'),
        client: MockClient((request) async {
          capture?.call(request);
          return http.Response('', status);
        }),
      );

  group('the wire contract', () {
    // These field names are matched by hand in a TypeScript service in
    // another repository. Changing them here without changing it there means
    // every report is rejected.
    test('carries the key, the metadata and the image', () async {
      late http.Request seen;
      final uploader = uploaderReturning(200, capture: (r) => seen = r);

      await uploader.upload(report);

      expect(seen.method, 'POST');
      expect(seen.url.path, '/v1/squawks');
      expect(seen.headers['Authorization'], 'Bearer sq_live_key');

      // latin1, not utf8: the body carries raw PNG bytes, which are not valid
      // UTF-8 and would throw on decode.
      final body = latin1.decode(seen.bodyBytes);
      expect(body, contains('name="${HttpReportUploader.metadataField}"'));
      expect(body, contains('name="${HttpReportUploader.screenshotField}"'));
      expect(body, contains('filename="r1.png"'));
    });

    test('the metadata is JSON carrying the capture time', () async {
      late http.Request seen;
      final uploader = uploaderReturning(200, capture: (r) => seen = r);

      await uploader.upload(report);

      final json = RegExp(r'\{.*\}', dotAll: true)
          .firstMatch(latin1.decode(seen.bodyBytes))!;
      final decoded = jsonDecode(json.group(0)!) as Map<String, Object?>;

      expect(decoded['capturedAt'], '2026-08-17T12:30:00.000Z');
      expect(decoded['text'], 'the button is red');
      expect(decoded['buildMode'], 'release');
    });
  });

  group('what each status means', () {
    Future<UploadOutcome> outcomeOf(int status) =>
        uploaderReturning(status).upload(report);

    test('2xx is delivered', () async {
      expect(await outcomeOf(200), UploadOutcome.sent);
      expect(await outcomeOf(202), UploadOutcome.sent);
    });

    // The server understood and refused. Retrying cannot change the answer.
    test('4xx is refused for good', () async {
      expect(await outcomeOf(400), UploadOutcome.rejected);
      expect(await outcomeOf(413), UploadOutcome.rejected);
      expect(await outcomeOf(422), UploadOutcome.rejected);
    });

    // Deliberately not treated as permanent while the backend is new: an
    // auth bug on our side would otherwise destroy every report from every
    // user. See SQUAW-33.
    test('401 is retried, and says so loudly', () async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      expect(await outcomeOf(401), UploadOutcome.retryable);

      expect(errors, hasLength(1));
      expect(errors.single.exception.toString(), contains('API key'));
    });

    test('429 means not now, not never', () async {
      expect(await outcomeOf(429), UploadOutcome.retryable);
    });

    test('5xx is worth another attempt', () async {
      expect(await outcomeOf(500), UploadOutcome.retryable);
      expect(await outcomeOf(503), UploadOutcome.retryable);
    });

    // No route, DNS failure, TLS error. None of these say the report is bad.
    test('a transport failure is retryable', () async {
      final uploader = HttpReportUploader(
        apiKey: 'k',
        endpoint: Uri.parse('https://example.test/v1/squawks'),
        client: MockClient((_) async => throw const SocketExceptionStub()),
      );

      expect(await uploader.upload(report), UploadOutcome.retryable);
    });
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
