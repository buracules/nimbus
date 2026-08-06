#!/usr/bin/env python3
"""Generate the nimbus workflow's info.plist.

Alfred's info.plist is a graph — objects keyed by UUID, connections keyed by
source UUID — and hand-editing one means keeping a dozen UUIDs in step across
three sections. Writing it from here means the graph is stated once, in the
shape it actually has, and the plist is a build product of that statement.

The generated plist is committed, so a reviewer never has to run this to see
what Alfred will load. Re-run it after changing the graph:

    python3 alfred/make-info-plist.py

Object type numbers are taken from workflows that already run on this machine:
`type: 0` is /bin/bash and `scriptargtype: 1` is "input as argv". Each script
object is a one-line trampoline into a real file in the bundle, because a shell
script in a repository can be read, diffed and run directly, and one embedded in
a plist string cannot.
"""

import plistlib
from pathlib import Path

BUNDLE_ID = "co.ustun.nimbus"
KEYWORD = "nim"

# Stable UUIDs. They are identity, not randomness: regenerating them would make
# every rebuild look like a different workflow to Alfred's sync and to git.
PROJECTS_FILTER = "1A1E2B00-0001-4000-A000-000000000001"
DEVICES_FILTER = "1A1E2B00-0002-4000-A000-000000000002"
RUN_FILTER = "1A1E2B00-0003-4000-A000-000000000003"
ACTION_SCREENSHOT = "1A1E2B00-0011-4000-A000-000000000011"
ACTION_RECORD = "1A1E2B00-0012-4000-A000-000000000012"
ACTION_APPEARANCE = "1A1E2B00-0013-4000-A000-000000000013"
ACTION_USE = "1A1E2B00-0014-4000-A000-000000000014"
ACTION_LOGS = "1A1E2B00-0015-4000-A000-000000000015"
NOTIFY_RUN = "1A1E2B00-0020-4000-A000-000000000020"
NOTIFY_SCREENSHOT = "1A1E2B00-0021-4000-A000-000000000021"
NOTIFY_RECORD = "1A1E2B00-0022-4000-A000-000000000022"
NOTIFY_APPEARANCE = "1A1E2B00-0023-4000-A000-000000000023"
NOTIFY_USE = "1A1E2B00-0024-4000-A000-000000000024"
OPEN_LOG = "1A1E2B00-0030-4000-A000-000000000030"
TERMINAL_LOGS = "1A1E2B00-0031-4000-A000-000000000031"
TRIGGER_RUN_FINISHED = "1A1E2B00-0040-4000-A000-000000000040"

# Alfred's modifier bitmask, as used in a connection's `modifiers` key.
NO_MODIFIER = 0
CMD = 1048576
ALT = 524288
CTRL = 262144
CMD_ALT = CMD | ALT
CMD_CTRL = CMD | CTRL


def script_filter(uid, keyword, title, subtext, running, scriptfile, argumenttype):
    """A Script Filter that lets Alfred do the filtering.

    `alfredfiltersresults` is what keeps this fast: the script runs once when
    the keyword is entered, not once per keystroke. `nimbus devices --json`
    takes about a quarter of a second, which is fine once and miserable per
    character.
    """
    config = {
        "alfredfiltersresults": True,
        "alfredfiltersresultsmatchmode": 0,
        "argumenttreatemptyqueryasnil": True,
        "argumenttrimmode": 0,
        "argumenttype": argumenttype,
        "escaping": 102,
        "queuedelaycustom": 3,
        "queuedelayimmediatelyinitially": True,
        "queuedelaymode": 0,
        "queuemode": 1,
        "runningsubtext": running,
        "script": "#!/bin/bash\nexec ./%s\n" % scriptfile,
        "scriptargtype": 1,
        "scriptfile": "",
        "subtext": subtext,
        "title": title,
        "type": 0,
        "withspace": False,
    }
    # A downstream Script Filter is reached by a connection, never by typing, so
    # its keyword is empty rather than absent — Alfred expects the key.
    config["keyword"] = keyword or ""
    return {
        "config": config,
        "type": "alfred.workflow.input.scriptfilter",
        "uid": uid,
        "version": 3,
    }


