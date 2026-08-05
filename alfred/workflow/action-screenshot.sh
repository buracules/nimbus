#!/bin/bash
#
# Action (⌘): screenshot the simulator pinned to the selected project.
#
# The destination is the workflow variable `screenshot_dir`, defaulting to the
# Desktop. nimbus's own default is the working directory, and the working
# directory here is the user's project — dropping PNGs into a source tree is not
# what someone pressing a hotkey wants.
#
# Run it directly the way Alfred would:
#   projectRoot=/path/to/project ./action-screenshot.sh

set -u
cd "$(dirname "$0")" || exit 1
# shellcheck source=lib.sh
. ./lib.sh

action_require_tools || exit 0
require_project_root || exit 0

dest_dir="${screenshot_dir:-$HOME/Desktop}"
mkdir -p "$dest_dir" 2>/dev/null
dest="$dest_dir/nimbus-screenshot-$(date +%Y%m%d-%H%M%S).png"

envelope="$(cd "$projectRoot" && "$NIMBUS" sim screenshot --json "$dest" 2>/dev/null)"

if [ "$(envelope_field "$envelope" '.ok')" != "true" ]; then
    echo "$(envelope_error_line "$envelope" "nimbus sim screenshot failed and said nothing readable")"
    exit 0
fi

path="$(envelope_field "$envelope" '.data.file.path')"
device="$(envelope_field "$envelope" '.data.resolution.device.name')"

echo "Screenshot of ${device:-the simulator} saved to ${path:-$dest}"
