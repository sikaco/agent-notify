# agent-notify

macOS-only notifications for Claude Code and Codex CLI.

- Claude Code uses a native `Stop` hook.
- Codex CLI uses a background watcher for local session JSONL files.
- Codex App is not handled because it already has built-in notifications.

## Install

One-line install:

```bash
curl -fsSL https://raw.githubusercontent.com/sikaco/agent-notify/main/install.sh | bash
```

Or clone the repo and run locally:

```bash
git clone https://github.com/sikaco/agent-notify.git
cd agent-notify
bash install.sh
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/sikaco/agent-notify/main/uninstall.sh | bash
```

Or:

```bash
bash uninstall.sh
```

## What It Does

- Sends a macOS notification when Claude Code finishes a response.
- Sends a macOS notification when Codex CLI writes an `assistant final_answer`.
- Shows the project name so multiple sessions are easier to distinguish.
- Uses `terminal-notifier` when available.
- Falls back to built-in `osascript` notifications, so Homebrew is optional.

## Requirements

- macOS
- `python3`
- Claude Code and/or Codex CLI

Optional:

- `terminal-notifier` for grouped notifications and custom sounds

## Notes

- Restart Claude Code and Codex CLI after installation.
- The Codex watcher listens to `~/.codex-cli/sessions`.
- Notification permissions may need to be enabled in System Settings.
- If `terminal-notifier` is not installed, agent-notify falls back to built-in `osascript`.

## Files Installed

- `~/.claude/hooks/agent-notify.sh`
- `~/.agent-notify/bin/agent-notify-watch.py`
- `~/Library/LaunchAgents/dev.agent-notify.codex-watcher.plist`

## Troubleshooting

No notification:

```bash
tail -f ~/.agent-notify/logs/agent-notify.err.log
launchctl print "gui/$(id -u)/dev.agent-notify.codex-watcher"
```

Claude hook test:

```bash
~/.claude/hooks/agent-notify.sh
```

## License

MIT
