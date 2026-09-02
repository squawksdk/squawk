# Squawk

[![pub package](https://img.shields.io/pub/v/squawk.svg)](https://pub.dev/packages/squawk)

Your testers shake their phone. The annotated screenshot, recent logs and
device info land in your inbox. One widget, no native setup.

A tester finds a bug, shakes the phone, draws on the screenshot and taps
send. You get the whole picture without a single follow-up question:

- **Annotated screenshot.** Pen, arrows and text labels, drawn by the
  person who found the bug.
- **Device and app context.** Model, OS version, app version and build
  number, and whether it was a debug, profile or release build.
- **Recent logs.** The last 100 lines of console output, captured
  automatically.
- **Who hit it.** An optional reporter email, plus any user context you
  attach.

Reports arrive in a web inbox at
[app.squawksdk.com](https://app.squawksdk.com), with email, Slack and
webhook delivery. Free while in beta.

## Install

```sh
flutter pub add squawk
```

Android and iOS only. See [Platforms](#platforms).

## Quick start

Create a project at [app.squawksdk.com](https://app.squawksdk.com) and
copy the key it issues. Then wrap your app:

```dart
// Supplied at build time, so no key lives in your repo:
//   flutter run --dart-define=SQUAWK_API_KEY=sqk_yourkey
const squawkApiKey = String.fromEnvironment('SQUAWK_API_KEY');

void main() {
  runApp(
    Squawk(
      apiKey: squawkApiKey,
      child: const MyApp(),
    ),
  );
}
```

That is the whole integration. No native project edits, no `Info.plist`
entries, no manifest changes. `Squawk` has to sit above your `MaterialApp`
(or `CupertinoApp`); the root is the usual place, but not the only one.
See [Theming](#theming) for when it should go lower.

The key is publishable. It identifies your project and nothing more, and
shipping it inside a test build is the intended use. If it leaks, regenerate
it in project settings and the old one stops working immediately.

## Only on test builds

Most teams want Squawk in the builds testers get and out of the build the
public gets. How you do that depends on whether those are different builds.

### Different builds for testers and for the store

Pass the key only when building for testers, and switch Squawk off when
it is missing:

```dart
const squawkApiKey = String.fromEnvironment('SQUAWK_API_KEY');

void main() {
  runApp(
    Squawk(
      apiKey: squawkApiKey,
      options: SquawkOptions(enabled: squawkApiKey.isNotEmpty),
      child: const MyApp(),
    ),
  );
}
```

With `enabled: false`, `Squawk` renders your app and nothing else. No
shake listener, no floating button, no log capture, and nothing left in
the spool by an earlier build is uploaded. `Squawk.show()` returns without
opening anything and without reporting an error, so a "Report a bug" menu
item is safe to leave in place.

```sh
# Testers
flutter build apk --dart-define=SQUAWK_API_KEY=sqk_yourkey

# The store: no define, so Squawk is never attached
flutter build appbundle
```

In CI, `--dart-define-from-file=squawk.json` keeps the key out of your
build scripts.

Do not gate on `kReleaseMode` for this. TestFlight and Play testing builds
are release builds, so `if (kReleaseMode)` switches Squawk off exactly
where your testers are.

### The same build promoted from TestFlight to the App Store

If you promote the TestFlight build to the store, anything baked in at
build time ships to everyone. On iOS you can instead decide at runtime,
because Apple re-signs TestFlight builds with a sandbox receipt and
App Store builds with a production one. `package_info_plus` reads that
for you:

```dart
import 'package:package_info_plus/package_info_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final info = await PackageInfo.fromPlatform();

  runApp(
    Squawk(
      apiKey: squawkApiKey,
      options: SquawkOptions(
        enabled: info.installerStore == 'com.apple.testflight',
      ),
      child: const MyApp(),
    ),
  );
}
```

`enabled` is an ordinary runtime value, so it can wait for an answer like
this one. It is read when `Squawk` is built, not on a timer, so it is not
a remote kill switch for a build already in people's hands.

`installerStore` is `com.apple.testflight` for TestFlight, `com.apple` for
the App Store, and `com.apple.simulator` on the simulator. A debug build
run from Xcode on a device also carries a sandbox receipt, so this check
means "not from the App Store" rather than "TestFlight specifically". For
this purpose that is what you want.

This adds nothing to your app. Squawk already depends on
`package_info_plus` to read your version and build number, so every app
with Squawk has it. Add it to your own `pubspec.yaml` only so you can
import it directly, which the `depend_on_referenced_packages` lint asks
for.

**Android has no equivalent.** Play's internal, closed and open testing
tracks install through the same installer as production, and nothing on
the device says which track a build came from. Ship a separate production
build without the key, as in the section above. Production uploads to Play
are separate uploads anyway, so this costs you nothing but a second build
command.

### Or ship it everywhere and filter

Every report records whether it came from a debug, profile or release
build, and the inbox filters on it. If you want reports from real users
but triaged apart from your testers, shipping Squawk everywhere works.

## Ways to open the sheet

Shaking the device opens the report sheet. Three more ways in, all
opening the same sheet:

```dart
// From anywhere in your code: a menu item, a debug screen, a gesture.
Squawk.show();
```

```dart
// A floating button. Off by default because it covers your UI.
SquawkOptions(feedbackButton: true)
```

```dart
// No shake at all. Pair it with the button or with Squawk.show().
SquawkOptions(shakeToReport: false)
```

`Squawk.show()` is safe to call from anywhere. If no `Squawk` widget is
mounted it reports a Flutter error and returns; it never throws, so a
misconfigured build cannot take your app down.

### Shake sensitivity

If your app is used in motion, on a run or a bike or a ferry, a normal
shake can fire on its own. Raise the threshold, or turn the shake off and
keep the button:

```dart
SquawkOptions(shakeSensitivity: ShakeSensitivity.firm)
```

Three levels: `light`, `medium` (the default) and `firm`. This is Android
only. iOS uses the system shake gesture, which Apple does not make
tunable.

## What a report contains

**The screenshot**, as the tester annotated it. Pen strokes, arrows and
text labels are drawn into the image before it is sent.

**Device and app context.** Device model, OS name and version, your app's
version and build number, and the build mode.

**Recent logs.** The last 100 lines of console output, each cut at 2,048
characters. This is on by default; see [Your obligations](#your-obligations)
before leaving it on in an app that logs anything sensitive.

**Who sent it.** An optional email address the tester types on the sheet,
plus whatever you attached with `Squawk.setUser` and `Squawk.setMetadata`.

Reports go to squawksdk.com. There is no self-hosted backend and the
endpoint is not configurable.

## Who hit it

Attach the user context you already have and every report carries it:

```dart
Squawk.setUser(id: 'u_42', email: 'jo@client.com');
Squawk.setMetadata('plan', 'trial');
Squawk.setMetadata('flags', ['new_checkout', 'dark_mode']);

// On sign-out. Forgets the user and every metadata key.
Squawk.clearUser();
```

Both calls are safe before the widget mounts, including before `runApp`.
`setMetadata` accepts any value that can be encoded as JSON. Both values
show on the report in the inbox.

Two different things can carry an email. `setUser` is the account your app
signed in; the sheet's own email field is whoever is holding the phone.
They are stored separately, and the sheet remembers the address the
tester typed so they do not retype it on every report. `clearUser()`
forgets that too.

## Offline

Reports are written to disk first and sent when the network allows. A
tester on a plane can shake, annotate and send; the report arrives after
landing.

The spool holds up to 50 reports for up to 7 days. Older or excess reports
are dropped, oldest first. Sending is retried with increasing delays, from
2 seconds up to 6 hours between attempts, and anything still waiting is
retried on every app start. Each upload gives up after 30 seconds and
tries again later.

If the server rejects the key, reports are kept and retried rather than
dropped, and a Flutter error names the problem so you see it in your
console. Fix the key and the queue drains.

## Theming

Squawk draws above your `MaterialApp`, so it cannot read your theme. Hand
it one and the report sheet, the sent note and the floating button all
match your app:

```dart
Squawk(
  apiKey: squawkApiKey,
  options: SquawkOptions(theme: myTheme, darkTheme: myDarkTheme),
  child: const MyApp(),
)
```

Pass only `theme` and it is used whatever the device is set to, which is
what you want if your app pins one `themeMode`. Pass both and Squawk
follows the device the way `ThemeMode.system` does. Pass neither and it
falls back to a plain light or dark theme matching the device.

`ThemeData` has no const constructor, so `SquawkOptions` cannot be `const`
once a theme is set.

### When a widget builds your theme

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
        apiKey: squawkApiKey,
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

Every option has a default that suits most apps. Passing no options at
all is the expected case.

| Option              | Default  | What it does                                    |
| ------------------- | -------- | ----------------------------------------------- |
| `enabled`           | `true`   | Whether Squawk does anything at all             |
| `shakeToReport`     | `true`   | Shaking opens the report sheet                  |
| `shakeSensitivity`  | `medium` | How hard the shake must be (Android only)       |
| `feedbackButton`    | `false`  | A floating button that opens the sheet          |
| `captureLogs`       | `true`   | Attach the last 100 log lines to reports        |
| `askReporterEmail`  | `true`   | The sheet asks the tester for their email       |
| `theme`             | unset    | Theme for Squawk's own UI                       |
| `darkTheme`         | unset    | Theme while the device is dark; needs `theme`   |

## Platforms

Android and iOS. The shake trigger is native code for exactly those two
platforms, and the package does not support others.

Known limit: platform views such as Google Maps and WebView render blank
in screenshots. Everything Flutter draws itself is captured.

## Where reports go and how long they stay

Reports are stored on Cloudflare in the European Union. On the free tier
they are deleted automatically 30 days after they arrive. Deleting a
report in the inbox is immediate and permanent: the database row and the
screenshot go together, the same day, with no trash bin to recover from.

Reports delivered to Slack are posted as the Squawk app, so resolving or
deleting a report in the inbox updates or removes the Slack message too,
and a report can be resolved from Slack. See
[squawksdk.com/privacy](https://squawksdk.com/privacy) for the full policy.

## Your obligations

Reports can contain personal data: whatever is on the screen, whatever
your app logs, the tester's email, and any user context you attach. What
goes into a report is under your control:

- Set `captureLogs: false` if your logs can carry sensitive data.
- Only attach user context you are allowed to share with a processor.
- Cover feedback reports in your app's privacy policy if you ship Squawk
  to end users rather than to testers.

## Roadmap and feedback

Squawk is built in the open. Bugs and feature requests for the SDK, the
inbox or delivery live in
[GitHub issues](https://github.com/squawksdk/squawk/issues). Their labels
(`considering`, `planned`, `in progress`, `shipped`) are the roadmap.
Questions and half-formed ideas go to
[Discussions](https://github.com/squawksdk/squawk/discussions). What has
already shipped is on the [changelog](https://squawksdk.com/changelog).

## License

[Apache-2.0](LICENSE). The SDK is open source. The hosted inbox that
receives reports is a separate service, free while in beta, with billing
announced by email before it starts.
