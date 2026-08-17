import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/capture/squawk_feedback_form.dart';
import 'package:squawk/src/squawk_controller.dart';

import 'support/fakes.dart';

/// Reported from a Samsung A56 on Android 16: the submit button sat underneath
/// the system navigation bar and could not be tapped, which makes the SDK
/// unusable on any device with on-screen back/home buttons.
///
/// `feedback` accounts for the top padding and the keyboard, but never
/// `padding.bottom`, and ships no SafeArea.
void main() {
  setUp(() => resetSquawk());

  const navBarHeight = 48.0;

  /// Simulates a device with on-screen navigation buttons by setting real
  /// view padding, rather than faking a MediaQuery that would contradict the
  /// test surface.
  void giveDeviceANavBar(WidgetTester tester) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(bottom: navBarHeight);
    addTearDown(tester.view.reset);
  }

  Widget hostApp() => const Squawk(
        apiKey: 'k',
        child: MaterialApp(
          home: Scaffold(body: Center(child: Text('host app'))),
        ),
      );

  testWidgets('the submit button clears the system navigation bar',
      (tester) async {
    giveDeviceANavBar(tester);
    await tester.pumpWidget(hostApp());

    unawaited(Squawk.show());
    await tester.pumpAndSettle();

    final submit = find.byKey(const Key('squawk_submit_button'));
    expect(submit, findsOneWidget);

    final button = tester.getRect(submit);
    final screenHeight = tester.view.physicalSize.height;

    expect(
      button.bottom,
      lessThanOrEqualTo(screenHeight - navBarHeight),
      reason: 'the button must sit above the navigation bar, not under it',
    );
  });

  // The sheet opens at a fraction of screen height. If the fixed area at the
  // bottom grows past it, the scrollable region collapses to nothing and the
  // comment box — the primary input — silently stops rendering.
  testWidgets('every input renders in the collapsed sheet', (tester) async {
    await tester.pumpWidget(hostApp());

    unawaited(Squawk.show());
    await tester.pumpAndSettle();

    expect(find.byKey(SquawkFeedbackForm.textKey), findsOneWidget);
    expect(find.byKey(SquawkFeedbackForm.emailKey), findsOneWidget);
    expect(find.byKey(SquawkFeedbackForm.submitKey), findsOneWidget);
    expect(find.text("What's wrong?"), findsOneWidget);
  });

  testWidgets('submitting from the custom form still produces a report',
      (tester) async {
    giveDeviceANavBar(tester);
    await tester.pumpWidget(hostApp());

    unawaited(Squawk.show());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(SquawkFeedbackForm.textKey),
      'the button is red',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('squawk_submit_button')));
    await tester.pump(const Duration(milliseconds: 300));
    await waitReal(
      tester,
      () => SquawkController.instance.lastReport.value != null,
    );
    await tester.pumpAndSettle();

    expect(SquawkController.instance.lastReport.value?.text,
        'the button is red');
  });
}

void unawaited(Future<void> future) {}
