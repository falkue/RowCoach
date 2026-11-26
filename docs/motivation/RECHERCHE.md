# Motivation und Nudges: Recherche und Feature-Katalog (Stand 26.11.2026)

Auftrag (Falk, 26.11.): „Sportliteratur durchsuchen zu Nudges und Motivationen, die man noch einbauen kann.“
Dieses Dokument liefert Belege, einen Praxisvergleich und einen priorisierten Katalog. Gebaut wird später.

Es baut auf vorhandenen Entscheidungen auf und wiederholt sie nicht:
- `docs/design/startscreen-gamification.md` (23.11.): kein Tages-Streak, Wochenserie mit Joker, Seen-Pass ohne
  Sammelzwang, Liste „Bewusst nicht tun“. Die dortigen Quellen [1]–[11] gelten weiter (Teixeira 2012, Mazéas 2022,
  Sharif & Shu 2017, Silverman & Barasch 2023, Dai/Milkman/Riis 2014, Patel 2019 u. a.).
- `docs/coach/SPEC.md` und `RECHERCHE.md`: Sprachcoach **während** der Fahrt (verbale Ermutigung, Ton). Hier geht es
  um Motivation **zwischen** den Fahrten: anfangen, dranbleiben, wiederkommen.
- `docs/trainingsplaene/RECHERCHE.md`: Wunschtage, verpasste Einheiten (5.2), Wiedereinstieg (5.3), RPE-Anpassung
  (5.5), Saison (5.7). Die Motivationsfunktionen hängen sich an diese Regeln an.

Was es heute schon gibt (Code gelesen): Tagesvorschlag mit Begründung (`DailySuggestion`), Wochenziel 1–7 Fahrten
(Einstellungen), Wochenserie mit Joker (`TrainingStats.Streak`), Wochenkarte mit Stufen leicht/mittel/hart,
„Letzte Fahrt“ mit Bestzeit je Strecke, Seen-Pass, Anstrengung 1–10 nach der Fahrt (`SummaryView`), Geister-Transport
für „Gegen meine Bestfahrt“ (Knopf noch offen, `MULTIPLAYER.md`). Es fehlen: Meilensteine, persönliche Rekorde je
Distanz, Rückblicke, Erinnerungen, Wiedereinstiegs-Logik ausserhalb von Plänen, Fitness-Trend.

Belegstärke wie im Coach-Dokument: **A** Meta-Analyse oder systematische Übersicht · **B** einzelnes Experiment oder
RCT · **C** Praxis, Firmenangabe, Produktseite · **abg.** von Claude abgeleitet. BCT-Nummern nach der Taxonomie
BCTTv1 (Michie et al. 2013, *Ann Behav Med* 46:81–95, doi:10.1007/s12160-013-9486-6).

---

## 1. Recherchewege

1. **Zotero** (`zrag search "gamification physical activity"`): nur Transkript-Notizen und eine Arbeit zu Green Nudging,
   nichts Einschlägiges; `zrag semantic` brach nach Zeitüberschreitung ab. Übersprungen.
2. **Fundus**: vorhanden und genutzt: Teixeira 2012 (study 1036), Mazéas 2022 (1037), Sharif & Shu 2017 (1038),
   Silverman & Barasch 2023 (1039), Patel 2019 STEP UP (1040), Dai et al. 2014 (1041), Aral & Nicolaides 2017
   „Exercise contagion“ (656), Fogg-Modell (fact 1600), Duolingo-Streak (practice 606), Berridge & Robinson 2016 (659),
   Lukoff 2021 (664), Allcott et al. 2022 (675).
3. **Web**: nur für Lücken, Zahlen am Abstract bzw. an der PubMed/PMC-Seite geprüft (nicht im Volltext, ausser wo
   vermerkt). Neu zurückgeschrieben nach Fundus: siehe Abschnitt 8.

---

## 2. Befunde aus der Forschung

### 2.1 Gamification wirkt im Mittel klein bis mittel, aber nicht jedes Element
- **Mazéas et al. 2022** (JMIR 24:e26779): 16 RCTs, 2407 Personen, Hedges g = 0,42 (95 %-KI 0,14–0,69), etwa
  +1600 Schritte/Tag. Wirkung nach Ende der Intervention schwächer. **A** (Fundus 1037)
- **Johnson et al. 2016** (*Internet Interventions* 6:89–106, doi:10.1016/j.invent.2016.10.002): 19 Arbeiten, 59 %
  positive, 41 % gemischte Effekte; am klarsten bei Gesundheitsverhalten wie Bewegung, Evidenzqualität meist mässig.
  Kaum Vergleiche „gleiche App mit vs. ohne Spielelemente“. **A**
- **Milkman et al. 2021, Megastudie** (*Nature* 600:478–483, doi:10.1038/s41586-021-04128-4): 61 293 Mitglieder einer
  US-Fitnesskette, 54 vierwöchige Programme von 30 Forschenden. 45 % steigerten die Besuche um 9–27 %; nur 8 % wirkten
  nach Ende messbar nach. **Bestes Programm: kleiner Bonus fürs Wiederkommen nach einem verpassten Training (+27 %).**
  Fachleute konnten die Rangfolge nicht vorhersagen. **B** (sehr grosses Feldexperiment)
- Folgerung: Spielelemente sind kein Selbstläufer. Was wirkt, sind die Verhaltenstechniken darunter (Ziel,
  Selbstbeobachtung, Rückmeldung, Planung, Wiedereinstieg). Punkte, Münzen und Level ohne Rudersinn bleiben weg
  (wie in startscreen-gamification.md 4).