def run_script(uid, scriptfile):
    """An action that runs in the foreground and prints one line.

    Foreground on purpose: Alfred's window is already gone by the time this
    starts, so nothing looks frozen, and finishing in the foreground is what
    lets the connected notification fire with the result rather than with a
    guess made before the work happened.
    """
    return {
        "config": {
            "concurrently": False,
            "escaping": 102,
            "script": "#!/bin/bash\nexec ./%s\n" % scriptfile,
            "scriptargtype": 1,
            "scriptfile": "",
            "type": 0,
        },
        "type": "alfred.workflow.action.script",
        "uid": uid,
        "version": 2,
    }


def notification(uid, title):
    """The completion signal for a long action.

    Alfred's own notifier rather than `osascript -e 'display notification'`:
    Alfred is already permitted to post notifications, and an osascript banner
    is attributed to Script Editor and silently suppressed if that application
    is not allowed to notify.
    """
    return {
        "config": {
            "lastpathcomponent": False,
            "onlyshowifquerypopulated": True,
            "removeextension": False,
            "text": "{query}",
            "title": title,
        },
        "type": "alfred.workflow.output.notification",
        "uid": uid,
        "version": 1,
    }


def open_file(uid):
    """Open whatever path arrives, with whatever the user opens that kind of
    file with.

    Alfred's own object rather than `open` in a script: it is one less process,
    and "the app the user chose for this" is a preference that belongs to the
    system, not to this workflow.
    """
    return {
        "config": {"openwith": "", "sourcefile": ""},
        "type": "alfred.workflow.action.openfile",
        "uid": uid,
        "version": 3,
    }


def terminal_command(uid):
    """Run whatever arrives, in the terminal the user has told Alfred about.

    `escaping: 0` because the previous object hands this a complete, already
    quoted command line. Letting Alfred escape it again would break the quoting
    that makes a path with a space work.
    """
    return {
        "config": {"escaping": 0, "script": "{query}"},
        "type": "alfred.workflow.action.terminalcommand",
        "uid": uid,
        "version": 0,
    }


def external_trigger(uid, trigger_id):
    """An entry point reachable from outside Alfred.

    This is how a detached process gets a notification posted by Alfred rather
    than by itself: `open -g alfred://runtrigger/<bundle>/<id>/?argument=...`.
    Alfred is already permitted to notify and an osascript banner is attributed
    to Script Editor, which may not be. `-g` keeps Alfred in the background.
    """
    return {
        "config": {"triggerid": trigger_id},
        "type": "alfred.workflow.trigger.external",
        "uid": uid,
        "version": 1,
    }


def connection(destination, modifiers=NO_MODIFIER, subtext=""):
    return {
        "destinationuid": destination,
        "modifiers": modifiers,
        "modifiersubtext": subtext,
        "vitoclose": False,
    }


OBJECTS = [
    script_filter(
        PROJECTS_FILTER,
        KEYWORD,
        "nimbus projects",
        "Pick a project, then ↵ run · ⌘ screenshot · ⌥ record · ⌃ appearance · ⌘⌥ simulator · ⌘⌃ logs",
        "Reading nimbus projects…",
        "projects.sh",
        # Optional: the keyword works on its own, and the typed text filters.
        argumenttype=1,
    ),
    script_filter(
        DEVICES_FILTER,
        None,
        "Choose a simulator",
        "Pin a simulator to this project",
        "Reading simulators…",
        "devices.sh",
        argumenttype=1,
    ),
    # ↵ leads here rather than to a Run Script, and that is the whole answer to
    # "pressing enter looked like it did nothing". Actioning a row that leads to
    # another Script Filter leaves the Alfred window open; a Run Script closes
    # it. The build runs detached and this filter watches it.
    script_filter(
        RUN_FILTER,
        None,
        "nimbus run",
        "Build, install and launch",
        "Starting…",
        "run-status.sh",
        argumenttype=1,
    ),
    run_script(ACTION_SCREENSHOT, "action-screenshot.sh"),
    run_script(ACTION_RECORD, "action-record.sh"),
    run_script(ACTION_APPEARANCE, "action-appearance.sh"),
    run_script(ACTION_USE, "action-use.sh"),
    run_script(ACTION_LOGS, "action-logs.sh"),
    open_file(OPEN_LOG),
    terminal_command(TERMINAL_LOGS),
    external_trigger(TRIGGER_RUN_FINISHED, "run-finished"),
    notification(NOTIFY_RUN, "nimbus run"),
    notification(NOTIFY_SCREENSHOT, "nimbus screenshot"),
    notification(NOTIFY_RECORD, "nimbus record"),
    notification(NOTIFY_APPEARANCE, "nimbus appearance"),
    notification(NOTIFY_USE, "nimbus use"),
]

