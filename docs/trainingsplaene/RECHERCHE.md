# Trainingspläne über mehrere Wochen: Recherche, Planbibliothek und Regeln für die App

Stand 26.11.2026. Auftrag Falk (26.11.): Sportliteratur zu Trainingsplänen über Wochen und Monate durchsuchen und daraus
Pläne für RowCoach bauen. Ergebnis:

- `App/RowCoach/Resources/training_plans.json` – 17 Pläne, zusammengesetzt aus den 104 Programmen in `plans.json` (per id)
- `App/l10n/check_training_plans.py` – Prüfskript (läuft fehlerfrei: 17 Pläne, 0 Fehler, 0 Warnungen)
- `docs/trainingsplaene/PLAENE.md` – lesbare Übersicht aller Pläne Woche für Woche (aus dem JSON erzeugt)
- dieses Dokument – Belege, Format und Regeln, nach denen die App die Pläne ausführt

Belegstärke in diesem Dokument: **stark** = Metaanalyse oder randomisierte Studie; **mittel** = Einzelstudie,
Beobachtungsstudie oder Review; **Praxis** = veröffentlichter Plan eines Herstellers oder Verbands (Concept2,
British Rowing, NHS, Pete Plan); **abgeleitet** = eigene Regel, aus Belegen geschlossen, nicht direkt geprüft.

## 1. Recherchewege

1. Zotero (`zrag search`/`zrag semantic`): `search` lieferte nur ein unpassendes Transkript, `semantic` antwortete nicht
   (Zeitüberschreitung) – übersprungen.
2. Fundus (Projekt `rowcoach`): vorhanden waren Bosquet 2007 (Tapering), Seiler & Tønnessen 2009, Seiler & Kjerland 2006,
   Pete Plan, Concept2 Couch to Consistency, Concept2 2k-, 500-m- und 4-min-Pläne, Wolfson-Leitfaden, Paul's Law.
3. Web, Primärquellen: Concept2-Planseiten (Couch to Consistency, 5k, Halbmarathon, Marathon), British Rowing (Go Row
   Beginner als PDF vollständig gelesen, „How Much How Often“ als PDF gelesen), Beginner Pete Plan, NHS Couch to 5K,
   Abstracts/PubMed bzw. Frontiers zu Treff 2017, Stöggl & Sperlich 2014, Fiskerstrand & Seiler 2004, Güllich et al.
   2009, Mujika & Padilla 2000/2001, Spiering 2021, Fell & Williams 2008, Borges 2016, Issurin 2010, Garber/ACSM 2011.
   Bei den Fachartikeln wurden Abstracts und Zusammenfassungen gelesen, nicht immer der Volltext (vermerkt).
4. Nicht geprüft und deshalb nicht verwendet: Nolte „Rowing Faster“ (Buch, nicht zugänglich), Wolverine Plan im Detail
   (nur Forenbeiträge; Caviston: 6–7 Einheiten zu 40–60 min, Stufen 1–4), Dark Horse Rowing, USRowing-Pläne,
   GB-Rowing-Matrix (Weiterleitung, schon in der früheren Recherche nicht abrufbar).
5. In Fundus zurückgeschrieben (unverified, Projekt rowcoach): Treff 2017 (study 1052), Stöggl & Sperlich 2014 (1053),
   Spiering 2021 (1054), Mujika & Padilla 2000 (1055), Concept2 Halbmarathonplan (practice 992), Concept2 Marathonplan
   (993), Beginner Pete Plan (994), NHS Couch to 5K (995). British Rowing Go Row Beginner und „How Much How Often“
   wurden abgelehnt (ich hatte sie fälschlich als verifiziert markiert) und nicht erneut versucht.

## 2. Belege: was die Literatur zu Plänen sagt

### 2.1 Intensitätsverteilung (Grundlage fast aller Pläne)
- Elite-Ausdauersportler trainieren 80 % oder mehr unter der Laktatschwelle; bei Elite-Ruderern (Steinacker 1998)
  dominierten 60–120-min-Einheiten unter 2 mmol/l, hohe Intensitäten waren etwa 4–10 % der Ruderzeit
  (Seiler & Tønnessen 2009, Fundus study 1035). **mittel**
- Norwegische Medaillengewinner 1970–2001: über die Jahrzehnte mehr Umfang, mehr Grundlage in der Vorbereitung, etwa
  75 % deutlich unter und 15–20 % deutlich über der Schwelle (Fiskerstrand & Seiler 2004; Zahlen nur aus Sekundärquellen,
  Volltext nicht gelesen). **mittel**
