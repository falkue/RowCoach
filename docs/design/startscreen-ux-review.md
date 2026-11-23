# Startbildschirm – UX-Review und ruhigere Fassung (Variante C, 23.11.2026)

Grundlage: Bildschirmfotos `tools/coursebuilder/build/sim-screens/6963b54_*` und `f0ea3c8_*`, Konzept `startscreen.md`. Entwurf: `design/startscreen/variante-c-ipad.png` und `variante-c-iphone.png`, erzeugt mit `build_mockups.py c`.

## Befund

Der Bildschirm zeigt das Konzept vollständig, aber alles gleichzeitig. Aus 1–1,5 m Abstand wirkt er wie ein Dashboard, nicht wie eine Startrampe.

1. **Zu viele Bausteine.** iPad quer, ohne Scrollen: 14 abgegrenzte Elemente, davon 6 Kästen oder Chips im Vorschlag. Gescrollt sind es über 20. Darunter: Phasenleiste, 3 Zielwerte, Profil-Link, Begründungskasten, 2 Tasten, 2 Alternativ-Chips, Hinweissatz, Wochenpunkte, Wochensatz, Serienkasten, Leicht/hart-Balken mit Legende, Letzte Fahrt mit 4 Messwerten, 5 Strecken-Kacheln.
2. **Rund 40 Zahlen ohne Handlungsbezug.** Vor dem Rudern braucht man keine Werte wie „76 % / 8 % / 16 %“, „2 von 10 Einheiten hart“, „Ø 70 min der 4 Wochen davor“, „KW 48“, „137 Ø Puls“ oder je zwei Zahlen auf 5 Kacheln. Sie entscheiden nichts. Die Zielwerte (Tempo, Schlagzahl, Zone) braucht man erst beim Rudern, und dort zeigt sie die Fahranzeige ohnehin.
3. **Vier Überschriften konkurrieren.** „Zeit-Pyramide 1-2-3-4-3-2-1“ (zwei Zeilen à 50 pt), „Diese Woche“, „Neue Woche“ (46 pt) und die Zielwerte (40 pt) sind fast gleich gross. Das Auge findet keinen Einstieg. Orange steht an vier Stellen: Kicker, Phasenleiste, Begründungsstrich und Taste.
4. **Dopplungen.** Das Programm steht im Titel und noch einmal in der Begründung („… heute Zeit-Pyramide 1-2-3-4-3-2-1“). Die Woche wird dreimal beschrieben: Punkte, „Neue Woche / Letzte Woche“ und Serienkasten. Die letzte Fahrt erscheint als Karte und als Kachel „Utoquai · Zuletzt“, der Vorschlag noch einmal als Kachel „Heute“. „Frei rudern“ gibt es als Chip und hinter „Anders wählen“.
5. **Lesbarkeit über dem Luftbild.** Route und Zielwerte überlagern sich („22–28 /min“ liegt auf dem Startpunkt). Der Begründungskasten liegt halb auf der Karte, und der Untertitel bricht um („· Intervalle“ allein in Zeile 2). Text unter 17 pt (Hinweissatz, Legende) ist aus 1,5 m kaum lesbar.

## Vorschlag (Variante C „Ruhig“)

**Regel:** eine Hauptaktion und zwei ruhige Nebeninfos. Orange gibt es nur beim Kicker und bei der Taste „Los“. Jede Nebenkarte hat höchstens 3 Zahlen und 12 Wörter, die Vorschlagskarte höchstens 2 Zahlen im Text.

| Ebene | Inhalt |
|---|---|
| **Bleibt – Vorschlag** (ca. 65 % der Fläche) | Kicker „Vorschlag für heute“ (16 pt). Programm einzeilig, 60 pt („Zeit-Pyramide“; das Schema 1-2-3-4-3-2-1 zeigt die Phasenleiste). Strecke · Dauer (24 pt). Phasenleiste ohne Beschriftung. Begründung in einem Satz, 19 pt, ohne Kasten. **Los** (88 pt hoch, 280 pt breit) und daneben „Anders wählen“ als ruhige Glastaste. Auf dem Luftbild bei neuer Strecke ein Hinweis „Neu für deinen Seen-Pass“. |
| **Bleibt – Diese Woche** | Punkte Mo–So, darunter ein Satz in 30 pt: „1 von 3 Fahrten“. Serie klein mit Stern („7 Wochen in Folge“), nur ab 2 Wochen. Ein Tipp öffnet die Wochenansicht. |
| **Bleibt – Letzte Fahrt** | Luftbild der Strecke, „Gestern · Utoquai“, ein Satz „4000 m in 18:51“. Bestzeit-Zeile nur, wenn sie positiv ist. Ein Tipp öffnet die Fahrt im Verlauf. |
| **Eine Ebene tiefer** | Zielwerte Tempo, Schlagzahl, Zone und die Phasen im Detail: Tippen auf die Karte (Vorschau) und in der Fahranzeige. Alternativen, „Frei rudern“ und **Seen-Pass** als ganze Sammlung: hinter „Anders wählen“ (gibt es schon). Leicht/hart (28 Tage), Vergleich mit dem Schnitt der Vorwochen, Joker: Wochenansicht im Verlauf. Messwerte Tempo und Ø Puls der letzten Fahrt: Verlauf. |
| **Fällt weg** | Satz „Vorschlag aus deinen letzten Fahrten …“ (einmalig im Onboarding oder hinter einem ⓘ). Profil-Link als Dauerzeile (stattdessen ein Punkt am Tab „Einstellungen“ und einmalig ein Banner). „KW 48“. Doppelte Kacheln „Heute“ und „Zuletzt“. |

**Masse iPad (pt):** Ränder 32, Abstand zwischen Karten 16–24, Innenabstand der Karten mindestens 30. Schriften: Titel 60, Satzzahl 30, Text 19–24, kleinste Schrift 14 (nur Kicker, gesperrt). Mindestens 40 % jeder Nebenkarte bleiben leer. Tastfläche „Los“ mindestens 88 × 280, damit sie auch mit verschwitzten Fingern sicher trifft.

**Kern der Fachbeiträge, erhalten:**
- Sport: Vorschlag mit Begründung, Woche als Häufigkeit, letzte Fahrt.
- Gamification: wohlwollende Serie ohne Verlustsprache, Landschaft als Bühne. Der Seen-Pass wird erlebbar, sobald der Vorschlag eine neue Strecke bringt, und die ganze Sammlung liegt einen Tipp entfernt.

**Varianten:**
- **iPad quer:** Vorschlag links (760 pt), rechts übereinander Woche und letzte Fahrt; nichts muss gescrollt werden.
- **iPad hoch:** Vorschlag oben über die volle Breite (ca. 55 % der Höhe), darunter Woche und letzte Fahrt nebeneinander in zwei gleich grossen Karten.
- **iPhone hoch:** Vorschlag mit Los über dem Daumenbereich, darunter die Woche als Punktreihe mit „1 von 3“ und die letzte Fahrt als eine Zeile; alles über der Tab-Leiste ohne Scrollen.
