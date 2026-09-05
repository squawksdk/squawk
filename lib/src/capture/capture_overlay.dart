import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../reporter_email_store.dart';
import '../squawk_controller.dart';
import 'annotation_canvas.dart';
import 'annotations.dart';
import 'squawk_feedback_form.dart';

/// The full capture screen, in two steps.
///
/// First the screenshot fills the screen and the reporter draws on it, with
/// nothing but a slim bar of tools at either end. Then Next slides the form
/// up over it for the words and the email. Drawing and describing never
/// share the screen, so neither the form nor the keyboard ever shrinks the
/// picture, and a finger always has the whole screen to aim at.
///
/// Built for someone who has never filed a bug: every control is either
/// obvious (colors, undo, close) or labelled in plain words, and drawing is
/// optional — Next is always there.
class CaptureOverlay extends StatefulWidget {
  const CaptureOverlay({
    super.key,
    required this.image,
    required this.annotations,
    required this.askReporterEmail,
    required this.onSubmit,
    required this.onDismiss,
    required this.onRetired,
  });

  final ui.Image image;
  final AnnotationController annotations;
  final bool askReporterEmail;

  /// Handed the comment and normalised email; the host owns what happens
  /// next. The overlay stays up, with the send button disabled, until this
  /// returns.
  final Future<void> Function(String text, String? email) onSubmit;

  final VoidCallback onDismiss;

  /// Called when this overlay instance leaves the tree, exit animation
  /// included. The session decides whether that means its image can go —
  /// another instance may still be showing it.
  final VoidCallback onRetired;

  static const Key closeButtonKey = Key('squawk_close_button');
  static const Key undoButtonKey = Key('squawk_undo_button');
  static const Key nextButtonKey = Key('squawk_next_button');
  static const Key backButtonKey = Key('squawk_back_button');
  static const Key penToolKey = Key('squawk_pen_tool');
  static const Key arrowToolKey = Key('squawk_arrow_tool');
  static const Key textToolKey = Key('squawk_text_tool');
  static const Key moveToolKey = Key('squawk_move_tool');
  static const Key labelInputKey = Key('squawk_label_input');
  static const Key labelSaveKey = Key('squawk_label_save');
  static const Key labelCancelKey = Key('squawk_label_cancel');
  static const Key labelDeleteKey = Key('squawk_label_delete');
  static const Key discardButtonKey = Key('squawk_discard_button');
  static const Key keepEditingButtonKey = Key('squawk_keep_editing_button');

  /// Room the details sheet always leaves above itself, so a strip of the
  /// drawing stays visible as the thing being described.
  static const double _sheetHeadroom = 56;

  @override
  State<CaptureOverlay> createState() => _CaptureOverlayState();
}

/// Which of the two steps is in front.
enum _Step { markup, details }

