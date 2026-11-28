# Schwellenprofil, Schwellentests und Trainingszonen: Spezifikation (Stand 27.11.2026)

Grundlage: `docs/schwelle/RECHERCHE.md` (Belege, Belegstärke). Diese Datei ist der Bauauftrag. Sie ändert keine
bestehende Logik stillschweigend: Alles, was heute auf der 2000-m-Bestzeit beruht, läuft weiter und bekommt seinen
2k-Bezug künftig aus dem Schwellenprofil.

## 0. Entscheidungen auf einen Blick

| Thema | Entscheidung |
|---|---|
| Referenzgrösse | **Schwellenleistung T in Watt** („Schwelle“): Leistung, die man im Test etwa 30 min halten kann (entspricht der FTP-Konvention 0,95 × 20-min-Leistung). Tempo ist abgeleitet. |
| Watt ↔ Tempo | Concept2: W = 2,80 / (p/500)³, p = 500 · (2,80/W)^(1/3), p in s/500 m |
| Leistung über die Dauer | Potenzgesetz P(t) = P(t₀) · (t/t₀)^(−b), Standard **b = 0,15**, persönlich kalibrierbar (0,08–0,22) |
| Zonen | 5 Leistungszonen in % T (UT3/UT2/UT1/AT/TR-AN); Tempozonen daraus; Pulszonen aus LTHR, sonst Karvonen wie heute |
| Neue Tests | Stufentest submaximal mit Puls (+ DFA-α1, Talk-Test), 20 min, Rampe, 3 min All-out; bestehende Tests werten ebenfalls auf T aus |
| Quellen | Eingabe, Tests, Fahrten-Schätzung, Altwert 2k; Auswahl nach kleinster aktueller Unsicherheit; Eingaben nie still überschreiben |
| Abwärtskompatibilität | `TrainingSettings.best2k` bleibt der 2k-Bezug aller Programme und wird aus T gespiegelt (gleichwertige 2k-Zeit). Neue Phasenfelder `powerPctMin/Max` sind optional; alte App-Versionen ignorieren sie. |
| Plattform | Logik in RowCoachKit (nur Foundation, portabel für Android), Ansichten in der App. Keine Netzwerkfunktion nötig. |

## 1. Datenmodell (RowCoachKit, neuer Ordner `Threshold/`)

```swift
/// Woher eine Schätzung stammt (als Text gespeichert, unbekannte Werte bleiben lesbar)
public enum ThresholdSourceKind: String, Codable, Sendable {
    case manualPower        // Eingabe Watt
    case manualPace         // Eingabe Tempo /500 m an der Schwelle
    case manual2k           // Eingabe 2k-Bestzeit (Profil)
    case legacy2k           // Altwert aus TrainingSettings.best2k bei der Migration
    case timeTrial          // Zeitfahren mit fester Zeit oder Distanz (2000 m, 20/30/60 min, 5000 m …)
    case ramp               // Rampentest
    case allOut3min         // 3-min-All-out (Endleistung ≈ CP)
    case stepHR             // Stufentest: Leistung beim Schwellenpuls
    case stepDFA            // Stufentest: DFA-α1 (experimentell)
    case criticalPowerFit   // CP aus 2–3 maximalen Efforts (Fahrten)
    case ridesAuto          // beste maximale 8–60-min-Leistung aus Fahrten
}

public struct ThresholdEstimate: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: String                 // ThresholdSourceKind.rawValue
    public var date: Date                   // Datum der Messung bzw. Eingabe
    public var powerW: Double               // T in Watt
    public var sigmaPct: Double             // Grundunsicherheit in % (1 Standardabweichung, Tabelle 2.3)
    public var planId: String?              // Testprogramm
    public var workoutId: UUID?             // Fahrt
    public var details: [String: Double]    // Rohwerte: "p20", "map", "ep", "cp", "wPrime", "hrT", "slope", "r2", "b" …
    public var status: String               // "active" | "candidate" | "rejected" | "superseded"
    public var firstOfKind: Bool            // erster Test dieser Art (Lerneffekt, +2 %)
}

public struct HeartProfile: Codable, Equatable, Sendable {
    public var maxHR: Int?                  // gemessen oder eingegeben
    public var maxHRSource: String?         // "manual" | "measured" | "tanaka"
    public var restHR: Int?
    public var lthr: Int?                   // Schwellenpuls
    public var lthrSource: String?          // "manual" | "test30" | "stepDFA"
    public var lthrDate: Date?
    public var birthYear: Int?              // nur für Tanaka-Startwert, optional
}

public struct ThresholdProfile: Codable, Equatable, Sendable {
    public static let formatVersion = 1
    public var estimates: [ThresholdEstimate]   // Verlauf, neueste zuerst; höchstens 100
    public var heart: HeartProfile
    public var exponentB: Double                // Standard 0,15; persönlich kalibriert
    public var exponentBSource: String?         // "default" | "calibrated"
    public var rampFactor: Double               // Standard 0,75; persönlich kalibriert
    public var preferredTest: String?           // plan id, z. B. "schwelle-test-20min"
    public var healthScreen: HealthScreen?      // Antworten Gesundheitsfragen (Abschnitt 9)
}
```

Funktionen (reine Logik, deterministisch, getestet):

- `ThresholdMath`: `watts(pace:)`, `pace(watts:)`, `equivalentPower(_:from:to:b:)`, `thresholdFromEffort(power:duration:b:)`,
  `equivalentBest2k(threshold:b:)`, `threshold(fromBest2k:b:)`.
- `ThresholdEvaluator`: wertet eine Fahrt eines Testprogramms aus → `ThresholdEstimate?` plus Prüfhinweise
  (`[EvaluationNote]`, z. B. „zu schnell gestartet“, „nicht all-out“, „Puls lückenhaft“).
- `ThresholdSelector`: wählt die aktive Schätzung, rechnet die aktuelle Unsicherheit, erzeugt Vorschläge.
- `ThresholdDetector`: Schätzung aus Fahrten (Abschnitt 5).
- `TrainingZones`: Leistungs-, Tempo- und Pulszonen (Abschnitt 4).
- `DFAAlpha1`: α1 aus RR-Intervallen (Abschnitt 2.1, nur Kit, ohne UI-Abhängigkeit).

Speicherung (App): `ThresholdStore` als JSON in UserDefaults (`threshold.profile.v1`), Änderungen veröffentlichen ein
Ereignis, damit Ansichten und `TrainingSettings.best2k` (Spiegel, Abschnitt 8) nachziehen. In die Synchronisation
(docs/SYNC.md) später als eigenes Dokument aufnehmen; nicht Teil dieses Auftrags.

## 2. Formeln

### 2.1 Grundformeln

- Watt aus Tempo: `W = 2.80 / pow(p / 500, 3)`; Tempo aus Watt: `p = 500 * cbrt(2.80 / W)`.
- Gleichwertige Leistung über die Dauer: `P(t2) = P(t1) * pow(t2 / t1, -b)`.
- Schwelle aus maximaler Leistung `P` über die Dauer `t` (Sekunden, gültig 180 s ≤ t ≤ 3600 s):
  `T = P * pow(t / 1800, b)`.
  Faktoren bei b = 0,15: 4 min 0,739 · 10 min 0,848 · 20 min 0,941 · 30 min 1,000 · 42 min 1,052 · 60 min 1,110.
- Schwelle aus 2k-Zeit `t2k` (s): `P2k = W(t2k / 4)`, `T = P2k * pow(t2k / 1800, b)` (6:40 → 0,80; 8:00 → 0,82 × P2k).
- Gleichwertige 2k-Zeit aus T (Fixpunktiteration, konvergiert in < 10 Schritten): start `t = 480`;
  wiederhole `P2k = T * pow(t / 1800, -b)`, `t = 4 * pace(P2k)` bis |Δt| < 0,05 s.
  Beispiel: 2k 8:00,0 → T = 166,1 W (Schwelle 2:08,2/500 m) → zurück 8:00,0. T = 200 W → 2k 7:29,7.
- Tempo für x % der Schwelle: `p(x) = pace(T * x / 100)` = `pace(T) * pow(x/100, -1/3)`.

### 2.2 Umrechnung je Quelle und Grundunsicherheit

| Quelle | Formel für T | σ₀ (1 SD) | Belegstärke |
|---|---|---|---|
| Eingabe Watt | T = Eingabe | 4 % | – |
| Eingabe Tempo | T = W(Tempo) | 4 % | – |
| Eingabe / Altwert 2k | T = P2k · (t2k/1800)^b | 6 % (Altwert = Standard 8:00: 15 %) | abgeleitet |
| Zeitfahren 30 min | T = P30 | 3 % | mittel (Friel; Rudern Praxis) |
| Zeitfahren 20 min | T = P20 · 0,941 | 4 % | mittel (Radsport, Borszcz TEE 4,7 %) |
| Zeitfahren 60 min | T = P60 · 1,110 | 5 % | abgeleitet |
| 2000 m, 5000 m, 6000 m, 10 000 m, 4 min | T = P · (t/1800)^b | 5–6 % (1000 m/4 min: 8 %) | abgeleitet |
| Einsteiger 10 min | T = P10 · 0,848 | 8 % | abgeleitet |
| Rampe | T = rampFactor · MAP (Standard 0,75) | 8 % | schwach (Hersteller, Radsport) |
| 3 min All-out | T = 0,88 · EP | 8 % | mittel (EP ≈ CP; Faktor abgeleitet) |
| CP aus Efforts | T = 0,88 · CP | 6 % | abgeleitet |
| Stufentest Puls | T = Leistung beim Schwellenpuls | 12 % (LTHR bekannt: 9 %) | schwach–mittel |
| Stufentest DFA-α1 | T = P(α1 = 0,5), sonst P(α1 = 0,75) / 0,77 | 12 % | experimentell |
| Fahrten automatisch | wie Zeitfahren, aus Fahrt | 6 % (+2 %, wenn Maximalität nur aus Puls) | schwach |

