#!/bin/bash

set -euo pipefail

REPO_OWNER="${AGENT_NOTIFY_REPO_OWNER:-sikaco}"
REPO_NAME="${AGENT_NOTIFY_REPO_NAME:-agent-notify}"
REPO_REF="${AGENT_NOTIFY_REF:-main}"
RAW_BASE="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$REPO_REF"

INSTALL_ROOT="$HOME/.agent-notify"
BIN_DIR="$INSTALL_ROOT/bin"
LOG_DIR="$INSTALL_ROOT/logs"
WATCHER_NAME="agent-notify-watch.mjs"
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

require_node() {
  if ! command -v node >/dev/null 2>&1; then
    echo "node is required."
    exit 1
  fi
}

ensure_terminal_notifier() {
  if command -v terminal-notifier >/dev/null 2>&1; then
    return
  fi

  if command -v brew >/dev/null 2>&1; then
    echo "terminal-notifier not found. Installing with Homebrew..."
    brew install terminal-notifier
    return
  fi

  cat <<'EOF'
terminal-notifier is not installed.
agent-notify will fall back to osascript notifications.

If you want the recommended notification path, install terminal-notifier first:
  brew install terminal-notifier

Then open macOS System Settings -> Notifications -> terminal-notifier
and allow notifications for terminal-notifier.
EOF
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
  cat > "$CLAUDE_HOOK_PATH" <<'EOF'
#!/bin/bash
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

/usr/bin/osascript -e "display notification \"$MESSAGE\" with title \"$TITLE\" subtitle \"$SUBTITLE\"" >/dev/null 2>&1 || true
EOF
  chmod +x "$CLAUDE_HOOK_PATH"
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
  node <<'NODE'
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const settingsPath = path.join(os.homedir(), ".claude", "settings.json");
const hookPath = path.join(os.homedir(), ".claude", "hooks", "agent-notify.sh");

let config = {};
if (fs.existsSync(settingsPath)) {
  try {
    config = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
  } catch {
    config = {};
  }
}

config.hooks ??= {};
if (!Array.isArray(config.hooks.Stop)) {
  config.hooks.Stop = [];
}

const exists = config.hooks.Stop.some((entry) =>
  Array.isArray(entry.hooks) &&
  entry.hooks.some((hook) => hook.type === "command" && hook.command === hookPath),
);

if (!exists) {
  config.hooks.Stop.push({
    hooks: [
      {
        type: "command",
        command: hookPath,
      },
    ],
  });
}

fs.writeFileSync(settingsPath, `${JSON.stringify(config, null, 2)}\n`);
NODE
}

install_watcher() {
  mkdir -p "$BIN_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"
  rm -f "$BIN_DIR/agent-notify-watch.py"
  rm -rf "$BIN_DIR/__pycache__"
  download_or_copy "$WATCHER_NAME" "$WATCHER_DEST"
  chmod +x "$WATCHER_DEST"
}

write_launch_agent() {
  cat > "$LAUNCH_AGENT_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>$LAUNCH_AGENT_ID</string>
    <key>ProgramArguments</key>
    <array>
      <string>$(command -v node)</string>
      <string>$WATCHER_DEST</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
      <key>PATH</key>
      <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>WorkingDirectory</key>
    <string>$HOME</string>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/agent-notify.out.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/agent-notify.err.log</string>
  </dict>
</plist>
EOF
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
require_node
ensure_terminal_notifier
write_claude_hook
backup_claude_settings
merge_claude_hook_config
install_watcher
write_launch_agent
restart_launch_agent
print_summary
