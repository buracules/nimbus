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

# Stream app logs from simulator
nimbus logs

# Run tests
nimbus test

# Clean
nimbus clean

# List available simulators
nimbus devices
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
| `nimbus run --interactive` | Interactive device picker before running |
| `nimbus logs` | Stream app logs from simulator in real-time |
| `nimbus logs --interactive` | Interactive device picker before streaming logs |
| `nimbus test` | Run unit tests |
| `nimbus clean` | Clean build artifacts |
| `nimbus devices` | List available simulators |
| `nimbus init` | Generate nimbus.yml from auto-detected settings |
| `nimbus init --global` | Generate global config at ~/.config/nimbus/config.yml |

### Shared Flags

All build commands accept:

```
--scheme        Xcode scheme to use
--configuration Build configuration (Debug/Release)
--device        Simulator device name
--os            Simulator OS version
--verbose       Show verbose output
--interactive   Interactively select a simulator from a menu
```

### Device Selection

Nimbus has intelligent device selection that works even when the exact device isn't available:

**Smart Fallback (automatic)**:
- If no device is specified, nimbus will automatically pick:
  1. A booted device matching your OS preference
  2. Any booted device
  3. The first available device

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

The `logs` command streams app output from the simulator in real-time:

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
- Stream logs in real-time (press Ctrl+C to stop)

## Features

- **Auto-detection** — finds `.xcworkspace` > `.xcodeproj`, detects schemes via `xcodebuild -list`
- **Smart device selection** — automatically picks the best available simulator, or use `--interactive` to choose
- **Fuzzy matching** — typo in device name? Get helpful suggestions for similar devices
- **Real-time logs** — stream app output directly from the simulator with `nimbus logs`
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

## License

MIT
