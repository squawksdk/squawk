import 'package:flutter/material.dart';
import 'package:squawk/squawk.dart';

void main() {
  runApp(
    Squawk(
      // Create a project at https://app.squawksdk.com and paste the key
      // it issues. Keys are publishable — shipping one in a test build
      // is the intended use.
      apiKey: 'sqk_your_project_key',
      child: const DemoApp(),
    ),
  );
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Squawk demo',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: const DemoHome(),
    );
  }
}

class DemoHome extends StatefulWidget {
  const DemoHome({super.key});

  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  bool _signedIn = false;

  void _toggleSignIn() {
    setState(() => _signedIn = !_signedIn);

    // Ordinary app logging — recent lines ride along on every report.
    debugPrint(_signedIn ? 'user signed in' : 'user signed out');

    if (_signedIn) {
      Squawk.setUser(id: 'u_42', email: 'jo@client.com');
      Squawk.setMetadata('plan', 'trial');
    } else {
      Squawk.clearUser();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Squawk demo'),
        actions: [
          // Squawk.show() opens the same sheet a shake does — wire it to
          // a menu item or a debug-only button if shaking is not enough.
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
            'Shake the phone or tap the toolbar icon. Both open the report '
            'sheet: annotate the screenshot, describe the problem, send.',
          ),
          const SizedBox(height: 24),
          Card(
            child: SwitchListTile(
              title: const Text('Signed in'),
              subtitle: Text(
                _signedIn
                    ? 'Reports carry u_42, jo@client.com, plan=trial'
                    : 'Reports carry no user context',
              ),
              value: _signedIn,
              onChanged: (_) => _toggleSignIn(),
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
            'Annotate this text when the sheet opens — it is here to give '
            'the screenshot something recognisable to draw on.',
          ),
        ],
      ),
    );
  }
}
