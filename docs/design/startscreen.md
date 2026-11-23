# Startbildschirm – Synthese (Entwurf 23.11.2026)

Grundlage sind `startscreen-gamification.md` und `startscreen-sport.md`. Die Bilder liegen in `design/startscreen/`: Variante A „Heute-Karte“ und Variante B „Landschaft als Bühne“, jeweils für iPad und iPhone. Erzeugt werden sie mit `build_mockups.py`. Die Beispieldaten sind fiktiv, ausser Falks echter Fahrt vom 23.11.2026. „Heute“ ist in den Bildern Dienstag, der 24.11.

## 1. Aufbau

Der Startbildschirm ist eine Startrampe, kein Dashboard. Er hat einen Kopf und drei Informationsblöcke, wichtigster Block zuerst:

| | Element | Inhalt |
|---|---|---|
| Kopf | Logo, Tabs, Geräte | Logo dezent oben links. Gerätestatus als zwei ruhige Chips („PM5 bereit“, Puls). Eine Störung oder eine unterbrochene Fahrt erscheint als einzeilige Leiste unter dem Kopf, nur dann. |
| 1 | **Vorschlag für heute** | Luftbild der Strecke mit eingezeichneter Route. Darauf: Programm, Strecke, Dauer, Phasenleiste und drei Zielwerte (Tempo /500 m, Schlagzahl, Pulszone). Dazu die Begründung in einer Zeile, die Tasten **Los** und **Anders wählen**, zwei Alternativen und „Frei rudern“. |
| 2 | **Diese Woche** | Tagespunkte Mo–So in den Farben leicht/mittel/hart. Summe in Minuten (km klein daneben) und Schnitt der 4 Wochen davor. Wochenserie. Balken „leicht und hart, 28 Tage“. |
| 3 | **Letzte Fahrt** (A) bzw. **Deine Strecken** (B) | A: Datum, Strecke, Distanz, Zeit, Tempo, Ø Puls, Bestzeit-Hinweis nur wenn positiv. B: Seen-Pass mit fünf Strecken-Karten (Fahrten, km, Bestzeit, „noch offen“). Die letzte Fahrt steht dort als Zeile im Wochenblock. |

**Hierarchie:** Block 1 nimmt etwa 60 % der Fläche ein und hat als einziger Farbe (orange Taste). Die Blöcke 2 und 3 sind dunkle, ruhige Karten. Die kleinste Schrift auf dem iPad hat 13 pt, Zahlen und Titel 30–50 pt. So bleibt alles aus 1–1,5 m lesbar.

**Bewusst weggelassen:**
- Kalorien
- Readiness- und Fitness-Scores, Acute:Chronic-Ampel
- Tagesserien, rote Zahlen, Abwärtspfeile
- Punkte und Level, gesperrte Strecken
- 12-Wochen-Band, TRIMP und 2000-m-Verlauf (gehören in den Verlauf)
- Meilensteine (kommen ruhig in der Zusammenfassung nach der Fahrt)
- Geisterboot (wird als Option erst in der Streckenauswahl angeboten)
- Simulatorfahrten in jeder Zahl

**Später mit Rennen:** Erst wenn ein RowServer abonniert ist, erscheint in Block 1 oben eine Zeile „Nächstes Rennen: Sa 18:00 · Utoquai · angemeldet“. Am Renntag ersetzt das Rennen den Vorschlag. Bis dahin ist dafür kein Platz reserviert. Wetter- und Saisonvarianten erscheinen als Bildvariante der Karte, nicht als eigener Block.

## 2. Regeln für den „Vorschlag für heute“

Es gilt die erste Zeile, die zutrifft. Eingaben sind nur die eigenen PM5-Fahrten. Jede Einheit wird als Ganzes eingestuft: über `category`, sonst über die Zeit in Pulszonen, sonst über das Tempo.

0. Weniger als 3 Fahrten oder mehr als 7 Tage Pause → Lockere Grundlage 30 („Locker einsteigen“).
1. Harte oder mittlere Einheit vor weniger als 48 h → Technik 25 (wenn gestern hart), sonst Grundlage 30.
2. Mindestens 2 harte Einheiten in 7 Tagen → Grundlage 3 × 10.
3. Leicht-Anteil unter 75 % (28 Tage, mindestens 6 Fahrten mit Puls) → Grundlage.
4. Letzter 2000-m-Test vor mehr als 8 Wochen, 4 Wochen regelmässig trainiert und die letzten 2 Tage leicht → Test 2000 m.
5. Sonst ist ein harter Reiz fällig → die am längsten nicht gefahrene Einheit aus Schwelle, 4 × 4, 8 × 2 und Pyramide. Sprint höchstens alle 14 Tage.

