#!/bin/bash
#
# Shared helpers for the nimbus Alfred workflow.
#
# What Alfred guarantees when it runs one of these scripts:
#
#   * the working directory is the workflow bundle, so `./lib.sh` resolves;
#   * PATH is /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin,
#     which is where `jq` lives on a Homebrew machine but is *not* where
#     `nimbus` lives, so nimbus is resolved explicitly below;
#   * item and workflow variables arrive as environment variables.
#
# Nothing here reshapes nimbus's facts. Every script calls `nimbus <cmd> --json`
# and turns the envelope into Alfred's own Script Filter JSON. Alfred's format is
# Alfred's contract; it does not belong inside nimbus.

# --- locating the tools -----------------------------------------------------

# Set NIMBUS to the nimbus binary, or set NIMBUS_RESOLVE_ERROR and return 1.
#
# Sets a global rather than printing, so that the reason for a failure survives:
# `X="$(resolve_nimbus)"` would run this in a subshell and the explanation would
# die with it.
#
# `nimbus_bin` is a workflow variable, so a user with nimbus somewhere unusual
# has an escape hatch that does not involve editing these scripts. A `nimbus_bin`
# that is set but wrong is an error, not a reason to search — the search would
# probably find *a* nimbus, and the user would then be debugging the wrong binary
# while their setting sat there being ignored.
resolve_nimbus() {
    NIMBUS=""
    NIMBUS_RESOLVE_ERROR=""

    if [ -n "${nimbus_bin:-}" ]; then
        if [ -x "$nimbus_bin" ]; then
            NIMBUS="$nimbus_bin"
            return 0
        fi
        NIMBUS_RESOLVE_ERROR="The workflow variable nimbus_bin is set to '$nimbus_bin', which is not an executable file."
        return 1
    fi

    local candidate
    for candidate in \
        "$HOME/.local/bin/nimbus" \
        "/opt/homebrew/bin/nimbus" \
        "/usr/local/bin/nimbus" \
        "/usr/bin/nimbus"
    do
        if [ -x "$candidate" ]; then
            NIMBUS="$candidate"
            return 0
        fi
    done

    candidate="$(command -v nimbus 2>/dev/null)"
    if [ -n "$candidate" ]; then
        NIMBUS="$candidate"
        return 0
    fi

    NIMBUS_RESOLVE_ERROR="$NIMBUS_NOT_FOUND_SUBTITLE"
    return 1
}

have_jq() {
    command -v jq >/dev/null 2>&1
}

# --- emitting Script Filter JSON --------------------------------------------

# Escape a string for use inside a JSON string literal.
#
# Deliberately dependency-free: it is used on the paths where jq is the thing
# that is missing, so it cannot use jq. Handles the three characters that
# actually occur in a file path or an error message.
json_escape() {
    printf '%s' "$1" \
        | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
        | awk 'BEGIN { ORS = "" } { print (NR > 1 ? "\\n" : "") $0 }'
}

# Emit a single unactionable Script Filter row. This is how every failure and
# every empty list is reported: a row that says what happened and what to do
# about it, never a blank list.
#
#   sf_message TITLE SUBTITLE [TEXT_TO_COPY]
sf_message() {
    local title subtitle copy
    title="$(json_escape "$1")"
    subtitle="$(json_escape "$2")"
    if [ -n "${3:-}" ]; then
        copy="$(json_escape "$3")"
        printf '{"items":[{"title":"%s","subtitle":"%s","valid":false,"text":{"copy":"%s","largetype":"%s"}}]}\n' \
            "$title" "$subtitle" "$copy" "$copy"
    else
        printf '{"items":[{"title":"%s","subtitle":"%s","valid":false}]}\n' "$title" "$subtitle"
    fi
}

NIMBUS_NOT_FOUND_TITLE="nimbus is not installed where this workflow can find it"
NIMBUS_NOT_FOUND_SUBTITLE="Looked in ~/.local/bin, /opt/homebrew/bin and /usr/local/bin. Set the workflow variable nimbus_bin to an absolute path."

