#!/bin/bash
#
# Resolve one presentable icon per project root, cheaply enough to sit in front
# of a Script Filter.
#
# Sourced, never run. `projects.sh` is the only caller.
#
# This is presentation, and it lives here for the same reason the rest of this
# directory does: nimbus states facts about projects and simulators, and Alfred
# wants a picture. Teaching nimbus about Alfred's icon field would put a
# consumer's format inside the tool, so the workflow adapts instead.
#
# The chain, best-effort, falling back rather than failing:
#
#   1. the app icon in the project's own asset catalog
#   2. the icon inside a built .app, if one is lying around in DerivedData
#   3. Alfred's `fileicon` pointed at the .xcodeproj / .xcworkspace
#   4. nothing, which means Alfred draws the workflow's own icon
#
# A row never fails and never goes blank because an icon could not be found.
# Step 4 always succeeds, by doing nothing.
#
# --- what makes this affordable ----------------------------------------------
#
# Step 1 is a directory walk, and one of the projects it runs against is a 16 GB
# iOS repo. Unbounded, that walk is the whole time budget and then some. Two
# things keep it honest:
#
#   * the walk is depth-limited and prunes the directories that make a big repo
#     big (measured on that repo: 20 ms at depth 4, 50 ms at depth 5, 80 ms at
#     depth 6 — the cost is the traversal, not the match);
#   * the answer is cached per project root, so the walk happens on a cache miss
#     and not otherwise.
#
# Measured end to end on that repo: the filter was 30 ms, is 40 ms once the cache
# is warm, and costs 80 ms on the run that has to resolve an icon.

# --- tuning -------------------------------------------------------------------

# Deep enough for App/Resources/Assets.xcassets/AppIcon.appiconset, which is
# where the largest project on this machine keeps its icon, and no deeper. Each
# further level is real money on a big repo: 4 costs 20 ms, 5 costs 50 ms, 6
# costs 80 ms, and that is the difference between an 80 ms cache miss and a
# 120 ms one.
#
# A project that nests its catalog deeper than this does not fail — it falls to
# the next rung of the chain and shows its project icon. Raising this is one
# line if that turns out to matter, and the cost of raising it is known.
ICON_MAX_DEPTH=4

# The blunt backstop on a cache entry. Mtime (below) catches the case that
# actually happens — someone replaced the icon — immediately and exactly. The
# TTL catches everything mtime cannot see: a catalog that moved, an icon that
# appeared where there was none, a fallback that is no longer the best answer
# available. A day is a guess, and it is stated as one rather than dressed up as
# a derived number.
ICON_CACHE_TTL=86400

# --- cache --------------------------------------------------------------------
#
# One JSON file for all projects rather than a file per project: it is one read
# and one write however many projects there are, and a full path is its own key
# with no hashing and no collisions.
#
# Written by rename, so a reader sees either the whole old value or the whole new
# one, never half of either. Two filters resolving at the same time can still
# lose one entry to the other — last writer wins — and the cost of that is one
# extra walk later. That is the entire blast radius, so it is left alone.

