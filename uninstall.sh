#!/bin/bash

set -euo pipefail

CLAUDE_HOOK_PATH="$HOME/.claude/hooks/agent-notify.sh"
CLAUDE_SETTINGS_PATH="$HOME/.claude/settings.json"
INSTALL_ROOT="$HOME/.agent-notify"
LAUNCH_AGENT_ID="dev.agent-notify.codex-watcher"
LAUNCH_AGENT_PATH="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_ID.plist"

remove_hook_file() {
  rm -f "$CLAUDE_HOOK_PATH"

  if [ -d "$HOME/.claude/hooks" ] && [ -z "$(ls -A "$HOME/.claude/hooks")" ]; then
    rmdir "$HOME/.claude/hooks"
  fi
}

remove_hook_config() {
  if [ ! -f "$CLAUDE_SETTINGS_PATH" ]; then
    return
  fi

  python3 <<'PY'
import json
from pathlib import Path

settings_path = Path.home() / ".claude" / "settings.json"
hook_path = str(Path.home() / ".claude" / "hooks" / "agent-notify.sh")

try:
    config = json.loads(settings_path.read_text())
except Exception:
    raise SystemExit(0)

hooks = config.get("hooks")
if not isinstance(hooks, dict):
    raise SystemExit(0)

stop_entries = hooks.get("Stop")
if not isinstance(stop_entries, list):
    raise SystemExit(0)

cleaned = []
for entry in stop_entries:
    nested = entry.get("hooks", [])
    if not isinstance(nested, list):
        cleaned.append(entry)
        continue

    kept = [
        hook
        for hook in nested
        if not (hook.get("type") == "command" and hook.get("command") == hook_path)
    ]

    if kept:
        next_entry = dict(entry)
        next_entry["hooks"] = kept
        cleaned.append(next_entry)

if cleaned:
    hooks["Stop"] = cleaned
else:
    hooks.pop("Stop", None)

if not hooks:
    config.pop("hooks", None)

settings_path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + "\n")
PY
}

stop_watcher() {
  launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_PATH" >/dev/null 2>&1 || true
}

remove_files() {
  rm -f "$LAUNCH_AGENT_PATH"
  rm -rf "$INSTALL_ROOT"
}

print_summary() {
  cat <<'EOF'

agent-notify removed.

Restart Claude Code and Codex CLI if they are still running.
EOF
}

remove_hook_file
remove_hook_config
stop_watcher
remove_files
print_summary