### 2.2 Selbstbeobachtung und Rückmeldung (BCT 2.2, 2.3, 2.7, 1.5)
- **Michie et al. 2009** (*Health Psychol* 28:690–701, doi:10.1037/a0016136): 122 Evaluationen (N = 44 747) zu
  Bewegung und Ernährung, Gesamteffekt 0,31. Selbstbeobachtung **plus** mindestens eine weitere Technik der
  Kontrolltheorie (Ziel setzen, Rückmeldung, Ziel überprüfen) 0,42 gegenüber 0,26 ohne diese Kombination. **A**
- **Harkin et al. 2016** (*Psychol Bull* 142:198–229, doi:10.1037/bul0000025): 138 randomisierte Studien
  (N = 19 951): Fortschrittsbeobachtung fördert die Zielerreichung, d = 0,40 (KI 0,32–0,48). Stärker, wenn der
  Fortschritt **festgehalten** (aufgeschrieben, angezeigt) oder öffentlich gemacht wird. **A**
- **Gegenbefund Etkin 2016** (*J Consum Res* 42:967–984, doi:10.1093/jcr/ucv095): Sechs Experimente: Messen
  steigert die Menge, kann aber die Freude senken und das freiwillige Weitermachen danach verringern – vor allem bei
  Tätigkeiten, die man aus Freude tut. **B**
- Folgerung für RowCoach: Zahlen nach der Fahrt sind gut, wenn sie an ein Ziel geknüpft sind und Bedeutung haben
  („gleiches Tempo, 6 Schläge tiefer im Puls als im Oktober“). Für Landschafts-Fahrten soll die App die Zahlen auch
  zurücknehmen können („Nur rudern“: keine Auswertung auf dem Bildschirm, Speicherung im Hintergrund).

### 2.3 Ziele (BCT 1.1, 1.3, 1.5, 1.6)
- **Locke & Latham 2002** (*Am Psychol* 57:705–717, doi:10.1037/0003-066X.57.9.705): konkrete, fordernde Ziele mit
  Rückmeldung schlagen „gib dein Bestes“; bei neuen, komplexen Aufgaben sind Lernziele besser als Leistungsziele. **A**
  (Übersicht über Jahrzehnte Forschung)
- **Sharif & Shu 2017**: Ziele mit eingebautem Spielraum werden lieber gewählt und eher durchgehalten. **B** (Fundus
  1038, schon umgesetzt als Joker)
- Folgerung: Das Wochenziel bleibt das Hauptziel (Verhaltensziel). Ergebnisziele (2000-m-Zeit, Kilometer) kommen
  über Pläne und Meilensteine. Nach 4 Wochen das Wochenziel überprüfen lassen (BCT 1.5), mit Vorschlag nach oben **oder
  unten**.

### 2.4 Wenn-dann-Pläne (Implementation Intentions, BCT 1.4, 7.1)
- **Gollwitzer & Sheeran 2006** (*Adv Exp Soc Psychol* 38:69–119, doi:10.1016/S0065-2601(06)38002-1): 94 Tests,
  d = 0,65 auf die Zielerreichung (Gesundheit und andere Bereiche). **A**
- **Bélanger-Gravel, Godin & Amireault 2013** (*Health Psychol Rev* 7:23–54, doi:10.1080/17437199.2011.560095):
  speziell körperliche Aktivität, 26 Studien: SMD 0,31 direkt danach, 0,24 bei Nachbefragung; stärker mit
  Hindernisplanung („Wenn ich müde heimkomme, dann rudere ich trotzdem 15 Minuten“). **A**
- Folgerung: Die Wunschtage aus den Trainingsplänen um **Uhrzeit und Anlass** ergänzen („Di und Do nach der Arbeit,
  Sa morgens“). Das ist der stärkste billige Hebel im Katalog.

### 2.5 Gewohnheit (BCT 8.3, 8.1)
- **Lally et al. 2010** (*Eur J Soc Psychol* 40:998–1009, doi:10.1002/ejsp.674): 96 Personen, tägliches neues
  Verhalten über 84 Tage. Automatismus im Mittel nach 66 Tagen, Spanne 18 bis (hochgerechnet) 254 Tage; Bewegung
  dauerte länger als Trinken oder Essen. **Ein einzelnes Auslassen schadete der Gewohnheitsbildung nicht**, häufiges
  Auslassen schon. **B** (Zahlen über Abstract und Universitätsmitteilung geprüft)
- **Gardner, Lally & Wardle 2012** (*Br J Gen Pract* 62:664–666, doi:10.3399/bjgp12X659466): Gewohnheit entsteht aus
  Wiederholung im **gleichen Kontext** (gleiche Zeit, gleicher Anlass). **B** (Übersichtsbeitrag)
- **Kaushal & Rhodes 2015** (*J Behav Med* 38:652–663, doi:10.1007/s10865-015-9640-7): neue Fitnessstudio-Mitglieder;
  etwa vier Einheiten pro Woche über rund sechs Wochen gingen mit einer Trainingsgewohnheit einher. **B** (nicht am
  Original nachgeprüft)
- Folgerung: Für Einsteiger zählt in den ersten 8–10 Wochen Regelmässigkeit am gleichen Anlass mehr als Leistung.
  „Nie zweimal verpassen“ (Praxisregel, z. B. James Clear) ist durch Lally gedeckt: ein Ausfall ist harmlos, eine
  Kette von Ausfällen nicht. Die Megastudie zeigt, dass genau das Wiederkommen nach einem Ausfall der beste
  Ansatzpunkt ist (+27 %).

