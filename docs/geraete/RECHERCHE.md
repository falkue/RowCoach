# Rudergeräte und ihre Schnittstellen (Recherche 27.11.2026)

Frage (Falk, 27.11.): Welche gängigen Rudergeräte haben eine offene Schnittstelle, die RowCoach auf dem iPad nutzen
kann? Ergebnis: Der einzige breit offene Weg neben dem Concept2-PM5-Protokoll ist **Bluetooth FTMS** (Fitness Machine
Service, Characteristic *Rower Data*). RowCoach unterstützt ihn jetzt als Beta (Umsetzung: [UMSETZUNG.md](UMSETZUNG.md)).

Recherche-Reihenfolge: Zotero (`zrag` nicht erreichbar, Zeitüberschreitung), Fundus (nur ein Concept2-Kalorienfakt,
sonst nichts zum Thema), dann Web. Fünf Kernfakten stehen in Fundus (Projekt `rowcoach`, Fakten 2448–2452, ungeprüft).
Aus Open-Source-Projekten wurden nur Protokollfakten übernommen, kein Code.

## Was auf dem iPad technisch geht

| Schnittstelle | iPad | Bemerkung |
|---|---|---|
| Bluetooth LE, GATT (FTMS, PM5, proprietäres BLE) | **ja** | CoreBluetooth als Central; FTMS und PM5 brauchen keine Kopplung in den Systemeinstellungen. |
| Bluetooth FTMS 0x1826, Rower Data 0x2AD1 | **ja** | offener Standard der Bluetooth SIG; Spezifikation frei zugänglich. |
| ANT+ / ANT+ FE-C | nein | iPad hat kein ANT-Funkmodul (nur über Brücken-Hardware). |
| USB-Seriell (WaterRower S4 USB, PM5 USB/CSAFE) | nein | USB-CDC-Geräte sind für normale Apps nicht erreichbar (External Accessory nur mit MFi; DriverKit auf M-iPads nur mit Sonderberechtigung). Nicht verfolgt. |
| Proprietäres BLE ohne Doku (Echelon, iFit …) | technisch ja, praktisch nein | nur durch Reverse Engineering; Hersteller sperren teils per Firmware (Echelon 2025). Nicht verfolgt. |
| Cloud/geschlossene Konsole (Hydrow, Ergatta …) | nein | keine Live-Daten nach aussen bekannt. |

## Gerätetabelle

„Nutzbar“ = RowCoach kann die Live-Daten heute lesen. FTMS-Geräte: Beta, mit echter Hardware **ungetestet**.
„Beleg“ nennt die Quelle; „nicht belegt“ = nur Kenntnisstand, keine Quelle gefunden – vor einer Aussage gegenüber
Nutzern prüfen.