- P = mittlere Leistung (Watt) der Belastungsphase aus den PM5-Messwerten (`WorkoutSample.power`), zeitgewichtet
  (jeder Wert gilt bis zum nächsten, höchstens 5 s, wie `HeartRateZones.secondsPerZone`).
- `firstOfKind`: erster Test dieser Art für die Person → σ₀ + 2 % (Lerneffekt +2,3 % vom 1. zum 2. 2k-Versuch,
  Schabort 1999).
- Die Faktoren 0,88 (CP/EP → T) und 0,77 (LT1 → T) sind abgeleitet (RECHERCHE 1.2, 3.1) und werden nach den ersten
  echten Daten überprüft (Abschnitt 11).

### 2.3 Persönliche Kalibrierung

- **Exponent b**: Liegen zwei gültige maximale Zeitfahren (Quelle `timeTrial`, nicht Fahrten-Automatik) innerhalb von
  42 Tagen mit Dauerverhältnis ≥ 2,5 vor (z. B. 2000 m und 30 min), dann `b = -ln(P_a/P_b) / ln(t_a/t_b)`, begrenzt auf
  0,08–0,22, `exponentBSource = "calibrated"`. Bei mehreren Paaren das jüngste. Anzeige: „Dein Ausdauerprofil: eher
  Ausdauertyp (b klein) / eher Sprinttyp (b gross)“.
- **Rampenfaktor**: Rampe und ein Zeitfahren 20–60 min innerhalb von 28 Tagen → `rampFactor = T_Zeitfahren / MAP`,
  begrenzt 0,68–0,82.
- Kalibrierung ändert keine alten Schätzungen rückwirkend; sie gilt für neue Umrechnungen und für die gleichwertige
  2k-Zeit.

## 3. Testprogramme

### 3.1 Formaterweiterung von plans.json (abwärtskompatibel)

Alte App-Versionen ignorieren unbekannte Felder (`WorkoutPlan` dekodiert tolerant). Deshalb tragen die neuen Phasen
**zusätzlich** `paceOffsetMinS/MaxS` für den Referenzsplit 2:00 (2k 8:00 → T = 166,1 W), damit sie auch ohne
Schwellenlogik sinnvolle Tempi zeigen.

Neue optionale Felder:

| Ebene | Feld | Bedeutung |
|---|---|---|
| Phase | `powerPctMin`, `powerPctMax` | Ziel in % der Schwelle; hat Vorrang vor `paceOffset*`, wenn ein Schwellenprofil existiert. Tempobereich = `pace(T·max/100)…pace(T·min/100)` |
| Phase | `allOut` (bool) | maximale Belastung: kein Tempoziel als Ampel, Coach im All-out-Modus; Tempo nur als Orientierung |
| Phase | `endOnFailure` (bool) | Rampenphase: Sobald die Person das Ziel nicht mehr hält (3.5), springt der Plan zur nächsten Phase, die nicht `endOnFailure` ist (Ausrudern) |
| Phase | `testRole` | `step`, `timeTrial`, `allOut3min`, `ramp` – sagt dem Auswerter, welche Phasen zählen |
| Programm | `test` | `{kind, requiresHeartRate, usesRR, allOut, evaluator}`; `evaluator` ∈ `stepHR`, `timeTrial`, `ramp`, `allOut3min` |

`WorkoutPhase` bekommt die Felder als Optionals; `paceRange(best2k:)` wird um `paceRange(profile:)` ergänzt
(Abschnitt 8.2). `PlanEngine` braucht für `endOnFailure` einen Eingang „Abbruch erkannt“ (vom `RampFailureDetector`
oder Knopf „Ich kann nicht mehr“), der die restlichen Rampenphasen überspringt.

Bestehende Testprogramme bekommen nur das Feld `test` (Evaluator) nachgetragen:

| id | evaluator | Auswertung |
|---|---|---|
| test-2000m, test-1000m, test-5000m, test-6000m, test-10000m, test-500m* | timeTrial | T aus Zeit über Potenzgesetz (*500 m, 100 m, 1 min: keine Schwelle, nur Bestmarke) |
| test-30min | timeTrial | T = P30 über alle Belastungsphasen (25 + 5 min); LTHR = Puls Minute 10–30 |
| test-60min | timeTrial | T = P60 · 1,110 |
| test-4min | timeTrial | T = P4 · 0,739, σ 8 % |
| einsteiger-test-10min | timeTrial | T = P10 · 0,848, σ 8 % |
| stufentest-5x4, stufentest-7x4 | stepHR | Stufen = Belastungsphasen; bei 7 × 4 zusätzlich Stufe 7 als 4-min-Zeitfahren (T = P4 · 0,739); das genauere Ergebnis wird aktiv, das andere als Vergleich gezeigt |

### 3.2 Schwellentest submaximal (Stufen mit Puls) – `schwelle-stufentest-puls`

- **Ablauf**: 10 min sehr locker einrudern (35–45 % T, ohne Antritte), dann **6 Stufen à 4 min ohne Pause** bei
  50, 60, 70, 80, 88, 95 % der aktuellen Schwelle (± 2 %), 5 min ausrudern. Gesamt 39 min. Schlagzahl 18–24.
  Ohne brauchbare Schwellenschätzung (Altwert = Standard, σ 15 %): Startschwelle T₀ = min(T, 130 W) – lieber zu leicht.
- **Mindestanforderung**: Pulsgurt verbunden (Programm startet sonst nicht, Hinweis). RR-Intervalle (Polar H9/H10)
  optional für DFA-α1. Ruhepuls und Maximalpuls im Profil empfohlen.
- **Vorzeitiges Ende (kein Fehler)**: Puls ≥ Schwellenpuls + 3 über 30 s, oder α1 < 0,5 über 60 s (wenn RR), oder Knopf
  „zu anstrengend“ → Sprung ins Ausrudern; ausgewertet wird mit den fertigen Stufen.
- **Talk-Test**: Am Ende jeder Stufe ab Stufe 2 fragt der Coach „Kannst du noch in ganzen Sätzen sprechen?“; drei
  grosse Knöpfe „leicht / geht so / nein“ (auch per Watch/Taste später). Gespeichert je Stufe.
- **Auswertung (`stepHR`)**:
  1. Je Stufe: HR_s = mittlerer Puls der letzten 60 s (mindestens 45 s gültige Pulswerte), P_s = mittlere gemessene
     Leistung im selben Fenster. Stufen, in denen P_s mehr als 10 % vom Ziel abweicht, zählen trotzdem (es zählt die
     gemessene Leistung).
  2. Gültig sind Stufen mit HR_s ≥ Ruhepuls + 20. Mindestens 3 Stufen, sonst „nicht auswertbar“.
  3. Lineare Regression HR = a + c · P über die gültigen Stufen; Bedingung c > 0 und r² ≥ 0,90, sonst Hinweis
     „Puls unregelmässig“ und σ + 5 %.
  4. Schwellenpuls HR_T: LTHR, wenn vorhanden und ≤ 12 Monate alt; sonst Ruhepuls + 0,85 · (HFmax − Ruhepuls)
     (AT-Band 80–85 % HFR; Wolfson/ISS). HFmax nur aus Tanaka → σ + 3 %.
  5. T_HR = (HR_T − a) / c. Liegt HR_T mehr als 15 Schläge über dem höchsten Stufenpuls → „zu weit hochgerechnet“,
     Ergebnis nur als Hinweis, nicht aktiv; 5–15 Schläge → σ + 3 %.
  6. Talk-Test (Plausibilität): letzte Stufe mit „leicht“ = P_talk (≈ VT1). Erwartet T ≈ P_talk / 0,77 (± 15 %);
     Abweichung grösser → Hinweis „Puls und Gefühl passen nicht zusammen“ (kein Eingriff in T).
  7. **DFA-α1 (wenn RR vorhanden, `stepDFA`)**: RR in s → Artefakte markieren (Abweichung > 20 % vom gleitenden
     Median der 11 umgebenden Schläge), ersetzen durch Interpolation; Fenster 120 s, alle 10 s neu; Fenster mit > 5 %
     Artefakten verwerfen. α1 = Steigung von log F(n) über log n für n = 4…16 Schläge (Standard-DFA, lineare
     Detrendierung je Box). Je Stufe α1 = Median der Fenster in den letzten 2 min. Lineare Regression α1 über P;
     P(0,75) = LT1-Leistung, HR bei α1 0,75 = LT1-Puls; P(0,5), falls erreicht oder ≤ 10 % über der letzten Stufe
     extrapolierbar. T_DFA = P(0,5) bzw. P(0,75) / 0,77. HR bei α1 = 0,5 → LTHR-Vorschlag (σ ± 5 bpm, Quelle `stepDFA`).
     Anzeige als „zweite Meinung (experimentell, am Rudern nicht geprüft)“.
  8. Ergebnis: Liegen T_HR und T_DFA innerhalb ± 10 % → T = Mittel, σ 10 %; sonst T = T_HR, Abweichung anzeigen.
  9. Nebenprodukte: Puls-Leistungs-Gerade (für die Anzeige „bei 150 W ≈ 142 bpm“), LT1-Puls als Obergrenze Zone 2
     (Hinweis, falls deutlich anders als das Zonenmodell).
