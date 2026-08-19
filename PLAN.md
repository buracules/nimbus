# Nimbus — Implementation Plan

Goal: make nimbus star-worthy on GitHub. This plan comes from a full code + docs review
(2026-07-02). Work through the phases in order — Phase 1 items are user-visible bugs,
Phase 2 is robustness/quality, Phase 3 is documentation, Phase 4 is repo hygiene.

## Status (2026-08-19)

Phases 1–3 are **done**, plus `2.5` and `2.7` which were the last stragglers.
The test suite grew from 28 to 212.

Still open, all in Phase 4 (distribution — none of it blocks using nimbus):

| Item | State |
|---|---|
| 4.1 GitHub Actions CI | ✅ done |
| 4.2 Release automation + `v0.1.0` tag | ⬜ open |
| 4.3 Community files | 🟡 `LICENSE` + `CHANGELOG.md`; no CONTRIBUTING / CODE_OF_CONDUCT |
| 4.4 Demo GIF | ⬜ open |
| 4.5 Homebrew tap | ⬜ open — needs a `buracules/homebrew-tap` repo |
| 4.6 Repo metadata (description, topics) | ⬜ open — manual, on GitHub |

Work not in this plan that shipped anyway: the `sim` command family, the JSON
result envelope, per-project simulator pinning (`nimbus use`), and the Alfred
workflow.

---

Conventions for the implementer:
- Run `swift build && swift test` after every task. All 28 existing tests must stay green.
- Each task lists **Files**, **Change**, and **Acceptance** criteria.
- Add unit tests where a task says so; keep them in the existing XCTest style
  (`Tests/NimbusTests/`, temp-dir setUp/tearDown pattern as in `ConfigLoaderTests`).
- Commit per task (or per small group) with conventional commit messages
  (`fix:`, `feat:`, `docs:`, `ci:`, `chore:`), matching existing history.

---

## Phase 1 — Critical bug fixes

### 1.1 Fix the `nimbus logs` predicate (flagship feature is likely broken)

**Files:** `Sources/nimbus/Commands/LogsCommand.swift`, `Sources/nimbus/Core/SimulatorManager.swift`

**Problem:** `LogsCommand.swift:109` filters with
`processImagePath CONTAINS "<bundleID>"`. On the simulator the process image path is
`.../Containers/Bundle/Application/<UUID>/MyApp.app/MyApp` — the bundle ID never appears
in it, so the stream matches nothing for a typical app.

**Change:**
1. Add `SimulatorManager.executableName(appPath:)` that reads `CFBundleExecutable` from
   the app's `Info.plist` (same pattern as the existing `bundleIdentifier(appPath:)` at
   `SimulatorManager.swift:227`).
2. In `LogsCommand`, resolve BOTH the bundle ID and the executable name when the app
   bundle is found. When only `--bundle-id` is provided (no app bundle available), fall
   back to using the bundle ID's last dot-component as a best-effort process name and
   also match on subsystem.
3. Build the predicate as an OR so it catches print/stderr output (matched by process)
   and `os.Logger` output (matched by subsystem):
   ```
   processImagePath ENDSWITH "/<executableName>" OR subsystem == "<bundleID>"
   ```
   Escape embedded quotes in both values before interpolation.
4. Keep `--style compact`.

**Acceptance:**
- Unit test for `executableName(appPath:)` with a fixture Info.plist written to a temp
  dir (create `Fake.app/Info.plist` containing `CFBundleExecutable`).
- Unit test for a new pure helper `LogsCommand.buildPredicate(executableName:bundleID:)`
  (extract predicate construction into a testable static function) asserting the exact
  predicate string.
- Manual check if a simulator + app is available: `nimbus logs` shows the app's output.

### 1.2 Make `nimbus devices --all` work (currently a no-op flag)

**Files:** `Sources/nimbus/Core/SimulatorManager.swift`, `Sources/nimbus/Commands/DevicesCommand.swift`

