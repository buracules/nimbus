#!/bin/bash
#
# The process that actually performs `nimbus run`, detached from Alfred.
#
# `nimbus run` on a real project is minutes of work. Alfred's window closes the
# moment a Run Script action starts, so a foreground action can only ever report
# at the end — which is what made pressing ↵ look like it did nothing. Running
# detached means the Alfred window can stay open on a Script Filter and watch
# this process instead.
#
# Ownership, which is the whole reason this is a separate file:
#
#   * This process owns the run record at <state>/runs-state/<key>.json. It
#     writes `phase: running` as its first act and the finished record as its
#     last, and nothing else ever writes that file. run-status.sh reads it.
#   * run-status.sh owns the PID file — "the run I started for this project".
#     It is a handle, not a second opinion about whether a run exists.
#   * nimbus owns the build. Everything here is presentation and bookkeeping.
#
# It is never run by Alfred directly. run-status.sh starts it, in its own
# process group, with every stream pointed away from Alfred.
#
# Run it directly the way run-status.sh would:
#   projectRoot=/path/to/project projectName=thing ./run-detached.sh

set -u
cd "$(dirname "$0")" || exit 1
# shellcheck source=lib.sh
. ./lib.sh

[ -n "${projectRoot:-}" ] || exit 1

name="${projectName:-}"
[ -n "$name" ] || name="${projectRoot##*/}"

run_log_begin "run" "$name"

state_dir="$(run_state_dir)" || state_dir=""
record=""
if [ -n "$state_dir" ]; then
    record="$state_dir/$(project_key "$projectRoot").json"
fi

# --- announce that the work has started -------------------------------------
#
# Written before nimbus is invoked, so the filter's first re-read has something
# true to show. A record that appeared only once the build finished would leave
# the window with nothing to say for the minutes that matter.

REC_PHASE="running"
REC_OK="false"
REC_ACTION="run"
REC_ROOT="$projectRoot"
REC_NAME="$name"
REC_DEVICE="${projectDevice:-}"
REC_STARTED="$RUN_LOG_STARTED"
REC_FINISHED=""
REC_HEADLINE="Building $name…"
REC_MESSAGE="Building $name…"
REC_LOG="$RUN_LOG"
REC_EXIT=""
# Stated in the record so a reader that holds no handle on this process — the
# projects list, which sees only last-run.json — can still tell a run that is
# happening from one that stopped without saying so.
REC_PID="$$"
REC_DIAGNOSTICS=""

[ -n "$record" ] && record_write "$record"
record_publish_last

# --- do the work ------------------------------------------------------------

if ! action_require_tools; then
    headline="$ACTION_ERROR"
    REC_MESSAGE="$ACTION_ERROR"
    ok="false"
else
    scratch="$(mktemp -d)"
    trap 'rm -rf "$scratch"' EXIT

    # The working directory is the whole mechanism for passing project context.
    # There is no --project flag because this is the ruled way to say it.
    #
    # stderr is kept rather than discarded: under --json nimbus moves everything
    # a human would have read to stderr, so this is the narration of the build,
    # and a log that threw it away would be a log of one JSON object.
    envelope="$(cd "$projectRoot" && "$NIMBUS" run --json 2>"$scratch/err")"
    stderr="$(cat "$scratch/err" 2>/dev/null)"

    run_log_section "nimbus run --json (stdout)" "$envelope"
    run_log_section "nimbus narration (stderr)" "$stderr"

    if [ "$(envelope_field "$envelope" '.ok')" = "true" ]; then
        ok="true"
        device="$(envelope_field "$envelope" '.data.resolution.device.name')"
        bundle="$(envelope_field "$envelope" '.data.app.bundleID')"
        seconds="$(envelope_field "$envelope" '.data.build.duration | floor')"
        [ -n "$device" ] && REC_DEVICE="$device"
        headline="Launched ${bundle:-the app} on ${device:-the simulator} · built in ${seconds:-?}s"
        REC_MESSAGE="$headline"
    else
        ok="false"
        headline="$(envelope_error_line "$envelope" "nimbus run failed and said nothing readable")"
        # The headline leads with the compiler; the message is nimbus's own
        # summary. The window shows the summary and the diagnostics as separate
        # rows, so it needs them apart rather than run together.
        REC_MESSAGE="$(envelope_field "$envelope" '.error.message')"
        [ -n "$REC_MESSAGE" ] || REC_MESSAGE="$headline"
        REC_EXIT="$(envelope_field "$envelope" '.error.exitCode')"
        # The compiler's actual words, in the order it said them. This is the
        # part that has been produced and dropped until now.
        REC_DIAGNOSTICS="$(envelope_field "$envelope" '(.error.diagnostics // [])[]')"
    fi
fi

# --- report -----------------------------------------------------------------

REC_PHASE="done"
REC_OK="$ok"
REC_FINISHED="$(date +%s)"
REC_HEADLINE="$headline"

{
    printf -- '--- result ---\n'
    printf '%s: %s\n' "$([ "$ok" = "true" ] && echo ok || echo fail)" "$headline"
    printf '# finished: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
} >> "$RUN_LOG" 2>/dev/null

[ -n "$record" ] && record_write "$record"
record_publish_last

# --- the backstop -----------------------------------------------------------
#
# The Alfred window is the primary channel and it shows all of this live. This
# notification is for the case where it was dismissed: ↵, Escape, go and do
# something else.
#
# Alfred's own notifier rather than `osascript -e 'display notification'`,
# reached through an external trigger. An osascript banner is attributed to
# Script Editor and is silently suppressed if that application is not allowed to
# notify; Alfred is already permitted. `open -g` fires the trigger without
# bringing Alfred to the front, and needs no automation permission.
if have_jq; then
    text="$headline"
    [ "$ok" = "true" ] || text="$headline
Full output: the “Last run” row under the nim keyword"
    encoded="$(printf '%s' "$text" | jq -sRr @uri 2>/dev/null)"
    if [ -n "$encoded" ]; then
        /usr/bin/open -g \
            "alfred://runtrigger/${alfred_workflow_bundleid:-co.ustun.nimbus}/run-finished/?argument=$encoded" \
            >/dev/null 2>&1
    fi
fi

exit 0
