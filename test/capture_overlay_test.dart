import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/capture/annotation_canvas.dart';
import 'package:squawk/src/capture/annotations.dart';
import 'package:squawk/src/capture/capture_overlay.dart';
import 'package:squawk/src/capture/squawk_feedback_form.dart';
import 'package:squawk/src/squawk_controller.dart';

import 'support/fakes.dart';

/// The capture screen's chrome, driven through the real widget stack.
///
/// Several of these pin device-found bugs from the `feedback` era: the submit
/// button under the Android navigation bar, and inputs that silently failed
/// to render in a height-starved sheet.
void main() {
  setUp(() => resetSquawk());

  Widget hostApp() => const Squawk(
        apiKey: 'sq_test_key',
        child: MaterialApp(
          home: Scaffold(body: Center(child: Text('host app'))),
        ),
      );

  Future<void> openCapture(WidgetTester tester) async {
    await tester.pumpWidget(hostApp());
    unawaited(SquawkController.instance.show());
    await tester.pumpAndSettle();
  }

  Future<void> draw(WidgetTester tester) async {
    await tester.drag(
      find.byType(AnnotationCanvas),
      const Offset(80, 40),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
  }

  AnnotationCanvas canvasOf(WidgetTester tester) =>
      tester.widget(find.byType(AnnotationCanvas));

  group('layout', () {
    // Reported from a Samsung A56 on Android 16 against the old sheet: the
    // submit button sat underneath the system navigation bar.
    testWidgets('the send button clears the system navigation bar',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.reset);

      await openCapture(tester);

      final button = tester.getRect(find.byKey(SquawkFeedbackForm.submitKey));
      expect(
        button.bottom,
        lessThanOrEqualTo(tester.view.physicalSize.height - 48),
        reason: 'the button must sit above the navigation bar, not under it',
      );
    });

    // The old sheet was a fixed fraction of the screen and could starve its
    // own inputs of height. The new layout must always show all of them.
    testWidgets('the form says what a report includes', (tester) async {
      await openCapture(tester);

      expect(
        find.textContaining('screenshot, device info'),
        findsOneWidget,
        reason: 'the reporter must know what travels with their words',
      );
    });

    testWidgets('every input is visible on a phone-sized screen',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await openCapture(tester);

      expect(find.byKey(SquawkFeedbackForm.textKey), findsOneWidget);
      expect(find.byKey(SquawkFeedbackForm.emailKey), findsOneWidget);
      expect(find.byKey(SquawkFeedbackForm.submitKey), findsOneWidget);
      expect(find.byType(AnnotationCanvas), findsOneWidget);
    });

    // Three tools, four colors and undo have to coexist with the close
    // button on the narrowest phones without clipping or overflow stripes.
    testWidgets('the toolbar fits a narrow phone', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.reset);

      await openCapture(tester);

      expect(find.byKey(CaptureOverlay.closeButtonKey), findsOneWidget);
      expect(find.byKey(CaptureOverlay.textToolKey), findsOneWidget);
      expect(find.byKey(CaptureOverlay.undoButtonKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the keyboard pushes the form up, not over it',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      await openCapture(tester);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();

      final button = tester.getRect(find.byKey(SquawkFeedbackForm.submitKey));
      expect(
        button.bottom,
        lessThanOrEqualTo(tester.view.physicalSize.height - 300),
        reason: 'the send button must stay above the keyboard',
      );
      addTearDown(tester.view.reset);
    });
  });

  group('drawing tools', () {
    testWidgets('the hint stands down after the first stroke', (tester) async {
      await openCapture(tester);

      final hint = find.text(
        'Draw on the screenshot to point at the problem',
      );
      expect(hint, findsOneWidget);
      double hintOpacity() => tester
          .widget<AnimatedOpacity>(
            find.ancestor(of: hint, matching: find.byType(AnimatedOpacity)),
          )
          .opacity;
      expect(hintOpacity(), 1);

      await draw(tester);

      expect(hintOpacity(), 0);
    });

    testWidgets('undo wakes with the first stroke and removes it',
        (tester) async {
      await openCapture(tester);
      final undo = find.byKey(CaptureOverlay.undoButtonKey);

      expect(tester.widget<IconButton>(undo).onPressed, isNull);

      await draw(tester);
      expect(canvasOf(tester).controller.hasAnnotations, isTrue);
      expect(tester.widget<IconButton>(undo).onPressed, isNotNull);

      await tester.tap(undo);
      await tester.pumpAndSettle();

      expect(canvasOf(tester).controller.hasAnnotations, isFalse);
      expect(tester.widget<IconButton>(undo).onPressed, isNull);
    });

    testWidgets('the pen is the tool in hand until the arrow is chosen',
        (tester) async {
      await openCapture(tester);
      final controller = canvasOf(tester).controller;
      expect(controller.tool, AnnotationTool.pen);

      await tester.tap(find.byKey(CaptureOverlay.arrowToolKey));
      await tester.pumpAndSettle();
      expect(controller.tool, AnnotationTool.arrow);

      await draw(tester);
      expect(controller.annotations.single, isA<ArrowAnnotation>(),
          reason: 'a drag in arrow mode must produce an arrow');

      await tester.tap(find.byKey(CaptureOverlay.penToolKey));
      await tester.pumpAndSettle();
      await draw(tester);
      expect(controller.annotations.last, isA<StrokeAnnotation>());
    });

    testWidgets('a tap with the text tool writes a note onto the shot',
        (tester) async {
      await openCapture(tester);
      await tester.tap(find.byKey(CaptureOverlay.textToolKey));
      await tester.pumpAndSettle();

      expect(find.text('Tap the screenshot to add a note'), findsOneWidget,
          reason: 'the hint follows the tool in hand');

      await tester.tap(find.byType(AnnotationCanvas), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Add a note'), findsOneWidget);

      await tester.enterText(
        find.byKey(CaptureOverlay.labelInputKey),
        'wrong price here',
      );
      await tester.tap(find.byKey(CaptureOverlay.labelSaveKey));
      await tester.pumpAndSettle();

      final label =
          canvasOf(tester).controller.annotations.single as TextAnnotation;
      expect(label.text, 'wrong price here');
      expect(find.byKey(CaptureOverlay.labelInputKey), findsNothing);
    });

    testWidgets('cancelling the note editor leaves nothing behind',
        (tester) async {
      await openCapture(tester);
      await tester.tap(find.byKey(CaptureOverlay.textToolKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AnnotationCanvas), warnIfMissed: false);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(CaptureOverlay.labelInputKey),
        'never mind',
      );
      await tester.tap(find.byKey(CaptureOverlay.labelCancelKey));
      await tester.pumpAndSettle();

      expect(canvasOf(tester).controller.hasAnnotations, isFalse);
    });

    testWidgets('saving an empty note adds nothing', (tester) async {
      await openCapture(tester);
      await tester.tap(find.byKey(CaptureOverlay.textToolKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AnnotationCanvas), warnIfMissed: false);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(CaptureOverlay.labelSaveKey));
      await tester.pumpAndSettle();

      expect(canvasOf(tester).controller.hasAnnotations, isFalse);
      expect(find.byKey(CaptureOverlay.labelInputKey), findsNothing,
          reason: 'the editor closes rather than nagging');
    });

    testWidgets('tapping an existing note reopens it for editing',
        (tester) async {
      await openCapture(tester);
      await tester.tap(find.byKey(CaptureOverlay.textToolKey));
      await tester.pumpAndSettle();

      final canvasCenter =
          tester.getCenter(find.byType(AnnotationCanvas));
      await tester.tapAt(canvasCenter);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(CaptureOverlay.labelInputKey),
        'first draft',
      );
      await tester.tap(find.byKey(CaptureOverlay.labelSaveKey));
      await tester.pumpAndSettle();

      await tester.tapAt(canvasCenter);
      await tester.pumpAndSettle();

      expect(find.text('Edit note'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(CaptureOverlay.labelInputKey))
            .controller!
            .text,
        'first draft',
        reason: 'editing starts from the words already there',
      );

      await tester.tap(find.byKey(CaptureOverlay.labelDeleteKey));
      await tester.pumpAndSettle();

      expect(canvasOf(tester).controller.hasAnnotations, isFalse);
    });

    testWidgets('the move tool drags a drawing somewhere else',
        (tester) async {
      await openCapture(tester);
      final controller = canvasOf(tester).controller;

      // An arrow to move, drawn through the real gesture path.
      await tester.tap(find.byKey(CaptureOverlay.arrowToolKey));
      await tester.pumpAndSettle();
      final canvasCenter = tester.getCenter(find.byType(AnnotationCanvas));
      await tester.timedDragFrom(
        canvasCenter - const Offset(60, 0),
        const Offset(120, 0),
        const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();
      final arrow = controller.annotations.single as ArrowAnnotation;
      final startBefore = arrow.start;

      await tester.tap(find.byKey(CaptureOverlay.moveToolKey));
      await tester.pumpAndSettle();
      await tester.timedDragFrom(
        canvasCenter,
        const Offset(0, 80),
        const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();

      expect(arrow.start.dx, startBefore.dx);
      expect(arrow.start.dy, greaterThan(startBefore.dy),
          reason: 'the drag must have carried the arrow downward');
      expect(controller.annotations, hasLength(1),
          reason: 'moving must not draw anything new');
    });

    testWidgets('in move mode a tap selects and an empty tap clears',
        (tester) async {
      await openCapture(tester);
      final controller = canvasOf(tester).controller;

      await tester.tap(find.byKey(CaptureOverlay.arrowToolKey));
      await tester.pumpAndSettle();
      final canvasCenter = tester.getCenter(find.byType(AnnotationCanvas));
      await tester.timedDragFrom(
        canvasCenter - const Offset(60, 0),
        const Offset(120, 0),
        const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(CaptureOverlay.moveToolKey));
      await tester.pumpAndSettle();
      await tester.tapAt(canvasCenter);
      await tester.pumpAndSettle();
      expect(controller.selected, same(controller.annotations.single));

      final canvasRect = tester.getRect(find.byType(AnnotationCanvas));
      await tester.tapAt(canvasRect.topLeft + const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(controller.selected, isNull);
    });

    testWidgets('tapping a color dot changes the marker', (tester) async {
      await openCapture(tester);
      final controller = canvasOf(tester).controller;
      expect(controller.color, annotationColors.first);

      await tester.tap(find.bySemanticsLabel('Green marker'));
      await tester.pumpAndSettle();

      expect(controller.color, annotationColors[2]);
    });
  });

  group('closing', () {
    testWidgets('with nothing entered, close closes at once', (tester) async {
      await openCapture(tester);

      await tester.tap(find.byKey(CaptureOverlay.closeButtonKey));
      await tester.pumpAndSettle();

      expect(find.byType(CaptureOverlay), findsNothing);
    });

    testWidgets('with work on screen, close asks first', (tester) async {
      await openCapture(tester);
      await draw(tester);

      await tester.tap(find.byKey(CaptureOverlay.closeButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('Discard this report?'), findsOneWidget);

      await tester.tap(find.byKey(CaptureOverlay.keepEditingButtonKey));
      await tester.pumpAndSettle();
      expect(find.byType(CaptureOverlay), findsOneWidget,
          reason: 'keep editing keeps the capture open');

      await tester.tap(find.byKey(CaptureOverlay.closeButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CaptureOverlay.discardButtonKey));
      await tester.pumpAndSettle();

      expect(find.byType(CaptureOverlay), findsNothing);
    });

    testWidgets('typed text alone is enough to warrant asking',
        (tester) async {
      await openCapture(tester);
      await tester.enterText(
        find.byKey(SquawkFeedbackForm.textKey),
        'almost done writing this up',
      );

      await tester.tap(find.byKey(CaptureOverlay.closeButtonKey));
      await tester.pumpAndSettle();

      expect(find.text('Discard this report?'), findsOneWidget);
    });

    testWidgets('the Android back button closes the capture', (tester) async {
      await openCapture(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(CaptureOverlay), findsNothing);
      expect(find.text('host app'), findsOneWidget,
          reason: 'back must close the capture, not the app or a host route');
    });
  });

  testWidgets('a remembered address is offered, but typing wins',
      (tester) async {
    SquawkController.instance.emailStore =
        InMemoryEmailStore(initial: 'jo@client.com');

    await openCapture(tester);
    await tester.pumpAndSettle();

    final email = tester.widget<TextField>(
      find.byKey(SquawkFeedbackForm.emailKey),
    );
    expect(email.controller!.text, 'jo@client.com');
  });
}