class _CaptureOverlayState extends State<CaptureOverlay>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final _text = TextEditingController();
  final _email = TextEditingController();

  /// Drives the entrance: chrome slides in while the screenshot settles into
  /// its frame. Reversed, faster, on dismiss — leaving should feel lighter
  /// than arriving.
  late final AnimationController _entrance;
  late final CurvedAnimation _eased;

  /// Drives the details sheet up over the drawing and back down.
  late final AnimationController _sheet;
  late final CurvedAnimation _sheetEased;

  _Step _step = _Step.markup;
  bool _submitting = false;
  bool _confirmingDiscard = false;
  bool _leaving = false;

  /// Set while the label editor is open: where a new label would land, or
  /// which existing one is being reworded.
  ({Offset point, TextAnnotation? existing})? _labelEdit;
  final _labelText = TextEditingController();

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _eased = CurvedAnimation(
      parent: _entrance,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _sheet = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _sheetEased = CurvedAnimation(
      parent: _sheet,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _entrance.forward();
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
    _sheetEased.dispose();
    _sheet.dispose();
    _eased.dispose();
    _entrance.dispose();
    _text.dispose();
    _email.dispose();
    _labelText.dispose();
    super.dispose();
    widget.onRetired();
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

  void _showDetails() {
    if (_step == _Step.details) return;
    // The selection box is drawing-time chrome. It goes before the form
    // covers it, so what shows through the scrim is the report as sent.
    widget.annotations.select(null);
    setState(() => _step = _Step.details);
    _sheet.forward();
  }

  Future<void> _showMarkup() async {
    if (_step == _Step.markup) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await _sheet.reverse();
    if (mounted) setState(() => _step = _Step.markup);
  }

  /// A tap with the text tool: rewording the label it landed on, or writing
  /// a new one where it did not.
  void _onLabelRequested(Offset imagePoint) {
    final existing = widget.annotations.labelAt(imagePoint);
    _labelText.text = existing?.text ?? '';
    setState(() => _labelEdit = (point: imagePoint, existing: existing));
  }

  void _saveLabel() {
    final edit = _labelEdit;
    if (edit == null) return;

    if (edit.existing != null) {
      widget.annotations.updateLabel(edit.existing!, _labelText.text);
    } else {
      widget.annotations.addLabel(edit.point, _labelText.text);
    }
    setState(() => _labelEdit = null);
  }

  void _deleteLabel() {
    final existing = _labelEdit?.existing;
    if (existing != null) widget.annotations.updateLabel(existing, '');
    setState(() => _labelEdit = null);
  }

  /// Plays the exit and only then tells the host — so walking away gets the
  /// same care as arriving.
  Future<void> _dismiss() async {
    if (_leaving) return;
    _leaving = true;
    await _entrance.reverse();
    widget.onDismiss();
  }

  void _requestClose() {
    if (_submitting || _leaving) return;
    // Back (or a second close) while a dialog is up reads as "never mind" —
    // the safe choice, matching how dialogs behave everywhere else.
    if (_confirmingDiscard) {
      setState(() => _confirmingDiscard = false);
      return;
    }
    if (_labelEdit != null) {
      setState(() => _labelEdit = null);
      return;
    }
    // From the form, back means back to the drawing, not out. Nothing is
    // lost either way: the words stay typed.
    if (_step == _Step.details) {
      _showMarkup();
      return;
    }
    if (_hasContent) {
      setState(() => _confirmingDiscard = true);
    } else {
      _dismiss();
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

    return FadeTransition(
      opacity: _eased,
      child: Material(
        // Blended onto an opaque base: a host theme may leave
        // scaffoldBackgroundColor translucent, and the live app is still
        // painting under this overlay — it would show through beside the
        // frozen screenshot.
        color: Color.alphaBlend(
          theme.scaffoldBackgroundColor,
          theme.brightness == Brightness.dark
              ? const Color(0xFF000000)
              : const Color(0xFFFFFFFF),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Inert under the sheet: a stroke drawn through the scrim would
            // be invisible to the reporter and present in the report.
            IgnorePointer(
              ignoring: _step == _Step.details || _submitting,
              child: _markup(theme),
            ),
            if (_step == _Step.details) _details(theme),
            if (_labelEdit != null) _labelEditor(theme),
            if (_confirmingDiscard) _discardConfirm(theme),
          ],
        ),
      ),
    );
  }

  Widget _slideIn(Widget child, {required Offset from}) => SlideTransition(
    position: Tween<Offset>(begin: from, end: Offset.zero).animate(_eased),
    child: child,
  );

  /// Step one: the screenshot between two slim bars, and nothing else.
  Widget _markup(ThemeData theme) {
    return SafeArea(
      child: Column(
        children: [
          _slideIn(from: const Offset(0, -0.6), _topBar(theme)),
          Expanded(
            // The screenshot settles from slightly over-scale into its
            // frame — the screen becoming a photo.
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.06, end: 1.0).animate(_eased),
              child: _canvasWithHint(theme),
            ),
          ),
          _slideIn(from: const Offset(0, 0.4), _toolStrip(theme)),
        ],
      ),
    );
  }

  Widget _topBar(ThemeData theme) {
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
            builder:
                (context, _) => IconButton(
                  key: CaptureOverlay.undoButtonKey,
                  onPressed:
                      widget.annotations.canUndo
                          ? widget.annotations.undo
                          : null,
                  icon: const Icon(Icons.undo),
                  tooltip: 'Undo drawing',
                ),
          ),
          const SizedBox(width: 4),
          FilledButton.tonal(
            key: CaptureOverlay.nextButtonKey,
            onPressed: _showDetails,
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }

  /// Tools and colors along the bottom, under the thumb, and never shrunk
  /// to fit the way a single crowded row would be.
  Widget _toolStrip(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: ListenableBuilder(
        listenable: widget.annotations,
        builder:
            (context, _) => _scrollableWhenTight(
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ToolButton(
                    key: CaptureOverlay.penToolKey,
                    icon: Icons.gesture,
                    label: 'Pen tool',
                    selected: widget.annotations.tool == AnnotationTool.pen,
                    onTap: () => widget.annotations.tool = AnnotationTool.pen,
                  ),
                  _ToolButton(
                    key: CaptureOverlay.arrowToolKey,
                    icon: Icons.north_east,
                    label: 'Arrow tool',
                    selected: widget.annotations.tool == AnnotationTool.arrow,
                    onTap: () => widget.annotations.tool = AnnotationTool.arrow,
                  ),
                  _ToolButton(
                    key: CaptureOverlay.textToolKey,
                    icon: Icons.text_fields,
                    label: 'Text tool',
                    selected: widget.annotations.tool == AnnotationTool.text,
                    onTap: () => widget.annotations.tool = AnnotationTool.text,
                  ),
                  _ToolButton(
                    key: CaptureOverlay.moveToolKey,
                    icon: Icons.open_with,
                    label: 'Move tool',
                    selected: widget.annotations.tool == AnnotationTool.move,
                    onTap: () => widget.annotations.tool = AnnotationTool.move,
                  ),
                  const SizedBox(width: 10),
                  for (final color in annotationColors)
                    _ColorDot(
                      color: color,
                      selected: widget.annotations.color == color,
                      onTap: () => widget.annotations.color = color,
                    ),
                ],
              ),
            ),
      ),
    );
  }

  /// Lets [row] scroll sideways on a phone too narrow for it, and centres it
  /// everywhere else.
  ///
  /// Scrolling rather than scaling: shrinking the strip to fit would take the
  /// tap targets under the 44px that every accessibility guideline asks for,
  /// and these are the controls the whole screen exists to offer.
  Widget _scrollableWhenTight(Widget row) {
    return LayoutBuilder(
      builder:
          (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: row,
            ),
          ),
    );
  }

  Widget _canvasWithHint(ThemeData theme) {
    return Stack(
      children: [
        Positioned.fill(
          child: AnnotationCanvas(
            image: widget.image,
            controller: widget.annotations,
            onLabelRequested: _onLabelRequested,
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
              builder:
                  (context, _) => AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: widget.annotations.hasAnnotations ? 0 : 1,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.inverseSurface.withValues(
                            alpha: 0.75,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          switch (widget.annotations.tool) {
                            AnnotationTool.text =>
                              'Tap the screenshot to add a note',
                            AnnotationTool.move =>
                              'Drag a drawing to move it — the corner '
                                  'dot resizes',
                            _ =>
                              'Draw on the screenshot to point at the '
                                  'problem. Pinch to zoom in.',
                          },
                          textAlign: TextAlign.center,
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
    );
  }

  /// Step two: the form as a sheet over the dimmed drawing.
  ///
  /// The sheet alone tracks the keyboard. Deliberately not AnimatedPadding:
  /// the platform already animates viewInsets frame by frame as the keyboard
  /// slides, so easing toward it meant chasing a moving target. Tracking the
  /// inset directly is what makes the sheet look attached to it.
  Widget _details(ThemeData theme) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FadeTransition(
          opacity: _sheetEased,
          child: GestureDetector(
            // Tapping the drawing goes back to it — the same gesture as
            // dragging the sheet away, for people who do not know to drag.
            onTap: _showMarkup,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(_sheetEased),
              child: LayoutBuilder(
                builder:
                    (context, constraints) => ConstrainedBox(
                      // A landscape phone has less height than the form wants.
                      // The drawing keeps its strip and the form scrolls.
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                        maxHeight:
                            constraints.maxHeight -
                            CaptureOverlay._sheetHeadroom,
                      ),
                      child: Material(
                        color: theme.colorScheme.surface,
                        elevation: 8,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sheetHandle(theme),
                            Flexible(
                              child: SingleChildScrollView(
                                child: SquawkFeedbackForm(
                                  onSubmit: _submit,
                                  textController: _text,
                                  emailController: _email,
                                  askReporterEmail: widget.askReporterEmail,
                                  busy: _submitting,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The grab bar and the way back. Dragging down closes the sheet, and so
  /// does the button beside the bar for anyone who would rather tap.
  Widget _sheetHandle(ThemeData theme) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 200) _showMarkup();
      },
      child: SizedBox(
        height: 40,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Positioned(
              left: 4,
              child: TextButton.icon(
                key: CaptureOverlay.backButtonKey,
                onPressed: _submitting ? null : _showMarkup,
                icon: const Icon(Icons.chevron_left, size: 18),
                label: const Text('Drawing'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelEditor(ThemeData theme) {
    final editing = _labelEdit?.existing != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onTap: () => setState(() => _labelEdit = null),
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
        ),
        // Sits in the upper half on purpose, clear of the keyboard the
        // autofocus is about to raise.
        Align(
          alignment: const Alignment(0, -0.5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Material(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      editing ? 'Edit note' : 'Add a note',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: CaptureOverlay.labelInputKey,
                      controller: _labelText,
                      autofocus: true,
                      maxLength: 100,
                      maxLines: 2,
                      minLines: 1,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _saveLabel(),
                      decoration: const InputDecoration(
                        hintText: 'What should this point out?',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (editing)
                          TextButton(
                            key: CaptureOverlay.labelDeleteKey,
                            onPressed: _deleteLabel,
                            child: Text(
                              'Remove',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        const Spacer(),
                        TextButton(
                          key: CaptureOverlay.labelCancelKey,
                          onPressed: () => setState(() => _labelEdit = null),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          key: CaptureOverlay.labelSaveKey,
                          onPressed: _saveLabel,
                          child: Text(editing ? 'Save' : 'Add'),
                        ),
                      ],
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
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your drawing and notes will be lost.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      key: CaptureOverlay.keepEditingButtonKey,
                      onPressed:
                          () => setState(() => _confirmingDiscard = false),
                      child: const Text('Keep editing'),
                    ),
                    TextButton(
                      key: CaptureOverlay.discardButtonKey,
                      onPressed: _dismiss,
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

/// One drawing tool in the toolbar. A filled pill when active, so which
/// tool the next drag uses is never a guess.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color:
                  selected
                      ? theme.colorScheme.primaryContainer
                      : const Color(0x00000000),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              size: 20,
              color:
                  selected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
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
            width: selected ? 30 : 24,
            height: selected ? 30 : 24,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border:
                  selected
                      ? Border.all(color: theme.colorScheme.onSurface, width: 2)
                      : null,
            ),
          ),
        ),
      ),
    );
  }
}
