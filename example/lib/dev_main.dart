import 'dart:async';

import 'package:flutter/material.dart';
import 'package:squawk/squawk.dart';
// The harness reaches into the SDK's internals on purpose: on a device run
// it needs to see the spool and the last captured report, which the public
// API deliberately does not expose. Run it with
//   flutter run -t lib/dev_main.dart
// The published example is lib/main.dart; this file never appears on pub.dev.
// ignore: implementation_imports
import 'package:squawk/src/squawk_controller.dart';
// ignore: implementation_imports
import 'package:squawk/src/upload/spool.dart';

const _endpointFromEnv = String.fromEnvironment('SQUAWK_ENDPOINT');

/// Null unless SQUAWK_ENDPOINT was defined, so the demo falls back to the
/// same endpoint a real app would use.
final Uri? _endpointOverride =
    _endpointFromEnv.isEmpty ? null : Uri.parse(_endpointFromEnv);

void main() {
  runApp(const HarnessRoot());
}

/// Owns the theme mode, above [Squawk], so a change re-hands the SDK its
/// theme: Squawk draws above the MaterialApp and cannot read the app's.
class HarnessRoot extends StatefulWidget {
  const HarnessRoot({super.key});

  @override
  State<HarnessRoot> createState() => _HarnessRootState();
}

class _HarnessRootState extends State<HarnessRoot> {
  ThemeMode _mode = ThemeMode.system;

  static final _light = ThemeData(colorSchemeSeed: Colors.indigo);
  static final _dark = ThemeData(
    colorSchemeSeed: Colors.indigo,
    brightness: Brightness.dark,
  );

  /// Mirrors what the app shows: one theme when pinned, both to follow the
  /// device, the same way an app would set SquawkOptions for its themeMode.
  SquawkOptions get _options => switch (_mode) {
    ThemeMode.system => SquawkOptions(
      feedbackButton: true,
      theme: _light,
      darkTheme: _dark,
    ),
    ThemeMode.light => SquawkOptions(feedbackButton: true, theme: _light),
    ThemeMode.dark => SquawkOptions(feedbackButton: true, theme: _dark),
  };

  @override
  Widget build(BuildContext context) {
    return Squawk(
      // Passed at run time so no real key lives in this open-source repo:
      //   flutter run --dart-define=SQUAWK_API_KEY=sqk_yourkey
      // Without it the SDK still captures and spools; uploads retry as 401s
      // until a real key arrives, which is itself a useful thing to watch.
      apiKey: const String.fromEnvironment(
        'SQUAWK_API_KEY',
        defaultValue: 'sqk_example_placeholder',
      ),
      // Point the demo at a Worker other than production, for trying
      // ingest changes against a real device before they are deployed:
      //   flutter run --dart-define=SQUAWK_ENDPOINT=https://…/v1/squawks
      // Empty means the published default. Nobody's own endpoint belongs
      // in this repo, so it only ever arrives at run time.
      //
      // ignore: invalid_use_of_visible_for_testing_member
      endpoint: _endpointOverride,
      // The floating button is on so the demo can be triggered without
      // shaking, e.g. on a simulator or while the phone is tethered.
      options: _options,
      child: HarnessApp(
        theme: _light,
        darkTheme: _dark,
        mode: _mode,
        onModeChanged: (mode) => setState(() => _mode = mode),
      ),
    );
  }
}

class HarnessApp extends StatelessWidget {
  const HarnessApp({
    super.key,
    required this.theme,
    required this.darkTheme,
    required this.mode,
    required this.onModeChanged,
  });

  final ThemeData theme;
  final ThemeData darkTheme;
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Squawk dev harness',
      theme: theme,
      darkTheme: darkTheme,
      themeMode: mode,
      home: HarnessHome(mode: mode, onModeChanged: onModeChanged),
    );
  }
}

class HarnessHome extends StatefulWidget {
  const HarnessHome({
    super.key,
    required this.mode,
    required this.onModeChanged,
  });

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onModeChanged;

  @override
  State<HarnessHome> createState() => _HarnessHomeState();
}

class _HarnessHomeState extends State<HarnessHome> {
  bool _loggedIn = false;