### 2.6 Serien (Streaks) und ihre Nebenwirkungen
- **Silverman & Barasch 2023**: Hervorgehobene intakte Serien steigern die Beteiligung, gerissene senken sie,
  besonders bei Selbstvorwurf; reparierbare Serien mildern das. **B** (Fundus 1039)
- **Duolingo**: Streak Freeze, Serie vom Tagesziel getrennt; Firmenzahlen korrelativ. **C** (Fundus 606)
- Für Ausdauertraining kommt dazu: Tages-Serien belohnen tägliches Training und damit fehlende Ruhetage. Das steht
  gegen die Plan-Regeln (≥ 48 h zwischen harten Reizen, Ruhetage für Einsteiger). **abg.**
- Folgerung: bei der vorhandenen Wochenserie bleiben. Ergänzen: Pause-Modus (Krankheit, Ferien), der die Serie
  einfriert, ohne den Joker zu verbrauchen.

### 2.7 Selbstbestimmung: Autonomie, Kompetenz, Verbundenheit
- **Teixeira et al. 2012**: In 66 Studien hängt eigenständige Motivation mit mehr Bewegung zusammen; identifizierte
  Motivation („weil es mir wichtig ist“) sagt den Einstieg voraus, innere Motivation („weil es Freude macht“) das
  langfristige Dranbleiben. **A** (Fundus 1036)
- **Deci, Koestner & Ryan 1999** (*Psychol Bull* 125:627–668, doi:10.1037/0033-2909.125.6.627): 128 Experimente.
  Erwartete, an Leistung geknüpfte materielle Belohnungen senken das freiwillige Weitermachen (d etwa −0,28 bis
  −0,40 je nach Art); positive Rückmeldung steigert es (d = 0,33). **A**
- Folgerung: Rückmeldung, die Kompetenz zeigt, ja („Dein schnellstes 4-min-Intervall bisher“). Belohnungen, die das
  Rudern zum Mittel für etwas anderes machen (Punkte, freischaltbare Inhalte), nein. Jede Motivationsfunktion ist
  abschaltbar (Autonomie), und die App fragt nach dem eigenen Grund fürs Rudern (identifizierte Motivation).

### 2.8 Sozialer Vergleich
- **Patel et al. 2019 STEP UP**: Wettbewerb wirkte am stärksten und als einziger Arm nach dem Spiel weiter. **B**
  (Fundus 1040)
- **Aral & Nicolaides 2017** (*Nat Commun* 8:14753): Laufen steckt in einem globalen Netzwerk an; weniger Aktive
  beeinflussen Aktivere, nicht umgekehrt (Vergleich nach oben scheut man nicht, Vergleich nach unten spornt an). **B**
  (Fundus 656)
- **Arigo et al. 2020** (*JMIR* 22:e15642, doi:10.2196/15642): Meta-Review über 26 Übersichten: Vergleichsfunktionen in
  Bewegungs-Apps sind schlecht definiert und nie auf die Person zugeschnitten, obwohl Menschen sehr unterschiedlich auf
  Vergleiche reagieren. **A** (über die Belegbasis, nicht über Wirkung)
- Folgerung: Vergleich nur in selbst gewählten Gruppen, mit wählbarer Richtung (gegen mich selbst, gegen Ähnliche,
  gemeinsames Gruppenziel statt Rangliste). Ohne Konto bleibt der Vergleich mit sich selbst (Bestfahrt).

### 2.9 Neuanfänge (Fresh Start, BCT 1.1 + Timing)
- **Dai, Milkman & Riis 2014**: Ziele und Fitnessstudiobesuche nehmen nach zeitlichen Marken zu (Wochen-, Monats-,
  Jahresbeginn, Geburtstag, nach Ferien). **B** (Fundus 1041)
- Folgerung: Rückblicke und Zielangebote an diese Marken binden (Montag, Monatserster, Neujahr, Geburtstag aus dem
  Profil, erste Fahrt nach den Ferien). Nicht nach Rückschlägen „Neustart“ sagen, sondern einfach die neue Woche zeigen.

### 2.10 Temptation Bundling (Versuchung koppeln)
- **Milkman, Minson & Volpp 2014** (*Manage Sci* 60:283–299, doi:10.1287/mnsc.2013.1784): 226 Personen, Hörbücher nur
  im Fitnessstudio: +51 % Besuche anfangs, nachlassend nach einer Ferienpause; 61 % zahlten danach für die
  Beschränkung. **B**
- **Kirgios et al. 2020** (*Organ Behav Hum Decis Process* 161:20–35, doi:10.1016/j.obhdp.2020.09.003): grosse
  Replikation: Hörbuch + Ermutigung zur Kopplung, +10–14 % Wahrscheinlichkeit eines wöchentlichen Besuchs, bis 17 Wochen
  nach Ende. **B**
- Folgerung: realistisch ist ein Effekt um 10 %, nicht 50 %. Für RowCoach heisst das: „Mein Ruder-Hörbuch/Podcast“
  als Einstellung, die App erinnert daran („Kapitel 7 wartet beim Rudern“) und zeigt an der Startseite, wo man steht.
  Die Kopplung muss freiwillig bleiben.

