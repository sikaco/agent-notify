#!/bin/bash

set -euo pipefail

REPO_OWNER="${AGENT_NOTIFY_REPO_OWNER:-sikaco}"
REPO_NAME="${AGENT_NOTIFY_REPO_NAME:-agent-notify}"
REPO_REF="${AGENT_NOTIFY_REF:-main}"
RAW_BASE="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$REPO_REF"

INSTALL_ROOT="$HOME/.agent-notify"
BIN_DIR="$INSTALL_ROOT/bin"
LOG_DIR="$INSTALL_ROOT/logs"
WATCHER_NAME="agent-notify-watch.py"
WATCHER_DEST="$BIN_DIR/$WATCHER_NAME"

CLAUDE_DIR="$HOME/.claude"
CLAUDE_HOOKS_DIR="$CLAUDE_DIR/hooks"
CLAUDE_HOOK_PATH="$CLAUDE_HOOKS_DIR/agent-notify.sh"
CLAUDE_SETTINGS_PATH="$CLAUDE_DIR/settings.json"

LAUNCH_AGENT_ID="dev.agent-notify.codex-watcher"
LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_ID.plist"

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

require_macos() {
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "agent-notify currently supports macOS only."
    exit 1
  fi
}

require_python() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required."
    exit 1
  fi
}

download_or_copy() {
  local filename="$1"
  local destination="$2"
  local local_path="$SCRIPT_DIR/$filename"

  if [ -f "$local_path" ]; then
    cp "$local_path" "$destination"
    return
  fi

  curl -fsSL "$RAW_BASE/$filename" -o "$destination"
}

write_claude_hook() {
  mkdir -p "$CLAUDE_HOOKS_DIR"

  python3 - "$CLAUDE_HOOK_PATH" <<'PY'
from pathlib import Path
import stat
import sys

hook_path = Path(sys.argv[1])
script = """#!/bin/bash
set -euo pipefail

PROJECT_NAME=$(basename "${PWD:-$HOME}")
TITLE="${PROJECT_NAME:-Claude Code}"
SUBTITLE="Claude Code finished"
MESSAGE="Task completed"

if command -v terminal-notifier >/dev/null 2>&1; then
  terminal-notifier \
    -title "$TITLE" \
    -subtitle "$SUBTITLE" \
    -message "$MESSAGE" \
    -sound "${AGENT_NOTIFY_SOUND:-Glass}" \
    -group "agent-notify:claude:${PROJECT_NAME:-default}"
  exit 0
fi

python3 - "$TITLE" "$SUBTITLE" "$MESSAGE" <<'INNER'
import json
import subprocess
import sys

title, subtitle, message = sys.argv[1:4]
script = (
    f"display notification {json.dumps(message)} "
    f"with title {json.dumps(title)} "
    f"subtitle {json.dumps(subtitle)}"
)
subprocess.run(["osascript", "-e", script], check=False)
INNER
"""
hook_path.write_text(script)
hook_path.chmod(hook_path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
PY
}

backup_claude_settings() {
  if [ ! -f "$CLAUDE_SETTINGS_PATH" ]; then
    return
  fi

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  cp "$CLAUDE_SETTINGS_PATH" "$CLAUDE_SETTINGS_PATH.backup_$timestamp"
}

merge_claude_hook_config() {
  python3 <<'PY'
import json
from pathlib import Path

settings_path = Path.home() / ".claude" / "settings.json"
hook_path = str(Path.home() / ".claude" / "hooks" / "agent-notify.sh")

if settings_path.exists():
    try:
        config = json.loads(settings_path.read_text())
    except Exception:
        config = {}
else:
    config = {}

hooks = config.setdefault("hooks", {})
stop_entries = hooks.setdefault("Stop", [])
if not isinstance(stop_entries, list):
    stop_entries = []
    hooks["Stop"] = stop_entries

for entry in stop_entries:
    nested = entry.get("hooks", [])
    for hook in nested:
        if hook.get("type") == "command" and hook.get("command") == hook_path:
            settings_path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n")
            raise SystemExit(0)

stop_entries.append(
    {
        "hooks": [
            {
                "type": "command",
                "command": hook_path,
            }
        ]
    }
)

settings_path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n")
PY
}

install_watcher() {
  mkdir -p "$BIN_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"
  download_or_copy "$WATCHER_NAME" "$WATCHER_DEST"
  chmod +x "$WATCHER_DEST"
}

write_launch_agent() {
  python3 - "$LAUNCH_AGENT_PATH" "$LAUNCH_AGENT_ID" "$WATCHER_DEST" "$LOG_DIR" <<'PY'
from pathlib import Path
import sys

plist_path = Path(sys.argv[1])
label = sys.argv[2]
watcher_path = sys.argv[3]
log_dir = sys.argv[4]

content = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>{label}</string>
    <key>ProgramArguments</key>
    <array>
      <string>/usr/bin/python3</string>
      <string>{watcher_path}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>{Path.home()}</string>
    <key>StandardOutPath</key>
    <string>{log_dir}/agent-notify.out.log</string>
    <key>StandardErrorPath</key>
    <string>{log_dir}/agent-notify.err.log</string>
  </dict>
</plist>
"""
plist_path.write_text(content)
PY
}

restart_launch_agent() {
  launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_PATH" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PATH"
  launchctl kickstart -k "gui/$(id -u)/$LAUNCH_AGENT_ID" >/dev/null 2>&1 || true
}

print_summary() {
  cat <<'EOF'

agent-notify installed.

- Claude Code notifications: enabled with a Stop hook
- Codex CLI notifications: enabled with a LaunchAgent watcher
- Codex App: unchanged, it already has built-in notifications

Next:
1. Restart Claude Code.
2. Restart Codex CLI.
3. Enable notification permissions if macOS asks.

Optional:
- Install terminal-notifier for grouped notifications and custom sounds.
EOF
}

require_macos
require_python
write_claude_hook
backup_claude_settings
merge_claude_hook_config
install_watcher
write_launch_agent
restart_launch_agent
print_summary
