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
# shellcheck source=icons.sh
. ./icons.sh

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

# One icon per project, so the list is scannable by sight rather than by reading.
# This is the only thing here that touches the filesystem beyond nimbus's answer,
# and it is cached and depth-bounded because one of these projects is a 16 GB
# repo — see icons.sh. It cannot fail the list: the worst it returns is an empty
# map, and a project with no entry simply has no icon key.
icons="$(icon_map_for_envelope "$envelope")"
[ -n "$icons" ] || icons='{}'

# The way back to the last thing this workflow did.
#
# A notification is gone the moment it is dismissed, and a build has more to say
# than a banner holds. This row is the door to the log, and it costs nothing to
# open: one shell read of a small file — no fork, no extra jq, nothing added to
# the path this filter is measured on. A cache directory that is missing or a
# record that is not JSON both come out as "no row", which is correct.
last_raw=""
last_file="${alfred_workflow_cache:-${TMPDIR:-/tmp}/nimbus-alfred}/last-run.json"
[ -f "$last_file" ] && last_raw="$(< "$last_file")"

# Is the run that record describes still happening?
#
# This list holds no handle on any run — the project's own view is where
# liveness is properly decided, with a PID file and a check on what that process
# actually is. But a record left saying "running" by a crash or a reboot would
# otherwise make this row claim a build is in progress forever, and that is a lie
# the user has no reason to doubt. `kill -0` is a shell builtin, so asking costs
# nothing on the path this filter is measured on, and the answer is right in
# every case except a recycled PID.
last_pid=""
case "$last_raw" in
    *'"pid":'*) last_pid="${last_raw#*\"pid\":}"; last_pid="${last_pid%%,*}" ;;
esac
last_alive=0
case "$last_pid" in
    ''|0|*[!0-9]*) ;;
    *) kill -0 "$last_pid" 2>/dev/null && last_alive=1 ;;
esac

# Nothing here checks whether a project root still exists. `nimbus projects`
# already drops entries whose directory is gone, and re-deriving that would be a
# second opinion about a fact nimbus states. The race it leaves — a directory
# deleted between this list and the keypress — belongs to the action scripts,
# which check before they run anything.
printf '%s' "$envelope" | jq \
    --arg home "$HOME" \
    --arg shotdir "${screenshot_dir:-$HOME/Desktop}" \
    --arg lastRaw "$last_raw" \
    --argjson lastAlive "$last_alive" \
    --argjson icons "$icons" \
    '
    def shorten($p):
        if ($p | startswith($home + "/")) then "~" + $p[($home | length):] else $p end;

    # Alfred wants {path} for an image and {type: "fileicon", path} for "draw
    # whatever Finder draws". No entry means no icon key at all, which is how
    # Alfred is told to fall back to the workflow icon.
    def icon_for($p):
        ($icons[$p] // {}) as $i
        | if (($i.path // "") == "") then {}
          elif (($i.type // "") == "") then { icon: { path: $i.path } }
          else { icon: { type: $i.type, path: $i.path } }
          end;

    ($lastRaw | try fromjson catch null) as $last

    # The one row that is not a project. `intent` is what the run filter reads
    # to tell "the user asked for this project to be built" from "the user asked
    # to see what already happened" — the same destination, two questions.
    | def last_run_row:
        if $last == null then []
        else
          ($last.phase == "running" and $lastAlive == 1) as $live
          | ($last.phase == "running" and $lastAlive != 1) as $abandoned
          | [ { title: (
                (if $live then "Running now · ⟳ "
                 elif $abandoned or (($last.ok // false) | not) then "Last run · ✗ "
                 else "Last run · ✓ " end)
                + ($last.action // "run")
                + (if ($last.projectName // "") != "" then " on " + $last.projectName else "" end)
              ),
              # The arrow leads so that the one thing this row offers survives a
              # headline long enough to be truncated — which a compiler error,
              # or a saved file path, reliably is.
              subtitle: ("↵ show the whole output   ·   "
                         + (if $abandoned then "It stopped without reporting"
                            else ($last.headline // "") end)),
              match: "last run log output result "
                     + ($last.projectName // "") + " " + ($last.action // ""),
              arg: ($last.log // ""),
              valid: true,
              variables: { intent: "show" },
              icon: (if ($last.ok // false) or $live
                     then { path: "icon.png" }
                     else { path: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns" }
                     end),
              # Every modifier on this row belongs to a project, and this row is
              # not one. Saying so beats firing a screenshot at no project.
              mods: {
                cmd:       { valid: false, subtitle: "Nothing here — this row is a result, not a project" },
                alt:       { valid: false, subtitle: "Nothing here — this row is a result, not a project" },
                ctrl:      { valid: false, subtitle: "Nothing here — this row is a result, not a project" },
                "cmd+alt": { valid: false, subtitle: "Nothing here — this row is a result, not a project" },
                "cmd+ctrl":{ valid: false, subtitle: "Nothing here — this row is a result, not a project" }
              } } ]
        end;

    # A failure, or a run happening right now, is news and goes first. A run that
    # succeeded is history and goes last, out of the way of the project the user
    # actually came here to press.
    (if $last != null and (($last.ok // false) | not) then last_run_row else [] end) as $leading
    | (if $last != null and (($last.ok // false)) then last_run_row else [] end) as $trailing

    | { items: ($leading + (.data.projects | map(
        .projectRoot as $root
        | .device as $device
        | (.os | if . then " (OS " + . + ")" else "" end) as $ostag
        | (($root | split("/") | last) // $root) as $name
        | ({ projectRoot: $root, projectName: $name, projectDevice: $device, intent: "run" }) as $vars
        | icon_for($root) + {
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
                },
                "cmd+ctrl": {
                    subtitle: ("Stream " + $name + " logs in a terminal"),
                    arg: $root,
                    variables: $vars
                }
            }
          }
      )) + $trailing) }
    '
