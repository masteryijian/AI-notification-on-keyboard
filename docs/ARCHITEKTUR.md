# Architektur und Datenfluss

## Ziele

Der Mac darf für andere Arbeiten im Vordergrund bleiben, während mehrere Agenten
im Hintergrund laufen. Die Tastatur soll drei Fragen ohne Fensterwechsel
beantworten:

1. Welche Aufgaben laufen noch?
2. Welche Aufgabe ist fertig oder fehlgeschlagen?
3. Wie öffne ich genau diese Aufgabe wieder?

## Komponenten

### `DesktopActivityMonitor`

Die Hauptquelle liest append-only Rollout-Dateien aus
`~/.codex/sessions/YYYY/MM/DD`. Beim Start werden nur die letzten drei
Datumsverzeichnisse und Dateien mit Änderungen innerhalb von 36 Stunden geprüft.

Erkannte Ereignisse:

| JSONL-Ereignis | interner Zustand |
| --- | --- |
| `task_started` | `running` |
| `task_complete` | `done` |
| `turn_aborted`, `task_cancelled` | `done` |
| `stream_error`, `task_failed`, `turn_failed` | `error` |

Beim Neustart werden nur tatsächlich aktive Sitzungen neu angelegt. Ein historisch
abgeschlossener Task darf keine Ziffer belegen; er darf aber eine bereits bekannte
Belegung korrekt auf „fertig“ setzen.

Neue Bytes werden über einen Dateicursor inkrementell gelesen. Unvollständige
JSONL-Zeilen bleiben bis zum nächsten Durchlauf gepuffert. Neue Dateien werden
alle zwei Sekunden gesucht, bekannte Dateien etwa alle 200 ms geprüft.

### Hook-Adapter

Optional verarbeiten Codex-Hooks `UserPromptSubmit` und `Stop`. Sie verbessern
die Reaktionszeit, sind aber nicht die einzige Wahrheit. Desktop-Monitor und Hook
schreiben über dieselbe `session_id` in denselben Zustand; dadurch ist die
Operation idempotent.

### `TaskStore`

Der persistente Zustand ist eine kleine JSON-Datei mit Dateisperre. Die Vergabe:

1. nach der zuletzt vergebenen Ziffer zyklisch weiterzählen;
2. nach `9` wieder bei `1` beginnen;
3. jede noch laufende Belegung überspringen;
4. die erste freie, abgeschlossene oder fehlerhafte Belegung verwenden;
5. niemals eine aktuell laufende Aufgabe verdrängen.

### HID-Ausgabe

Der Daemon berechnet aus dem Zustand eine 378-Byte-Farbtabelle und sendet nur,
wenn sich deren Signatur oder die Blinkphase geändert hat. Die laufende Aufgabe
wechselt im Sekundentakt zwischen Orange und „aus“.

### `HotKeyNavigator`

Die App registriert `Control+Command+1…9` als globale macOS-Hotkeys. Das
System gibt bei einer bestehenden Belegung einen Fehler zurück; das Programm
überschreibt fremde Kurzbefehle nicht. Eine erfolgreiche Eingabe öffnet
`codex://threads/<session-id>`.

## Warum zwei Erkennungswege?

Nur Hooks zu verwenden war nicht zuverlässig genug: bereits offene, später
wiederaufgenommene und mehrere parallele Desktop-Threads wurden nicht in jeder
Situation gemeldet. Nur JSONL zu verwenden hat dagegen eine kleine
Erkennungslatenz und hängt von einem internen Format ab. Die Kombination liefert
im praktischen Betrieb die robusteste Lösung und bleibt durch die Sitzungs-ID
duplikatfrei.

## Erweiterung für andere Agenten

Ein neuer Adapter muss lediglich normalisierte Ereignisse liefern:

```text
source task id + working directory + running/done/error + timestamp
```

Die Tastenvergabe, Persistenz, RGB-Ausgabe und Navigation können unverändert
bleiben. Für Navigation braucht der Agent zusätzlich eine stabile URL oder einen
anderen gezielten Öffnungsmechanismus.
