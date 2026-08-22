# Squawk

Your testers shake their phone — the annotated screenshot, logs, and device
info land in your inbox. One widget. Zero native setup.

> **Status: placeholder.** This release reserves the package name. There is
> no working API yet, so please don't depend on it. Follow along at
> [squawksdk.com](https://squawksdk.com).

## What it will do

A tester finds a bug, shakes their phone, scribbles on the screenshot, and
taps send. You get the whole picture without asking them a single follow-up
question:

- **Annotated screenshot** — draw on the screen to point at the problem
- **Device and app context** — model, OS, app version, build mode
- **Recent logs** — a rolling buffer captured automatically, no setup
- **Reporter identity** — who hit it, and whatever user context you attach

Reports arrive in a web inbox, with email, Slack, and webhook delivery.

## What it will look like

```dart
void main() {
  runApp(
    Squawk(
      apiKey: 'sq_live_xxxxxxxx',
      child: const MyApp(),
    ),
  );
}
```

That's the integration. No native project edits, no Info.plist entries, no
manifest changes.

## Status and roadmap

The SDK is being built in the open. The plan is a free tier that never caps
report volume, and a flat paid tier for team delivery — no per-seat pricing,
no usage meters.

Watch [squawksdk.com](https://squawksdk.com) or the
[GitHub repo](https://github.com/squawksdk/squawk) for the first working
release.

## License

[Apache-2.0](LICENSE). The SDK is open source; the hosted backend that
receives reports is a separate paid service.
