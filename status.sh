#!/bin/sh
# Show every agent Herdr currently recognises, and where ZimZilla sits among
# them. Read-only: this is the "why does my sidebar look like that" command.

set -u

HERDR=${HERDR_BIN_PATH:-$(command -v herdr 2>/dev/null || true)}
if [ -z "$HERDR" ]; then
    echo "herdr is not on PATH." >&2
    exit 1
fi

if [ "${HERDR_ENV:-}" != "1" ]; then
    echo "Not inside a Herdr pane — nothing to show." >&2
    exit 1
fi

# The Python lives in a heredoc rather than a -c string: the code contains
# quotes and braces that a shell-quoted one-liner mangles.
TABLE=$(cat <<'PYEOF'
import json, sys

try:
    agents = json.load(sys.stdin)["result"]["agents"]
except Exception as exc:
    print("could not read the agent list: %s" % exc, file=sys.stderr)
    raise SystemExit(1)

if not agents:
    print("Herdr sees no agents in this session.")
    print()
    print("ZimZilla registers itself when it starts inside a Herdr pane.")
    print("If it is running and still absent, check that its pane is not")
    print("sitting at a shell prompt — Herdr clears an agent once the pane")
    print("is back at the prompt.")
    raise SystemExit(0)

rows = [(a.get("agent", "?"), a.get("agent_status", "?"), a.get("pane_id", "?"))
        for a in agents]
width = max(len(r[0]) for r in rows)

print("%-*s  %-8s  %s" % (width, "AGENT", "STATE", "PANE"))
for name, state, pane in sorted(rows):
    mark = "  <- zimzilla" if name == "zimzilla" else ""
    print("%-*s  %-8s  %s%s" % (width, name, state, pane, mark))
PYEOF
)

"$HERDR" agent list 2>/dev/null | python3 -c "$TABLE"