icon_cache_file() {
    local dir="${alfred_workflow_cache:-${TMPDIR:-/tmp}/nimbus-alfred}"
    # Alfred sets the variable but does not promise the directory. Creating it is
    # a process spawn, so it is only paid on the run that finds it missing.
    [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || return 1
    printf '%s/project-icons.json' "$dir"
}

# --- resolving ----------------------------------------------------------------

# The project file, if there is one. Needed both for the fileicon fallback and
# for the DerivedData name, so it is resolved once up front.
#
# Workspace before project: when a repo has both, the workspace is the one that
# gets opened.
_icon_project_file() {
    local candidate
    for candidate in "$1"/*.xcworkspace "$1"/*.xcodeproj; do
        [ -e "$candidate" ] && { printf '%s' "$candidate"; return 0; }
    done
    return 1
}

# The likeliest app-icon catalog under a project root.
#
# A real iOS repo has several .appiconset directories and only one of them is the
# app's — the others belong to widgets, extensions and test hosts. Ranking them
# is not optional: on the repo this was measured against, the widget's catalog
# sorts first under every naive rule, including "shallowest wins".
#
# One walk at full depth, then rank. Widening the walk a level at a time and
# stopping at the first depth that answered would be cheaper still — but it was
# tried and it is wrong: stopping early makes depth the ranking rule, and on that
# repo the widget's catalog sits one level above the app's, so it wins and the
# row shows the wrong icon. A wrong icon is worse than a generic one, since being
# scannable by sight is the whole point.
_icon_appiconset() {
    local root="$1"

    find "$root" -maxdepth "$ICON_MAX_DEPTH" \
        \( -name '.?*' \
           -o -name Pods -o -name Carthage -o -name node_modules \
           -o -name DerivedData -o -name build -o -name Build \
           -o -name '*.framework' -o -name '*.app' -o -name '*.xcarchive' \) \
        -prune -o \
        -type d -name '*.appiconset' -print 2>/dev/null \
    | /usr/bin/awk -v root="$root" '
        {
            rel = substr($0, length(root) + 2)
            low = tolower(rel)
            penalty = 0
            # A catalog under any of these belongs to some other target.
            if (low ~ /test/)                        penalty += 10
            if (low ~ /widget/)                      penalty += 10
            if (low ~ /extension/)                   penalty += 10
            if (low ~ /watch/)                       penalty += 10
            if (low ~ /appclip/)                     penalty += 10
            if (low ~ /example|sample|demo|fixture/) penalty += 5
            # Among equals the shallowest is the likeliest main target, and the
            # path itself breaks the last tie so the answer is stable run to run.
            score = penalty * 1000 + split(rel, parts, "/")
            if (best == "" || score < bestscore || (score == bestscore && $0 < best)) {
                bestscore = score
                best = $0
            }
        }
        END { if (best != "") print best }
    '
}

# Which image to actually show out of an .appiconset.
#
# Contents.json is the catalog stating which file is which, so it is read rather
# than guessed at: the largest image carrying no `appearances` key, which is the
# one Xcode uses when nothing special applies. Picking the biggest file on disk
# instead would show the dark-mode icon on the repo this was measured against.
_icon_image_in_appiconset() {
    local set_dir="$1" name

    if [ -f "$set_dir/Contents.json" ]; then
        name="$(jq -r '
            [ .images[]?
              | select(.filename != null and .filename != "")
              | select(has("appearances") | not)
              | { f: .filename,
                  px: ( ((.size  // "0x0") | split("x") | .[0] | tonumber? // 0)
                        * ((.scale // "1x") | rtrimstr("x") | tonumber? // 1) ) }
            ] | sort_by(.px) | last | .f // empty
        ' "$set_dir/Contents.json" 2>/dev/null)"
        if [ -n "$name" ] && [ -f "$set_dir/$name" ]; then
            printf '%s' "$set_dir/$name"
            return 0
        fi
    fi

    # No usable Contents.json: largest PNG, which is what the format implies.
    name="$(/bin/ls -S "$set_dir"/*.png 2>/dev/null | head -1)"
    [ -n "$name" ] && { printf '%s' "$name"; return 0; }
    return 1
}

# The icon out of a built .app, if one was left behind in DerivedData.
#
# Shallow globs only. Which build is the right one is guesswork — a repo with
# several worktrees has several DerivedData directories — but this only runs when
# no asset catalog was found at all, and a plausible icon beats a generic one.
_icon_from_built_app() {
    local name="$1" dd="$HOME/Library/Developer/Xcode/DerivedData" app png
    [ -n "$name" ] || return 1
    [ -d "$dd" ] || return 1

    app="$(/bin/ls -dt "$dd/$name-"*/Build/Products/*-iphonesimulator/*.app 2>/dev/null | head -1)"
    [ -n "$app" ] && [ -d "$app" ] || return 1

    png="$(/bin/ls -S "$app"/AppIcon*.png 2>/dev/null | head -1)"
    [ -n "$png" ] && { printf '%s' "$png"; return 0; }
    return 1
}

# The field separator for every record passed around inside this file.
#
# Not a tab. Tab is IFS whitespace, so `read` collapses runs of it and drops the
# empty fields between — and an empty field is the normal case here, because a
# plain image icon has no type. US (0x1f) is not whitespace, cannot occur in a
# path, and makes `read` preserve every field exactly as written.
ICON_SEP=$'\037'

# Resolve one project root. Prints "TYPE<SEP>PATH".
#
# TYPE is Alfred's: empty means "this path is an image", `fileicon` means "draw
# whatever Finder draws for this path". An empty PATH is step 4 of the chain —
# say nothing, and Alfred uses the workflow's own icon.
icon_resolve() {
    local root="$1" project_file="" name="" set_dir image

    project_file="$(_icon_project_file "$root")"
    if [ -n "$project_file" ]; then
        name="${project_file##*/}"
        name="${name%.*}"
    fi

    set_dir="$(_icon_appiconset "$root")"
    if [ -n "$set_dir" ]; then
        image="$(_icon_image_in_appiconset "$set_dir")"
        [ -n "$image" ] && { printf '%s%s' "$ICON_SEP" "$image"; return 0; }
    fi

    image="$(_icon_from_built_app "$name")"
    [ -n "$image" ] && { printf '%s%s' "$ICON_SEP" "$image"; return 0; }

    [ -n "$project_file" ] && { printf 'fileicon%s%s' "$ICON_SEP" "$project_file"; return 0; }

    printf '%s' "$ICON_SEP"
}

# --- the whole job ------------------------------------------------------------

