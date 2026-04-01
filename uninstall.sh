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

  node <<'NODE'
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const settingsPath = path.join(os.homedir(), ".claude", "settings.json");
const hookPath = path.join(os.homedir(), ".claude", "hooks", "agent-notify.sh");

let config;
try {
  config = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
} catch {
  process.exit(0);
}

if (!config.hooks || !Array.isArray(config.hooks.Stop)) {
  process.exit(0);
}

const cleaned = config.hooks.Stop
  .map((entry) => {
    if (!Array.isArray(entry.hooks)) {
      return entry;
    }

    const hooks = entry.hooks.filter(
      (hook) => !(hook.type === "command" && hook.command === hookPath),
    );

    return hooks.length === 0 ? null : { ...entry, hooks };
  })
  .filter(Boolean);

if (cleaned.length > 0) {
  config.hooks.Stop = cleaned;
} else {
  delete config.hooks.Stop;
}

if (Object.keys(config.hooks).length === 0) {
  delete config.hooks;
}

fs.writeFileSync(settingsPath, `${JSON.stringify(config, null, 2)}\n`);
NODE
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
