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

---

## Core Commands

### Build the Project
```bash
# Basic build
nimbus build

# Build with specific configuration
nimbus build --configuration Release

# Build with verbose output for debugging
nimbus build --verbose
```

### Run on Simulator
```bash
# Build + install + launch (uses smart device selection)
nimbus run

# Interactive device selection
nimbus run --interactive

# Run on specific device
nimbus run --device "iPhone 17 Pro"

# Run on specific OS version
nimbus run --os 26.4
```

### Stream Logs
```bash
# Auto-detect bundle ID and stream logs
nimbus logs

# Interactive device selection for logs
nimbus logs --interactive

# Specify bundle ID explicitly
nimbus logs --bundle-id com.example.MyApp

# Stream logs from specific device
nimbus logs --device "iPhone 17" --os 26.4
```

### List Available Devices
```bash
# See all available simulators
nimbus devices
```

### Run Tests
```bash
# Run unit tests
nimbus test

# Run tests with verbose output
nimbus test --verbose
```

### Clean Build Artifacts
```bash
# Clean DerivedData and build artifacts
nimbus clean
```

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

All fields are optional - nimbus auto-detects what it can.

### Generate Configuration
```bash
# Generate nimbus.yml from auto-detected settings
nimbus init

# Generate global config at ~/.config/nimbus/config.yml
nimbus init --global
```

---

## Device Selection Strategies

### Smart Fallback (Default)
When no device is specified, nimbus automatically picks:
1. A booted device matching your OS preference
2. Any booted device
3. The first available device

### Interactive Selection
Use `--interactive` flag to see a numbered menu:
```bash
nimbus run --interactive
```

### Fuzzy Matching
If device name has a typo, nimbus suggests similar devices:
```bash
nimbus run --device "iPhon 17"
# Shows: "Did you mean: iPhone 17, iPhone 17 Pro, iPhone 17e?"
```

---

## Common Workflows

### First Time Setup
```bash
# Navigate to project
cd /path/to/ios/project

# Generate config (optional - auto-detection works without it)
nimbus init

# Build and run
nimbus run --interactive
```

### Daily Development
```bash
# Build and run with auto device selection
nimbus run

# Stream logs in another terminal
nimbus logs

# Make changes, rebuild and rerun
nimbus run
```

### Testing on Multiple Devices
```bash
# Run on iPhone
nimbus run --device "iPhone 17" --os 26.4

# Run on iPad
nimbus run --device "iPad Pro 13-inch (M5)"

# Or use interactive selection each time
nimbus run --interactive
```

### Debugging Build Issues
```bash
# Build with verbose output to see full xcodebuild logs
nimbus build --verbose

# Clean and rebuild
nimbus clean
nimbus build --verbose

# Check available simulators
nimbus devices
```

---

## Troubleshooting

### "Simulator not found"
- Run `nimbus devices` to see available simulators
- Use `--interactive` to pick from a menu
- Check if device name matches exactly (or use fuzzy matching)
- Try without `--device` to use smart fallback

### "Built app not found in DerivedData"
- Run `nimbus clean` first
- Rebuild with `nimbus build`
- Check scheme name matches with `xcodebuild -list`
- Verify configuration (Debug/Release) matches

### "Cannot determine scheme"
- Add `scheme: YourScheme` to `nimbus.yml`
- Or use `--scheme YourScheme` flag
- Run `xcodebuild -list` to see available schemes

### "No simulators available"
- Open Xcode and install simulators
- Check `xcrun simctl list devices`
- Ensure Xcode command line tools are installed: `xcode-select --install`

### Logs not showing
- Ensure app is running: `nimbus run` first
- Check bundle ID is correct: use `--bundle-id` flag
- Try building and installing fresh: `nimbus clean && nimbus run`
- Boot simulator manually if needed

---

## Best Practices

1. **Use interactive mode** when switching between many devices:
   ```bash
   nimbus run --interactive
   ```

2. **Set global preferences** for common settings:
   ```bash
   nimbus init --global
   # Edit ~/.config/nimbus/config.yml with your preferred device/OS
   ```

3. **Keep project-specific config minimal** - let auto-detection work:
   ```yaml
   # Good nimbus.yml (only what's needed)
   scheme: MyApp
   ```

4. **Use verbose mode for debugging** build issues:
   ```bash
   nimbus build --verbose
   ```

5. **Stream logs during development**:
   ```bash
   # Terminal 1
   nimbus run

   # Terminal 2
   nimbus logs
   ```

---

## Integration with Claude Code

When helping users with nimbus:

1. **Always check current directory** - ensure they're in an iOS project
2. **Read nimbus.yml if it exists** to understand their configuration
3. **Check git status** before suggesting clean builds
4. **Use appropriate commands** based on context:
   - Building: `nimbus build`
   - Running: `nimbus run --interactive` (if user is unsure about device)
   - Debugging: `nimbus build --verbose` + `nimbus logs`
5. **Suggest configuration** if user frequently specifies same options
6. **Recommend --interactive** for first-time users or when device selection is unclear

---

## Quick Reference

| Task | Command |
|------|---------|
| Build project | `nimbus build` |
| Run on simulator | `nimbus run` |
| Pick device interactively | `nimbus run --interactive` |
| Stream app logs | `nimbus logs` |
| List simulators | `nimbus devices` |
| Run tests | `nimbus test` |
| Clean build | `nimbus clean` |
| Setup config | `nimbus init` |
| Debug build issues | `nimbus build --verbose` |
| Run on specific device | `nimbus run --device "iPhone 17"` |

---

## Example Session

```bash
# First time using nimbus in a project
$ cd ~/MyiOSApp
$ nimbus devices
# See available simulators...

$ nimbus run --interactive
# Select device from menu...

# App builds and launches
# In another terminal:
$ nimbus logs
# See real-time logs

# Make code changes, rebuild
$ nimbus run
# Uses same device as before (or smart fallback)

# Before committing, run tests
$ nimbus test

# All good!
```
