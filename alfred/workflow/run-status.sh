#!/bin/bash
#
# Script Filter: start a run, then show it happening inside the Alfred window.
#
# This is the ↵ destination of the projects filter. A Script Filter rather than
# a Run Script action for one reason: actioning a row that leads to another
# filter leaves the Alfred window open, and a Run Script closes it. Minutes of a
# closed window with nothing said is what made ↵ look broken.
#
# An intent arrives with every invocation and decides whether anything starts:
#
#   intent=run    a project row was actioned — start a run for it, unless one is
#                 already going
#   intent=show   the "Last run" row was actioned — show what happened, start
#                 nothing
#   intent=watch  this script re-invoking itself; see below
#
# A run starts *only* on intent=run. That is the rule that makes a live view
# safe: Alfred re-invokes this script every second while `rerun` is set, and a
# re-invocation read as "the user asked for a run" would build the project in a
# loop. So every response this script emits carries `variables: {intent: watch}`,
# which Alfred hands back on the re-invocation — a rerun cannot start a build
# because by then it is no longer asking for one.
#
# That round-trip is Alfred's behaviour, not this script's, so it is not the only
# guard; see `just_finished` below for the one that holds if it does not.
#
# `rerun` is emitted only while a run is in flight. Once the record says the run
# finished the key is absent, Alfred stops re-invoking, and this stops costing
# anything.
#
# Deliberately does not source icons.sh and never calls nimbus: this runs once a
# second for as long as a build lasts. It reads one small file and asks the
# kernel whether one process is alive.
#
# Run it directly to see what Alfred sees:
#   projectRoot=/path/to/project intent=run ./run-status.sh | jq .
#   intent=show ./run-status.sh | jq .

set -u
cd "$(dirname "$0")" || exit 1
# shellcheck source=lib.sh
. ./lib.sh

have_jq || {
    sf_message "$JQ_NOT_FOUND_TITLE" "$JQ_NOT_FOUND_SUBTITLE" "brew install jq"
    exit 0
}

intent="${intent:-}"

state="$(workflow_state_dir)" || {
    sf_message "Nowhere to keep this run's state" \
        "Alfred's cache directory for this workflow could not be created."
    exit 0
}
runs_state="$(run_state_dir)" || {
    sf_message "Nowhere to keep this run's state" \
        "Alfred's cache directory for this workflow could not be created."
    exit 0
}

# --- which record are we looking at? ----------------------------------------

if [ "$intent" = "run" ] && [ -z "${projectRoot:-}" ]; then
    sf_message "No project was selected" \
        "Open the nimbus workflow with its keyword and pick a project first."
    exit 0
fi

if [ "$intent" = "show" ] || [ -z "${projectRoot:-}" ]; then
    # The last thing that happened, whatever project it belonged to. Also the
    # honest answer for a re-invocation that arrived without its project: show
    # something true rather than complain about a variable the user never saw.
    record_file="$state/last-run.json"
else
    record_file="$runs_state/$(project_key "$projectRoot").json"
fi

RECORD=""
[ -f "$record_file" ] && RECORD="$(< "$record_file")"

# The facts the shell needs out of the record. One jq for all of them, because
# this runs every second.
#
# US (0x1f) rather than a tab, for the reason icons.sh already found the hard
# way: tab is IFS whitespace, so `read` collapses runs of it and drops the empty
# fields between. An empty field is normal here — a record written when the
# cache was unwritable has no log path — and with a tab every field after it
# would shift by one and be read as something it is not.
REC_SEP=$'\037'
rec_log=""
rec_root=""
rec_phase=""
rec_finished=""
if [ -n "$RECORD" ]; then
    IFS="$REC_SEP" read -r rec_log rec_root rec_phase rec_finished <<< "$(
        printf '%s' "$RECORD" \
            | jq -r --arg sep "$REC_SEP" \
                '[(.log // ""), (.projectRoot // ""), (.phase // ""), ((.finished // 0) | tostring)] | join($sep)' \
              2>/dev/null
    )"
fi

# The run is always identified by the project it belongs to, whether that came
# from the row that was actioned or out of the record itself.
owner_root="${projectRoot:-$rec_root}"
if [ -n "$owner_root" ]; then
    key="$(project_key "$owner_root")"
    pid_file="$runs_state/$key.pid"
    err_file="$runs_state/$key.err"
    lock_dir="$runs_state/$key.lock"
else
    pid_file=""
    err_file=""
    lock_dir=""
fi

# --- is the process that owns the record still there? -----------------------