- Deutsche Weltklasse-Junioren: etwa 95 % niedrige Intensität über die Saison, in der Wettkampfphase stärker polarisiert
  (Güllich, Seiler & Emrich 2009, Abstract). **mittel**
- Polarisiert gegen Schwelle, HIIT und hohen Umfang, 9 Wochen, 48 gut trainierte Ausdauersportler (keine Ruderer):
  grösster VO2peak-Zuwachs mit polarisiert (+11,7 %) (Stöggl & Sperlich 2014). **stark** (eine RCT)
- Bei 14 nationalen Elite-Ruderern war polarisiert über 11 Wochen **nicht** besser als pyramidal; beide ≈ 93–94 % Zone 1
  (Treff et al. 2017). **mittel**
- Folgerung für RowCoach: alle Pläne haben etwa 75–85 % der Pflichtzeit in Pulszone 1–2 (gerechnet aus den Phasen der
  Programme; das Prüfskript warnt unter 70 %). Das „80/20“ ist gut begründet als Rahmen; einen bewiesenen Vorteil der
  strikt polarisierten gegenüber der pyramidalen Verteilung gibt es bei Ruderern nicht. Der Plan
  `polarisiert-80-20-10-wochen` sagt das in seinem Belegtext.

### 2.2 Periodisierung, Belastung und Entlastung
- Blockperiodisierung (Issurin 2010): aufeinanderfolgende Blöcke mit wenigen Schwerpunkten (Akkumulation →
  Transmutation → Realisation); Kiely (2010) hält die Evidenz für dünn. **mittel/umstritten** – in RowCoach nur als
  Abfolge Grundlage → Intervalle → Renntempo in den 12-Wochen-Plänen.
- Leichtere Woche nach 2–3 normalen (3:1, bei Masters 2:1): in Plänen weit verbreitet, aber für Ausdauersport kaum
  direkt untersucht; die Delphi-Studie von Bell et al. 2023 betrifft Kraftsport. **Praxis/abgeleitet**. In RowCoach:
  leichtere Woche = mindestens 25 % weniger Minuten als die Woche davor, Intensität bleibt teilweise erhalten.
- Concept2-Pläne haben selbst keine Deload-Wochen, aber Testwochen mit weniger Umfang; der Concept2-Marathonplan senkt
  die lange Fahrt in Woche 4 und 8 (12 bzw. 18 km nach 16 bzw. 26 km). **Praxis**
- Pete Plan (FAQ): wer leichter trainieren will, ordnet die drei Wochen eines Zyklus als leicht/mittel/hart an.
  **Praxis**

### 2.3 Tapering vor Test oder Rennen
- Metaanalyse über 27 Studien: am wirksamsten sind etwa 2 Wochen mit 41–60 % weniger Umfang, exponentiell abnehmend,
  ohne Intensität oder Häufigkeit zu senken; Effektstärke 0,72 (Bosquet et al. 2007, Fundus study 1044). **stark**
- RowCoach: 2000-m-Pläne mit 12 Wochen und der Wettkampfplan haben 2 Taper-Wochen, die 8-Wochen-Pläne 1 Woche, der
  Marathonplan wie Concept2 4 Wochen. Die Zahl der Einheiten pro Woche bleibt gleich, die Programme werden kürzer;
  harte Reize bleiben (z. B. Renntempo 2 × 1000 m, 4 × 500 m). Das Prüfskript verlangt: Taper-Wochen nehmen nicht zu,
  die letzte liegt mindestens 25 % unter dem Schnitt der drei Wochen davor (ohne die Zieleinheit).

### 2.4 Umfang und Häufigkeit für Freizeit- und Masters-Ruderer
- ACSM 2011: ≥ 150 min moderat an ≥ 5 Tagen oder ≥ 75 min intensiv an ≥ 3 Tagen pro Woche (Garber et al.). **stark**
  (Leitlinie)
- British Rowing „How Much How Often“ (2019, S. 5): Level 1 höchstens 2 rudertypische Einheiten zu 30–40 min (1–2 h);
  Level 2 im Mittel 3, höchstens 4 Einheiten zu 45–60 min (2–4 h); Level 3 im Mittel 4, höchstens 6 (4–8 h);
  Level 4 im Mittel 6, höchstens 8 (6–12 h). Länge und Intensität richten sich danach, ob Technik und Haltung halten. **Praxis**
