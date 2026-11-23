# Startbildschirm: Motivation statt Menü

Entwurf aus Sicht Gamification und Motivationsdesign, 23.11.2026. Ziel: Der Tab „Rudern“ zeigt beim Öffnen am iPad (Querformat), *warum* man heute rudern will und *was* man rudern könnte, bevor jemand eine Option wählen muss. Belege stehen in eckigen Klammern [n] und sind in Abschnitt 5 aufgelistet. Alles andere ist begründete Designeinschätzung.

## 1. Kurzdiagnose des heutigen Startbildschirms

1. **Ein Verzweigungsmenü statt eines Ziels.** Es gibt zwei graue Karten („Frei rudern“, „Training“) auf viel weissem Raum. Der Bildschirm fragt „Wie?“, bevor er „Wohin?“ oder „Wofür?“ beantwortet. Das stärkste Kapital der App, die Landschaft, sieht man erst zwei Ebenen tiefer.
2. **Die App scheint kein Gedächtnis zu haben.** Verlauf, Bestzeiten, Pulszonen und Health-Daten liegen vor, aber der Start zeigt nichts davon. Wer nach der dritten Fahrt öffnet, sieht dasselbe wie beim ersten Mal. Kompetenzerleben braucht sichtbare Rückmeldung [1].
3. **Die einzige persönliche Meldung ist eine Störung.** Hinweise wie „Die letzte Fahrt wurde unterbrochen“ sind wichtig, aber sie sind heute das einzige, was die App „über dich“ sagt.
4. **Keine Einladung, sofort loszulegen.** Bis „Los“ braucht es mindestens drei Schritte: Modus, dann Programm, dann Strecke. Laut Fogg-Modell geschieht Verhalten, wenn Motivation, Fähigkeit und ein Auslöser zusammenkommen [2]. Jeder zusätzliche Schritt senkt die Fähigkeit.
5. **Gerätestatus steht am falschen Ort.** PM5 und Puls erscheinen erst in der Streckenauswahl, als „nicht verbunden“. Das ist eine Hürde, die man schon vorher still lösen könnte.

## 2. Aufbau nach Priorität

Layout iPad quer: links etwa 60 % eine grosse **Heute-Karte** mit Luftbild, rechts eine schmale Spalte **Deine Wochen**, darunter ein Band **Strecken**. „Frei rudern“ und „Training“ bleiben als zwei kleine Wege („Andere Strecke…“, „Alle Trainings…“) erhalten.

| Prio | Element | Was zu sehen ist | Daten | Motiv | Risiko → Gegenmittel |
|---|---|---|---|---|---|
| **Muss** | **Heute-Karte** | Grosses Luftbild der vorgeschlagenen Strecke, darüber Vorschlag in einem Satz („Utoquai · 2×2000 m · ruhig in Zone 2, ca. 35 min“), eine grosse Taste **Los**, darunter „Anderer Vorschlag“ und zwei Alternativen als Chips. Gerätestatus als kleine Punkte in der Karte | Verlauf (letzte Strecke, letzte Intensität, Tage seit Fahrt), Programme, Zonen, Wochentag | Autonomie (Vorschlag, kein Befehl), Kompetenz (passende Last) | Fühlt sich bevormundend an → immer 2–3 Alternativen, eine Erklärung („weil du gestern hart gefahren bist“), kein „Du musst“ |
| **Muss** | **Letzte Fahrt in einer Zeile** | „Mo 11:27 · Utoquai · 4000 m in 18:51 · 2:21/500 m“. Antippen öffnet die Zusammenfassung | Workout.summary, splits | Kompetenz | Kein rotes „schlechter als“. Vergleiche nur, wenn sie positiv oder neutral formuliert sind |
| **Muss** | **Wochenband (8–12 Wochen)** | Kleine Säulen mit Minuten oder Metern je Woche, die laufende Woche hervorgehoben, ein frei gewähltes Wochenziel als dünne Linie | Verlauf + Apple Health (andere Sportarten grau) | Kompetenz, Selbstwirksamkeit | Wird zur Pflicht → Ziel optional, mit Spielraum (siehe 3e), leere Wochen neutral grau statt rot |
| **Soll** | **Strecken-Band („Seen-Pass“)** | 5 Luftbild-Kacheln, je mit persönlicher Bestzeit, Anzahl Fahrten und km. Noch nicht geruderte Strecken sind farbig wie die anderen, mit dem Vermerk „noch offen“ | courseId, summary.distance, Zeiten je Strecke | Autonomie, Neugier, Kompetenz | Sammelzwang → keine Prozentanzeige „3/5 erledigt“, keine gesperrten Strecken |
| **Soll** | **Bestmarke als Herausforderung** | Auf der Heute-Karte optional: „Dein Bestwert hier: 18:51. Gegen dein Geisterboot fahren?“ | beste Fahrt je Strecke mit Samples | Kompetenz | Jede Fahrt wird zum Test → nur anbieten, nicht als Standard; an Erholungstagen nicht anbieten |
| **Soll** | **Meilenstein-Hinweis** | Höchstens einer, und nur wenn er nah ist: „Noch 6 km bis 100 km auf dem Zürichsee“ | Summen je Gewässer | Kompetenz (Zielgradient) | Konfetti-Inflation → wenige, bedeutsame Schwellen, eine ruhige Feier nach der Fahrt statt auf dem Start |
| **Später** | **Nächstes Rennen** | Karte oberhalb der Wochen: Rennen, Server, Startzeit, Strecke, „Angemeldet“ | RowServer, raceId | Zugehörigkeit | Leere Versprechen → die Karte gibt es erst, wenn ein Server abonniert ist. Bis dahin ist der Platz nicht reserviert |
| **Später** | **Saison- und Wetterhinweis** | „Diese Woche: Winter auf dem Rhein“ als Variante der Heute-Karte | weather/season | Neugier, Abwechslung | Künstliche Verknappung → keine Fristen, die etwas wegnehmen |