### 2.11 Erinnerungen und Timing (JITAI, BCT 7.1)
- **Nahum-Shani et al. 2018** (*Ann Behav Med* 52:446–462, doi:10.1007/s12160-016-9830-8): Rahmen für
  „Just-in-time adaptive interventions“: Unterstützung nur in Momenten, in denen sie nötig **und** annehmbar ist.
  **Modell**
- **Klasnja et al. 2019, HeartSteps** (*Ann Behav Med* 53:573–582, doi:10.1093/abm/kay067): 44 Personen, 42 Tage,
  fünf Entscheidungszeitpunkte am Tag: eine passende Aufforderung steigerte die Schritte der nächsten 30 min um 14 %
  (≈ 35 Schritte, p = 0,06), mit der Zeit abnehmend. **B**
- **Hardeman et al. 2019** (*IJBNPA* 16:31, doi:10.1186/s12966-019-0792-7): 19 Arbeiten, 14 JITAIs: Wirkung gemischt,
  keine Studie ausreichend gross. **A** (schwache Belegbasis)
- **Kushlev et al. 2016** (CHI): Mitteilungen erhöhen Unaufmerksamkeit. **B** (Fundus 666)
- Folgerung: Eine Erinnerung zur selbst gewählten Zeit an selbst gewählten Tagen (Wenn-dann-Plan) ist gut belegt;
  „schlaue“ adaptive Erinnerungen sind es nicht. Höchstens eine lokale Mitteilung pro Tag, nie an Ruhetagen, nie mit
  Verlust-Sprache, nach zwei ignorierten Erinnerungen eine Woche Pause (Ermüdung). **abg.**

### 2.12 Abwechslung
- **Sylvester et al. 2016** (*J Behav Med* 39:214–224, doi:10.1007/s10865-015-9688-4): 121 inaktive Studierende,
  6 Wochen, mehr Abwechslung im Programm → höhere Teilnahme, vermittelt über **wahrgenommene** Abwechslung. **B**
- Folgerung: RowCoach hat hier einen natürlichen Vorteil (Strecken, Wetter, Programme, Verkehr). Der Tagesvorschlag
  wählt schon die am längsten nicht geruderte Strecke; das sichtbar machen („Neu für dich: Stein am Rhein“).

### 2.13 Erholung und Übertraining
- **Meeusen et al. 2013** (*Eur J Sport Sci* 13:1–24, doi:10.1080/17461391.2012.730061): Konsens ECSS/ACSM: Leistung
  stagniert trotz Training, Stimmung und Schlaf leiden; Vorbeugung durch Belastungssteuerung, Ruhetage,
  Beobachtung von Belastung und Befinden. **A** (Konsenspapier)
- Session-RPE als Messung der inneren Belastung: siehe trainingsplaene 5.5. **A/B**
- Folgerung: Jede Motivationsfunktion braucht eine Bremse. Wenn die Belastungsregeln (Regel 1 im Tagesvorschlag,
  RPE-Regeln 5.5) Erholung verlangen, schweigen Challenges, Bestfahrt-Angebote und Meilenstein-Hinweise; Ruhetage
  werden gelobt („Ruhetag geplant und gehalten“).

### 2.14 Masters und Ältere
- Die Trainingspläne sehen für Masters 72 h zwischen harten Einheiten vor (trainingsplaene 5.1, **abg.**).
  Für die Motivation fand sich in dieser Recherche keine eigene, belastbare Quelle. Plausibel (**abg.**): Gesundheit,
  Freude und Gemeinschaft wiegen mehr als Bestzeiten; Altersklassen-Vergleiche (Concept2-Rangliste nach Alter) sind für
  Leistungsorientierte wertvoll. Konsequenz: Ziele und Rekorde mit Altersbezug nur anbieten, nicht voreinstellen.

---

## 3. Praxis: was andere machen und was davon belegt ist

| Anbieter | Mechanik | Beleg für Wirkung | Für RowCoach |
|---|---|---|---|
| **Strava** | Segmente mit Bestzeit und Rangliste, Kudos, monatliche Challenges, Jahresrückblick „Year in Sport“ | Ansteckung im Netzwerk belegt (Aral & Nicolaides 2017, **B**); Segmente, Kudos und Jahresrückblick ohne eigene Wirkstudie (**C**) | Segment-Idee als „Teilstrecke einer Strecke“ mit eigener Bestzeit; Jahresrückblick lokal |
| **Apple Fitness** | Ringe (Bewegen, Trainieren, Stehen), Auszeichnungen, Serien; seit watchOS 11 (2024) Ringe pausieren und Ziele je Wochentag | Selbstbeobachtung + Ziel (Michie 2009, Harkin 2016, **A** für das Prinzip); Produktwirkung nicht veröffentlicht (**C**) | Pause-Funktion und Ziel je Wochentag übernehmen |
| **Peloton** | Meilensteine (100., 500. Fahrt), Abzeichen, Bestleistung je Kurs, High Fives, Klassen-Rangliste | keine unabhängige Wirkstudie (**C**) | Meilensteine nach Fahrtenzahl und Distanz |
| **Zwift** | virtuelle Welten, Gruppenfahrten, Rennen, Level und Freischaltungen | Nutzerbefragung: Gesundheit, Training und Geselligkeit wichtiger als Wettbewerb (NC State/Münster 2021, **B** Befragung) | Landschaft und Gruppenfahrten ja, Freischalten nein |
| **Hydrow** | Fahrten auf echtem Wasser mit Trainer-Video, Meilensteine, Bestenliste | **C** | bestätigt den Weg „echte Orte“; RowCoach kann Orte ohne Video |
| **Concept2 Logbook** | Million-Meter-Award, saisonale Challenges (u. a. Holiday Challenge zwischen Thanksgiving und Heiligabend mit Spendenzweck), Ranglisten nach Alter und Gewicht | **C** (Gemeinschaftstradition, keine Wirkstudie) | Meter-Meilensteine im Concept2-Stil; Logbook-Upload später als Brücke zur Community |
| **Duolingo** | Tages-Streak mit Freeze, Ligen | korrelative Firmenangaben (**C**); Streak-Forschung zeigt Risiken (Silverman & Barasch, **B**) | nur das Reparieren übernehmen, nicht den Tages-Streak |
| **Garmin** | Abzeichen, Training Readiness, Belastungsstatus, Erholungszeit | Wirkung auf Dranbleiben nicht belegt (**C**); Prinzip Belastungssteuerung (Meeusen 2013, **A**) | Erholungshinweis aus vorhandenen Daten (RPE, Stufen), keine Scheingenauigkeit |
| **WHOOP** | Recovery-Score, Strain-Ziel | **C**; ohne HRV-Messung in RowCoach nicht übertragbar | nicht nachbauen |
| **Gyms (Megastudie)** | Mini-Bonus fürs Wiederkommen nach Ausfall | **B**, +27 % (Milkman 2021) | „Wiedereinstieg leicht machen“ statt Strafe |

