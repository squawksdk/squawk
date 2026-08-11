/// Squawk — shake-to-report feedback for Flutter apps.
///
/// This release reserves the package name while the SDK is being built. It
/// has no working API yet, so nothing here is safe to depend on.
///
/// See https://squawksdk.com for progress.
library;

/// Whether this build of the package is a name-reservation placeholder.
///
/// Always `true` until the first real release. The working SDK will expose a
/// `Squawk` widget that wraps your app, plus a small static API for showing
/// the report sheet and attaching user context.
const bool isPlaceholder = true;