## 3. Ideen kritisch bewertet

- **a) „Heute rudern“-Vorschlag. Stark, Kern des Entwurfs.** Die Regeln sind einfach und durchschaubar: nach harter Einheit locker, nach 3+ Tagen Pause kurz und leicht, Strecke abwechseln, Wochentag merken. Die Begründung wird immer angezeigt. Der Vorschlag nimmt eine Entscheidung ab, ohne sie wegzunehmen. Autonome Motivation sagt Training und Durchhalten besser voraus als kontrollierte [1]. Risiko: Undurchsichtige „KI-Empfehlungen“ schwächen das Gefühl, selbst zu steuern. Systeme, die selbsttätig das Nächste vorgeben, mindern dieses Gefühl nachweislich [3]. Deshalb gilt: Regeln statt Black Box, und „Anderer Vorschlag“ ist immer da.
- **b) Fortschritt über Wochen. Stark.** Die Wochensicht verzeiht mehr als die Tagessicht: Ein verpasster Tag fällt im Wochenbalken kaum auf. Daten aus Apple Health machen das Bild ehrlich (Velo oder Laufen zählt mit, grau). Risiko: Das Band wird zum Leistungsdruck. Deshalb keine Trendpfeile nach unten und keine „schlechteste Woche“.
- **c) Bestmarken je Strecke, Geisterboot. Stark für Falk, mit Mass einzusetzen.** Der Vergleich mit sich selbst bedient Kompetenz ohne sozialen Druck. Die Daten (Samples mit Zeit und Distanz) liegen schon vor. Als Kriterium zählt die Bestzeit über die volle Strecke, nicht einzelne Splits. Risiko: Wer jede Fahrt gegen die Bestzeit fährt, erholt sich nicht mehr. Deshalb ist das Geisterboot opt-in und wird auf Zone-2-Tagen nicht angeboten.
- **d) Seen-Pass, Streckensammlung. Mittel.** Für einen Landschaftsliebhaber passt das gut: Stempel als kleine Ortsgrafik („Luzern, 3 Fahrten, 11,4 km“). Bei 5 Strecken ist die Sammlung aber schnell voll. Danach muss der Wert aus Tiefe kommen (Saisons, Bestzeiten), nicht aus Vollständigkeit. Nicht bauen: gesperrte Strecken oder „Freischalten durch Leistung“, das macht die Landschaft zum Köder.
- **e) Wohlwollende Wochenziele statt Streaks. Stark, mit Belegen.** Das Ziel lautet etwa „3 Fahrten pro Woche, 1 Joker“. Ziele mit eingeplantem Spielraum werden bevorzugt und führen zu mehr Durchhalten als harte Ziele ohne Puffer [4]. Ein kleiner Replikationsversuch fand den Effekt nicht. Gerissene Streaks senken die weitere Beteiligung deutlich, vor allem wenn man sich selbst die Schuld gibt. Abgemildert wird das, wenn sich die Serie „reparieren“ lässt [5]. Duolingo setzt deshalb auf Streak Freeze [6]. Für RowCoach folgt daraus: Es gibt **keinen Tages-Streak**, sondern eine Wochenserie mit Joker. Eine Unterbrechung wird nie auf dem Startbildschirm hervorgehoben. Neue Wochen und Monate sind natürliche Neuanfänge, an denen Menschen eher neue Ziele beginnen [7]. Montags und am Monatsersten bietet die App deshalb ein neues Ziel an.
- **f) Meilensteine („100 km Zürichsee“). Mittel.** Die Grösse ist gut zu greifen und hat einen Ortsbezug. Ein Meilenstein wirkt aber nur, wenn er selten und nah ist. Vorschlag: wenige Schwellen je Gewässer (25, 100, 250, 500 km) und Lebenssummen (100, 500, 1000 km). Angezeigt wird höchstens ein naher Meilenstein, und zwar nur dann, wenn er in 1–2 Fahrten erreichbar ist.
- **g) Saisonale Herausforderungen. Später, mit Vorsicht.** Wenn es die Wettervarianten gibt, ist „Winter auf dem Rhein“ eine schöne Abwechslung. Die Herausforderung bleibt aber eine Einladung ohne Frist. Fear of missing out passt nicht zu einer Open-Source-App ohne Geschäftsmodell.
- **h) Sozialer Vergleich und Rennen. Später, gut geeignet.** Gamifizierung wirkt im Mittel klein bis mittel auf körperliche Aktivität [8]. Im STEP-UP-Versuch war Wettbewerb unter den sozialen Varianten am wirksamsten und hielt als einzige nach dem Spiel an [9]. Bei Zwift-Nutzern war der Wettbewerb im Spiel dagegen kein Haupttreiber; wichtiger waren Gesundheit, Training und Geselligkeit [10]. Für den RowServer heisst das: freiwillige Rennen mit Menschen, die man kennt, statt globaler Ranglisten.