- Concept2 Couch to Consistency: 4 Einheiten pro Woche, „mindestens zwei gute harte Reize pro Woche“, Intensität
  variieren. **Praxis**
- Masters: Erholung der Muskulatur nach Belastung möglicherweise langsamer (Fell & Williams 2008), der Alterseffekt ist
  aber kleiner als oft angenommen und hängt stark vom Aktivitätsniveau ab (Borges et al. 2016). **mittel (unsicher)**
  → RowCoach-Masters-Plan: 1 harter Reiz pro Woche, 72 h Abstand, jede dritte Woche leichter (**abgeleitet**).

### 2.5 Einsteiger: Progression und Dranbleiben
- NHS Couch to 5K: 9 Wochen, 3 Einheiten mit Ruhetag dazwischen, von 1-Minuten-Stücken zu 30 Minuten am Stück; „it's
  totally okay to repeat a week“. **Praxis** (sehr verbreitet)
- British Rowing Go Row Beginner (8 Wochen, 2 Einheiten): Woche 1 5 × 1 min und 2 × 5 min locker, Woche 5 erste 2000 m,
  Woche 6 erste harte 1-Minuten-Stücke; Schlagzahl 18–24, Dämpfer ≤ 4. **Praxis** (PDF vollständig gelesen)
- Concept2 Couch to Consistency (6 Wochen + offenes Muster): am Stück 15 → 30 → 40 min, 2000 → 4000 → 5000 m in Woche 6.
  **Praxis**

### 2.6 Pause, Wiedereinstieg, Erhalten
- Unter 4 Wochen ohne Training sinkt die VO2max bei Trainierten rasch (v. a. über weniger Blutvolumen), bleibt aber über
  Untrainierten; bei erst kurz Trainierten gehen die Zugewinne nach mehr als 4 Wochen weitgehend verloren
  (Mujika & Padilla 2000, 2001). **mittel** (Reviews)
- Erhalten: Ausdauerleistung blieb bis zu 15 Wochen erhalten mit nur 2 Einheiten pro Woche oder 33–66 % weniger Umfang,
  solange die Intensität gehalten wurde (Spiering et al. 2021; Evidenz v. a. aus älteren Studien, nicht an Athleten).
  **mittel**
- Pete Plan FAQ: nach einer Pause die Tempoziele um 1 s/500 m pro verpasster Woche senken. **Praxis**

### 2.7 Bewährte Pläne, die in die Bibliothek eingeflossen sind
| Vorlage | Kern | RowCoach-Plan |
|---|---|---|
| Concept2 Couch to Consistency | 6 Wochen, 4×/Woche, Steigerung bis 5000 m / 40 min | einstieg-4-wochen, einstieg-8-wochen-5000m, fitness-3x-12-wochen |
| British Rowing Go Row Beginner | 8 Wochen, 2×/Woche, Ziel 2000 m | einstieg-8-wochen-5000m, test-2000m-8-wochen-einsteiger |
| NHS Couch to 5K | 9 Wochen, 3×/Woche, Wochen wiederholen erlaubt | Einstiegslogik (Ruhetag, Woche wiederholen) |
| Concept2 2k 4 und 12 Wochen | 3 + 1 freiwillige Einheit, 4×4, 6–10×2, 6×500, 3×1000 | test-2000m-8-/12-wochen-* |
| Concept2 5k (8/12 Wochen) | lange Fahrt 5–10 km, Intervalle, 2×3000, 5k-Test Woche 1 und 4 | langdistanz-5000m-8-wochen, grundlage-winter-12-wochen |
| Concept2 Halbmarathon | 10 Wochen, 4×, lange Fahrt 8 → 16 km, HMP ab Woche 7 | halbmarathon-12-wochen |
| Concept2 Marathon | 16 Wochen, 4×, lange Fahrt 12 → 34 km, Taper ab Woche 13 | marathon-16-wochen |
| Pete Plan | 3-Wochen-Zyklus, 6 Einheiten, Tempo- und Ausdauer-Intervalle | test-2000m-12-wochen-leistung |
| Beginner Pete Plan | 24 Wochen, 3 + 2 freiwillig, Grundlage 5 → 12 km | pete-artig-24-wochen |

## 3. Planbibliothek

17 Pläne, Details Woche für Woche in `PLAENE.md`.

