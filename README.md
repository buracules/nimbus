# Nimbus

A simple, fast iOS build CLI tool. Like `cargo` for Xcode projects.

Nimbus wraps `xcodebuild` and `xcrun simctl` with a clean interface, auto-detection, and pretty output.

## Install

```bash
# Build from source
git clone https://github.com/user/nimbus.git
cd nimbus
swift build -c release
cp .build/release/nimbus /usr/local/bin/

# Or with Mint
mint install user/nimbus
```

## Quick Start

```bash
cd your-ios-project

# Generate config (optional — nimbus auto-detects everything)
nimbus init

# Build
nimbus build

# Build + install + launch on simulator
nimbus run

# Build + install + launch with interactive device selection
nimbus run --interactive

# Build, install, launch, and stream the app's console output
nimbus run --logs

# Stream logs from an app that is already running
nimbus logs

# Run tests
nimbus test

# Clean
nimbus clean

# List available simulators
nimbus devices

# Control the simulator: screenshots, deep links, permissions, appearance...
nimbus sim screenshot
nimbus sim openurl "myapp://profile/42"

# Machine-readable output, for scripts and agents
nimbus build --json
```

## Configuration

Create a `nimbus.yml` in your project root:

```yaml
project: MyApp.xcodeproj       # or workspace: MyApp.xcworkspace
scheme: MyApp
device: "iPhone 17"
os: "26.2"
configuration: Debug
xcbeautify: true               # true/false/omit for auto-detect
```

All fields are optional. Nimbus auto-detects what it can.

`nimbus.yml` is found by walking up from the current directory, so it works from
a subdirectory of a monorepo.

### Global Config

Set defaults across all projects with a global config at `~/.config/nimbus/config.yml`:

```bash
# Generate a global config
nimbus init --global
```

The global config should only contain **user preferences** like `device`, `os`, `configuration`, and `xcbeautify`. Project-specific fields (`project`, `workspace`, `scheme`) should NOT be in global config — they're auto-detected from each directory, which ensures everything works correctly in git worktrees.

**Priority chain**: CLI flags > project `nimbus.yml` > global `~/.config/nimbus/config.yml` > auto-detected > defaults

## Commands

| Command | Description |
|---------|-------------|
| `nimbus build` | Build the project |
| `nimbus run` | Build + install + launch on simulator |
| `nimbus run --logs` | Launch and stream the app's console output |
| `nimbus test` | Run unit tests |
| `nimbus clean` | Clean build artifacts |
| `nimbus logs` | Stream logs from an app already running on the simulator |
| `nimbus devices` | List available simulators |
| `nimbus devices --all` | Include unavailable simulators, with the reason |
| `nimbus sim <subcommand>` | Control the simulator — see below |
| `nimbus init` | Generate nimbus.yml from auto-detected settings |
| `nimbus init --global` | Generate global config at ~/.config/nimbus/config.yml |

### Simulator Control

| Command | Description |
|---------|-------------|
| `nimbus sim screenshot [path]` | Save a screenshot (`--type png/jpeg/tiff/bmp/gif`) |
| `nimbus sim record [path]` | Record the screen until Ctrl+C (`--codec h264/hevc`) |
| `nimbus sim openurl <url>` | Open a deep link or universal link |
| `nimbus sim push <payload.json>` | Send a simulated push notification |
| `nimbus sim privacy <action> <service>` | Grant, revoke or reset a permission |
| `nimbus sim appearance [light\|dark]` | Get or set the appearance |
| `nimbus sim statusbar` | Override the status bar, or `--clear` it |
| `nimbus sim location <lat,lon>` | Set or `--clear` the simulated location |
| `nimbus sim shutdown [--all]` | Shut down a simulator, or every booted one |

Every `sim` subcommand resolves a simulator with the same `--device` / `--os` /
`--interactive` flags as the build commands, and boots it if needed
(`shutdown` excepted, for obvious reasons).

### Shared Flags

All build commands accept:

```
--scheme        Xcode scheme to use
--configuration Build configuration (Debug/Release)
--device        Simulator device name
--os            Simulator OS version
--verbose       Show verbose output
--interactive   Interactively select a simulator from a menu
--json          Emit a JSON result envelope on stdout instead of human output
```

`build`, `run`, `test` and `clean` all resolve a real simulator before invoking
xcodebuild, so the `-destination` is always a UDID that exists on this machine.
`--interactive` works on all four.

### JSON Output

Every command except `logs` accepts `--json`. Under `--json`, stdout carries
exactly one object and all narration moves to stderr:

