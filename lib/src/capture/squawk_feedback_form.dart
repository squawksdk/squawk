import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';

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
  });

  final OnSubmit onSubmit;

  /// Non-null when the sheet is draggable; must be handed to the scrollable so
  /// dragging expands the sheet.
  final ScrollController? scrollController;

  static const Key submitKey = Key('squawk_submit_button');

  @override
  State<SquawkFeedbackForm> createState() => _SquawkFeedbackFormState();
}

class _SquawkFeedbackFormState extends State<SquawkFeedbackForm> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
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
                key: const Key('squawk_text_input'),
                style: theme.textTheme.bodyMedium,
                controller: _controller,
                maxLines: 2,
                minLines: 2,
                textInputAction: TextInputAction.done,
              ),
            ],
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
            onPressed: () => widget.onSubmit(_controller.text),
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