| id | Ziel | Niveau | Wochen | Einheiten/Woche | Beleg |
|---|---|---|---|---|---|
| einstieg-4-wochen | 30 min locker am Stück, erste Referenz | Einsteiger | 4 | 3 | angepasst |
| einstieg-8-wochen-5000m | 5000 m am Stück | Einsteiger | 8 | 3 (+1) | angepasst |
| fitness-3x-12-wochen | Ausdauer/Gesundheit, offen (danach ab Woche 5) | Einsteiger | 12 | 3 (+1) | abgeleitet |
| erhaltung-2x | Form halten mit wenig Zeit, offen | Fortgeschritten | 8 | 2 (+1) | abgeleitet |
| wiedereinstieg-3-wochen | nach 2–8 Wochen Pause zurück | Einsteiger | 3 | 3 | abgeleitet |
| grundlage-winter-12-wochen | Wintergrundlage, 5000 m | Fortgeschritten | 12 | 3 (+1) | angepasst |
| test-2000m-8-wochen-einsteiger | erster 2000-m-Test | Einsteiger | 8 | 3 (+1) | angepasst |
| test-2000m-8-wochen-fortgeschritten | 2000-m-Bestzeit | Fortgeschritten | 8 | 3 (+1) | angepasst |
| test-2000m-12-wochen-fortgeschritten | 2000-m-Bestzeit | Fortgeschritten | 12 | 3 (+1) | angepasst |
| test-2000m-12-wochen-leistung | 2000-m-Bestzeit hoch | Leistung | 12 | 4 (+1) | angepasst |
| langdistanz-5000m-8-wochen | 5000/6000 m | Fortgeschritten | 8 | 3–4 | angepasst |
| halbmarathon-12-wochen | Halbmarathon | Fortgeschritten | 12 | 4 | angepasst |
| marathon-16-wochen | Marathon | Leistung | 16 | 4 | angepasst |
| masters-50plus-12-wochen | Form ohne Überlastung | Fortgeschritten | 12 | 3 (+1) | abgeleitet |
| polarisiert-80-20-10-wochen | VO2max/2000 m, 80/20 | Fortgeschritten | 10 | 4 (+1) | angepasst |
| pete-artig-24-wochen | halbes Jahr Aufbau, 2000 m | Fortgeschritten | 24 | 3 (+1) | angepasst |
| wettkampf-tapering-3-wochen | frisch zum Rennen | Leistung | 3 | 4 | direkt |

Grenzen der Umsetzung (offen benannt):
- Die Programme haben feste Längen. Feine Steigerungen (z. B. Pete: +500 m pro Woche) werden auf vorhandene Distanzen
  gerundet (5000 / 8000 / 10 000 m, 40 / 72 min).
- Marathon: Die längste Vorbereitungsfahrt ist der Halbmarathon statt 28–34 km bei Concept2, weil Programme über
  2–2,5 h fehlen (Vorschlag unten).
- Das kürzeste Einsteigerprogramm dauert 17 min (mit Ein- und Ausrudern); British Rowing beginnt mit 13–15 min.

### 3.1 Fehlende Programme (Vorschläge, nicht in plans.json eingetragen)
| Vorschlag (id) | Inhalt | Wozu | Quelle |
|---|---|---|---|
| `einsteiger-5x1-2x5` | 5 × 1 min locker / 1 min Pause und 2 × 5 min / 3 min, ohne langes Einrudern (≈ 15 min) | allererste Einheit | British Rowing Go Row Beginner, Woche 1 |
| `langdistanz-ut2-120` | 2 h UT2 in 4 Blöcken zu 30 min, Trinkpausen (≈ 24–26 km) | Marathonplan Wochen 9–13 | Concept2 Marathonplan |
| `langdistanz-ut2-150` | 2,5 h UT2 (≈ 30–32 km) | längste Marathon-Vorbereitung | Concept2 Marathonplan (Woche 11–12: 32–34 km) |
| `langdistanz-hmp-50` | 50 min am Stück im Halbmarathon- bzw. Marathontempo | HM-Woche 8, Marathon Woche 12 | Concept2 HM- und Marathonplan |
| `grundlage-locker-45` | 45 min UT2 am Stück | Lücke zwischen 40 und 60/72 min (Masters, Fitness) | Wolfson (60–90-min-Einheiten in 20–30-min-Blöcken) |
| `grundlage-distanz` (parametrisch) | Grundlage über frei wählbare Distanz 6000–12 000 m | Pete-Plan-Steigerung in 500-m-Schritten | Beginner Pete Plan |