# Given a nimbus projects envelope, print the icon map as JSON:
#
#   { "<projectRoot>": { "type": "", "path": "/…/Light.png" }, … }
#
# A cached entry is trusted while it is unexpired, the file it names is still
# there, and — for a real image file — that file still has the mtime it had.
# Mtime is the honest invalidator: it is exactly the thing that changes when the
# icon changes, it costs one stat, and it claims nothing it cannot see. A
# `fileicon` entry names a project bundle whose mtime moves for reasons that have
# nothing to do with its icon, so for those, existence is the check and the TTL
# does the rest.
icon_map_for_envelope() {
    local envelope="$1"
    local cache_file cache rows
    local root hit type path stamp fresh
    local resolved="" mtimes="" any_miss=0
    local paths=()

    cache_file="$(icon_cache_file)" || { printf '{}'; return 0; }

    cache='{}'
    [ -f "$cache_file" ] && cache="$(< "$cache_file")"
    [ -n "$cache" ] || cache='{}'

    # One pass over the envelope: every project root, carrying its cache entry if
    # that entry has not expired. The second field says whether there was one at
    # all, because "cached, and the answer was nothing" and "not cached" are
    # different rows that otherwise look identical.
    #
    # A cache file that is not valid JSON fails this outright; that is the
    # self-heal, and the retry treats it as absent rather than giving up.
    #
    # The clock is jq's own `now`, here and in the write below. Shelling out to
    # `date` for it would be one more process spawn on the path that runs every
    # time, and that is the path that has to stay cheap.
    local jq_rows='
        (now | floor) as $now
        | .data.projects[]? | .projectRoot as $r
        | ($cache[$r] // null) as $e
        | if ($e != null and (($e.expires // 0) > $now))
          then [$r, "1", ($e.type // ""), ($e.path // ""), (($e.stamp // "") | tostring)]
          else [$r, "0", "", "", ""] end
        | join($sep)'

    rows="$(printf '%s' "$envelope" | jq -r \
        --arg sep "$ICON_SEP" --argjson cache "$cache" "$jq_rows" 2>/dev/null)" \
    || rows="$(printf '%s' "$envelope" | jq -r \
        --arg sep "$ICON_SEP" --argjson cache '{}' "$jq_rows" 2>/dev/null)"

    [ -n "$rows" ] || { printf '{}'; return 0; }

    # Every cached path stated in one stat, rather than one stat per project.
    while IFS="$ICON_SEP" read -r root hit type path stamp; do
        [ -n "$path" ] && paths[${#paths[@]}]="$path"
    done <<< "$rows"

    if [ "${#paths[@]}" -gt 0 ]; then
        mtimes=$'\n'"$(/usr/bin/stat -f '%m %N' -- "${paths[@]}" 2>/dev/null)"$'\n'
    fi

    while IFS="$ICON_SEP" read -r root hit type path stamp; do
        fresh=0
        if [ "$hit" = "1" ]; then
            if [ -z "$path" ]; then
                # Nothing was found last time and the entry has not expired.
                # Believe it — re-walking a big repo to reconfirm an absence is
                # exactly the expensive case this cache exists to avoid.
                fresh=1
            elif [ -n "$stamp" ]; then
                case "$mtimes" in *$'\n'"$stamp $path"$'\n'*) fresh=1 ;; esac
            else
                case "$mtimes" in *" $path"$'\n'*) fresh=1 ;; esac
            fi
        fi

        if [ "$fresh" != "1" ]; then
            any_miss=1
            IFS="$ICON_SEP" read -r type path <<< "$(icon_resolve "$root")"
            stamp=""
            # Only image files get an mtime stamp; see the note above.
            if [ -n "$path" ] && [ -z "$type" ]; then
                stamp="$(/usr/bin/stat -f '%m' -- "$path" 2>/dev/null)"
            fi
        fi

        resolved="$resolved$root$ICON_SEP$type$ICON_SEP$path$ICON_SEP$stamp"$'\n'
    done <<< "$rows"

    # Every row came out of the cache, so the cache already *is* the answer.
    # Rebuilding it would be one more jq on the path that runs every time. It may
    # hold entries for projects that are no longer listed; the caller looks up by
    # root, so they are invisible, and the next write drops them.
    if [ "$any_miss" != "1" ]; then
        printf '%s' "$cache"
        return 0
    fi

    local map
    map="$(printf '%s' "$resolved" | jq -R -s \
        --argjson ttl "$ICON_CACHE_TTL" --arg sep "$ICON_SEP" '
        (now | floor) as $now
        | [ split("\n")[] | select(length > 0) | split($sep)
            | { key: .[0],
                value: { type: .[1], path: .[2], stamp: .[3], expires: ($now + $ttl) } }
          ] | from_entries
    ' 2>/dev/null)"
    [ -n "$map" ] || { printf '{}'; return 0; }

    # Written from the current project list alone, so entries for projects that
    # are no longer pinned drop out on their own. No separate expiry sweep.
    local tmp="$cache_file.$$"
    if printf '%s' "$map" > "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$cache_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    fi

    printf '%s' "$map"
}