- **Coach**: Stufenansage 15 s vorher mit Zieltempo; während der Stufe nur „gleichmässig, nicht schneller werden“
  (keine Motivation, kein Anfeuern); Talk-Test-Frage; „Schwelle erreicht, wir hören hier auf – gut gemacht“.

### 3.3 Schwellentest 20 Minuten (FTP) – `schwelle-test-20min`

- **Ablauf**: 10 min einrudern steigernd, 3 min mit 3 Antritten à 20 s, 3 min locker, **20 min Zeitfahren**, 10 min
  ausrudern (46 min). Orientierungstempo 102–110 % T (erwartete 20-min-Leistung = T / 0,941 = 106 %).
- **Auswertung (`timeTrial`)**: P20 = mittlere Leistung der Belastungsphase; T = P20 · 0,941 (Potenzgesetz, b aus
  Profil). Ungültig, wenn die Phase unterbrochen wurde oder mehr als 15 s ohne Schlag. Hinweis „zu schnell gestartet“,
  wenn mittlere Leistung Minute 0–5 > 1,08 × Minute 5–20 (Ergebnis bleibt gültig, σ + 1 %).
- Kein LTHR aus diesem Test (Friels Regel gilt für 30 min); Puls wird als Vergleich gezeigt.
- **Mindestanforderung**: keine (Puls optional). Gesundheitsfragen beantwortet (Abschnitt 9).
- **Coach**: Halbzeit, alle 5 min Stand in Watt/Tempo gegenüber dem Mittel, „zu schnell“ in den ersten 3 min, wenn
  > 110 % T; ab Minute 18 anfeuern (All-out-Budget); Endergebnis mit neuer Schwelle.

### 3.4 Schwellentest 3 Minuten All-out (Critical Power) – `schwelle-test-3min`

- **Ablauf**: 10 min einrudern steigernd, 2 Antritte à 10 s, 5 min ganz locker, **3 min All-out von der ersten
  Sekunde**, 10 min ausrudern (30 min). Kein Tempoziel; Anzeige gross: Watt, Zeit.
- **Auswertung (`allOut3min`)**: EP = mittlere Leistung 150–180 s; T = 0,88 · EP. Prüfung „wirklich all-out“: mittlere
  Leistung 0–30 s ≥ 1,3 × EP **und** 120–150 s ≤ 1,10 × EP. Sonst Hinweis „eingeteilt statt all-out – Ergebnis
  unsicher“, σ 15 %, Ergebnis nicht automatisch aktiv. W′ wird nicht berechnet (Metaanalyse: nicht verlässlich).
- **Mindestanforderung**: Niveau „Leistung“ empfohlen; Gesundheitsfragen ohne Ja; nicht als erster Test einer neuen
  Person anbieten (vorher ein anderer Test oder 4 Wochen Training), Hinweis „Gewöhnung nötig: das erste Mal ist
  meist zu vorsichtig“.
- **Coach**: Start „Voll! Nicht einteilen!“, alle 20 s Zuspruch (Fundus 1049: Zuspruch alle 20–60 s wirkt),
  bei 90 s „Halbzeit, die Leistung fällt – das ist richtig, halt dagegen“, letzte 30 s „Das zählt! Alles!“.

### 3.5 Schwellentest Rampe – `schwelle-rampentest`

- **Ablauf**: 5 min sehr locker (40–45 % T), dann Minutenstufen ab **50 % T, je Minute +5 % T** (bei T = 162 W:
  81, 89, 97 … W bzw. 2:42,9 → 2:37,8 → …), bis zur Aufgabe; danach 10 min ausrudern. Die Phasen sind bis 160 % T
  ausgerollt (23 Stufen); typische Dauer der Rampe 12–16 min.
- **Abbruch erkennen (`RampFailureDetector`)**: gleitende 15-s-Leistung < 90 % des aktuellen Ziels über 15 s am Stück
  (erst ab Stufe 4), oder Knopf „Ich kann nicht mehr“, oder Schlagzahl 0 über 5 s. Dann `endOnFailure` → Ausrudern.
- **Auswertung (`ramp`)**: MAP = höchste gleitende 60-s-Leistung in den Rampenphasen; T = rampFactor · MAP (Standard
  0,75). Gültig, wenn mindestens 6 Rampenminuten gefahren; sonst „Rampe zu kurz – Start war zu hoch“, Ergebnis nur als
  Hinweis, nächste Rampe startet 10 % tiefer. Länger als 20 min → nächste Rampe startet 10 % höher (Hinweis).
- **Mindestanforderung**: keine; Puls optional (HFmax-Vorschlag, wenn der höchste Puls über dem gespeicherten liegt).
- **Coach**: 5 s vor jedem Minutenwechsel neues Zieltempo („Nächste Minute 2:05“), ab 100 % T anfeuern, bei erkannter
  Aufgabe „Stark! Jetzt ganz locker ausrudern.“

### 3.6 JSON der vier neuen Programme

Format wie `docs/plans-new/BRIEF.md`, Phasen ausgerollt, gültiges JSON (mit `python3 -m json.tool` geprüft).
`paceOffsetMinS/MaxS` gelten für Referenzsplit 2:00 (aus `powerPct*` über Watt ~ 1/Tempo³ gerechnet). Der Bauer legt
sie in `plans.json` ab (Kategorie Test).

