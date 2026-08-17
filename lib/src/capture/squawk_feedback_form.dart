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

  @override
  Widget build(BuildContext context) {
    final strings = FeedbackLocalizations.of(context);
    // Flutter's theme rather than the package's: FeedbackTheme is not
    // exported, and this keeps the form independent of a dependency that is
    // slated to be vendored.
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: EdgeInsets.fromLTRB(
              16,
              widget.scrollController != null ? 20 : 16,
              16,
              0,
            ),
            children: [
              Text(
                strings.feedbackDescriptionText,
                maxLines: 2,
                style: theme.textTheme.titleSmall,
              ),
              TextField(
                key: SquawkFeedbackForm.textKey,
                style: theme.textTheme.bodyMedium,
                controller: _controller,
                maxLines: 2,
                minLines: 2,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
        ),
        // Outside the scroll area on purpose: the sheet opens collapsed and
        // its ListView builds lazily, so a field placed after the comment box
        // is never rendered until the reporter scrolls — and most will not.
        if (widget.askReporterEmail)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: TextField(
              key: SquawkFeedbackForm.emailKey,
              style: theme.textTheme.bodyMedium,
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Your email (optional)',
                isDense: true,
              ),
            ),
          ),
        Padding(
          // The whole point of this widget: keep the button clear of the
          // system navigation bar and the home indicator.
          padding: EdgeInsets.only(
            bottom: 8 + MediaQuery.of(context).padding.bottom,
          ),
          child: TextButton(
            key: SquawkFeedbackForm.submitKey,
            onPressed: _submit,
            child: Text(
              strings.submitButtonText,
              style: TextStyle(color: theme.colorScheme.primary),
            ),
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
