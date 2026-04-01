# agent-notify

[简体中文](README.zh-CN.md)

Get a macOS notification when Claude Code or Codex CLI finishes, so you do not need to keep watching the terminal.

- Claude Code: native `Stop` hook
- Codex CLI: background watcher for `~/.codex-cli/sessions`
- Codex App: unchanged, it already has built-in notifications

## Quick Install

Requirements:

- macOS
- `node`
- Claude Code and/or Codex CLI

Install:

```bash
curl -fsSL https://raw.githubusercontent.com/sikaco/agent-notify/main/install.sh | bash
```

After install:

1. Restart Claude Code
2. Restart Codex CLI
3. If macOS asks for notification permission, allow it

## Important: Enable Notification Permission

If `terminal-notifier` is installed, you still need to enable its notification permission in macOS.

Path:

1. Open `System Settings`
2. Open `Notifications`
3. Find `terminal-notifier`
4. Turn on `Allow Notifications`

Without this, the command may succeed but no banner will appear.

## What It Installs

- `~/.claude/hooks/agent-notify.sh`
- `~/.agent-notify/bin/agent-notify-watch.mjs`
- `~/Library/LaunchAgents/dev.agent-notify.codex-watcher.plist`

## How It Works

- Claude Code uses a `Stop` hook
- Codex CLI uses a LaunchAgent watcher
- `terminal-notifier` is used when available
- If `terminal-notifier` is missing, agent-notify falls back to `osascript`
- If Homebrew is available, the installer tries to install `terminal-notifier` automatically

## Quick Check

Check the Codex watcher:

```bash
launchctl print "gui/$(id -u)/dev.agent-notify.codex-watcher"
tail -f ~/.agent-notify/logs/agent-notify.err.log
```

Test `terminal-notifier`:

```bash
command -v terminal-notifier
terminal-notifier -title "agent-notify" -subtitle "manual test" -message "If you see this, terminal-notifier works"
```

If the command succeeds but nothing appears, go back to:

`System Settings -> Notifications -> terminal-notifier`

and enable notifications there.

Test the Claude hook:

```bash
~/.claude/hooks/agent-notify.sh
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/sikaco/agent-notify/main/uninstall.sh | bash
```

## License

MIT
