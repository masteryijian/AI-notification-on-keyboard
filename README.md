# AI Notifications on Your Keyboard

An experimental macOS background service that visualizes running Codex tasks on
the RGB-enabled number keys `1` through `9`, followed by `0`, on a
**CHERRY PIXIU 75** and opens
the associated task directly through a global keyboard shortcut.

The project addresses an attention problem: instead of constantly watching
running AI agents on screen, you can glance at the keyboard and passively track
their progress.

> Prototype status: tested on August 13, 2026, with macOS, a wired CHERRY PIXIU
> 75 (`VID 046A`, `PID 01E2`), and Codex Desktop 26.803.61601.

## What works

| State | Indicator |
| --- | --- |
| Task running or waiting | Solid orange |
| Task completed | Solid green |
| Reliably detected error | Solid red |
| No assigned task | LED off |

- Assignment cycles through `1` to `9`, then `0`, and skips slots with running tasks.
- Multiple concurrent desktop tasks are shown separately.
- Resumed tasks and tasks already running when the program starts are detected.
- `⌃⌘1` through `⌃⌘9`, plus `⌃⌘0`, open the associated Codex task.
- Normal number entry and common shortcuts such as `⌘1` through `⌘9` remain unchanged.
- Everything runs locally; the service has no network functionality of its own.

## Architecture at a glance

```text
Codex Desktop / CLI                       optional Codex hooks
~/.codex/sessions/**/*.jsonl              UserPromptSubmit / Stop
             │                                     │
             └────────────────┬────────────────────┘
                              ▼
                  session state + keys 1–9,0
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
             USB HID RGB reports   ⌃⌘ + number
             to the PIXIU 75       codex://threads/<ID>
```

Desktop monitoring is the primary event source. Hooks are only a faster,
optional supplement. Both sources use the same session ID, so they do not
create duplicate key assignments.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools with Swift 6
- CHERRY PIXIU 75 connected by USB cable
- Codex Desktop or Codex CLI for automatic task detection
- **Input Monitoring** permission for the built app

CHERRY Utility, Windows, UTM, USBPcap, and Wireshark were required for protocol
analysis but are not needed for everyday operation.

## Quick start

```bash
git clone https://github.com/masteryijian/AI-notification-on-keyboard.git
cd AI-notification-on-keyboard
./scripts/install.sh
open "$HOME/Applications/Pixiu Agent LED.app"
```

Then open **System Settings → Privacy & Security → Input Monitoring**, enable
“Pixiu Agent LED,” and restart the app.

For stable macOS permission mapping, an Apple Development signature is preferable
to the default ad hoc signature:

```bash
SIGNING_IDENTITY='Apple Development: Name (TEAMID)' ./scripts/install.sh
```

For detailed steps, see [Installation and operation](docs/INSTALLATION.md).

## Useful diagnostic commands

```bash
swift run pixiu-led list
swift run pixiu-led probe
swift run pixiu-led status
swift run pixiu-led hotkeys
swift run pixiu-led desktop-sync
swift run pixiu-led set 1 green 2 orange 3 red
swift run pixiu-led set 1 green 2 orange 3 red --apply
```

Without `--apply`, test colors are validated but **not** sent to the keyboard.
`probe` only opens and closes the detected HID interface.

## Important limitations

- The RGB protocol has only been tested on the PIXIU 75 variant listed above.
- The Codex JSONL structure and `codex://threads/<ID>` are observed local
  interfaces, not stable public APIs guaranteed by this project. A Codex update
  may require changes.
- A Codex adapter currently exists. Other agents can be added when they provide
  reliable start, completion, and error events.
- No more than ten tasks can be represented at once. If every slot is occupied,
  no running task is displaced; the oldest completed assignment is reused only
  when another slot is needed.
- A red light is intentionally used only for an unambiguous error event. A run
  aborted or stopped by the user is considered finished, not failed.
- The running indicator deliberately does not blink in software. Repeated full
  RGB-table updates measurably blocked the keyboard firmware and caused dropped
  keystrokes during fast typing.

## Documentation

- [Installation and operation](docs/INSTALLATION.md)
- [Architecture and data flow](docs/ARCHITECTURE.md)
- [Development log: experiments, dead ends, and the working solution](docs/DEVELOPMENT_LOG.md)
- [USB/RGB protocol](PROTOCOL.md)
- [Privacy and security model](SECURITY.md)

## Project status

This is a hardware-specific research prototype, not an official OpenAI or CHERRY
product. No license has been assigned to this repository; standard copyright
restrictions apply until one is added.
