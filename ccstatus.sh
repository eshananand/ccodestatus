#!/bin/zsh

# Exit silently if no stdin
if [[ -t 0 ]]; then
  exit 0
fi

raw=$(cat)
if [[ -z "$raw" ]]; then
  exit 0
fi

# --- Stage 1: JSON parsing via inline Python (no temp file) ---
pycode=$(cat << 'PYEOF'
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("ERROR")
    sys.exit(0)

def safe_str(v):
    """Return empty string for None/null; str() for everything else."""
    return "" if v is None else str(v)

m  = d.get("model", {}) or {}
cw = d.get("context_window", {}) or {}
c  = d.get("cost", {}) or {}
rl = d.get("rate_limits", {}) or {}
fh = rl.get("five_hour") or {}
sd = rl.get("seven_day") or {}

# cwd: prefer workspace.current_dir (more stable), fall back to top-level cwd
cwd = (d.get("workspace") or {}).get("current_dir") or d.get("cwd", "")

# Worktree name: --worktree sessions expose worktree.name; linked worktrees use workspace.git_worktree
worktree = (d.get("worktree") or {}).get("name") or (d.get("workspace") or {}).get("git_worktree") or ""

# context_window.used_percentage can be null early in a session — guard it
ctx_pct = cw.get("used_percentage")
ctx_pct_str = "—" if ctx_pct is None else str(ctx_pct)

fields = [
    m.get("display_name", "—"),
    ctx_pct_str,
    str(c.get("total_cost_usd", "—")),
    str(c.get("total_duration_ms", "—")),
    cwd,
    worktree,
    safe_str(fh.get("used_percentage")),
    safe_str(fh.get("resets_at")),
    safe_str(sd.get("used_percentage")),
    safe_str(sd.get("resets_at")),
]
print("|".join(fields))
PYEOF
)

parsed=$(printf '%s' "$raw" | python3 -c "$pycode")

if [[ "$parsed" == "ERROR" ]]; then
  echo "ccstatus: parse error"
  exit 0
fi

# Split pipe-separated fields — pipes are non-whitespace IFS chars, so empty fields are preserved
IFS='|' read -r model ctx_pct cost_usd duration_ms cwd worktree rate_5h rate_5h_resets rate_7d rate_7d_resets <<< "$parsed"

# --- Stage 2: Format derived values ---

# Cost: format to 2 decimal places, prefix with $
if [[ "$cost_usd" != "—" && "$cost_usd" != "" ]]; then
  cost_fmt=$(printf '$%.2f' "$cost_usd")
else
  cost_fmt="—"
fi

# Context: append % symbol
if [[ "$ctx_pct" != "—" && "$ctx_pct" != "" ]]; then
  ctx_fmt="${ctx_pct}%"
else
  ctx_fmt="—"
fi

# Duration: convert ms to MM:SS or HH:MM:SS
if [[ "$duration_ms" != "—" && "$duration_ms" != "" ]]; then
  total_sec=$(( ${duration_ms%.*} / 1000 ))
  hrs=$(( total_sec / 3600 ))
  mins=$(( (total_sec % 3600) / 60 ))
  secs=$(( total_sec % 60 ))
  if (( hrs > 0 )); then
    clock_fmt=$(printf '%d:%02d:%02d' $hrs $mins $secs)
  else
    clock_fmt=$(printf '%d:%02d' $mins $secs)
  fi
else
  clock_fmt="—"
fi

# Rate limit helper: color-grade a percentage (>=80 red, >=50 yellow, else green)
# Note: color variables (C_RED, C_YELLOW, C_GREEN) are defined in Stage 4 before this is called.
pct_color() {
  local pct=$1
  if (( pct >= 80 )); then printf '%s' "$C_RED"
  elif (( pct >= 50 )); then printf '%s' "$C_YELLOW"
  else printf '%s' "$C_GREEN"
  fi
}

# Rate limit reset-time helpers (resets_at is a unix epoch in seconds)
# macOS: date -r <epoch>; GNU/Linux: date -d "@<epoch>"; gracefully silent on failure.
fmt_hhmm() {
  local epoch="$1"
  [[ -z "$epoch" ]] && return
  date -r "$epoch" "+%H:%M" 2>/dev/null || date -d "@$epoch" "+%H:%M" 2>/dev/null || true
}
fmt_weekday_hhmm() {
  local epoch="$1"
  [[ -z "$epoch" ]] && return
  date -r "$epoch" "+%a %H:%M" 2>/dev/null || date -d "@$epoch" "+%a %H:%M" 2>/dev/null || true
}

# --- Stage 3: Git info ---
branch=""
repo=""
if [[ -n "$cwd" ]] && command -v git &>/dev/null; then
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
  wt_path=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
  if [[ -n "$wt_path" ]]; then
    repo="${wt_path:t}"
  fi
fi

# --- Stage 4: ANSI output ---
# Colors (256-color level 2)
C_CYAN='\033[36m'
C_DIM='\033[90m'
C_MAGENTA='\033[35m'
C_YELLOW='\033[33m'
C_GREEN='\033[32m'
C_RED='\033[31m'
C_RESET='\033[0m'
SEP=" │ "

# Line 1: model | context% | $cost | clock
line1="${C_CYAN}${model}${C_RESET}${SEP}${C_DIM}${ctx_fmt}${C_RESET}${SEP}${C_MAGENTA}${cost_fmt}${C_RESET}${SEP}${C_YELLOW}${clock_fmt}${C_RESET}"

# Line 2: branch | repo [| wt:<name>]  — skip when no git info and no worktree
if [[ -n "$branch" || -n "$repo" || -n "$worktree" ]]; then
  line2="${branch:-—}${SEP}${repo:-—}"
  if [[ -n "$worktree" ]]; then
    line2="${line2}${SEP}wt:${worktree}"
  fi
else
  line2=""
fi

# Line 3: rate limits — only present for Claude.ai Pro/Max subscribers after the first API
# response in a session. Each window (5h / 7d) may be independently absent.
line3=""
if [[ -n "$rate_5h" ]]; then
  rate_5h_int=$(printf '%.0f' "$rate_5h")
  rate_5h_color=$(pct_color "$rate_5h_int")
  reset_5h_str=""
  if [[ -n "$rate_5h_resets" ]]; then
    t=$(fmt_hhmm "$rate_5h_resets")
    [[ -n "$t" ]] && reset_5h_str="${C_DIM} @${t}${C_RESET}"
  fi
  line3="${rate_5h_color}5h:${rate_5h_int}%${C_RESET}${reset_5h_str}"
fi
if [[ -n "$rate_7d" ]]; then
  rate_7d_int=$(printf '%.0f' "$rate_7d")
  rate_7d_color=$(pct_color "$rate_7d_int")
  reset_7d_str=""
  if [[ -n "$rate_7d_resets" ]]; then
    t=$(fmt_weekday_hhmm "$rate_7d_resets")
    [[ -n "$t" ]] && reset_7d_str="${C_DIM} @${t}${C_RESET}"
  fi
  rate_7d_part="${rate_7d_color}7d:${rate_7d_int}%${C_RESET}${reset_7d_str}"
  if [[ -n "$line3" ]]; then
    line3="${line3}${SEP}${rate_7d_part}"
  else
    line3="$rate_7d_part"
  fi
fi

# Output
echo -e "$line1"
if [[ -n "$line2" ]]; then
  echo -e "$line2"
fi
if [[ -n "$line3" ]]; then
  echo -e "$line3"
fi
echo ""
