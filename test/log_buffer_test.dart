import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/src/log_buffer.dart';

void main() {
  volumeAndTruncation();

  late LogBuffer buffer;

  setUp(() => buffer = LogBuffer(capacity: 3));
  tearDown(() => buffer.stop());

  group('buffer behaviour', () {
    test('captures debugPrint output while started', () {
      buffer.start();

      debugPrint('first');
      debugPrint('second');

      expect(buffer.entries.map((e) => e.message), ['first', 'second']);
    });

    test('drops the oldest entry once full, keeping order', () {
      buffer.start();

      for (final line in ['a', 'b', 'c', 'd']) {
        debugPrint(line);
      }

      expect(buffer.entries.map((e) => e.message), ['b', 'c', 'd']);
    });

    test('records Flutter errors alongside ordinary output', () {
      // Silence the handler we chain to: the test framework's default prints
      // the error, which our own debugPrint hook would then capture too.
      final original = FlutterError.onError;
      FlutterError.onError = (_) {};
      addTearDown(() => FlutterError.onError = original);

      buffer.start();

      debugPrint('before the crash');
      FlutterError.onError!(
        FlutterErrorDetails(exception: StateError('boom')),
      );

      expect(buffer.entries, hasLength(2));
      expect(buffer.entries.last.isError, isTrue);
      expect(buffer.entries.last.message, contains('boom'));
      expect(buffer.entries.first.isError, isFalse);
    });

    test('captures nothing before start or after stop', () {
      debugPrint('before start');
      buffer.start();
      debugPrint('while running');
      buffer.stop();
      debugPrint('after stop');

      expect(buffer.entries.map((e) => e.message), ['while running']);
    });
  });

  // The host app almost certainly has something on these already — Sentry,
  // Crashlytics, or its own logging. Swallowing their output or their crash
  // reports would be the worst bug this SDK could ship.
  group('chaining and restore', () {
    test('the previous debugPrint still receives every line', () {
      final seen = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => seen.add(message ?? '');
      addTearDown(() => debugPrint = original);

      buffer.start();
      debugPrint('still visible');

      expect(seen, ['still visible']);
      expect(buffer.entries.single.message, 'still visible');
    });

    test('the previous error handler still fires', () {
      final seen = <FlutterErrorDetails>[];
      final original = FlutterError.onError;
      FlutterError.onError = seen.add;
      addTearDown(() => FlutterError.onError = original);

      buffer.start();
      FlutterError.onError!(
        FlutterErrorDetails(exception: StateError('boom')),
      );

      expect(seen, hasLength(1), reason: 'the host app must still see it');
      expect(buffer.entries, hasLength(1));
    });

    test('stop() puts the original handlers back', () {
      final originalPrint = debugPrint;
      final originalOnError = FlutterError.onError;

      buffer.start();
      expect(debugPrint, isNot(same(originalPrint)));

      buffer.stop();

      expect(debugPrint, same(originalPrint));
      expect(FlutterError.onError, same(originalOnError));
    });
  });
}

void volumeAndTruncation() {
  group('volume and pathological input', () {
    test('a chatty app cannot grow the buffer past its capacity', () {
      final buffer = LogBuffer(capacity: 100);
      addTearDown(buffer.stop);
      buffer.start();

      for (var i = 0; i < 10000; i++) {
        debugPrint('line $i');
      }

      expect(buffer.entries, hasLength(100));
      expect(buffer.entries.first.message, 'line 9900');
      expect(buffer.entries.last.message, 'line 9999');
    });

    test('one enormous line cannot dominate the payload', () {
      final buffer = LogBuffer(capacity: 10);
      addTearDown(buffer.stop);
      buffer.start();

      debugPrint('x' * 500000);

      final stored = buffer.entries.single.message;
      expect(stored.length, lessThanOrEqualTo(LogBuffer.maxLineLength + 32));
      expect(stored, endsWith('… (truncated)'));
    });

    test('a line at the limit is kept whole', () {
      final buffer = LogBuffer(capacity: 10);
      addTearDown(buffer.stop);
      buffer.start();

      final exact = 'y' * LogBuffer.maxLineLength;
      debugPrint(exact);

      expect(buffer.entries.single.message, exact);
    });
  });
}
