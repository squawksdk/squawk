# Squawk example

The smallest complete integration: wrap the app in `Squawk`, pass a
project key, and every shake opens the report sheet.

## Run it

```sh
flutter run
```

Create a project at [app.squawksdk.com](https://app.squawksdk.com) and put
its key in `lib/main.dart` to see reports arrive in your inbox. Without a
real key the capture flow still works; sending retries in the background
until a valid key is in place.

## The dev harness

`lib/dev_main.dart` is a second entrypoint used to verify the SDK on real
devices. It reaches into the package's internals to show the upload spool
and the last captured report, and accepts run-time overrides:

```sh
flutter run -t lib/dev_main.dart \
  --dart-define=SQUAWK_API_KEY=sqk_yourkey \
  --dart-define=SQUAWK_ENDPOINT=https://your-ingest.example/v1/squawks
```

It exists for working on Squawk itself; `main.dart` is the file to copy
from.
