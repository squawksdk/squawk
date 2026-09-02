## 0.1.4

* `SquawkOptions.enabled`, default `true`. Set it to `false` and `Squawk`
  renders your app and nothing else: no shake listener, no floating
  button, no log capture, and nothing left in the spool by an earlier
  build is uploaded. `Squawk.show()` returns silently rather than
  reporting the "nothing mounted" error, since a disabled build is a
  choice and not a mistake.

  It is a plain runtime value, so it can come from a `--dart-define` or
  from something only known once the app is running, such as whether the
  install came from TestFlight. The README's "Only on test builds"
  section now leads with it. Passing an empty key and skipping the wrapper
  still works as before.

## 0.1.3

* Documentation only. The README is rewritten so a reader can ship Squawk
  correctly without asking anyone:
  * A new section covers keeping Squawk out of the build the public gets.
    Separate builds use a `--dart-define` and skip the wrapper when the
    key is empty. A TestFlight build promoted to the App Store can decide
    at runtime with `package_info_plus`, since Apple re-signs TestFlight
    builds with a sandbox receipt. Android has no such signal, so it gets
    a separate production build. `kReleaseMode` is called out as the
    wrong tool: TestFlight and Play testing builds are release builds.
  * The quick start and the published example now read the key from a
    `--dart-define` rather than hardcoding it.
  * The limits are stated: 100 log lines, a spool of 50 reports for
    7 days, and the retry schedule.
  * Retention now matches the privacy policy: reports on the free tier
    are deleted automatically 30 days after they arrive.
  * Slack delivery is described as it works now: posted as the app, so
    a resolve or delete in the inbox reaches the message, and a report
    can be resolved from Slack.

## 0.1.2

* Documentation only. The theming section now covers themes that a widget
  above them builds, such as one sized with `flutter_screenutil`: put
  `Squawk` below that widget rather than at the root. Wrapping at the root
  with such a theme threw `LateInitializationError` and opened the app to
  a blank screen, and the error named the theming package rather than
  Squawk.

## 0.1.1

* No behaviour change. Restructured how the capture session's future is
  returned so pub.dev's stricter analyzer no longer flags it, restoring
  the static-analysis score.

## 0.1.0

The first working release.

* `Squawk` widget: wrap your app, pass a project key, done. No native
  project edits.
* Shake opens the report sheet. `Squawk.show()` and an opt-in floating
  button open the same sheet; `shakeSensitivity` tunes the trigger on
  Android (iOS uses the system gesture).
* Annotate the screenshot with pen, arrows and text labels.
* Every report carries device and app info, the build mode, recent logs
  (`captureLogs` opts out), an optional reporter email, and any user
  context set with `Squawk.setUser` / `Squawk.setMetadata`.
* Offline spool: reports queue on disk and send when the network returns.
* `SquawkOptions.theme` / `darkTheme` match the report UI to the host app.
* Android and iOS only. Platform views (Maps, WebView) render blank in
  screenshots.

## 0.0.1

* Placeholder release reserving the `squawk` package name. No public API
  yet — the SDK is in development.
