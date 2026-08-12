import 'dart:collection';
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// One captured line.
class LogEntry {
  LogEntry({
    required this.message,
    required this.timestamp,
    this.isError = false,
  });

  final String message;
  final DateTime timestamp;
  final bool isError;

  @override
  String toString() =>
      '${timestamp.toIso8601String()} ${isError ? '[error] ' : ''}$message';
}

/// Keeps the most recent log lines and Flutter errors in memory, ready to
/// attach to a report.
///
/// Captures by replacing [debugPrint] and the two global error handlers, and
/// **always chains to whatever was there before**. The host app has probably
/// already installed Sentry, Crashlytics or its own logging; swallowing their
/// output — or worse, their crash reports — would be the most damaging thing
/// this SDK could do.
///
/// Deliberately not zone-based: running the app in a custom zone triggers the
/// "Zone mismatch" warning present since Flutter 3.10, and the host app may
/// already own its zone.
class LogBuffer {
  LogBuffer({this.capacity = 100});

  final int capacity;

  /// Longest single line kept, in characters.
  ///
  /// The entry count is capped, but without this one pathological line — a
  /// serialized response, a giant stack trace — would dominate the uploaded
  /// report on its own. Truncating trades exactness for a payload that stays
  /// predictable.
  static const int maxLineLength = 2048;

  final Queue<LogEntry> _entries = Queue<LogEntry>();

  DebugPrintCallback? _previousDebugPrint;
  FlutterExceptionHandler? _previousOnError;
  ErrorCallback? _previousPlatformOnError;
  bool _started = false;

  /// The captured lines, oldest first.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  void start() {
    if (_started) return;
    _started = true;

    _previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        _add(LogEntry(message: _truncate(message), timestamp: _now()));
      }
      _previousDebugPrint?.call(message, wrapWidth: wrapWidth);
    };

    _previousOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _addError(details.exceptionAsString());
      _previousOnError?.call(details);
    };

    _previousPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _addError(error.toString());
      // Returning false lets the error keep propagating when nothing else
      // handles it. Claiming to have handled it would hide real crashes.
      return _previousPlatformOnError?.call(error, stack) ?? false;
    };
  }

  void stop() {
    if (!_started) return;
    _started = false;

    if (_previousDebugPrint != null) debugPrint = _previousDebugPrint!;
    FlutterError.onError = _previousOnError;
    PlatformDispatcher.instance.onError = _previousPlatformOnError;

    _previousDebugPrint = null;
    _previousOnError = null;
    _previousPlatformOnError = null;
  }

  void clear() => _entries.clear();

  void _addError(String message) => _add(
        LogEntry(
          message: _truncate(message),
          timestamp: _now(),
          isError: true,
        ),
      );

  static String _truncate(String message) => message.length <= maxLineLength
      ? message
      : '${message.substring(0, maxLineLength)}… (truncated)';

  void _add(LogEntry entry) {
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
  }

  DateTime _now() => DateTime.now();
}
