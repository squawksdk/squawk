import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/capture/annotation_canvas.dart';
import 'package:squawk/src/capture/annotations.dart';
import 'package:squawk/src/capture/capture_overlay.dart';
import 'package:squawk/src/capture/squawk_feedback_form.dart';
import 'package:squawk/src/squawk_controller.dart';

import 'support/fakes.dart';

/// The owned capture stack, end to end: shake to submitted report, through
/// the real screenshot, the real overlay and the real composite.
void main() {
  setUp(() {
    resetSquawk();
  });

  Widget hostApp() => const Squawk(
        apiKey: 'sq_test_key',
        child: MaterialApp(
          home: Scaffold(body: Center(child: Text('host app'))),
        ),
      );

  testWidgets('show() opens the capture screen over the host app',
      (tester) async {
    await tester.pumpWidget(hostApp());
    expect(find.text('Send report'), findsNothing);

    unawaited(SquawkController.instance.show());
    await tester.pumpAndSettle();

    expect(find.text('What went wrong?'), findsOneWidget);
    expect(find.text('Send report'), findsOneWidget);
  });

  // The device-found bug that started SQUAW-27's predecessor: the old sheet
  // opened once and never again, because dismissal never completed the
  // capture and the re-entrancy guard swallowed every later shake.
  testWidgets('dismissing completes the capture and re-arms the trigger',
      (tester) async {
    await tester.pumpWidget(hostApp());

    var completed = false;
    SquawkReport? report;
    SquawkController.instance.show().then((r) {
      report = r;
      completed = true;
    });
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(CaptureOverlay.closeButtonKey));
    await tester.pumpAndSettle();

    expect(completed, isTrue, reason: 'the capture must not hang on dismiss');
    expect(report, isNull);
    expect(SquawkController.instance.isCapturing.value, isFalse);

    unawaited(SquawkController.instance.show());
    await tester.pumpAndSettle();
    expect(find.text('Send report'), findsOneWidget,
        reason: 'the trigger has to work a second time');
  });

  testWidgets('submitting returns a report with real screenshot bytes',
      (tester) async {
    await tester.pumpWidget(hostApp());

    SquawkReport? report;
    unawaited(SquawkController.instance.show().then((r) => report = r));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(SquawkFeedbackForm.textKey),
      'the button is red',
    );
    await tester.enterText(
      find.byKey(SquawkFeedbackForm.emailKey),
      '  Jo@Client.com ',
    );
    await tester.tap(find.byKey(SquawkFeedbackForm.submitKey));

    // The composite renders through the engine, which answers on the real
    // clock, not the test's fake one.
    await waitReal(tester, () => report != null);
    await tester.pumpAndSettle();

    expect(report!.text, 'the button is red');
    expect(report!.reporterEmail, 'Jo@Client.com',
        reason: 'trimmed by normalisation');
    // PNG magic number — real encoded image bytes, not a placeholder.
    expect(report!.screenshot.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(find.byType(CaptureOverlay), findsNothing);
  });

  testWidgets('a drawn stroke is burned into the submitted screenshot',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(hostApp());

    SquawkReport? report;
    unawaited(SquawkController.instance.show().then((r) => report = r));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byType(AnnotationCanvas),
      const Offset(120, 0),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnnotationCanvas>(find.byType(AnnotationCanvas))
          .controller
          .hasAnnotations,
      isTrue,
      reason: 'the drag must have produced a stroke',
    );

    await tester.tap(find.byKey(SquawkFeedbackForm.submitKey));
    await waitReal(tester, () => report != null);
    await tester.pumpAndSettle();

    expect(
      await _containsColor(tester, report!.screenshot, annotationColors.first),
      isTrue,
      reason: 'the marker color must appear in the uploaded PNG',
    );
  });

  testWidgets('an empty comment travels as null, not an empty string',
      (tester) async {
    await tester.pumpWidget(hostApp());

    SquawkReport? report;
    unawaited(SquawkController.instance.show().then((r) => report = r));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(SquawkFeedbackForm.submitKey));
    await waitReal(tester, () => report != null);
    await tester.pumpAndSettle();

    expect(report!.text, isNull);
  });

  testWidgets('unmounting the host mid-capture completes with null',
      (tester) async {
    await tester.pumpWidget(hostApp());

    SquawkReport? report;
    var completed = false;
    SquawkController.instance.show().then((r) {
      report = r;
      completed = true;
    });
    await tester.pumpAndSettle();
    expect(find.byType(CaptureOverlay), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(completed, isTrue, reason: 'the caller must not hang');
    expect(report, isNull);
  });
}

/// Whether any pixel in [png] is exactly [color].
Future<bool> _containsColor(
  WidgetTester tester,
  Uint8List png,
  Color color,
) async {
  return tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    final data =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final bytes = data.buffer.asUint8List();
    image.dispose();

    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    for (var i = 0; i < bytes.length; i += 4) {
      if (bytes[i] == r && bytes[i + 1] == g && bytes[i + 2] == b) {
        return true;
      }
    }
    return false;
  }).then((found) => found!);
}