JQ_NOT_FOUND_TITLE="jq is not installed"
JQ_NOT_FOUND_SUBTITLE="This workflow reshapes nimbus's JSON with jq. Install it with: brew install jq"

# Resolve nimbus and jq or emit a Script Filter row explaining which is missing.
# Sets NIMBUS on success.
sf_require_tools() {
    if ! have_jq; then
        sf_message "$JQ_NOT_FOUND_TITLE" "$JQ_NOT_FOUND_SUBTITLE" "brew install jq"
        return 1
    fi
    resolve_nimbus || {
        sf_message "$NIMBUS_NOT_FOUND_TITLE" "$NIMBUS_RESOLVE_ERROR"
        return 1
    }
    return 0
}

# The action-script equivalent. Sets ACTION_ERROR rather than printing it: an
# action's exit has to be routed through `finish` so the log and the record are
# written, and a function that printed the reason itself would have already
# spent the line `finish` needs.
ACTION_ERROR=""

action_require_tools() {
    ACTION_ERROR=""
    if ! have_jq; then
        ACTION_ERROR="jq is not installed. Run: brew install jq"
        return 1
    fi
    resolve_nimbus || {
        ACTION_ERROR="$NIMBUS_RESOLVE_ERROR"
        return 1
    }
    return 0
}

# --- project context --------------------------------------------------------

# The project the upstream Script Filter chose. Alfred has no working directory,
# so this variable *is* the project context, and running nimbus with the child
# process's cwd set to it is the whole mechanism.
require_project_root() {
    ACTION_ERROR=""
    if [ -z "${projectRoot:-}" ]; then
        ACTION_ERROR="No project was selected."
        return 1
    fi
    if [ ! -d "$projectRoot" ]; then
        ACTION_ERROR="That project directory no longer exists: $projectRoot"
        return 1
    fi
    return 0
}

# Read a field out of a nimbus envelope, printing nothing if it is absent.
envelope_field() {
    printf '%s' "$1" | jq -r "$2 // empty" 2>/dev/null
}

# Turn a nimbus envelope into one line of human text for a notification.
# Success is the caller's business; this only handles the failure shape, which
# is identical for every command.
#
# The diagnostic leads. `.error.message` is nimbus's classification — "Build
# failed" — and the caller already knows that much from the ✗. The first
# diagnostic is the compiler's own words, which is the only part that says
# anything the reader did not already have.
envelope_error_line() {
    local envelope="$1" fallback="$2" message diagnostic
    if [ -z "$envelope" ]; then
        printf '%s' "$fallback"
        return
    fi
    message="$(envelope_field "$envelope" '.error.message')"
    if [ -z "$message" ]; then
        printf '%s' "$fallback"
        return
    fi
    diagnostic="$(envelope_field "$envelope" '.error.diagnostics[0]')"
    if [ -n "$diagnostic" ]; then
        printf '%s — %s' "$diagnostic" "$message"
    else
        printf '%s' "$message"
    fi
}

# --- where this workflow keeps its own state --------------------------------
#
# `$alfred_workflow_cache` is Alfred's own answer to "regenerable data for this
# workflow". Everything below is regenerable: delete the directory and the next
# action rebuilds what it needs. Alfred sets the variable but does not promise
# the directory, so it is created on the run that finds it missing.

