import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/capture/squawk_feedback_form.dart';
import 'package:squawk/src/squawk_controller.dart';

import 'support/fakes.dart';

void main() {
  late InMemoryEmailStore store;

  setUp(() {
    resetSquawk();
    store = InMemoryEmailStore();
    SquawkController.instance.emailStore = store;
  });

  Widget hostApp({bool askReporterEmail = true}) => Squawk(
        apiKey: 'k',
        options: SquawkOptions(askReporterEmail: askReporterEmail),
        child: const MaterialApp(
          home: Scaffold(body: Center(child: Text('host app'))),
        ),
      );

  Future<void> openSheet(WidgetTester tester) async {
    unawaited(Squawk.show());
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(SquawkFeedbackForm.submitKey));
    await tester.pump(const Duration(milliseconds: 300));
    await waitReal(
      tester,
      () => SquawkController.instance.lastReport.value != null,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a typed address reaches the report, trimmed', (tester) async {
    await tester.pumpWidget(hostApp());
    await openSheet(tester);

    await tester.enterText(
      find.byKey(SquawkFeedbackForm.emailKey),
      '  jo@client.com  ',
    );
    await submit(tester);

    expect(
      SquawkController.instance.lastReport.value?.reporterEmail,
      'jo@client.com',
    );
  });

  testWidgets('askReporterEmail: false renders no field and sends no address',
      (tester) async {
    await tester.pumpWidget(hostApp(askReporterEmail: false));
    await openSheet(tester);

    expect(find.byKey(SquawkFeedbackForm.emailKey), findsNothing);

    await submit(tester);

    expect(
      SquawkController.instance.lastReport.value?.reporterEmail,
      isNull,
    );
  });

  testWidgets('a submitted address is offered back on the next report',
      (tester) async {
    await tester.pumpWidget(hostApp());
    await openSheet(tester);
    await tester.enterText(
      find.byKey(SquawkFeedbackForm.emailKey),
      'jo@client.com',
    );
    await submit(tester);

    expect(store.writes, 1);

    await openSheet(tester);

    expect(
      tester.widget<TextField>(find.byKey(SquawkFeedbackForm.emailKey))
          .controller
          ?.text,
      'jo@client.com',
    );
  });

  // Asking a signed-in tester for their address is asking a question the app
  // has already answered.
  testWidgets('setUser(email:) prefills the field', (tester) async {
    Squawk.setUser(id: 'u_42', email: 'signed.in@client.com');
    await tester.pumpWidget(hostApp());

    await openSheet(tester);

    expect(
      tester.widget<TextField>(find.byKey(SquawkFeedbackForm.emailKey))
          .controller
          ?.text,
      'signed.in@client.com',
    );
  });

  // QA devices get passed around. Without this, a logout would leave the
  // previous tester's address prefilled on the next person's report.
  testWidgets('clearUser wipes the remembered address', (tester) async {
    await tester.pumpWidget(hostApp());
    await openSheet(tester);
    await tester.enterText(
      find.byKey(SquawkFeedbackForm.emailKey),
      'jo@client.com',
    );
    await submit(tester);

    Squawk.clearUser();
    await tester.pumpAndSettle();

    expect(await store.read(), isNull);
  });

  testWidgets('a dismissed sheet leaves no address behind', (tester) async {
    await tester.pumpWidget(hostApp());
    await openSheet(tester);
    await tester.enterText(
      find.byKey(SquawkFeedbackForm.emailKey),
      'jo@client.com',
    );

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(store.writes, 0);
    expect(await store.read(), isNull);
  });

  testWidgets('the reporter address stays distinct from the user address',
      (tester) async {
    Squawk.setUser(id: 'u_42', email: 'account@client.com');
    await tester.pumpWidget(hostApp());
    await openSheet(tester);

    await tester.enterText(
      find.byKey(SquawkFeedbackForm.emailKey),
      'someone.else@client.com',
    );
    await submit(tester);

    final report = SquawkController.instance.lastReport.value!;
    expect(report.userEmail, 'account@client.com');
    expect(report.reporterEmail, 'someone.else@client.com');
  });
}

void unawaited(Future<void> future) {}
