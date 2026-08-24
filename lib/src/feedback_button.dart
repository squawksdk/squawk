import 'package:flutter/material.dart';

import 'capture/squawk_theme.dart';
import 'squawk_controller.dart';

/// A small floating button that opens the report sheet.
///
/// Opt-in via `SquawkOptions(feedbackButton: true)`, because it covers part
/// of the host app's UI.
///
/// It hides itself while a capture is on screen. The button sits inside the
/// capture boundary, so leaving it visible would put a Squawk button in the
/// reporter's own screenshot.
class FeedbackButton extends StatelessWidget {
  const FeedbackButton({
    super.key,
    this.theme,
    this.darkTheme,
    required this.child,
  });

  /// Identifies the button in tests and in host-app integration tests.
  static const Key buttonKey = Key('squawk_feedback_button');

  /// See `SquawkOptions.theme`.
  final ThemeData? theme;

  /// See `SquawkOptions.darkTheme`.
  final ThemeData? darkTheme;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // This widget sits above the host app's MaterialApp, so there is no
    // Directionality, MediaQuery or Theme to inherit — everything the button
    // needs has to be supplied here, and degrade gracefully when absent.
    //
    // SquawkTheme wraps the button alone: wrapping `child` would hand the
    // host app our MediaQuery and Theme in place of its own.
    return Directionality(
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      child: Stack(
        children: [
          child,
          // Align rather than Positioned: a Positioned given only right and
          // bottom passes unbounded constraints down, and the button lays
          // itself out at 100000px.
          Align(
            alignment: Alignment.bottomRight,
            child: SquawkTheme(
              theme: theme,
              darkTheme: darkTheme,
              child: ValueListenableBuilder<bool>(
                valueListenable: SquawkController.instance.isCapturing,
                builder: (context, isCapturing, _) {
                  if (isCapturing) return const SizedBox.shrink();

                  return Padding(
                    padding: EdgeInsets.only(
                      right: 16,
                      // Clear the home indicator. SquawkTheme guarantees the
                      // MediaQuery this reads.
                      bottom: 16 + MediaQuery.paddingOf(context).bottom,
                    ),
                    // Semantics rather than the FAB's tooltip: Tooltip needs an
                    // Overlay ancestor, and this button lives above the host
                    // app's MaterialApp where none exists.
                    child: Semantics(
                      label: 'Report a problem',
                      button: true,
                      child: FloatingActionButton.small(
                        key: FeedbackButton.buttonKey,
                        heroTag: 'squawk_report_button',
                        onPressed: () => SquawkController.instance.show(),
                        child: const Icon(Icons.bug_report_outlined),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
