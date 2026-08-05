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

action_require_tools || exit 0
require_project_root || exit 0

current_envelope="$(cd "$projectRoot" && "$NIMBUS" sim appearance --json 2>/dev/null)"

if [ "$(envelope_field "$current_envelope" '.ok')" != "true" ]; then
    echo "$(envelope_error_line "$current_envelope" "Could not read the simulator's appearance")"
    exit 0
fi

current="$(envelope_field "$current_envelope" '.data.appearance')"

# simctl can report something other than light or dark on a device that has no
# opinion yet. Dark is the useful destination from an unknown starting point.
case "$current" in
    dark) next="light" ;;
    *)    next="dark" ;;
esac

envelope="$(cd "$projectRoot" && "$NIMBUS" sim appearance "$next" --json 2>/dev/null)"

if [ "$(envelope_field "$envelope" '.ok')" != "true" ]; then
    echo "$(envelope_error_line "$envelope" "nimbus sim appearance failed and said nothing readable")"
    exit 0
fi

device="$(envelope_field "$envelope" '.data.resolution.device.name')"
applied="$(envelope_field "$envelope" '.data.appearance')"

echo "${device:-Simulator} appearance is now ${applied:-$next}"
