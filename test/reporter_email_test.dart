import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/src/reporter_email_store.dart';

import 'support/fakes.dart';

void main() {
  group('normalisation', () {
    test('trims surrounding whitespace', () {
      expect(ReporterEmail.normalise('  jo@client.com  '), 'jo@client.com');
    });

    // Empty must become null, not an empty string: the report field means
    // "the reporter did not give an address", and "" would read as one.
    test('empty and whitespace-only become null', () {
      expect(ReporterEmail.normalise(''), isNull);
      expect(ReporterEmail.normalise('   '), isNull);
      expect(ReporterEmail.normalise(null), isNull);
    });

    test('an absurd paste is capped rather than shipped whole', () {
      final huge = '${'x' * 5000}@example.com';

      final result = ReporterEmail.normalise(huge)!;

      expect(result.length, ReporterEmail.maxLength);
    });

    // Deliberately permissive: a typo'd address is worth far more than a
    // report the reporter abandoned because we refused to accept it.
    test('keeps input that does not look like an email', () {
      expect(ReporterEmail.normalise('not an email'), 'not an email');
    });
  });

  group('persistence rules', () {
    test('a remembered address is offered back', () async {
      final store = InMemoryEmailStore(initial: 'jo@client.com');

      expect(await store.read(), 'jo@client.com');
    });

    // A shared QA device would otherwise ship the previous tester's address
    // on the next person's report.
    test('clear wipes the remembered address', () async {
      final store = InMemoryEmailStore(initial: 'jo@client.com');

      await store.clear();

      expect(await store.read(), isNull);
    });

    // Storage is a convenience. Losing it must never cost a report.
    test('a failing store is survivable', () async {
      final store = InMemoryEmailStore(throwOnEverything: true);

      expect(() => store.read(), throwsStateError);
      await expectLater(
        SafeReporterEmailStore(store).read(),
        completion(isNull),
      );
      await expectLater(
        SafeReporterEmailStore(store).write('jo@client.com'),
        completes,
      );
      await expectLater(SafeReporterEmailStore(store).clear(), completes);
    });
  });
}
