import 'package:flutter/material.dart';
import 'package:squawk/squawk.dart';

// A screen that looks like a real app, for recording the README GIF and the
// launch screenshots. The order total is wrong on purpose: that is the bug
// the tester circles. Run it with
//   flutter run -t lib/demo_main.dart --dart-define=SQUAWK_API_KEY=sqk_yourkey
// Shake only, no floating button, so the recording shows the shake.

const _apiKey = String.fromEnvironment(
  'SQUAWK_API_KEY',
  defaultValue: 'sqk_example_placeholder',
);

final _theme = ThemeData(
  colorSchemeSeed: const Color(0xFF3F51B5),
  scaffoldBackgroundColor: const Color(0xFFF7F6F3),
);

void main() {
  runApp(
    Squawk(
      apiKey: _apiKey,
      options: SquawkOptions(theme: _theme),
      child: const DemoApp(),
    ),
  );
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Morning Bakery',
      debugShowCheckedModeBanner: false,
      theme: _theme,
      home: const OrderScreen(),
    );
  }
}

class _Line {
  const _Line(this.name, this.detail, this.qty, this.price);
  final String name;
  final String detail;
  final int qty;
  final double price;
  double get total => qty * price;
}

const _lines = [
  _Line('Butter croissant', 'Warmed', 2, 3.50),
  _Line('Flat white', 'Oat milk, regular', 1, 4.20),
  _Line('Cinnamon bun', '', 1, 3.90),
];

const _delivery = 2.50;

class OrderScreen extends StatelessWidget {
  const OrderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtotal = _lines.fold(0.0, (sum, l) => sum + l.total);
    // The bug: delivery is subtracted instead of added.
    final total = subtotal - _delivery;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Your order'),
        centerTitle: false,
        leading: const Icon(Icons.arrow_back),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
        children: [
          Text(
            'Morning Bakery, Elm Street',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pickup at 8:40',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFE6E3DD)),
            ),
            child: Column(
              children: [for (final line in _lines) _LineTile(line: line)],
            ),
          ),
          const SizedBox(height: 20),
          _Row('Subtotal', subtotal),
          _Row('Delivery', _delivery),
          const Divider(height: 28),
          _Row('Total', total, bold: true),
          const SizedBox(height: 8),
          Text(
            'Paid with Apple Pay',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 34),
        child: FilledButton(
          onPressed: () {},
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text('Track order'),
        ),
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line});
  final _Line line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '${line.qty}×',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      title: Text(line.name),
      subtitle: line.detail.isEmpty ? null : Text(line.detail),
      trailing: Text(_money(line.total), style: theme.textTheme.bodyLarge),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.amount, {this.bold = false});
  final String label;
  final double amount;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = bold
        ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(_money(amount), style: style),
        ],
      ),
    );
  }
}

String _money(double amount) => '\$${amount.toStringAsFixed(2)}';
