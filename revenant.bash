# revenant.bash — reattach a restored Warp pane to its Claude Code session.
#
# Zero-config by default, configured through ~/.revenant/config (edited with
# the `revenant` CLI, not by hand). Source this near the END of your
# ~/.bashrc:
#
#     source ~/.revenant/revenant.bash
#
# Everything here is INERT unless the shell is an interactive Warp bash pane, so
# it is safe to source unconditionally. See `revenant help`.

# ---------------------------------------------------------------------------
# paths + config
# ---------------------------------------------------------------------------
: "${REVENANT_HOME:=$HOME/.revenant}"
: "${REVENANT_CONFIG_FILE:=$REVENANT_HOME/config}"
: "${REVENANT_STATE_DIR:=$REVENANT_HOME/panes}"
# The Warp client version this was tested against (doctor warns on mismatch).
: "${REVENANT_TESTED_WARP:=v0.2026.10}"

# Effective config (filled by _revenant_load_config). Defaults chosen so a
# fresh install with an empty config file "just works".
declare -gA RV_CFG 2>/dev/null || true
declare -gA RV_ACCOUNT_DIR 2>/dev/null || true
declare -gA RV_ACCOUNT_ROOTS 2>/dev/null || true

_revenant_defaults() {
    RV_CFG=(
        [auto_resume]=1
        [details]=1
        [max_age]=604800
        [resume_flags]=""
        [disable]=0
        [default_account]=""
    )
    RV_ACCOUNT_DIR=()
    RV_ACCOUNT_ROOTS=()
}

# Load ~/.revenant/config (simple "key = value", plus account.<name>.<field>).
# Env vars REVENANT_* still override, for quick one-off toggles.
_revenant_load_config() {
    _revenant_defaults
    local line key val n
    if [[ -f $REVENANT_CONFIG_FILE ]]; then
        while IFS= read -r line || [[ -n $line ]]; do
            line="${line%%#*}"
            [[ $line == *=* ]] || continue
            key="${line%%=*}"; val="${line#*=}"
            # trim both
            key="${key#"${key%%[![:space:]]*}"}"; key="${key%"${key##*[![:space:]]}"}"
            val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
            case "$key" in
                account.*.config_dir) n="${key#account.}"; n="${n%.config_dir}"
                                      RV_ACCOUNT_DIR[$n]="${val/#\~/$HOME}" ;;
                account.*.roots)      n="${key#account.}"; n="${n%.roots}"
                                      RV_ACCOUNT_ROOTS[$n]="$val" ;;
                auto_resume|details|max_age|resume_flags|disable|default_account)
                                      RV_CFG[$key]="$val" ;;
            esac
        done < "$REVENANT_CONFIG_FILE"
    fi
    # env overrides
    [[ -n ${REVENANT_DISABLE:-}  ]] && RV_CFG[disable]="$REVENANT_DISABLE"
    [[ -n ${REVENANT_AUTO:-}     ]] && RV_CFG[auto_resume]="$REVENANT_AUTO"
    [[ -n ${REVENANT_DETAILS:-}  ]] && RV_CFG[details]="$REVENANT_DETAILS"
    [[ -n ${REVENANT_MAX_AGE:-}  ]] && RV_CFG[max_age]="$REVENANT_MAX_AGE"
    return 0
}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
_revenant_pane() {
    local p="${WARP_TERMINAL_SESSION_UUID:-}"
    [[ $p =~ ^[0-9a-fA-F]{16,64}$ ]] || return 1
    printf '%s' "$p"
}

