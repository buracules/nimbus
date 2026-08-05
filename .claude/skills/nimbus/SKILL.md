---
name: nimbus
description: >
  Build, run, test, and debug iOS apps using the nimbus CLI. Use this skill when
  the user wants to build an iOS project, run an app on the simulator, stream logs,
  select a device, troubleshoot build issues, or says anything like "build the app",
  "run on simulator", "show me the logs", "pick a device", "nimbus build", "nimbus run",
  or asks about Xcode build configuration. Also trigger when the user mentions iOS
  development tasks like "launch my app", "test my changes on simulator", or "why
  isn't my app building?".
---

# Nimbus iOS Build Helper

Help users build, run, and debug iOS applications using the nimbus CLI tool.

**Read the JSON Output section first.** When you are the one running nimbus, pass
`--json` and parse the result. Do not scrape the human output — it is decorated,
it is not a contract, and it will change.

---

## JSON Output

Every command except `logs` accepts `--json`. Under `--json`, stdout carries
exactly one JSON object and nothing else. All narration moves to stderr.

### Envelope

```json
{ "ok": true,  "command": "build", "data": { ... } }
{ "ok": false, "command": "build", "error": { "code": "build_failed", "message": "...", "exitCode": 65, "diagnostics": ["..."] } }
```

- `ok` — whether the command did what it was asked.
- `command` — the command that ran, e.g. `build`, `sim screenshot`.
- `data` — present only when `ok` is true.
- `error` — present only when `ok` is false.
- Exit status is 0 when `ok` is true and non-zero otherwise, so you can branch on
  either.

**Branch on `error.code`, never on `error.message`.** Codes are stable; messages
are worded for humans and get reworded.

`error.exitCode` and `error.diagnostics` appear only when there is something to
report. `diagnostics` holds the compiler/xcodebuild lines that caused the
failure, capped at 50 — that is where the "why" of a failed build lives.

### Error codes

| Code | Meaning |
|------|---------|
| `build_failed` | `xcodebuild build` returned non-zero; see `diagnostics` |
| `test_failed` | `xcodebuild test` returned non-zero; see `diagnostics` |
| `clean_failed` | `xcodebuild clean` returned non-zero |
| `no_simulators` | This machine has no simulators at all |
| `no_device_selected` | The interactive picker was cancelled |
| `scheme_unknown` | No scheme configured and none could be detected |
| `app_bundle_not_found` | The built `.app` is not on disk — build first |
| `bundle_identifier_unknown` | Could not read `CFBundleIdentifier` from the app |
| `xcodebuild_not_found` | Xcode command line tools are missing |
| `config_exists` | `nimbus init` found a config and `--force` was not given |
| `invalid_arguments` | The flags given cannot be acted on |
| `file_not_found` | A file the command was pointed at does not exist |
| `command_failed` | An underlying tool (usually `simctl`) failed |
| `parse_error` | A tool's output could not be read |
| `config_error` | A config file could not be loaded |
| `not_found` | Something nimbus looked for was not there |
| `unsupported_output_mode` | `--json` asked for on a command that streams stdout |
| `internal_error` | Unclassified |

### What `data` contains

| Command | `data` keys |
|---------|-------------|
| `build` | `scheme`, `configuration`, `resolution`, `build` |
| `run` | `scheme`, `configuration`, `resolution`, `build`, `app` (`path`, `bundleID`) |
| `test` | `scheme`, `configuration`, `resolution`, `test` |
| `clean` | `scheme`, `configuration`, `clean` |
| `devices` | `runtimes` — each with `runtime`, `name`, `devices` |
| `init` | `path`, `config` |
| `sim screenshot` / `sim record` | `resolution`, `file` (`path`) |
| `sim openurl` | `resolution`, `url` |
| `sim push` | `resolution`, `bundleID`, `payload` |
| `sim privacy` | `resolution`, `action`, `service`, `bundleID` |
| `sim appearance` | `resolution`, `appearance` |
| `sim statusbar` | `resolution`, `cleared`, `overrides` |
| `sim location` | `resolution`, `cleared`, `latitude`, `longitude` |
| `sim shutdown` | `devices` — each with `udid`, `name`, `wasBooted` |