**Problem:** the `--all` flag is declared (`DevicesCommand.swift:11`) but never read;
`listDevices()` always filters `isAvailable`.

**Change:**
1. Add parameter `listDevices(includeUnavailable: Bool = false)`. When true, skip the
   `.filter { $0.isAvailable }` and keep groups even if they only contain unavailable
   devices.
2. In `DevicesCommand.run()`, pass `includeUnavailable: all`. Render unavailable devices
   with a dim `(Unavailable)` badge and, when present, the `availabilityError` in dim
   text on the same line.

**Acceptance:** `nimbus devices --all` lists at least as many devices as
`nimbus devices`; unavailable ones are visually distinct. All existing callers of
`listDevices()` compile unchanged (default parameter).

### 1.3 Give `nimbus test` a real destination

**Files:** `Sources/nimbus/Commands/TestCommand.swift` (plus the shared helper from task 2.6 — do 2.6 first or extract minimally here)

**Problem:** with no `device`/`os` configured, `simulatorDestination` returns nil
(`XcodeBuildRunner.swift:51`), so `xcodebuild test` runs without `-destination` and
typically fails or picks an arbitrary device.

**Change:**
1. In `TestCommand.run()`, resolve a simulator the same way `RunCommand` does:
   `SimulatorManager.findDeviceWithFallback(name: config.device, os: config.os)`, print
   which device was chosen (`Console.info`), and pass
   `destinationUDID: match.device.udid` to `XcodeBuildRunner`.
2. Support `--interactive` on `test` too (same flag/behavior as run/logs). This becomes
   trivial after task 2.6 (shared device-resolution helper) — implement 2.6 first and
   call it from here.
3. If no simulator exists at all, error with the same message run uses
   ("No simulators available. Run 'nimbus devices'...").

**Acceptance:** `nimbus test` in a project with no nimbus.yml selects a simulator and
passes `-destination platform=iOS Simulator,id=<udid>` (verify via `--verbose` output).

### 1.4 Fix data race / lost output in `ProcessRunner.stream`

**Files:** `Sources/nimbus/Core/ProcessRunner.swift`

**Problem:** `stdoutBuffer`/`stderrBuffer` (`ProcessRunner.swift:75-101`) are mutated on
the pipes' readability-handler queues while the main thread reads them after
`waitUntilExit()`. `waitUntilExit` does not guarantee the handlers drained the pipes, so
the final lines can be lost, and the unsynchronized access is a data race.

**Change (recommended shape):**
1. Serialize all buffer access through a private `DispatchQueue` (e.g.
   `DispatchQueue(label: "nimbus.process-stream")`): the readability handlers dispatch
   their append+line-splitting work onto it (the line callbacks then also fire on that
   queue — that is fine, callers only `print`).
2. After `waitUntilExit()`, do a final drain: set handlers to nil, then call
   `readDataToEndOfFile()` on both read handles and run the same append+split logic on
   the queue, then flush any trailing partial line. Use `queue.sync {}` as the final
   barrier so everything is delivered before `stream` returns.
3. Factor the duplicated stdout/stderr buffering logic into one small private helper
   (a `LineBuffer` struct with `append(Data, emit: (String) -> Void)` and
   `flush(emit:)`) — removes the copy-paste and makes it testable.

**Acceptance:**
- Unit test `LineBuffer`: feed data in odd chunk boundaries (mid-line, multi-line,
  UTF-8 split across chunks is out of scope) and assert emitted lines + flush behavior.
- Integration-style test: `ProcessRunner.stream("/bin/sh", arguments: ["-c", "printf 'a\\nb\\nc'"])`
  must deliver exactly `a`, `b`, `c` (the unterminated `c` via flush) — run it in a loop
  ~50 times in the test to shake out the race.

### 1.5 Proper OS-version matching (stop loose substring matching)

