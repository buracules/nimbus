# Simulator window following: measured, then dropped

2026-08-05 — no code in this repository; a proof-of-concept was built outside it
and discarded.

## The decision

nimbus does not follow the Simulator's window — no overlay, no attaching a
control surface to a particular simulator window.

## The kill rule, written before the evidence arrived

If automatic window-to-device identification could not reliably distinguish one
simulator from another, following was out of scope. The rule was fixed first so
the measurement could not be argued with afterwards.

## What the proof-of-concept found

Window titles carry the device name, but reading them requires Screen Recording
permission.

The permission-free route was to match live window centres against Simulator's
persisted per-UDID geometry preferences. It identified the right device 3/3 on
one run and 2/3 twenty minutes later, and the stored preferences already
contained a real collision — two devices with the same recorded geometry. So the
failure mode is not "it cannot find the window." It is **attaching to the wrong
device without saying so**, which is worse than not shipping the feature.

That, and not the permission prompt, is why this is dead.

## What is still true, if anyone revisits

- Geometry *tracking* is cheap and unproblematic: no permission, 60 Hz polling,
  p50 lag 16 ms, 0.4–1.6% CPU, roughly 146 lines. Tracking was never the hard
  part; identification was.
- TCC grants survive rebuilds only with a stable self-signed identity. A
  permission-gated build that re-prompts every rebuild is a signing problem, not
  a macOS one.
- The Accessibility route was **never run**. "AX versus polling" is unmeasured.
  Do not cite it as decided either way.

## The reopening that changed nothing

The owner has since said permission prompts are acceptable, since the tool is
for himself. That legitimately reopens the Screen Recording path — and the
outcome still stands, because the menu bar controller (see
[0003](0003-companion-app-is-a-menu-bar-app.md)) removes the need to identify a
window at all. It deletes the edge case rather than solving it.

Reviving window following therefore requires a new answer to *identification*,
not a new answer to *permission*.
