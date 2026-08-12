import 'package:flutter/material.dart';
import 'package:squawk/squawk.dart';
// Demo-only: reports currently stop at a stubbed sink inside the SDK because
// there is no upload or inbox yet. Watching it is how this app shows what was
// captured. Delete this import — and the card below — once reports have a
// real destination.
// ignore: implementation_imports
import 'package:squawk/src/squawk_controller.dart';

void main() {
  runApp(
    Squawk(
      apiKey: 'sq_test_placeholder',
      options: const SquawkOptions(
        // On so the demo can be triggered without shaking, e.g. on a
        // simulator or while the phone is tethered.
        feedbackButton: true,
      ),
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
  bool _loggedIn = false;

  void _toggleLogin() {
    setState(() => _loggedIn = !_loggedIn);

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
        title: const Text('Squawk demo'),
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
          const SizedBox(height: 24),
          const Text(
            'Annotate this text when the sheet opens — it is here to give the '
            'screenshot something recognisable to draw on.',
          ),
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
            Text('metadata: ${report.metadata}'),
            Text('screenshot: ${report.screenshot.lengthInBytes ~/ 1024} KB'),
            const SizedBox(height: 8),
            Image.memory(report.screenshot, height: 360),
          ],
        );
      },
    );
  }
}