**Files:** `Sources/nimbus/Core/SimulatorManager.swift`

**Problem:** `runtime.contains(os)` at `SimulatorManager.swift:58,98,116,144` means
`--os 6.2` matches runtime `...iOS-26-2`.

**Change:**
1. Add `static func runtimeVersion(from identifier: String) -> String?` that extracts the
   trailing version from identifiers like
   `com.apple.CoreSimulator.SimRuntime.iOS-26-2` → `"26.2"` (split on `.`, take last
   component, strip the leading platform word, join numeric parts with `.`).
2. Add `static func runtimeMatches(_ identifier: String, os: String) -> Bool` that
   compares version *components*: `os` matches if its dot-separated components are a
   prefix of the runtime's (so `26` matches 26.2, `26.2` matches 26.2, `6.2` does NOT).
3. Replace all four `contains(os) || contains(os.replacingOccurrences(...))` call sites
   with `runtimeMatches(group.runtime, os: os)`.

**Acceptance:** unit tests for `runtimeVersion(from:)` and `runtimeMatches(_:os:)`
covering: exact match, major-only prefix match, the `6.2` vs `26.2` false-positive (must
be false), tvOS/watchOS identifiers, and malformed identifiers (return nil / false, no
crash).

### 1.6 Robust app-bundle discovery via build settings

**Files:** `Sources/nimbus/Core/XcodeBuildRunner.swift`, `Sources/nimbus/Core/SimulatorManager.swift`, `Sources/nimbus/Commands/RunCommand.swift`, `Sources/nimbus/Commands/LogsCommand.swift`

**Problem:** `findAppBundle` (`SimulatorManager.swift:197`) globs
`~/Library/Developer/Xcode/DerivedData` by scheme-name substring and picks the newest
`.app`. Wrong app is possible with similar project names; custom DerivedData locations
break it entirely.

**Change:**
1. Add `XcodeBuildRunner.builtProductPath()` that runs
   `xcodebuild <project/workspace/scheme/configuration args> -destination <same as build> -showBuildSettings -json`
   via `ProcessRunner.run`, parses the JSON array, and returns
   `"\(TARGET_BUILD_DIR)/\(WRAPPER_NAME)"` (equivalently `CODESIGNING_FOLDER_PATH`) for
   the first target whose `WRAPPER_NAME` ends in `.app`.
   Extract the JSON parsing into a pure static
   `parseBuiltProductPath(fromJSON:) -> String?` for testability.
2. In `RunCommand` (step 4) and `LogsCommand` (bundle-ID auto-detect): try
   `builtProductPath()` first; if it returns nil or the path doesn't exist on disk, fall
   back to the existing `findAppBundle(scheme:configuration:)` heuristic, and note the
   fallback in `Console.verbose`.
3. `-showBuildSettings` adds ~1-3 s; acceptable for `run`. Do NOT call it during plain
   `build`.

**Acceptance:** unit test `parseBuiltProductPath(fromJSON:)` with a captured/fixture
`-showBuildSettings -json` payload (array of `{"target":..., "buildSettings": {...}}`).
Manual: `nimbus run` still finds the app on a real project.

---

## Phase 2 — Robustness & code quality

### 2.1 Replace the 2-second boot sleep with `bootstatus`

**Files:** `Sources/nimbus/Core/SimulatorManager.swift`, `Sources/nimbus/Commands/LogsCommand.swift`, `Sources/nimbus/Commands/RunCommand.swift`

**Change:** add `SimulatorManager.waitForBoot(udid:)` that runs
`xcrun simctl bootstatus <udid> -b` (blocks until booted; also triggers boot if needed).
Call it in `boot(udid:)` after the boot call (or replace the boot body with
`bootstatus -b` alone), and delete the `Thread.sleep(forTimeInterval: 2.0)` at
`LogsCommand.swift:71`.

**Acceptance:** no `Thread.sleep` remains in the codebase; `nimbus logs` against a
shut-down simulator starts streaming without a fixed delay.

