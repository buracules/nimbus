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

# The action-script equivalent: one line of plain text, which becomes the
# notification body.
action_require_tools() {
    if ! have_jq; then
        echo "jq is not installed. Run: brew install jq"
        return 1
    fi
    resolve_nimbus || {
        echo "$NIMBUS_RESOLVE_ERROR"
        return 1
    }
    return 0
}

# --- project context --------------------------------------------------------

# The project the upstream Script Filter chose. Alfred has no working directory,
# so this variable *is* the project context, and running nimbus with the child
# process's cwd set to it is the whole mechanism.
require_project_root() {
    if [ -z "${projectRoot:-}" ]; then
        echo "No project was selected."
        return 1
    fi
    if [ ! -d "$projectRoot" ]; then
        echo "That project directory no longer exists: $projectRoot"
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
        printf '%s — %s' "$message" "$diagnostic"
    else
        printf '%s' "$message"
    fi
}