## 4. Format von training_plans.json

Wie im Auftrag; zusätzlich (alle freiwillig, die App darf sie ignorieren):
- `rules.repeatFrom` (Zahl): offener Plan, läuft nach der letzten Woche ab dieser Woche weiter (fitness: 5, erhaltung: 1).
- `rules.repeatWeekIfMissed` (Zahl): Einsteigerpläne – fehlen so viele Pflicht-Einheiten einer Woche, wird die Woche
  wiederholt statt weitergegangen (NHS-Logik).
- `rules.interimTestWeek`: Woche mit Zwischentest (setzt neue Tempoziele, wie retestWeek).
- `weeks_detail[].taper: true`: Taper-Woche (weniger Umfang, Intensität bleibt).
- `sessions[].event: true`: Zieleinheit des Plans (Schlusstest oder Rennen); die App kann sie hervorheben und schiebt
  sie nie ersatzlos weg.
- `intensity` ist die Einstufung des Programms aus seinen Tags (easy/moderate/hard/max); das Prüfskript verlangt
  Gleichheit, damit Plan und App (`IntensityRules`) dieselbe Sprache sprechen.
- `minutesPerWeek`: kleinste Woche (Pflicht) bis grösste Woche (mit freiwilligen), Schätzung 2:00/500 m für Distanzen.

## 5. Regeln für die App

### 5.1 Einheiten auf Wunschtage verteilen
1. Der Nutzer wählt Wunschtage (z. B. Mo, Mi, Fr, Sa). Weniger Wunschtage als `sessionsPerWeek.min` → Plan nicht
   startbar, Hinweis auf einen Plan mit weniger Einheiten (z. B. erhaltung-2x). Mehr Wunschtage als Pflicht-Einheiten →
   freiwillige Einheiten auf die übrigen Tage, sonst Ruhetag.
2. Die Pflicht-Einheiten werden in der Reihenfolge der Slots auf die Wunschtage gelegt. Danach Prüfung:
   - zwei Einheiten mit `intensity` hard/max nie an aufeinanderfolgenden Tagen und nie mit weniger als
     `hardSessionsMinGapHours` Abstand (48 h, Masters 72 h) – auch über die Wochengrenze (letzte Einheit der Woche → erste
     der nächsten);
   - höchstens `maxConsecutiveDays` Trainingstage hintereinander (Einsteiger 1 = immer ein Ruhetag dazwischen);
   - Verletzt eine Zuordnung das, tauscht die App die harte Einheit mit der nächsten leichten Einheit derselben Woche.
     Geht das nicht, wird die harte Einheit auf den nächsten passenden Wunschtag geschoben oder durch ihre leichte
     Variante ersetzt (siehe 5.2).
   Belege: harte und leichte Tage im Wechsel und ≥ 48 h zwischen harten Reizen ist Konsens in den Plänen (Concept2,
   Pete Plan mit Ruhetag, Wolfson) und entspricht der Praxis der Elite (Seiler 2009) – **Praxis/mittel**; Ruhetag
   zwischen Einsteigereinheiten: NHS Couch to 5K – **Praxis**; 72 h bei Masters – **abgeleitet** (Fell & Williams 2008,
   Borges 2016, unsicher).

### 5.2 Verpasste Einheiten
1. Verschieben innerhalb der Woche, wenn ein freier Wunschtag (oder ein beliebiger freier Tag, falls der Nutzer das
   erlaubt) übrig ist und die Regeln aus 5.1 eingehalten bleiben.
2. Sonst je nach `missedSessionPolicy`:
   - `shift`: Einsteigerpläne und Pete-artig – die nächste Einheit rückt nach, die Woche wird ggf. um 1–2 Tage länger
     (höchstens bis zur nächsten Woche; dann gilt `skip`).
   - `replace-easy`: Leistungs-/Testpläne – ist der nächste freie Tag zu nah an einer harten Einheit, wird die verpasste
     harte Einheit durch eine leichte Grundlage ähnlicher Dauer ersetzt (z. B. Grundlage 3 × 10) oder gestrichen.
   - `skip`: Masters, Wiedereinstieg, Wettkampf – verpasste Einheit fällt weg, der Plan läuft nach Kalender weiter.
