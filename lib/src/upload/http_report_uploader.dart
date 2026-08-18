import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'report_uploader.dart';
import 'spool_storage.dart';

/// Sends a report to the ingest endpoint as multipart form data.
///
/// This is the only place in the SDK that knows the wire format. The server
/// side is TypeScript in a separate repository with no shared types, so the
/// field names below are a contract maintained by hand — change them here and
/// the ingest Worker changes with them, or reports start being rejected.
class HttpReportUploader implements ReportUploader {
  HttpReportUploader({
    required this.apiKey,
    required this.endpoint,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  /// The project's publishable key. Safe to ship inside an app bundle.
  final String apiKey;

  final Uri endpoint;
  final http.Client _client;

  /// A stalled request must not hold the drain open indefinitely; captive
  /// portals accept a connection and then never answer.
  final Duration timeout;

  static const String screenshotField = 'screenshot';
  static const String metadataField = 'report';

  @override
  Future<UploadOutcome> upload(SpooledReport report) async {
    try {
      final request = http.MultipartRequest('POST', endpoint)
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..fields[metadataField] = jsonEncode({
          'capturedAt': report.capturedAt.toUtc().toIso8601String(),
          ...report.metadata,
        })
        ..files.add(
          http.MultipartFile.fromBytes(
            screenshotField,
            report.screenshot,
            filename: '${report.id}.png',
          ),
        );

      final response = await _client
          .send(request)
          .timeout(timeout)
          .then(http.Response.fromStream);

      if (response.statusCode == 401) _reportRejectedKey();
      return _outcomeFor(response.statusCode);
    } catch (_) {
      // Anything thrown here is a transport problem — no route, DNS failure,
      // TLS error, timeout. None of them say the report is bad.
      return UploadOutcome.retryable;
    }
  }

  /// A rejected key is otherwise invisible: reports simply never arrive, and
  /// the developer has nothing to go on. Saying so in the console turns a
  /// silent failure into a one-line fix.
  void _reportRejectedKey() {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError(
          'Squawk rejected the API key when sending a report. Check the key '
          'against project settings on squawksdk.com. Reports are being kept '
          'and retried in the meantime.',
        ),
        library: 'squawk',
        context: ErrorDescription('while uploading a report'),
      ),
    );
  }

  /// Maps a status to what the spool should do next.
  ///
  /// The distinction that matters: a 4xx means the server understood the
  /// request and refused it, so retrying spends battery on an answer that
  /// cannot change. Two exceptions:
  ///
  /// - 429 means "not now", not "never".
  /// - 401 is retried on purpose while the backend is new. Dropping on 401
  ///   means an auth bug in our own ingest destroys every report from every
  ///   user, unrecoverably, whereas retrying a genuinely wrong key costs only
  ///   battery. See SQUAW-33 for tightening this once auth is proven.
  static UploadOutcome _outcomeFor(int status) {
    if (status >= 200 && status < 300) return UploadOutcome.sent;
    if (status == 401 || status == 429 || status >= 500) {
      return UploadOutcome.retryable;
    }
    return UploadOutcome.rejected;
  }
}