  void _toggleLogin() {
    setState(() => _loggedIn = !_loggedIn);

    // Ordinary app logging — this is what ends up on a report.
    debugPrint(_loggedIn ? 'user signed in' : 'user signed out');

    if (_loggedIn) {
      Squawk.setUser(id: 'u_42', email: 'jo@client.com');
      Squawk.setMetadata('plan', 'trial');
      Squawk.setMetadata('screen', 'demo');
    } else {
      Squawk.clearUser();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Squawk dev harness'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: Squawk.show,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Shake the phone, tap the floating button, or use the toolbar '
            'icon. Each opens the same report sheet.',
          ),
          const SizedBox(height: 24),
          Card(
            child: SwitchListTile(
              title: const Text('Signed in'),
              subtitle: Text(
                _loggedIn
                    ? 'Reports carry u_42, jo@client.com, plan=trial'
                    : 'Reports carry no user context',
              ),
              value: _loggedIn,
              onChanged: (_) => _toggleLogin(),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Theme'),
                  const SizedBox(height: 4),
                  Text(
                    'The report sheet should match the app in every mode.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('System'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                      ),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                    ],
                    selected: {widget.mode},
                    onSelectionChanged: (modes) =>
                        widget.onModeChanged(modes.single),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton(
                onPressed: () => debugPrint(
                  'noisy line at ${DateTime.now().toIso8601String()}',
                ),
                child: const Text('Log a line'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => Future<void>.error(
                  StateError('deliberate demo failure'),
                ),
                child: const Text('Throw an error'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Annotate this text when the sheet opens — it is here to give the '
            'screenshot something recognisable to draw on.',
          ),
          const Divider(height: 40),
          const _SpoolCard(),
          const Divider(height: 40),
          const _LastReportCard(),
        ],
      ),
    );
  }
}

/// Shows whatever the SDK last captured, from any trigger.
///
/// Check the screenshot for the floating button: it sits inside the capture
/// boundary, so if it ever appears here, it is appearing in real reports too.
class _LastReportCard extends StatelessWidget {
  const _LastReportCard();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SquawkReport?>(
      valueListenable: SquawkController.instance.lastReport,
      builder: (context, report, _) {
        if (report == null) {
          return const Text('No report captured yet.');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last report', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('text: ${report.text ?? '(none)'}'),
            Text('user: ${report.userId ?? '(none)'} '
                '${report.userEmail ?? ''}'),
            Text('reporter email: ${report.reporterEmail ?? '(none)'}'),
            Text('metadata: ${report.metadata}'),
            Text('screenshot: ${report.screenshot.lengthInBytes ~/ 1024} KB'),
            Text('device: ${report.device?.deviceModel ?? '(unknown)'} '
                '• ${report.device?.osName ?? '?'} '
                '${report.device?.osVersion ?? ''}'),
            Text('app: ${report.device?.appVersion ?? '(unknown)'} '
                '• ${report.device?.buildMode.name ?? '?'} build'),
            const SizedBox(height: 8),
            Text(
              'logs: showing last ${report.logs.length.clamp(0, 20)} '
              'of ${report.logs.length} captured, newest last',
            ),
            for (final entry in report.logs.reversed.take(20).toList().reversed)
              Text(
                '${entry.isError ? '⚠ ' : ''}${entry.message}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: entry.isError ? Colors.red : null,
                ),
              ),
            const SizedBox(height: 8),
            Image.memory(report.screenshot, height: 360),
          ],
        );
      },
    );
  }
}

/// Shows what is still waiting to be delivered.
///
/// Without this a device run cannot tell a successful send from the SDK
/// quietly doing nothing — everything after submit happens in the background.
class _SpoolCard extends StatefulWidget {
  const _SpoolCard();

  @override
  State<_SpoolCard> createState() => _SpoolCardState();
}

class _SpoolCardState extends State<_SpoolCard> {
  Timer? _poll;
  int _waiting = 0;
  String _lastChecked = '—';

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final Spool? spool = SquawkController.instance.spool;
    if (spool == null) return;

    final waiting = await spool.pendingCount;
    if (!mounted) return;
    setState(() {
      _waiting = waiting;
      _lastChecked = DateTime.now().toIso8601String().substring(11, 19);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Delivery', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          _waiting == 0
              ? 'Nothing waiting — everything captured has been sent or dropped.'
              : '$_waiting report(s) still queued, retrying in the background.',
        ),
        Text('checked at $_lastChecked', style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: () => SquawkController.instance.spool?.drain(),
          child: const Text('Try sending now'),
        ),
      ],
    );
  }
}