| Gerät | Schnittstelle | RowCoach nutzbar | Datenumfang | Beleg |
|---|---|---|---|---|
| Concept2 RowErg mit PM5 | eigenes BLE-Protokoll (CE06…, CSAFE) | **ja** (seit Beginn, getestet) | alles: Zeit, Distanz, Tempo, Schlagzahl, Watt, Kalorien, Schlagzustand, Durchzug/Freilauf, Kraftkurve, Puls vom PM5 | Concept2 *PM CSAFE Communication Definition* (`docs/vendor/csafe.pdf`) |
| Concept2 PM5 – FTMS? | in der Firmware-Historie (bis Mai 2026) **nicht erwähnt**; auch die CSAFE-Doku Rev. 0.31 nennt FTMS nicht | – | – | [PM5 Firmware Timeline](https://www.concept2.com/support/monitors/pm5/firmware-timeline), Fundus 2449. Bietet ein PM5 doch FTMS an, nimmt RowCoach das PM5-Protokoll (mehr Daten). |
| WaterRower mit S4 + Bluetooth-ComModule („WaterRower Connect“) | BLE (nRF52811-Modul); Kinomap, EXR und laut WaterRower Peloton Row verbinden sich – die setzen FTMS voraus, also **sehr wahrscheinlich FTMS** | **ja, Beta** | voraussichtlich Schlagzahl, Schläge, Distanz, Tempo, Watt, Kalorien, Zeit | [Nordic](https://www.nordicsemi.com/News/2023/02/WaterRowers-S4-Performance-Monitor-and-ComModule-employ-module-based-on-nRF52811-SoC) (Fundus 2450), [WaterRower ComModule](https://www.nohrd.com/us/waterrower-com-module.html), [EXR](https://exrgame.com/support/waterrower). FTMS selbst ist von WaterRower nicht ausdrücklich bestätigt. Nur **eine** App gleichzeitig (asensei, EXR). ComModule braucht S4 Version 2. |
| WaterRower S4 ohne ComModule (USB) | USB-Seriell, ASCII-Protokoll („S4 Communications Protocol“; Projekte wie PiRowFlo lesen es und senden FTMS weiter) | nein (iPad) | voll | [EXR: keine USB-Verbindung](https://exrgame.com/support/waterrower); Umweg: Raspberry Pi mit PiRowFlo (GPL-3.0) als FTMS-Brücke → dann **ja, Beta** |
| WaterRower mit SmartRow | eigenes BLE der SmartRow-App; sendet laut App Store an Kinomap, EXR, Zwift weiter | unklar (nicht ausprobiert) | Kraftkurve u. a. | [SmartRow (App Store)](https://apps.apple.com/us/app/smartrow/id1223542275) |
| First Degree Fitness (FDF) mit Bluetooth-Konsole | **FTMS Rower Data** + Pulsgurt-Empfang | **ja, Beta** | laut Anleitung FTMS-Rower-Data; Konsole zeigt während der Verbindung nur Balken | [FDF Console Guide 1.0](https://cdn.shopify.com/s/files/1/1950/1891/files/FDF_FluidRower_Bluetooth_Console_Guide_1.0_11012021.pdf) (Fundus 2448). FTMS-Modus an der Konsole wählen: AUF+AB 3 s halten, dann AUF. |
| Merach (alle Rudergeräte laut Hersteller) | **FTMS** | **ja, Beta** | modellabhängig | [Merach R50 Pro](https://uk.merachfit.com/products/merach-novarow-r50-pro-air-rower) (Herstellerangabe, Fundus 2452) |
| Domyos/Decathlon | einzelne Modelle FTMS (Woodrower, Rower 900 laut RowerTrain); Rower 500B nicht | Woodrower/900: **ja, Beta**; andere: offen | modellabhängig | [RowerTrain (App Store)](https://apps.apple.com/ca/app/rowertrain/id6758657773); EXR führt Domyos |
| Skandika (Venn, Nemo IV), RPM Power, VirtuFit, Flow Fitness | als Kinomap-kompatibel geführt; Kinomap nutzt FTMS als Standard | wahrscheinlich **ja, Beta** | modellabhängig | [Skandika](https://skandika.com/en/service/kinomap), [Kinomap: FTMS](https://support.kinomap.com/hc/en-us/articles/360015335632-What-is-the-FTMS-protocol) (Seite nur als Suchauszug lesbar) |
| Xebex (Air Rower 2.0 u. a.) | von EXR offiziell unterstützt, Protokoll nicht genannt | offen | – | [EXR-Liste](https://exrgame.com/support/compatible-machines); FTMS nicht belegt |
| Technogym Skillrow | BLE, offiziell mit EXR; Protokoll nicht dokumentiert, Kinomap führt ihn nicht | offen (eher nein) | – | [EXR Technogym](https://exrgame.com/support/technogym), [Kinomap Technogym](https://kinomap.com/us/compatibility/technogym) |
| Echelon Row | **proprietäres BLE** (von QZ entschlüsselt); Berichte über Firmware-Sperre lokaler Verbindungen (2025) | nein | – | [QZ](https://apps.apple.com/us/app/qz-qdomyos-zwift/id1543684531), [Bericht Firmware-Sperre](https://news.lavx.hu/article/echelon-s-server-lockout-when-your-fitness-equipment-stops-being-yours) (eine Sekundärquelle) |
| NordicTrack/ProForm (RW600/RW900, iFit) | iFit-Ökosystem; FTMS für Rudergeräte nicht belegt | nein (nach heutigem Stand) | – | [PopSci RW900](https://www.popsci.com/gear/nordictrack-rw900-rower-review/); FTMS nur für einige Laufbänder/Crosstrainer erwähnt |
| Hydrow | geschlossen (eigene Konsole/App), keine Live-Daten nach aussen bekannt | nein | – | nicht belegt (keine Quelle zu FTMS gefunden) |
| Ergatta | geschlossen; Daten nur übers Konto zu Strava/Apple Health; nimmt Pulsgurte an | nein | – | [Ergatta Integrations](https://ergatta.com/blogs/game-based-fitness/ergatta-rower-integrations) |
| Aviron | geschlossen; die Aviron-App läuft umgekehrt auch mit PM5/S4 | nein | – | [Aviron (App Store)](https://apps.apple.com/app/id6453695519) |
| Kettler, Sportstech, Xiaomi/Mobi, Life Fitness (Row HX) | keine belastbare Angabe gefunden; manche Sportstech-/Kettler-Modelle werben mit Kinomap (dann FTMS) | offen – mit FTMS automatisch **ja, Beta** | – | nicht belegt |
| beliebige „Kinomap-/Peloton-kompatible“ Rudergeräte | FTMS (Kinomap und die Peloton-App koppeln Fremd-Rudergeräte nur über FTMS) | **ja, Beta** | geräteabhängig | [Peloton-App und FTMS](https://www.pelobuddy.com/third-party-rowers-ftms/) |
| Zwift | Zwift nimmt Rudergeräte nur über Brücken-Apps (RowedBiker, PainSled) | – | – | [Zwift Insider](https://zwiftinsider.com/rowing-on-zwift/) |

Faustregel für Nutzer: Steht beim Gerät „Kinomap“, „FTMS“ oder „Peloton-App kompatibel“, sollte es mit RowCoach
(Beta) laufen. Geräte, die nur mit der Hersteller-App gehen, gehen mit RowCoach nicht.

## Die FTMS-Schnittstelle (Fakten aus der Spezifikation)

Bluetooth SIG, *Fitness Machine Service 1.0* (2017) mit den Characteristic-Definitionen (ältere XML-Definitionen bzw.
GATT Specification Supplement). Little Endian.

- Dienst `0x1826`. Werbepaket: Service Data zu 0x1826 = Flags (1 Byte, Bit 0 „verfügbar“) + Fitness Machine Type
  (2 Byte, Bit 4 = Rudergerät). Viele Geräte senden keine Service Data; dann entscheidet `0x2AD1` beim Verbinden.
- `0x2ACC` Fitness Machine Feature: 2 × uint32 (Fähigkeiten, Zielwerte). Bits u. a. 1 Kadenz, 2 Distanz, 5 Tempo,
  7 Widerstand, 9 Energie, 10 Puls, 11 MET, 12 verstrichene Zeit, 13 Restzeit, 14 Leistung.
- `0x2AD1` Rower Data (Notify): uint16 Flags, danach nur die Felder, deren Bit gesetzt ist:

| Bit | Feld | Typ | Einheit/Auflösung |
|---|---|---|---|
| 0 = **0** (invertiert, „More Data“) | Stroke Rate · Stroke Count | uint8 · uint16 | 0,5 /min · 1 |
| 1 | Average Stroke Rate | uint8 | 0,5 /min |
| 2 | Total Distance | **uint24** | m |
| 3 | Instantaneous Pace | uint16 | s pro 500 m |
| 4 | Average Pace | uint16 | s pro 500 m |
| 5 | Instantaneous Power | **sint16** | W |
| 6 | Average Power | sint16 | W |
| 7 | Resistance Level | **sint16 (XML/FTMS 1.0) oder uint8 (neuere GSS)** | ohne Einheit |
| 8 | Total Energy · Energy per Hour · Energy per Minute | uint16 · uint16 · uint8 | kcal · kcal/h · kcal/min; 0xFFFF/0xFF = nicht unterstützt |
| 9 | Heart Rate | uint8 | bpm |
| 10 | Metabolic Equivalent | uint8 | 0,1 |
| 11 | Elapsed Time | uint16 | s |
| 12 | Remaining Time | uint16 | s |

- Passt ein Datensatz nicht in eine Notification (MTU 23 → 20 Nutzbytes; alle Felder sind bis 30 Bytes), teilt das
  Gerät ihn auf: Teilpakete mit Bit 0 = 1 (ohne Schlagfelder), das letzte mit Bit 0 = 0.
- `0x2AD9` Control Point (Write + Indicate): 0x00 Request Control (Pflicht vor allem anderen), 0x01 Reset,
  0x07 Start/Resume, 0x08 Stop (Parameter 0x01) bzw. Pause (0x02); Antwort 0x80, Op Code, Ergebnis
  (0x01 Erfolg, 0x02 nicht unterstützt, 0x03 ungültiger Parameter, 0x04 fehlgeschlagen, 0x05 keine Berechtigung).
- `0x2ADA` Fitness Machine Status (Notify): 0x01 Reset, 0x02 vom Nutzer gestoppt/pausiert, 0x04 vom Nutzer
  gestartet, 0xFF Kontrolle entzogen.

## Bekannte Besonderheiten und Fehler

- **Widerstandsfeld 1 oder 2 Byte**: die Definitionen widersprechen sich (Fundus 2451); weil das Feld mitten im Paket
  liegt, verschiebt eine falsche Annahme alle Folgefelder (Puls, Zeit). RowCoach leitet die Breite aus der Paketlänge ab.
- **Aufgeteilte Pakete**: Geräte mit kleiner MTU senden die Schlagwerte in einem eigenen Paket; Apps, die jedes Paket
  als vollständigen Datensatz lesen, zeigen springende Nullen.
- **Schlagzahl ohne Faktor 0,5**: einzelne Konsolen senden ganze statt halber Schläge pro Minute (Anzeige halb so hoch).
- **Felder fehlen**: einfache Konsolen senden nur Schlagzahl, Schlagzähler und Distanz – Tempo, Watt und Zeit muss die
  App selbst berechnen.
- **Nur eine Verbindung**: ComModule und viele Konsolen erlauben nur eine verbundene App; die Hersteller-App vorher
  schliessen.
- **Tempo 0 bzw. 0xFFFF** im Stillstand, **Puls 0** ohne Gurt – als „unbekannt“ lesen.
- Die FTMS-Daten tragen keinen Schlagzustand (Durchzug/Freilauf) und keine Kraftkurve: Technikanalysen wie beim PM5
  gehen mit FTMS nicht.

## Open-Source-Projekte (nur als Faktenquelle, Lizenzen beachtet)

| Projekt | Lizenz | Bezug |
|---|---|---|
| openrowingmonitor | GPL-3.0 | baut aus einem Sensor am Schwungrad ein FTMS-Rudergerät (Peripheral) |
| PiRowFlo | GPL-3.0 | liest WaterRower S4 per USB und sendet FTMS/ANT+ weiter (Brücke fürs iPad) |
| qdomyos-zwift (QZ) | GPL-3.0 | viele proprietäre Protokolle (Echelon, Domyos, iFit) und FTMS |

Wegen GPL-3.0 (RowCoach: Apache-2.0) wurde aus diesen Projekten nichts übernommen; der Parser folgt nur der
Spezifikation, die Testpakete sind selbst gebaut.
