# UX-Review der ganzen App aus Rudersicht (23.11.2026)

Grundlage: 35 Bildschirmfotos der Klicktour `tools/coursebuilder/build/sim-screens/tour-9744c6c/` (iPad Pro 11" quer, Simulator, Beispieldaten, Systemsprache Englisch). Gelesen wurden dazu `KONZEPT.md`, `docs/design/startscreen*.md` und `App/RowCoach/Views/**`. Bildnummern stehen in eckigen Klammern, z. B. [06]. Schwere: **H** hoch, **M** mittel, **N** niedrig.

## 1. Kurzurteil

Der Startbildschirm (Variante C) und die 3D-Fahrt tragen die App: „Los“ ist ein einziger Tipp, und der Trainingsbaustein im Ruderbildschirm zeigt Phase, Restzeit und Zielwerte mit Ampel. Dahinter wirkt die App aber wie zwei verschiedene Produkte. Die Rudern- und Fahrbildschirme sind dunkel und ruhig, Listen, Programme, Verlauf, Geräte und Einstellungen sind hell und im iOS-Standardstil, mit vier verschiedenen Akzentfarben (Orange, Blau, Pink, Grün). Am Ruderer fehlt die Rangordnung der Werte: Tempo /500 m ist die kleinste Kachel, die Geschwindigkeit in km/h steht gross oben, und die Restzeit eines Intervalls ist kleiner als die Watt. Zwei Fehler blockieren den Alltag: Das Fahrtdetail ist fast unleserlich [04, 22], und beim Beenden fehlt „Weiterrudern“ [16].

## 2. Mängel nach Klickstrecke

### Start und Vorschlag [01–04, 35]
| S | Bild | Mangel | Vorschlag |
|---|---|---|---|
| H | 04 | Fahrtdetail als Sheet: Text schwarz auf Schwarz. Ursache im Code: `SummaryView` setzt einen dunklen Hintergrund, erbt aber das helle Farbschema (fehlendes `.environment(\.colorScheme, .dark)`). Unten eine helle Systemleiste. | Zusammenfassung erzwingt das dunkle Schema. Die Aktionen kommen in eine dunkle Leiste aus dem Gestaltungssystem (Abschnitt 4). |
| M | 01 | Der Hinweis „Standardwerte – Profil prüfen“ und das Badge „1“ an „Einstellungen“ sagen dasselbe, dauerhaft. | Nur das Banner zeigen. Nach ✕ bleibt ein Punkt am Tab, ohne Zahl. |
| M | 01 | Der Begründungssatz wiederholt das Programm („… heute Zeit-Pyramide 1-2-3-4-3-2-1“). Wird die Karte „Letzte Fahrt“ angeschnitten, ist die Bestzeit-Zeile abgeschnitten. | Den Satz auf den Grund kürzen: „Letzte harte Einheit vor 12 Tagen.“ Die Karte „Letzte Fahrt“ so kürzen, dass sie ganz sichtbar ist. |
| M | 02 | „Vorschau“ zeigt die Zielwerte als Spanne über alle Phasen („1:56–2:04“), ohne die Phasen selbst. Es gibt zwei Los-Tasten übereinander. | Die Vorschau zeigt die Phasenliste kompakt (Dauer, Tempo, Schlagzahl je Block). Nur das Sheet hat eine Los-Taste; die Taste der Karte dahinter wird ausgeblendet statt nur abgedunkelt. |
| N | 03 | Die Wochenansicht zeigt das Kopfelement (Punkte Mo–So) doppelt, im Sheet und auf der Karte dahinter. | Im Sheet direkt mit „Neue Woche / Letzte Woche“ beginnen. |
| N | 01 | Das Datum steht als „Mon Nov 23“, die Oberfläche ist deutsch. | Siehe „Sprache und Formate“ unter Einstellungen. |

### Strecke wählen [05–07b]
| S | Bild | Mangel | Vorschlag |
|---|---|---|---|
| H | 06 | Die Tasten „Frei rudern“ und „Mit Training“ liegen auf dem iPad quer unter der Falz. Man muss scrollen, bevor man rudern kann. | Zweispaltiges Layout: links Luftbild und Text, rechts eine feste Spalte mit Tempo-Linie, den beiden Tasten und „Heutiger Vorschlag hier“. Auf dem iPhone kommen die Tasten in eine feste Leiste unten. |
| M | 07 | Beim Scrollen läuft der Inhalt unter dem schwebenden Titel „Rhein Basel“ und der Tab-Leiste durch und bleibt halb lesbar. | Eine Kopfleiste mit Material-Hintergrund, sobald gescrollt wird, oder den Titel ganz weglassen (der grosse Titel steht im Inhalt). |
| M | 06, 07 | Daten widersprechen sich. „Fakten: 2 Brücken“, aber „Unterwegs“ listet vier (Wettstein, Mittlere, Johanniter, Dreirosen). Die Länge heisst hier „1,6 km hin und zurück, 3,1 km“, in Frei rudern [11] „2 × 1550 m = 3100 m“ und in „Anders wählen“ [05] „20 km“ (Summe aller Fahrten). | Eine einzige Längenangabe in allen Ansichten: „3,1 km (2 × 1,55 km)“. Die Brücken zählt das Kartenpaket. |
| M | 05 | „Anders wählen“ bietet vier Wege zum selben Ziel: Chips „Lockere Grundlage“ und „Frei rudern · Utoquai“, die Karten „Frei rudern“ und „Training“ sowie die Streckenkacheln. Das Kachelraster ist versetzt (Luzern sitzt höher). | Oben zwei Reihen: „Training wählen“ und „Frei rudern“. Darunter die Strecken in einem sauberen Raster mit gleicher Höhe. Die Chips fallen weg. |
| N | 07b | „Unterwegs“ ist zweisprachig gemischt („voraus auf der Hinfahrt · just behind the start“). | Kommt aus den Streckentexten (Simulator englisch). Beschriftungen und Texte immer in derselben Sprache. |
| N | 06 | Der Schalter „Tempo-Linie“ ist halb so breit wie die Tasten darunter, der Aus-Zustand ist auf Dunkel kaum erkennbar. | Volle Spaltenbreite, Aus-Zustand mit sichtbarer Kontur. |

### Training wählen [08–10, 13–14]
| S | Bild | Mangel | Vorschlag |
|---|---|---|---|
| H | 08–14 | Helles Design mitten im dunklen Ablauf, mit einer blauen Haupttaste „Strecke wählen“ [14]. | Dunkles Thema. Die Haupttaste ist orange. |
| H | 09→13 | Der Filter „Einsteiger“ von der Streckenseite ist im Programmkatalog noch aktiv. „Filter zurücksetzen“ steckt im Sortiermenü [10]. | Filter je Einstieg zurücksetzen. Ein aktiver Filter zeigt eine Zeile „6 von 11 · Filter löschen“ über der Liste. |
| M | 08 | In der Phasenleiste ist jeder Belastungsblock orange, ob „Lockere Grundlage“ oder Sprint. Die Leiste zeigt also nur die Struktur, nicht die Härte. | Belastungsblöcke nach Zielzone färben (Zonenfarben, Abschnitt 4). Die Höhe zeigt dann Arbeit oder Pause. |
| M | 08, 14 | Zeit-Pyramide (Zone 3–5, bis 2000-m-Tempo −3 s) ist als „Einsteiger“ eingestuft. | Einstufen nach Zielzone und Dauer: Zone ≥ 4 ist „Fortgeschritten“. |
| M | 08 | Fachjargon und Anglizismen: „5-6k-Tempo“, „2k+3 s“, „Pace bleibt gleich“, „Power 20“. | „Tempo der 2000-m-Bestzeit + 3 s“, „Tempo bleibt gleich“, „20 kräftige Schläge“. |
| M | 14 | Der Weg Training → Strecke ist umgekehrt zum Weg über die Streckenseite. Es gibt keinen „Los“ mit der letzten oder der vorgeschlagenen Strecke. | Unter „Strecke wählen“ eine Zeile „Los auf Utoquai“ (zuletzt bzw. vorgeschlagen). |
| N | 08 | Die Kartenhöhen springen, weil die Mittelspalte zwei Zeilen Titel hat. „ca. 27:44 min“ statt „ca. 28 min“. | Feste Kartenhöhe, Titel einzeilig mit Abkürzung. Dauer immer auf Minuten runden. |

### Frei rudern mit Tempo-Linie [11–12]
| S | Bild | Mangel | Vorschlag |
|---|---|---|---|
| M | 12 | Das Tempo wird mit doppelten Tasten eingestellt („−5 s“, „−“, „+“, „+5 s“), dazu ein pinker Schalter als vierte Akzentfarbe. | Ein Rad oder ±1 s mit Halten zum Beschleunigen. Vorbelegt mit dem letzten Tempo bzw. dem Ø Tempo der letzten Fahrt. Pink nur für die Linie in der Szene. |
| M | 12 | „2:18.0“ zeigt Zehntel, die beim Einstellen nichts bedeuten. | „2:18 /500 m“. |
| N | 11 | Der Gerätestatus steht hier als Textzeile, auf dem Start als Chip. | Überall derselbe Chip. |

### Rudern: HUD, Training, Tempo-Linie, Verkehr [15, 17, 30–34]
| S | Bild | Mangel | Vorschlag |
|---|---|---|---|
| H | 15, 31 | Die Rangordnung stimmt nicht. Tempo /500 m ist die kleinste Kachel (Zahl ca. 60 pt, Schlagzahl ca. 80 pt). „Geschwindigkeit 14.4 km/h“ steht gross in der Kopfleiste, obwohl kein Ruderer in km/h denkt. | Tempo als grösste Zahl (iPad 120 pt) unten in der Mitte, Schlagzahl daneben. Geschwindigkeit nur auf Wunsch. Kopfleiste: Zeit, Distanz, Rest. |
| H | 31–34 | Die Restzeit der Phase (z. B. „3:17“) ist kleiner als Watt und Puls und steht im Kasten oben links. Das Zieltempo steht nur dort als Zahl mit Punkt, die Tempo-Kachel selbst zeigt kein Ziel. | Im Intervall wird die Phasen-Restzeit die zweitgrösste Zahl. Die Tempo-Kachel zeigt das Ziel klein darunter („Ziel 1:58–2:02“) und färbt ihren Rand nach der Ampel. Dasselbe gilt für die Schlagzahl. |
| H | 30 | Die Tempo-Linie meldet „gleichauf“, im Bild ist aber keine Linie zu sehen. | Die Linie bei Gleichstand 5–10 m vor dem Bug zeigen, und den Abstand in Metern oder Sekunden als Zahl („+3 m“, „−1,2 s“). |
| M | 31 | „Training noch 23:02“ oben und „noch ca. 23:02“ in der Phasenleiste doppeln sich. Die Leiste trägt die Beschriftung „Runde 1“, die nichts erklärt. | Restzeit nur einmal (oben). In der Phasenleiste stattdessen „Intervall 1 von 4“. |
| M | 15, 33 | Die Ruder laufen sichtbar über die Kacheln. Die Kacheln decken Boot und Figur halb ab. | Kacheln niedriger und nur bis zum Bootsrand, oder die Kamera etwas höher setzen. Ruder unter dem HUD-Hintergrund zeichnen. |
| M | 15 | „unter Zone 1“ bei 77–111 bpm wirkt wie ein Fehler. | Unter Zone 1 nichts anzeigen bzw. „locker“. |
| N | 17 | Verkehr und Schiff sind gut sichtbar und ruhig. | Bleibt. Nur keine Boote hinter dem Trainingskasten auftauchen lassen. |
| N | 15 | Der Chip „Simulator“ ist knallig pink-violett. | Ruhiger Chip, Zustandsfarbe „Hinweis“. |

### Fahrt beenden und Zusammenfassung [16, 18–20]
| S | Bild | Mangel | Vorschlag |
|---|---|---|---|
| H | 16 | Im Dialog fehlt „Weiterrudern“. Auf dem iPad zeigt `confirmationDialog` die Abbruch-Taste als Popover nicht an, man kann nur speichern oder verwerfen. Die Fahrt läuft weiter, während der Dialog offen ist. | Eigener Dialog mit drei grossen Tasten: **Weiterrudern** (Standard), Beenden und speichern, Verwerfen (rot, mit Rückfrage). Die Zeit hält an, solange der Dialog offen ist. |
| H | 16→18 | ✕ (Rudern) und „Fertig“ (Zusammenfassung) sitzen an derselben Stelle oben rechts. Ein Doppeltipp schliesst die Zusammenfassung ungesehen. | „Fertig“ unten als breite Taste, oben rechts nichts. Oder eine Sperre von 1 s nach dem Wechsel. |
| M | 18 | Die Anstrengungsabfrage braucht zwei Tipps (Zahl, dann „Speichern“). Die blaue Taste ist eine fünfte Akzentfarbe. | Ein Tipp auf die Zahl speichert sofort. Darunter klein „Überspringen“. |
| M | 19 | Der Hinweis „Nicht in Apple Health“ steht dreimal (Titelzone, Unterzeile, orange Zeile in der Belastungskarte). | Einmal als Banner mit „Verbinden“. |
| M | 20 | „Splits“ zeigt eine einzige Zeile für die ganze Fahrt (363 m). Bei einer Trainingsfahrt fehlt die Tabelle je Intervall. | Splits je 500 m. Bei Intervallen eine Zeile je Belastungsblock mit Ø Tempo, Schlagzahl, Watt, Puls und Ampel gegenüber dem Ziel. |
| M | 20 | Pulszonen: Legende „<1 / Z1 / Z2“ in Weiss, Grau und Blau. In den Einstellungen [24] tragen die Zonen andere Farben. Die Zonenlinien im Diagramm haben keine Beschriftung. | Ein Satz Zonenfarben (Abschnitt 4), Zonen als farbige Bänder hinter der Kurve. |
| N | 19 | Die Kachel „Schläge“ steht allein in einer zweiten Reihe, und die Pulskachel ist höher als die anderen. | Sechs Kacheln in einer Reihe. Schläge und Kalorien als Text darunter. |

### Verlauf [21–22]
| S | Bild | Mangel | Vorschlag |
|---|---|---|---|
| H | 22 | Dasselbe Lesbarkeitsproblem wie [04]. Die Aktionen „Belastung ändern“ und „In Apple Health speichern“ liegen in einer hellen Leiste. | Wie [04]. |
| H | 21 | Die Liste ist voll mit Testfahrten (1 m · 0:00, 40 m · 0:10). Alle Fahrten heissen „Utoquai – Seefeld“, das Programm fehlt. | Fahrten unter 100 m bzw. 1 min nicht speichern. Simulatorfahrten nur mit Filter. Titel = Programm, Untertitel = Strecke. |
| M | 21 | Die Symbole (Monitor, durchgestrichene Flagge, durchgestrichenes Bluetooth) erklärt niemand. | Text-Chips: „Simulator“, „Nicht in Health“. |
| M | 21 | Es gibt keine Wochensicht. Die Wochenkarte liegt nur auf dem Start [03]. | Die Liste nach Wochen gruppieren, mit Kopfzeile „KW 48 · 3 Fahrten · 81 min · leicht/hart“. Die Wochenkarte auf dem Start springt dorthin. |

### Geräte [23]
| S | Bild | Mangel | Vorschlag |
|---|---|---|---|
| H | 23 | Die Überschrift heisst „Verbunden“, darunter steht zweimal „nicht verbunden“. „Gefunden“ ist leer, ohne Zustand, und „Suchen“ oben rechts ist grau. | Je Gerät eine Karte mit Zustand (verbunden · sucht · nicht gefunden), Batterie bzw. Puls live und der Taste „Verbinden“. Während der Suche einen Fortschrittshinweis. Die Anleitung als nummerierte Schritte mit PM5-Bild. |
| M | 23 | Der Simulator ist an, die Geräteseite sagt das aber nicht. | Banner: „Simulator aktiv – echte Geräte werden ignoriert“ mit Schalter. |

### Einstellungen [24–28]
| S | Bild | Mangel | Vorschlag |
|---|---|---|---|
| H | 24 | Maximalpuls und 2000-m-Bestzeit werden mit ±-Tasten eingestellt. Von 8:00 auf 7:20 sind das Dutzende Tipps. | Zahlenfeld bzw. Rad (min:s). Daneben „aus dem letzten 2000-m-Test übernehmen“. |
| M | 25–28 | Der Bereich „Entwickler“ (Simulator, Testtempo, PM5-Neustart) steht gleichrangig zwischen den Nutzereinstellungen. | Ausblenden, erst nach siebenmaligem Tippen auf die Version sichtbar (oder nur in Debug-Builds). |
| M | 24, 07 | Die Quellen sind unvollständig. Die Streckenseite nennt OSM und Copernicus, die Einstellungen nur swisstopo. | Eine gemeinsame Quellenliste aus allen Kartenpaketen. |
| M | alle | **Sprache und Formate:** englische Datumsformate („Monday, 23 November 2026 at 21:12“, „Nov 23, 2026 at 21:12“), englische Streckentexte, Dezimalpunkt bei km/h und Schlagzahl („14.4“, „21.8“). | Alles über `Locale` formatieren, Strecken- und UI-Texte in derselben Sprache. Ausnahme: das Tempo als `m:ss,z` bzw. `m:ss` wie am PM5. |
| N | 24 | Lange Fliesstexte unter jedem Block (Health, Zonen, Sonnenstand). | Je ein Satz, der Rest hinter ⓘ. |

### Leer-Zustand und erster Start [35]
| S | Bild | Mangel | Vorschlag |
|---|---|---|---|
| M | 35 | Das Luftbild beginnt erst bei etwa 18 % der Kartenbreite (links ein dunkler Streifen). Der Titel läuft durch den Endpunkt der Route. | Bild randlos füllen, die Route rechts von der Textspalte platzieren, Verlauf hinter dem Text. |
| M | 35 | „Willkommen“ steht zweimal, „30 min“ zweimal („Lockere Grundlage 30 min“, „Utoquai · 30 min“). Kein Hinweis „PM5 verbinden“, obwohl der Chip „nicht verbunden“ zeigt. | Titel „Lockere Grundlage“, Unterzeile „Utoquai · 30 min“. Beim ersten Start steht vor „Los“ ein Schritt „PM5 verbinden“ (2 Tipps), dann das Profil. |
| N | 35 | Die Karte „Letzte Fahrt“ ist leer und gross. | Stattdessen „Deine Strecken: 5 offen“ mit Mini-Luftbildern (Seen-Pass). |

## 3. Effizienz: Tipps bis zum Rudern

| Weg | Heute | Vorschlag |
|---|---|---|
| Vorschlag rudern | **1** (Los) | 1 |
| Letzte Fahrt wiederholen | nicht vorgesehen (≥ 4) | **2** (Karte „Letzte Fahrt“ → „Nochmal“) |
| Frei rudern auf anderer Strecke | 3 (Anders wählen → Frei rudern → Kachel) | **2** (Anders wählen → Kachel mit Los) |
| Frei rudern mit Tempo-Linie | 5–8 (+ Schalter, Tempo ±, Kachel) | **3** (Tempo vorbelegt mit dem letzten Wert) |
| Bestimmtes Training, Wunschstrecke | 5, mit aktivem Filter 7 (Anders wählen → Training → [Filter löschen] → Programm → Strecke wählen → Kachel) | **3** (Anders wählen → Programm → „Los auf Utoquai“ oder Strecke) |
| Training über Streckenseite | 4 + Scrollen (Anders wählen → Strecke → scrollen → Mit Training → Programm) | **3**, ohne Scrollen |
| Fahrt beenden bis Startbildschirm | 5 + Wartezeit (✕ → Beenden → Zahl → Speichern → Fertig) | **3** (✕ → Beenden → Zahl; Fertig unten) |
| Erster Start bis rudern | Profil: 10–40 Tipps ±; PM5 über Tab „Geräte“ | **5** (PM5 verbinden 2, Profil per Zahlenfeld 2, Los 1) |

## 4. Gestaltungssystem (kurz)

**Thema.** Durchgehend dunkel, in der ganzen App. Hell nur für Systemblätter, die iOS vorgibt (Health-Freigabe, Teilen). Eine Datei `Theme` als einzige Quelle. Alle Ansichten setzen das dunkle Farbschema an der Wurzel (`.preferredColorScheme(.dark)` am `TabView`), nicht je Karte.

**Farbtokens.**
| Token | Wert | Verwendung |
|---|---|---|
| `bg` | #080F1A | Grund aller Seiten |
| `card` | #121A29, Rand weiss 7 % | Karten, Listen, Sheets |
| `hud` | Schwarz 48 %, Rand weiss 8 % | Kacheln über der 3D-Szene |
| `text` / `text2` / `text3` | weiss 100 / 65 / 40 % | Werte / Beschriftung / Hinweis |
| `accent` | Abendorange #F29C4D | **nur** Hauptaktion (Los, Frei rudern, Speichern) und Kicker |
| `link` | #66CCF2 | Textlinks, Nebenaktionen als Text |
| `ok` / `warn` / `bad` | #4DD973 / #FACC40 / #F24D4D | Ampel Ziel, Health-Status, Verwerfen |
| `paceLine` | #FA52BD | nur Tempo-Linie in der Szene und in deren Kachel |
| Zonen Z1–Z5 | grau-blau #8CA6BF, blau #4DA6F2, grün #4DCC73, orange #FAA633, rot #F24D4D | Puls, Phasenleiste, Zonenbänder, Anstrengung |
Blau als Tastenfarbe, Pink als Schalterfarbe und Grün als Schalterfarbe fallen weg. Schalter verwenden `accent`.

**Schriftstufen (pt, SF Rounded, Ziffern fest breit).**
| Stufe | iPad am Ruderer | iPad Menü | iPhone |
|---|---|---|---|
| Hauptwert (Tempo; im Intervall die Restzeit) | 120 | – | 72 |
| Kachelwert | 72 | 40 | 44 |
| Kopfleiste (Zeit, Distanz, Rest) | 44 | – | 28 |
| Titel | – | 44–60 | 32 |
| Text | 22 | 19 | 17 |
| Beschriftung (Versalien, gesperrt) | 16 | 14 | 12 |
Untergrenze am Ruderer: 16 pt. Kein Text unter 14 pt im Menü.

**Raster und Abstände.** 8-pt-Raster. Ränder iPad 32, iPhone 16. Abstand zwischen Karten 16–24, Innenabstand der Karten 24. Eckradien: Karte 24, Kachel 18, Taste als Kapsel, Chip 12. Tastfläche mindestens 64 pt hoch, Hauptaktion 88 pt.

**Bausteine.**
- **Karte:** `card`, Radius 24, ein Titel, höchstens 3 Zahlen.
- **Haupttaste:** Kapsel `accent`, Text dunkel 28 pt, eine je Ansicht.
- **Nebentaste:** Kapsel mit Glas bzw. `card` und weissem Text.
- **Kennzahl-Kachel:** Beschriftung 16 pt oben, Wert mit Einheit klein, optional Ziel darunter und farbiger Rand nach Ampel.
- **Listenzeile:** Titel / Untertitel links, Wert rechts, 72 pt hoch.
- **Sheet:** dunkel, Kopf mit „Schliessen“ links, Aktionen in einer dunklen Fussleiste.
- **Banner:** eine Zeile mit Symbol, Satz und Aktion; schliessbar.
- **Leer-Zustand:** Bild bzw. Symbol, ein Satz, eine Taste.

**Bewegung.** Nur Überblendung (0,2 s) und Push. Ein Phasenwechsel bekommt einen kurzen Puls des Trainingskastens und einen Ton. Keine springenden Zahlen: Ziffern fest breit, Werte nicht animiert.

## 5. Rudersicht

**Begriffe (Glossar, überall gleich).**
| Verwenden | Statt | Anmerkung |
|---|---|---|
| Tempo /500 m | Pace, 2k-Tempo | Ziel relativ: „2000-m-Tempo + 3 s“ |
| Schlagzahl, Einheit „/min“ | SPM, s/m | in Tabellen kurz „SZ“ |
| Leistung, Einheit „W“ | Watt (als Titel) | |
| Split | Splits für die ganze Fahrt | nur für 500-m-Abschnitte bzw. Intervalle |
| Intervall / Pause | Belastung (als Phase) | „Belastung“ heisst heute zugleich Phase [14, 32] und Anstrengung nach der Fahrt [18]. |
| Anstrengung (1–10) | Belastung | wie Apple Health |
| Einrudern / Ausrudern | – | bleibt |

**Welche Werte wann wichtig sind.**
| Situation | Hauptwert | Nebenwerte | Weg |
|---|---|---|---|
| Frei, Strecke | Tempo | Schlagzahl, Rest bis Ziel, Hochrechnung Zielzeit | km/h, Kalorien |
| Mit Tempo-Linie | Abstand zur Linie (m / s) | Tempo, Schlagzahl | – |
| Intervall | Restzeit der Phase + Tempo gegen Ziel | Schlagzahl gegen Ziel, Ø Tempo des Intervalls, Intervall n von N | Gesamtdistanz klein |
| Pause | Restzeit der Pause (gross) | Split des letzten Intervalls, Puls (Erholung), was als Nächstes kommt | Tempo |
| Grundlage | Puls und Zone | Schlagzahl, Tempo | – |
| Danach | Ø Tempo der Belastung, Splits | Zonenanteile, Anstrengung | Schläge, Kalorien |

**Was im Ruderbildschirm fehlt:** Ø Tempo der laufenden Phase und Split des letzten Intervalls (der PM5 zeigt beides); die Hochrechnung der Zielzeit bei Strecken mit fester Länge („Ziel ca. 18:40“); das Zieltempo der Phase **in** der Tempo-Kachel; ein grosser Pausen-Countdown; der Abstand zur Tempo-Linie als Zahl.
**Was zu viel ist:** Geschwindigkeit in km/h; „Training noch“ doppelt; „Runde 1“; „unter Zone 1“; der Chip „Simulator“ in voller Farbe.

## 6. Top 10 der Änderungen mit grösster Wirkung

1. **Fahrtdetail lesbar machen** [04, 22]: dunkles Farbschema für `SummaryView` erzwingen, Aktionen in eine dunkle Leiste. Behebt einen Fehler, der heute jeden Blick in eine alte Fahrt verhindert.
2. **Beenden sicher machen** [16, 18]: eigener Dialog mit „Weiterrudern“ als Standard, Zeit hält an, „Fertig“ unten statt an der Stelle von ✕.
3. **HUD-Rangordnung nach Ruderlogik** [15, 31–34]: Tempo als grösste Zahl, im Intervall die Phasen-Restzeit gleich gross. Zieltempo und Ampel in der Tempo- und der Schlagzahl-Kachel. km/h weg.
4. **Eine App, ein Thema** [08–14, 21–28]: alles dunkel, Tokens aus Abschnitt 4. Orange nur für die Hauptaktion, Blau, Pink und Grün als Tastenfarben weg.
5. **Streckenseite ohne Scrollen** [06]: Aktionsspalte rechts fest, auf dem iPhone Fussleiste.
6. **Splits und Intervalltabelle** [20]: 500-m-Splits und eine Zeile je Intervall mit Ampel gegenüber dem Ziel.
7. **Glossar und Formate**: „Intervall“ statt „Belastung“ als Phase, „Anstrengung“ für die Abfrage, keine Anglizismen. Datum und Dezimalzeichen über `Locale`.
8. **Verlauf entrümpeln** [21]: Mini-Fahrten nicht speichern, Simulator filtern, Programm als Titel, Gruppen nach Woche statt doppelter Wochenkarte.
9. **Profil per Zahlenfeld** [24]: Maximalpuls und 2000-m-Zeit direkt eingeben bzw. aus dem Test übernehmen. Beim ersten Start „PM5 verbinden“ vor „Los“.
10. **Filter und Wege straffen** [05, 09, 13]: Filter je Einstieg zurücksetzen und sichtbar löschen, Chips in „Anders wählen“ weg, „Los auf <Strecke>“ direkt im Programmdetail, „Nochmal“ auf der letzten Fahrt.
