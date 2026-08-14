# Technical Notes on the PIXIU 75 RGB Protocol

## Observed device

| Property | Value |
| --- | --- |
| USB vendor ID | `046A` |
| USB product ID | `01E2` |
| RGB OUT endpoint in the Windows capture | `0x05` |
| Response endpoint | `0x82` |
| Transport size | 64 bytes |
| HID Report ID used on macOS | `4` |

All values come from a single wired CHERRY PIXIU 75. Other firmware or hardware
variants must be checked separately before sending data.

## How the capture was created

CHERRY Utility ran in a Windows 11 VM under UTM. USBPcap recorded the USB traffic
while only the color of key `1` was changed in sequence:

```text
green → off → red → green → off
```

This deliberately simple sequence exposed the three variable RGB bytes. Raw PCAP
files do not belong in this repository because they may contain device or usage data.

## One selected key

The observed transaction consisted of:

1. begin with command byte `01`;
2. set the selected key's color with command byte `06`; and
3. commit with command byte `02`.

In the 64-byte report for number key `1`, red, green, and blue were located at
offsets 13, 14, and 15. Observed values:

| State | RGB bytes |
| --- | --- |
| Disabled / no color | `FF FF FF` |
| Red | `FF 00 00` |
| Green | `00 54 1C` |
| Orange used by the prototype | `FF 60 00` |

Here, `FF FF FF` is the “off” sentinel observed from CHERRY Utility, not white light.

## Complete color table

Persistent color assignments use command `0B`. A 378-byte table is divided into
seven payload blocks and then committed.

- Key `1`: table slot 11, offsets 33–35
- Keys `1` through `9`: slots 11–19
- The keymap read from the device associates these slots with HID usages `1E`
  through `26`, making their mapping to the number row unambiguous.

The prototype therefore generates this sequence for each update:

```text
01 (begin) → 7 × 0B (table chunks) → 02 (commit)
```

## Selecting the correct macOS HID interface

The keyboard exposes several HID interfaces, so vendor and product IDs alone are
not sufficient. A successful match requires both:

- a maximum output report size of 64 bytes; and
- Output Report ID `4` declared in the HID Report Descriptor.

Another vendor usage page on the keyboard uses Report ID `5`; it is not part of
the RGB transport observed here.

## Tool safety rule

Diagnostic commands are dry runs by default. Data is sent only when `--apply` is
provided. Before every write, the program validates the VID, PID, report size,
and Report ID. This reduces the risk of sending reports to the wrong HID interface.
