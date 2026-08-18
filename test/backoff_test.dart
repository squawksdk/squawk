import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/src/upload/backoff.dart';

void main() {
  const backoff = Backoff();

  test('the first retry is soon, so a blip costs almost nothing', () {
    expect(backoff.delayFor(1), lessThanOrEqualTo(const Duration(seconds: 4)));
  });

  test('delays grow with each attempt', () {
    final delays = [for (var i = 1; i <= 5; i++) backoff.delayFor(i)];

    for (var i = 1; i < delays.length; i++) {
      expect(
        delays[i],
        greaterThan(delays[i - 1]),
        reason: 'attempt ${i + 1} must wait longer than attempt $i',
      );
    }
  });

  // Without a ceiling the delay doubles into days, and a report captured on
  // Monday would sit unsent on Friday because the schedule outran the spool's
  // own seven-day expiry.
  test('the delay is capped', () {
    expect(backoff.delayFor(50), backoff.maxDelay);
    expect(backoff.delayFor(500), backoff.maxDelay);
  });

  // Ten attempts is where the spool gives up on an entry. They have to span
  // long enough to ride out an ordinary server outage, or a perfectly good
  // report is discarded because the backend was down over lunch.
  test('ten attempts span most of a day', () {
    final total = List.generate(10, (i) => backoff.delayFor(i + 1))
        .fold(Duration.zero, (sum, d) => sum + d);

    expect(total, greaterThan(const Duration(hours: 6)));
    expect(total, lessThan(const Duration(days: 2)));
  });

  test('attempt numbers below one are treated as the first attempt', () {
    expect(backoff.delayFor(0), backoff.delayFor(1));
    expect(backoff.delayFor(-3), backoff.delayFor(1));
  });
}