workflow_state_dir() {
    local dir="${alfred_workflow_cache:-${TMPDIR:-/tmp}/nimbus-alfred}"
    [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || return 1
    printf '%s' "$dir"
}

# A filename-safe key for a project root.
#
# Hashed because a path contains slashes and can be longer than a filename may
# be. `/usr/bin/shasum` by absolute path: /opt/homebrew/bin comes first on
# Alfred's PATH and Homebrew's perl puts its own shasum there.
project_key() {
    printf '%s' "$1" | /usr/bin/shasum -a 256 | cut -c1-16
}

# --- the run log ------------------------------------------------------------
#
# Every action Alfred triggers writes its whole output to a file. A notification
# holds one line; a failed build has more to say than that, and until now the
# rest was produced and then dropped.
#
# Retention is by count, not by age. Age-based expiry has the failure that
# matters here: come back after a fortnight away and every log is gone, which is
# exactly when the question "what did that do?" gets asked. A count keeps the
# same number of answers available regardless of how long the gap was.
#
# The prune runs before the new file is created and keeps RUN_LOG_KEEP-1, so the
# file about to be written can never be the one deleted, and the newest file —
# the one every record points at — is never a candidate.
RUN_LOG_KEEP=40

RUN_LOG=""
RUN_LOG_ACTION=""
RUN_LOG_STARTED=""

run_log_dir() {
    local state
    state="$(workflow_state_dir)" || return 1
    [ -d "$state/runs" ] || mkdir -p "$state/runs" 2>/dev/null || return 1
    printf '%s/runs' "$state"
}

_run_log_prune() {
    local dir="$1" old name
    old="$(/bin/ls -t "$dir" 2>/dev/null | tail -n +"$RUN_LOG_KEEP")"
    [ -n "$old" ] || return 0
    printf '%s\n' "$old" | while IFS= read -r name; do
        [ -n "$name" ] && rm -f -- "$dir/$name"
    done
}

# Open the log for this invocation. Best effort: an unwritable cache directory
# leaves RUN_LOG empty and every logging call below becomes a no-op, because
# failing to record what an action did is not a reason to refuse to do it.
#
#   run_log_begin ACTION [PROJECT_NAME]
run_log_begin() {
    local action="$1" name="${2:-}" dir slug stamp
    RUN_LOG=""
    RUN_LOG_ACTION="$action"
    RUN_LOG_STARTED="$(date +%s)"

    dir="$(run_log_dir)" || return 0
    _run_log_prune "$dir"

    [ -n "$name" ] || name="no-project"
    # Only characters that survive a shell glob and a filename, so the prune
    # above can walk the directory without quoting games.
    slug="$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')"
    stamp="$(date +%Y%m%d-%H%M%S)"

    RUN_LOG="$dir/$stamp-$action-$slug.log"
    {
        printf '# nimbus alfred workflow\n'
        printf '# action:  %s\n' "$action"
        printf '# project: %s\n' "${projectRoot:-(none)}"
        printf '# started: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
        printf '\n'
    } > "$RUN_LOG" 2>/dev/null || RUN_LOG=""
    return 0
}

# Append a labelled block. Used for each envelope and each stderr capture, so a
# reader can tell nimbus's answer from nimbus's narration.
run_log_section() {
    [ -n "$RUN_LOG" ] || return 0
    {
        printf -- '--- %s ---\n' "$1"
        if [ -n "${2:-}" ]; then
            printf '%s\n' "$2"
        else
            printf '(nothing)\n'
        fi
        printf '\n'
    } >> "$RUN_LOG" 2>/dev/null
    return 0
}

# --- the run record ---------------------------------------------------------
#
# One JSON object describing what an action did. It exists so the Alfred window
# can show an outcome without re-running anything, and so a run in progress can
# be watched while it happens.
#
# Two files carry it, and each has exactly one writer:
#
#   * <state>/runs-state/<key>.json — the current or last run *of one project*.
#     Written only by run-detached.sh, which is the process doing the work.
#     run-status.sh reads it and never writes it.
#   * <state>/last-run.json — the most recent action of any kind, for any
#     project. Written by whichever action finished last. "Last writer wins" is
#     not a hazard here; it is the definition of the field.
#
# The shape is stated in exactly one place — `record_write` — so the two writers
# cannot drift.

REC_PHASE="done"          # running | done
REC_OK="false"
REC_ACTION=""
REC_ROOT=""
REC_NAME=""
REC_DEVICE=""
REC_STARTED="0"
REC_FINISHED=""           # empty while running
REC_HEADLINE=""          # the line a human reads first, diagnostic first
REC_MESSAGE=""           # nimbus's own classification, without the diagnostic
REC_LOG=""
REC_EXIT=""               # the underlying tool's exit code, when there was one
REC_PID="0"               # the process writing this record, while phase is running
REC_DIAGNOSTICS=""        # newline-separated, first line first

# Render the REC_* globals and put them at PATH, atomically.
#
# Written by rename so a reader — which may be a filter re-invoked every second —
# sees either the whole old record or the whole new one, never half of either.
#
# Deliberately jq-free: this also runs on the path where jq is the thing that is
# missing, and a record saying "jq is not installed" is the one that matters most
# on that path.
record_write() {
    local target="$1" tmp diagnostics line first=1
    [ -n "$target" ] || return 0

    diagnostics=""
    if [ -n "$REC_DIAGNOSTICS" ]; then
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            if [ "$first" = "1" ]; then first=0; else diagnostics="$diagnostics,"; fi
            diagnostics="$diagnostics\"$(json_escape "$line")\""
        done <<< "$REC_DIAGNOSTICS"
    fi

    tmp="$target.$$"
    {
        printf '{'
        printf '"phase":"%s",' "$REC_PHASE"
        printf '"ok":%s,' "$REC_OK"
        printf '"action":"%s",' "$(json_escape "$REC_ACTION")"
        printf '"projectRoot":"%s",' "$(json_escape "$REC_ROOT")"
        printf '"projectName":"%s",' "$(json_escape "$REC_NAME")"
        printf '"device":"%s",' "$(json_escape "$REC_DEVICE")"
        printf '"started":%s,' "${REC_STARTED:-0}"
        printf '"finished":%s,' "${REC_FINISHED:-null}"
        printf '"headline":"%s",' "$(json_escape "$REC_HEADLINE")"
        printf '"message":"%s",' "$(json_escape "$REC_MESSAGE")"
        printf '"log":"%s",' "$(json_escape "$REC_LOG")"
        printf '"exitCode":%s,' "${REC_EXIT:-null}"
        printf '"pid":%s,' "${REC_PID:-0}"
        printf '"diagnostics":[%s]' "$diagnostics"
        printf '}\n'
    } > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
    mv -f "$tmp" "$target" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
    return 0
}

# Where one project's run state lives: the record, and the handle on the process
# writing it.
run_state_dir() {
    local state
    state="$(workflow_state_dir)" || return 1
    [ -d "$state/runs-state" ] || mkdir -p "$state/runs-state" 2>/dev/null || return 1
    printf '%s/runs-state' "$state"
}

# Point `last-run.json` at whatever just happened.
record_publish_last() {
    local state
    state="$(workflow_state_dir)" || return 0
    record_write "$state/last-run.json"
    return 0
}

# --- how a foreground action ends -------------------------------------------

# Close the log, publish the record, say the one line Alfred turns into a
# notification, and stop.
#
# Every exit from every action goes through here. That is the point: the log and
# the record cannot be forgotten on the path nobody thought about, which is
# always the failing path.
#
#   finish ok|fail "the line the user reads"
#
# Set REC_DIAGNOSTICS and REC_EXIT before calling if the action has them; they
# travel into the record so the Alfred window can show them without re-running
# anything.
finish() {
    local result="$1" headline="$2"

    if [ -n "$RUN_LOG" ]; then
        {
            printf -- '--- result ---\n'
            printf '%s: %s\n' "$result" "$headline"
            printf '# finished: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
        } >> "$RUN_LOG" 2>/dev/null
    fi

    REC_PHASE="done"
    if [ "$result" = "ok" ]; then REC_OK="true"; else REC_OK="false"; fi
    REC_ACTION="${RUN_LOG_ACTION:-unknown}"
    REC_ROOT="${projectRoot:-}"
    REC_NAME="${projectName:-}"
    [ -n "$REC_NAME" ] || REC_NAME="${projectRoot##*/}"
    REC_STARTED="${RUN_LOG_STARTED:-0}"
    REC_FINISHED="$(date +%s)"
    REC_HEADLINE="$headline"
    [ -n "$REC_MESSAGE" ] || REC_MESSAGE="$headline"
    REC_LOG="$RUN_LOG"
    record_publish_last

    printf '%s\n' "$headline"
    # A failure has more behind it than fits in a banner, so the banner says
    # where the rest is. Success does not need the pointer, and adding it there
    # would train the reader to stop reading the line that matters.
    if [ "$result" != "ok" ] && [ -n "$RUN_LOG" ]; then
        printf 'Full output: the “Last run” row under the nim keyword\n'
    fi
    exit 0
}
