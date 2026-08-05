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

action_require_tools || exit 0
require_project_root || exit 0

if [ -z "${useDevice:-}" ]; then
    echo "No simulator was chosen."
    exit 0
fi

if [ -n "${useOS:-}" ]; then
    envelope="$(cd "$projectRoot" && "$NIMBUS" use "$useDevice" --os "$useOS" --json 2>/dev/null)"
else
    envelope="$(cd "$projectRoot" && "$NIMBUS" use "$useDevice" --json 2>/dev/null)"
fi

if [ "$(envelope_field "$envelope" '.ok')" != "true" ]; then
    echo "$(envelope_error_line "$envelope" "nimbus use failed and said nothing readable")"
    exit 0
fi

device="$(envelope_field "$envelope" '.data.device')"
os="$(envelope_field "$envelope" '.data.os')"
name="${projectName:-$(basename "$projectRoot")}"

if [ -n "$os" ]; then
    echo "$name is pinned to $device (OS $os)"
else
    echo "$name is pinned to $device"
fi
