# UX-Überarbeitung: Zusammenführung beider Prüfungen (23.11.2026)

Grundlage: `ux-review-rowing.md` (Ruder- und Effizienzsicht) und `ux-review-apple.md` (HIG-Sicht), beide unabhängig erstellt anhand der Klicktour `tools/coursebuilder/build/sim-screens/tour-9744c6c/`.

## Einig in beiden Prüfungen
1. **Ein Farbschema:** durchgehend dunkel, gestaltet über Farbtokens. Eine Akzentfarbe (Abendorange) nur für die Hauptaktion. Ein einziger Satz Zonenfarben.
2. **Blocker beheben:**
   - Fahrtdetail unlesbar: schwarze Schrift auf dunklem Grund.
   - Dialog „Fahrt beenden“: „Weiterrudern“ fehlt auf dem iPad, die Fahrt läuft weiter. „Fertig“ liegt an der Stelle von ✕.
3. **Sprache und Formate:** String Catalog de/en, Zahlen, Daten und Einheiten über die Systemformate.
4. **Hauptaktion immer sichtbar:** Die Streckenseite hat rechts eine feste Aktionsspalte, „Letzte Fahrt“ wird nicht abgeschnitten.
5. **Profil:** Werte per Zahlenfeld bzw. Auswahlrad statt Stepper. Erster Start mit „PM5 verbinden“ vor „Los“.
6. **Aufräumen:**
   - Kurzfahrten unter 100 m bzw. 1 min nicht speichern
   - Simulatorfahrten aus dem Verlauf
   - Entwicklerbereich nur in Debug-Builds
   - Geräte mit Such- und Leer-Zustand
   - Quellen vollständig (swisstopo, OSM, Copernicus)

## Ergänzungen der Rudersicht
- **HUD nach Ruderlogik:**
  - Tempo /500 m als grösste Zahl.
  - Im Intervall die Restzeit der Phase gleich gross.
  - Zieltempo und Ampel direkt in den Kacheln Tempo und Schlagzahl.
  - km/h und doppelte Anzeigen fallen weg.
- **Zusammenfassung:** Splits je 500 m und eine Zeile je Intervall mit Ampel gegenüber dem Ziel.
- **Begriffe:**
  - „Intervall/Pause“ für Phasen, „Anstrengung“ (wie in Apple Health) für die Abfrage nach der Fahrt.
  - Keine Anglizismen wie 2k, Pace, SPM.
- **Phasenleiste nach Härte gefärbt**, nicht nur nach Struktur.
- Niveau der Programme prüfen (Zeit-Pyramide).
- Tempo-Linie mit Abstand als Zahl.

## Ergänzungen der HIG-Sicht
- **Flachere Navigation:**
  - Tabs „Heute · Strecken · Programme · Verlauf“, auf dem iPad als Seitenleiste umschaltbar.
  - Geräte als Sheet hinter der Statusanzeige, Einstellungen in der Toolbar.
- **Gesprochene Ansagen** bei Phasenwechsel und Countdown (Musik wird leiser), auf dem iPhone zusätzlich Haptik.
- Systemschriftgrösse auf den Lesebildschirmen, „Bewegung reduzieren“ in der Szene beachten.
- Ampel zusätzlich mit Symbolen, nicht nur über Farbe.

## Weniger Tipps bis zum Rudern (Vorschlag)
| Weg | heute | neu |
|---|---|---|
| Vorschlag | 1 | 1 |
| Frei auf anderer Strecke | 3 | 2 |
| Frei mit Tempo-Linie | 5–8 | 3 |
| Bestimmtes Training | 5–7 | 3 |
| Erster Start | 10–40 | 5 |