### 2.2 Threshold fuzzy-match suggestions

**Files:** `Sources/nimbus/Utilities/FuzzyMatcher.swift`

**Change:** in `findClosestMatches`, drop candidates whose distance exceeds
`max(2, target.count / 3)` before taking the top N. Keep the signature; add the
threshold as a defaulted parameter if useful for tests.

**Acceptance:** unit tests: `"iPhon 17 Pro"` against a typical device list still returns
the iPhone 17 family; a nonsense query like `"zzzzzz"` returns `[]`. Update RunCommand /
LogsCommand behavior implicitly (they already handle the empty-suggestions case).

### 2.3 Remove dead code / no-ops

**Files:** `Sources/nimbus/Commands/DevicesCommand.swift`, `Sources/nimbus/Core/SimulatorManager.swift`

**Change:**
- Delete the no-op `.replacingOccurrences(of: "iOS ", with: "iOS ")` at
  `DevicesCommand.swift:46`.
- In `findAppBundle` (`SimulatorManager.swift:205`), `$0.hasPrefix(scheme) || $0.contains(scheme)`
  — the first clause is redundant; keep `contains` only. (This code remains as the
  fallback path after task 1.6.)
- Optional: reuse task 1.5's `runtimeVersion(from:)` inside
  `DevicesCommand.formatRuntime` so runtime formatting has one source of truth.

**Acceptance:** build + tests green; `nimbus devices` output unchanged.

### 2.4 Smarter scheme auto-detection ordering

**Files:** `Sources/nimbus/Commands/SharedOptions.swift`

**Change:** keep the current logic (name match → prefix match → blocklist skip) but:
1. Move the scheme-selection block into a pure static function
   `selectScheme(from schemes: [String], projectName: String?) -> String?` so it's unit
   testable.
2. Extend the skip heuristic: besides the hardcoded prefixes, also deprioritize schemes
   ending in `Tests`/`UITests`.
3. In verbose mode, print the candidate schemes and why one was chosen.

**Acceptance:** unit tests for `selectScheme` covering: exact name match wins, prefix
match, dependency schemes skipped, Tests-suffixed schemes skipped, single-scheme list,
empty list → nil.

### 2.5 Color handling: NO_COLOR + per-stream tty

**Files:** `Sources/nimbus/Output/Console.swift`

**Change:**
1. Respect the `NO_COLOR` convention: if `ProcessInfo.processInfo.environment["NO_COLOR"]`
   is set (any value), disable colors everywhere.
2. Decide color per stream: `error()` should check `isatty(fileno(stderr))`, everything
   else stdout. Simplest shape: `colored(_:_:stream:)` with an enum, or two computed
   flags `stdoutColorsEnabled` / `stderrColorsEnabled` consulted by the emit functions.