`build`, `test` and `clean` each hold a result object: `succeeded`, `exitCode`,
`duration` (seconds).

Keys with no value are **omitted, not null** — `sim location --clear` has no
`latitude`, and `sim privacy reset` has no `bundleID`. Use `?` in jq
(`.data.bundleID?`) or check for presence.

`resolution` is how nimbus picked the simulator, and it is worth reading:

```json
"resolution": {
  "device": { "udid": "...", "name": "iPhone 17 Pro", "state": "Booted", "isAvailable": true },
  "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-26-3",
  "requestedName": "iPhone 17",
  "matchedRequest": false,
  "suggestions": []
}
```

`matchedRequest: false` means the configured device does not exist here and
nimbus fell back to another one. Tell the user — a build that "worked" on the
wrong simulator is a common surprise.

### `--json` is refused by the streaming commands

`nimbus logs --json` and `nimbus run --logs --json` fail with
`unsupported_output_mode`. A log stream owns stdout for as long as it runs, so
an envelope cannot be written to the same place. Run `nimbus run --json` to
build and launch, then `nimbus logs` separately if a human wants to watch.

### `--json` implies non-interactive

`--interactive` is ignored under `--json` (with a warning on stderr) — a menu
prompt has the same stdout problem, and there is nobody to answer it. Pass
`--device` / `--os`, or let the smart fallback choose.

---

## Core Commands

### Build the Project
```bash
nimbus build                            # build
nimbus build --json                     # build, machine-readable result
nimbus build --configuration Release
nimbus build --verbose                  # full xcodebuild log
nimbus build --interactive              # pick the simulator from a menu
```

`build` resolves a real simulator before building, so the `-destination` is
always a UDID that exists on this machine.

### Run on Simulator
```bash
nimbus run                              # build + install + launch
nimbus run --json
nimbus run --interactive
nimbus run --device "iPhone 17 Pro"
nimbus run --os 26.4
nimbus run --logs                       # launch and stream the app's console
```

`run --logs` launches with `simctl launch --console-pty`, so it shows this
launch's stdout/stderr. It holds the terminal until Ctrl+C, and it cannot be
combined with `--json`.

### Run Tests
```bash
nimbus test
nimbus test --json                      # failing tests appear in error.diagnostics
nimbus test --interactive               # pick the simulator from a menu
nimbus test --verbose
```

`test` resolves a simulator and passes a real `-destination`.

### Stream Logs
```bash
nimbus logs                             # auto-detect the bundle ID from the scheme
nimbus logs --interactive
nimbus logs --bundle-id com.example.MyApp
nimbus logs --device "iPhone 17" --os 26.4
```

`logs` attaches to whatever is already running. It boots the simulator if
needed, then streams with a predicate that matches both the app's executable
name (which catches `print` and stderr) and its subsystem (which catches
`os.Logger`). Press Ctrl+C to stop. **Does not accept `--json`.**

Use `logs` to watch an app that is already running; use `run --logs` to launch
and watch in one step.

### List Available Devices
```bash
nimbus devices                          # available simulators
nimbus devices --all                    # including unavailable ones, with the reason
nimbus devices --json
```

### Clean Build Artifacts
```bash
nimbus clean
nimbus clean --json
```

---

## Simulator Control (`nimbus sim`)

Every `sim` subcommand takes `--device`, `--os`, `--interactive`, `--verbose`
and `--json`, and resolves a simulator the same way `build`/`run`/`test` do.
All of them except `shutdown` boot the device first if it is not already booted.