CONNECTIONS = {
    PROJECTS_FILTER: [
        connection(RUN_FILTER, NO_MODIFIER, "Build and run"),
        connection(ACTION_SCREENSHOT, CMD, "Screenshot"),
        connection(ACTION_RECORD, ALT, "Start or stop recording"),
        connection(ACTION_APPEARANCE, CTRL, "Toggle light / dark"),
        connection(DEVICES_FILTER, CMD_ALT, "Change simulator"),
        connection(ACTION_LOGS, CMD_CTRL, "Stream logs in a terminal"),
    ],
    DEVICES_FILTER: [connection(ACTION_USE)],
    # Every actionable row in the run filter carries the same thing in `arg`:
    # the path of that run's log.
    RUN_FILTER: [connection(OPEN_LOG)],
    ACTION_SCREENSHOT: [connection(NOTIFY_SCREENSHOT)],
    ACTION_RECORD: [connection(NOTIFY_RECORD)],
    ACTION_APPEARANCE: [connection(NOTIFY_APPEARANCE)],
    ACTION_USE: [connection(NOTIFY_USE)],
    ACTION_LOGS: [connection(TERMINAL_LOGS)],
    # The run notification is fired by the detached build, not by a script
    # Alfred is waiting on. It is the backstop for a dismissed window.
    TRIGGER_RUN_FINISHED: [connection(NOTIFY_RUN)],
}

# Laid out left to right so the graph reads in the order it runs.
UIDATA = {
    PROJECTS_FILTER: {"xpos": 40, "ypos": 300},
    RUN_FILTER: {"xpos": 300, "ypos": 40},
    OPEN_LOG: {"xpos": 540, "ypos": 40},
    ACTION_SCREENSHOT: {"xpos": 300, "ypos": 185},
    ACTION_RECORD: {"xpos": 300, "ypos": 330},
    ACTION_APPEARANCE: {"xpos": 300, "ypos": 475},
    ACTION_LOGS: {"xpos": 300, "ypos": 620},
    TERMINAL_LOGS: {"xpos": 540, "ypos": 620},
    DEVICES_FILTER: {"xpos": 300, "ypos": 765},
    ACTION_USE: {"xpos": 540, "ypos": 765},
    NOTIFY_SCREENSHOT: {"xpos": 540, "ypos": 185},
    NOTIFY_RECORD: {"xpos": 540, "ypos": 330},
    NOTIFY_APPEARANCE: {"xpos": 540, "ypos": 475},
    NOTIFY_USE: {"xpos": 780, "ypos": 765},
    TRIGGER_RUN_FINISHED: {"xpos": 300, "ypos": 910},
    NOTIFY_RUN: {"xpos": 540, "ypos": 910},
}

# Exposed in Alfred's workflow configuration so the three things that are a
# matter of taste can be changed without editing a script.
VARIABLES = {
    "nimbus_bin": "",
    "screenshot_dir": "",
    "recording_dir": "",
}

VARIABLES_DONT_EXPORT = []

