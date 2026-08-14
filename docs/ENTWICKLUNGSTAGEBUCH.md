# Entwicklungstagebuch: Versuche, Probleme und erfolgreiche Lösung

Dieses Dokument hält bewusst auch die Fehlversuche fest. Gerade bei proprietärer
USB-Hardware waren sie entscheidend, um falsche Annahmen auszuschließen.

## 1. Ausgangsidee

Die Zahlenreihe `1` bis `9` sollte als physisches Task-Dashboard dienen:

- laufend beziehungsweise wartend: zunächst rot blinkend, später bewusst Orange;
- abgeschlossen: Grün;
- Fehler: Rot;
- Tastenkombination plus Ziffer: zur entsprechenden Agent-Aufgabe springen.

Rot wurde aus der normalen Laufanzeige entfernt, weil eine Alarmfarbe sonst bei
jedem gesunden Lauf ständig „Fehler“ signalisiert.

## 2. Erste Unsicherheit: Ist Einzel-RGB von macOS aus möglich?

CHERRY Utility konnte die Tastatur konfigurieren, bot aber keine dokumentierte
macOS-Automationsschnittstelle. Die erfolgreiche Einzel-Tastensteuerung im
Utility zeigte nur, dass die Firmware es kann, nicht wie der Mac die Pakete
senden muss.

## 3. Windows-VM und USB-Mitschnitt

CHERRY Utility wurde in einer Windows-11-VM unter UTM gestartet und die
kabelgebundene Tastatur per USB durchgereicht.

### Probleme auf diesem Weg

- **„Display output is not active“**: Die VM bzw. SPICE-Anzeige war nicht aktiv;
  vor der USB-Analyse musste die normale VM-Ausgabe wieder funktionieren.
- **QEMU `-global: requires an argument`**: Ein manuell ergänzter QEMU-Parameter
  war syntaktisch unvollständig. Zusätzliche Argumente müssen immer als
  vollständige Schlüssel-Wert-Einheit eingetragen werden.
- **PCAP-Pfad konnte nicht geöffnet werden**: QEMU versuchte eine Datei in einem
  nicht vorhandenen oder nicht zugänglichen Pfad zu öffnen. Ein existierender,
  für UTM beschreibbarer Pfad ist Voraussetzung.
- **Wireshark zeigte nur Ethernet, Loopback und ETW**: Das war kein Tastaturfehler.
  Die USB-Capture-Schnittstelle fehlte; USBPcap musste in Windows installiert und
  Wireshark danach mit den passenden Rechten neu gestartet werden.
- **CHERRY Utility erkannte die Tastatur zeitweise nicht**: USB-Passthrough kann
  immer nur einen Besitzer haben. Nach erneutem Verbinden mit der VM und Start
  des Utility wurde das Gerät wieder erkannt.

### Der brauchbare Mitschnitt

Nur Taste `1` wurde in der festen Folge

```text
grün → aus → rot → grün → aus
```

geändert. Dadurch ließen sich veränderliche RGB-Bytes von konstantem
Protokollrahmen unterscheiden. Aus dem Mitschnitt entstanden die Erkenntnisse in
[PROTOCOL.md](../PROTOCOL.md).

## 4. Direkter macOS-HID-Prototyp

Der erste Swift-Prototyp listete alle Geräte mit `VID 046A` und `PID 01E2` und
sendete zunächst grundsätzlich nichts. Das war wichtig, weil die Tastatur
mehrere HID-Schnittstellen besitzt.

### Falsche Annahme

Nur VID und PID zu prüfen reicht nicht: Eine andere Vendor-Schnittstelle meldet
Report ID `5`. Erfolgreich war die Kombination aus 64-Byte-Output-Report und der
im Descriptor vorhandenen Output Report ID `4`.

### macOS-Berechtigungsfalle

Ein doppelt angeklicktes Hintergrund-App-Bundle zeigt absichtlich kein Fenster.
Ohne **Eingabeüberwachung** schlug `IOHIDManagerOpen` mit `0xE00002E2` fehl. Nach
manueller Freigabe und Neustart funktionierte der Hardwarezugriff.

Beim Ersetzen oder anders Signieren einer App kann macOS die TCC-Zuordnung als
neue Anwendung betrachten. Eine stabile Bundle-ID und möglichst dieselbe
Development-Signatur vermeiden wiederholte Freigaben.

## 5. Von einer LED zu neun Task-Slots