Kurz: Belegt sind die Techniken darunter (Ziel + Selbstbeobachtung + Rückmeldung, Wenn-dann-Pläne, Wiederkommen nach
Ausfall, Abwechslung, Kopplung, Wettbewerb in kleinen Gruppen). Für Abzeichen, Ringe, Kudos und Jahresrückblicke als
einzelne Elemente gibt es keine Wirkstudien; sie sind vertretbar, wenn sie die belegten Techniken tragen.

---

## 4. Feature-Katalog (priorisiert)

Bewertung: **Nutzen** (für Dranbleiben, 1–3) × **Beleg** (A = 3, B = 2, C/abg. = 1) / **Aufwand** (S = 1, M = 2,
L = 3). Prio 1 = zuerst bauen. „Offline“ = ohne Konto und ohne Netz voll nutzbar.

| # | Feature | Was genau | Warum (Beleg, BCT) | Daten in RowCoach | Offline | Risiken → Gegenmittel | Aufwand | Prio |
|---|---|---|---|---|---|---|---|---|
| 1 | **Erfolgserlebnisse nach der Fahrt** | In der `SummaryView` oben 1–3 Zeilen „Was heute gut war“, aus Regeln: neue Bestzeit (Strecke/Distanz), schnellstes Intervall dieses Programms, Intervalle konstant (±1,5 s), Zielbereich gehalten (% der Zeit), Puls tiefer bei gleichem Tempo als vor 4–8 Wochen, Meilenstein erreicht, Ruhetag-Regel eingehalten. Dazu ein Coach-Satz nach der Fahrt (neues Szenario `post_ride` in `coach_phrases.json`, auch gesprochen). Immer etwas Wahres, nie erfunden; bei schwacher Fahrt Anstrengung oder Dabeisein loben | Rückmeldung zur Kompetenz (Deci 1999 d = 0,33; Harkin 2016 d = 0,40) **A**; BCT 2.2, 2.7, 15.3, 10.4 | alles vorhanden (Splits, Phasen, Zonen, Bestzeiten, Verlauf) | ja | Inflation von Lob → höchstens 3 Zeilen, Rangfolge, Wiederholungen vermeiden; kein Vergleich mit schlechterer Note in Rot | S–M | **1** |
| 2 | **Persönliche Rekorde je Distanz und Zeit, „Gegen deine Bestfahrt“** | Rekorde für 500, 1000, 2000, 5000, 6000, 10 000 m, Halbmarathon, Marathon, 30 und 60 min, auch als **Teilstücke** beliebiger Fahrten (wie Strava „Best Efforts“), je Strecke wie heute. Verlauf der Rekorde. Auf der Streckenseite Knopf „Gegen meine Bestfahrt“ (Geister-Transport ist fertig); im Tagesvorschlag nur an Tagen ohne Erholungsbedarf anbieten | Vergleich mit sich selbst, Kompetenz (Teixeira 2012 **A**); BCT 2.3, 2.7, 15.3, 1.6 | Samples mit Zeit/Distanz vorhanden; Teilstück-Suche neu in RowCoachKit | ja | Jede Fahrt wird zum Test → Bestfahrt opt-in, nie an leichten Tagen vorschlagen (Regel 1, 5.5); kurze Teilstücke aus Intervallen nicht als 2000-m-Rekord werten | M | **1** |
| 3 | **„Wann ruderst du?“: Wenn-dann-Plan mit Erinnerung** | Beim Wochenziel bzw. Planstart: Tage **und** Uhrzeit **und** Anlass wählen („nach der Arbeit“, „vor dem Frühstück“); optional Hindernisplan („Wenn ich müde bin, dann 15 min locker“). Lokale Mitteilung zur gewählten Zeit (UNUserNotificationCenter, kein Server), Text mit dem Vorschlag des Tages. Optional Termin in den Kalender (EventKit). Höchstens 1/Tag, nie an Ruhetagen, nach 2 ignorierten eine Woche Ruhe, jederzeit aus | d = 0,65 allgemein, 0,31 für Bewegung (Gollwitzer & Sheeran 2006; Bélanger-Gravel 2013) **A**; Prompts zur gewählten Zeit (HeartSteps 14 %) **B**; BCT 1.4, 7.1, 8.3, 1.2 | Wunschtage aus Plänen; Uhrzeit neu; Einstellungen vorhanden | ja (lokale Mitteilungen) | Nerven, Druck → opt-in, sachlicher Ton, keine Verlust-Sprache („Dein Ruderplan für heute: …“), Ruhetage still | S–M | **1** |
| 4 | **Sanfter Wiedereinstieg („nie zweimal verpassen“)** | Ist ein Wunschtag verstrichen, zeigt die Startseite am nächsten Tag eine **kurze** Einheit („15 min locker zählen genauso“) als Vorschlag, ohne Hinweis auf das Verpasste. Erste Fahrt nach ≥ 7 Tagen: Willkommen ohne Vorwurf, Regel 0 bzw. Plan 5.3. Eine Fahrt nach einer Lücke wird in der Auswertung gewürdigt („Wieder drin“) | Wiederkommen nach Ausfall war das wirksamste von 54 Programmen (+27 %, Milkman 2021) **B**; ein Ausfall stört die Gewohnheit nicht (Lally 2010) **B**; BCT 1.2, 8.7, 15.1 | Verlauf, Wunschtage, `DailySuggestion` Regel 0 | ja | Schuldgefühl → nie „verpasst“, „Serie in Gefahr“ o. ä.; keine Mitteilung am Tag nach dem Ausfall ausser der normalen | S | **1** |
| 5 | **Meilensteine** | Wenige, bedeutsame Schwellen: Lebens-Meter (100 km, 250, 500, 1000 km = „Million Meter“, 2500, 5000 …), Fahrtenzahl (10, 25, 50, 100, 250), je Gewässer (25/100/250 km wie im Entwurf), Strecken eines Landes vollständig (Seen-Pass, ohne Prozentbalken auf der Startseite). Ruhige Feier in der Auswertung, Liste im Profil; höchstens ein naher Meilenstein auf der Startseite (in 1–2 Fahrten erreichbar) | Zwischenziele, Kompetenz, Identität („1000-km-Ruderer“) **abg.** auf Basis Locke & Latham **A**; Concept2-Praxis **C**; BCT 1.3, 2.7, 13.5, 10.3 | Distanz je Fahrt und Strecke vorhanden | ja | Konfetti-Inflation, Sammelzwang → wenige Stufen, keine Punkte, keine Sperren; Simulator zählt nie | S | **1** |
| 6 | **Rückblick Woche, Monat, Jahr (mit Neuanfang)** | Montag: kleine Karte „Letzte Woche“ (gibt es teils); Monatserster: Monatsrückblick (Fahrten, km, Anteil leicht/hart, Rekorde, neue Strecken) und die Frage nach dem Ziel für den Monat; Jahresende: „Dein Ruderjahr“ als Seite zum Teilen (Bild, lokal erzeugt). Auch zum Geburtstag und nach Ferien ein Angebot für ein neues Ziel | Fresh-Start (Dai 2014) **B**; Ziel überprüfen + Rückmeldung (Michie 2009, Harkin 2016) **A**; BCT 1.5, 2.2, 15.3 | Verlauf, `TrainingStats` | ja (Teilen über Share Sheet) | Vergleich mit Vormonat drückt → nur positive oder neutrale Vergleiche, leere Monate neutral | M | **2** |
| 7 | **Wochenziel flexibel, mit Pause** | Ziel wählbar als Fahrten **oder** Minuten, optional je Wochentag; „Pause“ für Krankheit/Ferien (1 Tag bis 4 Wochen) friert Serie und Ziel ein, ohne den Joker zu brauchen; mit aktivem Plan zählen geplante Ruhetage als erfüllt; nach 4 erreichten Wochen Vorschlag „etwas mehr?“, nach 3 verfehlten „etwas weniger?“ | Ziele mit Spielraum (Sharif & Shu 2017) **B**; Streak-Reparatur (Silverman & Barasch 2023) **B**; Apple Pause Rings **C**; BCT 1.1, 1.5 | Wochenziel, Streak, Pläne vorhanden | ja | Missbrauch der Pause unwichtig (keine Wettbewerbswirkung) | S | **1** |
| 8 | **Fitness-Trend** | In Grundlage-Fahrten Tempo (bzw. Watt) bei gleichem Puls über Wochen, als ruhige Linie im Verlauf; zusätzlich geschätzte 2000-m-Zeit aus den Rekorden (Paul's Law, schon in den Plänen). Nur bei genug Daten (≥ 6 Grundlage-Fahrten mit Puls in 8 Wochen), Spannbreite statt Scheingenauigkeit | Ergebnis-Rückmeldung, Kompetenz **A** (Harkin, Michie); Rechenweg **abg.**; BCT 2.4, 2.7 | Puls, Tempo, Stufen vorhanden | ja | Rauschen (Hitze, Schlaf, Tagesform) → geglättet, keine roten Abwärtspfeile; Hinweis bei Verschlechterung nur neutral mit Erholungsfrage | M | **2** |
| 9 | **Abwechslung sichtbar machen** | „Neu für dich“ an noch nicht geruderten Strecken und Programmen; im Tagesvorschlag ab der dritten gleichen Einheit eine andere Strecke oder Tageszeit/Wetter-Variante; monatlich „3 Strecken, die du lange nicht gerudert hast“ | wahrgenommene Abwechslung → Teilnahme (Sylvester 2016) **B**; BCT 8.2 (Verhaltensvarianten), 12.1 (Umgebung umgestalten) | Strecken, Programme, Verlauf | ja (heruntergeladene Strecken) | Überforderung → höchstens ein Hinweis pro Bildschirm | S | **2** |
| 10 | **Mein Grund fürs Rudern** | Beim Einrichten optional: Gesundheit, Kopf frei, Leistung, Landschaft, Wettkampf (mehrfach). Die App passt Ton und Hervorhebungen an (Landschaft → Strecken, Leistung → Rekorde, Gesundheit → Wochenminuten) | identifizierte Motivation (Teixeira 2012) **A**; Autonomie; BCT 13.2, 1.1 | neu, klein | ja | Schubladen → jederzeit änderbar | S | **2** |
| 11 | **Ruder-Hörbuch / Podcast koppeln (Temptation Bundling)** | Einstellung „Nur beim Rudern“: gewählter Podcast/Hörbuch/Playlist; Knopf „weiter hören“ beim Start (öffnet die Medien-App bzw. Apple Music über MediaPlayer), Startseite „Kapitel 7 wartet“. Coach-Lautstärke duckt Musik (schon über AVAudioSession lösbar) | +51 % klein (Milkman 2014), +10–14 % gross (Kirgios 2020) **B**; BCT 10.9 (Selbstbelohnung), 12.1 (Umgebung umgestalten) | neu; Medienzugriff je nach Anbieter begrenzt | ja | Kontrolle über fremde Apps begrenzt → zunächst nur Erinnerung + Notiz „wo war ich“ | M | **2** |
| 12 | **Erholungs-Wächter (Querschnittsregel)** | Ein Zustand „Erholung empfohlen“ aus Regel 1 (< 48 h nach hart), RPE-Regeln 5.5 und Masters-72 h; solange er gilt: keine Bestfahrt-Angebote, keine Challenge-Hinweise, keine Erinnerung mit hartem Vorschlag; Startseite lobt den Ruhetag. Wochenziel-Obergrenze (z. B. höchstens 6 Fahrten, Hinweis bei 7) | Übertraining vorbeugen (Meeusen 2013) **A**; BCT 5.1 (Info über Folgen), 1.2 | Regeln vorhanden | ja | Bevormundung → begründen, nie sperren | S | **1** (als Regel für alle anderen) |
| 13 | **Teilstrecken („Segmente“) auf Strecken** | Feste Abschnitte je Strecke (z. B. „Utoquai bis Zürihorn 1,2 km“) mit eigener Bestzeit, angezeigt im Ziel | Strava-Praxis **C**; Kompetenz **abg.** | Streckengeometrie und Samples vorhanden; Abschnitte im Coursebuilder neu | ja | Sprint-Lust in Grundlage → nur in freien Fahrten zeigen | M | **3** |
| 14 | **Virtuelle Reisen** | Mehrfahrten-Ziel entlang echter Gewässer: „Rhein vom Tomasee bis Basel (≈ 375 km)“, „Zürichsee rund“, „Themse“; jede Fahrt schiebt die Marke weiter, Etappen mit Ortsnamen und Bild, Etappenziel = Meilenstein; Ziel und Tempo selbst gewählt | Zwischenziele, Neuheit **abg.**; Praxis (Concept2-Challenges, virtuelle Läufe) **C** | Distanzen vorhanden; Routen als Polyline + Orte neu (OSM) | ja (Daten mitliefern) | Druck durch Frist → keine Frist, nur Fortschritt | M–L | **3** |
| 15 | **Saison-Challenges** | Opt-in, selbst gewähltes Ziel: „Winterkilometer“ (Nov–Feb, passend zu `season: winter`), „Dezember-100-km“ (Holiday-Challenge-Anlehnung), „Sommer-Seen“. Start an Monatsersten (Fresh Start). Ohne Konto lokal; mit Konto gemeinsame Gruppensumme | Fresh Start **B**; Ziel + Rückmeldung **A**; Concept2-Praxis **C**; BCT 1.1, 1.9 | Saison-Logik vorhanden | ja (Gruppe nur online) | FOMO, Übertreibung kurz vor Fristende → Ziel nur vorab wählbar, Erholungs-Wächter gilt, kein Countdown-Druck | M | **3** |
| 16 | **Freunde und kleine Gruppen (nur mit Konto)** | Gruppe bis ~20 Personen: gemeinsames Wochenziel (Kollaboration), „Daumen“ nach einer Fahrt, freiwillige Rennen und Geister von Freunden; Vergleich nur innerhalb der Gruppe, wählbar „gegen Ähnliche“. Keine globale Rangliste | Wettbewerb/Kollaboration (STEP UP) **B**; Ansteckung (Aral 2017) **B**; Vergleich individuell (Arigo 2020) **A**; BCT 3.1, 6.2, 10.4 | braucht Firebase (geplant, `MULTIPLAYER.md`) | nein | Datenschutz, Abwärtsvergleich, Druck → opt-in, nur Spitzname, sichtbar nur für die Gruppe, jederzeit verlassen, nichts ohne Zustimmung teilen | L | **3** |
| 17 | **Selbst-Zusage (Commitment)** | „Diese Woche sage ich mir 3 Fahrten zu“ am Montag, optional mit Person aus der Gruppe; am Sonntag ehrlicher Rückblick ohne Strafe | Commitment (Allcott 2022: selbst gesetzte Grenzen wirken, Fundus 675) **B** indirekt; BCT 1.9, 1.8 | Wochenziel vorhanden | ja (Person: online) | Scheitern drückt → nur als Option, kein Geldeinsatz | S | **3** |
| – | **Nicht bauen** | Tages-Streak mit Flamme, Punkte/Münzen/Level, Freischalten von Strecken, Zufallsbelohnungen, globale Ranglisten auf der Startseite, „Serie in Gefahr“-Mitteilungen, Geld-Einsatz | Overjustification (Deci 1999) **A**; Wollen ohne Mögen (Berridge 2016) **A**; Streak-Bruch (Silverman 2023) **B**; Ruhetage | – | – | – | – | – |

---

## 5. Ton und Ethik

1. **Keine Dark Patterns.** Keine künstliche Verknappung, keine Verlust-Sprache („verlierst“, „in Gefahr“), keine
   versteckten Abschalter, keine Mitteilungen, die die App öffnen sollen, ohne dem Rudern zu dienen. Autoplay-ähnliche
   Ketten („nächste Fahrt gleich starten“) mindern das Gefühl, selbst zu steuern (Lukoff 2021, Fundus 664).
2. **Kein Schuld-Druck.** Pausen sind neutral, nie rot, nie gezählt („seit 9 Tagen nicht“). Die App würdigt das
   Wiederkommen, nicht das Durchhalten um jeden Preis.
3. **Autonomie.** Jede Funktion aus diesem Katalog ist einzeln abschaltbar; Einstellung „Nur rudern“ blendet Zahlen
   und Hinweise aus (Etkin 2016). Vorschläge begründen („weil …“), immer Alternativen, nie sperren.
4. **Erholung schützen.** Der Erholungs-Wächter (#12) hat Vorrang vor jeder Motivationsfunktion. Ruhetage zählen als
   Teil des Plans und werden gelobt. Keine Funktion belohnt tägliches Training.
5. **Ehrlichkeit.** Lob nur für Wahres; Prognosen mit Spannbreite; Simulatorfahrten zählen nie.
6. **Privatsphäre.** Alles lokal und ohne Konto; Gruppen und Teilen nur auf ausdrücklichen Wunsch, mit Spitznamen,
   für eine gewählte Gruppe. Keine Analyse-SDKs für Motivationsdaten.
7. **Sprache.** Duzen, kurz, sachlich-warm, Anstrengung statt Talent loben (Coach-RECHERCHE 1.6), keine Konfetti-
   Inflation.

---

## 6. Empfehlung: die ersten 5 Features

1. **Erfolgserlebnisse nach der Fahrt + Coach-Satz `post_ride`** (#1, S–M): Daten liegen vor, wirkt bei jeder Fahrt,
   starke Belege für kompetenzbezogene Rückmeldung.
2. **„Wann ruderst du?“ mit lokaler Erinnerung** (#3, S–M): stärkster billiger Hebel (Wenn-dann-Pläne, A), fügt sich
   in die Wunschtage der Trainingspläne.
3. **Sanfter Wiedereinstieg** (#4, S): bestes Programm der Megastudie; eigentlich nur Regeln und Texte.
4. **Persönliche Rekorde je Distanz + „Gegen meine Bestfahrt“** (#2, M): Geister-Transport ist fertig, es fehlt die
   Rekordsuche in Teilstücken und der Knopf.
5. **Meilensteine** (#5, S): billig, offline, passt zu Seen-Pass und Concept2-Kultur.

Mit dabei als Regeln, nicht als eigene Features: **Erholungs-Wächter** (#12) und **Pause im Wochenziel** (#7), beide S.
Danach Rückblicke mit Neuanfang (#6), Fitness-Trend (#8), Abwechslung (#9), Hörbuch-Kopplung (#11).

---

## 7. Offene Punkte
- Vor dem Bau von #1: Regelkatalog „Was heute gut war“ mit Rangfolge und Textvarianten (de/en) in
  `coach_phrases.json` bzw. eigener Datei.
- Teilstück-Rekorde (#2): Algorithmus für schnellstes Teilstück über Samples (Zwei-Zeiger-Suche) in RowCoachKit,
  Test mit echten Fahrten.
- Erinnerungen (#3): iOS-Berechtigung erst beim Einschalten erfragen, nicht beim ersten Start.
- Die Belege wurden über Abstracts/PubMed/Verlagsseiten geprüft, nicht im Volltext; Kaushal & Rhodes 2015 und die
  genauen Werte von Deci 1999 je Belohnungsart sind nicht nachgeprüft.

## 8. Fundus
Genutzt: siehe Abschnitt 1. Zurückgeschrieben am 26.11.2026 (project `rowcoach`, alle „unverified“, Tags
`endurance-training`/`consumer-attitudes`): study 1056 Harkin 2016, 1057 Michie 2009, 1058 Milkman 2021 (Megastudie),
1059 Gollwitzer & Sheeran 2006 (mit Bélanger-Gravel 2013), 1060 Lally 2010, 1061 Milkman 2014 (mit Kirgios 2020),
1062 Sylvester 2016, 1063 Etkin 2016, 1064 Klasnja 2019 (mit Hardeman 2019), 1065 Johnson 2016.
Nicht zurückgeschrieben (Zahlen nicht am Original geprüft): Deci 1999 je Belohnungsart, Kaushal & Rhodes 2015,
Arigo 2020, Meeusen 2013, Locke & Latham 2002.
