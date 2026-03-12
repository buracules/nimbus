# Nimbus Claude Skill

A Claude Code skill for building, running, and debugging iOS applications using the nimbus CLI.

## Installation

### Option 1: Symlink from this repository

```bash
# Create symlink to your Claude skills directory
ln -s "$(pwd)/.claude/skills/nimbus" ~/.claude/skills/nimbus
```

### Option 2: Copy to Claude skills directory

```bash
# Copy the skill directory
cp -r .claude/skills/nimbus ~/.claude/skills/
```

### Option 3: Add to your dotfiles

If you manage Claude skills in dotfiles:

```bash
# Copy to your dotfiles
cp -r .claude/skills/nimbus ~/dotfiles/claude-skills/

# Create symlink
ln -s ~/dotfiles/claude-skills/nimbus ~/.claude/skills/nimbus
```

## Usage

Once installed, you can invoke the skill in Claude Code:

```
/nimbus
```

Or just describe what you want to do:
- "Build my iOS app"
- "Run this on the simulator"
- "Show me the logs"
- "Pick a device to run on"
- "Why isn't my app building?"

Claude will automatically use the nimbus skill to help you.

## What It Does

The skill helps Claude understand and use nimbus commands for:

- Building iOS projects
- Running apps on simulators with smart device selection
- Streaming logs in real-time
- Interactive device picking
- Troubleshooting common build issues
- Setting up configuration
- Running tests

## Requirements

- [nimbus CLI](https://github.com/user/nimbus) installed and available in PATH
- Xcode with command line tools
- iOS simulators installed

## Features

- Comprehensive command reference
- Device selection strategies explained
- Common workflows and best practices
- Troubleshooting guide
- Integration tips for Claude Code

## Contributing

If you find ways to improve this skill, please submit a PR or issue!
