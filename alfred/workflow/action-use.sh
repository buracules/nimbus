#!/bin/bash
#
# Action: pin the chosen simulator to the chosen project.
#
# `useOS` is set by devices.sh only when the device name exists under more than
# one runtime. An empty value means the name alone identifies the simulator, and
# a name-only pin is the more durable one — it keeps working across a runtime
# upgrade.
#
# Run it directly the way Alfred would:
#   projectRoot=/path/to/project useDevice="iPhone 17 Pro" ./action-use.sh
#   projectRoot=/path/to/project useDevice="iPhone 17 Pro" useOS=26.3 ./action-use.sh

set -u
cd "$(dirname "$0")" || exit 1
# shellcheck source=lib.sh
. ./lib.sh

run_log_begin "use" "${projectName:-}"

action_require_tools || finish fail "$ACTION_ERROR"
require_project_root || finish fail "$ACTION_ERROR"

if [ -z "${useDevice:-}" ]; then
    finish fail "No simulator was chosen."
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

if [ -n "${useOS:-}" ]; then
    envelope="$(cd "$projectRoot" && "$NIMBUS" use "$useDevice" --os "$useOS" --json 2>"$scratch/err")"
else
    envelope="$(cd "$projectRoot" && "$NIMBUS" use "$useDevice" --json 2>"$scratch/err")"
fi

run_log_section "nimbus use --json (stdout)" "$envelope"
run_log_section "nimbus narration (stderr)" "$(cat "$scratch/err" 2>/dev/null)"

if [ "$(envelope_field "$envelope" '.ok')" != "true" ]; then
    REC_EXIT="$(envelope_field "$envelope" '.error.exitCode')"
    finish fail "$(envelope_error_line "$envelope" "nimbus use failed and said nothing readable")"
fi

device="$(envelope_field "$envelope" '.data.device')"
os="$(envelope_field "$envelope" '.data.os')"
name="${projectName:-${projectRoot##*/}}"
REC_DEVICE="$device"

if [ -n "$os" ]; then
    finish ok "$name is pinned to $device (OS $os)"
else
    finish ok "$name is pinned to $device"
fi