```json
[
 {
  "id": "schwelle-stufentest-puls",
  "name": {"de": "Schwellentest submaximal (Stufen mit Puls)", "en": "Submaximal threshold test (steps with heart rate)"},
  "summary": {"de": "Sechs Stufen zu 4 Minuten ohne Pause, von sehr locker bis knapp unter die Schwelle. Die App misst Puls (und wenn möglich die Herzfrequenzvariabilität) und schätzt daraus Schwelle und Zonen, ohne dass du an die Grenze gehst.", "en": "Six 4-minute steps without rest, from very easy to just below threshold. The app records heart rate (and heart rate variability if available) and estimates your threshold and zones without an all-out effort."},
  "purpose": {"de": "Schwellenbestimmung submaximal: Puls-Leistungs-Gerade, Leistung beim Schwellenpuls, optional DFA-alpha1 (Pulszone 1-4)", "en": "Submaximal threshold estimate: heart rate-power line, power at threshold heart rate, optional DFA alpha1 (zone 1-4)"},
  "level": {"de": "Einsteiger", "en": "Beginner"},
  "category": {"de": "Test", "en": "Test"},
  "tags": ["moderate", "threshold", "aerobic", "progressive", "ladder", "benchmark", "beginner-friendly"],
  "test": {"kind": "step-submax", "requiresHeartRate": true, "usesRR": "optional", "allOut": false, "evaluator": "stepHR"},
  "sources": [{"title": "The Effect of Sampling Time on Blood Lactate Concentration in Trained Rowers (Kass & Carpenter), incremental test 5 x 4 min", "publisher": "University of Hertfordshire Research Archive", "url": "https://uhra.herts.ac.uk/id/eprint/790/2/903972.pdf", "published": null, "zotero": null}, {"title": "A New Detection Method Defining the Aerobic Threshold ... Fractal Correlation Properties of Heart Rate Variability (Rogers et al.), Front Physiol 11:596567, doi:10.3389/fphys.2020.596567", "publisher": "Frontiers", "url": "https://doi.org/10.3389/fphys.2020.596567", "published": "2021-01-15", "zotero": null}, {"title": "Joe Friel's Quick Guide to Setting Zones", "publisher": "TrainingPeaks", "url": "https://www.trainingpeaks.com/learn/articles/joe-friel-s-quick-guide-to-setting-zones/", "published": null, "zotero": null}],
  "evidence": "angepasst: Stufen à 4 min wie Kass & Carpenter (dort 5 Stufen, 1 min Pause, je 25 W); hier ohne Pause (für Puls-Drift und DFA-alpha1) und in % der aktuellen Schwellenschätzung; Auswertung Leistung bei Schwellenpuls und DFA-alpha1 0,75/0,5 nach Rogers et al. 2021 (Laufband, Rudern nicht validiert). Pace-Offsets für Referenz 2:00 aus Watt ~ 1/Pace^3",
  "phases": [
   {"kind": "warmup", "durationS": 600, "spmMin": 18, "spmMax": 22, "hrZone": 1, "powerPctMin": 35, "powerPctMax": 45, "label": {"de": "Einrudern 10 min sehr locker, ohne Antritte (Puls soll ruhig sein)", "en": "Warm-up 10 min very easy, no bursts (heart rate should settle)"}},
   {"kind": "work", "durationS": 240, "spmMin": 18, "spmMax": 24, "hrZone": 1, "paceOffsetMinS": 39, "paceOffsetMaxS": 44, "powerPctMin": 48, "powerPctMax": 52, "label": {"de": "Stufe 1/6: 50 % der Schwelle, gleichmässig, Puls am Ende zählt", "en": "Step 1/6: 50 % of threshold, steady, heart rate at the end counts"}, "testRole": "step"},
   {"kind": "work", "durationS": 240, "spmMin": 18, "spmMax": 24, "hrZone": 2, "paceOffsetMinS": 30, "paceOffsetMaxS": 34, "powerPctMin": 58, "powerPctMax": 62, "label": {"de": "Stufe 2/6: 60 % der Schwelle, gleichmässig, Puls am Ende zählt", "en": "Step 2/6: 60 % of threshold, steady, heart rate at the end counts"}, "testRole": "step"},
   {"kind": "work", "durationS": 240, "spmMin": 18, "spmMax": 24, "hrZone": 2, "paceOffsetMinS": 23, "paceOffsetMaxS": 26, "powerPctMin": 68, "powerPctMax": 72, "label": {"de": "Stufe 3/6: 70 % der Schwelle, gleichmässig, Puls am Ende zählt", "en": "Step 3/6: 70 % of threshold, steady, heart rate at the end counts"}, "testRole": "step"},
   {"kind": "work", "durationS": 240, "spmMin": 18, "spmMax": 24, "hrZone": 3, "paceOffsetMinS": 17, "paceOffsetMaxS": 19, "powerPctMin": 78, "powerPctMax": 82, "label": {"de": "Stufe 4/6: 80 % der Schwelle, gleichmässig, Puls am Ende zählt", "en": "Step 4/6: 80 % of threshold, steady, heart rate at the end counts"}, "testRole": "step"},
   {"kind": "work", "durationS": 240, "spmMin": 18, "spmMax": 24, "hrZone": 4, "paceOffsetMinS": 13, "paceOffsetMaxS": 15, "powerPctMin": 86, "powerPctMax": 90, "label": {"de": "Stufe 5/6: 88 % der Schwelle, gleichmässig, Puls am Ende zählt", "en": "Step 5/6: 88 % of threshold, steady, heart rate at the end counts"}, "testRole": "step"},
   {"kind": "work", "durationS": 240, "spmMin": 18, "spmMax": 24, "hrZone": 4, "paceOffsetMinS": 10, "paceOffsetMaxS": 11, "powerPctMin": 93, "powerPctMax": 97, "label": {"de": "Stufe 6/6: 95 % der Schwelle, gleichmässig, Puls am Ende zählt", "en": "Step 6/6: 95 % of threshold, steady, heart rate at the end counts"}, "testRole": "step"},
   {"kind": "cooldown", "durationS": 300, "spmMin": 16, "spmMax": 20, "hrZone": 1, "label": {"de": "Ausrudern 5 min ganz locker", "en": "Cool-down 5 min very easy"}}
  ]
 },
 {
  "id": "schwelle-test-20min",
  "name": {"de": "Schwellentest 20 Minuten (FTP)", "en": "Threshold test 20 minutes (FTP)"},
  "summary": {"de": "20 Minuten mit der höchsten Leistung, die du gleichmässig halten kannst. Schwelle = Durchschnittsleistung mal 0,94.", "en": "20 minutes at the highest power you can hold evenly. Threshold = average power times 0.94."},
  "purpose": {"de": "Schwellenbestimmung maximal (FTP-Test), Grundlage für Leistungs- und Tempozonen (Pulszone 4-5)", "en": "Maximal threshold test (FTP test), basis for power and pace zones (zone 4-5)"},
  "level": {"de": "Fortgeschritten", "en": "Advanced"},
  "category": {"de": "Test", "en": "Test"},
  "tags": ["hard", "threshold", "benchmark"],
  "test": {"kind": "tt-20min", "requiresHeartRate": false, "usesRR": "no", "allOut": true, "evaluator": "timeTrial"},
  "sources": [{"title": "Is the Functional Threshold Power Interchangeable With the Maximal Lactate Steady State in Trained Cyclists? (Borszcz et al.), IJSPP 14:1029, doi:10.1123/ijspp.2018-0572", "publisher": "Human Kinetics", "url": "https://doi.org/10.1123/ijspp.2018-0572", "published": "2019-09", "zotero": null}, {"title": "Joe Friel's Quick Guide to Setting Zones", "publisher": "TrainingPeaks", "url": "https://www.trainingpeaks.com/learn/articles/joe-friel-s-quick-guide-to-setting-zones/", "published": null, "zotero": null}, {"title": "Training for a 2K Rowing Ergometer Test - 4 Week Plan (warm-up guidance)", "publisher": "Concept2", "url": "https://www.concept2.com/training/plans/2k-erg-test-4-week", "published": null, "zotero": null}],
  "evidence": "angepasst: 20-min-Zeitfahren nach Allen & Coggan (Schwelle 95 % der Leistung, im Radsport gegen MLSS geprüft: Borszcz 2019 Bias 1,4 %); hier Faktor 0,94 aus dem Potenzgesetz b = 0,15 (abgeleitet), Einrudern nach Concept2; Rudern nicht validiert",
  "phases": [
   {"kind": "warmup", "durationS": 600, "spmMin": 18, "spmMax": 24, "hrZone": 2, "powerPctMin": 50, "powerPctMax": 75, "label": {"de": "Einrudern 10 min: locker beginnen, bis Zone 3 steigern", "en": "Warm-up 10 min: start easy, build to zone 3"}},
   {"kind": "warmup", "durationS": 180, "spmMin": 20, "spmMax": 30, "hrZone": 3, "label": {"de": "3 Antritte à 20 s auf Testtempo, dazwischen locker", "en": "3 bursts of 20 s at test pace, easy in between"}},
   {"kind": "rest", "durationS": 180, "spmMin": 16, "spmMax": 20, "hrZone": 1, "activeRest": true, "label": {"de": "3 min locker paddeln, dann Test", "en": "3 min easy paddling, then the test"}},
   {"kind": "work", "durationS": 1200, "spmMin": 22, "spmMax": 30, "hrZone": 4, "paceOffsetMinS": 4, "paceOffsetMaxS": 7, "powerPctMin": 102, "powerPctMax": 110, "allOut": true, "testRole": "timeTrial", "label": {"de": "20 min so viel Leistung wie möglich, gleichmässig einteilen, letzte 2 min steigern", "en": "20 min as much power as you can, pace evenly, build in the last 2 min"}},
   {"kind": "cooldown", "durationS": 600, "spmMin": 16, "spmMax": 20, "hrZone": 1, "label": {"de": "Ausrudern 10 min ganz locker", "en": "Cool-down 10 min very easy"}}
  ]
 },
 {
  "id": "schwelle-test-3min",
  "name": {"de": "Schwellentest 3 Minuten All-out (Critical Power)", "en": "Threshold test 3-minute all-out (critical power)"},
  "summary": {"de": "3 Minuten maximal von der ersten Sekunde an, ohne einzuteilen. Die Leistung der letzten 30 Sekunden schätzt die Critical Power; daraus folgt die Schwelle.", "en": "3 minutes maximal from the first second, without pacing. Power over the last 30 seconds estimates critical power, from which the threshold follows."},
  "purpose": {"de": "Critical Power und Schwelle in kurzer Zeit, nur für Geübte (Pulszone 5)", "en": "Critical power and threshold in a short test, experienced rowers only (zone 5)"},
  "level": {"de": "Leistung", "en": "Performance"},
  "category": {"de": "Test", "en": "Test"},
  "tags": ["max", "threshold", "anaerobic", "benchmark", "time-efficient"],
  "test": {"kind": "cp-3min", "requiresHeartRate": false, "usesRR": "no", "allOut": true, "evaluator": "allOut3min"},
  "sources": [{"title": "Determination of critical power in trained rowers using a three-minute all-out rowing test (Cheng et al.), Eur J Appl Physiol 112:1251, doi:10.1007/s00421-011-2081-2", "publisher": "Springer", "url": "https://doi.org/10.1007/s00421-011-2081-2", "published": "2012-04", "zotero": null}, {"title": "The 3-min all-out test in cycling: systematic review and meta-analysis (Quittmann & Piehl), Eur J Appl Physiol 126:4673, doi:10.1007/s00421-026-06356-w", "publisher": "Springer", "url": "https://doi.org/10.1007/s00421-026-06356-w", "published": "2026-09", "zotero": null}],
  "evidence": "direkt: 3-min-All-out auf dem Ruderergometer, Endleistung (letzte 30 s) ~ CP (Cheng 2012, n = 18); Metaanalyse 2026 (Radsport): EP überschätzt CP leicht, Gewöhnung und Zuspruch nötig. Schwelle = 0,88 x EP abgeleitet",
  "phases": [
   {"kind": "warmup", "durationS": 600, "spmMin": 18, "spmMax": 24, "hrZone": 2, "powerPctMin": 50, "powerPctMax": 75, "label": {"de": "Einrudern 10 min: locker beginnen, bis Zone 3 steigern", "en": "Warm-up 10 min: start easy, build to zone 3"}},
   {"kind": "warmup", "durationS": 120, "spmMin": 20, "spmMax": 36, "hrZone": 3, "label": {"de": "2 Antritte à 10 s voll, dazwischen locker", "en": "2 bursts of 10 s full, easy in between"}},
   {"kind": "rest", "durationS": 300, "spmMin": 16, "spmMax": 20, "hrZone": 1, "activeRest": true, "label": {"de": "5 min ganz locker, Kopf auf All-out einstellen", "en": "5 min very easy, get ready for all-out"}},
   {"kind": "work", "durationS": 180, "spmMin": 28, "spmMax": 40, "hrZone": 5, "allOut": true, "testRole": "allOut3min", "label": {"de": "3 min ALL-OUT von Anfang an: nicht einteilen, bis zum Schluss alles geben", "en": "3 min ALL-OUT from the start: do not pace, give everything to the end"}},
   {"kind": "cooldown", "durationS": 600, "spmMin": 16, "spmMax": 20, "hrZone": 1, "label": {"de": "Ausrudern 10 min ganz locker", "en": "Cool-down 10 min very easy"}}
  ]
 },
 {
  "id": "schwelle-rampentest",
  "name": {"de": "Schwellentest Rampe", "en": "Threshold ramp test"},
  "summary": {"de": "Jede Minute wird das Zieltempo etwas schneller, bis du es nicht mehr halten kannst. Schwelle = 75 % der besten Minute. Kurz, nur das Ende ist hart.", "en": "The target pace gets a little faster every minute until you can no longer hold it. Threshold = 75 % of your best minute. Short; only the end is hard."},
  "purpose": {"de": "Schwellenschätzung und maximale aerobe Leistung (Pulszone 1-5)", "en": "Threshold estimate and maximal aerobic power (zone 1-5)"},
  "level": {"de": "Fortgeschritten", "en": "Advanced"},
  "category": {"de": "Test", "en": "Test"},
  "tags": ["hard", "vo2max", "threshold", "progressive", "ladder", "benchmark", "time-efficient"],
  "test": {"kind": "ramp", "requiresHeartRate": false, "usesRR": "optional", "allOut": true, "evaluator": "ramp"},
  "sources": [{"title": "How to Test With the Ramp Test", "publisher": "TrainerRoad", "url": "https://support.trainerroad.com/hc/en-us/articles/360003910912-How-to-Test-With-the-Ramp-Test", "published": null, "zotero": null}, {"title": "Peak power output predicts rowing ergometer performance in elite male rowers (Bourdin et al.), Int J Sports Med 25:368, doi:10.1055/s-2004-815844", "publisher": "Thieme", "url": "https://doi.org/10.1055/s-2004-815844", "published": "2004-07", "zotero": null}],
  "evidence": "angepasst: Rampentest nach TrainerRoad/Zwift (Minutenstufen bis zum Abbruch, Schwelle 75 % der besten Minute; Herstellerregel aus dem Radsport); Stufen hier 5 % der aktuellen Schwellenschätzung je Minute ab 50 %; Spitzenleistung im Stufentest sagt die 2k-Leistung voraus (Bourdin 2004, r = 0,92); Faktor 0,75 fürs Rudern nicht validiert",
  "phases": [
   {"kind": "warmup", "durationS": 300, "spmMin": 18, "spmMax": 22, "hrZone": 1, "paceOffsetMinS": 45, "paceOffsetMaxS": 50, "powerPctMin": 40, "powerPctMax": 45, "label": {"de": "Einrudern 5 min sehr locker", "en": "Warm-up 5 min very easy"}},
   {"kind": "work", "durationS": 60, "spmMin": 20, "spmMax": 28, "hrZone": 1, "paceOffsetMinS": 40, "paceOffsetMaxS": 43, "powerPctMin": 49, "powerPctMax": 51, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 1: 50 % der Schwelle halten", "en": "Ramp minute 1: hold 50 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 20, "spmMax": 28, "hrZone": 2, "paceOffsetMinS": 36, "paceOffsetMaxS": 37, "powerPctMin": 54, "powerPctMax": 56, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 2: 55 % der Schwelle halten", "en": "Ramp minute 2: hold 55 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 20, "spmMax": 28, "hrZone": 2, "paceOffsetMinS": 31, "paceOffsetMaxS": 33, "powerPctMin": 59, "powerPctMax": 61, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 3: 60 % der Schwelle halten", "en": "Ramp minute 3: hold 60 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 20, "spmMax": 28, "hrZone": 2, "paceOffsetMinS": 27, "paceOffsetMaxS": 29, "powerPctMin": 64, "powerPctMax": 66, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 4: 65 % der Schwelle halten", "en": "Ramp minute 4: hold 65 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 20, "spmMax": 28, "hrZone": 2, "paceOffsetMinS": 24, "paceOffsetMaxS": 25, "powerPctMin": 69, "powerPctMax": 71, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 5: 70 % der Schwelle halten", "en": "Ramp minute 5: hold 70 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 20, "spmMax": 28, "hrZone": 3, "paceOffsetMinS": 20, "paceOffsetMaxS": 22, "powerPctMin": 74, "powerPctMax": 76, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 6: 75 % der Schwelle halten", "en": "Ramp minute 6: hold 75 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 20, "spmMax": 28, "hrZone": 3, "paceOffsetMinS": 18, "paceOffsetMaxS": 19, "powerPctMin": 79, "powerPctMax": 81, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 7: 80 % der Schwelle halten", "en": "Ramp minute 7: hold 80 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 20, "spmMax": 28, "hrZone": 3, "paceOffsetMinS": 15, "paceOffsetMaxS": 16, "powerPctMin": 84, "powerPctMax": 86, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 8: 85 % der Schwelle halten", "en": "Ramp minute 8: hold 85 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 20, "spmMax": 28, "hrZone": 4, "paceOffsetMinS": 12, "paceOffsetMaxS": 13, "powerPctMin": 89, "powerPctMax": 91, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 9: 90 % der Schwelle halten", "en": "Ramp minute 9: hold 90 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 20, "spmMax": 28, "hrZone": 4, "paceOffsetMinS": 10, "paceOffsetMaxS": 11, "powerPctMin": 94, "powerPctMax": 96, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 10: 95 % der Schwelle halten", "en": "Ramp minute 10: hold 95 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 24, "spmMax": 36, "hrZone": 4, "paceOffsetMinS": 8, "paceOffsetMaxS": 9, "powerPctMin": 99, "powerPctMax": 101, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 11: 100 % der Schwelle halten", "en": "Ramp minute 11: hold 100 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 24, "spmMax": 36, "hrZone": 5, "paceOffsetMinS": 6, "paceOffsetMaxS": 7, "powerPctMin": 104, "powerPctMax": 106, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 12: 105 % der Schwelle halten", "en": "Ramp minute 12: hold 105 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 24, "spmMax": 36, "hrZone": 5, "paceOffsetMinS": 4, "paceOffsetMaxS": 5, "powerPctMin": 109, "powerPctMax": 111, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 13: 110 % der Schwelle halten", "en": "Ramp minute 13: hold 110 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 24, "spmMax": 36, "hrZone": 5, "paceOffsetMinS": 2, "paceOffsetMaxS": 3, "powerPctMin": 114, "powerPctMax": 116, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 14: 115 % der Schwelle halten", "en": "Ramp minute 14: hold 115 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 24, "spmMax": 36, "hrZone": 5, "paceOffsetMinS": 0, "paceOffsetMaxS": 1, "powerPctMin": 119, "powerPctMax": 121, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 15: 120 % der Schwelle halten", "en": "Ramp minute 15: hold 120 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 24, "spmMax": 36, "hrZone": 5, "paceOffsetMinS": -1, "paceOffsetMaxS": -1, "powerPctMin": 124, "powerPctMax": 126, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 16: 125 % der Schwelle halten", "en": "Ramp minute 16: hold 125 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 24, "spmMax": 36, "hrZone": 5, "paceOffsetMinS": -3, "paceOffsetMaxS": -2, "powerPctMin": 129, "powerPctMax": 131, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 17: 130 % der Schwelle halten", "en": "Ramp minute 17: hold 130 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 24, "spmMax": 36, "hrZone": 5, "paceOffsetMinS": -4, "paceOffsetMaxS": -4, "powerPctMin": 134, "powerPctMax": 136, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 18: 135 % der Schwelle halten", "en": "Ramp minute 18: hold 135 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 24, "spmMax": 36, "hrZone": 5, "paceOffsetMinS": -6, "paceOffsetMaxS": -5, "powerPctMin": 139, "powerPctMax": 141, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 19: 140 % der Schwelle halten", "en": "Ramp minute 19: hold 140 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 24, "spmMax": 36, "hrZone": 5, "paceOffsetMinS": -7, "paceOffsetMaxS": -6, "powerPctMin": 144, "powerPctMax": 146, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 20: 145 % der Schwelle halten", "en": "Ramp minute 20: hold 145 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 24, "spmMax": 36, "hrZone": 5, "paceOffsetMinS": -8, "paceOffsetMaxS": -8, "powerPctMin": 149, "powerPctMax": 151, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 21: 150 % der Schwelle halten", "en": "Ramp minute 21: hold 150 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 24, "spmMax": 36, "hrZone": 5, "paceOffsetMinS": -9, "paceOffsetMaxS": -9, "powerPctMin": 154, "powerPctMax": 156, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 22: 155 % der Schwelle halten", "en": "Ramp minute 22: hold 155 % of threshold"}},
   {"kind": "work", "durationS": 60, "spmMin": 24, "spmMax": 36, "hrZone": 5, "paceOffsetMinS": -11, "paceOffsetMaxS": -10, "powerPctMin": 159, "powerPctMax": 161, "testRole": "ramp", "endOnFailure": true, "label": {"de": "Rampe Minute 23: 160 % der Schwelle halten", "en": "Ramp minute 23: hold 160 % of threshold"}},
   {"kind": "cooldown", "durationS": 600, "spmMin": 16, "spmMax": 20, "hrZone": 1, "label": {"de": "Ausrudern 10 min ganz locker (beginnt, sobald du die Rampe nicht mehr hältst)", "en": "Cool-down 10 min very easy (starts as soon as you can no longer hold the ramp)"}}
  ]
 }
]
```

