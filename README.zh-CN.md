# agent-notify

为 macOS 上的 Claude Code 和 Codex CLI 提供完成通知。

- Claude Code 使用原生 `Stop` hook
- Codex CLI 使用后台 watcher 监听本地 session JSONL
- Codex App 不处理，因为它已经自带通知

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/sikaco/agent-notify/main/install.sh | bash
```

或者：

```bash
git clone https://github.com/sikaco/agent-notify.git
cd agent-notify
bash install.sh
```

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/sikaco/agent-notify/main/uninstall.sh | bash
```

## 需要先看这一条

如果机器上安装了 `terminal-notifier`，**还必须去 macOS 系统设置里打开它的通知权限**，否则命令行虽然执行成功，屏幕上也可能完全没有横幅提醒。

路径是：

1. 打开 `系统设置`
2. 进入 `通知`
3. 找到 `terminal-notifier`
4. 打开 `允许通知`

这一条很重要，尤其是你手动执行过：

```bash
terminal-notifier -title "test" -message "hello"
```

但仍然看不到通知时，优先检查这里。

## 功能说明

- Claude Code 回复完成时发送通知
- Codex CLI 写入 `assistant final_answer` 时发送通知
- 标题显示当前项目名，便于区分多个会话
- 优先使用 `terminal-notifier`
- 如果没有安装 `terminal-notifier`，会退回到 `osascript`

## 运行要求

- macOS
- `node`
- Claude Code 和/或 Codex CLI

可选：

- `terminal-notifier`
- Homebrew

如果安装器检测到你有 Homebrew，但没有 `terminal-notifier`，会尝试自动安装：

```bash
brew install terminal-notifier
```

## 安装后会写入这些文件

- `~/.claude/hooks/agent-notify.sh`
- `~/.agent-notify/bin/agent-notify-watch.mjs`
- `~/Library/LaunchAgents/dev.agent-notify.codex-watcher.plist`

## 常见排查

没有收到 Codex CLI 通知时，先检查：

```bash
launchctl print "gui/$(id -u)/dev.agent-notify.codex-watcher"
tail -f ~/.agent-notify/logs/agent-notify.err.log
```

手动测试 `terminal-notifier`：

```bash
command -v terminal-notifier
terminal-notifier -title "agent-notify" -subtitle "manual test" -message "如果你看到了这条，说明 terminal-notifier 本身能工作"
```

如果命令执行成功，但屏幕上没有通知，通常就是：

- `系统设置 -> 通知 -> terminal-notifier` 没开

手动测试 Claude hook：

```bash
~/.claude/hooks/agent-notify.sh
```

## 技术原理

- Claude Code：通过 `Stop` hook 触发通知
- Codex CLI：通过 LaunchAgent 常驻 watcher 监听 `~/.codex-cli/sessions`

## 许可

MIT