# True when the PID is alive and is still a shell, which is what run-detached.sh
# runs as. Nothing here ever signals that process — this is only the difference
# between "still working" and "died without saying so" — so a recycled PID costs
# an over-optimistic row for a moment and nothing worse.
pid_alive() {
    local pid="$1" comm
    [ -n "$pid" ] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    comm="$(ps -o comm= -p "$pid" 2>/dev/null)"
    case "$comm" in
        */bash|bash|*/sh|sh) return 0 ;;
        *)                   return 1 ;;
    esac
}

alive=0
if [ -n "$pid_file" ] && [ -f "$pid_file" ]; then
    pid_alive "$(cat "$pid_file" 2>/dev/null)" && alive=1
fi

# --- start, when and only when asked ----------------------------------------

started_now=0

start_run() {
    # mkdir is atomic, so it is the mutex. Two invocations landing together —
    # a double-tap of ↵, or the first rerun overtaking the first invocation —
    # would otherwise both read "nothing running" and start two builds of the
    # same project against the same simulator.
    mkdir "$lock_dir" 2>/dev/null || return 1

    # Re-read under the lock: the invocation that lost the race wrote its PID
    # file while this one was between the check above and the mkdir.
    local held=""
    [ -f "$pid_file" ] && held="$(cat "$pid_file" 2>/dev/null)"
    if pid_alive "$held"; then
        rmdir "$lock_dir" 2>/dev/null
        alive=1
        return 1
    fi

    # `set -m` puts the child in its own process group. Alfred kills a Script
    # Filter's process when it re-invokes it, and without this the build would
    # go with it. nohup covers the hangup; disown covers this shell's own exit.
    set -m
    nohup /bin/bash ./run-detached.sh >/dev/null 2>"$err_file" </dev/null &
    local pid=$!
    set +m

    # Written before anything else can look: an invocation that died between the
    # fork and this line would leave a build running with no handle on it.
    printf '%s' "$pid" > "$pid_file"
    disown "$pid" 2>/dev/null || true
    rmdir "$lock_dir" 2>/dev/null

    alive=1
    return 0
}

# A run that finished a moment ago is one this window has just been watching,
# not one the user has asked for again.
#
# This is the second lock on the door, and it is here because the first one is
# not mine to guarantee. The primary guard is the `variables` this script emits:
# Alfred hands them back on a re-invocation, so a rerun arrives as intent=watch
# and can never start anything. If that round-trip does not happen, every rerun
# would instead look like a fresh ↵ — and the one that arrives a second after a
# build finishes would start another, forever. A few seconds of refusal costs a
# user who re-enters immediately one extra keypress; the alternative costs them
# a machine that will not stop building.
just_finished=0
if [ "$rec_phase" = "done" ] && [ -n "$rec_finished" ] && [ "$rec_finished" != "0" ]; then
    [ "$(( $(date +%s) - rec_finished ))" -lt 5 ] && just_finished=1
fi

if [ "$intent" = "run" ] && [ "$alive" = "0" ] && [ "$just_finished" = "0" ] && [ -n "$pid_file" ]; then
    if start_run; then
        started_now=1
        # The record belongs to run-detached.sh, so the first read after a start
        # can legitimately find the previous run's record or none at all. Either
        # way this invocation shows "Starting…" and the next one shows the truth.
        RECORD=""
        rec_log=""
    fi
fi

log_exists=0
[ -n "$rec_log" ] && [ -f "$rec_log" ] && log_exists=1

# --- render ------------------------------------------------------------------

project_label="${projectName:-}"
if [ -z "$project_label" ] && [ -n "$owner_root" ]; then
    project_label="${owner_root##*/}"
fi
[ -n "$project_label" ] || project_label="this project"

