# Sprachcoach: fachliche Grundlage und Parameter-Empfehlungen (Recherche, Stand 26.11.2026)

Zweck: Belege und Empfehlungen für den adaptiven Sprachcoach (docs/coach/SPEC.md, `CoachConfig.swift`).
Abschnitt 4 nennt die Parameter in der Form „heute | empfohlen“. Abschnitt 5 sammelt typische Rufe als Anregung für
`coach_phrases.json`.

**Vorgehen und Belegstärke.** In Zotero (`zrag search`) gab es zu keinem der Themen einen Treffer: nur unpassende
Transkript-Notizen. `zrag semantic` brach mit einem Serverfehler ab. In Fundus lagen zum Thema `endurance-training`
nur Trainingsplanung und Intensitätszonen (Seiler, Concept2), aber nichts zu Coaching-Sprache. Deshalb kommen alle
Belege aus dem Web. Studienergebnisse sind an den Abstracts geprüft (Europe PMC, Crossref). Die Volltexte
lagen nicht vor, deshalb gibt es keine Seitenangaben über die Seitenspanne des Artikels hinaus.

Belegstärke in den Tabellen:
- **A**: Meta-Analyse oder mehrere Experimente in dieselbe Richtung.
- **B**: einzelne kontrollierte Studie(n), kleine Stichproben.
- **C**: Praxiswissen (Steuerleute- und Trainerhandbücher, Produktdokumentation) oder eigene Ableitung.

---

## 1. Befunde aus der Forschung

### 1.1 Verbale Ermutigung wirkt, vor allem wenn sie häufig kommt und bei Untrainierten
- **Häufigkeit entscheidet.** Andreacci et al. (2002) liessen 28 Personen einen Laufband-Maximaltest machen.
  Ermutigt wurde ab Stufe 3 alle 20 s, alle 60 s oder alle 180 s, die Kontrollgruppe gar nicht. Nur bei 20 s und
  bei 60 s stiegen VO2max, Laktat, RER und RPE gegenüber dem Vortest ohne Ermutigung. Die 20-s-Gruppe hielt auch
  länger durch (P < 0,0001). Bei 180 s und ohne Ermutigung änderte sich nichts. Schluss der Autoren: Ermutigung
  mindestens einmal pro Minute, wahrscheinlich öfter. *J Sports Sci* 20:345–352,
  doi:10.1080/026404102753576125. **B** (n = 28, aber klare Dosis-Wirkung)
- **Untrainierte profitieren mehr.** Moffatt et al. (1994) verglichen Laufband-Maximaltests mit und ohne Ermutigung.
  Bei 14 Untrainierten stiegen VO2max (44,9 vs. 42,8 ml/kg/min), Laufzeit (14,3 vs. 12,4 min), Maximalpuls und
  Laktat. Bei 14 Wettkampfläufern blieben VO2max und Laktat gleich, Laufzeit und Maximalpuls stiegen trotzdem.
  *J Sports Med Phys Fitness* 34:45–49, PMID 7934010. **B**
- **Auch bei selbst eingeteilter Ausdauer.** Edwards et al. (2018) liessen 12 aktive Untrainierte 20 min auf dem
  Rad fahren und 2 × 30 s sprinten. Mit Ermutigung von aussen stieg die mittlere Leistung
  (F(1,11) = 15,37, p = 0,002, ηp² = 0,58). Auch die Lust auf Training am nächsten Tag stieg (p = 0,04).
  *BMJ Open Sport Exerc Med* 4:e000368, doi:10.1136/bmjsem-2018-000368. **B**
- **Gegenbefund bei Erfahrenen.** Engel et al. (2019) testeten 19 erfahrene Athletinnen und Athleten. Ermutigung
  brachte im 1RM-Squat nur +2 kg (d = 0,06) und im 12-min-Ausdauer-Workout keinen Unterschied (182 vs. 181
  Wiederholungen, d = 0,03). Die Ergebnisse streuten mit Ermutigung aber weniger von Tag zu Tag.
  *Front Physiol* 10:460, doi:10.3389/fphys.2019.00460. **B**
