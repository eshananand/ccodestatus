# ccodestatus

A self-contained, zero-dependency status line for [Claude Code](https://claude.ai/code). Replaces npm-based alternatives like `ccstatusline` with a single shell script.

## What it shows

```
Opus 4.6 (1M context) │ 12% │ $0.45 │ 3:03
front-end-changes │ my-project │ wt:hotfix-x
5h:34% @14:20 │ 7d:61% @Mon 09:00
```

**Line 1:** Model name (cyan) │ Context window usage (dim) │ Session cost (magenta) │ Session duration (yellow)

**Line 2:** Git branch │ Git repo name │ `wt:<name>` worktree label (only when inside a Claude Code worktree)

**Line 3:** Subscription rate limits — `5h:<pct>% @<reset-time>` and `7d:<pct>% @<reset-day-time>` (only for Claude.ai Pro/Max users; absent for API-key sessions). Percentages are color-coded: green below 50%, yellow 50–79%, red 80%+.

Line 3 is omitted entirely for API-key users or before the first API call of a session.

## Requirements

- **zsh** (default shell on macOS)
- **python3** (for JSON parsing — pre-installed on macOS)
- **git** (optional — for branch/repo display)

No Node.js. No npm. No jq. No package managers.

## Installation

### 1. Download the script

```bash
curl -o ~/.claude/ccstatus.sh https://raw.githubusercontent.com/eshananand/ccodestatus/main/ccstatus.sh
chmod +x ~/.claude/ccstatus.sh
```

Or clone and copy:

```bash
git clone https://github.com/eshananand/ccodestatus.git
cp ccodestatus/ccstatus.sh ~/.claude/ccstatus.sh
chmod +x ~/.claude/ccstatus.sh
```

### 2. Configure Claude Code

Edit `~/.claude/settings.json` and add or update the `statusLine` section:

First, find your absolute path:

```bash
echo "$HOME/.claude/ccstatus.sh"
```

Then edit `~/.claude/settings.json` and use that path:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/Users/yourname/.claude/ccstatus.sh",
    "padding": 0
  }
}
```

> **Replace `/Users/yourname/`** with your actual home directory. You must use the full absolute path — `~` will not work.

### 3. Restart Claude Code

Start a new Claude Code session. The status line should appear immediately.

## How it works

Claude Code pipes a JSON payload to the status line command via stdin on every update. The JSON contains session data like:

```json
{
  "model": { "display_name": "Opus 4.6 (1M context)" },
  "context_window": { "used_percentage": 12 },
  "cost": { "total_cost_usd": 0.45, "total_duration_ms": 183000 },
  "workspace": {
    "current_dir": "/Users/you/your-project",
    "git_worktree": "hotfix-x"
  },
  "worktree": { "name": "hotfix-x" },
  "rate_limits": {
    "five_hour":  { "used_percentage": 34.0, "resets_at": 1780000000 },
    "seven_day":  { "used_percentage": 61.2, "resets_at": 1780500000 }
  }
}
```

`ccstatus.sh` does four things:

1. **Parses JSON** — writes a tiny Python script to a temp file, runs it to extract fields, deletes it
2. **Formats values** — cost → `$0.45`, duration ms → `3:03`, rate percentages → rounded integers
3. **Reads git info** — runs `git branch` and `git rev-parse` against the working directory
4. **Formats output** — assembles ANSI-colored text across up to 3 lines and prints to stdout

## Error handling

| Condition | Behavior |
|-----------|----------|
| No stdin / empty stdin | Silent exit |
| Invalid JSON | Prints `ccstatus: parse error` |
| Not in a git repo | Skips the git info (line 2) |
| Missing JSON fields | Shows `—` as placeholder |
| No `rate_limits` in JSON (API-key user) | Line 3 skipped entirely |
| `context_window.used_percentage` is null | Shows `—` (occurs before first API call) |

## Customization

Edit `ccstatus.sh` directly. The ANSI color codes are at the top of Stage 4:

```bash
C_CYAN='\033[36m'      # Model name
C_DIM='\033[90m'       # Context percentage
C_MAGENTA='\033[35m'   # Session cost
C_YELLOW='\033[33m'    # Session clock / rate limit warning (50–79%)
C_GREEN='\033[32m'     # Rate limit OK (< 50%)
C_RED='\033[31m'       # Rate limit high (>= 80%)
```

Rate limit color thresholds are in `pct_color()` in Stage 2. To apply the same color grading to the context percentage, replace `${C_DIM}${ctx_fmt}` in the line 1 assembly with `$(pct_color ${ctx_pct:-0})${ctx_fmt}`.

## License

MIT
