#!/bin/bash
#
# Script Filter: the projects that have a simulator pinned to them.
#
# Alfred has no working directory and no idea what a project is, which is
# exactly why `nimbus projects` and `nimbus use` exist. This filter is the entry
# point: pick a project here, and every downstream action runs nimbus with its
# child process's working directory set to that project's root.
#
# Alfred filters the rows itself (alfredfiltersresults), so this runs once per
# invocation rather than once per keystroke.
#
# Run it directly to see what Alfred sees:
#   ./projects.sh | jq .

set -u
cd "$(dirname "$0")" || exit 1
# shellcheck source=lib.sh
. ./lib.sh

sf_require_tools || exit 0

envelope="$("$NIMBUS" projects --json 2>/dev/null)"

if [ -z "$envelope" ] || ! printf '%s' "$envelope" | jq -e . >/dev/null 2>&1; then
    sf_message "nimbus did not answer" \
        "'nimbus projects --json' produced nothing readable. Try running it in a terminal."
    exit 0
fi

if [ "$(printf '%s' "$envelope" | jq -r '.ok')" != "true" ]; then
    sf_message "nimbus projects failed" \
        "$(envelope_error_line "$envelope" "Unknown error")"
    exit 0
fi

count="$(printf '%s' "$envelope" | jq -r '.data.projects | length')"

# The empty case is the first thing a new user sees, so it says what to do
# rather than showing nothing. The suggested command names a simulator that
# actually exists on this machine, so copying it produces a working command.
if [ "$count" = "0" ]; then
    example="$("$NIMBUS" devices --json 2>/dev/null \
        | jq -r '[.data.runtimes[]?.devices[]?.name] | first // empty' 2>/dev/null)"
    [ -n "$example" ] || example="iPhone 17 Pro"
    sf_message "No projects have a pinned simulator yet" \
        "cd into an Xcode project and run: nimbus use \"$example\"   (⌘C copies it)" \
        "nimbus use \"$example\""
    exit 0
fi

# Nothing here checks whether a project root still exists. `nimbus projects`
# already drops entries whose directory is gone, and re-deriving that would be a
# second opinion about a fact nimbus states. The race it leaves — a directory
# deleted between this list and the keypress — belongs to the action scripts,
# which check before they run anything.
printf '%s' "$envelope" | jq \
    --arg home "$HOME" \
    --arg shotdir "${screenshot_dir:-$HOME/Desktop}" \
    '
    def shorten($p):
        if ($p | startswith($home + "/")) then "~" + $p[($home | length):] else $p end;

    { items: (.data.projects | map(
        .projectRoot as $root
        | .device as $device
        | (.os | if . then " (OS " + . + ")" else "" end) as $ostag
        | (($root | split("/") | last) // $root) as $name
        | ({ projectRoot: $root, projectName: $name, projectDevice: $device }) as $vars
        | {
            title: $name,
            subtitle: ("Build and run on " + $device + $ostag + "  ·  " + shorten($root)),
            match: ($name + " " + $root + " " + $device),
            arg: $root,
            valid: true,
            variables: $vars,
            quicklookurl: $root,
            text: {
                copy: $root,
                largetype: ($name + "\n" + $root + "\n" + $device + $ostag)
            },
            # A modifier per hot action, rather than a keyword per verb. The
            # subtitles are where they are discoverable: Alfred shows each one
            # while its key is held.
            mods: {
                cmd: {
                    subtitle: ("Screenshot " + $device + " → " + shorten($shotdir)),
                    arg: $root,
                    variables: $vars
                },
                alt: {
                    subtitle: ("Start or stop recording " + $device),
                    arg: $root,
                    variables: $vars
                },
                ctrl: {
                    subtitle: ("Toggle light / dark on " + $device),
                    arg: $root,
                    variables: $vars
                },
                "cmd+alt": {
                    subtitle: ("Change the simulator pinned to " + $name),
                    arg: $root,
                    variables: $vars
                }
            }
          }
      )) }
    '