## 4. Eingabe (Profil → „Schwelle und Zonen“)

Ein Bildschirm, erreichbar aus dem Profil und aus jedem Testergebnis:

- **Kopf**: aktive Schwelle „162 W · 2:09,3/500 m“, Quelle und Datum („aus Test 30 min, 12.11.2026“), Unsicherheit
  „± 3 % (157–167 W)“ mit Stufe hoch/mittel/niedrig, gleichwertige 2k-Zeit („entspricht 2k ≈ 7:58“).
- **Eingabe wahlweise** (Segment): Watt · Tempo an der Schwelle (/500 m) · 2k-Bestzeit · „Ich kenne meinen Wert nicht“
  (→ Testauswahl). Gültigkeitsbereich: 40–600 W; Tempo 1:15–4:00; 2k 5:20–15:00. Jede Eingabe erzeugt eine Schätzung
  (`manualPower`/`manualPace`/`manual2k`, σ₀ 4 % bzw. 6 %) mit Datum heute; Datum änderbar („Wann gemessen?“).
- **Puls**: HFmax (bpm, Quelle: eingegeben / gemessen / geschätzt aus Alter), Ruhepuls, LTHR (optional, mit Hinweis
  „Durchschnittspuls der letzten 20 min eines 30-min-Tests“). Geburtsjahr optional für die Tanaka-Schätzung
  (208 − 0,7 × Alter), nur wenn HFmax fehlt.
