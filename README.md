# AI-Benachrichtigungen auf der Tastatur

Ein experimenteller macOS-Hintergrunddienst, der laufende Codex-Aufgaben auf den
RGB-Tasten `1` bis `9` einer **CHERRY PIXIU 75** sichtbar macht und per globalem
Kurzbefehl direkt zur zugehörigen Aufgabe springt.

Das Projekt löst ein Aufmerksamkeitsproblem: Statt laufende KI-Agenten ständig
auf dem Bildschirm zu beobachten, genügt ein kurzer Blick auf die Tastatur, um
ihren Fortschritt passiv wahrzunehmen.

> Stand des Prototyps: getestet am 13. August 2026 mit macOS, einer kabelgebundenen
> CHERRY PIXIU 75 (`VID 046A`, `PID 01E2`) und Codex Desktop 26.803.61601.

## Was funktioniert

| Zustand | Anzeige |
| --- | --- |
| Aufgabe läuft oder wartet | langsam orange blinkend |
| Aufgabe abgeschlossen | grün, dauerhaft |
| zuverlässig erkannter Fehler | rot, dauerhaft |
| kein zugewiesener Task | LED aus |

- Die Vergabe läuft zyklisch über `1` bis `9`; laufende Belegungen werden übersprungen.
- Mehrere parallele Desktop-Aufgaben werden getrennt dargestellt.
- Wieder aufgenommene und beim Programmstart bereits laufende Aufgaben werden erkannt.
- `⌃⌘1` bis `⌃⌘9` öffnen die zugehörige Codex-Aufgabe.
- Normale Zahleneingabe und übliche Kürzel wie `⌘1` bis `⌘9` bleiben unverändert.
- Alles läuft lokal; der Dienst besitzt keine eigene Netzwerkkommunikation.

## Architektur in einem Bild

```text
Codex Desktop / CLI                     optionale Codex-Hooks
~/.codex/sessions/**/*.jsonl            UserPromptSubmit / Stop
             │                                   │
             └──────────────┬────────────────────┘
                            ▼
                  Sitzungszustand + Tasten 1–9
                            │
                  ┌─────────┴─────────┐
                  ▼                   ▼
          USB-HID-RGB-Berichte   ⌃⌘ + Ziffer
          an die PIXIU 75        codex://threads/<ID>
```

Die Desktop-Überwachung ist die Hauptquelle. Hooks dienen nur als schneller,
optionaler Zusatz. Beide Quellen verwenden dieselbe Sitzungs-ID und erzeugen
daher keine doppelten Tastenbelegungen.

## Voraussetzungen

- macOS 13 oder neuer
- Xcode Command Line Tools mit Swift 6
- CHERRY PIXIU 75 über USB-Kabel
- Codex Desktop bzw. Codex CLI für die automatische Aufgabenerkennung
- Berechtigung **Eingabeüberwachung** für die gebaute App

CHERRY Utility, Windows, UTM, USBPcap und Wireshark waren für die
Protokollanalyse nötig, werden für den täglichen Betrieb aber nicht benötigt.

## Schnellstart

```bash
git clone https://github.com/masteryijian/AI-notification-on-keyboard.git
cd AI-notification-on-keyboard
./scripts/install.sh
open "$HOME/Applications/Pixiu Agent LED.app"
```

Danach unter **Systemeinstellungen → Datenschutz & Sicherheit →
Eingabeüberwachung** den Schalter für „Pixiu Agent LED“ aktivieren und die App
neu starten.

Für eine stabile macOS-Berechtigungszuordnung ist eine eigene Apple-Development-
Signatur besser als die standardmäßige Ad-hoc-Signatur:

```bash
SIGNING_IDENTITY='Apple Development: Name (TEAMID)' ./scripts/install.sh
```

Ausführliche Schritte: [Installation und Betrieb](docs/INSTALLATION.md).

## Nützliche Diagnosebefehle

```bash
swift run pixiu-led list
swift run pixiu-led probe
swift run pixiu-led status
swift run pixiu-led hotkeys
swift run pixiu-led desktop-sync
swift run pixiu-led set 1 green 2 orange 3 red
swift run pixiu-led set 1 green 2 orange 3 red --apply
```

Ohne `--apply` werden Testfarben nur validiert und **nicht** an die Tastatur
gesendet. `probe` öffnet und schließt lediglich die erkannte HID-Schnittstelle.

## Wichtige Grenzen

- Das RGB-Protokoll wurde nur auf der oben genannten PIXIU-75-Variante geprüft.
- Die Codex-JSONL-Struktur und `codex://threads/<ID>` sind beobachtete lokale
  Schnittstellen, keine hier garantierten stabilen öffentlichen APIs. Nach einem
  Codex-Update kann eine Anpassung nötig werden.
- Aktuell existiert ein Adapter für Codex. Andere Agenten können ergänzt werden,
  sobald sie verlässliche Start-, Abschluss- und Fehlerereignisse bereitstellen.
- Es werden höchstens neun Aufgaben gleichzeitig abgebildet. Ist alles belegt,
  wird keine laufende Aufgabe verdrängt; die älteste abgeschlossene Belegung wird
  erst beim nächsten Bedarf wiederverwendet.
- Ein rotes Licht wird bewusst nur bei einem eindeutigen Fehlerereignis gesetzt.
  Ein abgebrochener oder vom Nutzer beendeter Lauf gilt als beendet, nicht als Fehler.

## Dokumentation

- [Installation und Betrieb](docs/INSTALLATION.md)
- [Architektur und Datenfluss](docs/ARCHITEKTUR.md)
- [Entwicklungstagebuch: Versuche, Sackgassen und erfolgreiche Lösung](docs/ENTWICKLUNGSTAGEBUCH.md)
- [USB-/RGB-Protokoll](PROTOCOL.md)
- [Datenschutz und Sicherheitsmodell](SECURITY.md)

## Projektstatus

Dies ist ein hardwaregebundener Forschungsprototyp und kein offizielles Produkt
von OpenAI oder CHERRY. Für dieses Repository wurde noch keine Lizenz festgelegt;
bis dahin gelten die gesetzlichen Standardrechte des Urhebers.
