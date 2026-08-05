#!/bin/bash
#
# Action: build, install and launch the selected project.
#
# Runs in the foreground so that Alfred's Post Notification object fires when it
# finishes. Alfred's window closes the moment the row is actioned, so nothing
# looks frozen; this script's single line of stdout becomes the notification.
#
# Always exits 0. A non-zero exit makes Alfred report its own failure instead of
# the one nimbus explained, and nimbus's explanation is the better one.
#
# Run it directly the way Alfred would:
#   projectRoot=/path/to/project ./action-run.sh

set -u
cd "$(dirname "$0")" || exit 1
# shellcheck source=lib.sh
. ./lib.sh

action_require_tools || exit 0
require_project_root || exit 0

# The working directory is the whole mechanism for passing project context.
# There is no --project flag because this is the ruled way to say it.
envelope="$(cd "$projectRoot" && "$NIMBUS" run --json 2>/dev/null)"

if [ "$(envelope_field "$envelope" '.ok')" != "true" ]; then
    echo "$(envelope_error_line "$envelope" "nimbus run failed and said nothing readable")"
    exit 0
fi

device="$(envelope_field "$envelope" '.data.resolution.device.name')"
bundle="$(envelope_field "$envelope" '.data.app.bundleID')"
seconds="$(envelope_field "$envelope" '.data.build.duration | floor')"

echo "Launched ${bundle:-the app} on ${device:-the simulator} · built in ${seconds:-?}s"
