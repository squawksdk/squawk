import 'package:flutter/material.dart';

/// Picks the theme Squawk's own UI should use.
///
/// Squawk's chrome sits above the host app's `MaterialApp`, so there is no
/// ancestor `Theme` to read and the host has to hand one over instead.
///
/// One theme on its own is used at both brightnesses. That is how an app
/// pinned to a single `themeMode` says which one it is, and it is the case
/// this option exists for: platform brightness alone gets that app wrong.
ThemeData resolveSquawkTheme({
  required ThemeData? theme,
  required ThemeData? darkTheme,
  required Brightness platformBrightness,
}) {
  final dark = platformBrightness == Brightness.dark;

  if (theme != null && darkTheme != null) return dark ? darkTheme : theme;

  final only = theme ?? darkTheme;
  if (only != null) return only;

  return dark ? ThemeData.dark() : ThemeData.light();
}

/// Supplies the theme and the metrics Squawk's own chrome needs above the
/// host app.
///
/// Wrap only Squawk's own widgets in this. The host app keeps its own
/// `MediaQuery` and `Theme`; wrapping its subtree here would replace both
/// for the entire application.
class SquawkTheme extends StatelessWidget {
  const SquawkTheme({
    super.key,
    required this.theme,
    required this.darkTheme,
    required this.child,
  });

  /// See `SquawkOptions.theme`.
  final ThemeData? theme;

  /// See `SquawkOptions.darkTheme`.
  final ThemeData? darkTheme;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // MediaQuery.fromView rather than reading platformBrightness off the view
    // directly: only the MediaQuery registers a dependency, so the device
    // switching to dark mid-capture actually rebuilds.
    return MediaQuery.fromView(
      view: View.of(context),
      child: Builder(
        builder: (context) => Theme(
          data: resolveSquawkTheme(
            theme: theme,
            darkTheme: darkTheme,
            platformBrightness: MediaQuery.platformBrightnessOf(context),
          ),
          child: child,
        ),
      ),
    );
  }
}