- **Zonen-Tabelle** darunter (Abschnitt 4.1) mit Watt, Tempo, Puls; Umschalter „Pulszonen nach LTHR / Herzfrequenzreserve
  / % HFmax“ (Standard automatisch, Abschnitt 4.2).
- **Verlauf**: Liste der Schätzungen (Datum, Quelle, Watt, σ), antippen → Details (Rohwerte, Hinweise, Fahrt öffnen),
  „als aktiv verwenden“, „verwerfen“.
- Bestehende Felder im Profil (Bestzeit 2k, Max-/Ruhepuls) bleiben und schreiben in dieselben Daten (keine doppelte
  Wahrheit): 2k-Bestzeit im Profil = Eingabe `manual2k`.

### 4.1 Zonenrechner (Leistung, Tempo)

| Zone (hrZone) | Name de/en | Band | % T | Watt | Tempo |
|---|---|---|---|---|---|
| 1 | Regeneration / Recovery | UT3 | < 55 | < 0,55 T | langsamer als p(55) |
| 2 | Grundlage / Endurance | UT2 | 55–75 | 0,55–0,75 T | p(55)…p(75) |
| 3 | Grundlage intensiv / Steady state | UT1 | 75–88 | 0,75–0,88 T | p(75)…p(88) |
| 4 | Schwelle / Threshold | AT | 88–102 | 0,88–1,02 T | p(88)…p(102) |
| 5 | Über der Schwelle / Above threshold | TR/AN | > 102 | > 1,02 T | schneller als p(102) |

`p(x) = pace(T) · (x/100)^(−1/3)`; Faktoren 1,220 / 1,101 / 1,043 / 0,993. Beispiel T = 166,1 W (2k 8:00):
Zone 2 = 2:36,5–2:21,1, Zone 3 = 2:21,1–2:13,8, Zone 4 = 2:13,8–2:07,4. Optional Unterteilung Zone 5 in 5a TR
(102–120 %) und 5b AN (> 120 %) nur für die Anzeige.

Die Ampel `TargetLight.pace` bleibt (± 3 s Toleranz); bei Phasen mit `powerPct*` kann zusätzlich eine Watt-Ampel
(± 5 %) gezeigt werden.

### 4.2 Pulszonen

Modellwahl automatisch, in dieser Reihenfolge:

1. **LTHR** vorhanden (≤ 12 Monate): Zone 1 70–80 %, Zone 2 81–89 %, Zone 3 90–93 %, Zone 4 94–99 %, Zone 5 ≥ 100 %
   der LTHR (Friel, Radsporttabelle; unter 70 % = Zone 0).
2. **HFmax und Ruhepuls** vorhanden: Karvonen wie heute (`HeartRateZones`, 50/60/70/80/90 % HFR). Unverändert.
3. **Nur HFmax**: % HFmax nach Concept2 (50/60/70/80/90 %).
4. Nichts: HFmax nach Tanaka (wenn Geburtsjahr) bzw. Standard 185 wie heute, Hinweis „Pulszonen geschätzt“.

Umsetzung: `HeartRateZones` bekommt ein `model` (`.lthr(Int)`, `.reserve(max, rest)`, `.percentMax(max)`) mit
derselben Schnittstelle (`lowerBound(zone:)`, `zone(for:)`, `secondsPerZone`). Gespeicherte Fahrten behalten ihre
gespeicherten Zonensekunden; neu berechnet wird nur auf ausdrücklichen Wunsch („Zonen aller Fahrten neu berechnen“).

HFmax gemessen: höchster 5-s-Mittelwert des Pulses aus Fahrten der letzten 12 Monate (Plausibilität: ≤ 220, kein
Sprung > 15 bpm innerhalb 2 s); liegt er ≥ 3 bpm über dem gespeicherten Wert → Vorschlag „Neuer Maximalpuls 191?“.

## 5. Automatische Schätzung aus Fahrten (`ThresholdDetector`)

- **Eingang**: echte PM5-Fahrten (keine Simulatorfahrten) der letzten 42 Tage mit Zeitreihe (`WorkoutSample.power`,
  ~1 Hz).
- **Leistungs-Dauer-Kurve je Fahrt**: höchste mittlere Leistung über Uhrzeitfenster (Pausen zählen mit Leistung 0,
  wie bei `BestEffortFinder` die Uhrzeit) für t ∈ {180, 300, 480, 600, 720, 1200, 1800, 2400, 3600} s.
  Zwei-Zeiger-Verfahren über kumulierte Arbeit, linear interpoliert. Zwischenspeichern je Fahrt (einmal berechnen).
- **Maximalität** (sonst zählt die Fahrt nicht): Programm der Kategorie Test, **oder** eigene Belastung ≥ 8
  (`WorkoutEffort.userScore`), **oder** mittlerer Puls im Fenster ≥ Untergrenze Zone 4 und Fenster ≥ 8 min
  (dann σ + 2 %).
- **Kandidat Zeitfahren**: für t ≥ 480 s (wie Zwift 8–60 min): T_t = MMP(t) · (t/1800)^b; je Fahrt das Maximum über t;
  Gesamt-Kandidat = höchster Wert der 42 Tage. Quelle `ridesAuto`, σ₀ 6 %.
- **Kandidat CP** (`criticalPowerFit`): zwei maximale Efforts mit 120 s ≤ t₁ < t₂ ≤ 1200 s, t₂/t₁ ≥ 2,5, aus
  verschiedenen oder derselben Fahrt (nur, wenn dazwischen kein Überlappen): W = P · t,
  CP = (W₂ − W₁)/(t₂ − t₁), W′ = W₁ − CP · t₁. Plausibel nur bei CP > 0 und 5 kJ ≤ W′ ≤ 40 kJ. T = 0,88 · CP. Bei drei
  Efforts lineare Regression W über t (CP = Steigung).
- **Vorschlag**: wenn Kandidat ≥ aktive T · 1,03 und ≥ T + 5 W: Karte „Neue Schwelle erkannt: 171 W (aus deiner Fahrt
  vom 20.11.: 24 min mit 175 W). Übernehmen?“ – Ja → Schätzung aktiv; Nein → `rejected`, gleicher Wert wird nicht erneut
  vorgeschlagen (erneut erst ab weiteren + 2 %). Höchstens ein Vorschlag je 7 Tage.