jq -n \
    --arg raw "$RECORD" \
    --arg intent "$intent" \
    --arg label "$project_label" \
    --arg root "$owner_root" \
    --arg home "$HOME" \
    --argjson alive "$alive" \
    --argjson starting "$started_now" \
    --argjson logExists "$log_exists" \
    '
    def clock($s):
        (if $s < 0 then 0 else $s end | floor) as $t
        | (($t / 60) | floor) as $m
        | ($t % 60) as $r
        | ($m | tostring) + ":" + (if $r < 10 then "0" else "" end) + ($r | tostring);

    # A diagnostic reads "<file>:<line>:<col>: error: <what>". The what is the
    # news and the where is context, so they go on separate lines rather than
    # being truncated together in the middle of one.
    def parts($d):
        ($d | index(": error: ")) as $i
        | if $i then { where: $d[0:$i], msg: $d[($i + 9):] }
          else { where: "", msg: $d } end;

    def shorten($p):
        if ($p | startswith($home + "/")) then "~" + $p[($home | length):] else $p end;

    ($raw | try fromjson catch null) as $rec
    | ($rec.log // "") as $log
    | ($rec.projectName // $label) as $name
    | ($logExists == 1) as $canOpen

    # Every row that leads anywhere leads to the same place: the log for this
    # run. The Open File object downstream takes it from `arg`, and quicklookurl
    # puts the same file behind ⇧ without leaving the window at all.
    | def openable:
        if $canOpen then { arg: $log, valid: true, quicklookurl: $log, text: { copy: $log } }
        else { valid: false } end;

    (
      # Asked to show the last run when nothing has run. Not a failure, and not
      # a reason to keep re-asking every second.
      if $rec == null and $intent == "show" then
        [ { title: "Nothing has run from Alfred yet",
            subtitle: "Pick a project and press ↵; what happens will be here afterwards",
            match: "last run nothing empty",
            valid: false } ]

      elif $rec == null or $starting == 1 then
        [ { title: ("Starting nimbus run on " + $name + "…"),
            subtitle: "Resolving the simulator and handing over to xcodebuild",
            match: "run building starting",
            valid: false } ]

      elif $rec.phase == "running" and $alive == 1 then
        [ ( openable + {
            title: ("Building " + $name + "…   " + clock(now - ($rec.started // 0))),
            subtitle: (
              "nimbus run"
              + (if ($rec.device // "") != "" then " · " + $rec.device else "" end)
              + (if $canOpen then "   ·   ↵ opens the log so far, ⇧ previews it here" else "" end)
            ),
            match: "run building running" } ) ]

      elif $rec.phase == "running" then
        [ ( openable + {
            title: "✗ The run ended without reporting",
            subtitle: (
              "The process is gone and never wrote a result"
              + (if $canOpen then "   ·   ↵ opens the log, which may say why" else "" end)
            ),
            match: "run failed died" } ) ]

      elif $rec.ok then
        [ ( openable + {
            title: ("✓ " + ($rec.headline // "Done")),
            subtitle: (
              $name + " · " + ($rec.action // "run") + " · took "
              + clock((($rec.finished // 0) - ($rec.started // 0)))
              + (if $canOpen then "   ·   ↵ opens the full log" else "" end)
            ),
            match: "run done ok success finished" } ) ]

      else
        [ ( openable + {
            # The summary, not the first diagnostic: the diagnostics get rows
            # of their own below, and a title holding a full file path would be
            # truncated exactly where the error text starts.
            title: ("✗ " + ($rec.message // $rec.headline // "Failed")),
            subtitle: (
              $name + " · " + ($rec.action // "run")
              + (if ($rec.exitCode // null) != null then " · exit " + ($rec.exitCode | tostring) else "" end)
              + (if $canOpen then "   ·   ↵ opens the full log, ⇧ previews it here" else "" end)
            ),
            match: "run failed error" } ) ]
      end
    )
    # The compiler said more than one line. Showing the first few as rows is the
    # difference between "the build failed" and knowing why, and it draws them
    # with nothing this workflow has not already proven it can draw.
    + (
      ($rec.diagnostics // [])
      | if length == 0 then []
        else
          . as $all
          | [ limit(8; .[]) ]
          | to_entries
          | map(
              parts(.value) as $p
              | { title: $p.msg,
                  subtitle: (
                    (if $p.where != "" then shorten($p.where) + "   ·   " else "" end)
                    + "error " + ((.key + 1) | tostring) + " of " + ($all | length | tostring)
                  ),
                  match: .value,
                  valid: false,
                  text: { copy: .value, largetype: ($all | join("\n")) } })
        end
    )
    # Our order is the meaning — the outcome, then the compiler in the order it
    # spoke — and Alfred learning a different one would take that away.
    | { items: ., skipknowledge: true,
        # Handed back to this script on every re-invocation, which is how a
        # rerun tells itself apart from a fresh ↵. Only intent=run starts a
        # build, so a rerun cannot, however many of them arrive.
        # projectRoot travels with it so a re-invocation is never left
        # guessing which project it is watching.
        variables: { intent: (if $intent == "show" then "show" else "watch" end),
                     projectRoot: $root,
                     projectName: $label } }
      + (if ($rec == null and $intent == "show") then {}
         elif ($rec == null or $starting == 1 or ($rec.phase == "running" and $alive == 1))
         then { rerun: 1 } else {} end)
    '
