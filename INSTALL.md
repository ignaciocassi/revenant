# Install

Step-by-step setup. See [README](README.md) for what it does.

## 1. Requirements

- **Warp** with *Settings → Session Restore* **on**
- **bash 5.x** (Warp's default shell on Linux)
- **Claude Code** installed and logged in (`claude` on your `PATH`)
- **Linux** (macOS likely works, untested)
- `git`; `python3` optional (improves the preview — works without it)

## 2. Get the code

```bash
git clone https://github.com/ignaciocassi/revenant ~/src/revenant
cd ~/src/revenant
```

## 3. Install

**Single account:**
```bash
./revenant install
```

**Everything in one command (multiple accounts + options):**
```bash
./revenant install \
  --account work=~/.claude \
  --account personal=~/.claude-personal
```

A fresh install turns on **auto-resume + details + skip-permissions**. Opt out
with `--no-skip-permissions` / `--no-auto-resume` / `--no-details`. Re-running
`install` never resets options you changed later unless you pass the flag again.

It does, idempotently:

- Copies `record-session.sh`, `revenant.bash` and the CLI to **`~/.revenant/`**.
- Links the CLI to **`~/.local/bin/revenant`** (if it's on your `PATH`).
- Creates **`~/.revenant/config`**.
- Adds the `SessionStart` hook to each account's **`settings.json`** (with a backup).
- Appends a single `source ~/.revenant/revenant.bash` line to **`~/.bashrc`**.

## 4. Open a NEW Warp tab

Needed to load the `.bashrc` line and the new hook. Already-open tabs won't pick
it up until you reopen them (or run `source ~/.bashrc`).

## 5. Verify

```bash
revenant doctor      # you want everything green
```

## 6. Use it

1. In a pane: `claude` → work normally (the hook has recorded *this pane = this session*).
2. (Optional) `revenant list` → shows your pane marked with `→`.
3. **Close and reopen Warp** → each restored pane resumes its session automatically.

## Multiple Claude accounts

If you use several `CLAUDE_CONFIG_DIR`s (e.g. work/personal), just register each
dir. On resume the account is **auto-detected** by finding which dir holds the
session's transcript:

```bash
revenant account add work ~/.claude
revenant account add personal ~/.claude-personal
revenant install                      # adds the hook into EACH account
```

The `SessionStart` hook has to live in every account's `settings.json` (that's
how Claude Code finds hooks), so `install` adds it to all registered dirs at
once. With no accounts configured it runs in single-account mode
(`$CLAUDE_CONFIG_DIR` or `~/.claude`).

> Optional fallback: give an account a colon-separated list of folders (roots)
> and set a default account, for records whose transcript has already been
> pruned. Resolution order: transcript auto-detect → roots → default.

## Everyday commands

| Command | What it does |
| --- | --- |
| `revenant resume` | resume this pane now |
| `revenant list` | pane → session mappings |
| `revenant forget` | drop this pane's record |
| `revenant status` | effective config + this pane |
| `revenant doctor` | environment diagnostics |

## Uninstall

```bash
revenant uninstall           # hook + ~/.bashrc line + ~/.revenant + CLI link
revenant uninstall --purge   # also deletes the .bak backups the installer left
```

Your conversations (`~/.claude*/projects/`) are left untouched. After
uninstalling, already-open tabs keep the old functions in memory until you open
a new tab.

## Installing with an agent (Claude Code)

Instead of running the steps yourself, you can ask an agent to install following
this guide. Open Claude Code **inside the repo** and give it a prompt like:

```
Install revenant on this system following INSTALL.md.
Base + multi-account (auto-detect, no roots):
  - account add work     ~/.claude
  - account add personal ~/.claude-personal
  - enable skip-permissions
  - revenant install   (adds the hook into both accounts)
When done, run `revenant doctor` and show me the output.
Don't touch anything outside what INSTALL.md says; if something exists, don't duplicate it.
```

Then **open a new Warp tab** yourself (the agent can't do that).

> Note for the agent: on this machine the Claude Code shell may export
> `CLAUDE_CONFIG_DIR` and `REVENANT_ACTIVE`; run the commands with
> `env -u CLAUDE_CONFIG_DIR -u REVENANT_ACTIVE` so the environment matches a
> fresh user's.
