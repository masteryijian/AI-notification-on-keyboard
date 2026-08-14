# Architecture and Data Flow

## Goals

The Mac should remain available for foreground work while several agents run in
the background. The keyboard should answer three questions without switching
windows:

1. Which tasks are still running?
2. Which task finished or failed?
3. How do I reopen that exact task?

## Components

### `DesktopActivityMonitor`

The primary event source reads append-only rollout files from
`~/.codex/sessions/YYYY/MM/DD`. At startup, it checks only the three most recent
date directories and files modified within the last 36 hours.

Detected events:

| JSONL event | Internal state |
| --- | --- |
| `task_started` | `running` |
| `task_complete` | `done` |
| `turn_aborted`, `task_cancelled` | `done` |
| `stream_error`, `task_failed`, `turn_failed` | `error` |

On restart, only genuinely active sessions are added. A historically completed
task must not occupy a number key, but it may correctly mark an existing known
assignment as done.

New bytes are read incrementally through a file cursor. Incomplete JSONL lines
remain buffered until the next pass. New files are discovered every two seconds;
known files are checked approximately every 200 ms.

### Hook adapter

Optional Codex hooks process `UserPromptSubmit` and `Stop`. They improve response
time but are not the sole source of truth. The desktop monitor and hooks write to
the same state through the same `session_id`, making the operation idempotent.

### `TaskStore`

Persistent state is stored in a small, file-locked JSON document. Assignment:

1. continues cyclically after the last assigned number;
2. assigns `0` after `9`, then returns to `1`;
3. skips every assignment that is still running;
4. uses the first free, completed, or failed assignment; and
5. never displaces a currently running task.

### HID output

The daemon calculates a 378-byte color table from the current state and sends it
only when its signature changes. Running tasks remain solid orange, so USB writes
occur only on real status transitions and normal typing is not interrupted by
software-driven blinking.

### `HotKeyNavigator`

The app registers `Control+Command+1…9` and `Control+Command+0` as global macOS
hotkeys. The system
returns an error when a shortcut is already assigned; the program does not
override shortcuts owned by other applications. A successful input opens
`codex://threads/<session-id>`.

## Why use two detection paths?

Hooks alone were not reliable enough: already open, later resumed, and multiple
parallel desktop threads were not reported in every situation. JSONL alone has
minor detection latency and depends on an internal format. In practice, the
combination provides the most robust result and remains duplicate-free because
both paths use the session ID.

## Extending support to other agents

A new adapter only needs to provide normalized events:

```text
source task ID + working directory + running/done/error + timestamp
```

Key assignment, persistence, RGB output, and navigation can remain unchanged.
Navigation additionally requires a stable URL or another targeted opening
mechanism for the agent.
