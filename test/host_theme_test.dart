import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/squawk.dart';
import 'package:squawk/src/capture/capture_overlay.dart';
import 'package:squawk/src/capture/sent_confirmation.dart';
import 'package:squawk/src/capture/squawk_feedback_form.dart';
import 'package:squawk/src/feedback_button.dart';
import 'package:squawk/src/squawk_controller.dart';

import 'support/fakes.dart';

/// SQUAW-31: Squawk renders above the host's MaterialApp, so it cannot read
/// their theme and has to be handed one.
void main() {
  setUp(() => resetSquawk());
  tearDown(
    () => TestWidgetsFlutterBinding
        .instance.platformDispatcher
        .clearPlatformBrightnessTestValue(),
  );

  final brandDark = ThemeData.dark().copyWith(
    colorScheme: const ColorScheme.dark(primary: Color(0xFF00E5FF)),
  );
  final brandLight = ThemeData(colorSchemeSeed: Colors.teal);

  Widget app({SquawkOptions options = const SquawkOptions()}) => Squawk(
        apiKey: 'k',
        options: options,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: Text('host app'))),
        ),
      );

  Future<void> openSheet(WidgetTester tester) async {
    unawaited(SquawkController.instance.show());
    await tester.pumpAndSettle();
  }

  ThemeData sheetTheme(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(CaptureOverlay)));

  void setDevice(Brightness brightness) => TestWidgetsFlutterBinding
      .instance
      .platformDispatcher
      .platformBrightnessTestValue = brightness;

  group('the sheet', () {
    // The original bug: an app pinned to ThemeMode.dark, on a phone in light
    // mode, got a light sheet.
    testWidgets('a lone theme beats the device brightness', (tester) async {
      setDevice(Brightness.light);
      await tester.pumpWidget(app(options: SquawkOptions(theme: brandDark)));
      await openSheet(tester);

      expect(sheetTheme(tester).brightness, Brightness.dark);
    });

    testWidgets('follows the device when both are given', (tester) async {
      setDevice(Brightness.dark);
      await tester.pumpWidget(
        app(options: SquawkOptions(theme: brandLight, darkTheme: brandDark)),
      );
      await openSheet(tester);

      expect(
        sheetTheme(tester).colorScheme.primary,
        const Color(0xFF00E5FF),
      );
    });

    testWidgets('falls back to the device when nothing is given',
        (tester) async {
      setDevice(Brightness.dark);
      await tester.pumpWidget(app());
      await openSheet(tester);

      expect(sheetTheme(tester).brightness, Brightness.dark);
    });

    testWidgets('the fallback follows the device switching mid-capture',
        (tester) async {
      setDevice(Brightness.light);
      await tester.pumpWidget(app());
      await openSheet(tester);
      expect(sheetTheme(tester).brightness, Brightness.light);

      setDevice(Brightness.dark);
      await tester.pump();

      expect(sheetTheme(tester).brightness, Brightness.dark);
    });

    testWidgets('restyles when the theme changes mid-capture', (tester) async {
      setDevice(Brightness.light);
      await tester.pumpWidget(app(options: SquawkOptions(theme: brandLight)));
      await openSheet(tester);
      expect(sheetTheme(tester).brightness, Brightness.light);

      await tester.pumpWidget(app(options: SquawkOptions(theme: brandDark)));
      await tester.pump();

      expect(sheetTheme(tester).brightness, Brightness.dark);
    });

    // The live app is still painting beneath the overlay. A translucent
    // backdrop would let it show through beside the frozen screenshot.
    testWidgets('keeps an opaque backdrop under a see-through theme',
        (tester) async {
      await tester.pumpWidget(
        app(
          options: SquawkOptions(
            theme: ThemeData(scaffoldBackgroundColor: Colors.transparent),
          ),
        ),
      );
      await openSheet(tester);

      final backdrop = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(CaptureOverlay),
              matching: find.byType(Material),
            )
            .first,
      );

      expect(backdrop.color!.a, 1.0);
    });

    testWidgets('accepts a Material 2 theme', (tester) async {
      await tester.pumpWidget(
        app(
          options: SquawkOptions(
            theme: ThemeData(useMaterial3: false, primarySwatch: Colors.pink),
          ),
        ),
      );
      await openSheet(tester);

      expect(tester.takeException(), isNull);
      expect(sheetTheme(tester).useMaterial3, isFalse);
    });
  });

  group('the two steps', () {
    Color buttonColor(WidgetTester tester, Key key) =>
        tester
            .widget<Material>(
              find.descendant(
                of: find.byKey(key),
                matching: find.byType(Material),
              ),
            )
            .color!;

    Material sheet(WidgetTester tester) => tester.widget<Material>(
      find
          .ancestor(
            of: find.byType(SquawkFeedbackForm),
            matching: find.byType(Material),
          )
          .first,
    );

    testWidgets('Next, the sheet and Send take the given theme', (
      tester,
    ) async {
      setDevice(Brightness.dark);
      await tester.pumpWidget(app(options: SquawkOptions(theme: brandLight)));
      await openSheet(tester);

      expect(
        buttonColor(tester, CaptureOverlay.nextButtonKey),
        brandLight.colorScheme.secondaryContainer,
      );

      await openDetails(tester);

      expect(sheet(tester).color, brandLight.colorScheme.surface);
      expect(
        buttonColor(tester, SquawkFeedbackForm.submitKey),
        brandLight.colorScheme.primary,
      );
    });

    testWidgets('the open sheet restyles when the theme changes', (
      tester,
    ) async {
      setDevice(Brightness.light);
      await tester.pumpWidget(app(options: SquawkOptions(theme: brandLight)));
      await openSheet(tester);
      await openDetails(tester);

      await tester.pumpWidget(app(options: SquawkOptions(theme: brandDark)));
      await tester.pump();

      expect(sheet(tester).color, brandDark.colorScheme.surface);
      expect(find.byKey(SquawkFeedbackForm.textKey), findsOneWidget);
    });

    testWidgets('both steps work under a Material 2 theme', (tester) async {
      await tester.pumpWidget(
        app(
          options: SquawkOptions(
            theme: ThemeData(useMaterial3: false, primarySwatch: Colors.pink),
          ),
        ),
      );
      await openSheet(tester);
      await openDetails(tester);
      expect(find.byKey(SquawkFeedbackForm.textKey), findsOneWidget);

      await tester.fling(
        find.byKey(CaptureOverlay.sheetHandleKey),
        const Offset(0, 80),
        800,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(SquawkFeedbackForm.textKey), findsNothing);
      expect(find.byKey(CaptureOverlay.nextButtonKey), findsOneWidget);
    });
  });

  group('the floating button', () {
    testWidgets('takes the given theme', (tester) async {
      await tester.pumpWidget(
        app(
          options: SquawkOptions(feedbackButton: true, theme: brandDark),
        ),
      );

      final theme = Theme.of(tester.element(find.byKey(FeedbackButton.buttonKey)));
      expect(theme.colorScheme.primary, const Color(0xFF00E5FF));
    });

    // Squawk's theme is for Squawk's chrome. Wrapping the child would hand
    // the host app our Theme and MediaQuery in place of its own.
    testWidgets('leaves the host app on its own theme', (tester) async {
      await tester.pumpWidget(
        Squawk(
          apiKey: 'k',
          options: SquawkOptions(feedbackButton: true, theme: brandDark),
          child: MaterialApp(
            theme: brandLight,
            home: const Scaffold(body: Center(child: Text('host app'))),
          ),
        ),
      );

      final host = Theme.of(tester.element(find.text('host app')));
      expect(host.brightness, Brightness.light);
    });
  });

  group('the sent note', () {
    testWidgets('takes its colours from the given theme', (tester) async {
      await tester.pumpWidget(SentConfirmation(theme: brandDark));
      await tester.pump();

      final chip = tester.widget<Container>(
        find.byKey(SentConfirmation.noteKey),
      );
      final decoration = chip.decoration! as BoxDecoration;

      expect(
        decoration.color,
        brandDark.colorScheme.inverseSurface.withValues(alpha: 0.9),
      );
    });
  });
}
