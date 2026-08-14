# Development Log: Experiments, Problems, and the Working Solution

This document intentionally records failed experiments as well. With proprietary
USB hardware, they were essential for ruling out incorrect assumptions.

## 1. Initial idea

The number row from `1` through `9` was intended to serve as a physical task dashboard:

- running or waiting: initially blinking red, later deliberately changed to orange;
- completed: green;
- error: red; and
- modifier keys plus a number: jump to the corresponding agent task.

Red was removed from the normal running indicator because an alarm color would
otherwise signal “error” continuously during every healthy run.

The first orange implementation blinked in software once per second. Each
transition sent nine HID reports with about 225 ms of total delay. In practical
testing, this dropped keystrokes during fast typing. The safe final version uses
solid orange and writes only on real task-state changes. Hardware blinking can
be added later if a separate, non-blocking firmware command is identified.

## 2. First uncertainty: Is per-key RGB control possible from macOS?

CHERRY Utility could configure the keyboard but offered no documented macOS
automation interface. Its successful per-key control only proved that the
firmware supported it, not how the Mac needed to send the packets.

## 3. Windows VM and USB capture

CHERRY Utility was started in a Windows 11 VM under UTM, with the wired keyboard
passed through over USB.

### Problems encountered

- **“Display output is not active”**: The VM or SPICE display was inactive; the
  normal VM output had to work again before USB analysis could continue.
- **QEMU `-global: requires an argument`**: A manually added QEMU parameter was
  syntactically incomplete. Extra arguments must be entered as complete key-value
  units.
- **The PCAP path could not be opened**: QEMU attempted to open a file in a path
  that did not exist or was not accessible. The path must exist and be writable
  by UTM.
- **Wireshark showed only Ethernet, loopback, and ETW**: This was not a keyboard
  problem. The USB capture interface was missing; USBPcap had to be installed in
  Windows and Wireshark restarted with the appropriate permissions.
- **CHERRY Utility temporarily stopped detecting the keyboard**: USB passthrough
  can have only one owner. Reconnecting the device to the VM and restarting the
  utility restored detection.

### The useful capture

Only key `1` was changed, in this fixed sequence:

```text
green → off → red → green → off
```

This made it possible to distinguish changing RGB bytes from the constant
protocol framing. The findings from this capture are documented in
[PROTOCOL.md](../PROTOCOL.md).

## 4. Direct macOS HID prototype

The first Swift prototype listed every device with `VID 046A` and `PID 01E2` and
sent nothing by default. This was important because the keyboard exposes several
HID interfaces.

### Incorrect assumption

Checking only VID and PID is insufficient: another vendor interface reports
Report ID `5`. The successful combination was a 64-byte output report and Output
Report ID `4` declared in the descriptor.

### macOS permission trap

A background app bundle launched by double-clicking intentionally shows no
window. Without **Input Monitoring**, `IOHIDManagerOpen` failed with
`0xE00002E2`. Hardware access worked after permission was granted manually and
the app restarted.

When an app is replaced or signed differently, macOS may treat its TCC mapping
as a new application. A stable bundle ID and, ideally, the same development
signature prevent repeated permission prompts.

## 5. From one LED to nine task slots

Individual reports were useful for verification but unsuitable for multiple
tasks. The complete 378-byte table (`0B`) proved to be the correct abstraction.
Slots 11–19 correspond to the number row, allowing each update to set all nine
task colors consistently.

## 6. First lifecycle implementation: hooks only

`UserPromptSubmit` marked a session as running, while `Stop` marked it as done.
This worked for new, hook-enabled runs and proved the end-to-end chain.

### Why that was not enough

- Old desktop tasks that were already open had not emitted a start hook.
- Resumed threads did not always behave like new sessions.
- Multiple concurrently running desktop tasks were not always fully visible.
- A stop hook does not automatically distinguish every error case.

## 7. Attempt to subscribe directly to the Codex App Server

The public App Server semantics include thread state, turn start, and turn
completion. The running desktop process, however, communicated locally through
private pipes. Attempts to connect through the visible IPC socket and
`app-server proxy` produced no usable response. Starting a second App Server
would not have mirrored the state of the existing desktop client.

This path was therefore not made a runtime dependency.

## 8. Successful desktop detection through rollout files

Codex Desktop writes append-only JSONL rollouts for each thread with clear
`task_started` and `task_complete` events. The monitor reads only new bytes,
reconstructs active sessions at startup, and merges hook and desktop events
through the same session ID.

### Additional subtle bugs

- `session_meta` may appear after `task_started`. During the initial full scan,
  metadata is therefore collected before the event sequence is evaluated.
- The final JSONL line may still be incomplete. It must not be parsed until the
  next newline arrives.
- Recently completed historical threads must not occupy every key at startup.
  Only active sessions are added.
- Scanning years of session history every two seconds would be unnecessarily
  expensive. Only three date directories are considered.

## 9. Global navigation without interfering with existing shortcuts

Using `1` through `9` alone was not an option because it would break normal
typing. `⌘1…9` is used for tabs in many applications. The first choice was
therefore `⌃⌥⌘1…9`, but practical testing showed it was unnecessarily awkward.
The final assignment, `⌃⌘1…9`, uses only two modifiers while remaining distinct
from `⌘1…9` and `⌃1…9`.

macOS registers these combinations as true global hotkeys. If a combination is
already assigned, registration fails instead of overriding its owner. All nine
combinations were conflict-free during testing. Successful registration alone,
however, proved insufficient: the first background build kept only a Foundation
run loop alive. Carbon accepted the hotkeys but did not deliver their events to
the handler. Switching to the full `NSApplication.run()` event loop fixed the
problem. `hotkeys.json` now also records the most recent trigger and URL-opening
result.

The installed Codex app registered the `codex` URL scheme and accepted
`codex://threads/<thread-id>`. This enables an exact jump without a mouse, window
coordinates, or simulated search.

A later rebuild exposed a second macOS-specific problem: the locally authorized
prototype used `com.yijian.pixiu-agent-led`, while the published `Info.plist` and
installer still contained `io.github.masteryijian.pixiu-agent-led`. Despite the
same visible name, TCC treated the rebuild as a different application and denied
HID access with `0xE00002E2`. The bundle ID, LaunchAgent label, path, and
development signature are now consistent and stable. `daemon-status.json` also
distinguishes visibly between a detected task, an active send attempt, a
successfully applied color table, and an HID error.

## 10. Working end state

The robust chain now consists of:

1. the desktop JSONL monitor as the primary source;
2. hooks as an optional, faster supplement;
3. persistent, locked task state with deduplication;
4. nine RGB slots controlled through the complete color table;
5. solid orange for running or waiting, green for success, and red only for errors;
6. `⌃⌘1…9` for jumping directly back to a task; and
7. a signed background app bundle plus a LaunchAgent for startup at login.

The largest remaining technical debt is the dependency on observed Codex file
and URL formats that are not officially stable. The adapter boundary is
therefore intentionally kept small.
