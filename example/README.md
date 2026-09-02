# Squawk example

The smallest complete integration: wrap the app in `Squawk`, pass a
project key, and every shake opens the report sheet.

## Run it

Create a project at [app.squawksdk.com](https://app.squawksdk.com) and
pass its key at build time:

```sh
flutter run --dart-define=SQUAWK_API_KEY=sqk_yourkey
```

Without the define the app runs with Squawk left out entirely. That is
on purpose. It is the same switch a real app uses to keep Squawk out of
the build the public gets; the package README's "Only on test builds"
section explains the options.

With a key the server rejects, from a typo or a key you have since
regenerated, the sheet still opens and sending retries in the background.
A Flutter error in the console names the problem, and the queued reports
go through once the key is right.

## The dev harness

`lib/dev_main.dart` is a second entrypoint used to verify the SDK on real
devices. It reaches into the package's internals to show the upload spool
and the last captured report, and accepts run-time overrides:

```sh
flutter run -t lib/dev_main.dart \
  --dart-define=SQUAWK_API_KEY=sqk_yourkey \
  --dart-define=SQUAWK_ENDPOINT=https://your-ingest.example/v1/squawks
```

It exists for working on Squawk itself. `main.dart` is the file to copy
from.
