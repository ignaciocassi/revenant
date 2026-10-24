# Revenant - Auto-restore Claude Code sessions in Warp

Warp restores your terminal panes after a restart — but the **Claude Code**
sessions that were running inside them don't. This reattaches each restored pane
to *its own* conversation.

Two panes open on the same repo come back to their two different sessions, not to
"whatever ran there last".

![demo](https://www.image2url.com/r2/default/gifs/1792872851398-e3eca7ed-ee9d-42a6-af5a-016c1103d253.gif)

## How it works

Warp gives every local pane a stable id (`WARP_TERMINAL_SESSION_UUID`) that
survives a restart — a restored pane keeps its value, a new pane gets a fresh one.

1. A Claude Code **`SessionStart` hook** records which session runs in which pane.
2. When your shell starts, `revenant.bash` (sourced from `~/.bashrc`) looks up
   the current pane and resumes its session.

The resume runs at shell-init time, not from `PROMPT_COMMAND`, so Claude gets the
terminal before Warp's block editor engages. Only sessions started after you
install are tracked.

## Requirements

- **Warp** with session restore enabled
- **bash 5.x**, on **Linux**
- **Claude Code** — `claude` on your `PATH`
- `python3` (optional — nicer session preview)

## Install

```bash
git clone https://github.com/ignaciocassi/revenant ~/src/revenant
cd ~/src/revenant
./revenant install
```

Open a **new Warp tab**, then verify:

```bash
revenant doctor
```

By default a recorded pane resumes automatically, shows a short preview of the
session, and launches with `--dangerously-skip-permissions`.

### Multiple Claude accounts

If you use more than one `CLAUDE_CONFIG_DIR`, register each one in the same
command. The right account is auto-detected from where the session's transcript
lives, and `claude` runs with the matching `CLAUDE_CONFIG_DIR`:

```bash
./revenant install \
  --account work=~/.claude \
  --account personal=~/.claude-personal
```

## Commands

```
revenant resume     resume this pane's session now
revenant list       recorded pane → session mappings
revenant status     effective config + this pane
revenant doctor     check environment + install
revenant config     list | get <k> | set <k> <v> | unset <k>
revenant account    list | add <name> <dir> | remove <name>
revenant enable|disable   auto-resume | details | skip-permissions
revenant uninstall [--purge]
```

`resume` acts on the current shell (it's a shell function); the rest work from
any shell.

## Config

Stored in `~/.revenant/config` — edit it through the CLI, not by hand.
`~/.bashrc` only needs the single `source` line, kept **last**.

| key | default | meaning |
| --- | --- | --- |
| `auto_resume` | `1` | resume without asking (the `[Y/n]` prompt is fragile in Warp) |
| `details` | `1` | show the session preview (title / age / size / prompts) |
| `max_age` | `604800` | ignore records older than N seconds (7 days) |
| `resume_flags` | `--dangerously-skip-permissions` | extra flags passed on every resume |

Quick toggles:

```bash
revenant disable skip-permissions   # resume without --dangerously-skip-permissions
revenant disable auto-resume        # go back to a [Y/n] prompt
revenant config set max_age 0       # records never expire
```

## Uninstall

```bash
revenant uninstall           # removes the hook, the ~/.bashrc line, ~/.revenant, CLI link
revenant uninstall --purge   # also deletes the .bak backups the installer left
```

Your conversations (`~/.claude*/projects/`) are never touched.

## Notes

- Inert outside an interactive Warp bash pane — safe to source anywhere.
- Everything read from disk/JSON is validated before use; the recorder never
  calls `eval`, and records hold no conversation content (session id, dir,
  timestamp, mode only).
- `WARP_TERMINAL_SESSION_UUID` is undocumented; if Warp ever drops it, panes
  simply stop being offered a resume.
- zsh / fish / SSH panes are out of scope.

## License

MIT — see [LICENSE](LICENSE).
