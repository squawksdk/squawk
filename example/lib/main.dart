import 'dart:typed_data';

import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:shake_gesture/shake_gesture.dart';

/// Spike app for the two build-phase risks in SPEC.md §9:
///
/// 2. Does the shake trigger feel right? `shake_gesture` exposes no Dart-side
///    threshold, so the only question is whether the platform default is
///    usable as-is.
/// 3. Does `feedback` 3.2.0 (Jul 2025) still work on current Flutter stable?
void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BetterFeedback(
      child: MaterialApp(
        title: 'Squawk spike',
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        home: const SpikeHome(),
      ),
    );
  }
}

class SpikeHome extends StatefulWidget {
  const SpikeHome({super.key});

  @override
  State<SpikeHome> createState() => _SpikeHomeState();
}

class _SpikeHomeState extends State<SpikeHome> {
  final List<DateTime> _shakes = [];
  String? _text;
  Uint8List? _screenshot;

  void _onShake() {
    setState(() => _shakes.insert(0, DateTime.now()));
    BetterFeedback.of(context).show((UserFeedback feedback) {
      setState(() {
        _text = feedback.text;
        _screenshot = feedback.screenshot;
      });
    });
  }

  /// Gap since the previous shake, so double-fires are visible in the log.
  String _gap(int index) {
    if (index + 1 >= _shakes.length) return 'first';
    final ms = _shakes[index].difference(_shakes[index + 1]).inMilliseconds;
    return '+${ms}ms';
  }

  @override
  Widget build(BuildContext context) {
    return ShakeGesture(
      onShake: _onShake,
      child: Scaffold(
        appBar: AppBar(title: const Text('Squawk spike')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                title: Text(
                  '${_shakes.length}',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                subtitle: const Text('shakes detected'),
                trailing: FilledButton(
                  onPressed: _onShake,
                  child: const Text('Trigger'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Shake log', style: Theme.of(context).textTheme.titleMedium),
            if (_shakes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Shake the phone. Try gentle, hard, and while '
                    'walking — anything that fires here would fire in a real '
                    'app.'),
              ),
            for (var i = 0; i < _shakes.length && i < 8; i++)
              Text('${_shakes[i].toIso8601String().substring(11, 23)}'
                  '   ${_gap(i)}'),
            const Divider(height: 32),
            Text('Last report', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_screenshot == null)
              const Text('Nothing captured yet.')
            else ...[
              Text('text: ${_text?.isEmpty ?? true ? '(empty)' : _text}'),
              Text('screenshot: ${_screenshot!.lengthInBytes ~/ 1024} KB'),
              const SizedBox(height: 8),
              // Renders the annotated PNG the package returned. A blank or
              // broken image here is the failure mode risk 3 is watching for.
              Image.memory(_screenshot!, height: 320),
            ],
            const Divider(height: 32),
            const Text(
              'Annotate this text when the sheet opens — it is here to give '
              'the screenshot something recognisable to draw on.',
            ),
          ],
        ),
      ),
    );
  }
}
