# Datenschutz und Sicherheit

## Lokales Datenmodell

Der Dienst hat keine eigene Netzwerkfunktion. Er liest lokale Codex-Rollout-
Dateien unter `~/.codex/sessions`, extrahiert nur Sitzungs-ID, Arbeitsverzeichnis,
Turn-ID, Zeitstempel und Lebenszyklusereignis und speichert den kompakten Zustand
unter:

```text
~/Library/Application Support/PixiuAgentLED/
```

Beim Öffnen einer Aufgabe übergibt er lediglich die lokale URL
`codex://threads/<Sitzungs-ID>` an macOS.

## Nicht veröffentlichen

Folgende Dateien können vertrauliche Inhalte oder Geräteinformationen enthalten
und sind deshalb in `.gitignore` ausgeschlossen:

- USB-PCAP-/PCAPNG-Mitschnitte
- Codex-Rollout-Dateien (`*.jsonl`)
- `state.json`, `hotkeys.json` und Protokolldateien
- persönliche Hook-Konfigurationen mit absoluten Benutzerpfaden
- signierte lokale App-Bundles

## HID-Risiko

Das Programm sendet herstellerspezifische USB-HID-Berichte. Die Validierung von
VID, PID, Reportgröße und Report ID begrenzt das Ziel, ersetzt aber keine
Firmwaregarantie. Neue Hardwarevarianten zuerst nur mit `list`, `probe` und
Dry-Run-Befehlen untersuchen.

## Fehler melden

Bitte Sicherheitsprobleme nicht zusammen mit privaten PCAP- oder Sitzungsdaten
in ein öffentliches Issue kopieren. Ein minimaler, anonymisierter Hex-Ausschnitt
und die Hardware-/Firmwareversion reichen meistens aus.

