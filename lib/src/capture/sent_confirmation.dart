import 'package:flutter/material.dart';

/// The brief "it worked" the reporter sees after sending.
///
/// Worded for how delivery actually works: the report is spooled and
/// uploaded with retries, so "on its way" is true even offline — where
/// "sent" would be a lie the reporter might catch.
///
/// Lives above the host app's MaterialApp, so like the floating button it
/// brings everything it needs and inherits nothing.
class SentConfirmation extends StatelessWidget {
  const SentConfirmation({super.key});

  /// How long the note stays up — long enough to read twice, short enough
  /// to never be in the way.
  static const Duration visibleFor = Duration(milliseconds: 2800);

  static const Key noteKey = Key('squawk_sent_note');

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    final bottomInset = view.padding.bottom / view.devicePixelRatio;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: 32 + bottomInset),
          child: Semantics(
            liveRegion: true,
            child: Container(
              key: noteKey,
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: const Color(0xE6323232),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF81C784),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Thanks! Your report is on its way.',
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 14,
                      decoration: TextDecoration.none,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
