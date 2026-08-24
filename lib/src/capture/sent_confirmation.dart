import 'package:flutter/material.dart';

import 'squawk_theme.dart';

/// The brief "it worked" the reporter sees after sending.
///
/// Worded for how delivery actually works: the report is spooled and
/// uploaded with retries, so "on its way" is true even offline — where
/// "sent" would be a lie the reporter might catch.
///
/// Lives above the host app's MaterialApp, so like the floating button it
/// brings everything it needs and inherits nothing.
class SentConfirmation extends StatelessWidget {
  const SentConfirmation({super.key, this.theme, this.darkTheme});

  /// See `SquawkOptions.theme`.
  final ThemeData? theme;

  /// See `SquawkOptions.darkTheme`.
  final ThemeData? darkTheme;

  /// How long the note stays up — long enough to read twice, short enough
  /// to never be in the way.
  static const Duration visibleFor = Duration(milliseconds: 2800);

  static const Key noteKey = Key('squawk_sent_note');

  @override
  Widget build(BuildContext context) {
    return SquawkTheme(
      theme: theme,
      darkTheme: darkTheme,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final colors = theme.colorScheme;

          return Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: 32 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    key: noteKey,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      // The snackbar roles: a chip that contrasts with the
                      // app rather than blending into it.
                      color: colors.inverseSurface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: colors.inversePrimary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Thanks! Your report is on its way.',
                          // No Material ancestor here, so the ambient text
                          // style is the debug one with the yellow underline.
                          // Colour and decoration have to be stated.
                          style:
                              (theme.textTheme.bodyMedium ?? const TextStyle())
                                  .copyWith(
                            color: colors.onInverseSurface,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