_revenant_is_valid_sid() {
    local s="$1"
    [[ -n $s && ${#s} -le 64 && $s != -* && $s =~ ^[A-Za-z0-9_-]+$ ]]
}

# Which Claude config dir owns a session started in <cwd>?
# No accounts configured => single-account mode (CLAUDE_CONFIG_DIR or ~/.claude).
_revenant_cfg_for() {
    local cwd="$1" name roots root def
    if [[ ${#RV_ACCOUNT_DIR[@]} -eq 0 ]]; then
        printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; return
    fi
    def="${RV_CFG[default_account]}"
    for name in "${!RV_ACCOUNT_DIR[@]}"; do
        [[ $name == "$def" ]] && continue
        roots="${RV_ACCOUNT_ROOTS[$name]:-}"
        [[ -n $roots ]] || continue
        local IFS=:
        for root in $roots; do
            root="${root/#\~/$HOME}"
            [[ -n $root ]] || continue
            if [[ $cwd == "$root" || $cwd == "$root"/* ]]; then
                printf '%s' "${RV_ACCOUNT_DIR[$name]}"; return
            fi
        done
    done
    if [[ -n $def && -n ${RV_ACCOUNT_DIR[$def]:-} ]]; then
        printf '%s' "${RV_ACCOUNT_DIR[$def]}"
    else
        printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    fi
}

# All config dirs to consider (registered accounts, else the single default).
_revenant_candidate_dirs() {
    if [[ ${#RV_ACCOUNT_DIR[@]} -gt 0 ]]; then
        local n; for n in "${!RV_ACCOUNT_DIR[@]}"; do printf '%s\n' "${RV_ACCOUNT_DIR[$n]}"; done
    else
        printf '%s\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    fi
}

# Config dir whose projects/ actually holds the transcript for <sid>, if any.
# This is the "auto-detect" path: no roots/default needed — the session's own
# transcript tells us which account it belongs to.
_revenant_cfg_by_transcript() {
    local sid="$1" d f found=""
    _revenant_is_valid_sid "$sid" || return 1
    shopt -s nullglob
    while IFS= read -r d; do
        [[ -d $d/projects ]] || continue
        for f in "$d"/projects/*/"$sid".jsonl; do found="$d"; break; done
        [[ -n $found ]] && break
    done < <(_revenant_candidate_dirs)
    shopt -u nullglob
    [[ -n $found ]] || return 1
    printf '%s' "$found"
}

# Resolve the config dir for a session: transcript auto-detect first, then fall
# back to cwd/roots routing (for records whose transcript is already gone).
_revenant_resolve_cfg() {
    local sid="$1" cwd="$2" cfg
    cfg="$(_revenant_cfg_by_transcript "$sid")" && { printf '%s' "$cfg"; return; }
    _revenant_cfg_for "$cwd"
}

# Account name for a config dir (for display).
_revenant_account_of() {
    local cfg="$1" name
    for name in "${!RV_ACCOUNT_DIR[@]}"; do
        [[ ${RV_ACCOUNT_DIR[$name]} == "$cfg" ]] && { printf '%s' "$name"; return; }
    done
    return 1
}

_revenant_transcript() {
    local sid="$1" tdir="$2" newest="" f
    _revenant_is_valid_sid "$sid" || return 1
    [[ -d $tdir ]] || return 1
    shopt -s nullglob
    for f in "$tdir"/*/"$sid".jsonl; do
        [[ -z $newest || $f -nt $newest ]] && newest="$f"
    done
    shopt -u nullglob
    [[ -n $newest ]] || return 1
    printf '%s' "$newest"
}

_revenant_age() {
    local then="$1" now diff
    now="$(date +%s 2>/dev/null)" || { printf '?'; return; }
    diff=$(( now - then )); (( diff < 0 )) && diff=0
    if   (( diff < 60 ));    then printf '%ds ago' "$diff"
    elif (( diff < 3600 ));  then printf '%dm ago' "$(( diff/60 ))"
    elif (( diff < 86400 )); then printf '%dh ago' "$(( diff/3600 ))"
    else                          printf '%dd ago' "$(( diff/86400 ))"; fi
}

_revenant_size() {
    local b="$1"
    if   (( b < 1024 ));    then printf '%dB' "$b"
    elif (( b < 1048576 )); then printf '%dK' "$(( b/1024 ))"
    else LC_ALL=C awk -v x="$b" 'BEGIN{printf "%.1fM", x/1048576}'; fi
}

# Parse title / count / first / last from a transcript (python if present).
_revenant_parse() {
    local file="$1"
    command -v python3 >/dev/null 2>&1 || { printf '\x1f0\x1f\x1f'; return; }
    python3 -I -c '
import sys, json, unicodedata
path = sys.argv[1]; US = "\x1f"
def clean(s):
    if not isinstance(s, str): return ""
    return "".join(c for c in s if unicodedata.category(c) not in ("Cc","Cf","Zl","Zp")).strip()
def text_of(c):
    if isinstance(c, str): return c
    if isinstance(c, list): return " ".join(b.get("text","") for b in c if isinstance(b,dict) and b.get("type")=="text")
    return ""
custom=ai=summary=None; count=0; first=last=None
try: fh=open(path,encoding="utf-8",errors="replace")
except Exception: print(US.join(["","0","",""])); sys.exit(0)
with fh:
    for line in fh:
        line=line.strip()
        if not line: continue
        try: d=json.loads(line)
        except Exception: continue
        t=d.get("type")
        if   t=="custom-title": custom=d.get("customTitle") or custom
        elif t=="ai-title":     ai=d.get("aiTitle") or ai
        elif t=="summary":      summary=d.get("summary") or summary
        elif t=="user":
            if d.get("isSidechain") or d.get("isCompactSummary") or d.get("isVisibleInTranscriptOnly") or d.get("isMeta"): continue
            m=d.get("message") or {}
            if m.get("role")!="user": continue
            c=m.get("content")
            if isinstance(c,list) and all(isinstance(b,dict) and b.get("type")=="tool_result" for b in c): continue
            txt=clean(text_of(c))
            if not txt or txt.startswith("<"): continue
            if txt.startswith("/") and " " not in txt.split("\n",1)[0]: continue
            count+=1
            if first is None: first=txt
            last=txt
title=custom or ai or summary or first or ""
def trunc(s,n):
    s=clean(s); return (s[:n-1]+"…") if len(s)>n else s
print(US.join([trunc(title,72), str(count), trunc(first or "",100), trunc(last or "",100)]))
' "$file" 2>/dev/null
}

# ---------------------------------------------------------------------------
# core: offer / perform the reattach
# ---------------------------------------------------------------------------
_revenant_reattach() {
    local force="${1:-}"
    [[ ${RV_CFG[disable]} == 1 ]] && return 0
    [[ -n ${REVENANT_ACTIVE:-} ]] && return 0
    [[ ${WARP_IS_LOCAL_SHELL_SESSION:-0} == 1 ]] || { [[ $force == resume ]] && echo "revenant: not a local Warp shell"; return 0; }

    local pane; pane="$(_revenant_pane)" || { [[ $force == resume ]] && echo "revenant: no Warp pane id"; return 0; }
    local rec="$REVENANT_STATE_DIR/$pane"
    [[ -f $rec ]] || { [[ $force == resume ]] && echo "revenant: nothing recorded for this pane"; return 0; }

    local sid cwd ts pmode
    IFS=$'\t' read -r sid cwd ts pmode < "$rec" || return 0
    _revenant_is_valid_sid "$sid" || { [[ $force == resume ]] && echo "revenant: bad session id in record"; return 1; }
    [[ $cwd == /* ]] || { [[ $force == resume ]] && echo "revenant: bad directory in record"; return 1; }
    [[ $ts =~ ^[0-9]+$ ]] || ts=0

    if [[ $force != resume && ${RV_CFG[max_age]} -gt 0 ]]; then
        local now; now="$(date +%s 2>/dev/null)" || now=0
        (( now - ts > ${RV_CFG[max_age]} )) && return 0
    fi

    local bin; bin="$(command -v claude 2>/dev/null)" || { [[ $force == resume ]] && echo "revenant: 'claude' not found on PATH"; return 1; }

    local cfg tdir acct
    cfg="$(_revenant_resolve_cfg "$sid" "$cwd")"
    tdir="$cfg/projects"
    acct="$(_revenant_account_of "$cfg" 2>/dev/null || true)"

    if [[ ${RV_CFG[details]} != 0 ]]; then
        local file title count first last age size
        file="$(_revenant_transcript "$sid" "$tdir")" || file=""
        if [[ -n $file ]]; then
            local parsed; parsed="$(_revenant_parse "$file")"
            IFS=$'\x1f' read -r title count first last <<< "$parsed"
            local mtime bytes
            mtime="$(stat -c %Y "$file" 2>/dev/null)" || mtime="$ts"
            bytes="$(stat -c %s "$file" 2>/dev/null)" || bytes=0
            age="$(_revenant_age "${mtime:-$ts}")"; size="$(_revenant_size "${bytes:-0}")"
        else
            age="$(_revenant_age "$ts")"; size="?"; count="?"
        fi
        printf '\n\033[1;36m⟲ Warp pane has a Claude Code session\033[0m\n'
        [[ -n ${title:-} ]] && printf '  \033[1m%s\033[0m\n' "$title"
        printf '  dir:     %s\n' "$cwd"
        printf '  session: %s  ·  %s  ·  %s  ·  %s prompts%s\n' \
               "${sid:0:8}…" "${age:-?}" "${size:-?}" "${count:-?}" \
               "${acct:+  ·  $acct}"
        [[ -n ${first:-} ]] && printf '  first:   %s\n' "$first"
        [[ -n ${last:-}  ]] && printf '  last:    %s\n' "$last"
        printf '\n'
    fi

    if [[ ${RV_CFG[auto_resume]} != 1 && $force != force ]]; then
        local reply
        if [[ -t 0 ]]; then
            printf '\033[?1004l'
            local _flush
            while read -rs -t 0.15 -n 1 _flush 2>/dev/null; do :; done
        fi
        printf '\033[1mResume this session?\033[0m [Y/n] '
        IFS= read -r reply || { [[ -t 0 ]] && printf '\033[?1004h'; return 0; }
        [[ -t 0 ]] && printf '\033[?1004h'
        reply="${reply//$'\e'/}"; reply="${reply//[$'\x01'-$'\x1f']/}"
        reply="${reply#\[I}"; reply="${reply#\[O}"
        case "$reply" in
            ''|y|Y|yes|YES|s|S|si|Si|SI|sí|Sí ) : ;;
            * ) echo "revenant: skipped (run 'revenant resume' to resume later)"; return 0 ;;
        esac
    fi

    builtin cd -- "$cwd" 2>/dev/null || { echo "revenant: cannot cd to $cwd"; return 1; }
    local extra=(); [[ -n ${RV_CFG[resume_flags]} ]] && read -r -a extra <<< "${RV_CFG[resume_flags]}"
    CLAUDE_CONFIG_DIR="$cfg" REVENANT_ACTIVE=1 "$bin" "${extra[@]}" --resume "$sid"
    local rc=$?
    case "$rc" in 0|1|130) : ;; *) echo "revenant: claude exited with status $rc" ;; esac
    return 0
}

# ---------------------------------------------------------------------------
# runtime commands (need the current shell)
# ---------------------------------------------------------------------------
_revenant_cmd_forget() {
    local pane; pane="$(_revenant_pane)" || { echo "revenant: no pane id"; return 1; }
    local rec="$REVENANT_STATE_DIR/$pane"
    if [[ -f $rec ]]; then rm -f "$rec" && echo "revenant: forgot this pane's record"
    else echo "revenant: nothing recorded for this pane"; fi
}

_revenant_cmd_list() {
    [[ -d $REVENANT_STATE_DIR ]] || { echo "revenant: no records"; return 0; }
    local f pane sid cwd ts pmode cur any=0
    cur="$(_revenant_pane 2>/dev/null)"
    shopt -s nullglob
    for f in "$REVENANT_STATE_DIR"/*; do
        [[ -f $f ]] || continue
        any=1; pane="$(basename "$f")"
        IFS=$'\t' read -r sid cwd ts pmode < "$f"
        local mark="  "; [[ $pane == "$cur" ]] && mark="\033[1;32m→ \033[0m"
        local acct; acct="$(_revenant_account_of "$(_revenant_resolve_cfg "$sid" "$cwd")" 2>/dev/null || true)"
        printf '%b%s  %s  %s  %s%s\n' "$mark" "${pane:0:8}…" "${sid:0:8}…" \
               "$(_revenant_age "${ts:-0}")" "$cwd" "${acct:+  [$acct]}"
    done
    shopt -u nullglob
    (( any )) || echo "revenant: no records"
}

_revenant_cmd_status() {
    echo "revenant status"
    printf '  home:        %s\n' "$REVENANT_HOME"
    printf '  config:      %s%s\n' "$REVENANT_CONFIG_FILE" \
           "$([[ -f $REVENANT_CONFIG_FILE ]] || printf ' (none; using defaults)')"
    printf '  auto_resume: %s   details: %s   max_age: %ss\n' \
           "${RV_CFG[auto_resume]}" "${RV_CFG[details]}" "${RV_CFG[max_age]}"
    printf '  resume_flags:%s\n' "${RV_CFG[resume_flags]:+ ${RV_CFG[resume_flags]}}"
    if [[ ${#RV_ACCOUNT_DIR[@]} -gt 0 ]]; then
        local n
        printf '  accounts:\n'
        for n in "${!RV_ACCOUNT_DIR[@]}"; do
            printf '    - %-10s %s%s%s\n' "$n" "${RV_ACCOUNT_DIR[$n]}" \
                   "${RV_ACCOUNT_ROOTS[$n]:+  roots=${RV_ACCOUNT_ROOTS[$n]}}" \
                   "$([[ $n == ${RV_CFG[default_account]} ]] && printf '  (default)')"
        done
    else
        printf '  accounts:    single (%s)\n' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    fi
    local pane; if pane="$(_revenant_pane 2>/dev/null)"; then
        printf '  this pane:   %s%s\n' "${pane:0:8}…" \
               "$([[ -f $REVENANT_STATE_DIR/$pane ]] && printf ' (has a record)' || printf ' (no record yet)')"
    else
        printf '  this pane:   (not a Warp pane)\n'
    fi
}

# ---------------------------------------------------------------------------
# dispatcher: `revenant <cmd>`. Runtime cmds run here; admin cmds go to the
# standalone CLI on PATH (which can edit config/settings/bashrc).
# ---------------------------------------------------------------------------
revenant() {
    _revenant_load_config
    case "${1:-}" in
        resume)  shift; _revenant_reattach resume "$@" ;;
        list)    shift; _revenant_cmd_list "$@" ;;
        forget)  shift; _revenant_cmd_forget "$@" ;;
        status)  shift; _revenant_cmd_status "$@" ;;
        ''|help|-h|--help)
            command -v revenant >/dev/null 2>&1 && [[ -x "$(command -v revenant 2>/dev/null)" ]] \
                && command revenant help 2>/dev/null && return 0
            cat <<'EOF'
revenant — reattach restored Warp panes to their Claude Code session
  resume | list | forget | status
  install | uninstall | doctor | config | account | enable | disable
EOF
            ;;
        *)       command revenant "$@" ;;
    esac
}

# ---------------------------------------------------------------------------
# auto-trigger once, at the END of shell init (NOT PROMPT_COMMAND — see README).
# ---------------------------------------------------------------------------
if [[ $- == *i* && -z ${REVENANT_NOAUTO:-} && -z ${REVENANT_ACTIVE:-} \
      && -z ${_REVENANT_RAN:-} ]]; then
    _REVENANT_RAN=1
    _revenant_load_config
    [[ ${RV_CFG[disable]} == 1 ]] || _revenant_reattach
fi
