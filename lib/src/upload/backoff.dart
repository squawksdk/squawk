import 'dart:math' as math;

/// How long to wait before retrying a failed upload.
///
/// Exponential from a few seconds up to a ceiling. The ceiling matters: left
/// to double freely the delay reaches days, and a report captured on Monday
/// would still be waiting on Friday — outliving the spool's own expiry without
/// ever having been tried again.
class Backoff {
  const Backoff({
    this.first = const Duration(seconds: 2),
    this.growth = 3,
    this.maxDelay = const Duration(hours: 6),
  });

  /// Wait before the second attempt. Short, so a momentary blip costs the
  /// reporter nothing.
  final Duration first;

  /// Multiplier between attempts.
  ///
  /// Tripling rather than doubling for a specific reason: at ten attempts —
  /// the point where the spool gives up on an entry — doubling from two
  /// seconds spans barely half an hour, so an ordinary server outage would
  /// burn every attempt and discard the report. Tripling spans about half a
  /// day.
  final int growth;

  /// Longest wait between attempts, however many have failed.
  final Duration maxDelay;

  /// Delay before retrying, given how many attempts have already failed.
  ///
  /// [attempt] is one-based; anything lower is treated as the first.
  Duration delayFor(int attempt) {
    final n = math.max(1, attempt);

    // Cheap guard against overflow: anything this far out is far beyond the
    // ceiling anyway.
    if (n > 20) return maxDelay;

    final grown = first * math.pow(growth, n - 1).toDouble();
    return grown > maxDelay ? maxDelay : grown;
  }
}
