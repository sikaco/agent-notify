#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { spawnSync } from "node:child_process";

const home = os.homedir();
const watchRoots = [path.join(home, ".codex-cli", "sessions")];
const statePath = path.join(home, ".agent-notify", "state", "watch-state.json");
const pollMs = Number(process.env.AGENT_NOTIFY_POLL_SECONDS ?? "1.5") * 1000;
const maxMessageLen = 140;
const sound = process.env.AGENT_NOTIFY_SOUND ?? "Glass";
const notifierCandidates = [
  "terminal-notifier",
  "/opt/homebrew/bin/terminal-notifier",
  "/usr/local/bin/terminal-notifier",
];

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const exists = (target) => {
  try {
    fs.accessSync(target, fs.constants.F_OK);
    return true;
  } catch {
    return false;
  }
};

const isExecutable = (target) => {
  try {
    fs.accessSync(target, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
};

const loadState = () => {
  if (!exists(statePath)) {
    return { files: {} };
  }

  try {
    return JSON.parse(fs.readFileSync(statePath, "utf8"));
  } catch {
    return { files: {} };
  }
};

const saveState = (state) => {
  fs.mkdirSync(path.dirname(statePath), { recursive: true });
  fs.writeFileSync(statePath, `${JSON.stringify(state, null, 2)}\n`);
};

const walkJsonlFiles = (root) => {
  if (!exists(root)) {
    return [];
  }

  const entries = fs.readdirSync(root, { withFileTypes: true });
  return entries.flatMap((entry) => {
    const fullPath = path.join(root, entry.name);
    if (entry.isDirectory()) {
      return walkJsonlFiles(fullPath);
    }
    return entry.isFile() && fullPath.endsWith(".jsonl") ? [fullPath] : [];
  });
};

const sessionFiles = () =>
  watchRoots.flatMap(walkJsonlFiles).sort((left, right) => left.localeCompare(right));

const trimMessage = (text) => {
  const firstLine = text
    .split("\n")
    .map((line) => line.trim())
    .find(Boolean);
  const message = firstLine || "Task completed";
  return message.length <= maxMessageLen
    ? message
    : `${message.slice(0, maxMessageLen - 1)}…`;
};

const projectName = (cwd) => {
  if (!cwd) {
    return "Codex";
  }

  const name = path.basename(cwd.trim());
  return name || "Codex";
};

const resolveBinary = (candidate) => {
  if (path.isAbsolute(candidate)) {
    return isExecutable(candidate) ? candidate : null;
  }

  const envPath = process.env.PATH ?? "";
  return envPath
    .split(path.delimiter)
    .filter(Boolean)
    .map((part) => path.join(part, candidate))
    .find(isExecutable) ?? null;
};

const firstNotifier = () =>
  notifierCandidates.map(resolveBinary).find(Boolean) ?? null;

const run = (command, args) =>
  spawnSync(command, args, {
    encoding: "utf8",
    stdio: "ignore",
  });

const runNotification = ({ title, subtitle, message, group }) => {
  const notifier = firstNotifier();
  if (notifier) {
    run(notifier, [
      "-title",
      title,
      "-subtitle",
      subtitle,
      "-message",
      message,
      "-sound",
      sound,
      "-group",
      group,
    ]);
    return;
  }

  const script =
    `display notification ${JSON.stringify(message)} ` +
    `with title ${JSON.stringify(title)} ` +
    `subtitle ${JSON.stringify(subtitle)}`;
  run("/usr/bin/osascript", ["-e", script]);
};

const sendNotification = (filePath, cwd, text) => {
  runNotification({
    title: projectName(cwd),
    subtitle: "Codex CLI finished",
    message: trimMessage(text),
    group: `agent-notify:${path.parse(filePath).name}`,
  });
};

const extractText = (payload) =>
  (payload.content ?? [])
    .filter((item) => item.type === "output_text")
    .map((item) => item.text ?? "")
    .join("")
    .trim();

const readJsonlLines = (filePath) => {
  try {
    return fs
      .readFileSync(filePath, "utf8")
      .split("\n")
      .filter(Boolean)
      .map((line) => {
        try {
          return JSON.parse(line);
        } catch {
          return null;
        }
      })
      .filter(Boolean);
  } catch {
    return [];
  }
};

const bootstrapFile = (filePath) => {
  const entry = {
    offset: fs.statSync(filePath).size,
    cwd: null,
  };

  for (const row of readJsonlLines(filePath)) {
    if (row.type !== "turn_context") {
      continue;
    }
    const cwd = row.payload?.cwd;
    if (cwd) {
      entry.cwd = cwd;
    }
  }

  return entry;
};

const processFile = (filePath, entry) => {
  let stat;
  try {
    stat = fs.statSync(filePath);
  } catch {
    return false;
  }

  if (stat.size < (entry.offset ?? 0)) {
    Object.assign(entry, bootstrapFile(filePath));
    return true;
  }

  let content;
  try {
    content = fs.readFileSync(filePath, "utf8");
  } catch {
    return false;
  }

  const nextChunk = content.slice(entry.offset ?? 0);
  if (!nextChunk) {
    return false;
  }

  const lines = nextChunk.split("\n").filter(Boolean);
  let changed = false;

  for (const rawLine of lines) {
    changed = true;
    let row;
    try {
      row = JSON.parse(rawLine);
    } catch {
      continue;
    }

    if (row.type === "turn_context") {
      const cwd = row.payload?.cwd;
      if (cwd) {
        entry.cwd = cwd;
      }
      continue;
    }

    if (row.type !== "response_item") {
      continue;
    }

    const payload = row.payload ?? {};
    const isFinal =
      payload.type === "message" &&
      payload.role === "assistant" &&
      payload.phase === "final_answer";

    if (!isFinal) {
      continue;
    }

    sendNotification(filePath, entry.cwd, extractText(payload));
  }

  entry.offset = Buffer.byteLength(content, "utf8");
  return changed;
};

const pruneMissing = (state, liveFiles) => {
  const entries = state.files ?? {};
  const stalePaths = Object.keys(entries).filter((filePath) => !liveFiles.has(filePath));
  if (stalePaths.length === 0) {
    return false;
  }

  stalePaths.forEach((filePath) => {
    delete entries[filePath];
  });
  return true;
};

const bootstrapNewFiles = (state, files) => {
  let changed = false;
  state.files ??= {};

  files.forEach((filePath) => {
    if (state.files[filePath]) {
      return;
    }
    state.files[filePath] = bootstrapFile(filePath);
    changed = true;
  });

  return changed;
};

const main = async () => {
  if (process.platform !== "darwin") {
    console.error("agent-notify watcher supports macOS only.");
    process.exit(1);
  }

  const state = loadState();

  while (true) {
    const files = sessionFiles();
    const liveFiles = new Set(files);
    let dirty = pruneMissing(state, liveFiles);
    dirty = bootstrapNewFiles(state, files) || dirty;

    files.forEach((filePath) => {
      const entry = state.files[filePath];
      dirty = processFile(filePath, entry) || dirty;
    });

    if (dirty) {
      saveState(state);
    }

    await sleep(pollMs);
  }
};

await main();