- **Fenster beim App-Start** (seit 11/2026): Der Vorschlag erscheint zusätzlich einmal als kurzes Fenster beim Start
  bzw. bei der Rückkehr aus dem Hintergrund (nach der ersten Neuberechnung; Fahrten aus der Synchronisation zählen,
  wenn sie bis 90 s danach eintreffen): „Neue Schwelle erkannt 171 W, vorher 165 W – Aus deiner Fahrt vom 20.11.:
  24 min mit 175 W auf Alte Donau Wien.“ mit „Übernehmen“ (wie Ja), „Nicht jetzt“ und Link „Details“ (Schwelle &
  Zonen). „Nicht jetzt“ (auch Wegwischen) stellt zurück statt abzulehnen (`rideProposalDeferredW/-Date` im Profil,
  synchronisiert): das Fenster kommt erst wieder ab + 2 % über dem zurückgestellten Wert oder nach 7 Tagen
  (`ThresholdDetector.shouldPrompt`). Die Karte auf „Heute“ bleibt als ruhige Erinnerung, solange der Vorschlag offen
  ist (✕ auf der Karte = Nein). Nicht während einer Fahrt, nicht über Ersteinrichtung, Gesundheitsfragen,
  Health-Freigabe oder anderen Sheets, nicht im Testbetrieb (`-photoMode`, `-demoCourse`, `-seedDemoHistory`,
  `-demoRace`, `-demoTournament`). Testbetrieb: `-demoThresholdCandidate 1` (Beispiel + 4 %, alle Regeln) bzw. `2`
  (Zurückstellung beim Start vergessen), nur Debug/Dev.
- **Grundlage**: alle gespeicherten Fahrten, auch die per Synchronisation von anderen Geräten (gleicher Verlauf in
  SwiftData, Zeitreihe mit Leistung und Puls, Gerätequelle und eigene Belastung kommen mit; Test
  `testSyncedRideKeepsThresholdEfforts`). Neue Fahrten aus der Synchronisation lösen über den Verlauf die
  Neuberechnung aus. In der Basis-Fassung (ohne Synchronisation) nur die Fahrten dieses Geräts.
- **Nie automatisch senken** aus Fahrten (normale Fahrten sind meist nicht maximal). Senken nur über Test oder
  Eingabe (Abschnitt 7).
- **Pa:HR / Entkopplung** (nur Information, keine Schwelle): bei gleichmässigen Fahrten ≥ 40 min überwiegend in Zone 2:
  EF = mittlere Leistung / mittlerer Puls je Hälfte (erste 10 % ohne Einrudern); Entkopplung = (EF₁ − EF₂)/EF₁.
  < 5 % „Grundlage trägt“, 5–10 % „Grundlage begrenzt“, > 10 % „vermutlich über der aeroben Schwelle“
  (TrainingPeaks/Friel, Praxis). Anzeige in der Auswertung der Fahrt.

## 6. Priorisierung und Anzeige (`ThresholdSelector`)

- **Aktuelle Unsicherheit**: σ(t) = σ₀ (+ Aufschläge) + 0,5 % je Woche ab der 7. Woche nach dem Datum, höchstens 15 %
  (abgeleitet: Training verändert die Leistung über Wochen; Retest-Empfehlung 4–8 Wochen).
  Nach einer Trainingspause ≥ 14 Tage zusätzlich + 3 % (Abschnitt 7, R3).
- **Aktive Schwelle**: die Schätzung mit dem kleinsten σ(t); bei Gleichstand die neuere.
  Ausnahmen:
  1. **Eingaben** (`manual*`) werden nie automatisch abgelöst. Ist eine andere Schätzung um ≥ 1 Prozentpunkt sicherer
     und weicht um > 3 % ab → Vorschlag „Dein Test vom … ergab 171 W, eingetragen sind 160 W. Übernehmen?“.
  2. **Testergebnis höher** als aktive T → sofort aktiv (Hinweis „Neue Schwelle 171 W (+5 %)“), wie heute beim
     schnelleren 2k-Test.
  3. **Testergebnis niedriger** (> 3 %) → Rückfrage „übernehmen oder alte Schwelle behalten?“ (wie heute beim
     langsameren Test; Tagesform streut).
  4. Ergebnisse mit Prüfhinweis „nicht all-out“, „Rampe zu kurz“, „zu weit hochgerechnet“ werden nie automatisch aktiv.
- **Anzeige überall, wo Ziele stehen** (Programmansicht, Startbildschirm-Vorschlag, Training): kleine Zeile „Ziele aus
  Schwelle 162 W (Test 30 min, 12.11.)“; Farbe der Unsicherheitsstufe: hoch ≤ 4 %, mittel ≤ 8 %, niedrig > 8 %.
  Bei niedrig zusätzlich „Test empfohlen“ mit Link.
- **Testergebnis-Bildschirm**: Ergebnis (Watt, Tempo, gleichwertige 2k), Vergleich zur bisherigen Schwelle,
  Unsicherheit, Prüfhinweise, neue Zonen-Tabelle, Knöpfe „Übernehmen“ / „Behalten“ (bei automatischer Übernahme:
  „Rückgängig“).

## 7. Retest-Regeln

| # | Bedingung | Reaktion |
|---|---|---|
| R1 | aktive Schwelle älter als 8 Wochen (oder σ(t) > 8 %), 4 Wochen regelmässig (in jedem der letzten vier 7-Tage-Fenster ≥ 2 Fahrten), letzte 48 h leicht | `DailySuggestion` Regel 4 wird „Schwellentest fällig“: bevorzugter Test (unten) statt fest 2000 m |
| R2 | Fahrten-Kandidat ≥ T · 1,03 | Vorschlag „Neue Schwelle erkannt“ (Abschnitt 5), kein Test nötig |
| R3 | Pause ≥ 14 Tage ohne Fahrt | σ + 3 %; nach dem Wiedereinstieg (3. Fahrt) Vorschlag „Stufentest submaximal zum Wiedereinstieg“; bestehende Pausenregel der Trainingspläne (−1 s/500 m je Pausenwoche) bleibt |
| R4 | in 2 der letzten 3 Einheiten der Kategorien Schwelle/Intervalle: Tempoampel in Belastungsphasen > 40 % der Zeit rot (zu langsam) oder eigene Belastung ≥ 9 | Hinweis „Ziele zu hoch?“ mit Test oder „Schwelle −3 %“ (eine Taste, Quelle `manualPower`, Notiz) |
| R5 | in 3 der letzten 4 Schwellen-Einheiten: gemessene Leistung > 105 % des Ziels bei Puls höchstens Zone 3 | Hinweis „Ziele zu leicht?“ mit Test |
| – | Mindestabstand zwischen zwei vorgeschlagenen Tests 21 Tage; kein Testvorschlag mit aktivem Trainingsplan, der eigene Tests hat (wie heute) | |

**Bevorzugter Test** (`preferredTest`, in Einstellungen wählbar): Standard nach Profil – Pulsgurt bekannt und
(Niveau Einsteiger oder Gesundheitsfrage mit Ja oder Alter ≥ 60) → `schwelle-stufentest-puls`; schon einmal 2000 m
getestet → `test-2000m`; sonst `schwelle-test-20min`. Rampe und 3 min nur auf Wunsch.

## 8. Migration und Abwärtskompatibilität

### 8.1 Stufe 1 (Pflicht): Schwelle als Quelle, 2k als Spiegel

1. Beim ersten Start nach dem Update: `ThresholdProfile` anlegen. Aus `TrainingSettings.best2k` eine Schätzung
   `legacy2k` (σ₀ 6 %; ist der Wert der Standard 480 s und nie geändert → σ₀ 15 %, Text „Standardwert“). HFmax/Ruhepuls
   aus `profile.maxHR`/`profile.restHR` übernehmen (Quelle `manual`).
2. `TrainingSettings.best2k` bleibt der Bezug aller bestehenden Rechnungen (`PaceTargets`, `PlanEngine`, Effort,
   `IntensityRules`, Pace-Line, Trainingspläne). Neu ist nur, **wer ihn schreibt**: Bei jeder Änderung der aktiven
   Schwelle schreibt `ThresholdStore` die gleichwertige 2k-Zeit (Abschnitt 2.1) nach `best2kKey`.
   Rundreise-Garantie: Stammt die aktive Schwelle aus einer 2k-Eingabe oder einem 2k-Test, ist der Spiegel exakt diese
   Zeit (Test: |Δ| < 0,1 s). Damit ändern sich für bestehende Nutzer **keine Ziele**.
3. Das Profilfeld „Bestzeit 2k“ schreibt künftig eine Schätzung `manual2k` (statt direkt `best2kKey`); Anzeige
   unverändert.
