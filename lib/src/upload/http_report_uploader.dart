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
  /// portals accept a connection and then never answer. Covers the whole
  /// exchange including the response body — a portal can also answer the
  /// headers and then stall the body.
  final Duration timeout;

  /// Whether the console has already been told the key was rejected, so a
  /// spool full of reports produces the message once, not once per entry per
  /// drain.
  bool _keyRejectionReported = false;

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
          .then(http.Response.fromStream)
          .timeout(timeout);

      final outcome = _outcomeFor(response.statusCode);
      if (response.statusCode == 401) {
        _reportRejectedKeyOnce();
      } else if (outcome == UploadOutcome.sent) {
        _keyRejectionReported = false;
      }
      return outcome;
    } catch (_) {
      // Anything thrown here is a transport problem — no route, DNS failure,
      // TLS error, timeout. None of them say the report is bad.
      return UploadOutcome.unreachable;
    }
  }

  /// A rejected key is otherwise invisible: reports simply never arrive, and
  /// the developer has nothing to go on. Saying so in the console turns a
  /// silent failure into a one-line fix.
  void _reportRejectedKeyOnce() {
    if (_keyRejectionReported) return;
    _keyRejectionReported = true;

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
  /// - 401 is retried on purpose, permanently — a settled decision, not a
  ///   stopgap. Dropping on 401 destroys reports unrecoverably over what may
  ///   be a fixable key problem; retrying costs only battery, and reports
  ///   captured under a wrong key have been observed delivering intact the
  ///   moment the app restarted with the right one.
  static UploadOutcome _outcomeFor(int status) {
    if (status >= 200 && status < 300) return UploadOutcome.sent;
    if (status == 401 || status == 429 || status >= 500) {
      return UploadOutcome.retryable;
    }
    return UploadOutcome.rejected;
  }
}