3. Immer gilt: nie zwei harte Einheiten nachholen, nie zwei Einheiten an einem Tag, die Zieleinheit (`event`) wird
   verschoben, nicht gestrichen. Einsteiger: fehlen `repeatWeekIfMissed` (2) Pflicht-Einheiten, wird die Woche
   wiederholt (NHS: „it's totally okay to repeat a week“).
   Belegstärke: **Praxis/abgeleitet**. Keine der Quellen (Concept2-Pläne, Pete Plan) regelt verpasste Einheiten
   ausdrücklich; die Regeln folgen aus 5.1 und der Taper-/Detraining-Literatur (eine verpasste Einheit kostet wenig,
   zwei harte Einheiten hintereinander erhöhen das Überlastungsrisiko).

### 5.3 Plan pausieren und Wiedereinstieg
- „Pausiert“ wird ein Plan, wenn der Nutzer ihn anhält oder 10 Tage keine Fahrt gezählt wurde (passt zu Regel 0 im
  Tagesvorschlag, die nach 7 Tagen auf „locker wieder einsteigen“ schaltet).
- Beim Fortsetzen nach Länge der Pause:
  | Pause | Vorgehen | Tempoziele |
  |---|---|---|
  | bis 7 Tage | dort weitermachen, erste Einheit leicht (harte Einheit der Woche durch leichte ersetzen) | unverändert |
  | 8–14 Tage | letzte vollständige Woche wiederholen (oder die nächste Deload-Woche vorziehen) | −1 bis −2 s/500 m |
  | 15–28 Tage | `wiedereinstieg-3-wochen` ab Woche 2 (bei 3–4 Wochen Pause ab Woche 1), dann im Plan eine Woche vor dem Stand bei der Pause einsteigen | −1 s/500 m pro Pausenwoche |
  | 29–56 Tage | ganzer `wiedereinstieg-3-wochen`, danach Plan ab Beginn des aktuellen Blocks (Woche nach der letzten Deload-Woche) | −1 s pro Woche, dann Retest |
  | über 8 Wochen | Plan neu starten (ggf. niedrigeres Niveau vorschlagen) | Retest |
  Belege: Mujika & Padilla 2000/2001 (VO2max-Verlust in < 4 Wochen deutlich, nach > 4 Wochen bei kurz Trainierten
  Zugewinne weg) – **mittel**; −1 s/500 m pro Pausenwoche: Pete Plan FAQ – **Praxis**; Schwellen 7/14/28/56 Tage –
  **abgeleitet**. Nach Krankheit mit Fieber: nur lockere Einheiten bis beschwerdefrei (Allgemeinwissen, ohne
  eigene Quelle).

### 5.4 Anpassung an die Bestzeit (Retest → Tempoziele)
- Die App rechnet Tempoziele aus der 2000-m-Bestzeit (`PaceTargets.basePace500(best2k:)` = best2k / 4; Programme haben
  `paceOffsetMinS/MaxS` relativ dazu). Jeder Test im Plan (`retestWeek`, `interimTestWeek`, Test-Programme) aktualisiert
  die Referenz: test-2000m direkt; test-1000m, test-5000m, einsteiger-test-10min über Paul's Law (+5 s/500 m pro
  Verdopplung der Strecke, Fundus fact 2436 – Faustregel, **Praxis**) bzw. World-Rowing-Leistungsverhältnisse (60 min
  ≈ 76 %, 6000 m ≈ 85 % der 2000-m-Watt, Fundus observation 22437 – **Praxis**).
- Langdistanzpläne (Halbmarathon, Marathon) nennen Tempi relativ zum 5000-m-Tempo wie Concept2 (UT2 +18–22 s,
  UT1 +14–18 s, HMP +8–12 s, MP +10–14 s, AT +6–10 s/500 m) – **Praxis**.
- Wird ein Test schlechter als die alte Referenz, nicht automatisch langsamer machen: Hinweis und Wahl („neue
  Referenz übernehmen?“), weil Tagesform und Einteilung stark streuen (**abgeleitet**).
- Pete-artig: Ziel jeder Intervalleinheit = Schnitt der letzten gleichen Einheit, gleich oder 1–2 s schneller (Beginner
  Pete Plan) – **Praxis**.