## 4. Bewusst nicht tun

- Keine Tages-Streaks, keine Flammen-Symbole, keine Push-Nachrichten „Deine Serie ist in Gefahr“.
- Keine roten Zahlen, keine Abwärtspfeile, kein „du warst schon 5 Tage nicht da“. Pausen bleiben neutral.
- Keine Punkte, Münzen oder Level, die nichts über das Rudern aussagen. Kein virtuelles Geld.
- Keine gesperrten Strecken oder Programme, kein „Pro“ und keine Abo-Hinweise.
- Keine globalen Ranglisten und kein Vergleich mit Fremden auf dem Startbildschirm.
- Keine Überraschungsbelohnungen mit variablem Rhythmus. Sie erzeugen Wollen ohne Mögen [11] und passen nicht zu einem Trainingswerkzeug.
- Keine leeren Platzhalter für Rennen oder Community, bevor es sie gibt.
- Nicht mehr als drei Informationsblöcke. Der Startbildschirm ist eine Startrampe, kein Dashboard; Auswertungen gehören in „Verlauf“.

## 5. Quellen

1. Teixeira, Carraça, Markland, Silva, Ryan (2012): Exercise, physical activity, and self-determination theory: a systematic review. *IJBNPA* 9:78. https://doi.org/10.1186/1479-5868-9-78 (Fundus study:1036)
2. Fogg, B. J. (2009): A Behavior Model for Persuasive Design; behaviormodel.org. https://behaviormodel.org/ (Fundus fact:1600)
3. Lukoff et al. (2021): How the Design of YouTube Influences User Sense of Agency. *CHI 2021*. https://doi.org/10.1145/3411764.3445467 (Fundus study:664)
4. Sharif, Shu (2017): The Benefits of Emergency Reserves. *Journal of Marketing Research* 54(3). https://doi.org/10.1509/jmr.15.0231 (Fundus study:1038; schwache Gegenprobe: Utrecht-Masterarbeit, n = 11 in der Reserve-Gruppe)
5. Silverman, Barasch (2023): On or Off Track: How (Broken) Streaks Affect Consumer Decisions. *Journal of Consumer Research* 49(6). https://doi.org/10.1093/jcr/ucac029 (Fundus study:1039)
6. Duolingo (2022): How the Duolingo streak builds habit. https://blog.duolingo.com/how-duolingo-streak-builds-habit (Firmenquelle, korrelativ; Fundus practice:606)
7. Dai, Milkman, Riis (2014): The Fresh Start Effect. *Management Science* 60(10). https://doi.org/10.1287/mnsc.2014.1901 (Fundus study:1041)
8. Mazéas et al. (2022): Gamification for physical activity: meta-analysis of RCTs. *JMIR* 24(1):e26779. https://www.jmir.org/2022/1/e26779 (g = 0.42; Fundus study:1037)
9. Patel et al. (2019): STEP UP Randomized Clinical Trial. *JAMA Internal Medicine* 179(12). https://doi.org/10.1001/jamainternmed.2019.3505 (Fundus study:1040)
10. NC State / Universität Münster (2021): Studie zu Zwift-Nutzungsmotiven, 284 Nutzer, *Journal of Business Research*. Zusammenfassung: https://news.ncsu.edu/2021/06/why-mixed-reality-sports
11. Berridge, Robinson (2016): Liking, wanting, and the incentive-sensitization theory of addiction. *American Psychologist*. https://doi.org/10.1037/amp0000059 (Fundus study:659)

Hinweis: Die Belege 4, 5, 7, 8 und 9 wurden über Abstracts und Zusammenfassungen geprüft, nicht im Volltext. In Fundus sind sie unter `rowcoach` als „unverified“ abgelegt. In Zotero fanden sich zum Thema keine Artikel.