- **Übersicht.** Ketelhut et al. (2025) werteten in einem Scoping Review 49 Studien zu Maximaltests aus. Ihr
  Ergebnis: „Verbal encouragement, particularly when frequent and personalized, generally enhanced performance“.
  Motivationale Selbstgespräche und Wettkampfbedingungen wirkten ebenfalls positiv. Musik wirkte in Tests ohne
  festes Ende zuverlässig, in Tests mit festem Ende uneinheitlich. *IJSPP* 20:1319–1330,
  doi:10.1123/ijspp.2025-0086. **A–B** (Scoping Review, keine Effektgrössen)
- **Ermutigung ist ein echter Einflussfaktor.** Halperin, Pyne & Martin (2015) zählen „volume and frequency of
  verbal encouragement“ und „knowledge of exercise endpoint“ zu den Störgrössen, die Leistungstests messbar
  verändern. *IJSPP* 10:823–829, doi:10.1123/ijspp.2014-0566. **B** (Review)

**Folgerung für RowCoach:** In harten Phasen und Tests lohnen sich Rufe etwa alle 20–60 s. Seltener als alle 3 min
hat für die Leistung keine nachgewiesene Wirkung. Falk rudert als Freizeitsportler: Der Effekt dürfte zwischen dem
bei Untrainierten und dem bei Erfahrenen liegen.

### 1.2 Motivationale und instruktionale Selbstgespräche
- **Meta-Analyse.** Hatzigeorgiadis et al. (2011): 32 Studien mit 62 Effektgrössen, mittlerer positiver Effekt
  ES = 0,48. Instruktionale Sätze („Beine zuerst“) wirken besser bei feinmotorischen und neuen Aufgaben.
  Motivationale Sätze passen eher zu grobmotorischen, kraft- und ausdauerbetonten Aufgaben wie dem Ergometer-
  Rudern. *Perspect Psychol Sci* 6:348–356, doi:10.1177/1745691611413136. **A**
- **Weniger empfundene Anstrengung.** Blanchfield et al. (2014) gaben 24 Personen zwei Wochen Training in
  motivationalen Selbstgesprächen. Danach stieg die Zeit bis zur Erschöpfung bei 80 % der Spitzenleistung auf dem
  Rad von 637 auf 750 s. Die Kontrollgruppe blieb gleich (486 → 474 s). Die RPE bei halber Zeit sank von 7,3 auf
  6,4. *Med Sci Sports Exerc* 46:998–1007, doi:10.1249/MSS.0000000000000184. **B**

**Folgerung:** In der Belastung motivieren statt instruieren. Technik gehört in ruhige Phasen. Ein Coach-Ruf, den
man sich selbst nachsprechen kann („Dranbleiben!“), wirkt wie motivationales Selbstgespräch.

### 1.3 Wie oft Rückmeldung? Guidance-Hypothese und Feedback-Forschung
- **Für das Lernen ist weniger mehr.** Winstein & Schmidt (1990): Rückmeldung nach 50 % der Versuche führte zu
  besserem Behalten als Rückmeldung nach jedem Versuch. Die Guidance-Hypothese erklärt das so: Zu häufige
  Rückmeldung macht abhängig. *J Exp Psychol Learn Mem Cogn* 16:677–691, doi:10.1037/0278-7393.16.4.677. **A**
  (oft repliziert, z. B. Chiviacowsky et al. 2010, doi:10.3389/fpsyg.2010.00226. Es gibt auch Nullbefunde.)
  Geprüft nur über Sekundärquellen, der Abstract war nicht zugänglich.
- **Feedback kann schaden.** Kluger & DeNisi (1996) werteten 607 Effektgrössen aus, 23 663 Beobachtungen. Im
  Mittel verbesserte Rückmeldung die Leistung (d = 0,41), aber in über einem Drittel der Fälle verschlechterte sie
  sie. Die Wirkung sinkt, je mehr die Rückmeldung die Aufmerksamkeit von der Aufgabe weg auf die eigene Person
  lenkt. *Psychol Bull* 119:254–284, doi:10.1037/0033-2909.119.2.254. **A**

**Folgerung:** Technikimpulse selten geben (alle 4–7 min) und nicht wiederholen. Korrekturen beziehen sich auf die
Aufgabe („Schlagzahl 26 halten“), nie auf die Person („du bist zu schwach“). Lieber eine Korrektur weniger als eine
zu viel.