### 5.5 Anpassung nach Effort-Rückmeldung (RPE 1–10)
Die App speichert `WorkoutEffort.userScore` (1–10) und stuft ≥ 7 als hart, 4–6 als mittel ein
(`IntensityRules.level(effort:)`). Vorschlag:
1. Drei als leicht geplante Einheiten in Folge mit RPE ≥ 7 (oder zwei mit ≥ 9) → die nächste Woche wird zur leichteren
   Woche (Deload-Variante: harte Einheit kürzer, eine Einheit Regeneration), danach weiter im Plan; Hinweis „Erholung
   prüfen (Schlaf, Krankheit, Stress)“.
2. Zwei harte Einheiten in Folge mit RPE 10 und verfehlten Tempozielen (Schnitt > 2 s/500 m langsamer als Ziel) →
   Tempoziele um 1–2 s/500 m senken bis zum nächsten Test.
3. Drei harte Einheiten in Folge mit RPE ≤ 6 bei erreichten Zielen → Retest vorschlagen (Bestzeit vermutlich veraltet).
4. Nach einer Deload-Woche mit weiter hohem RPE bei leichten Einheiten → Plan pausieren und Wiedereinstieg vorschlagen.
Belege: Session-RPE ist eine gültige Messung der inneren Belastung und bildet die Intensitätsverteilung ähnlich ab wie
der Puls (Seiler & Kjerland 2006: 76/6/18 % per RPE vs. 75/8/17 % per Puls, Fundus study 1042; Validierung der
sRPE-Methode, Fundus fact 2421) – **mittel**. Die Schwellen (3×, ≥ 7, ≥ 9) sind **abgeleitet** und sollten nach den
ersten Nutzerdaten geprüft werden.

### 5.6 Verbindung zum Tagesvorschlag (`DailySuggestion.swift`)
Heute wählt der Tagesvorschlag nach sechs Regeln (0 Einstieg, 1 Erholung < 48 h, 2 genug hart, 3 zu wenig leicht,
4 2000-m-Test fällig, 5 harter Reiz). Mit aktivem Plan:
1. Neue Regel „plan“ vor Regel 2: Ist heute ein Plantag, schlägt die Karte die geplante Einheit vor („Woche 5 von 12,
   Einheit 2 von 3“). An Nicht-Plantagen: „Ruhetag laut Plan“ mit Alternative „Frei rudern“ bzw. der freiwilligen
   Einheit der Woche.
2. Sicherheitsregeln bleiben vorne: Regel 0 (≥ 7 Tage Pause) startet die Wiedereinstiegslogik aus 5.3; Regel 1 (harte
   oder mittlere Einheit vor < 48 h) gewinnt gegen eine harte Planeinheit – die Karte zeigt dann die leichte Variante
   und verschiebt die harte Einheit nach 5.2.
3. Regeln 2–5 entfallen, solange ein Plan aktiv ist (der Plan steuert Härte, Verteilung und Tests selbst); Regel 4
   (2000-m-Test) nur, wenn der Plan keinen eigenen Test hat (z. B. fitness- oder erhaltung-Pläne ab der zweiten Runde).
4. Alternativen auf der Karte: die leichte Ersatzeinheit (bei harter Planeinheit: Lockere Grundlage 30) und „Frei
   rudern“ wie bisher. Die Wahl einer Alternative zählt als verschobene, nicht als verpasste Einheit.
5. Das „80/20“-Ziel von Regel 3 (Leicht-Anteil < 75 % in 28 Tagen) bleibt als Hinweis sichtbar; alle Pläne liegen
   rechnerisch bei 75–85 % Zeit in Zone 1–2.

### 5.7 Saison
`season: "winter"` (grundlage-winter-12-wochen) empfiehlt die App auf der Nordhalbkugel von Oktober bis April, auf der
Südhalbkugel von April bis Oktober (Profil-Land). Grund: die Wintervorbereitung ist bei Ruderern die Phase mit dem
meisten Grundlagentraining (Fiskerstrand & Seiler 2004) – **mittel**.

## 6. Prüfskript

`python3 App/l10n/check_training_plans.py` prüft: gültiges JSON und Pflichtfelder, de/en-Texte (kein ß), jede planId in
plans.json, intensity = Einstufung des Programms, Wochenzahl = Länge von weeks_detail, Slots fortlaufend,
Pflicht-Einheiten in min..max (mit freiwilligen höchstens max), harte Einheiten nie in aufeinanderfolgenden Slots,
höchstens 2 harte Pflicht-Einheiten pro Woche (bei 72 h höchstens 1), Deload-Wochen ≥ 25 % unter der letzten normalen
Woche, Taper-Regeln (2.3), minutesPerWeek deckt die Schätzung ab, Warnung unter 70 % Zeit in Zone 1–2. Stand
26.11.2026: 17 Pläne, 0 Fehler, 0 Warnungen.