Weitere Regeln:
- Nach drei gleichen leichten Einheiten wird die Frequenzleiter angeboten.
- Ist der Vorschlag heute schon gerudert, erscheint „Heute erledigt“, und der Vorschlag für morgen steht klein darunter.
- Die Begründung steht immer da, dazu zwei Alternativen und der Hinweis „Vorschlag aus deinen letzten Fahrten. Fühlst du dich anders, wähle frei.“

**Strecke:** Vorgeschlagen wird die am längsten nicht geruderte Strecke, die zur Dauer passt. Im Beispiel ist das Rhein Basel, gerudert vor 4 Wochen.

## 3. Entscheidungen bei Widersprüchen

- **Strecke hinter „Los“:** Gamification will die vorgeschlagene, wechselnde Strecke, Sport die zuletzt genutzte. *Entscheid: wechselnde Strecke.* Die Strecke ist für das Training neutral, die Landschaft ist aber das stärkste Motiv der App.
- **Wochensicht:** Gamification will ein Band über 8–12 Wochen, Sport einen Streifen Mo–So mit dem Schnitt von 4 Wochen. *Entscheid: Mo–So.* Für die Steuerung zählt die Verteilung leicht/hart je Tag; die lange Reihe ist Auswertung und gehört in den Verlauf.
- **Ziel und Serie:** Gamification schlägt „3 Fahrten, 1 Joker“ vor, Sport „Wochen in Folge mit ≥ 3 Einheiten“. *Entscheid: beides zusammen* als Wochenserie mit Joker, Ziel einstellbar (Standard 3). Ein Joker verhindert, dass eine einzige verpasste Woche die Serie bricht.
- **Minuten oder Meter:** *Minuten führen.* Ein Sprinttag hat wenig Meter und ist trotzdem hart.
- **Strecken-Sammlung:** Bei Gamification ein „Soll“, bei Sport „später“. *Entscheid: in A nicht auf dem Start* (erreichbar über „Anders wählen“), *in B als Bühne.* Welche Gewichtung richtig ist, entscheidet die Wahl der Variante.
- **Tempo der letzten Fahrt:** Gilt aus dem Sport-Dokument. Bei Intervallen wird das Tempo der Belastungsphasen gezeigt, nicht der Schnitt mit Pausen.

## 4. Leere Zustände

- **Neuer Nutzer ohne Verlauf:**
  - Block 1 zeigt „Willkommen. Erste Fahrt: Lockere Grundlage 30 min“ auf dem Utoquai-Luftbild, mit **Los** und „Frei rudern“. Die Zielwerte sind nur Schlagzahl und Zone, ohne Tempo.
  - Block 2 zeigt sieben leere Tagespunkte und den Satz „Hier siehst du deine Woche, sobald du gerudert hast.“
  - Block 3 (A) zeigt „Noch keine Fahrt“. In B sind alle Strecken „noch offen“, ohne Zähler.
  - Der Balken leicht/hart erscheint erst ab 6 Fahrten mit Puls, vorher steht dort „noch zu wenig Daten“.
- **Profil nicht gesetzt** (Maximalpuls, Ruhepuls oder 2000-m-Bestzeit noch auf Voreinstellung):
  - In Block 1 steht unter den Zielwerten eine Zeile „Zonen und Tempo geschätzt – Profil setzen“, die direkt zum Profil führt.
  - Die Tempowerte stehen mit „ca.“ da.
  - Die Zeile verschwindet, sobald die Werte gesetzt sind.

## 5. iPhone (Hochformat)

Alles steht in einer Spalte: zuerst die Vorschlagskarte (Luftbild oben, Text und Los-Taste unten), darunter die Woche als kompakte Punktreihe, dann die letzte Fahrt als Zeile (A) bzw. zwei Strecken-Karten mit „Alle 5“ (B). Die Tabs wandern als Leiste nach unten. Phasenleiste und Begründung werden kürzer, die Taste **Los** bleibt immer ohne Scrollen sichtbar.

## Empfehlung

**Variante A als Grundlage, mit der Bildsprache von B.** A beantwortet in einem Blick „was heute?“, „wie läuft die Woche?“ und „was war zuletzt?“ und erfüllt damit die Muss-Elemente beider Fachleute. B wirkt emotionaler, stellt aber die Sammlung über die Steuerung, und auf dem Vollbild ist die Schrift über dem Luftbild schwerer zu lesen. Aus B übernehmen: Titel mit Ort („Pyramide am Rheinknie“) und den Seen-Pass als Ansicht hinter „Anders wählen“.
