# Privacy and Security

## Local data model

The service has no network functionality of its own. It reads local Codex rollout
files under `~/.codex/sessions`, extracts only the session ID, working directory,
turn ID, timestamp, and lifecycle event, and stores compact state under:

```text
~/Library/Application Support/PixiuAgentLED/
```

When opening a task, it only passes the local URL
`codex://threads/<session-ID>` to macOS.

## Do not publish

The following files may contain confidential content or device information and
are therefore excluded by `.gitignore`:

- USB PCAP or PCAPNG captures
- Codex rollout files (`*.jsonl`)
- `state.json`, `hotkeys.json`, and log files
- Personal hook configurations containing absolute user paths
- Signed local app bundles

## HID risk

The program sends vendor-specific USB HID reports. Validation of VID, PID, report
size, and Report ID restricts the target but does not provide a firmware guarantee.
Investigate new hardware variants first with `list`, `probe`, and dry-run commands.

## Reporting security issues

Do not include private PCAP or session data in a public issue. A minimal,
anonymized hexadecimal excerpt and the hardware and firmware versions are usually
sufficient.