PLIST = {
    "bundleid": BUNDLE_ID,
    "category": "Tools",
    "connections": CONNECTIONS,
    "createdby": "Burak Üstün",
    "description": "Build, run and drive iOS simulators with nimbus, without Xcode.",
    "disabled": False,
    "name": "nimbus",
    "objects": OBJECTS,
    "readme": (
        "Keyword: nim\n\n"
        "Lists the projects that have a simulator pinned with `nimbus use`, "
        "newest pin first. Alfred has no working directory, so the project you "
        "pick here is what gives every action its project context: each one "
        "runs nimbus with its working directory set to that project's root.\n\n"
        "  ↵      build, install and launch\n"
        "  ⌘↵   screenshot the simulator\n"
        "  ⌥↵   start a recording, or stop the one running\n"
        "  ⌃↵   toggle light / dark\n"
        "  ⌘⌥↵ change the simulator pinned to this project\n"
        "  ⌘⌃↵ stream this app's logs, in your terminal\n\n"
        "↵ keeps the Alfred window open and shows the build happening: a row "
        "that counts up while it runs, and then either what was launched or the "
        "compiler's own error lines. ↵ on that row opens the full log, ⇧ "
        "previews it without leaving Alfred. If you dismiss the window, a "
        "notification arrives when the build ends.\n\n"
        "Every action writes its whole output to a file under this workflow's "
        "cache folder; the newest 40 are kept. The “Last run” row at the top of "
        "the list is the way back to the most recent one.\n\n"
        "Nothing appears on the first run until you have pinned a simulator to "
        "at least one project. cd into an Xcode project and run:\n\n"
        "  nimbus use \"iPhone 17 Pro\"\n\n"
        "Requires nimbus and jq. nimbus is looked for in ~/.local/bin, "
        "/opt/homebrew/bin and /usr/local/bin; set nimbus_bin below if it lives "
        "somewhere else.\n\n"
        "Screenshots and recordings go to the Desktop unless screenshot_dir or "
        "recording_dir say otherwise."
    ),
    "uidata": UIDATA,
    "userconfigurationconfig": [
        {
            "config": {
                "default": "",
                "placeholder": "/usr/local/bin/nimbus",
                "required": False,
                "trim": True,
            },
            "description": "Leave empty to search ~/.local/bin, /opt/homebrew/bin and /usr/local/bin.",
            "label": "Path to nimbus",
            "type": "textfield",
            "variable": "nimbus_bin",
        },
        {
            "config": {
                "default": "",
                "placeholder": "~/Desktop",
                "required": False,
                "trim": True,
            },
            "description": "Where ⌘↵ writes screenshots. Empty means the Desktop.",
            "label": "Screenshot folder",
            "type": "textfield",
            "variable": "screenshot_dir",
        },
        {
            "config": {
                "default": "",
                "placeholder": "~/Desktop",
                "required": False,
                "trim": True,
            },
            "description": "Where ⌥↵ writes recordings. Empty means the Desktop.",
            "label": "Recording folder",
            "type": "textfield",
            "variable": "recording_dir",
        },
    ],
    "variables": VARIABLES,
    "variablesdontexport": VARIABLES_DONT_EXPORT,
    "version": "1.0.0",
    "webaddress": "https://github.com/buracules/nimbus",
}


def check_graph():
    """Fail on a graph Alfred would load and then quietly not run.

    A connection pointing at a UUID that is not an object, or a script object
    naming a file that is not in the bundle, produces a workflow that imports
    cleanly and does nothing when actioned. That is the worst failure available
    here, so it is caught at build time.
    """
    uids = {obj["uid"] for obj in OBJECTS}
    bundle = Path(__file__).resolve().parent / "workflow"

    for source, targets in CONNECTIONS.items():
        if source not in uids:
            raise SystemExit("connection from an object that does not exist: %s" % source)
        for target in targets:
            if target["destinationuid"] not in uids:
                raise SystemExit(
                    "connection from %s points at nothing: %s" % (source, target["destinationuid"])
                )

    for uid in uids:
        if uid not in UIDATA:
            raise SystemExit("object %s has no position, so it would stack at the origin" % uid)

    for obj in OBJECTS:
        script = obj.get("config", {}).get("script", "")
        for token in script.split():
            if token.startswith("./"):
                if not (bundle / token[2:]).is_file():
                    raise SystemExit("%s trampolines into a missing file: %s" % (obj["uid"], token))

    declared = {item["variable"] for item in PLIST["userconfigurationconfig"]}
    if declared != set(VARIABLES):
        raise SystemExit(
            "the configuration UI and the exported variables disagree: %s"
            % (declared ^ set(VARIABLES))
        )


def main():
    check_graph()
    target = Path(__file__).resolve().parent / "workflow" / "info.plist"
    with target.open("wb") as handle:
        plistlib.dump(PLIST, handle, fmt=plistlib.FMT_XML, sort_keys=True)
    print("wrote %s" % target)


if __name__ == "__main__":
    main()
