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