4. `TrainingProgramEngine.evaluateTests`/`estimateBest2k` (Paul's Law) wird ersetzt durch `ThresholdEvaluator` +
   gleichwertige 2k. Die Regeln „schneller sofort, langsamer nach Rückfrage“ und „Test setzt `paceAdjustment` zurück“
   bleiben. Hinweis für Tests: Paul's Law und Potenzgesetz ergeben für Nicht-2k-Tests leicht andere Referenzen
   (z. B. 30 min mit 2:10/500 m: Paul's Law 2k ≈ 8:04,2; Potenzgesetz 2k ≈ 8:07,1) – die bestehenden Unit-Tests dafür
   anpassen und den Unterschied im Changelog nennen.
5. Die tatsächliche 2k-Bestleistung bleibt in den Bestmarken (`BestEffortFinder`) sichtbar und ist von der
   gleichwertigen 2k-Zeit getrennt (Beschriftung „2k-Referenz für Ziele“ statt „Bestzeit“, wo sie aus einer anderen
   Quelle stammt).

### 8.2 Stufe 2 (optional, gleiche Version möglich): Ziele direkt aus der Schwelle

- Phasen mit `powerPctMin/Max` bekommen ihren Tempobereich aus T (Abschnitt 3.1); `paceOffset*` dieser Phasen dienen
  nur alten App-Versionen.
- Alte Programme ohne `powerPct*`: weiterhin `paceOffset*` relativ zur gespiegelten 2k-Zeit. Optionaler Schalter
  (Einstellungen → Training, Standard **aus**): „Ziele nach Leistungsanteil skalieren“ – dann wird ein Offset als
  Wattanteil des Referenzsplits 2:00 gelesen, `f = (120 / (120 + offset))³`, und auf die persönliche gleichwertige
  2k-Leistung angewendet (`pace = pace(f · P2k)`). Wirkung: für 2:00-Ruderer identisch, für schnelle Ruderer etwas
  kleinere, für langsame etwas grössere Sekundenabstände (z. B. +10 s bei 2k 1:40 → +8,4 s). Physiologisch richtiger,
  aber eine sichtbare Änderung; deshalb zuerst als Schalter.
- `hrZone` behält seine Bedeutung 1–5 und wird mit dem gewählten Pulsmodell (4.2) ausgewertet.

### 8.3 Datenformat

`plans.json` bleibt eine Liste; neue Felder sind optional. `ThresholdProfile` hat `formatVersion`; unbekannte
Quellenarten bleiben als Text erhalten (gleiches Prinzip wie `EffortBasis`).

## 9. Sicherheit

- **Gesundheitsfragen vor dem ersten maximalen Test** (20 min, 30/60 min, 2000 m und kürzer, Rampe, 3 min), angelehnt an
  PAR-Q+: bekannte Herzerkrankung oder Bluthochdruck in Behandlung; Brustschmerz in Ruhe oder bei Belastung;
  Schwindel/Bewusstlosigkeit in den letzten 12 Monaten; andere chronische Erkrankung, die Belastung einschränkt;
  Medikamente für Herz/Kreislauf; ärztlich geraten, nur unter Aufsicht zu trainieren; Schwangerschaft. Bei einem Ja:
  maximale Tests werden nicht vorgeschlagen, beim Start erscheint „Bitte zuerst ärztlich abklären“; der Stufentest
  submaximal bleibt verfügbar. Schalter „Ärztliche Freigabe liegt vor“ (Datum) hebt das auf. Antworten bleiben lokal.
- **Abbruch-Hinweis** in jedem Test vor dem Start und im Coach: bei Brustschmerz, Schwindel, ungewöhnlicher Atemnot oder
  Herzstolpern sofort aufhören. Knopf „Test abbrechen“ immer sichtbar.
- **Automatisch**: Puls > HFmax + 8 über 10 s oder Pulssprünge > 30 bpm/s → Hinweis „Pulsgurt prüfen“ (kein Abbruch);
  im Stufentest Pulsausfall > 30 s → Test pausiert die Auswertung und meldet „Puls fehlt“.
- Concept2 empfiehlt harte Zonen nur nach ärztlicher Freigabe (Concept2-Blog 2025); Text dazu in der Testauswahl.

## 10. Sprachcoach (Ergänzung zu docs/coach/SPEC.md)

Neue Szenarien (ids fest, Texte in `coach_phrases.json`, Stile sachlich/motivierend/Cox):

| id | Auslöser | Beispiel (sachlich) |
|---|---|---|
| `test_intro` | Start eines Testprogramms | „Schwellentest, 20 Minuten. Gleichmässig einteilen, die letzten zwei Minuten steigern.“ |
| `test_step_next` | 15 s vor einer Stufe | „Gleich Stufe 4: 2:19 pro 500 Meter.“ |
| `test_step_hold` | Stufentest, Tempo > 3 s schneller als Ziel über 10 s | „Nicht schneller werden. Ruhig bleiben.“ |
| `test_talk_check` | Stufenende ab Stufe 2 | „Kannst du noch in ganzen Sätzen sprechen?“ |
| `test_hr_reached` | Stufentest vorzeitig zu Ende | „Schwelle erreicht. Wir hören hier auf. Locker ausrudern.“ |
| `test_tt_pacing` | 20/30 min: erste 3 min > 110 % T bzw. alle 5 min Stand | „Etwas zu schnell, nimm zwei Watt raus.“ / „Halbzeit, Schnitt 175 Watt.“ |
| `test_allout_go` | Start 3 min All-out | „Voll! Nicht einteilen!“ |
| `test_allout_encourage` | alle 20 s im All-out, letzte 30 s | „Halt dagegen!“ / „Das zählt jetzt!“ |
| `test_ramp_next` | 5 s vor jeder Rampenminute | „Nächste Minute 2:05.“ |
| `test_ramp_end` | Abbruch erkannt | „Stark! Jetzt ganz locker ausrudern.“ |
| `test_result` | Ende des Testteils | „Neue Schwelle 171 Watt, 2:06 pro 500 Meter.“ |

Regeln: Im submaximalen Test keine Motivation (`fade_*`, `pace_on_target` aus), nur Information und `test_step_hold`.
In All-out-Phasen höheres Budget (bis 3 Ansagen/min) und Zuspruch alle 20–30 s (Fundus 1048–1050: Zuspruch alle
20–60 s steigert Ausbelastung und Leistung). Testansagen haben Priorität „Info“.

## 11. Tests und Abnahme (RowCoachKit, XCTest)

- `ThresholdMath`: W(120 s) = 202,5 W; pace(202,5 W) = 120,0 s; 2k 8:00 → T = 166,1 W → gleichwertige 2k 480,0 s
  (|Δ| < 0,1 s); T = 200 W → 2k 449,7 s; Faktoren 20/30/60 min = 0,941/1,000/1,110 bei b = 0,15.
- Zonen: T = 166,1 W → Grenzen Zone 2/3/4/5 = 2:36,5 / 2:21,1 / 2:13,8 / 2:07,4 (± 0,1 s).
- `stepHR`: synthetische Stufen (P = 80…150 W, HR = 60 + 0,5 · P ± Rauschen), HR_T = 135 → T = 150 W ± 2 W; < 3 gültige
  Stufen → nicht auswertbar; HR_T 20 bpm über höchster Stufe → nur Hinweis.
- `DFAAlpha1`: weisses Rauschen → α1 ≈ 0,5; Brownsches Rauschen (integriert) → α1 ≈ 1,5; 1/f-Rauschen → ≈ 1,0
  (± 0,1); Artefaktanteil > 5 % → Fenster verworfen.
- `ramp`: konstante Rampe bis 140 % T, Abbruch nach 15 s unter 90 % → MAP und T = 0,75 · MAP; Rampe < 6 min → Hinweis.
- `allOut3min`: Profil mit Spitze 1,6 × EP und Plateau → gültig; gleichmässige Leistung → „nicht all-out“, nicht aktiv.
- `ThresholdSelector`: Eingabe wird nicht abgelöst; Test höher → aktiv; Test niedriger → Rückfrage; Alterung
  (+0,5 %/Woche ab Woche 7, Deckel 15 %).
- `ThresholdDetector`: Fahrt mit 24 min bei 175 W und Belastung 8 → Kandidat 175 · (1440/1800)^0,15 = 169,2 W;
  Fahrt ohne Maximalitätsmerkmal → kein Kandidat; CP aus 3 min/300 W und 12 min/230 W → CP = 206,7 W, W′ = 16,8 kJ,
  T = 181,9 W.
- Migration: best2k 455 s → nach Migration `best2kKey` = 455,0 s; Programmziele aller 111 Programme unverändert
  (Schnappschuss-Test über `paceRange(best2k:)`).
- `plans.json`: alle vier neuen Programme dekodieren; alte Version (Felder ignoriert) liefert gültige Phasen.

## 12. Offene Punkte für Falk

1. Schwellendefinition „30 min“ (entspricht FTP-Konvention 0,95 × 20 min) statt „60 min“ – bewusst gewählt, weil
   Ruderer ihre 60-min-Leistung deutlich tiefer haben (Jensen: 76 % der 2k-Watt) und die Bänder sonst zu weich würden.
2. Schalter „Ziele nach Leistungsanteil skalieren“ (8.2) später Standard „ein“?
3. Nach den ersten eigenen Daten prüfen: Faktoren 0,88 (CP → T), 0,75 (Rampe), 0,77 (LT1 → T), b = 0,15; DFA-α1 am
   Ruderergometer gegen einen 30-min-Test vergleichen (eigene kleine Validierung, Hypothese im Forschungsregister
   anlegen, falls gewünscht).
4. Synchronisation des Schwellenprofils (docs/SYNC.md) und Anzeige auf Android (docs/ANDROID.md) – getrennt planen.
