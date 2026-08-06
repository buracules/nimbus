#!/bin/bash
#
# Action (⌘): screenshot the simulator pinned to the selected project.
#
# The destination is the workflow variable `screenshot_dir`, defaulting to the
# Desktop. nimbus's own default is the working directory, and the working
# directory here is the user's project — dropping PNGs into a source tree is not
# what someone pressing a hotkey wants.
#
# Foreground, and it stays that way: a screenshot is over before a notification
# could say it had begun, so there is nothing to watch.
#
# Run it directly the way Alfred would:
#   projectRoot=/path/to/project ./action-screenshot.sh

set -u
cd "$(dirname "$0")" || exit 1
# shellcheck source=lib.sh
. ./lib.sh

run_log_begin "screenshot" "${projectName:-}"

action_require_tools || finish fail "$ACTION_ERROR"
require_project_root || finish fail "$ACTION_ERROR"

dest_dir="${screenshot_dir:-$HOME/Desktop}"
mkdir -p "$dest_dir" 2>/dev/null
dest="$dest_dir/nimbus-screenshot-$(date +%Y%m%d-%H%M%S).png"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

envelope="$(cd "$projectRoot" && "$NIMBUS" sim screenshot --json "$dest" 2>"$scratch/err")"

run_log_section "nimbus sim screenshot --json (stdout)" "$envelope"
run_log_section "nimbus narration (stderr)" "$(cat "$scratch/err" 2>/dev/null)"

if [ "$(envelope_field "$envelope" '.ok')" != "true" ]; then
    REC_EXIT="$(envelope_field "$envelope" '.error.exitCode')"
    REC_DIAGNOSTICS="$(envelope_field "$envelope" '(.error.diagnostics // [])[]')"
    finish fail "$(envelope_error_line "$envelope" "nimbus sim screenshot failed and said nothing readable")"
fi

path="$(envelope_field "$envelope" '.data.file.path')"
device="$(envelope_field "$envelope" '.data.resolution.device.name')"
REC_DEVICE="$device"

finish ok "Screenshot of ${device:-the simulator} saved to ${path:-$dest}"
