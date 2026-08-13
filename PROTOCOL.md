# Technische Notizen zum RGB-Protokoll der PIXIU 75

## Beobachtetes Gerät

| Merkmal | Wert |
| --- | --- |
| USB Vendor ID | `046A` |
| USB Product ID | `01E2` |
| RGB OUT Endpoint im Windows-Mitschnitt | `0x05` |
| Antwort-Endpunkt | `0x82` |
| Transportgröße | 64 Byte |
| verwendete HID Report ID unter macOS | `4` |

Alle Werte stammen aus einer einzelnen kabelgebundenen CHERRY PIXIU 75. Andere
Firmware- oder Hardwarevarianten müssen vor dem Senden separat geprüft werden.

## Wie der Mitschnitt entstand

CHERRY Utility lief in einer Windows-11-VM unter UTM. USBPcap zeichnete den
USB-Verkehr auf, während nacheinander ausschließlich die Farbe der Taste `1`
geändert wurde:

```text
grün → aus → rot → grün → aus
```

Diese bewusst einfache Folge machte die drei veränderlichen RGB-Bytes sichtbar.
Roh-PCAP-Dateien gehören wegen möglicher Geräte- und Nutzungsdaten nicht in dieses
Repository.

## Einzelne ausgewählte Taste

Die beobachtete Transaktion bestand aus:

1. Beginn mit Command-Byte `01`
2. Farbe der ausgewählten Taste mit Command-Byte `06`
3. Übernahme mit Command-Byte `02`

Im 64-Byte-Bericht für die Zahlentaste `1` lagen Rot, Grün und Blau an den
Offsets 13, 14 und 15. Beobachtete Werte:

| Zustand | RGB-Bytes |
| --- | --- |
| deaktiviert / keine Farbe | `FF FF FF` |
| rot | `FF 00 00` |
| grün | `00 54 1C` |
| im Prototyp verwendetes Orange | `FF 60 00` |

`FF FF FF` ist hier der vom CHERRY Utility beobachtete „aus“-Sentinel und nicht
weißes Licht.

## Vollständige Farbtabelle

Persistente Farbzuweisungen verwenden Command `0B`. Eine 378 Byte große Tabelle
wird in sieben Nutzdatenblöcke aufgeteilt und anschließend übernommen.

- Taste `1`: Tabellenslot 11, Offsets 33–35
- Tasten `1` bis `9`: Slots 11–19
- Die zurückgelesene Tastenbelegung weist diesen Slots die HID Usages `1E` bis
  `26` zu; damit ist die Zuordnung zur Zahlenreihe eindeutig.

Der Prototyp erzeugt deshalb pro Aktualisierung:

```text
01 (begin) → 7 × 0B (table chunks) → 02 (commit)
```

## Auswahl der richtigen macOS-HID-Schnittstelle

Die Tastatur stellt mehrere HID-Schnittstellen bereit. Vendor- und Product-ID
allein reichen daher nicht aus. Die erfolgreiche Auswahl verlangt gleichzeitig:

- maximales Output-Report-Format von 64 Byte und
- eine im HID Report Descriptor deklarierte Output Report ID `4`.

Eine andere Vendor-Usage-Page der Tastatur verwendet Report ID `5`; sie gehört
nicht zu dem hier beobachteten RGB-Transport.

## Sicherheitsregel des Werkzeugs

Diagnosebefehle sind standardmäßig Dry-Runs. Erst `--apply` sendet Daten. Vor
jedem Schreibzugriff validiert das Programm VID, PID, Reportgröße und Report ID.
Das reduziert das Risiko, Berichte an eine falsche HID-Schnittstelle zu senden.

