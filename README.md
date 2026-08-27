# Squawk

[![pub package](https://img.shields.io/pub/v/squawk.svg)](https://pub.dev/packages/squawk)

Your testers shake their phone — the annotated screenshot, logs, and device
info land in your inbox. One widget. Zero native setup.

A tester finds a bug, shakes their phone, scribbles on the screenshot, and
taps send. You get the whole picture without asking a single follow-up
question:

- **Annotated screenshot** — pen, arrows and text labels, drawn by the
  person who found the bug
- **Device and app context** — model, OS, app version, build number, and
  whether it was a debug, profile or release build
- **Recent logs** — a rolling buffer of console output, captured
  automatically
- **Who hit it** — an optional reporter email, plus any user context you
  attach

Reports arrive in a web inbox at
[app.squawksdk.com](https://app.squawksdk.com), with email, Slack and
webhook delivery. Free while in beta.

## Install

```sh
flutter pub add squawk
```

## Quick start

Create a project at [app.squawksdk.com](https://app.squawksdk.com), copy
the key it issues, and wrap your app:

```dart
void main() {
  runApp(
    Squawk(
      apiKey: 'sqk_your_project_key',
      child: const MyApp(),
    ),
  );
}
```

That's the integration. No native project edits, no Info.plist entries, no
manifest changes. The key is publishable — shipping it in a test build is
the intended use.

## Triggers

Shaking the device opens the report sheet. Three more ways in, all opening
the same sheet:

```dart
// From anywhere in your code — a menu item, a debug button:
Squawk.show();

// A floating button, off by default because it covers your UI:
SquawkOptions(feedbackButton: true)
```

If your app is used in motion — running, cycling, on a ferry — raise the
shake threshold, or turn the shake off and keep the button:

```dart
SquawkOptions(shakeSensitivity: ShakeSensitivity.firm)
```

Sensitivity is Android-only; iOS rides the system shake gesture, which
Apple does not make tunable.

## Who hit it

Attach the user context you already have, and every report carries it:

```dart
Squawk.setUser(id: 'u_42', email: 'jo@client.com');
Squawk.setMetadata('plan', 'trial');

// On sign-out — forgets the user and all metadata:
Squawk.clearUser();
```

## Offline

Reports are spooled on disk and sent when the network is back. A tester on
a plane can shake, annotate and send; the report arrives after landing.

## Theming

Squawk draws above your `MaterialApp`, so it cannot read your theme. Hand
it one and the report sheet, the sent note and the floating button all
match your app:

```dart
Squawk(
  apiKey: 'sqk_your_project_key',
  options: SquawkOptions(theme: myTheme, darkTheme: myDarkTheme),
  child: const MyApp(),
)
```

Pass only `theme` and it is used whatever the device is set to — which is
what you want if your app pins one `themeMode`.

### If your theme is built by a widget

Some theming setups only work once a widget above them has run.
`flutter_screenutil` is the common one: a theme that sizes text with `.sp`
reads values that `ScreenUtilInit` sets up, so building that theme before
`ScreenUtilInit` throws `LateInitializationError` and the app opens to a
blank screen.

`Squawk` does not have to be at the root. It only has to sit above
`MaterialApp`, so put it below whatever your theme depends on:

```dart
void main() {
  runApp(
    ScreenUtilInit(
      designSize: const Size(393, 852),
      builder: (context, child) => Squawk(
        apiKey: 'sqk_your_project_key',
        options: SquawkOptions(theme: lightTheme),
        child: const MyApp(),
      ),
    ),
  );
}
```

The same applies to any theme that reads from an `InheritedWidget`. If you
are not theming Squawk, none of this matters and the root is fine.

## Options

Every option has a default that suits most apps; passing no options at all
is the expected case.

| Option             | Default  | What it does                                  |
| ------------------ | -------- | --------------------------------------------- |
| `shakeToReport`    | `true`   | Shaking opens the report sheet                |
| `shakeSensitivity` | `medium` | How hard the shake must be (Android only)     |
| `feedbackButton`   | `false`  | A floating button that opens the sheet        |
| `captureLogs`      | `true`   | Attach recent log output to reports           |
| `askReporterEmail` | `true`   | The sheet asks the reporter for their email   |
| `theme`/`darkTheme`| unset    | Theme Squawk's own UI                         |

## Platforms

Android and iOS. The positioning is literal — your testers shake their
phone — and the shake trigger is native code for exactly those two
platforms. On other platforms the package does not apply.

Known limit: platform views (Google Maps, WebView) render blank in
screenshots.

## Your obligations

Reports can contain personal data: whatever is on the screen, whatever
your app logs, the reporter's email, and any user context you attach.
Squawk stores reports in the EU and deletes them for real — deleting a
report removes the row and the screenshot the same day — but what goes
into a report is under your control:

- Set `captureLogs: false` if your logs can carry sensitive data.
- Only attach user context you are allowed to share with a processor.
- Cover feedback reports in your app's privacy policy if you ship Squawk
  to end users rather than testers.

## Roadmap and feedback

Squawk is built in the open. Bugs and feature requests — for the SDK,
the dashboard, or delivery — live in
[GitHub issues](https://github.com/squawksdk/squawk/issues); their labels
(`considering`, `planned`, `in progress`, `shipped`) are the roadmap.
Questions and half-formed ideas go to
[Discussions](https://github.com/squawksdk/squawk/discussions), and what
already shipped is on the
[changelog](https://squawksdk.com/changelog).

## License

[Apache-2.0](LICENSE). The SDK is open source; the hosted inbox that
receives reports is a separate paid service, free while in beta.