### 1.4 Grenzbereich: wenig Platz im Kopf
- Hutchinson & Tenenbaum (2007): Bei hoher Intensität richtet sich die Aufmerksamkeit fast nur noch nach innen,
  auf Atmung und Muskeln (assoziativ). Ablenkende Strategien greifen dann kaum. *Psychol Sport Exerc* 8:233–245,
  doi:10.1016/j.psychsport.2006.03.006. **B** (Abstract nur aus Sekundärquellen)
- Bei Steuerleuten heisst es ebenso: „In the sprint, keep calls especially clear and simple“ (Colburn 2002, row2k).
  **C**

**Folgerung:** Im letzten Drittel harter Phasen nur Rufe mit höchstens 4–6 Wörtern und ohne Zahlenkette. Eine Zahl
geht („Noch zehn!“), zwei Zahlen nicht.

### 1.5 Endspurt, Pacing und Abflachen
- **Pacing auf dem Ergometer.** Garland (2005) wertete 948 Rennprofile über 2000 m aus. Auf dem Ergometer lagen die
  500-m-Abschnitte im Mittel bei 101,5 / 99,8 / 99,0 / 99,7 % der Durchschnittsgeschwindigkeit: schneller Start,
  flache Mitte, leichter Endspurt. *Br J Sports Med* 39:39–42, doi:10.1136/bjsm.2003.010801. **A** (grosse
  Stichprobe, beobachtend)
  → Eine gute Einteilung schwankt in der Mitte nur um etwa 1 % der Geschwindigkeit. Bei 2:00/500 m sind das
  rund 1,2 s/500 m. Ein Tempoverlust von ≥ 2,5 s/500 m (≈ 2 %) ist also echtes Abflachen und kein normales
  Pacing.
- **Messgenauigkeit.** Soper & Hume (2004): Der Messfehler der mittleren Leistung über 2000 m auf dem Concept2
  liegt bei 1,3 % (%SEM), über 500 m bei 2,8 %. *Sports Biomech* 3:237–248, doi:10.1080/14763140408522843.
  Weil die Leistung mit der dritten Potenz der Geschwindigkeit wächst, entspricht 1,3 % Leistung etwa 0,4 %
  Tempo. **B**
- **Das Ende vor Augen.** Emanuel (2019) erklärt den Endspurt mit „perceived impact“: Je näher das Ziel, desto mehr
  bewirkt jeder Schlag am verbleibenden Rest, und desto höher steigt die Motivation. *Front Psychol* 10:1082,
  doi:10.3389/fpsyg.2019.01082. **C** (Theorie, Simulation)
- Im Rennen kommen die Athletinnen und Athleten „irgendwann an den Punkt, wo eigentlich nichts mehr geht, das
  Rennen aber meistens trotzdem noch mindestens 350 Meter läuft“. Dort helfen die bekannten Trigger der Mannschaft
  (Wiesen 2025, DRV, rudern.de/media/162973/download, PDF-S. 14). **C**

**Folgerung:** Die Restzeit ausdrücklich nennen („Noch 30 Sekunden“, „Noch zehn“), weil das Wissen um das Ende den
Endspurt auslöst. Abflachen im letzten Drittel ist der Moment, in dem ein Ruf am meisten bringt.

### 1.6 Ton: autonomieunterstützend, Anstrengung loben, positiv
- **Selbstbestimmungstheorie.** Mageau & Vallerand (2003): Ein Coach stärkt die innere Motivation, wenn er
  Autonomie unterstützt (Wahl lassen, begründen, Gefühle anerkennen), Struktur gibt und sich zuwendet. Das deckt
  die Bedürfnisse nach Autonomie, Kompetenz und Zugehörigkeit. *J Sports Sci* 21:883–904,
  doi:10.1080/0264041031000140374. **B** (Modell)
- **Wahl lassen statt befehlen.** Hooyman, Wulf & Lewthwaite (2014): Instruktionen mit Wahlmöglichkeit („du kannst
  …“) führten zu mehr Selbstwirksamkeit, besserer Stimmung und besserem Lernen als kontrollierende Sprache („du
  musst …“). *Hum Mov Sci* 36:190–198, doi:10.1016/j.humov.2014.04.005. **B**