```bash
$ nimbus build --json
{
  "ok" : true,
  "command" : "build",
  "data" : {
    "scheme" : "MyApp",
    "configuration" : "Debug",
    "resolution" : { "device" : { "name" : "iPhone 17 Pro", ... }, ... },
    "build" : { "succeeded" : true, "exitCode" : 0, "duration" : 1.6 }
  }
}
```

Failures are structured too, with a stable code to branch on and the compiler
diagnostics that caused them:

```bash
$ nimbus build --json | jq -r '.error.code, .error.diagnostics[]?'
build_failed
/src/ContentView.swift:597:31: error: cannot convert value of type 'String' to specified type 'Int'
```

Codes are stable; messages are not — branch on `error.code`. The full set is
documented in [the Claude skill](.claude/skills/nimbus/SKILL.md).

`nimbus logs --json` and `nimbus run --logs --json` are refused with
`unsupported_output_mode`: a log stream and a result envelope cannot share
stdout. `--json` also implies non-interactive, since a menu prompt has the same
problem.

### Device Selection

Nimbus has intelligent device selection that works even when the exact device isn't available:

**Smart Fallback (automatic)**:
- If no device is specified, nimbus will automatically pick:
  1. An exact name match, filtered by `--os` if given
  2. A booted device matching your OS preference
  3. Any booted device
  4. The first available device matching your OS preference
  5. The first available device

**OS Matching**: `--os` compares version *components*, not substrings — `--os 26`
matches iOS 26.2 and 26.4, `--os 26.2` matches only 26.2, and `--os 6.2` matches
nothing.

**Interactive Selection**:
```bash
nimbus run --interactive
# Shows a numbered menu of all available simulators
# Select by number or press 'q' to cancel
```

**Fuzzy Matching**:
- If a device name doesn't match exactly, nimbus suggests similar devices:
  ```bash
  nimbus run --device "iPhon 17 Pro"
  # ⚠ Device 'iPhon 17 Pro' not found, using 'iPhone 17' instead
  #   Did you mean: "iPhone 17 Pro", "iPhone 16 Pro", "iPhone 17 Pro Max"?
  ```

### Streaming Logs

There are two ways to see an app's output, and they do different things.

`nimbus run --logs` launches the app with `simctl launch --console-pty` and
shows *that launch's* stdout and stderr:

```bash
nimbus run --logs
```

`nimbus logs` attaches to an app that is already running:

```bash
# Auto-detect bundle ID from scheme
nimbus logs

# Explicit bundle ID
nimbus logs --bundle-id com.example.MyApp

# Interactive device selection
nimbus logs --interactive

# Filter by OS version
nimbus logs --os 26.4
```

The logs command will:
- Auto-boot the simulator if it's not already running
- Auto-detect the bundle ID from your scheme if not specified
- Match on both the app's executable name (which catches `print` and stderr) and
  its subsystem (which catches `os.Logger`)
- Stream in real-time (press Ctrl+C to stop)

Neither accepts `--json` — see [JSON Output](#json-output).

## Features

- **Auto-detection** — finds `.xcworkspace` > `.xcodeproj`, detects schemes via `xcodebuild -list`
- **Smart device selection** — automatically picks the best available simulator, or use `--interactive` to choose
- **Fuzzy matching** — typo in device name? Get helpful suggestions for similar devices
- **Real-time logs** — stream app output directly from the simulator with `nimbus logs`
- **Simulator control** — screenshots, recordings, deep links, push, permissions, appearance, status bar and location via `nimbus sim`
- **Machine-readable output** — `--json` gives scripts and agents a stable envelope with stable error codes, instead of text to scrape
- **Pretty output** — pipes through [xcbeautify](https://github.com/cpisciotta/xcbeautify) if installed, falls back to a built-in formatter
- **Build timing** — shows elapsed time after every build
- **Simple config** — one YAML file, all fields optional

## Claude Code Integration

Nimbus includes a [Claude Code](https://claude.ai/claude-code) skill that helps you build, run, and debug iOS apps with AI assistance.

### Install the Skill

```bash
# From the nimbus repository
ln -s "$(pwd)/.claude/skills/nimbus" ~/.claude/skills/nimbus
```

### Usage

In Claude Code, just describe what you want:
- "Build my iOS app"
- "Run this on the simulator"
- "Show me the logs"
- "Pick a device to run on"

Or invoke directly: `/nimbus`

The skill provides:
- Command reference and best practices
- Device selection strategies
- Troubleshooting guides
- Common workflows

See [.claude/skills/nimbus/README.md](./.claude/skills/nimbus/README.md) for more details.

## Decisions

[docs/decisions](./docs/decisions/) records why nimbus is shaped the way it is —
including the core/CLI boundary rule that `CoreBoundaryTests` enforces. Read it
before proposing a change that the tests refuse.

## License

MIT
