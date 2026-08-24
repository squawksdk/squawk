import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/capture/annotation_canvas.dart';
import 'package:squawk/src/capture/squawk_feedback_form.dart';
import 'package:squawk/src/squawk_controller.dart';

import 'support/fakes.dart';

/// SQUAW-32: the capture screen is a Column of a top bar, an Expanded
/// screenshot, a tool strip and the form. Everything but the screenshot is
/// content-sized, so a viewport too short for that chrome leaves the
/// Expanded no height and overflows the Column — a send button the reporter
/// cannot reach.
///
/// The sizes below are logical pixels at a device pixel ratio of 1.
void main() {
  setUp(() => resetSquawk());

  Widget hostApp({required bool askReporterEmail}) => Squawk(
        apiKey: 'k',
        options: SquawkOptions(askReporterEmail: askReporterEmail),
        child: const MaterialApp(
          home: Scaffold(body: Center(child: Text('host app'))),
        ),
      );

  Future<void> openAt(
    WidgetTester tester,
    Size size, {
    required bool askReporterEmail,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(hostApp(askReporterEmail: askReporterEmail));
    unawaited(SquawkController.instance.show());
    await tester.pumpAndSettle();
  }

  /// Every screen size has to leave the reporter able to describe the bug and
  /// send it. Anything else on screen is negotiable; these are not.
  ///
  /// On a landscape phone the form is taller than the screen, so the send
  /// button is below the fold and has to be scrolled to. That is allowed —
  /// what is not allowed is a button that cannot be reached at all.
  Future<void> expectUsable(
    WidgetTester tester,
    Size size, {
    required bool email,
  }) async {
    expect(tester.takeException(), isNull, reason: 'nothing may overflow');

    expect(find.byKey(SquawkFeedbackForm.textKey), findsOneWidget);
    expect(find.byKey(SquawkFeedbackForm.submitKey), findsOneWidget);
    expect(
      find.byKey(SquawkFeedbackForm.emailKey),
      email ? findsOneWidget : findsNothing,
    );
    expect(
      find.byType(AnnotationCanvas),
      findsOneWidget,
      reason: 'the screenshot must not be squeezed out entirely',
    );

    await tester.ensureVisible(find.byKey(SquawkFeedbackForm.submitKey));
    await tester.pumpAndSettle();

    final button = tester.getRect(find.byKey(SquawkFeedbackForm.submitKey));
    expect(
      button.bottom,
      lessThanOrEqualTo(size.height),
      reason: 'the send button must be reachable, scrolled to if need be',
    );
    expect(button.top, greaterThanOrEqualTo(0));
    expect(button.height, greaterThan(0));
  }

  const sizes = <String, Size>{
    'small phone portrait': Size(320, 568),
    'small phone landscape': Size(568, 320),
    'narrow phone portrait': Size(360, 640),
    'narrow phone landscape': Size(640, 360),
    'large phone portrait': Size(430, 932),
    'large phone landscape': Size(932, 430),
    'tablet portrait': Size(834, 1194),
    'tablet landscape': Size(1194, 834),
  };

  for (final entry in sizes.entries) {
    for (final email in [true, false]) {
      final label = email ? 'with the email field' : 'without the email field';

      testWidgets('${entry.key}, $label', (tester) async {
        await openAt(tester, entry.value, askReporterEmail: email);
        await expectUsable(tester, entry.value, email: email);
      });
    }
  }
}