## 7. Quellen
- Bosquet L, Montpetit J, Arvisais D, Mujika I (2007): Effects of tapering on performance: a meta-analysis. Med Sci Sports Exerc 39(8):1358-1365. https://pubmed.ncbi.nlm.nih.gov/17762369/
- Borges N, Reaburn P, Driller M, Argus C (2016): Age-related changes in performance and recovery kinetics in masters athletes: a narrative review. J Aging Phys Act 24(1):149-157. https://researchcommons.waikato.ac.nz/entities/publication/43c52ed0-3e7e-4f32-98fa-ccd16580054b
- British Rowing (2016): Go Row Indoor – Beginner Training Plan. https://www.britishrowing.org/wp-content/uploads/2016/10/BR_Go_Row_A4_Beginners_Training_Plan_P3.pdf
- British Rowing (2019): How Much How Often. https://www.britishrowing.org/wp-content/uploads/2019/03/How-Much-How-Often-210219.pdf
- Concept2: Couch to Consistency; 2K 4-Week; 2K 12-Week; 5K Erg Test; Half Marathon Row; Marathon Row Training Plan. https://www.concept2.com/training/plans
- Fell J, Williams A (2008): The effect of aging on skeletal-muscle recovery from exercise. J Aging Phys Act 16(1):97-115. https://pubmed.ncbi.nlm.nih.gov/18268815/
- Fiskerstrand Å, Seiler KS (2004): Training and performance characteristics among Norwegian international rowers 1970-2001. Scand J Med Sci Sports 14(5):303-310. https://pubmed.ncbi.nlm.nih.gov/15387804/
- Garber CE et al. (2011): ACSM Position Stand: Quantity and quality of exercise … Med Sci Sports Exerc 43(7):1334-1359. https://pubmed.ncbi.nlm.nih.gov/21694556/
- Güllich A, Seiler S, Emrich E (2009): Training methods and intensity distribution of young world-class rowers. Int J Sports Physiol Perform 4(4):448-460. https://pubmed.ncbi.nlm.nih.gov/20029096/
- Issurin VB (2010): New horizons for the methodology and physiology of training periodization. Sports Med 40(3):189-206. https://pubmed.ncbi.nlm.nih.gov/20199119/
- Mujika I, Padilla S (2000): Detraining … Part I: short term insufficient training stimulus. Sports Med 30(2):79-87. https://pubmed.ncbi.nlm.nih.gov/10966148/
- Mujika I, Padilla S (2001): Cardiorespiratory and metabolic characteristics of detraining in humans. Med Sci Sports Exerc 33(3):413-421. https://pubmed.ncbi.nlm.nih.gov/11252068/
- NHS: Couch to 5K running plan. https://www.nhs.uk/better-health/get-active/get-running-with-couch-to-5k/couch-to-5k-running-plan
- Pete Marston: The Pete Plan; Beginner Pete Plan. https://thepeteplan.wordpress.com/the-pete-plan/ · https://thepeteplan.wordpress.com/beginner-training/
- Seiler KS, Kjerland GØ (2006): Quantifying training intensity distribution in elite endurance athletes. Scand J Med Sci Sports 16:49-56. https://pubmed.ncbi.nlm.nih.gov/16430681/
- Seiler S, Tønnessen E (2009): Intervals, thresholds, and long slow distance. Sportscience 13:32-53. https://sportsci.org/2009/ss.htm
- Spiering BA, Mujika I, Sharp MA, Foulis SA (2021): Maintaining physical performance: the minimal dose of exercise … J Strength Cond Res 35(5):1449-1458. https://pubmed.ncbi.nlm.nih.gov/33629972/
- Stöggl T, Sperlich B (2014): Polarized training has greater impact on key endurance variables … Front Physiol 5:33. https://doi.org/10.3389/fphys.2014.00033
- Treff G et al. (2017): Eleven-week preparation involving polarized intensity distribution is not superior to pyramidal distribution in national elite rowers. Front Physiol 8:515. https://doi.org/10.3389/fphys.2017.00515
- Wolfson College Boat Club (2019): Erging (training guide). https://www.wolfson.cam.ac.uk/sites/default/files/2019-11/wcbc_erging_0.pdf
