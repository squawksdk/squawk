import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/src/capture/squawk_feedback_form.dart';

/// Pins a device-found bug: on iOS the keyboard could not be put away.
///
/// The description field is multiline, so its return key inserts a newline
/// and the iOS keyboard carries no Done key. With no system back gesture
/// either, a reporter who tapped that field was stuck with the keyboard up.
/// Android ran the same code and only escaped because of its back button,
/// which is why this never showed up there.
void main() {
  late TextEditingController text;
  late TextEditingController email;

  setUp(() {
    text = TextEditingController();
    email = TextEditingController();
  });

  tearDown(() {
    text.dispose();
    email.dispose();
  });

  /// The form as the sheet mounts it, with the keyboard's height reported
  /// through view insets exactly as the platform reports it.
  Widget host({required double keyboardHeight}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewInsets: EdgeInsets.only(bottom: keyboardHeight),
            ),
            child: SquawkFeedbackForm(
              onSubmit: () {},
              textController: text,
              emailController: email,
            ),
          ),
        ),
      ),
    );
  }

  // Assert on the keyboard itself rather than on focus. After unfocus() the
  // enclosing scope holds primary focus, so a focus check cannot tell the
  // two states apart — and "is the keyboard up" is the actual bug.
  bool keyboardShowing(WidgetTester tester) => tester.testTextInput.isVisible;

  /// Opacity of the nearest AnimatedOpacity above the Done button.
  double doneOpacity(WidgetTester tester) => tester
      .widgetList<AnimatedOpacity>(
        find.ancestor(
          of: find.byKey(SquawkFeedbackForm.dismissKeyboardKey),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .first
      .opacity;

  testWidgets('Done is invisible and inert while the keyboard is down',
      (tester) async {
    await tester.pumpWidget(host(keyboardHeight: 0));
    await tester.pumpAndSettle();

    expect(
      doneOpacity(tester),
      0,
      reason: 'a visible Done beside the title reads as a step in the flow',
    );
    expect(
      tester
          .widgetList<IgnorePointer>(
            find.ancestor(
              of: find.byKey(SquawkFeedbackForm.dismissKeyboardKey),
              matching: find.byType(IgnorePointer),
            ),
          )
          .any((widget) => widget.ignoring),
      isTrue,
      reason: 'an invisible control must not still be tappable',
    );
  });

  testWidgets('Done becomes visible when the keyboard comes up',
      (tester) async {
    await tester.pumpWidget(host(keyboardHeight: 320));
    await tester.pumpAndSettle();
    expect(doneOpacity(tester), 1);
  });

  // It used to leave the tree on the frame the keyboard finished closing,
  // which shrank the header row and jerked everything below it — a snap at
  // the end of an otherwise smooth slide. Staying put is what fixes that.
  testWidgets('the header keeps its height as the keyboard closes',
      (tester) async {
    await tester.pumpWidget(host(keyboardHeight: 320));
    await tester.pumpAndSettle();
    final withKeyboard = tester.getSize(
      find.ancestor(
        of: find.text('What went wrong?'),
        matching: find.byType(Row),
      ),
    );

    await tester.pumpWidget(host(keyboardHeight: 0));
    await tester.pumpAndSettle();
    final without = tester.getSize(
      find.ancestor(
        of: find.text('What went wrong?'),
        matching: find.byType(Row),
      ),
    );

    expect(without, withKeyboard);
  });

  testWidgets('Done releases focus, which is what closes the keyboard',
      (tester) async {
    await tester.pumpWidget(host(keyboardHeight: 320));
    await tester.tap(find.byKey(SquawkFeedbackForm.textKey));
    await tester.pump();
    expect(keyboardShowing(tester), isTrue);

    await tester.tap(find.byKey(SquawkFeedbackForm.dismissKeyboardKey));
    await tester.pump();
    expect(keyboardShowing(tester), isFalse);
  });

  testWidgets('tapping the form away from a field also releases focus',
      (tester) async {
    await tester.pumpWidget(host(keyboardHeight: 320));
    await tester.tap(find.byKey(SquawkFeedbackForm.textKey));
    await tester.pump();
    expect(keyboardShowing(tester), isTrue);

    // The disclaimer line at the bottom — inert text, and the largest piece
    // of the form a thumb can reach without hitting a control.
    await tester.tap(find.textContaining('Sends your notes'));
    await tester.pump();
    expect(keyboardShowing(tester), isFalse);
  });

  testWidgets('the description field still takes newlines', (tester) async {
    await tester.pumpWidget(host(keyboardHeight: 320));

    final field = tester.widget<TextField>(
      find.byKey(SquawkFeedbackForm.textKey),
    );
    expect(
      field.textInputAction,
      TextInputAction.newline,
      reason: 'switching this to done would fix the keyboard by breaking '
          'multi-line reports, which is the wrong trade',
    );
    expect(field.maxLines, greaterThan(1));
  });

  testWidgets('the send button is still reachable with the keyboard up',
      (tester) async {
    await tester.pumpWidget(host(keyboardHeight: 320));
    await tester.tap(find.byKey(SquawkFeedbackForm.textKey));
    await tester.pump();

    // Dismissing is only half of it: if Send were buried under the keyboard
    // the report could not be filed at all.
    expect(find.byKey(SquawkFeedbackForm.submitKey), findsOneWidget);
    await tester.tap(find.byKey(SquawkFeedbackForm.submitKey));
    await tester.pump();
  });
}
