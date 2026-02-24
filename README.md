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

The global config uses the same format as the project config. This is useful for settings like `device`, `os`, `configuration`, and `xcbeautify` that you want as defaults everywhere.

**Priority chain**: CLI flags > project `nimbus.yml` > global `~/.config/nimbus/config.yml` > auto-detected > defaults

## Commands

| Command | Description |
|---------|-------------|
| `nimbus build` | Build the project |
| `nimbus run` | Build + install + launch on simulator |
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
```

## Features

- **Auto-detection** — finds `.xcworkspace` > `.xcodeproj`, detects schemes via `xcodebuild -list`
- **Pretty output** — pipes through [xcbeautify](https://github.com/cpisciotta/xcbeautify) if installed, falls back to a built-in formatter
- **Build timing** — shows elapsed time after every build
- **Simple config** — one YAML file, all fields optional

## License

MIT
