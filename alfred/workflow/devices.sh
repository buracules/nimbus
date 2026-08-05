#!/bin/bash
#
# Script Filter: the simulators on this machine, for a project chosen upstream.
#
# Reached with ⌘⌥ from the projects filter. `projectRoot` arrives as an
# environment variable because Alfred passes an item's variables down the chain;
# actioning a row here runs `nimbus use` with that directory as the working
# directory.
#
# About --os: a pin stores the device name, and only stores an OS version when
# one is given. Two runtimes can both contain "iPhone 17 Pro", and in that case
# a name-only pin would not say which row was picked — so the OS goes in exactly
# when the name is ambiguous, and the row's subtitle says which it is doing.
#
# About the ✓: it marks the simulator that is in effect *now*, which is a
# different question from which name is stored. A name-only pin matches a name
# under several runtimes, so marking by name would tick four rows and tell the
# user nothing. `nimbus use` already answers the real question, so it is asked.
#
# Run it directly to see what Alfred sees:
#   projectRoot=/path/to/project projectDevice="iPhone 17 Pro" ./devices.sh | jq .

set -u
cd "$(dirname "$0")" || exit 1
# shellcheck source=lib.sh
. ./lib.sh

sf_require_tools || exit 0

if [ -z "${projectRoot:-}" ]; then
    sf_message "No project selected" \
        "Open the nimbus workflow with its keyword and pick a project first."
    exit 0
fi

# Two questions, two commands, asked at once so the picker still opens in about
# the time one of them takes: what simulators exist, and which one this project
# would use right now.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

"$NIMBUS" devices --json >"$scratch/devices" 2>/dev/null &
devices_pid=$!
( cd "$projectRoot" 2>/dev/null && "$NIMBUS" use --json ) >"$scratch/use" 2>/dev/null &
use_pid=$!
wait "$devices_pid" 2>/dev/null
wait "$use_pid" 2>/dev/null

envelope="$(cat "$scratch/devices")"

# The effective simulator is a nicety on top of the list. If nimbus could not
# answer — the directory moved, this machine has no simulators — the list is
# still correct and simply carries no ✓.
effective_udid="$(jq -r 'select(.ok == true) | .data.resolution.device.udid // empty' "$scratch/use" 2>/dev/null)"
effective_source="$(jq -r 'select(.ok == true) | .data.source // empty' "$scratch/use" 2>/dev/null)"

if [ -z "$envelope" ] || ! printf '%s' "$envelope" | jq -e . >/dev/null 2>&1; then
    sf_message "nimbus did not answer" \
        "'nimbus devices --json' produced nothing readable. Try running it in a terminal."
    exit 0
fi

if [ "$(printf '%s' "$envelope" | jq -r '.ok')" != "true" ]; then
    sf_message "nimbus devices failed" "$(envelope_error_line "$envelope" "Unknown error")"
    exit 0
fi

if [ "$(printf '%s' "$envelope" | jq -r '[.data.runtimes[]?.devices[]?] | length')" = "0" ]; then
    sf_message "No simulators on this machine" \
        "Open Xcode and install a simulator runtime, then come back."
    exit 0
fi

projectName="${projectName:-$(basename "$projectRoot")}"

printf '%s' "$envelope" | jq \
    --arg root "$projectRoot" \
    --arg name "$projectName" \
    --arg effective "$effective_udid" \
    --arg source "$effective_source" \
    '
    # How many runtimes contain a device with each name. Anything above one is
    # ambiguous by name alone.
    ( [ .data.runtimes[].devices[].name ]
      | group_by(.)
      | map({ key: .[0], value: length })
      | from_entries ) as $counts

    | { items: [ .data.runtimes[]
        | .name as $runtime
        | (($runtime | split(" ") | last) // "") as $version
        # Only trust a version we can read as digits and dots; otherwise pin the
        # name alone rather than hand nimbus an --os it cannot match.
        | (if ($version | test("^[0-9]+(\\.[0-9]+)*$")) then $version else "" end) as $os
        | .devices[]
        | .name as $device
        | (($counts[$device] // 1) > 1) as $ambiguous
        | (if $ambiguous then $os else "" end) as $useOS
        | ($effective != "" and .udid == $effective) as $inEffect
        | {
            title: (if $inEffect then "✓ " + $device else $device end),
            subtitle: (
                $runtime
                + " · " + .state
                + (if $useOS != "" then " · pins " + $device + " at OS " + $useOS
                   elif $ambiguous then " · pins " + $device + " by name only — this runtime has no version to pin to"
                   else " · pins " + $device end)
                + (if $inEffect then " · in effect now (from " + $source + ")" else "" end)
            ),
            match: ($device + " " + $runtime),
            arg: $device,
            valid: true,
            variables: {
                projectRoot: $root,
                projectName: $name,
                useDevice: $device,
                useOS: $useOS
            }
          }
      ] }
    '
