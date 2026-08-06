#!/bin/bash
#
# Action (⌥): start a screen recording, or stop the one already running.
#
# `nimbus sim record` records until it is interrupted; there is no stop verb, so
# the toggle needs a handle on the process it started. That handle is a PID file
# in this workflow's own cache directory.
#
# What owns what:
#
#   * nimbus owns the recording. It starts simctl, forwards the interrupt and
#     writes the movie.
#   * this script owns nothing but a *handle* — "the process I started for this
#     project". It is not a second opinion about whether a recording exists; if
#     the process is gone, the handle is wrong and gets thrown away.
#   * simctl owns whether a second recording on one simulator is allowed. Two
#     projects pinned to the same simulator can therefore collide, and simctl
#     says so; that failure surfaces in the notification rather than being
#     guessed at here.
#
# Concurrency: a double-fire of the hotkey would otherwise read the PID file,
# both branches decide "not running", and start two recordings — one of them
# unstoppable. `mkdir` is atomic, so it is the mutex.
#
# Recovery after a crash or a reboot: a PID file whose process is gone is a
# stale handle. It is removed and the invocation is treated as a start.
#
# Run it directly the way Alfred would:
#   projectRoot=/path/to/project ./action-record.sh     # start
#   projectRoot=/path/to/project ./action-record.sh     # stop

set -u
cd "$(dirname "$0")" || exit 1
# shellcheck source=lib.sh
. ./lib.sh

run_log_begin "record" "${projectName:-}"

action_require_tools || finish fail "$ACTION_ERROR"
require_project_root || finish fail "$ACTION_ERROR"

STATE_DIR="$(workflow_state_dir)" || finish fail "Alfred's cache directory for this workflow could not be created, so a recording cannot be tracked."

# One set of state files per project. The key is hashed because a path contains
# slashes; see project_key in lib.sh. These live in the cache root while a run's
# state lives in runs-state/, so the two never share a filename.
KEY="$(project_key "$projectRoot")"
PID_FILE="$STATE_DIR/$KEY.pid"
OUT_FILE="$STATE_DIR/$KEY.out"
ERR_FILE="$STATE_DIR/$KEY.err"
DEST_FILE="$STATE_DIR/$KEY.dest"
LOCK_DIR="$STATE_DIR/$KEY.lock"

# --- the mutex --------------------------------------------------------------

acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        return 0
    fi
    # A lock older than the longest thing that legitimately holds it was left
    # behind by something that died. Break it once, then give up.
    if [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +3 2>/dev/null)" ]; then
        rmdir "$LOCK_DIR" 2>/dev/null
        mkdir "$LOCK_DIR" 2>/dev/null && return 0
    fi
    return 1
}

acquire_lock || finish fail "Another recording action is already running for this project."
trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

# --- is the handle still good? ----------------------------------------------

# True when the PID is alive *and* is still the nimbus we started.
#
# PIDs are recycled. Between one press of the hotkey and the next, the number in
# that file can belong to something else entirely, and `kill -INT` on a stranger
# is the one mistake here that damages something outside this workflow.
recording_is_alive() {
    local pid="$1" comm
    [ -n "$pid" ] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    comm="$(ps -o comm= -p "$pid" 2>/dev/null)"
    case "$comm" in
        "$NIMBUS"|*/nimbus|nimbus) return 0 ;;
        *)                         return 1 ;;
    esac
}

clear_handle() {
    rm -f "$PID_FILE" "$DEST_FILE"
}

pid=""
[ -f "$PID_FILE" ] && pid="$(cat "$PID_FILE" 2>/dev/null)"

# --- stop -------------------------------------------------------------------

