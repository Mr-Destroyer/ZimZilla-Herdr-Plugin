# ZimZilla Herdr Plugin

Makes [Herdr](https://herdr.dev) recognise [ZimZilla](https://github.com/Mr-Destroyer/ZimZilla)
as an agent.

Herdr is a terminal workspace manager for coding agents. It tracks which panes
hold agents and rolls their `idle` / `working` / `blocked` state up to tabs and
workspaces, so you can run several agents at once and see which one needs you.

ZimZilla is not one of the agents Herdr ships support for, so out of the box it
shows up as a plain terminal. This plugin fixes that: ZimZilla appears in the
Herdr sidebar and in `herdr agent list` as `zimzilla`, with live state.

```
AGENT     STATE     PANE
zimzilla  working   w1:p2  <- zimzilla
claude    idle      w1:p3
```

---

## What you get

| ZimZilla | Herdr shows |
| --- | --- |
| shell ready | `idle` |
| a turn is running | `working` |
| a permission gate is up | `blocked` |
| you quit | the agent is released |

One agent per pane, so several ZimZilla instances are tracked separately. You
also get Herdr notifications when a turn finishes, and `herdr agent wait` works
against ZimZilla like it does against any other agent.

---

## Requirements

- **Herdr** 0.7.0 or later — `herdr --version`
- **ZimZilla** with the Herdr reporter (`zimzilla/herdr.py`)

The reporter ships with ZimZilla itself. This plugin does not add it — it
verifies it is present and shows you what Herdr sees. If your ZimZilla predates
the integration, the `install` action tells you so instead of failing silently.

Check whether you have it:

```bash
python -c "import os, zimzilla; print(os.path.dirname(zimzilla.__file__))"
# then look for herdr.py in that directory
```

---

## Install

### 1. Link the plugin

```bash
herdr plugin link ~/Documents/ZimZilla-Herdr-Plugin
```

`link` registers the directory in place, so edits you make here take effect
without reinstalling. Use `install` instead if you want Herdr to manage a copy
from GitHub:

```bash
herdr plugin install Mr-Destroyer/ZimZilla-Herdr-Plugin
```

### 2. Verify

```bash
herdr plugin action invoke zimzilla.herdr.install
```

You should see something like:

```
zimzilla:  /home/you/.local/bin/zimzilla
python:    /home/you/ZimZilla/.venv/bin/python
package:   /home/you/ZimZilla/zimzilla
reporter:  /home/you/ZimZilla/zimzilla/herdr.py

Herdr sees:
  no zimzilla agent in this session yet.
  Launch zimzilla in a pane; it registers itself on startup.
```

If it reports that `herdr.py` is missing, update ZimZilla and try again.

### 3. Launch ZimZilla in a Herdr pane

```bash
zimzilla
```

It registers itself on startup. You will see this line in the transcript:

```
· herdr: reporting as agent 'zimzilla'
```

And Herdr will list it:

```bash
herdr agent list
```

That is the whole setup. There is nothing to configure and no config file to
edit.

---

## Usage

### Check what Herdr sees

```bash
herdr plugin action invoke zimzilla.herdr.status
```

Lists every agent Herdr currently recognises and marks ZimZilla's row. This is
the "why does my sidebar look like that" command.

### From the Herdr UI

Both actions are available in the command palette and can be bound to keys. Add
to `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "prefix+z"
type = "plugin_action"
command = "zimzilla.herdr.status"
description = "zimzilla herdr status"
```

### Watch the state change

```bash
# in one pane
zimzilla

# in another
watch -n1 'herdr agent list'
```

Type a prompt in ZimZilla and watch it go `idle` → `working` → `done`.

---

## How it works

Herdr learns agent state in one of two ways.

**For agents it ships support for**, Herdr finds the agent's process in the pane
and reads the live bottom of the screen. Rules in a detection manifest decide
whether what it sees means `idle`, `working`, or `blocked`.

**For every other agent**, the agent reports its own state. This is the
documented path for an agent that supports Herdr from its own code, and it is
the one ZimZilla takes.

A detection manifest is not an option here. Herdr's own documentation is
explicit that remote and local manifests only *patch* rules for agents Herdr
already knows how to identify — adding a completely new agent still requires a
Herdr binary update.

So ZimZilla calls:

```bash
herdr pane report-agent "$HERDR_PANE_ID" \
  --source zimzilla --agent zimzilla --state working --seq 1791302971102
```

and on exit:

```bash
herdr pane release-agent "$HERDR_PANE_ID" \
  --source zimzilla --agent zimzilla --seq 1791302986106
```

The reporter lives in `zimzilla/herdr.py` inside ZimZilla. It is inert outside
Herdr: without `HERDR_ENV=1` and the pane variables Herdr injects, it does
nothing at all.

Reports go out on a background thread through a single-slot mailbox, so a burst
of state changes coalesces to the newest one instead of queueing up behind a
slow Herdr. A report can never block a turn or raise into the transcript.

### Resume after a server restart

On **Herdr 0.10.0 and later**, ZimZilla also reports a resume command, so a
session comes back in the same pane after a Herdr server restart:

```bash
herdr pane report-agent "$HERDR_PANE_ID" \
  --source zimzilla --agent zimzilla --state idle --seq 2 \
  -- zimzilla --workdir /path/to/project --mode auto
```

On older versions the command is dropped and state reporting carries on alone.
This is deliberate: Herdr 0.9.x does not understand the `--` that introduces a
resume command and rejects the **entire report** with `unknown option: --`,
which would cost you the agent state completely. The reporter probes
`herdr --version` first and only sends a resume command to a Herdr that can
parse one.

Upgrade Herdr to get resume:

```bash
herdr update
```

---

## Troubleshooting

**ZimZilla does not appear in `herdr agent list`**

Check you are actually inside a Herdr pane:

```bash
echo "$HERDR_ENV"      # should print 1
echo "$HERDR_PANE_ID"  # should print something like w1:p2
```

If those are empty, ZimZilla is not running under Herdr and will stay silent by
design.

**It appeared and then vanished**

Herdr clears an agent once its pane is back at an idle shell prompt. If you
reported from a shell script rather than from ZimZilla itself, the agent is
cleared as soon as the script exits. ZimZilla holds the pane for as long as it
runs, so this does not affect normal use.

**It shows `unknown` instead of a state**

`unknown` means Herdr sees an agent but cannot classify it. ZimZilla reports
its own state, so this should not happen — check the plugin log:

```bash
herdr plugin log list --plugin zimzilla.herdr
```

**The `install` action says `herdr.py` is missing**

Your ZimZilla predates the Herdr integration. Update it:

```bash
cd ~/ZimZilla && git pull && ./setup.sh
```

**`herdr plugin link` refuses**

If a plugin with the same id is already registered, unlink it first:

```bash
herdr plugin unlink zimzilla.herdr
herdr plugin link ~/Documents/ZimZilla-Herdr-Plugin
```

---

## Files

```
herdr-plugin.toml   manifest — startup hook and two actions
install.sh          verifies the installed ZimZilla can report
status.sh           shows what Herdr currently sees
```

The startup hook runs `install.sh --quiet` once per Herdr server start. It is
silent when the integration is healthy, so a broken install shows up in
`herdr plugin log list --plugin zimzilla.herdr` rather than going unnoticed.

Both scripts are read-only. They install nothing and change nothing.

---

## Uninstall

```bash
herdr plugin unlink zimzilla.herdr
```

ZimZilla keeps reporting to Herdr if it is running in a pane — the plugin only
verifies and inspects, it is not what makes the integration work. To turn the
reporting off, remove `zimzilla/herdr.py` from your ZimZilla install, or run
ZimZilla outside Herdr.

---

## License

MIT