- **Anstrengung loben, nicht Begabung.** Mueller & Dweck (1998) zeigten in sechs Studien mit Kindern: Wer für
  Begabung gelobt wird, hält nach Misserfolg weniger durch und leistet schlechter als jemand, der für Anstrengung
  gelobt wird. *J Pers Soc Psychol* 75:33–52, doi:10.1037/0022-3514.75.1.33. **B** (Kinder, Lernaufgaben)
- **SDT und Bewegung.** Teixeira et al. (2012): In 66 Studien hängt eigenständige Motivation positiv mit Bewegung
  zusammen. *IJBNPA* 9:78, doi:10.1186/1479-5868-9-78. Liegt schon in Fundus. **A**
- **Abwertendes Anschreien wirkt selten.** Colburn (2002, row2k) nennt es „negacoxing“. Das Wolfson-Handbuch
  verwirft „make them cry“ als Grenzüberschreitung. **C**

**Folgerung:** Der Stil `cox` darf fordern, aber nicht kontrollieren oder abwerten. Am Ende einer Belastung die
Anstrengung oder das Halten loben („Stark gehalten!“), nicht Talent („Du bist ein Naturtalent“). Wo ein Satz
begründet, die Wirkung nennen („… dann kommt die Zeit von allein“).

---

## 2. Wie Steuerleute und Trainer rufen (Praxis, Belegstärke C)

**Aufbau eines guten Rufs.**
1. **Information + Emotion.** Lage melden (Position, Rest, Wert) und dazu eine klare, ruhige und sichere Stimme
   (Colburn 2002). Ein Beispiel: „Alright, we're at the 750; we've got a half length lead …; let's build on it.“
2. **Ein Zweck je Ruf.** Ein blosses „Power 10“ ändert wenig. Besser „gimme 10 for …“ mit einem Ziel, zum Beispiel
   Beine oder Abstand (Wolfson-Handbuch, Concept2 AU „What is a Power Ten?“).
3. **Im Rhythmus.** Rufe auf den Schlag legen, zum Beispiel „Zack“ bei jedem Setzen in der vorderen Umkehr (Wiesen
   2025, PDF-S. 12) oder „SHARP! SEND! Controool…“ (Wolfson). Beim Herunternehmen der Schlagzahl mit
   ruhiger, langer Stimme rufen.
4. **Bilder statt Begriffe.** Wörter wie „slice“ oder „crisp“ erzeugen ein Bild vom guten Einsatz (Wolfson).
5. **Notrufe sparsam.** „I need ratio NOW!“ ist „best used as an ‚emergency' call, don't overuse it“ (Wolfson).
   Nicht jeder Ruf braucht ein Ausrufezeichen. Tonfall und Timing zählen mehr als das Wort.
6. **Eskalation.** Erst informieren, dann fordern, ganz am Ende emotional („three good strokes can win it“). Wer
   hinten liegt, hört Ermutigendes über die verbleibende Strecke (Colburn).
7. **Vermeiden:** Schreien ohne Inhalt, Abwertung, Drohung, Panik. Vor dem Rennen beruhigen statt aufheizen (Wiesen
   2025, PDF-S. 13: „Sicherheit ausstrahlen“).

**Deutsche Rudersprache.** Ein Kommando hat einen Ankündigungs- und einen Ausführungsteil mit kurzer Pause
dazwischen („Alles vorwärts – los!“). Quelle: Hessisches Lernarchiv, Ruderbefehle. Für die Rufe gilt
docs/coach/PHRASES.md (eigenständiges Deutsch, keine Lehnübersetzung).

---

## 3. Digitale Vorbilder (Belegstärke C, Produktseiten)