```bash
# Screenshot — writes ./nimbus-screenshot-<timestamp>.png by default
nimbus sim screenshot
nimbus sim screenshot /tmp/shot.png
nimbus sim screenshot --type jpeg /tmp/shot.jpeg
nimbus sim screenshot --json            # data.file.path is where it landed

# Screen recording — records until Ctrl+C, then writes the movie
nimbus sim record
nimbus sim record /tmp/demo.mov --codec hevc

# Deep links and universal links
nimbus sim openurl "myapp://profile/42"
nimbus sim openurl "https://example.com"

# Push notifications — payload is a JSON file containing an "aps" key
nimbus sim push payload.json --bundle-id com.example.MyApp

# Privacy permissions
nimbus sim privacy grant photos --bundle-id com.example.MyApp
nimbus sim privacy revoke location --bundle-id com.example.MyApp
nimbus sim privacy reset all

# Light/dark appearance
nimbus sim appearance                   # print the current appearance
nimbus sim appearance dark

# Status bar — for clean screenshots
nimbus sim statusbar --time 9:41 --battery-level 100 --wifi-bars 3
nimbus sim statusbar --clear

# Simulated location
nimbus sim location 37.3349,-122.0090
nimbus sim location --clear

# Shutdown
nimbus sim shutdown                     # the resolved device
nimbus sim shutdown --all               # every booted simulator
```

`sim statusbar` also accepts `--battery-state` (charging/charged/discharging),
`--cellular-bars` (0-4), `--data-network` (wifi/5g/lte/4g/3g/hide) and
`--operator-name`.

`sim record` is long-running but it is not a stream — nothing goes to stdout
while it runs — so `--json` works: the envelope arrives after Ctrl+C.

---

## Configuration

### Project Configuration (nimbus.yml)
Create or update `nimbus.yml` in the project root:

```yaml
project: MyApp.xcodeproj       # or workspace: MyApp.xcworkspace
scheme: MyApp
device: "iPhone 17"
os: "26.4"
configuration: Debug
xcbeautify: true
```

All fields are optional — nimbus auto-detects what it can. The file is found by
walking up from the current directory, so it works from a subdirectory of a
monorepo.

### Generate Configuration
```bash
nimbus init                             # project nimbus.yml
nimbus init --global                    # ~/.config/nimbus/config.yml
nimbus init --force                     # overwrite an existing one
nimbus init --json
```

Global config should only hold user preferences (`device`, `os`,
`configuration`, `xcbeautify`). `project`, `workspace` and `scheme` are
auto-detected per directory, which is what makes git worktrees work.

**Priority**: CLI flags > project `nimbus.yml` > global config > auto-detection.

---

## Device Selection Strategies

### Smart Fallback (Default)
When no device is specified, nimbus picks, in order:
1. An exact name match (filtered by `--os` if given)
2. A booted device matching the OS preference
3. Any booted device
4. The first available device matching the OS
5. The first available device

Under `--json`, `data.resolution.matchedRequest` tells you whether step 1 hit.

### OS Matching
`--os` matches by version component, not substring: `--os 26` matches iOS 26.2
and 26.4; `--os 26.2` matches only 26.2; `--os 6.2` matches nothing.

### Interactive Selection
```bash
nimbus run --interactive
```
Ignored under `--json`.

### Fuzzy Matching
```bash
nimbus run --device "iPhon 17"
# ⚠ Device 'iPhon 17' not found, using 'iPhone 17 Pro' instead
#   Did you mean: "iPhone 17 Pro", "iPhone 17 Pro Max"?
```
Under `--json` the same information is in `data.resolution.suggestions`.

---

## Common Workflows

### Driving nimbus as an agent
```bash
# Build and read the outcome
nimbus build --json

# On failure, .error.diagnostics has the compiler errors — read them, fix the
# code, build again. No terminal scraping.
nimbus build --json | jq -r '.error.diagnostics[]?'

# Build, install, launch, and confirm which device it landed on
nimbus run --json | jq -r '.data.resolution.device.name'

# Take a screenshot to check UI work
nimbus sim screenshot --json | jq -r '.data.file.path'
```

