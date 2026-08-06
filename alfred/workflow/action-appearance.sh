#!/bin/bash
#
# Action (⌃): toggle the pinned simulator between light and dark.
#
# `nimbus sim appearance` reads with no argument and writes with one, so the
# toggle is a read then a write. nimbus is the authority on the current
# appearance; this script never remembers it between invocations, so it cannot
# drift from what the simulator actually shows.
#
# Run it directly the way Alfred would:
#   projectRoot=/path/to/project ./action-appearance.sh

set -u
cd "$(dirname "$0")" || exit 1
# shellcheck source=lib.sh
. ./lib.sh

run_log_begin "appearance" "${projectName:-}"

action_require_tools || finish fail "$ACTION_ERROR"
require_project_root || finish fail "$ACTION_ERROR"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

current_envelope="$(cd "$projectRoot" && "$NIMBUS" sim appearance --json 2>"$scratch/err")"

run_log_section "nimbus sim appearance --json (stdout)" "$current_envelope"
run_log_section "nimbus narration (stderr)" "$(cat "$scratch/err" 2>/dev/null)"

if [ "$(envelope_field "$current_envelope" '.ok')" != "true" ]; then
    finish fail "$(envelope_error_line "$current_envelope" "Could not read the simulator's appearance")"
fi

current="$(envelope_field "$current_envelope" '.data.appearance')"

# simctl can report something other than light or dark on a device that has no
# opinion yet. Dark is the useful destination from an unknown starting point.
case "$current" in
    dark) next="light" ;;
    *)    next="dark" ;;
esac

envelope="$(cd "$projectRoot" && "$NIMBUS" sim appearance "$next" --json 2>"$scratch/err")"

run_log_section "nimbus sim appearance $next --json (stdout)" "$envelope"
run_log_section "nimbus narration (stderr)" "$(cat "$scratch/err" 2>/dev/null)"

if [ "$(envelope_field "$envelope" '.ok')" != "true" ]; then
    REC_EXIT="$(envelope_field "$envelope" '.error.exitCode')"
    finish fail "$(envelope_error_line "$envelope" "nimbus sim appearance failed and said nothing readable")"
fi

device="$(envelope_field "$envelope" '.data.resolution.device.name')"
applied="$(envelope_field "$envelope" '.data.appearance')"
REC_DEVICE="$device"

finish ok "${device:-Simulator} appearance is now ${applied:-$next}"
