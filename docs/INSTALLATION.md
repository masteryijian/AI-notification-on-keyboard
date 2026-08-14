# Installation and Operation

## 1. Build the project

```bash
swift build -c release
swift test
```

To test only the command-line tool:

```bash
.build/release/pixiu-led list
.build/release/pixiu-led probe
```

`probe` does not send a report.

## 2. Install the background app

```bash
./scripts/install.sh
```

The script:

1. builds the release version;
2. creates `~/Applications/Pixiu Agent LED.app`;
3. signs it ad hoc by default or with `SIGNING_IDENTITY`;
4. installs a LaunchAgent that starts automatically at login; and
5. starts the app through the LaunchAgent.

To use a development signature:

```bash
SIGNING_IDENTITY='Apple Development: Name (TEAMID)' ./scripts/install.sh
```

## 3. Allow Input Monitoring

Open **System Settings → Privacy & Security → Input Monitoring** and enable
“Pixiu Agent LED.” Then quit and reopen the app.

A typical missing-permission error looks like this:

```text
IOHIDManagerOpen failed: 0xE00002E2
```

## 4. Check the status

```bash
"$HOME/Applications/Pixiu Agent LED.app/Contents/MacOS/pixiu-led" status
"$HOME/Applications/Pixiu Agent LED.app/Contents/MacOS/pixiu-led" hotkeys
"$HOME/Applications/Pixiu Agent LED.app/Contents/MacOS/pixiu-led" daemon-status
```

Expected hotkey result:

```text
Registered keys: 1,2,3,4,5,6,7,8,9
Conflicts: none
```

## 5. Optional Codex hooks

Desktop monitoring works without hooks. For faster start and stop updates, use
[examples/hooks.json](../examples/hooks.json) as a template for
`~/.codex/hooks.json`. Do not blindly overwrite existing hooks; merge the entries.

## 6. Test colors safely

Start with a dry run:

```bash
swift run pixiu-led set 1 green 2 orange 3 red
```

Only then send the colors to the keyboard:

```bash
swift run pixiu-led set 1 green 2 orange 3 red --apply
```

## 7. Logs and state

```text
~/Library/Application Support/PixiuAgentLED/state.json
~/Library/Application Support/PixiuAgentLED/hotkeys.json
~/Library/Application Support/PixiuAgentLED/daemon-status.json
~/Library/Application Support/PixiuAgentLED/daemon.log
~/Library/Application Support/PixiuAgentLED/daemon-error.log
```

## 8. Troubleshooting

### The app does not show a window

This is intentional: `LSBackgroundOnly` is enabled. Check status and diagnostics
through the keyboard or the commands above.

### A Codex task is detected, but the LED does not change

Run `daemon-status`. `phase=applied` confirms the last color table sent
successfully; `phase=error` shows the specific HID error. Then run `probe`, check
Input Monitoring, and make sure the keyboard is connected by cable.

### The LED works, but the hotkey does not open the task

Run `hotkeys`, then press the desired shortcut once. The `Last trigger` line
distinguishes three cases: no event received, an event without an assigned task,
or a task opened successfully. If there is a conflict, change the other system or
app shortcut, or adjust the modifiers in `HotKeyNavigator.swift`. Verify that the
installed Codex version still supports `codex://threads/<ID>`.

### Permission disappears after rebuilding

Keep the bundle ID `com.yijian.pixiu-agent-led`, installation path, and signing
identity stable. TCC associates Input Monitoring permission with this application
identity, not only its visible name. A different bundle ID or a newly ad hoc-signed
build is treated as a different application.
