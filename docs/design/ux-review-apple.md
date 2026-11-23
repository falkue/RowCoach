# UX-Review aus Apple-Sicht (HIG iPadOS/iOS 26)

Stand: Commit 9744c6c, Klicktour mit 35 Bildern (`tools/coursebuilder/build/sim-screens/tour-9744c6c/`, iPad Pro 11" quer, Simulator, Systemsprache Englisch). Ich habe den Code unter `App/RowCoach/Views/**` und `RowCoachApp.swift` nur gelesen. Bildnummern stehen in eckigen Klammern. Die HIG-Verweise stammen aus meinem Wissen und sind nicht live nachgeprüft (Basis: developer.apple.com/design/human-interface-guidelines/…).

## 1. Kurzurteil

1. Der Ruderbildschirm und der neue Startbildschirm sind schon „Apple-like“: Es gibt eine klare Hauptaktion („Los“), grosse Zahlen in fester Ziffernbreite, Status- und Home-Leiste werden ausgeblendet, der Idle-Timer ist aus, und die Bestätigung vor „Verwerfen“ ist korrekt als destruktiv markiert [01, 15, 16].
2. Die Systembausteine sitzen weitgehend richtig: `TabView` mit `Tab`, `NavigationStack` mit typisierten Routen, `fullScreenCover` fürs Rudern, `ContentUnavailableView`, `confirmationDialog`, `onDelete` und viele VoiceOver-Labels.
3. Was die App am deutlichsten „un-Apple“ wirkt, ist das Erscheinungsbild: Innerhalb desselben Navigationsstapels springt sie zwischen hell und dunkel [07 → 08], und die Zusammenfassung zeigt in Sheet und Verlauf schwarze Schrift auf schwarzem Grund [04, 22].
4. Uneinheitlich sind auch die Akzentfarbe (Blau aus dem System neben Abendorange [14, 18 gegenüber 01]), die Typografie (feste Punktgrössen statt Dynamic Type) und die Zahlen- und Datumsformate (Dezimalpunkt neben Dezimalkomma, englische neben deutschen Daten) [15, 19, 21, 07].
5. Die Informationsarchitektur ist eine Ebene zu tief und hat doppelte Wege (Streckenliste, „Frei rudern“, „Training“ und Programmliste führen zum selben Ziel), und der Tab „Geräte“ ist eher ein Statusthema als ein eigener Ort.

## 2. HIG-Befunde nach Bereich

### Navigation und Informationsarchitektur
- **Hoch – Doppelte und tiefe Wege [05, 06, 08, 11, 13, 14].** Start → „Anders wählen“ → Strecke → „Mit Training“ → Programm → Los sind bis zu fünf Ebenen. „Frei rudern“ (Karte) und „Deine Strecken“ führen fast zum selben Ziel. Empfehlung: Auf dem iPad `TabView` mit `.tabViewStyle(.sidebarAdaptable)` und den Tabs **Heute · Strecken · Programme · Verlauf**, die Einstellungen als Zahnrad in der Toolbar oder als letzter Tab. Strecke und Programm sind dann zwei gleichrangige Einstiege, die sich auf der Detailseite treffen. HIG: *Tab bars*, *Sidebars*.
- **Mittel – „Geräte“ als Tab [23].** Ein Tab soll ein Ort sein, an den man zurückkehrt, kein Kopplungsdialog. Empfehlung: Die Statuspille „PM5 nicht verbunden“ [01] als `Button` gestalten, der ein Sheet mit Detents öffnet (`.presentationDetents([.medium, .large])`). Den Tab entfernen.
- **Mittel – Primäraktion unter dem Falz [06].** Auf der Streckenseite liegen „Frei rudern“ und „Mit Training“ erst unter Bild, Text und Tempo-Linie. Empfehlung: `safeAreaInset(edge: .bottom)` mit beiden Tasten oder `ToolbarItem(placement: .primaryAction)`.
- **Niedrig – Schliessen in Sheets [02, 03, 04].** „Schliessen“ als Text links oben ist korrekt. Unter iOS 26 ist jedoch `Button(role: .close)` in `.cancellationAction` üblich (Glas-Taste mit xmark, aus Wissen). „Fertig“ rechts oben in der Zusammenfassung [18] ist richtig (`.confirmationAction`).

### Visuelle Konsistenz
- **Hoch – Fehler hell/dunkel in der Zusammenfassung [04, 22].** `SummaryView` malt `Theme.background` (fast schwarz), nutzt aber `.primary` und `.secondary`. In einer hellen Umgebung (Sheet vom Start, Push aus dem Verlauf) ist die Schrift deshalb schwarz auf schwarz, und die untere `.bar` ist hellgrau. Empfehlung: das Farbschema eindeutig setzen, siehe nächster Punkt.
- **Hoch – Wechsel des Farbschemas im selben Stapel [01–07 dunkel, 08–14 hell, 21/23–28 hell, 18–20 dunkel].** Start und Streckenseite erzwingen `.environment(\.colorScheme, .dark)`, die Programmliste und die Streckenwahl erben aber das Systemschema. Empfehlung: Entweder die App bekennt sich zu dunkel (`.preferredColorScheme(.dark)` an `RootView`, sinnvoll fürs Rudern im abgedunkelten Raum), oder alle eigenen Farben werden zu Asset-Farben mit hellen und dunklen Varianten. Mischformen vermeiden. HIG: *Dark Mode*, *Color*.
- **Mittel – Akzentfarbe [14, 18, 22, 24].** „Strecke wählen“ und „Speichern“ sind systemblau, „Los“ ist orange, die Tab-Auswahl ist blau. Empfehlung: `AccentColor` im Asset-Katalog auf Abendorange (bzw. eine kontraststarke Variante) setzen. Dann folgen `.borderedProminent`, Toggles, Links und die Tab-Leiste automatisch.
- **Mittel – Rasterausrichtung [05, 08, 11, 12, 18].** Die Karten in `LazyVGrid` stehen versetzt (mittlere Spalte höher oder tiefer, Ø-Puls-Kachel tiefer). Empfehlung: `.frame(maxHeight: .infinity, alignment: .top)` in den Karten oder `Grid` mit `alignment: .top`.
- **Mittel – Eigener App-Kopf mit Icon und Name [01, 35].** Apple-Apps zeigen ihr Icon nicht in der eigenen Oberfläche. Empfehlung: Kopf weglassen oder einen grossen Navigationstitel („Heute“) verwenden.
- **Niedrig – Materialien.** Karten nutzen `.thinMaterial`, eigene Farbtöne und Strichkonturen nebeneinander. Liquid Glass gehört in die Steuerungsebene (Tab-Leiste, Toolbar, schwebende Tasten), nicht auf Inhaltskarten. Die HUD-Kacheln auf dem Wasser sollten ein dunkler, ruhiger Hintergrund bleiben, damit sie lesbar sind (kein `glassEffect` auf Zahlen). HIG: *Materials*.
- **Niedrig – Leeres Bild in der Willkommenskarte [35].** Links bleibt ein dunkler Streifen, weil das Luftbild die Karte nicht füllt (`.scaledToFill()` plus `.clipped()`).

### Bedienelemente
- **Hoch – Stepper für grosse Wertebereiche [24].** Die 2000-m-Bestzeit lässt sich von 5:30 bis 12:00 nur in 1-s-Schritten einstellen, das sind bis zu 390 Tipps. Beim Maximalpuls sind es 100 Schritte. Empfehlung: einen `Picker` mit `.wheel`-Stil für Minuten und Sekunden bzw. `TextField(value:format:)` mit `.keyboardType(.numberPad)`, dazu `LabeledContent("Maximalpuls") { Text("185 /min") }`. HIG: *Steppers* (nur für kleine Änderungen), *Pickers*.
- **Mittel – Vier Bedienelemente für ein Tempo [12].** „−5 s“, Stepper (−/+) und „+5 s“ stehen nebeneinander. Empfehlung: ein Stepper mit 1 s und zusätzlich langes Drücken, oder ein `Picker`/Menü mit gängigen Tempi.
- **Mittel – Filter als eigene Chips [08–10, 13].** Empfehlung: das Niveau als `Picker(.segmented)` (drei Werte), die Art als horizontale Chip-Reihe in `ScrollView(.horizontal)`. Im Sortiermenü [10] „Filter zurücksetzen“ nicht unter die Sortierung mischen, sondern als eigene Taste oder als eigenes Filtermenü (`line.3.horizontal.decrease.circle`).
- **Mittel – Entwicklerbereich in den Einstellungen [25–28].** Simulator, „PM5 neu starten“ und Diagnose gehören hinter `#if DEBUG` oder einen versteckten Schalter. „PM5 neu starten (Distanz auf 0)“ ist ein blauer Link ohne Bestätigung. Empfehlung: `role: .destructive` plus `confirmationDialog`.
- **Niedrig – Mikrotexte.** „Werte stimmen“ [24] besser als „Werte bestätigen“. Der Abschnitt „Verbunden“ zeigt „nicht verbunden“ [23], besser „Meine Geräte“. „Suchen“ ist grau ohne Grund [23]; ist Bluetooth nicht bereit, das sagen.

### Ruderbildschirm als Immersive-Ansicht
- **Gut:** `statusBarHidden`, `persistentSystemOverlays(.hidden)`, Idle-Timer aus, `fullScreenCover`, grosse Zahlen, ein grosses ✕ mit Bestätigung [15, 16].
- **Hoch – Ansagen statt Haptik.** Das iPad hat keine Taptic Engine. Haptik bringt deshalb nur auf dem iPhone etwas (`.sensoryFeedback(.impact(weight: .heavy), trigger: planStatus?.phaseIndex)`). Auf 1–1,5 m Abstand tragen Ton und Sprache: zum Phasenwechsel `AVSpeechSynthesizer` („Noch 10 Sekunden. Dann 4 Minuten im 2k-Tempo“), `AVAudioSession` mit `.playback` und `.duckOthers`, damit die Musik leiser wird statt abzubrechen. Zurzeit gibt es nur einen `AudioServicesPlaySystemSound`, der vom Stummschalter abhängt. HIG: *Playing audio*, *Playing haptics*.
- **Mittel – Bestätigungsdialog ohne sichtbares „Weiterrudern“ [16].** Auf dem iPad lässt der `confirmationDialog` die Taste mit der Rolle Abbrechen weg. Wer verschwitzt aus 1,5 m tippt, braucht drei grosse, klare Ziele. Empfehlung: `.alert` mit drei Tasten oder eine eigene Vollbild-Pause mit grossen Tasten. Zusätzlich `.defersSystemGestures(on: .all)`, damit Wischer am Rand nicht das Kontrollzentrum öffnen.
- **Mittel – Lesbarkeit der Trainingskarte [31–34].** Die Zeile „Als Nächstes …“ und die Zielwerte sind etwa 18 pt gross, aus 1,5 m knapp. Die Beschriftung der Phasenleiste überdeckt die Balken [31]. Ein Phasenwechsel ist in den Bildern 32–34 nicht als grosser Moment zu sehen. Empfehlung: Zielwerte etwa 28 pt, beim Wechsel einen Vollbreiten-Callout für 3 s (der Code hat einen `trainingCallout`; prüfen, dass er gross genug ist und auffällt).
- **Niedrig – „Simulator“-Plakette [15].** Grelles Magenta zieht den Blick an. Lieber dezent oder nur im Debug-Build.

### Bedienbarkeit für alle
- **Hoch – Information nur über Farbe [31–34, 18].** Die Ampelpunkte (grün, gelb, rot) bei Schlagzahl, Tempo und Zone sagen „im Ziel“ oder „daneben“ nur über Farbe. Empfehlung: SF Symbols mit Form (`checkmark.circle.fill`, `arrow.up.circle.fill`, `arrow.down.circle.fill`), zumindest bei `@Environment(\.accessibilityDifferentiateWithoutColor)`.
- **Mittel – Kontrast auf Luftbild und Wasser.** Der Puls in Zonenfarbe (Blau auf blauem Wasser hinter halbtransparentem Panel) und „125“ in Grau-Blau [31] liegen vermutlich unter 4,5:1. Die Kicker „VORSCHLAG FÜR HEUTE“ liegen über einem unruhigen Luftbild [01]. Empfehlung: das Panel deckender machen, die Zonenfarbe nur als Balken oder Rand zeigen und die Zahl weiss lassen, unter Text einen Verlauf als Scrim legen.
- **Mittel – Dynamic Type.** Start, Streckenseite, Wochen- und Vorschlagskarten verwenden durchgehend `.font(.system(size:))` und skalieren deshalb nicht. Empfehlung: Textstile (`.title`, `.body`) bzw. `@ScaledMetric`, begrenzt mit `.dynamicTypeSize(...DynamicTypeSize.accessibility2)`. Im HUD sind feste Grössen vertretbar; besser ist eine eigene Einstellung „HUD-Grösse“.
- **Mittel – Reduce Motion.** `accessibilityReduceMotion` wird nirgends ausgewertet. Bei aktivem Reduce Motion sollten Kameraschwanken, Wellen und Übergänge zurückgenommen werden.
- **Gut:** Viele `accessibilityLabel`, `accessibilityElement(children: .combine)` und Hinweise sind vorhanden. Ergänzen: Ansagen beim Phasenwechsel über `AccessibilityNotification.Announcement`.

### Lokalisierung und Formate
- **Hoch – Kein String Catalog.** Alle Texte sind fest auf Deutsch, der Inhalt der Strecken ist schon zweisprachig. Das ergibt Mischzeilen wie „voraus auf der Hinfahrt · through the main span“ [07]. Empfehlung: `Localizable.xcstrings` mit Plural-Varianten („1 Woche mit 3 Fahrten“, „0 von 3 Fahrten“).
- **Hoch – Zahlen und Daten von Hand formatiert.** `String(format: "%.1f")` erzeugt „14.4 km/h“ [15], an anderer Stelle wird „.“ durch „,“ ersetzt („1,6 km“ [06]). Datumsangaben erscheinen als „Monday, 23 November 2026 at 21:12“ [19], „Nov 23, 2026 at 21:12“ [21] und „14. Nov., 07:40“ [07]. Empfehlung: `Measurement(value:unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))`, `UnitSpeed.kilometersPerHour`, `Duration.formatted(.time(pattern: .minuteSecond))`, `Date.formatted(.dateTime.day().month().hour().minute())` bzw. `.relative(presentation: .named)`, und überall `FormatStyle` statt `DateFormatter`. Die Zehntel beim Tempo („2:05.0“) folgen der Concept2-Konvention und sind vertretbar, sollten aber einheitlich sein.
- **Niedrig – Abkürzungen.** „SPM“ [20], „2k+3 s“ [13, 14] und „Z1“/„<1“ [20] sollten ausgeschrieben oder mit Legende versehen werden.

### Leer-, Lade- und Fehlerzustände
- **Gut:** Der Willkommens-Vorschlag ohne Fahrten [35] und `ContentUnavailableView` in Verlauf und Programmliste.
- **Mittel – Geräte leer [23].** „Gefunden“ bleibt leer, ohne Suchanzeige. Empfehlung: `ContentUnavailableView("Keine Geräte gefunden", systemImage: "antenna.radiowaves.left.and.right", description: …)` mit „Suchen“-Taste, beim Suchen ein `ProgressView` im Abschnittskopf, die Signalstärke als `Image(systemName: "cellularbars", variableValue:)` statt dBm.
- **Mittel – Rauschen im Verlauf [21].** Viele Einträge mit „1 m · 0:00“, und die Zeichen (Bildschirm, Flagge, Blitz) bleiben ohne Erklärung. Empfehlung: Fahrten unter etwa 30 s gar nicht speichern oder in der Liste ausblenden, die Zeichen als `Label` mit Text bzw. mit Legende.
- **Niedrig – Warnung bei Beispielfahrten [04, 19].** „Nicht in Apple Health gespeichert“ erscheint orange auch bei Simulator- und Beispielfahrten, für die das gewollt ist. Dort neutral formulieren.

### iPad-spezifisch und iPhone
- **Mittel – Querformat ohne Scrollen hält nicht [01].** Die Karte „Letzte Fahrt“ ist unten abgeschnitten („Bestzeit 13 s schneller“). Empfehlung: `ViewThatFits` oder kompaktere Inhalte bei geringer Höhe.
- **Mittel – Fenster und Stage Manager.** Das Layout richtet sich nach `GeometryReader`-Breiten (900/700 pt). Das funktioniert, ist aber spröde. Empfehlung: `horizontalSizeClass` plus `ViewThatFits`, und den Ruderbildschirm im 1/3- und 1/2-Split prüfen (`compactHUD`).
- **Niedrig – Tastatur und Pointer.** `.keyboardShortcut(.defaultAction)` auf „Los“, Esc schliesst Sheets, `.hoverEffect(.highlight)` auf Karten. Für die Tasten auf dem Rudergerät kaum wichtig, für den Schreibtisch aber billig zu haben.
- **iPhone (nicht in den Bildern):** Der Vorschau-Sheet mit `.medium`-Detent, die Tab-Leiste unten. Der Tab-Name „Einstellungen“ ist lang. Das Badge am Einstellungen-Tab doppelt den Banner „Profil prüfen“ [01]; eins von beiden genügt.

## 3. Feinschliff

- Beim Start einen Übergang vom Vorschlag in die 3D-Szene (`matchedTransitionSource` + `.navigationTransition(.zoom)` bzw. Zoom ins Luftbild), statt dass der `fullScreenCover` hart erscheint.
- Countdown 3-2-1 mit Ton, auf dem iPhone mit `.sensoryFeedback(.impact)`, und mit `.contentTransition(.numericText(countsDown: true))` für die Ziffern.
- Phasenwechsel: Farbwechsel des Panels mit `.animation(.smooth)`, eine kurze Ansage und auf dem iPhone `.sensoryFeedback(.success)` am Ende einer Belastung.
- Neue Bestzeit in der Zusammenfassung: `star.fill` mit `.symbolEffect(.bounce)` und Ansage „Neue Bestzeit“.
- SF Symbols einheitlich: Pulsgurt `heart.fill` in Rot [23], Tempo `gauge.with.needle`, Schlagzahl `metronome`, Strecke `point.topleft.down.to.point.bottomright.curvepath`. Für Programme passt `chart.bar.xaxis` nicht so gut wie `figure.rower` mit Badge.
- Ziffern in allen Listen als `.monospacedDigit()` (im Verlauf rechtsbündig [21]).
- Die Zusammenfassung beginnt mit der Kernaussage („4001 m in 18:51, 13 s schneller als zuletzt“), die Kacheln folgen darunter.
- „Verwerfen“ im Verlauf als Wischen mit Rückgängig (`UndoManager` von SwiftData) statt sofortiger Löschung.

## 4. Top 10 der Empfehlungen (nach Wirkung)

1. **Ein Farbschema für die ganze App** (`.preferredColorScheme(.dark)` an der Wurzel oder vollständig adaptive Asset-Farben). Damit verschwinden der Bruch zwischen hell und dunkel [07→08] und die unlesbare Zusammenfassung [04, 22].
2. **Ansagen für Phasenwechsel und Countdown** über `AVSpeechSynthesizer` mit `.duckOthers`, auf dem iPhone zusätzlich `.sensoryFeedback`. Das ist der grösste Gewinn bei 1,5 m Blickabstand.
3. **String Catalog und `FormatStyle`/`Measurement`** für alle Texte, Zahlen, Daten und Einheiten. Das beendet den Sprach- und Formatmix [07, 15, 19, 21].
4. **Flachere Navigation:** `sidebarAdaptable`-Tabs „Heute · Strecken · Programme · Verlauf“, Geräte als Sheet hinter der Statuspille, Einstellungen über die Toolbar.
5. **Eine Akzentfarbe (`AccentColor`)** statt Blau aus dem System neben Orange.
6. **Ampelpunkte mit Form** (SF Symbols) statt nur Farbe, die Pulszahl weiss auf deckendem Panel.
7. **Profilwerte mit Picker oder Zahlenfeld** statt Stepper über Hunderte Schritte, Tempo-Linie mit einem einzigen Bedienelement.
8. **Dynamic Type** auf Start, Strecken- und Programmseiten (Textstile bzw. `@ScaledMetric`), Reduce Motion in der 3D-Szene beachten.
9. **Primäraktionen immer sichtbar** (`safeAreaInset` auf der Streckenseite [06]) und Querformat ohne Abschneiden [01], Raster oben ausgerichtet [05, 08, 18].
10. **Aufräumen für den Release:** Entwicklerbereich hinter `#if DEBUG`, Leer-Zustand und Suchanzeige bei Geräten, Kurzfahrten nicht speichern, eigener App-Kopf weg.