| Produkt | Was gesprochen wird | Adaptiv? |
|---|---|---|
| Peloton Row / Row+ | Live- und aufgezeichnete Kurse mit Instruktoren, die Schlagzahl und Tempo-Stufen ansagen (easy/moderate/challenging/max). Dazu Form Assist: Rückmeldung zur Technik je Schlag aus Sensoren, inzwischen „powered by Peloton IQ“ | Die Instruktoren-Ansagen sind vorproduziert. Form Assist reagiert in Echtzeit, aber nur auf die Technik ([Peloton Row features](https://www.onepeloton.com/blog/peloton-row-features-explained), [Row+](https://www.onepeloton.com/row-plus)) |
| Apple Watch Workout Buddy | Ermutigung „based on real-time analysis of your fitness history“, Meilensteine (Ringe, Bestzeiten), Zusammenfassung am Ende. Braucht Apple Intelligence, Kopfhörer und Englisch oder Spanisch, lässt sich stummschalten | Ja, generativ, nicht algorithmisch ([Apple Watch User Guide](https://support.apple.com/en-ae/guide/watch/apd65c7938e6/watchos)) |
| Garmin | Audio Prompts für Runde, Pace, Herzfrequenz, Leistung, Timer-Start/Stopp. Die Musik wird für die Ansage leiser gestellt | Regelbasiert: feste Intervalle und Alarme bei Zielabweichung, keine Motivation ([Garmin Manual](https://www8.garmin.com/manuals/webhelp/forerunner945/EN-US/GUID-4FD1E429-DE3B-4A8F-870B-82D8C482B20E.html)) |
| Nike Run Club Audio Guided Runs | Coach Bennett meldet sich „intermittently“ bei bestimmten Distanzen, Läufe als Studioaufnahme | Vorproduziert, ausgelöst nach Zeit und Distanz ([NPR 2023](https://www.npr.org/2023/11/04/1210678199), [Nike](https://www.nike.com/au/running/guided-runs/get-started)) |
| Hydrow | Über 5000 Workouts, die Spitzenathletinnen und -athleten auf dem Wasser filmen und kommentieren | Vorproduziert ([App Store](https://apps.apple.com/us/app/hydrow/id1458653991)) |
| Aviron | Spiele und Wettkämpfe, dazu Kurse mit Coach | Spielmechanik adaptiv, Coach vorproduziert ([Garage Gym Reviews](https://www.garagegymreviews.com/aviron-app-review)) |
| Concept2 ErgData | Zeigt Werte in Echtzeit, plant Intervalle und lädt ins Logbuch. Keine Sprachansagen belegt | – ([App Store](https://apps.apple.com/gb/app/ergdata/id561716382)) |
| CrewNerd, RowIQLive | Hörbare Rückmeldung zu Ziel-Schlagzahl oder Pulszone, RowIQLive mit Tönen bei erreichtem Ziel | Regelbasiert ([CrewNerd](https://apps.apple.com/app/id307935199)) |

Nicht geprüft: EXR, ErgZone (Sprachfunktionen), Zwift, Polar, Runtastic, Strava. Nach dem Absturz gab es keine
Zeit für weitere Abrufe.

**Lehren:** (1) Die grossen Anbieter trennen Information (Uhr: Runde, Pace) von Motivation (vorproduzierter
Trainer). RowCoach verbindet beides über die Messwerte, darin liegt der Unterschied. (2) Vorproduzierte Trainer
sprechen selten und nur bei Meilensteinen. (3) Echtzeit-Adaptivität gibt es bisher nur für Technik (Peloton) oder
generativ (Apple). Ein regelbasierter Coach, der auf Abflachen reagiert, besetzt eine Lücke. (4) Jede Ansage muss
abschaltbar sein und die Musik ducken.

---

## 4. Empfehlungen für `CoachConfig`

### 4.1 Die gefragten Punkte

| Parameter in CoachConfig | heute | empfohlen | Begründung | Quelle (Stärke) |
|---|---|---|---|---|
| **Dichte in der letzten Minute harter Intervalle**: kein eigener Parameter, `endPush` ist vom Budget ausgenommen | bis 5 Rufe in 60 s (`workout_final`, `last_30s`, `fade_end` 1, `fade_end` 2, `last_10s`) | **neu `endPushPerMinute` = [low: 2, normal: 3, high: 4]**, ohne Info und Töne. Dazu `workout_final` nicht im selben 60-s-Fenster wie `last_30s`: der erste gewinnt, oder `workout_final` ganz in die Ansage zum Start des letzten Intervalls legen. `fade_end` ersetzt `last_30s`, wenn beide innerhalb von 12 s fällig wären. `fade_end` Stufe 2 nur bei ≥ 15 s Rest | Etwa alle 20 s (3/min) ist die wirksamste geprüfte Dichte. Mehr bringt nichts Belegtes, kostet aber Aufmerksamkeit im Grenzbereich, wo nur noch kurze Rufe ankommen. Steuerleute rufen im Spurt viel, aber „clear and simple“. Bei `high`/`cox` sind 4 vertretbar | Andreacci 2002 (B); Hutchinson & Tenenbaum 2007 (B); Colburn 2002 (C); Kluger & DeNisi 1996 (A) |
| `minGap` | 12 s | **12 s beibehalten**. Optional in den letzten 60 s harter Phasen 10 s erlauben, aber nur bei `high` | Eine Ansage dauert mit bis zu 6 Wörtern etwa 2–3 s, dazu 9–10 s Ruhe, also etwa 4–5 Atemzüge bei hoher Belastung. Das liegt unter dem 20-s-Takt von Andreacci und lässt Platz für Info-Ansagen. Kürzer wirkt bei vorproduzierten Rufen schnell wie Dauerbeschallung | Andreacci 2002 (B); eigene Ableitung (C) |
| `cooldownByCategory[.praise]` | 90 s | **90 s beibehalten**. Je Belastungsphase höchstens 1 Lob mitten in der Phase plus die Rückmeldung am Ende | Häufiges, unspezifisches Lob nutzt sich ab. Lob soll an eine Leistung gebunden sein („Tempo hält“) und die Anstrengung oder das Halten loben | Mueller & Dweck 1998 (B); Kluger & DeNisi 1996 (A) |
| `easyPraiseCooldown` | 360 s | **360 s beibehalten** | In der Grundlage zählt Durchhalten, nicht maximale Leistung. Die SPEC sieht höchstens etwa 1 Motivation je 3 min vor | SPEC; Teixeira 2012 (A, indirekt) |
| `easyInterval` (Grundlage-Budget) | 360 / 180 / 120 s | **beibehalten** (normal 180 s). Technikimpulse (`techniqueInterval` 240–420 s) zählen mit ins Budget, nicht zusätzlich | Bei 180 s zeigte Andreacci keine Leistungswirkung. Das stört nicht, denn in der Grundlage ist das Ziel Gleichmass und Technik, nicht Ausbelastung. Für Technik spricht die Guidance-Hypothese für seltene Rückmeldung | Andreacci 2002 (B); Winstein & Schmidt 1990 (A); Seiler & Tønnessen 2009 (in Fundus) |
| `last10ReplacesCountdown` | true | **true nur, wenn jede `last_10s`-Variante die Restzeit nennt** („zehn“/„ten“). Die Töne 3-2-1 bleiben immer. Heute fehlt die Zeitangabe in 15 von 60 Varianten (z. B. „Gleich geschafft!“, „Final strokes!“, „Jetzt! Alles raus!“). Diese entweder umschreiben („Noch zehn – alles raus!“) oder für `last_10s` sperren. Bis das erledigt ist: **false** | Das Wissen um das Ende verändert die Leistung messbar und löst den Endspurt aus. Die Countdown-Ansage ist Information, und Information hat im Planer Vorrang vor Motivation. Ein reiner Motivationsruf ohne Zeitangabe nimmt diese Information weg | Halperin et al. 2015 (B); Emanuel 2019 (C); Garland 2005 (A) |

### 4.2 Weitere Parameter

| Parameter in CoachConfig | heute | empfohlen | Begründung | Quelle (Stärke) |
|---|---|---|---|---|
| `budgetPerMinute` | 1 / 2 / 3 | **beibehalten**. Für Tests (2k, 6k, Zeitfahren), falls die Engine sie erkennt: normal 3/min in der zweiten Hälfte, sonst nur Pacing-Info | Wirksam ist eine Dichte von ≥ 1/min. In Tests ist maximale Leistung das Ziel | Andreacci 2002 (B); Ketelhut 2025 (A–B) |
| `fadeRateDrop` | 2 /min | **2 beibehalten** | ±1/min ist normale Schwankung, ein Abfall um 2 auf das kurze Mittel ist deutlich | eigene Ableitung (C) |
| `fadePaceDrop` | 2,5 s/500 m | **2,5 s beibehalten**, besser **relativ: 2 % des Phasenmittels** (2,4 s bei 2:00, 3,0 s bei 2:30) | Eine gute Einteilung schwankt in der Mitte um etwa 1 % Geschwindigkeit (≈ 1,2 s bei 2:00). 2 % liegen sicher darüber. Bei langsamem Tempo wären feste 2,5 s zu empfindlich | Garland 2005 (A); Soper & Hume 2004 (B) |
| `fadeHold` + `smoothingTau` | 4 s + 4 s | **beibehalten**. Zusammen ergibt das etwa 6–8 s Verzögerung, gut 3 Schläge bei Schlagzahl 30. Kürzer gibt Fehlalarme durch einzelne Schläge, länger kommt für die letzten 30 s zu spät | eigene Ableitung (C) | – |
| `escalationDelay` | 10 s | **12 s** (= `minGap`), Stufe 2 nur bei ≥ 15 s Rest | Stufe 2 knapp vor `last_10s` stapelt sonst drei Rufe | Kluger & DeNisi 1996 (A, indirekt) |
| `paceSlowTolerance` / `paceSlowHold` | 1 s / 15 s | **2 s / 20 s** | 1 s liegt im Bereich normaler Pacing-Schwankung (≈ 1,2 s) und erzeugt sonst Korrekturen ohne Grund | Garland 2005 (A); Kluger & DeNisi 1996 (A) |
| `rateTolerance` / `rateHold` | 1 / 6 s | Toleranz 1 beibehalten, **`rateHold` 8 s** (in harten Phasen 6 s lassen) | In längeren mittleren Phasen sind kurze Ausreisser normal. Jede unnötige Korrektur lenkt ab | C |
| `maxCorrectionsPerPhase` | 3 | **2** für dasselbe Szenario. Nach der zweiten Korrektur lieber ein Lob, sobald es wieder passt | Rückmeldung schadet in über ⅓ der Fälle, besonders wenn sie sich wiederholt und auf die Person zielt | Kluger & DeNisi 1996 (A) |
| `phraseHistory` | 3 | **5** (bei 10 Varianten), mindestens die halbe Liste | Wiederholte Rufe nutzen sich ab. Steuerleute wechseln die Rufe und stimmen sie auf die Mannschaft ab | Colburn 2002 (C) |
| `techniqueInterval` / `techniqueFirstAfter` | 240–420 s / 180 s | **beibehalten**. Inhalt mit äusserem Fokus (Boot, Stemmbrett, Griff) statt Körperteilen | Seltene Rückmeldung fördert das Lernen. Äusserer Fokus schlägt inneren Fokus | Winstein & Schmidt 1990 (A); Wulf & Lewthwaite 2016, doi:10.3758/s13423-015-0999-9 (A) |
| `settleTime` | 15 s | **beibehalten**. Bei Phasen ≥ 3 min 20 s | Die ersten Schläge brauchen Zeit, bis sich der Rhythmus einstellt | C |
| `onTargetHold` | 45 s | **beibehalten** | Das Lob soll verdient sein. Es kommt ohnehin höchstens einmal je Phase (siehe Lob-Abklingzeit) | C |
| neu: Wortlimit für Rufe am Ende harter Phasen | – (PHRASES.md: Rufe ≤ 6 Wörter) | **≤ 4 Wörter in den letzten 60 s harter Phasen** bevorzugen (Auswahl, keine neue Regel nötig) | Im Grenzbereich ist die Aufmerksamkeit nach innen gerichtet. Kurze Rufe kommen an, Sätze nicht | Hutchinson & Tenenbaum 2007 (B); Colburn 2002 (C) |

**Wann schweigen:** in den letzten 4 s vor einem Wechsel (heute so). Bei ≥ 90 % der Phasenzeit keine Korrektur
mit Zahl, nur noch Rufe. In Pausen nach `rest_recover` nichts bis `rest_prepare`. Nie zwei Korrekturen
hintereinander ohne ein Lob oder eine Info dazwischen.

---

## 5. Typische Rufe nach Szenario (Anregung für coach_phrases.json)

Englisch aus den Steuerleute-Handbüchern (Wolfson College BC, row2k). Deutsch ist Trainer- und Steuerleute-Praxis
(nicht belegt, Ergänzung zu PHRASES.md).

| Szenario | Deutsch | Englisch |
|---|---|---|
| `prep_hard` | „Gleich vier Minuten. Ruhig atmen, Griff fest.“ · „Gleich geht's los – lang anfangen, dann aufbauen.“ | “Next piece: four minutes. Settle, breathe, sit tall.” |
| `go` | „Los!“ · „Jetzt!“ · „Und – ab!“ | “Go!” · “Attack!” · “Here we go!” |
| `first_strokes` | „Rhythmus finden.“ · „Lang bleiben, nicht überziehen.“ · „Ruhig nach vorne.“ | “Find your rhythm.” · “Long and strong!” · “Calm on the slide.” |
| `phase_half` | „Halbzeit – du liegst gut.“ · „Halbzeit, dranbleiben.“ | “Halfway – right on it.” · “Halfway, hold it here.” |
| `last_quarter` | „Letztes Viertel – jetzt aufbauen.“ · „Jeder Schlag zählt.“ | “Last quarter, build it!” · “Make every stroke count!” |
| `last_30s` | „Noch dreissig – Beine!“ · „Dreissig Sekunden, alles rein.“ | “Thirty to go – legs!” · “Empty the tank!” |
| `last_10s` | „Noch zehn – alles raus!“ · „Zehn, zieh durch!“ (immer mit Zeitangabe) | “Ten seconds – send it!” · “Last ten, empty it!” |
| `fade_end` 1 | „Halt die Frequenz!“ · „Beine, Beine!“ · „Nicht nachlassen!“ | “Hold the rate!” · “Stay with it!” · “Legs!” |
| `fade_end` 2 | „Beissen – das noch!“ · „Jetzt nochmal alles!“ · „Durchziehen!“ | “Dig in – this one!” · “Show me you want it!” · “No passengers!” |
| `rate_low` | „Frequenz zwei hoch.“ · „Hände schnell weg.“ | “Up two in two – up one, up two!” · “Quick hands!” |
| `rate_high` | „Ruhiger, mehr Druck pro Schlag.“ · „Lang machen.“ | “Lengthen it out.” · “Calm on the slide, power on the drive.” |
| `pace_on_target` | „Genau so.“ · „Tempo sitzt.“ | “Yeah, just like that!” · “Looking good, keep it there.” |
| `strong_finish` | „Stark raus!“ · „So endet man ein Intervall.“ | “Strong finish!” · “That's how you close it!” |
| `interval_done` | „Stark gehalten.“ · „Sauber durchgezogen – jetzt erholen.“ | “Well held.” · “Good work – recover now.” |
| `rest_recover` | „Tief atmen, locker rudern.“ · „Schultern locker, trinken.“ | “Breathe, easy strokes.” · “Shake it out.” |
| `technique` | „Erst Beine, dann Körper, dann Arme.“ · „Drück das Stemmbrett weg.“ · „Lass das Boot laufen.“ | “Legs, body, arms.” · “Push the footplate away.” · “Let it run.” |
| `stopped` | „Weiter – dranbleiben!“ | “Back on it!” |

---

## 6. Do / Don't für den Ton

| Do | Don't |
|---|---|
| Anstrengung und Halten loben („Stark gehalten!“) | Begabung loben („Naturtalent!“) oder Wert über die Person urteilen |
| Aufgabe benennen: Schlagzahl, Beine, Rest | Person kritisieren („Du bist zu schwach“), Schmerz verherrlichen („Schmerz ist Schwäche …“) |
| Restzeit oder Reststrecke nennen | Endlose Anfeuerung ohne Information |
| Kurz im Grenzbereich (≤ 4–6 Wörter, eine Zahl) | Zahlenketten oder zwei Anweisungen in einem Satz in harten Phasen |
| Fordernd und sicher im Stil `cox` („Beissen – das noch!“) | Kontrollierend oder drohend („Du musst!“, „Sonst …“) und „negacoxing“ |
| Wahl lassen und begründen in Vorbereitung und Technik („Wenn du willst, lang anfangen“) | Befehlston in ruhigen Phasen |
| Variieren (Historie ≥ 5) und an echte Werte binden | Dieselben Rufe im Minutentakt, Lob ohne Anlass |
| Schweigen, wenn alles passt (Grundlage) | Sprechen, nur weil das Budget es erlaubt |

---

## 7. Fundus

Zurückgeschrieben (project `rowcoach`, Tag `endurance-training`): Moffatt et al. 1994 (study 1048, verifiziert).
Weitere Einträge (Andreacci, Edwards, Engel u. a.) hat die Berechtigungsprüfung abgelehnt. Sie stehen hier mit DOI
und können nachgetragen werden.
