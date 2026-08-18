import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../reporter_email_store.dart';
import '../squawk_controller.dart';
import 'annotation_canvas.dart';
import 'annotations.dart';
import 'squawk_feedback_form.dart';

/// The full capture screen: the still screenshot to draw on, the marker
/// tools, and the report form.
///
/// Built for someone who has never filed a bug: one screen, no modes, and
/// every control is either obvious (colors, undo, close) or labelled in plain
/// words. Drawing is optional; the send button is always reachable.
class CaptureOverlay extends StatefulWidget {
  const CaptureOverlay({
    super.key,
    required this.image,
    required this.annotations,
    required this.askReporterEmail,
    required this.onSubmit,
    required this.onDismiss,
  });

  final ui.Image image;
  final AnnotationController annotations;
  final bool askReporterEmail;

  /// Handed the comment and normalised email; the host owns what happens
  /// next. The overlay stays up, with the send button disabled, until this
  /// returns.
  final Future<void> Function(String text, String? email) onSubmit;

  final VoidCallback onDismiss;

  static const Key closeButtonKey = Key('squawk_close_button');
  static const Key undoButtonKey = Key('squawk_undo_button');
  static const Key discardButtonKey = Key('squawk_discard_button');
  static const Key keepEditingButtonKey = Key('squawk_keep_editing_button');

  @override
  State<CaptureOverlay> createState() => _CaptureOverlayState();
}

class _CaptureOverlayState extends State<CaptureOverlay>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _email = TextEditingController();

  bool _submitting = false;
  bool _confirmingDiscard = false;

  @override
  void initState() {
    super.initState();
    // For the Android back button. Registered observers are asked in order,
    // so a host navigator with routes to pop handles back first — same
    // limitation the feedback package had. At the host's root route, back
    // reaches us and closes the capture instead of exiting the app.
    WidgetsBinding.instance.addObserver(this);
    if (widget.askReporterEmail) _offerRememberedEmail();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _text.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    _requestClose();
    return true;
  }

  Future<void> _offerRememberedEmail() async {
    final suggestion = await SquawkController.instance.suggestedReporterEmail();
    if (!mounted || suggestion == null) return;

    // The reporter may have started typing while this was loading. Their
    // input wins.
    if (_email.text.isEmpty) _email.text = suggestion;
  }

  /// Whether closing now would throw away work. A prefilled email does not
  /// count — the reporter did not type it.
  bool get _hasContent =>
      widget.annotations.hasAnnotations || _text.text.trim().isNotEmpty;

  void _requestClose() {
    if (_submitting) return;
    // Back (or a second close) while the confirm is up reads as "never
    // mind" — the safe choice, matching how dialogs behave everywhere else.
    if (_confirmingDiscard) {
      setState(() => _confirmingDiscard = false);
      return;
    }
    if (_hasContent) {
      setState(() => _confirmingDiscard = true);
    } else {
      widget.onDismiss();
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    await widget.onSubmit(_text.text, ReporterEmail.normalise(_email.text));

    // Normally the host has removed this overlay by now; reaching here still
    // mounted means it did not, and the button must come back to life.
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedPadding(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            // Lifts the form above the keyboard; the screenshot shrinks to
            // make the room.
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SafeArea(
              // The form handles the bottom inset itself, so it collapses
              // when the keyboard covers the navigation bar.
              bottom: false,
              child: Column(
                children: [
                  _toolbar(theme),
                  Expanded(child: _canvasWithHint(theme)),
                  _formPanel(theme),
                ],
              ),
            ),
          ),
          if (_confirmingDiscard) _discardConfirm(theme),
        ],
      ),
    );
  }

  Widget _toolbar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            key: CaptureOverlay.closeButtonKey,
            onPressed: _requestClose,
            icon: const Icon(Icons.close),
            tooltip: 'Close',
          ),
          const Spacer(),
          ListenableBuilder(
            listenable: widget.annotations,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final color in annotationColors)
                  _ColorDot(
                    color: color,
                    selected: widget.annotations.color == color,
                    onTap: () => widget.annotations.color = color,
                  ),
                const SizedBox(width: 4),
                IconButton(
                  key: CaptureOverlay.undoButtonKey,
                  onPressed: widget.annotations.canUndo
                      ? widget.annotations.undo
                      : null,
                  icon: const Icon(Icons.undo),
                  tooltip: 'Undo drawing',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _canvasWithHint(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Stack(
        children: [
          Positioned.fill(
            // Inert while submitting: a stroke drawn during the composite
            // would appear on screen but not in the report.
            child: IgnorePointer(
              ignoring: _submitting,
              child: AnnotationCanvas(
                image: widget.image,
                controller: widget.annotations,
              ),
            ),
          ),
          // Plain-words guidance that gets out of the way at the first
          // stroke, and never intercepts one.
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: ListenableBuilder(
                listenable: widget.annotations,
                builder: (context, _) => AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: widget.annotations.hasAnnotations ? 0 : 1,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.inverseSurface
                            .withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Draw on the screenshot to point at the problem',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onInverseSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formPanel(ThemeData theme) {
    return Material(
      color: theme.colorScheme.surface,
      elevation: 4,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: SquawkFeedbackForm(
        onSubmit: _submit,
        textController: _text,
        emailController: _email,
        askReporterEmail: widget.askReporterEmail,
        busy: _submitting,
      ),
    );
  }

  Widget _discardConfirm(ThemeData theme) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Tapping outside keeps the report — the safe reading of an
        // ambiguous gesture.
        GestureDetector(
          onTap: () => setState(() => _confirmingDiscard = false),
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Material(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Discard this report?',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your drawing and notes will be lost.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      key: CaptureOverlay.keepEditingButtonKey,
                      onPressed: () =>
                          setState(() => _confirmingDiscard = false),
                      child: const Text('Keep editing'),
                    ),
                    TextButton(
                      key: CaptureOverlay.discardButtonKey,
                      onPressed: widget.onDismiss,
                      child: Text(
                        'Discard',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One selectable marker color.
class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: selected,
      label: '${colorNameOf(color)} marker',
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: selected ? 28 : 22,
            height: selected ? 28 : 22,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: theme.colorScheme.onSurface, width: 2)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