if recording_is_alive "$pid"; then
    # nimbus forwards the interrupt to simctl and then writes the movie, so the
    # movie only exists if the process is asked to stop rather than killed.
    kill -INT "$pid" 2>/dev/null

    waited=0
    while recording_is_alive "$pid"; do
        if [ "$waited" -ge 300 ]; then
            finish fail "Asked the recording to stop, but it is still finishing. The movie will appear at $(cat "$DEST_FILE" 2>/dev/null)."
        fi
        sleep 0.2
        waited=$((waited + 1))
    done

    envelope="$(cat "$OUT_FILE" 2>/dev/null)"
    clear_handle
    run_log_section "nimbus sim record --json (stdout)" "$envelope"
    run_log_section "nimbus narration (stderr)" "$(cat "$ERR_FILE" 2>/dev/null)"

    if [ "$(envelope_field "$envelope" '.ok')" = "true" ]; then
        path="$(envelope_field "$envelope" '.data.file.path')"
        device="$(envelope_field "$envelope" '.data.resolution.device.name')"
        REC_DEVICE="$device"
        finish ok "Recording of ${device:-the simulator} saved to ${path:-unknown location}"
    else
        finish fail "$(envelope_error_line "$envelope" "The recording stopped but nimbus reported nothing readable")"
    fi
fi

# --- the handle was stale ---------------------------------------------------

if [ -n "$pid" ]; then
    # The process is gone but the handle survived it: nimbus exited on its own,
    # or the machine restarted mid-recording.
    #
    # When it left an explanation, this press reports it and stops rather than
    # starting a new recording. A recording that died on its own is news, and
    # quietly starting another one would bury it — the next press starts.
    envelope="$(cat "$OUT_FILE" 2>/dev/null)"
    clear_handle
    if [ -n "$envelope" ] && [ "$(envelope_field "$envelope" '.ok')" != "true" ]; then
        run_log_section "the previous recording's last words" "$envelope"
        finish fail "$(envelope_error_line "$envelope" "The previous recording ended unexpectedly")"
    fi
fi

# --- start ------------------------------------------------------------------

dest_dir="${recording_dir:-$HOME/Desktop}"
mkdir -p "$dest_dir" 2>/dev/null
dest="$dest_dir/nimbus-recording-$(date +%Y%m%d-%H%M%S).mov"

: > "$OUT_FILE"
: > "$ERR_FILE"

# Every stream is redirected to a file. Alfred reads a script's stdout until
# EOF, so a background child holding the inherited stdout open would make Alfred
# wait for the whole recording. `exec` in the inner shell means the recorded PID
# is nimbus's own, which is what has to receive the interrupt.
nohup /bin/sh -c 'cd "$1" || exit 1; exec "$2" sim record --json "$3"' \
    _ "$projectRoot" "$NIMBUS" "$dest" \
    >"$OUT_FILE" 2>"$ERR_FILE" </dev/null &
pid=$!

# Written before the liveness check, not after: a crash in between would
# otherwise leave a recording running with nothing able to stop it.
printf '%s' "$pid" > "$PID_FILE"
printf '%s' "$dest" > "$DEST_FILE"
disown "$pid" 2>/dev/null || true

sleep 0.5
if ! recording_is_alive "$pid"; then
    envelope="$(cat "$OUT_FILE" 2>/dev/null)"
    reason="$(envelope_error_line "$envelope" "")"
    [ -n "$reason" ] || reason="$(tail -n 1 "$ERR_FILE" 2>/dev/null)"
    clear_handle
    # simctl refuses a second recording on a simulator that is already being
    # recorded, and nimbus reports that as a bare exit code — it does not carry
    # simctl's own words through. Rather than decode exit numbers here and be
    # wrong about the ones that mean something else, name the usual cause
    # without claiming it is this one.
    run_log_section "nimbus sim record --json (stdout)" "$envelope"
    run_log_section "nimbus narration (stderr)" "$(cat "$ERR_FILE" 2>/dev/null)"
    finish fail "Recording did not start — ${reason:-nimbus exited immediately}. A simulator can only be recorded once at a time; check whether something else is already recording it."
fi

finish ok "Recording to $dest — press ⌥↵ on the same project to stop"
