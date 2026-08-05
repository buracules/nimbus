#!/bin/bash
#
# Assemble alfred/workflow/ into an importable .alfredworkflow.
#
# An .alfredworkflow is a zip. The zip is a build product and is not committed —
# the reviewable thing is the directory it is made from.
#
#   ./alfred/build.sh                  # writes alfred/dist/nimbus.alfredworkflow
#   ./alfred/build.sh /some/where.zip  # writes it somewhere else
#
# Importing is a deliberate act: open the file, and Alfred asks before adding
# it. This script never writes into Alfred's preferences.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
source_dir="$here/workflow"
target="${1:-$here/dist/nimbus.alfredworkflow}"

python3 "$here/make-info-plist.py"

# Fail loudly rather than shipping a workflow Alfred will refuse to load.
/usr/bin/plutil -lint "$source_dir/info.plist" >/dev/null

for script in "$source_dir"/*.sh; do
    # Libraries are sourced by the scripts Alfred runs, never run themselves, so
    # the executable bit would say something untrue about them.
    case "$(basename "$script")" in
        lib.sh|icons.sh) continue ;;
    esac
    if [ ! -x "$script" ]; then
        echo "error: $script is not executable; Alfred would not be able to run it" >&2
        exit 1
    fi
    /bin/bash -n "$script"
done

mkdir -p "$(dirname "$target")"
rm -f "$target"

# -X drops the extra file attributes; ditto's resource forks and .DS_Store
# entries make the archive differ run to run for no reason.
( cd "$source_dir" && zip -q -r -X "$target" . -x '.DS_Store' )

echo "built $target"
