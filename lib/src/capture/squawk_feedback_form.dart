import 'package:flutter/material.dart';

/// The form under the screenshot: comment, optional email, send.
///
/// Pure UI. The overlay owns the text controllers — it needs them to know
/// whether closing would discard something the reporter typed — and receives
/// the submit signal; this widget holds no report state of its own.
class SquawkFeedbackForm extends StatelessWidget {
  const SquawkFeedbackForm({
    super.key,
    required this.onSubmit,
    required this.textController,
    required this.emailController,
    this.askReporterEmail = true,
    this.busy = false,
  });

  /// Called once when the reporter sends. The values live in the controllers.
  final VoidCallback onSubmit;

  final TextEditingController textController;
  final TextEditingController emailController;

  /// Whether to ask the reporter for an address.
  final bool askReporterEmail;

  /// True while the report is being put together after the tap, so the send
  /// button cannot be tapped twice.
  final bool busy;

  static const Key textKey = Key('squawk_text_input');
  static const Key submitKey = Key('squawk_submit_button');
  static const Key emailKey = Key('squawk_email_input');

  /// One decoration for every field, so the sheet reads as a single form
  /// rather than a stack of unrelated inputs.
  ///
  /// Hints rather than floating labels: a label animating out of the field on
  /// focus shifts everything below it, which is jarring in a sheet already
  /// being resized by the keyboard.
  InputDecoration _fieldDecoration(
    ThemeData theme,
    String hint, {
    IconData? icon,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
    );

    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.4,
      ),
      prefixIcon: icon == null ? null : Icon(icon, size: 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        // Clears the system navigation bar and the home indicator. Goes to
        // zero on its own when the keyboard covers them.
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What went wrong?',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            key: textKey,
            style: theme.textTheme.bodyMedium,
            controller: textController,
            // Grows with what the reporter writes instead of being pinned at
            // two lines, and shrinks back when the keyboard takes the room.
            minLines: 2,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
            keyboardType: TextInputType.multiline,
            decoration: _fieldDecoration(theme, 'Describe what happened'),
          ),
          if (askReporterEmail) ...[
            const SizedBox(height: 12),
            TextField(
              key: emailKey,
              style: theme.textTheme.bodyMedium,
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => busy ? null : onSubmit(),
              decoration: _fieldDecoration(
                theme,
                'Your email (optional)',
                icon: Icons.alternate_email,
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: submitKey,
            onPressed: busy ? null : onSubmit,
            child: busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send report'),
          ),
          const SizedBox(height: 8),
          // The reporter deserves to know what travels with their words —
          // and their QA lead needs them to know it.
          Text(
            'Sends your notes with the screenshot, device info and '
            'recent app logs.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
