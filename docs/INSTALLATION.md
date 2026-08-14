# Installation und Betrieb

## 1. Projekt bauen

```bash
swift build -c release
swift test
```

Nur die Kommandozeile testen:

```bash
.build/release/pixiu-led list
.build/release/pixiu-led probe
```

`probe` sendet keinen Bericht.

## 2. Hintergrund-App installieren

```bash
./scripts/install.sh
```

Das Skript:

1. baut die Release-Version;
2. erzeugt `~/Applications/Pixiu Agent LED.app`;
3. signiert sie standardmäßig ad hoc oder mit `SIGNING_IDENTITY`;
4. installiert einen LaunchAgent für den automatischen Login-Start;
5. startet die App über den LaunchAgent.

Für eine Development-Signatur:

```bash
SIGNING_IDENTITY='Apple Development: Name (TEAMID)' ./scripts/install.sh
```

## 3. Eingabeüberwachung erlauben

Unter **Systemeinstellungen → Datenschutz & Sicherheit → Eingabeüberwachung**
„Pixiu Agent LED“ einschalten. Danach die App beenden und erneut öffnen.

Ein typischer fehlender Zugriff erscheint als:

```text
IOHIDManagerOpen failed: 0xE00002E2
```

## 4. Status prüfen

```bash
"$HOME/Applications/Pixiu Agent LED.app/Contents/MacOS/pixiu-led" status
"$HOME/Applications/Pixiu Agent LED.app/Contents/MacOS/pixiu-led" hotkeys
"$HOME/Applications/Pixiu Agent LED.app/Contents/MacOS/pixiu-led" daemon-status
```

Erwartetes Hotkey-Ergebnis:

```text
Registered keys: 1,2,3,4,5,6,7,8,9
Conflicts: none
```

## 5. Optionale Codex-Hooks

Die Desktop-Überwachung funktioniert ohne Hooks. Für schnellere Start-/Stop-
Updates kann [examples/hooks.json](../examples/hooks.json) als Vorlage für
`~/.codex/hooks.json` dienen. Vorhandene Hooks nicht blind überschreiben, sondern
die Einträge zusammenführen.

## 6. Farben sicher testen

Zuerst Dry-Run:

```bash
swift run pixiu-led set 1 green 2 orange 3 red
```

Erst danach wirklich senden:

```bash
swift run pixiu-led set 1 green 2 orange 3 red --apply
```

## 7. Protokolle und Zustand

```text
~/Library/Application Support/PixiuAgentLED/state.json
~/Library/Application Support/PixiuAgentLED/hotkeys.json
~/Library/Application Support/PixiuAgentLED/daemon-status.json
~/Library/Application Support/PixiuAgentLED/daemon.log
~/Library/Application Support/PixiuAgentLED/daemon-error.log
```

## 8. Häufige Probleme

### App zeigt kein Fenster

Das ist beabsichtigt: `LSBackgroundOnly` ist aktiv. Status und Diagnose erfolgen
über die Tastatur oder die obigen Befehle.

### Codex-Aufgabe wird erkannt, aber LED ändert sich nicht

`daemon-status` ausführen. `phase=applied` bestätigt die zuletzt erfolgreich
gesendete Farbtabelle; `phase=error` zeigt den konkreten HID-Fehler. Danach
`probe` ausführen, Eingabeüberwachung prüfen und sicherstellen, dass die Tastatur
per Kabel verbunden ist.

### LED funktioniert, aber der Hotkey springt nicht

`hotkeys` ausführen und danach den gewünschten Kurzbefehl einmal drücken. Die
Zeile `Last trigger` unterscheidet drei Fälle: Kein Ereignis angekommen,
Ereignis ohne zugewiesene Aufgabe oder Aufgabe erfolgreich geöffnet. Bei einem
Konflikt den fremden System-/App-Kurzbefehl ändern oder die Modifier in
`HotKeyNavigator.swift` anpassen. Prüfen, ob die installierte Codex-Version das
Schema `codex://threads/<ID>` noch unterstützt.

### Nach einem Neubau ist die Berechtigung weg

Bundle-ID `com.yijian.pixiu-agent-led`, Installationspfad und
Signierungsidentität stabil halten. TCC bindet die Eingabeüberwachung an diese
Anwendungsidentität, nicht nur an den sichtbaren Namen. Eine abweichende
Bundle-ID oder ad-hoc-signierte Neubauten werden als andere Anwendung behandelt.
