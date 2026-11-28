# App-Look: Marke „Bahnen“ leicht in der App

Stand 28.11.2026. Ziel: Man erkennt die Marke der Website (docs/site/index.html) und des Logos „Bahnen“
(design/logo/bahnen/) in der App wieder. Kein Umbau: gleiche Struktur, gleiche Grössen, gleiche dunkle Fläche;
geändert sind Akzentfarben, die grossen Überschriften, ein dezentes Bahnen-Motiv und der Startbildschirm.
Gilt für beide Targets (RowCoach 1.0 und RowCoachDev), weil beide dieselben Quellen und Assets nutzen.
Ersetzt die Farbzeilen `accent` und `link` in docs/design/ux-review-rowing.md Abschnitt 4.

## Entscheidungen

1. **Gelb ist die Hauptaktion und „du“.** Im Logo ist die gelbe Bahn die Führungsbahn = du. Deshalb trägt Gelb
   (#FFD60A, Text darauf Marken-Tinte #0E1236) die Haupttaste („Los“, `PrimaryButtonStyle`), Kicker
   („DEIN PLAN“, Vorschlag auf Heute, Planname in der Zusammenfassung), den heutigen Tag im Plan, die eigene Zeile in
   Ranglisten und das eigene Boot auf der Minikarte. Abendorange entfällt.
2. **Kobalt hell für Interaktion.** Reines Kobalt (#2340FF) hat auf dem dunklen Grund nur 3,0:1 und taugt dort
   nicht als Text oder Linie. Links, Schalter, Tab-Auswahl, Auswahlrahmen und Häkchen nehmen ein helles Kobalt
   (#9AA8FF, 8,6:1) – nahe an der Linkfarbe der Website im Dunkelmodus (#AEB9FF). Es ersetzt das frühere Cyan
   (#66CCF2) und ist zugleich der globale Tint (`RootView`) und das Asset AccentColor (dunkel).
3. **Kobalt als Fläche.** Gefüllte Auswahl (Wochentage in „Pläne“ und „Wann ruderst du?“) wird Kobalt mit
   weisser Schrift (6,5:1) wie die Kobaltflächen der Website; dort stand bisher Orange. So bleibt Gelb der
   Hauptaktion vorbehalten.
4. **Display-Schrift nur für grosse Überschriften im Inhalt.** Archivo, breit (wdth 125), kursiv, sehr fett (850)
   wie die Überschriften der Website, als statische Instanz im Bundle. Navigationsleisten bleiben SF: Die breite
   Schrift läuft etwa 25 % weiter, lange Titel wie „Konto & Synchronisation“ würden in der grossen
   Navigationsleiste abgeschnitten (sie bricht nicht um). Fliesstext, Listen, Kennzahlen und der ganze HUD bleiben
   SF bzw. SF Rounded mit festen Ziffern.
5. **Kein Martian Mono.** Die Website setzt Daten in Martian Mono. In der App bleiben Zahlen bei SF Rounded mit
   `monospacedDigit()` (Theme.number, DS.HUD): bewährt am Ruderer, eine Schriftdatei weniger, keine Gefahr für die
   Lesbarkeit. Die Wiedererkennung tragen Farbe, Überschriften und Bahnen.
6. **Bahnen-Motiv sparsam.** `BahnMarker` (eine kleine gelbe Bahn in Logo-Proportionen) steht vor den Kickern und
   vor dem heutigen Tag der Plan-Woche; `BahnenMark` (die vierbahnige Bildmarke als Vektor) steht im Kopf von
   „Heute“. „Über RowCoach“ zeigt schon das Bahnen-Logo (Logo.imageset). Keine Animationen.
7. **Startbildschirm Kobalt mit Bildmarke** über `UILaunchScreen` (UIColorName/UIImageName), ohne Storyboard.
   Danach wechselt die App auf den dunklen Grund; das ist gewollt (Marke beim Öffnen), kann aber als harter
   Wechsel wirken – Alternative in der Prüfliste.
8. **Fahrt-Ansicht praktisch unverändert.** Nur was aus dem Token folgt: Countdown der letzten 10 s gelb statt
   orange, eigenes Boot auf der Minikarte gelb; die anderen Ruderer auf der Minikarte wechseln von Warmgelb auf
   Kobalt hell, damit Gelb eindeutig „du“ bleibt. Grössen, Schriften und Kachelfarben des HUD bleiben.
9. **Rennen (nur Dev):** Das Feld im Histogramm wird Kobalt hell (andere), die eigene Position bleibt weiss,
   die eigene Ergebniszeile gelb getönt.

## Farben und Kontraste

Kontrast nach WCAG 2.x (relative Luminanz, gerechnet). Grund `bg` #080F1A, Karte `card` #121A29,
gehobene Fläche `cardRaised` #1C2638. AA verlangt 4,5:1 für Text, 3:1 für grosse Schrift und Bedienelemente.

| Token (Theme) | Farbe | Verwendung | Kontrast |
|---|---|---|---|
| `accent` | #FFD60A Marken-Gelb | Haupttaste, Kicker, du/heute | 13,6 auf bg · 12,3 auf card · 10,8 auf cardRaised |
| `onAccent` | #0E1236 Marken-Tinte | Text auf Gelb | 12,8 auf #FFD60A |
| `brand` | #2340FF Kobalt | Flächen (gefüllte Auswahl), Startbildschirm | 3,0 auf bg (nur Fläche, nie Text/Linie) |
| `onBrand` | #FFFFFF | Text auf Kobalt | 6,5 auf #2340FF |
| `link` = `tint` = `selection` | #9AA8FF Kobalt hell | Links, Schalter, Tabs, Auswahl, Häkchen | 8,6 auf bg · 7,8 auf card · 6,8 auf cardRaised |
| Auswahl getönt | #9AA8FF auf 18 % #9AA8FF über card (#2A3450) | aktive Filter-Kapsel | 5,5 |
| AccentColor hell | #2340FF | Systemdialoge im Hellmodus (App ist dunkel erzwungen) | 6,5 auf weiss · 5,8 auf #F2F2F7 |
| AccentColor dunkel | #9AA8FF | Systemakzent dunkel | 9,4 auf schwarz · 7,6 auf #1C1C1E |
| LaunchBackground | #2340FF | Startbildschirm | Bildmarke weiss 6,5 · gelb 4,6 |

Unverändert: `ok` #4DD973, `warn` #FACC40, `bad` #F24D4D, `paceLine` #FA52BD, Pulszonen.
Abgeschaltete Haupttaste: Gelb mit 35 % Deckkraft (#5E5514, Text 2,4:1) – inaktive Elemente sind von WCAG
ausgenommen, wie vorher bei Orange.

**Bekannte Nähe:** `accent` und `warn` sind fast gleich (1,08:1). Sie trennen sich über die Verwendung: Gelb als
Akzent steht nie auf Messwerten oder Zuständen, `warn` nur in Ampeln, Chips und „zurück zur Tempo-Linie“. Ebenso
liegen `link` und Pulszone 2 (#4DA6F2) in der Helligkeit nah (1,17:1), unterscheiden sich aber im Farbton
(Lavendel gegen Himmelblau) und stehen nicht nebeneinander.

## Schriften

| Stelle | Vorher | Nachher |
|---|---|---|
| Titel „Heute“ (Home) | SF Bold `.largeTitle` | `DSFont.pageTitle` (Archivo Expanded Display Italic, 30 pt relativ zu `.largeTitle`) |
| Titel der Vorschlagskarte auf Heute | SF Bold 40/60 pt fest | Archivo 36/54 pt fest (Zeile mit `minimumScaleFactor` wie vorher) |
| Seiten-Titel im Inhalt: Seen-Pass, Strecke (Detail), Programm, Plan, Plan-Woche („Woche 3 von 12“, „Plan geschafft“, „Wiedereinstieg …“) | SF Bold `.largeTitle` | `DSFont.pageTitle` |
| Zusammenfassung „Ziel erreicht“ u. ä. | SF Bold `.largeTitle` | `DSFont.pageTitle` |
| Navigationsleisten, Listen, Fliesstext, Tasten | SF | SF (unverändert) |
| Kennzahlen, HUD, Countdown | SF Rounded, feste Ziffern | unverändert |

Datei: `App/RowCoach/Resources/Fonts/ArchivoExpandedDisplay-Italic.ttf` (67 KB; statische Instanz wdth 125,
wght 850 aus Archivo Italic, auf Latein beschnitten; PostScript `ArchivoExpandedDisplay-Italic`), erzeugt mit
`tools/fonts/build_display_font.py`. Lizenz SIL OFL 1.1 ohne reservierten Namen: `Resources/Fonts/OFL.txt`
liegt mit im Bundle; Nennung in Einstellungen → „Quellen und Lizenzen“. Registriert über `UIAppFonts` in
App/project.yml. Fehlt die Schrift zur Laufzeit, fällt `Font.custom` still auf SF zurück.
Dynamic Type: `pageTitle` skaliert relativ zu `.largeTitle`; die Titel brechen um (keine `lineLimit`).

## Betroffene Dateien

- `App/RowCoach/Views/Theme.swift` – Tokens `accent`, `onAccent`, neu `brand`, `onBrand`, `link` (Kobalt hell),
  `tint`, `selection`.
- `App/RowCoach/Views/DesignSystem.swift` – `DSFont`, `BahnShape`, `BahnMarker`, `BahnenMark`; Kommentare.
- `App/RowCoach/Assets.xcassets/AccentColor.colorset` – hell #2340FF, dunkel #9AA8FF.
- `App/RowCoach/Assets.xcassets/LaunchBackground.colorset`, `LaunchMark.imageset` (@2x/@3x, 120 pt breit;
  `design/logo/bahnen/build_launch_mark.py`).
- `App/RowCoach/Resources/Fonts/` – Schrift und OFL.txt; `tools/fonts/build_display_font.py`.
- `App/project.yml` – `UILaunchScreen` (UIColorName, UIImageName), `UIAppFonts`, Kommentar zur Akzentfarbe.
- Ansichten: `RootView` (Tint), `Home/HomeView` (Bildmarke, Titel), `Home/SuggestionCard` (Marker, Titel,
  Text auf Gelb), `Home/SeenPass` (Badge-Text), `Home/CourseDetailView`, `CoursePickerView` (Titel,
  Filter-Kapsel, Download-Fortschritt), `ProgramViews` (Titel, Wochentage Kobalt, „DEIN PLAN“, heutiger Tag),
  `PlanViews`, `SummaryView` (Marker, Titel), `Motivation/MotivationViews` (Wochentage Kobalt, Symbole Kobalt hell),
  `ProfileView` (Auswahl), `DevicesView` (Symbol), `PaceLineSetupView` (Schalter), `MiniMapView` (andere
  Ruderer), `RaceFieldPanel` (Feld), `SettingsView` (Lizenzzeile).
- `App/l10n/en_strings.py`, `App/RowCoach/Resources/Localizable.xcstrings` – englischer Text der Lizenzzeile.
- RowCoachKit unverändert.

## Prüfliste auf dem Mac

Vorher: `cd App && xcodegen generate`, beide Schemes bauen (RowCoach, RowCoachDev). Auf dem Spark gab es keinen
Build; die Swift-Änderungen sind klein, aber ungeprüft kompiliert.

Allgemein
- [ ] Schrift geladen: Titel „Heute“ erscheint breit und kursiv. Wenn nicht: Datei in „Copy Bundle Resources“?
      PostScript-Name im Debugger `UIFont(name: "ArchivoExpandedDisplay-Italic", size: 30) != nil`.
- [ ] Startbildschirm: Kobalt mit Bildmarke mittig, iPhone und iPad, hoch und quer. Bei hartem Wechsel auf den
      dunklen Grund ggf. `LaunchBackground` auf #080F1A und Marke behalten (eine Zeile im Asset).
      Hinweis: iOS hält Startbildschirme zwischengespeichert – App löschen oder Gerät neu starten.
- [ ] Systemfarben: Schalter, Tab-Auswahl, Toolbar-Tasten („Schliessen“), Stepper, Alerts in Kobalt hell.

Bildschirme (je hell/dunkel des Systems – die App bleibt dunkel; und Textgrösse Standard sowie
Bedienungshilfen → Grössere Schrift auf Maximum)
- [ ] **Heute:** Bildmarke links neben „Heute“, Datum darunter; Vorschlagskarte mit gelbem Marker vor dem Kicker,
      Titel in Archivo (lange Strecken-/Programmnamen skalieren auf einer Zeile), „Los“ gelb mit dunkler Schrift.
      Seen-Pass-Kachel „Heute“-Badge gelb.
- [ ] **Strecken:** Titel „Seen-Pass“, aktive Filter-Kapsel Kobalt hell, Download-Fortschritt, „Training hier
      starten“ gelb; Strecken-Detail mit langem Titel (Umbruch statt Abschneiden).
- [ ] **Programme:** Programm-Detail mit langem Namen neben dem Level-Badge (Umbruch ok?).
- [ ] **Pläne:** „DEIN PLAN“-Karte mit Marker, Fortschritt gelb; Plan-Woche mit Titel „Woche 3 von 12“ bzw.
      „Wiedereinstieg · Woche …“ (zweizeilig erwartet); heutiger Tag mit gelbem Marker (Spalte 64 pt: bei grosser
      Schrift abgeschnitten?); Wochentage-Auswahl Kobalt mit weisser Schrift; Zieleinheit gelb in der Legende.
- [ ] **Einstellungen:** Links Kobalt hell; „Über RowCoach“ mit Logo; Lizenzzeile „Schrift der Überschriften …“
      (deutsch und englisch).
- [ ] **Zusammenfassung:** Planname mit Marker, Überschrift („Ziel erreicht“ o. ä.) in Archivo, grosse Schrift.
- [ ] **Fahrt:** HUD unverändert lesbar; Countdown ≤ 10 s gelb; Minikarte: eigenes Boot gelb, andere Ruderer
      Kobalt hell und auf Luftbild sichtbar.
- [ ] Profil & Figur: Auswahlrahmen und Häkchen Kobalt hell; „Wann ruderst du?“: Wochentage Kobalt.
- [ ] Dev: Rennen – eigene Zeile gelb getönt, Feld-Histogramm Kobalt hell.

Zurück auf den alten Stand: nur `Theme.accent`/`link` und das AccentColor-Asset zurücksetzen; die Display-Schrift
lässt sich zentral in `DSFont.pageTitle` auf `.largeTitle.bold()` zurückstellen.
