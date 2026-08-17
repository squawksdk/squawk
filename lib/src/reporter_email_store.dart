import 'package:shared_preferences/shared_preferences.dart';

/// Rules for the address a reporter types on the sheet.
abstract final class ReporterEmail {
  /// Longest address kept.
  ///
  /// The real limit for an email address is 254 characters; the slack allows
  /// for oddities without letting a paste of arbitrary size reach the report.
  static const int maxLength = 320;

  /// Trims, drops blanks, and caps length.
  ///
  /// Deliberately does no format validation. A typo'd address is worth far
  /// more than a report the reporter abandoned because the submit button
  /// refused them.
  static String? normalise(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.length <= maxLength
        ? trimmed
        : trimmed.substring(0, maxLength);
  }
}

/// Remembers the reporter's address between reports.
abstract interface class ReporterEmailStore {
  Future<String?> read();
  Future<void> write(String email);
  Future<void> clear();
}

/// Wraps a store so storage failures never reach the reporting path.
///
/// Remembering an address is a convenience. A device with full storage, or a
/// platform where the plugin is missing, must still be able to send reports.
class SafeReporterEmailStore implements ReporterEmailStore {
  const SafeReporterEmailStore(this._inner);

  final ReporterEmailStore _inner;

  @override
  Future<String?> read() async {
    try {
      return await _inner.read();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String email) async {
    try {
      await _inner.write(email);
    } catch (_) {
      // Nothing to do: the address still ships with this report, it just
      // will not be offered back on the next one.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _inner.clear();
    } catch (_) {
      // Ignored for the same reason.
    }
  }
}

/// Disk-backed store.
class PrefsReporterEmailStore implements ReporterEmailStore {
  const PrefsReporterEmailStore();

  static const String _key = 'squawk.reporter_email';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String email) async =>
      (await SharedPreferences.getInstance()).setString(_key, email);

  @override
  Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}