### First Time Setup
```bash
cd /path/to/ios/project
nimbus init                             # optional — auto-detection works without it
nimbus run --interactive
```

### Daily Development
```bash
nimbus run                              # build + launch
nimbus logs                             # watch output in another terminal
nimbus run                              # rebuild and relaunch
```

### UI Review Loop
```bash
nimbus run --json
nimbus sim appearance dark
nimbus sim statusbar --time 9:41 --battery-level 100 --wifi-bars 3
nimbus sim screenshot --json /tmp/dark.png
```

### Debugging Build Issues
```bash
nimbus build --verbose                  # full xcodebuild log
nimbus clean && nimbus build --verbose
nimbus devices --all                    # is the simulator even installed?
```

---

## Troubleshooting

### `no_simulators` / "Simulator not found"
- Run `nimbus devices --all` — unavailable simulators are listed with the reason
- Use `--interactive` to pick from a menu, or drop `--device` for smart fallback
- Check the name matches; fuzzy suggestions appear when it does not

### `matchedRequest: false` when you expected a specific device
The configured `device` does not exist on this machine. Check
`nimbus devices --all`, then fix `nimbus.yml` or the global config.

### `app_bundle_not_found`
- Build first: `nimbus build` or `nimbus run`
- Then `nimbus clean && nimbus run`
- `run` and `logs` locate the app via `xcodebuild -showBuildSettings`, falling
  back to a DerivedData search; `--verbose` says which route was used

### `scheme_unknown`
- Add `scheme: YourScheme` to `nimbus.yml`, or pass `--scheme`
- `xcodebuild -list` shows the available schemes
- `--verbose` prints the candidates and why one was chosen

### `test_failed` with "not configured for the test action"
The scheme has no test action. Pick a scheme that does, with `--scheme`.

### Logs not showing
- The app must be running — `nimbus run` first, or use `nimbus run --logs`
- Confirm the bundle ID with `--bundle-id`
- `--verbose` prints the predicate being used

### `unsupported_output_mode`
You passed `--json` to `logs` or to `run --logs`. Drop one of them.

---

## Quick Reference

| Task | Command |
|------|---------|
| Build | `nimbus build` |
| Build, machine-readable | `nimbus build --json` |
| Build + install + launch | `nimbus run` |
| Launch and stream console | `nimbus run --logs` |
| Attach to a running app's logs | `nimbus logs` |
| Run tests | `nimbus test` |
| Clean | `nimbus clean` |
| List simulators | `nimbus devices` |
| List all simulators | `nimbus devices --all` |
| Pick device interactively | `nimbus run --interactive` |
| Screenshot | `nimbus sim screenshot` |
| Record the screen | `nimbus sim record` |
| Open a deep link | `nimbus sim openurl "myapp://x"` |
| Send a push | `nimbus sim push payload.json --bundle-id com.example.App` |
| Grant a permission | `nimbus sim privacy grant photos --bundle-id com.example.App` |
| Dark mode | `nimbus sim appearance dark` |
| Clean status bar | `nimbus sim statusbar --time 9:41 --battery-level 100` |
| Set location | `nimbus sim location 37.3349,-122.0090` |
| Shut down simulators | `nimbus sim shutdown --all` |
| Generate config | `nimbus init` |

---

## Integration with Claude Code

1. **Use `--json` for anything you act on.** Human output is for humans.
2. **Check the current directory** is an iOS project before running anything.
3. **Read `nimbus.yml` if it exists** to understand the configuration.
4. **Report `matchedRequest: false`** — the user probably did not intend to build
   for a fallback device.
5. **Read `error.diagnostics` before guessing.** It has the actual compiler error.
6. **Never pass `--json` to `logs`.** Streaming is for a human to watch.
