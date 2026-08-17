import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';

import '../reporter_email_store.dart';
import '../squawk_controller.dart';

/// The form shown under the screenshot while reporting.
///
/// Squawk supplies its own rather than using the package default for one
/// reason: the default never accounts for `MediaQuery.padding.bottom`, so on
/// Android the submit button sits underneath the system navigation bar and
/// cannot be tapped. Reported on a Samsung A56, Android 16.
class SquawkFeedbackForm extends StatefulWidget {
  const SquawkFeedbackForm({
    super.key,
    required this.onSubmit,
    required this.scrollController,
    this.askReporterEmail = true,
  });

  final OnSubmit onSubmit;

  /// Whether to ask the reporter for an address.
  final bool askReporterEmail;

  /// Non-null when the sheet is draggable; must be handed to the scrollable so
  /// dragging expands the sheet.
  final ScrollController? scrollController;

  static const Key textKey = Key('squawk_text_input');
  static const Key submitKey = Key('squawk_submit_button');
  static const Key emailKey = Key('squawk_email_input');

  /// Key under which the address travels in `UserFeedback.extra`.
  static const String emailExtraKey = 'squawk.reporterEmail';

  @override
  State<SquawkFeedbackForm> createState() => _SquawkFeedbackFormState();
}

class _SquawkFeedbackFormState extends State<SquawkFeedbackForm> {
  final _controller = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.askReporterEmail) _offerRememberedEmail();
  }

  Future<void> _offerRememberedEmail() async {
    final suggestion = await SquawkController.instance.suggestedReporterEmail();
    if (!mounted || suggestion == null) return;

    // The reporter may have started typing while this was loading. Their
    // input wins.
    if (_emailController.text.isEmpty) _emailController.text = suggestion;
  }

  void _submit() {
    // `extra` is the package's own channel for fields a custom form adds, so
    // the address travels with the submission rather than through shared
    // mutable state that a second sheet could race.
    widget.onSubmit(
      _controller.text,
      extras: {
        SquawkFeedbackForm.emailExtraKey:
            ReporterEmail.normalise(_emailController.text),
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _emailController.dispose();
    super.dispose();
  }

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
    final strings = FeedbackLocalizations.of(context);
    // Flutter's theme rather than the package's: FeedbackTheme is not
    // exported, and this keeps the form independent of a dependency that is
    // slated to be vendored.
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: EdgeInsets.fromLTRB(
              20,
              widget.scrollController != null ? 20 : 16,
              20,
              0,
            ),
            children: [
              Text(
                strings.feedbackDescriptionText,
                maxLines: 2,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              TextField(
                key: SquawkFeedbackForm.textKey,
                style: theme.textTheme.bodyMedium,
                controller: _controller,
                // Grows with what the reporter writes instead of being pinned
                // at two lines, and shrinks back when the keyboard takes the
                // room.
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                decoration: _fieldDecoration(
                  theme,
                  'Describe what went wrong',
                ),
              ),
            ],
          ),
        ),
        // Outside the scroll area on purpose: the sheet opens collapsed and
        // its ListView builds lazily, so a field placed after the comment box
        // is never rendered until the reporter scrolls — and most will not.
        Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            // Clears the system navigation bar and the home indicator. Goes
            // to zero on its own when the keyboard covers them.
            12 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.askReporterEmail) ...[
                TextField(
                  key: SquawkFeedbackForm.emailKey,
                  style: theme.textTheme.bodyMedium,
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: _fieldDecoration(
                    theme,
                    'Your email (optional)',
                    icon: Icons.alternate_email,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                key: SquawkFeedbackForm.submitKey,
                onPressed: _submit,
                child: Text(strings.submitButtonText),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget squawkFeedbackBuilder(
  BuildContext context,
  OnSubmit onSubmit,
  ScrollController? scrollController,
) =>
    SquawkFeedbackForm(
      onSubmit: onSubmit,
      scrollController: scrollController,
    );
