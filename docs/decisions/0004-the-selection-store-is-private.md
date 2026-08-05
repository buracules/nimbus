# The pinned-simulator store is private; the CLI verb is the contract

2026-08-05 — landed in `5068ac2`

## The rule

`nimbus use` and `nimbus projects` are the interface to a project's pinned
simulator. **No program other than nimbus reads or writes the file behind them.**
A consumer with no working directory — the menu bar app of
[0003](0003-companion-app-is-a-menu-bar-app.md), an Alfred workflow, a script —
runs `nimbus use --json` or `nimbus projects --json` and parses the envelope.

Its path, its layout and its file naming are therefore not published anywhere,
including in the README. That omission is deliberate; it is not an oversight to
be tidied up.

## The alternative that was rejected

Letting those consumers read the file directly. It is one `JSONDecoder` away and
saves a process spawn.

What it costs: an out-of-repo reader freezes the layout, the key derivation, the
write atomicity and the staleness policy across implementations that cannot be
deployed in one commit. Every later change to how nimbus remembers a project
becomes a migration negotiated with programs that ship on their own schedule —
to buy a few milliseconds on a path a human triggers by hand.

This is the decision that erodes, because reading a JSON file is obviously
easier than spawning a process, and it will be proposed again. It is also the
half of 0003's "shells out rather than links" that 0003 recorded as missing.

## What future changes must respect

- Anything an external consumer needs to know is a field in a `--json` envelope,
  or it does not exist. Adding a documented path is the same decision as adding
  a public API.
- The store holds **inputs to** device resolution, never **results of** it. The
  worked example is the stored device name versus its UDID — a UDID is a result,
  and persisting it creates a second resolution path around `DeviceResolver`.
  The reasoning lives on `StoredSelection`, where anyone adding a field will hit
  it.
- There is no "current project" pointer in nimbus, and so no `--project` flag.
  Which project is current is the app's UI state; the app sets the working
  directory of the process it spawns. A `--project` flag would put a second,
  divergent answer to "which project" inside the CLI, and every command that
  resolves one would have to honour it.

## Two things that are not settled

**The project key deviates from the written ruling.** The ruling said key
derivation should prefer the directory holding `nimbus.yml`. The implementation
is nearest-marker-wins: a monorepo with a shared config on top and two apps below
gets two project roots, not one. The departure is deliberate and tested, on the
same reasoning that gives two git worktrees two pins. Confidence is medium and
reversing it is cheap — it is one walk, in `ProjectIdentity`. Treat it as a
position, not as settled law.

**A `nimbus.yml` naming a bare file name still resolves against the caller's
cwd.** A project with no `nimbus.yml` now builds from a subdirectory; a project
whose `nimbus.yml` says `workspace: MyApp.xcworkspace` does not, because that
value is passed through as written. Fixing it means redefining an existing
user-facing field as relative to the config file's directory, and the file's
location is gone by the time `ConfigLoader` merges the layers — so the fix is a
provenance change, not a path change. This is recorded as open. Nobody has
decided it.
