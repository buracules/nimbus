# Changelog

All notable changes to nimbus are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `nimbus sim` command family — boot, shutdown, erase and open simulators,
  with long-running work that can be cancelled.
- `nimbus use` pins a simulator per project, so `run` stops asking once you
  have chosen. The pin store is deliberately private (see
  `docs/decisions/0004-the-selection-store-is-private.md`).
- `--json` on every command emits a machine-readable result envelope; human
  narration moves to stderr so it cannot corrupt the parse.
- `nimbus logs` streams a running app's console output, and `nimbus run --logs`
  builds, launches and streams in one step.
- An Alfred workflow drives nimbus from the launcher: per-project app icons,
  a live run status, and a retained log per run.
- `NO_COLOR` is honoured (any value, per no-color.org), and colour is decided
  per output stream rather than from stdout alone.

### Changed

- Simulators are resolved by reading CoreSimulator's own files instead of
  shelling out to `simctl`, which dominated startup time.
- Core returns values and callers narrate, rather than core printing directly
  (`docs/decisions/0001-core-returns-values-callers-narrate.md`).
- Booting waits for an actual boot via `simctl bootstatus` instead of sleeping
  two seconds and hoping.
- Scheme auto-detection deprioritises test bundles and is extracted into a
  testable `selectScheme`.
- The project root is derived once and found from any subdirectory.
- `Package.resolved` is now tracked, so builds are reproducible.

### Fixed

- `nimbus logs` matched the wrong process; it now matches on executable name
  and subsystem.
- `nimbus run` located the built `.app` by guessing; it now reads xcodebuild's
  build settings.
- `nimbus test` ran without a real `-destination`.
- `nimbus devices --all` was a no-op flag and never listed unavailable
  simulators.
- OS versions matched by loose substring, so `17.0` could match `17.0.1`'s
  neighbours; matching is now per component.
- `ProcessRunner.stream` raced on its buffers and could lose output written
  just before exit.
- Fuzzy-match suggestions had no score threshold and crashed on empty input,
  and could suggest the same device more than once per runtime.
- The build trusted the configured simulator name instead of resolving a real
  device.

## [0.1.0] — unreleased

Initial iOS build CLI: `build`, `run`, `test`, `devices` and `init`, wrapping
`xcodebuild` and `xcrun simctl` with auto-detection and readable output.

[Unreleased]: https://github.com/buracules/nimbus/compare/main...HEAD
