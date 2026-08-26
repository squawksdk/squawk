# squawk

Shake-to-report feedback for Flutter. A tester shakes their phone; an
annotated screenshot, device and app details, recent logs, and any user
context you attached are delivered to the developer's inbox.

**Status: released.** `0.1.0` is the first working release; `0.0.1` was a
name reservation. Published versions are permanent, so treat every release
as one-way.

## Layout

A standard Dart package. `pubspec.yaml` sits at the repo root because
pub.dev renders the root `README.md` as the package page — that file is
the product's main listing, not just developer notes.

## Working here

```sh
flutter test
flutter pub publish --dry-run   # before any release
```

## Releasing

In order, once the release PR (version bump + CHANGELOG entry) is merged:

```sh
git tag -a vX.Y.Z <merge commit> -m "squawk X.Y.Z"
git push origin vX.Y.Z
gh release create vX.Y.Z --title "squawk X.Y.Z"   # notes = the CHANGELOG section
flutter pub publish                                # from a clean main checkout
```

The tag marks the exact commit pub.dev serves. Tag before publishing —
the publish is the one step that cannot be redone, so everything else
comes first.

## Conventions

- **Apache-2.0.** `LICENSE` at root. Its appendix template
  (`Copyright [yyyy] [name of copyright owner]`) stays verbatim — the
  copyright statement belongs in file headers or a `NOTICE`.
- **Published versions are permanent.** A version can be retracted but
  never deleted. Treat `flutter pub publish` as one-way.
- **The upload contract is versioned and hand-maintained.** This client
  shares no generated types with the server, so both sides move together.
  Ask before changing anything on that boundary.
- Conventional Commits; branches prefixed `feat/`, `fix/`, or `chore/`.

## Design decisions

Product scope, the public API surface, and naming are settled in a private
planning repo. Ask before changing any of them — the reasoning, including
the rejected options, is recorded there rather than here.

## Skills

- `codebase-design` — module interfaces and seams.
- `tdd` — features and bug fixes, test-first.
- `diagnosing-bugs` — something broken, throwing, failing, or slow.
- `code-review` — review a branch before it merges.
