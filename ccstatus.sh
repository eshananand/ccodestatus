#!/bin/zsh

# Exit silently if no stdin
if [[ -t 0 ]]; then
  exit 0
fi

raw=$(cat)
if [[ -z "$raw" ]]; then
  exit 0
fi

# --- Stage 1: JSON parsing via temp Python file ---
tmp_py=$(mktemp /tmp/ccstatus.XXXXXX.py)
cat > "$tmp_py" << 'PYEOF'
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("ERROR")
    sys.exit(0)
m = d.get("model", {})
cw = d.get("context_window", {})
c = d.get("cost", {})
fields = [
    m.get("display_name", "\u2014"),
    str(cw.get("used_percentage", "\u2014")),
    str(c.get("total_cost_usd", "\u2014")),
    str(c.get("total_duration_ms", "\u2014")),
    d.get("cwd", ""),
]
print("\t".join(fields))
PYEOF

parsed=$(echo "$raw" | python3 "$tmp_py")
rm -f "$tmp_py"

if [[ "$parsed" == "ERROR" ]]; then
  echo "ccstatus: parse error"
  exit 0
fi

# Split tab-separated fields
IFS=$'\t' read -r model ctx_pct cost_usd duration_ms cwd <<< "$parsed"

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

# --- Stage 3: Git info ---
branch=""
worktree=""
if [[ -n "$cwd" ]] && command -v git &>/dev/null; then
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
  wt_path=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
  if [[ -n "$wt_path" ]]; then
    worktree="${wt_path:t}"
  fi
fi

# --- Stage 4: ANSI output ---
# Colors (256-color level 2)
C_CYAN='\033[36m'
C_DIM='\033[90m'
C_MAGENTA='\033[35m'
C_YELLOW='\033[33m'
C_RESET='\033[0m'
SEP=" │ "

# Line 1: model | context% | $cost | clock
line1="${C_CYAN}${model}${C_RESET}${SEP}${C_DIM}${ctx_fmt}${C_RESET}${SEP}${C_MAGENTA}${cost_fmt}${C_RESET}${SEP}${C_YELLOW}${clock_fmt}${C_RESET}"

# Line 2: branch | worktree (skip if no git info)
if [[ -n "$branch" || -n "$worktree" ]]; then
  line2="${branch:-—}${SEP}${worktree:-—}"
else
  line2=""
fi

# Output
echo -e "$line1"
if [[ -n "$line2" ]]; then
  echo -e "$line2"
fi
echo ""
