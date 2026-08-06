#!/bin/bash
#
# Action (⌘⌃): stream the app's console output, in a terminal.
#
# `nimbus logs` and `nimbus run --logs` refuse `--json` by design — a log stream
# and a JSON envelope cannot share stdout — so there is no envelope to reshape
# into rows, and nothing here tries to invent one. A stream wants somewhere it
# can keep arriving, be scrolled back through and be interrupted, and that is a
# terminal. Alfred already knows which terminal the user uses; this hands the
# command to Alfred's Terminal Command object and lets it decide where.
#
# The command is built here rather than written into the Terminal Command object
# because the object cannot resolve nimbus. This workflow looks in ~/.local/bin
# and honours the nimbus_bin variable, and a terminal spawned by Alfred would
# only see the login PATH.
#
# This prints a shell command, not a sentence. Every path out of it, including
# every failure, therefore has to be a runnable command — a bare error message
# would be executed and the user would see the shell complain about it instead
# of reading it.
#
# Run it directly the way Alfred would:
#   projectRoot=/path/to/project ./action-logs.sh

set -u
cd "$(dirname "$0")" || exit 1
# shellcheck source=lib.sh
. ./lib.sh

# Single-quote for the shell: wrap, and end/escape/restart around each quote.
shell_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

say() {
    printf 'printf %s\n' "$(shell_quote "$1"$'\n')"
    exit 0
}

if ! resolve_nimbus; then
    say "$NIMBUS_RESOLVE_ERROR"
fi

if [ -z "${projectRoot:-}" ]; then
    say "No project was selected."
fi

if [ ! -d "$projectRoot" ]; then
    say "That project directory no longer exists: $projectRoot"
fi

# cd into the project because the working directory is how this workflow says
# which project it means, and the terminal the user lands in should be sitting
# in that project too — the next thing they type will almost always want it.
printf 'cd %s && %s logs\n' "$(shell_quote "$projectRoot")" "$(shell_quote "$NIMBUS")"
