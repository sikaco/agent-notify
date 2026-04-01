#!/usr/bin/env python3
"""
Watch Codex CLI session logs and send macOS notifications on final answers.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
WATCH_ROOTS = [HOME / ".codex-cli" / "sessions"]
STATE_PATH = HOME / ".agent-notify" / "state" / "watch-state.json"
POLL_SECONDS = float(os.environ.get("AGENT_NOTIFY_POLL_SECONDS", "1.5"))
MAX_MESSAGE_LEN = 140
SOUND = os.environ.get("AGENT_NOTIFY_SOUND", "Glass")
NOTIFIER_CANDIDATES = (
    "terminal-notifier",
    "/opt/homebrew/bin/terminal-notifier",
    "/usr/local/bin/terminal-notifier",
)


def load_state() -> dict:
    if not STATE_PATH.exists():
        return {"files": {}}

    try:
        return json.loads(STATE_PATH.read_text())
    except Exception:
        return {"files": {}}


def save_state(state: dict) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, indent=2, sort_keys=True))


def session_files() -> list[Path]:
    files: list[Path] = []
    for root in WATCH_ROOTS:
        if root.exists():
            files.extend(root.rglob("*.jsonl"))
    return sorted(files)


def trim_message(text: str) -> str:
    first_line = next((line.strip() for line in text.splitlines() if line.strip()), "")
    message = first_line or "Task completed"
    if len(message) <= MAX_MESSAGE_LEN:
        return message
    return message[: MAX_MESSAGE_LEN - 1] + "…"


def project_name(cwd: str | None) -> str:
    if not cwd:
        return "Codex"
    name = Path(cwd).name.strip()
    return name or "Codex"


def run_notification(title: str, subtitle: str, message: str, group: str) -> None:
    notifier = first_notifier()
    if notifier:
        subprocess.run(
            [
                notifier,
                "-title",
                title,
                "-subtitle",
                subtitle,
                "-message",
                message,
                "-sound",
                SOUND,
                "-group",
                group,
            ],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return

    script = (
        f"display notification {json.dumps(message)} "
        f"with title {json.dumps(title)} "
        f"subtitle {json.dumps(subtitle)}"
    )
    subprocess.run(
        ["osascript", "-e", script],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def first_notifier() -> str | None:
    for candidate in NOTIFIER_CANDIDATES:
        binary = shutil_which(candidate)
        if binary:
            return binary
    return None


def send_notification(path: Path, cwd: str | None, text: str) -> None:
    run_notification(
        title=project_name(cwd),
        subtitle="Codex CLI finished",
        message=trim_message(text),
        group=f"agent-notify:{path.stem}",
    )


def extract_text(payload: dict) -> str:
    content = payload.get("content", [])
    parts = [
        item.get("text", "")
        for item in content
        if item.get("type") == "output_text"
    ]
    return "".join(parts).strip()


def bootstrap_file(path: Path) -> dict:
    entry = {"offset": path.stat().st_size, "cwd": None}

    try:
        with path.open() as handle:
            for line in handle:
                row = json.loads(line)
                if row.get("type") != "turn_context":
                    continue
                cwd = row.get("payload", {}).get("cwd")
                if cwd:
                    entry["cwd"] = cwd
    except Exception:
        pass

    return entry


def process_file(path: Path, entry: dict) -> bool:
    changed = False

    try:
        size = path.stat().st_size
    except FileNotFoundError:
        return False

    if size < entry.get("offset", 0):
        entry.update(bootstrap_file(path))
        return True

    with path.open() as handle:
        handle.seek(entry.get("offset", 0))

        for raw_line in handle:
            changed = True

            try:
                row = json.loads(raw_line)
            except json.JSONDecodeError:
                continue

            if row.get("type") == "turn_context":
                cwd = row.get("payload", {}).get("cwd")
                if cwd:
                    entry["cwd"] = cwd
                continue

            if row.get("type") != "response_item":
                continue

            payload = row.get("payload", {})
            is_final = (
                payload.get("type") == "message"
                and payload.get("role") == "assistant"
                and payload.get("phase") == "final_answer"
            )
            if not is_final:
                continue

            send_notification(path, entry.get("cwd"), extract_text(payload))

        entry["offset"] = handle.tell()

    return changed


def prune_missing(state: dict, live_files: set[str]) -> bool:
    entries = state.setdefault("files", {})
    stale = [path for path in entries if path not in live_files]
    if not stale:
        return False

    for path in stale:
        entries.pop(path, None)
    return True


def bootstrap_new_files(state: dict, files: list[Path]) -> bool:
    changed = False
    entries = state.setdefault("files", {})

    for path in files:
        key = str(path)
        if key in entries:
            continue
        entries[key] = bootstrap_file(path)
        changed = True

    return changed


def shutil_which(name: str) -> str | None:
    direct = Path(name)
    if direct.is_absolute() and direct.exists() and os.access(direct, os.X_OK):
        return str(direct)

    for part in os.environ.get("PATH", "").split(os.pathsep):
        if not part:
            continue
        candidate = Path(part) / name
        if candidate.exists() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def main() -> int:
    if sys.platform != "darwin":
        print("agent-notify watcher supports macOS only.", file=sys.stderr)
        return 1

    state = load_state()

    while True:
        files = session_files()
        live = {str(path) for path in files}
        dirty = prune_missing(state, live)
        dirty = bootstrap_new_files(state, files) or dirty

        for path in files:
            entry = state["files"][str(path)]
            dirty = process_file(path, entry) or dirty

        if dirty:
            save_state(state)

        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    raise SystemExit(main())
