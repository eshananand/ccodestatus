# ccodestatus

A self-contained, zero-dependency status line for [Claude Code](https://claude.ai/code). Replaces npm-based alternatives like `ccstatusline` with a single shell script.

## What it shows

```
Opus 4.6 (1M context) │ 12% │ $0.45 │ 3:03
front-end-changes │ my-project
```

**Line 1:** Model name (cyan) │ Context window usage (dim) │ Session cost (magenta) │ Session duration (yellow)

**Line 2:** Git branch │ Git repo name (skipped if not in a git repo)

## Requirements

- **zsh** (default shell on macOS)
- **python3** (for JSON parsing — pre-installed on macOS)
- **git** (optional — for branch/worktree display)

No Node.js. No npm. No package managers.

## Installation

### 1. Download the script

```bash
curl -o ~/.claude/ccstatus.sh https://raw.githubusercontent.com/eshananand-10/ccodestatus/main/ccstatus.sh
chmod +x ~/.claude/ccstatus.sh
```

Or clone and copy:

```bash
git clone https://github.com/eshananand-10/ccodestatus.git
cp ccodestatus/ccstatus.sh ~/.claude/ccstatus.sh
chmod +x ~/.claude/ccstatus.sh
```

### 2. Configure Claude Code

Edit `~/.claude/settings.json` and add or update the `statusLine` section:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/absolute/path/to/.claude/ccstatus.sh",
    "padding": 0
  }
}
```

**Important:** Use the full absolute path (e.g., `/Users/yourname/.claude/ccstatus.sh`), not `~`.

### 3. Restart Claude Code

Start a new Claude Code session. The status line should appear immediately.

## How it works

Claude Code pipes a JSON payload to the status line command via stdin on every update. The JSON contains session data like:

```json
{
  "model": { "display_name": "Opus 4.6 (1M context)" },
  "context_window": { "used_percentage": 12 },
  "cost": { "total_cost_usd": 0.45, "total_duration_ms": 183000 },
  "cwd": "/Users/you/your-project"
}
```

`ccstatus.sh` does three things:

1. **Parses JSON** — writes a tiny Python script to a temp file, runs it to extract fields, deletes it
2. **Reads git info** — runs `git branch` and `git rev-parse` against the working directory
3. **Formats output** — assembles ANSI-colored text and prints to stdout

## Error handling

| Condition | Behavior |
|-----------|----------|
| No stdin / empty stdin | Silent exit |
| Invalid JSON | Prints `ccstatus: parse error` |
| Not in a git repo | Skips the git info line |
| Missing JSON fields | Shows `—` as placeholder |

## Customization

Edit `ccstatus.sh` directly. The ANSI color codes are at the top of Stage 4:

```bash
C_CYAN='\033[36m'      # Model name
C_DIM='\033[90m'        # Context percentage
C_MAGENTA='\033[35m'    # Session cost
C_YELLOW='\033[33m'     # Session clock
```

## License

MIT