Einzelberichte waren gut zum Verifizieren, aber ungeeignet für mehrere Aufgaben.
Die vollständige 378-Byte-Tabelle (`0B`) erwies sich als richtige Ebene. Die
Slots 11–19 entsprechen der Zahlenreihe. Damit konnte jede Aktualisierung alle
neun Taskfarben konsistent setzen.

## 6. Erster Lebenszyklus: nur Hooks

`UserPromptSubmit` setzte eine Sitzung auf „laufend“, `Stop` auf „fertig“. Das
funktionierte für neue, hook-fähige Läufe und bewies die Ende-zu-Ende-Kette.

### Warum das nicht genügte

- alte, schon offene Desktop-Aufgaben hatten keinen Start-Hook geliefert;
- wiederaufgenommene Threads verhielten sich nicht immer wie neue Sitzungen;
- mehrere gleichzeitig laufende Desktop-Aufgaben waren nicht zuverlässig
  vollständig sichtbar;
- ein Stop-Hook unterscheidet nicht automatisch jeden Fehlerfall.

## 7. Versuch, den Codex App Server direkt zu abonnieren

Die öffentliche App-Server-Semantik kennt Thread-Status sowie Turn-Start und
Turn-Abschluss. Der laufende Desktop-Prozess kommunizierte lokal jedoch über
private Pipes. Ein Verbindungsversuch über den sichtbaren IPC-Socket und
`app-server proxy` lieferte keine nutzbare Antwort. Einen zweiten App Server zu
starten hätte nicht den Zustand des bereits laufenden Desktop-Clients gespiegelt.

Diese Route wurde deshalb nicht zur Laufzeitabhängigkeit gemacht.

## 8. Erfolgreiche Desktop-Erkennung über Rollout-Dateien

Codex Desktop schreibt pro Thread append-only JSONL-Rollouts mit klaren
`task_started`- und `task_complete`-Ereignissen. Der Monitor liest nur neue Bytes,
rekonstruiert beim Start aktive Sessions und führt Hook- und Desktop-Ereignisse
über dieselbe Sitzungs-ID zusammen.

### Weitere subtile Fehler

- `session_meta` kann nach `task_started` erscheinen. Deshalb wird beim ersten
  vollständigen Scan zunächst die Metadatenlage und erst danach die Ereignisfolge
  ausgewertet.
- Eine letzte JSONL-Zeile kann noch unvollständig sein. Sie darf erst nach dem
  nächsten Newline geparst werden.
- Beim Programmstart dürfen kürzlich abgeschlossene historische Threads nicht
  alle Tasten belegen. Nur aktive Sessions werden neu angelegt.
- Ein Scan über die gesamte jahrelange Session-Historie alle zwei Sekunden wäre
  unnötig teuer. Es werden nur drei Tagesverzeichnisse betrachtet.

## 9. Globale Navigation ohne bestehende Kürzel zu stören

Ein einzelner Druck auf `1` bis `9` kam nicht infrage, weil er normale Eingabe
zerstören würde. `⌘1…9` ist in vielen Programmen für Tabs belegt. Gewählt wurde
deshalb zunächst `⌃⌥⌘1…9`. Im Praxistest war das unnötig umständlich. Die
endgültige Belegung `⌃⌘1…9` benötigt nur zwei Modifier, bleibt aber getrennt von
`⌘1…9` und `⌃1…9`.

macOS registriert diese Kombinationen als echte globale Hotkeys. Ist eine
Kombination schon vergeben, schlägt die Registrierung fehl, statt den Besitzer
zu überschreiben. Im Test waren alle neun Kombinationen konfliktfrei.

Die installierte Codex-App registrierte das URL-Schema `codex` und akzeptierte
`codex://threads/<thread-id>`. Damit ist ein genauer Sprung möglich, ohne Maus,
Fensterkoordinaten oder simulierte Suche.

## 10. Erfolgreicher Endzustand

Die robuste Kette besteht nun aus:

1. Desktop-JSONL-Monitor als Hauptquelle;
2. Hooks als optionaler schneller Zusatz;
3. persistenter, gesperrter Task-Zustand mit Deduplizierung;
4. neun RGB-Slots über die komplette Farbtabelle;
5. Orange blinkend für Arbeit/Warten, Grün für Erfolg, Rot nur für Fehler;
6. `⌃⌘1…9` für den direkten Rücksprung zur Aufgabe;
7. signiertem Hintergrund-App-Bundle plus LaunchAgent für den Login-Start.

Die größte verbleibende technische Schuld ist die Abhängigkeit von beobachteten,
nicht offiziell stabilisierten Codex-Datei- und URL-Formaten. Die Adaptergrenze
ist deshalb bewusst klein gehalten.