3. Cache the flags in `static let` (they're currently computed per call).

**Acceptance:** `NO_COLOR=1 nimbus devices` emits no ANSI escapes;
`nimbus devices | cat` already plain (regression check); build/tests green.

### 2.6 Extract shared device-resolution helper (removes ~45 duplicated lines)

**Files:** new `Sources/nimbus/Core/DeviceResolver.swift`; `Sources/nimbus/Commands/RunCommand.swift`, `Sources/nimbus/Commands/LogsCommand.swift`, `Sources/nimbus/Commands/TestCommand.swift`

**Change:** create
```swift
enum DeviceResolver {
    static func resolve(config: NimbusConfig, interactive: Bool, verbose: Bool)
        throws -> (device: SimulatorManager.Device, runtime: String)?
}
```
containing the interactive branch (DevicePicker) and the fallback branch (find +
fallback warning + fuzzy "Did you mean" suggestions + "Using device:" info lines),
exactly as currently duplicated in `RunCommand.swift:17-64` and
`LogsCommand.swift:17-61`. Both commands (and `TestCommand` after 1.3) call it and
`throw ExitCode.failure` on nil.

**Acceptance:** run/logs behavior and console output identical to before (compare
manually); duplication gone; tests green.

### 2.7 Commit `Package.resolved`

**Files:** `.gitignore`, `Package.resolved`

**Change:** remove the `Package.resolved` line from `.gitignore` and commit the file.
(For an executable package, pinning dependencies is the recommended practice —
reproducible builds for contributors and CI.)

**Acceptance:** `git ls-files | grep Package.resolved` shows the file; fresh clone +
`swift build` uses pinned versions.

---

## Phase 3 — Documentation

### 3.1 README overhaul

**Files:** `README.md`

Apply all of the following:

1. **Fix placeholder URLs** (lines 11, 17): replace `github.com/user/nimbus` and
   `mint install user/nimbus` with the real repo path. If the repo isn't published yet,
   use the intended `burakustn/nimbus` path consistently.
2. **Add a hook before Install**: 3-4 lines contrasting the raw xcodebuild incantation
   with nimbus, e.g. a side-by-side code block:
   `xcodebuild -workspace App.xcworkspace -scheme App -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' build`
   vs `nimbus run`. Keep the existing "Like cargo for Xcode projects" tagline as the
   first line.
3. **Demo placeholder**: add `![demo](docs/demo.gif)` right under the tagline and create
   `docs/` with a `README` note explaining how to regenerate the recording (see task 4.4
   which produces the actual GIF). Don't ship a broken image link — commit the GIF in
   the same PR as this line, or add the line in task 4.4 instead.
4. **Requirements section** (after Install): macOS 13+, Xcode with iOS simulators
   installed, Swift 5.9+ toolchain to build from source; `xcbeautify` optional.
5. **Document `nimbus run --logs`**: add to Quick Start, the Commands table, and a short
   paragraph in the Streaming Logs section (launch-with-console vs. attach-to-running).
6. **Document config discovery**: note that `nimbus.yml` is found by walking up parent
   directories from the CWD (monorepo/subdirectory friendly).
7. **Badges** (top of file, added properly in task 4.1): CI status, Swift version,
   platform macOS, license MIT.
8. **Promote the Claude Code skill section**: move it above License, keep as is
   otherwise; it's a differentiator.
9. After Phase 1 lands, re-verify every documented flag/behavior matches the code
   (`devices --all`, `test --interactive`, logs predicate description).

**Acceptance:** no `user/nimbus` placeholders remain; every command/flag in the README
exists in `--help` output; every shipped flag appears in the README.

### 3.2 Sync the example config and skill docs

**Files:** `nimbus.yml.example`, `.claude/skills/nimbus/SKILL.md`, `.claude/skills/nimbus/README.md`

**Change:** after Phase 1/2 land, sweep both skill docs and the example config for
accuracy (new `test --interactive`, `devices --all` now functional, logs behavior).
Keep the SKILL.md trigger description unchanged.

**Acceptance:** no doc references a flag that doesn't exist; no shipped flag missing
from SKILL.md's command reference.

---

## Phase 4 — Repo hygiene & distribution

### 4.1 GitHub Actions CI

**Files:** new `.github/workflows/ci.yml`

**Change:** workflow on push/PR to main: `runs-on: macos-latest` (or `macos-15`), steps:
checkout → `swift --version` → `swift build -c release` → `swift test`. Optionally a
second job running `swift build` on the oldest supported Xcode via `maxim-lobanov/setup-xcode`.
Add the CI badge to README (task 3.1 item 7).

**Acceptance:** workflow file is valid (run `gh workflow list` after push, or at minimum
`yamllint`-clean); badge URL matches the workflow name.

### 4.2 Release automation + v0.1.0

**Files:** new `.github/workflows/release.yml`, `Sources/nimbus/Nimbus.swift`

**Change:**
1. Release workflow triggered on `v*` tags: build `swift build -c release --arch arm64 --arch x86_64`
   (universal binary), `tar.gz` it, attach to a GitHub Release via `softprops/action-gh-release`
   (or `gh release create`).
2. Keep the version string in `Nimbus.swift:8` in sync with the tag — add a checklist
   note in CONTRIBUTING (4.3): bump `version:` before tagging.
3. After all phases: tag `v0.1.0`.

**Acceptance:** tagging produces a release with a downloadable universal binary that
runs on a clean machine (`./nimbus --version` prints the tag version).

### 4.3 Community files

**Files:** new `CONTRIBUTING.md`, `.github/ISSUE_TEMPLATE/bug_report.md`, `.github/ISSUE_TEMPLATE/feature_request.md`, `LICENSE`

**Change:**
1. `CONTRIBUTING.md`: dev setup (`swift build`, `swift test`), code style (match
   existing; `scripts/format-changes.sh` exists), commit conventions (conventional
   commits, as used in history), release checklist (version bump + tag).
2. Bug template: nimbus version, macOS + Xcode version, project type
   (workspace/project/SPM), the failing command with `--verbose` output.
3. Feature template: minimal (problem / proposed behavior).
4. `LICENSE`: replace "Nimbus Contributors" with the author's name — "Copyright (c) 2025
   Burak Üstün" (confirm the year the repo was created; keep MIT).

**Acceptance:** files exist, render correctly on GitHub, README links to CONTRIBUTING.

### 4.4 Demo GIF

**Files:** new `docs/demo.gif`, optional `docs/demo.tape`

**Change:** record a ~15-second terminal session showing `nimbus run` end-to-end
(device pick → build with pretty output → "Running on iPhone 17"). Preferred tool:
[VHS](https://github.com/charmbracelet/vhs) with a committed `.tape` script so it's
reproducible; asciinema + agg also fine. Embed at the top of the README. Keep the GIF
under ~3 MB (trim the build, or use a small demo project).

**Acceptance:** GIF displays on the GitHub repo page and shows the colored output.

### 4.5 Homebrew tap

**Files:** separate repo `homebrew-tap` (outside this one), plus README Install section update

**Change:** create `burakustn/homebrew-tap` with `Formula/nimbus.rb` pointing at the
v0.1.0 release tarball (url + sha256; `depends_on :macos`). Add
`brew install burakustn/tap/nimbus` as the FIRST install option in the README, before
build-from-source and Mint.

**Acceptance:** `brew install burakustn/tap/nimbus && nimbus --version` works on a
machine without the repo cloned.

### 4.6 Repo metadata (manual, on GitHub)

**Change:** set repo description ("A simple, fast iOS build CLI — like cargo for Xcode
projects"), topics (`ios`, `xcode`, `cli`, `swift`, `simulator`, `xcodebuild`,
`developer-tools`, `claude-code`, `agent-skills`), and a social-preview image (can be a
frame from the demo GIF). This is done in the GitHub UI, not in code — leave as a
checklist item for the maintainer.

---

## Suggested commit/PR grouping

1. PR "logs + devices + test fixes" — tasks 1.1, 1.2, 1.3 (+2.6 as its prerequisite)
2. PR "process streaming + device matching robustness" — 1.4, 1.5, 1.6, 2.1, 2.2, 2.3, 2.4
3. PR "console polish + repo pinning" — 2.5, 2.7
4. PR "docs" — 3.1, 3.2
5. PR "ci + community" — 4.1, 4.2, 4.3
6. PR "demo + distribution" — 4.4, then tag v0.1.0, then 4.5; 4.6 manual

## Definition of done

- `swift build -c release && swift test` green locally and in CI.
- Every documented flag exists; every flag is documented.
- `nimbus logs` demonstrably streams output from a real app (record this run — it can
  double as demo material).
- Fresh-machine install works via at least one non-source path (brew or release binary).
