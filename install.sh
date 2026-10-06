#!/bin/sh
# Verify that the installed ZimZilla can report itself to Herdr.
#
# ZimZilla is not one of the agents Herdr ships a detection manifest for, and
# a manifest cannot introduce a new agent on its own. So ZimZilla reports its
# own state through `herdr pane report-agent`, from zimzilla/herdr.py. This
# script checks that the installed copy actually has that module, and says so
# plainly when it does not.
#
# Idempotent and read-only: it installs nothing and changes nothing.

set -u

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

say() { [ "$QUIET" = 1 ] || printf '%s\n' "$*"; }
bad() { printf '%s\n' "$*" >&2; }

# --- locate the installed package --------------------------------------------
ZIM=$(command -v zimzilla 2>/dev/null || true)
if [ -z "$ZIM" ]; then
    bad "zimzilla: not on PATH — install ZimZilla first, then re-run this."
    exit 1
fi

# Finding the package means finding the interpreter that owns it, and there is
# no single reliable way to do that: `zimzilla` may be a console script with a
# python shebang, or the bash shim that setup.sh writes, which points at a
# checkout and its venv. So collect every plausible interpreter and take the
# first one that can actually import the package.
candidates=""

# The shim records the checkout it belongs to.
root=$(sed -n 's/^ *export ZIMZILLA_ROOT=//p' "$ZIM" 2>/dev/null | head -1 | tr -d '"'"'"'')
[ -n "$root" ] && candidates="$candidates $root/.venv/bin/python"

# A console script names its interpreter in the shebang.
shebang=$(sed -n '1s|^#! *||p' "$ZIM" 2>/dev/null || true)
case "$shebang" in
    *python*) candidates="$candidates $shebang" ;;
esac

# Whatever the shim execs may itself be a python entrypoint.
exec_target=$(sed -n 's/^ *exec \([^ ]*\) .*/\1/p' "$ZIM" 2>/dev/null | head -1)
[ -n "$exec_target" ] && candidates="$candidates $exec_target"

candidates="$candidates $(command -v python3 2>/dev/null || true) $(command -v python 2>/dev/null || true)"

PY=""
PKG=""
for cand in $candidates; do
    [ -x "$cand" ] || continue
    found=$("$cand" -c 'import os, zimzilla; print(os.path.dirname(zimzilla.__file__))' 2>/dev/null || true)
    if [ -n "$found" ]; then
        PY="$cand"
        PKG="$found"
        break
    fi
done

if [ -z "$PY" ]; then
    bad "zimzilla: found $ZIM, but no interpreter on this machine can import"
    bad "the zimzilla package. Re-run ZimZilla's setup.sh to repair the install."
    exit 1
fi

say "zimzilla:  $ZIM"
say "python:    $PY"
say "package:   $PKG"

# --- the reporter ------------------------------------------------------------
if [ ! -f "$PKG/herdr.py" ]; then
    bad ""
    bad "This ZimZilla predates its Herdr integration: $PKG/herdr.py is missing."
    bad "Update ZimZilla (git pull in its checkout, or re-run setup.sh) and"
    bad "launch it again. Until then Herdr will show it as a plain terminal."
    exit 1
fi
say "reporter:  $PKG/herdr.py"

# --- what Herdr sees right now ----------------------------------------------
HERDR=${HERDR_BIN_PATH:-$(command -v herdr 2>/dev/null || true)}
if [ -z "$HERDR" ]; then
    say ""
    say "herdr is not on PATH, so there is nothing to report to yet."
    exit 0
fi

if [ "${HERDR_ENV:-}" != "1" ]; then
    say ""
    say "Not running inside a Herdr pane, so ZimZilla will stay silent here."
    say "Launch it from a Herdr pane and it will register itself."
    exit 0
fi

# The Python lives in a heredoc rather than a -c string: the code contains
# quotes and braces that a shell-quoted one-liner mangles.
REPORT=$(cat <<'PYEOF'
import json, sys

try:
    agents = json.load(sys.stdin)["result"]["agents"]
except Exception:
    print("  (could not read the agent list)")
    raise SystemExit(0)

mine = [a for a in agents if a.get("agent") == "zimzilla"]
if not mine:
    print("  no zimzilla agent in this session yet.")
    print("  Launch zimzilla in a pane; it registers itself on startup.")
else:
    for a in mine:
        name = a.get("agent", "?")
        state = a.get("agent_status", "?")
        pane = a.get("pane_id", "?")
        print("  %s  %s  %s" % (name, state, pane))
PYEOF
)

say ""
say "Herdr sees:"
"$HERDR" agent list 2>/dev/null | "$PY" -c "$REPORT" || say "  (could not read the agent list)"

exit 0
