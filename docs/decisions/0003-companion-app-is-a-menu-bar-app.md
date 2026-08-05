# The companion app is a menu bar app, and it is gated

2026-08-05 — not built. This records the shape and the gate, so neither is
rediscovered or quietly skipped.

## The shape, if it is built

A resident menu bar controller holding two pieces of state — the current project
and the target simulator — with four actions: Run, Screenshot, Record,
Appearance. It shells out to the `nimbus` binary rather than linking nimbus as a
library.

Choosing this over a window-attached overlay is what made
[0002](0002-no-simulator-window-following.md) stay decided: a resident panel
never has to work out which simulator window it is looking at.

The reasoning for shelling out rather than linking was not recorded at the time.
If that choice starts to matter, ask rather than reconstruct it.

## The gate

It is not to be built until `nimbus sim` has shipped and had **two weeks of real
use**.

## The pre-registered failure test

After those two weeks: if the panel's Run is not used more often than
`nimbus run` in a terminal, delete the app.

## Why this is written down

The gate is the load-bearing part of the recommendation and the easiest part to
skip. A menu bar app is pleasant to build and answers a question — "do I
actually reach for this?" — that only real use can answer. Building it before
the two weeks does not make the answer arrive sooner; it just makes it more
expensive to accept.
