# Core returns values; callers narrate

2026-08-05 — landed in `8665a06`

## The rule

Core decides what happened. Callers decide what the user is told. Core types
return values that describe the outcome — `DeviceResolution`, `BuildResult` —
and every line a command might print is derivable from those fields.

The checkable form: nothing in `Sources/nimbus/Core/` imports `ArgumentParser`,
and nothing in `Core/` writes to the terminal. `CoreBoundaryTests` enforces both.

## Why not a reporter protocol

The obvious correction — hand core a reporter or a progress delegate to call —
was considered and rejected. A reporter lets core keep deciding what the user is
told while appearing decoupled. It adds a layer of indirection whose effect is to
preserve the exact ownership confusion the split existed to remove.

This is the part worth remembering, because a reporter protocol is what anyone
will propose next time core "needs to say something."

## What future changes must respect

If core needs to communicate something, it returns a field. Not a closure, not a
delegate, not a protocol with an `info(_:)` method. Adding any of those reopens
this decision, and the boundary tests will fail rather than let it happen
quietly.

The `--json` envelope follows from the same rule: it is composed of the types
core already returns, so there is no second model of nimbus's facts drifting
away from the first.
