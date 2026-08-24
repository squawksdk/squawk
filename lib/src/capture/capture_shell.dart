import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'squawk_theme.dart';

/// The environment Squawk's capture UI needs to exist.
///
/// The capture overlay sits *above* the host app's `MaterialApp`, so nothing
/// ordinary widgets rely on — MediaQuery, Directionality, Localizations,
/// Theme, an Overlay for text-selection handles — exists yet. This provides
/// all of it: the theme from [SquawkTheme], everything else from scratch.
class CaptureShell extends StatefulWidget {
  const CaptureShell({
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
  State<CaptureShell> createState() => _CaptureShellState();
}

class _CaptureShellState extends State<CaptureShell> {
  /// Owned by the state: an Overlay only reads `initialEntries` once, so the
  /// entry has to be told when the child it builds has changed.
  late final OverlayEntry _entry =
      OverlayEntry(builder: (_) => widget.child);

  @override
  void didUpdateWidget(CaptureShell old) {
    super.didUpdateWidget(old);
    if (old.child != widget.child) _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    // After the frame, because the Overlay below is unmounting in this same
    // teardown: remove() detaches from it safely once it is gone, and only a
    // detached entry may be disposed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entry
        ..remove()
        ..dispose();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SquawkTheme(
      theme: widget.theme,
      darkTheme: widget.darkTheme,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Localizations(
          locale: const Locale('en'),
          delegates: const [
            DefaultWidgetsLocalizations.delegate,
            DefaultMaterialLocalizations.delegate,
            DefaultCupertinoLocalizations.delegate,
          ],
          // Text editing wants hardware-keyboard shortcuts and an Overlay
          // for the selection toolbar; WidgetsApp normally provides both.
          child: DefaultTextEditingShortcuts(
            child: Overlay(initialEntries: [_entry]),
          ),
        ),
      ),
    );
  }
}
