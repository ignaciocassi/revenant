# CLAUDE.md

Reattach a restored Warp pane to its own Claude Code session. Zero-config
defaults plus a `revenant` CLI.

## Layout
- `record-session.sh` — POSIX `sh` SessionStart hook. Writes one record per pane
  to `$REVENANT_STATE_DIR/<pane>`: `sid \t cwd \t ts \t mode`. Always `exit 0`.
- `revenant.bash` — sourced from `~/.bashrc` (keep it LAST). Loads config,
  defines runtime + the `revenant()` dispatcher, and triggers the resume **at
  source time** (NOT PROMPT_COMMAND — that left Warp in block-editor mode and
  Claude got no keystrokes). Auto-trigger is the bottom `if`; guarded by
  interactive + `REVENANT_NOAUTO` + `REVENANT_ACTIVE` + `_REVENANT_RAN`.
- `revenant` — admin CLI (install/uninstall/doctor/config/account/enable/
  disable + read-only list/status). Sources the lib with `REVENANT_NOAUTO=1`.
- `install.sh` / `uninstall.sh` — thin wrappers to `revenant install/uninstall`.

## Config
`~/.revenant/config`: `key = value`, plus `account.<name>.config_dir` and
`account.<name>.roots` (colon-separated). Loaded into `RV_CFG` / `RV_ACCOUNT_DIR`
/ `RV_ACCOUNT_ROOTS` by `_revenant_load_config`. Env `REVENANT_*` overrides.
Keys: auto_resume(1) details(1) max_age(604800) resume_flags() default_account().

## Routing (`_revenant_resolve_cfg <sid> <cwd>`)
1. **Auto-detect** (`_revenant_cfg_by_transcript`): the config dir whose
   `projects/*/<sid>.jsonl` exists, among registered account dirs (or the single
   default). No roots needed.
2. Fallback (`_revenant_cfg_for <cwd>`): cwd under a non-default account's
   roots → that account; else default account (or `$CLAUDE_CONFIG_DIR`/`~/.claude`).
Resume runs `CLAUDE_CONFIG_DIR=<cfg> claude <resume_flags> --resume <sid>`.
`install` adds the hook to every registered account config dir.

## Invariants
- Pane key = `WARP_TERMINAL_SESSION_UUID` (bare hex). Validate everything read;
  never `eval`. Resolve `claude` to abs path before `cd`.
- Inert unless interactive Warp bash pane.

## Transcript format (`<config>/projects/*/<sid>.jsonl`)
Title: `custom-title` > `ai-title` > `summary` > first prompt. Real user prompts:
`type=="user"`, not sidechain/compact-summary/visible-only/meta, role user, string
content (skip tool_result lists), not starting with `<` or a `/slash-command`.

## Env quirks when testing
This session exports `CLAUDE_CONFIG_DIR` and (when running inside a resumed
pane) `REVENANT_ACTIVE=1`. Always test with `env -u CLAUDE_CONFIG_DIR -u
REVENANT_ACTIVE` or the auto-trigger is suppressed and routing hits the wrong
profile.
