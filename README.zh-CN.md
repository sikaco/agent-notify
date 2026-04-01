# agent-notify

[English](README.md)

让 Claude Code 或 Codex CLI 在任务完成时给你一个 macOS 通知，这样你不用一直盯着终端等。

- Claude Code：使用原生 `Stop` hook
- Codex CLI：后台 watcher 监听 `~/.codex-cli/sessions`
- Codex App：不处理，因为它已经自带通知

## 一键安装

运行要求：

- macOS
- `node`
- Claude Code 和/或 Codex CLI

安装：

```bash
curl -fsSL https://raw.githubusercontent.com/sikaco/agent-notify/main/install.sh | bash
```

安装后：

1. 重启 Claude Code
2. 重启 Codex CLI
3. 如果 macOS 弹出通知权限提示，点允许

## 重要：必须打开通知权限

如果机器上安装了 `terminal-notifier`，你还必须去 macOS 里打开它的通知权限，不然命令执行成功也可能没有横幅提醒。

路径：

1. 打开 `系统设置`
2. 打开 `通知`
3. 找到 `terminal-notifier`
4. 打开 `允许通知`

这是最容易让人误以为“脚本没生效”的地方。

## 它会安装什么

- `~/.claude/hooks/agent-notify.sh`
- `~/.agent-notify/bin/agent-notify-watch.mjs`
- `~/Library/LaunchAgents/dev.agent-notify.codex-watcher.plist`

## 工作方式

- Claude Code 走 `Stop` hook
- Codex CLI 走 LaunchAgent watcher
- 有 `terminal-notifier` 就优先使用它
- 没有 `terminal-notifier` 就退回到 `osascript`
- 如果你装了 Homebrew，安装器会尝试自动安装 `terminal-notifier`

## 快速排查

检查 Codex watcher：

```bash
launchctl print "gui/$(id -u)/dev.agent-notify.codex-watcher"
tail -f ~/.agent-notify/logs/agent-notify.err.log
```

手动测试 `terminal-notifier`：

```bash
command -v terminal-notifier
terminal-notifier -title "agent-notify" -subtitle "manual test" -message "如果你看到了这条，说明 terminal-notifier 本身能工作"
```

如果命令执行成功，但屏幕没有通知，优先回到这里检查：

`系统设置 -> 通知 -> terminal-notifier`

手动测试 Claude hook：

```bash
~/.claude/hooks/agent-notify.sh
```

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/sikaco/agent-notify/main/uninstall.sh | bash
```

## 许可

MIT
