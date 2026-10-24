#!/bin/sh
# record-session.sh — Claude Code SessionStart hook.
#
# Records which Claude Code session is running in which Warp pane, so that a
# pane restored by Warp (which keeps its WARP_TERMINAL_SESSION_UUID) can be
# reattached to exactly its own conversation later.
#
# One record file per pane:  $REVENANT_STATE_DIR/<pane-uuid>
# Format (tab-separated, single line):
#     <session_id>\t<cwd>\t<unix_ts>\t<permission_mode>
#
# Reads the hook JSON payload from stdin. Always exits 0 so it never blocks
# Claude Code from starting, whatever happens here.

set -u

# --- pane key -------------------------------------------------------------
# Warp exports this into every local pane. Restored panes keep their value;
# new panes get a fresh one. No pane id -> nothing to record.
pane="${WARP_TERMINAL_SESSION_UUID:-}"
case "$pane" in
    '' ) exit 0 ;;
    # must be a bare hex string (what Warp emits); reject anything odd.
    *[!0-9a-fA-F]* ) exit 0 ;;
esac
[ "${#pane}" -ge 16 ] && [ "${#pane}" -le 64 ] || exit 0

state_dir="${REVENANT_STATE_DIR:-$HOME/.revenant/panes}"

# --- read payload ---------------------------------------------------------
payload="$(cat 2>/dev/null)" || payload=""
[ -n "$payload" ] || exit 0

# Extract session_id, cwd, permission_mode from the JSON. Prefer python3
# (robust); fall back to a conservative grep/sed that never runs eval.
sid=""; cwd=""; pmode=""
if command -v python3 >/dev/null 2>&1; then
    fields="$(printf '%s' "$payload" | python3 -I -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
def g(k):
    v = d.get(k, "")
    return v if isinstance(v, str) else ""
print(g("session_id"))
print(g("cwd"))
print(g("permission_mode"))
' 2>/dev/null)" || fields=""
    sid="$(printf '%s\n' "$fields" | sed -n '1p')"
    cwd="$(printf '%s\n' "$fields" | sed -n '2p')"
    pmode="$(printf '%s\n' "$fields" | sed -n '3p')"
else
    # Minimal fallback: pull the first "key":"value" occurrences.
    sid="$(printf '%s' "$payload" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    cwd="$(printf '%s' "$payload" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    pmode="$(printf '%s' "$payload" | sed -n 's/.*"permission_mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
fi

# --- validate -------------------------------------------------------------
# session id: [A-Za-z0-9_-], not starting with '-', max 64 chars.
[ -n "$sid" ] || exit 0
[ "${#sid}" -le 64 ] || exit 0
case "$sid" in
    -* ) exit 0 ;;
    *[!A-Za-z0-9_-]* ) exit 0 ;;
esac

# cwd: absolute, no control characters. Fall back to $PWD if unusable.
case "$cwd" in
    /* ) : ;;
    * ) cwd="$PWD" ;;
esac
# strip if it contains a control char (newline/tab would break the record).
case "$cwd" in
    *"$(printf '\t')"* ) exit 0 ;;
esac
printf '%s' "$cwd" | LC_ALL=C grep -q '[[:cntrl:]]' && exit 0

# permission mode: allowlist only; otherwise store empty.
case "$pmode" in
    default|plan|acceptEdits|bypassPermissions ) : ;;
    * ) pmode="" ;;
esac

# --- write record atomically ---------------------------------------------
mkdir -p "$state_dir" 2>/dev/null || exit 0
chmod 0700 "$state_dir" 2>/dev/null
# also lock down the parent (~/.revenant)
parent="$(dirname "$state_dir")"
[ "$parent" != "$state_dir" ] && chmod 0700 "$parent" 2>/dev/null

ts="$(date +%s 2>/dev/null)" || ts=0
tmp="$state_dir/.tmp.$pane.$$"
rec="$(printf '%s\t%s\t%s\t%s' "$sid" "$cwd" "$ts" "$pmode")"

( umask 077; printf '%s\n' "$rec" > "$tmp" ) 2>/dev/null || exit 0
chmod 0600 "$tmp" 2>/dev/null
mv -f "$tmp" "$state_dir/$pane" 2>/dev/null || rm -f "$tmp" 2>/dev/null

exit 0
