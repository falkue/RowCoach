# Review Diversity, Gender und inklusives Design – Figuren und Profil (Stand 26.11.2026)

Unabhängige, kritische Prüfung der Figurtypen und Profilangaben von RowCoach für ein internationales Publikum
(CH, DE, FR, UK, JP, PL, später Südamerika, USA). Geprüft wurden die Bilder selbst (`docs/avatar/overview-figures.png`,
`App/RowCoach/Resources/AvatarPreviews/char-*.png`, `docs/avatar/palette.png`), die Daten
(`App/RowCoach/Resources/appearance.json`), `docs/avatar/DESIGN.md` und `SPEC.md`, die Oberfläche
(`App/RowCoach/Views/ProfileView.swift`), das Modell (`RowCoachKit/Avatar/RowerProfile.swift`), die Szene
(`App/RowCoach/Scene3D/RowerFigure.swift`) und der Generator (`tools/avatars/figure.py`). Nichts gerendert oder gebaut.

---

## Gesamturteil: GELB

Die Grundlage ist besser als in vielen Fitness-Apps: Monk-Skala statt Fitzpatrick, Typnamen ohne Geschlecht,
Geschlecht bleibt auf dem Gerät, Trikotfarben auf Farbsehschwäche geprüft. Drei Dinge verhindern aber ein Grün:

1. **„Frei kombinierbar“ stimmt nur für Farben.** Frisur, Körperbau, Grösse, Kleidung und Accessoires hängen fest am
   Typ (`RowerAppearance` kennt nur `skinToneId`, `hairColorId`, `shirtColorId`). Damit wird der Körper über die Frisur
   gegendert: alle langen Frisuren sind `slim` und kleiner (Höhe 0,95–0,99), alle kurzen/kahlen `broad` und grösser
   (1,04–1,06). Eine Frau mit Buzzcut bekommt zwangsläufig den breiten, grossen Körper, ein Mann mit langem Haar den
   schmalen, kleinen. Der Footer „unabhängig von Geschlecht“ verspricht mehr, als die App hält.
2. **Dunkle Hauttöne verlieren im Bild das Gesicht.** Bei char-07 und char-09 (MST 9/10) sind Gesicht, Augen und Haar
   eine fast schwarze Fläche; die Augen sind dunkle Ellipsen auf dunkler Haut, der Afro (schwarz auf MST 9, Kontrast 1,4
   laut DESIGN.md) liest sich wie ein Helm. Umgekehrt wirken MST 1–3 im 3D grau-weiss wie Schaufensterpuppen; die drei
   hellsten Töne sind im Render praktisch gleich. Zusammen mit der Sonnenbrille als Standard (5 von 10 Typen) entstehen
   gesichtslose Figuren – hell wie Crashtest-Dummys, dunkel wie Silhouetten.
3. **Wichtige Gruppen fehlen ganz:** Kopfbedeckungen aus religiösen/kulturellen Gründen (Sport-Hijab, Patka/Turban),
   lange Sportkleidung, Bart, sichtbar ältere und fülligere Körper, Para-Ruderer.

Keiner dieser Punkte ist schwer zu beheben; der grösste Hebel (Entkoppeln) ist reine Kit-/UI-Arbeit, weil die Szene
`look.hairStyle`, `look.build`, `look.accessories` usw. schon einzeln auswertet.

---

## Stärken

- **Hauttöne nach Monk Skin Tone Scale** (10 Stufen, mehr Abstufung im dunklen Bereich als Fitzpatrick), jeder Ton
  genau einmal als Standard, Lizenz und Herkunft dokumentiert.
- **Typnamen beschreiben Aussehen, nicht Geschlecht oder Herkunft** (SPEC-Regel; im Englischen durchgehend erfüllt).
- **Datensparsamkeit:** Geschlecht geht nie an andere, Nationalität nur mit Flaggen-Schalter, „Keine Angabe“ ist
  Standard (`gender == nil`), unbekannte Werte werden tolerant als „keine Angabe“ gelesen.
- **Neutraler Rumpf:** ein Torso für alle, keine sexualisierten Körpermerkmale, keine Brust-/Hüft-Schalter nach Geschlecht.
- **Trikotpalette Okabe-Ito**, mit Simulation geprüft (ΔE2000 > 10 auch bei Protan/Deutan/Tritan).
- **Vielfalt an Haartexturen angelegt:** Afro, Locken, Zopf, Dutt, Glatze sind mehr als in vielen Ausdauer-Apps.
- **Masters ist mitgedacht** (char-10) – nur nicht sichtbar umgesetzt (siehe unten).
- **Accessibility-Labels** an den Farbtupfern vorhanden.

---

## Probleme nach Schwere

Aufwand: S = bis ½ Tag, M = 1–3 Tage, L = > 3 Tage.

### MUSS (vor öffentlichem Start)

**M1 Frisur, Körperbau, Grösse, Kleidung und Accessoires unabhängig wählbar machen (M).**
Problem: siehe Gesamturteil 1. Stärkste implizite Gender-Codierung im ganzen System; zudem verstärkt sie das Muster
„dunkel = breit, gross, kahl“ (char-02 MST 8 broad/buzz, char-09 MST 10 broad/kahl/gross). Forschung: Selbst gestaltete
Avatare erhöhen Identifikation, Autonomie und Spieldauer (Kao et al. 2022, aufbauend auf Birk et al. 2016).
Änderung:
- Kit: `RowerAppearance` um optionale Überschreibungen `hairStyle`, `build`, `heightScale`, `shirtStyle`,
  `accessories: [String]?` (nil = vom Typ) erweitern; `AppearanceCatalog.resolve` übernimmt sie; tolerantes Decoding
  wie bisher. `publicAppearance` geht unverändert mit (enthält keine Personendaten).
- UI (`ProfileView.colorSection` → „Anpassen“): Zeilen „Frisur“, „Körperbau“, „Grösse“ (klein/mittel/gross),
  „Oberteil“, „Brille/Kopf/Handgelenk“. Typen werden zu **Startvorlagen**; ein Typwechsel setzt wie heute zurück, mit
  Hinweis.
- Footer ehrlich formulieren: „Die Vorlagen sind nur Startpunkte – alles lässt sich frei kombinieren.“
- `RowerFigure.swift` braucht keine Änderung (liest `look.*` schon einzeln).

**M2 Dunkle und sehr helle Hauttöne erkennbar darstellen (M).**
Problem: siehe Gesamturteil 2. Augen: `RigLook.eyes` dunkel → auf MST 8–10 unsichtbar. Haar Schwarz #1E1A18 auf
MST 9/10 ohne Kontrast. MST 1–3 werden zu Grau.
Änderung:
- Generator/Szene: Augen zweifarbig (helle Sklera bzw. kleiner heller Glanzpunkt, `eyes_mesh()` um zwei winzige
  Ellipsoide ergänzen, Materialgruppe `eyes_hl`) – auf jedem Hautton sichtbar.
- Szene: Hautmaterial mit leichtem warmem Specular/„Sheen“ und Fülllicht bzw. Rim-Light von der Kamera, damit dunkle
  Haut Form und Glanz behält (Prüfregel: Gesichtsmitte von MST 10 im Render nicht unter ~L* 15, Haar gegen Haut
  über Glanzkante unterscheidbar). Für Haar auf dunkler Haut Roughness 0,9 → 0,7 und schmale Glanzkante.
- Helle Töne: Tonemapping/Weissabgleich so prüfen, dass MST 1–3 warm bleiben und sich unterscheiden (Testbild mit
  allen 10 Tönen nebeneinander in der Szene, als Abnahme in SPEC.md aufnehmen).
- Abnahme: ein Kontaktbogen „10 Hauttöne × 3 Lichtsituationen (Sonne, bedeckt, Gegenlicht)“ vor jedem Release.

**M3 Sonnenbrille nicht als Standard; Gesichter nie leer (S).**
Problem: 5 von 10 Vorlagen tragen Brille, die die Augen ausblendet (`eyes.hide()`); mit hellem Visier-Rahmen auf
dunkler Haut (char-09) und grauer Haut (char-01, -03, -10) wirkt das wie ein Roboter/Dummy und ist in Rennen der
einzige Gesichtseindruck. Unfreiwillig komisch: die Cap von char-10 sieht aus wie ein Reithelm.
Änderung: `appearance.json` – `sunglasses` bei höchstens 2 Vorlagen; Brille als frei wählbares Accessoire (M1).
Cap im Generator (`cap_mesh`) flacher, Schirm länger und weicher, Haar seitlich unter der Cap sichtbar lassen.

**M4 Sport-Kopftuch und lange Sportkleidung (M).**
Problem: Für muslimische Ruderinnen (und viele andere, die bedeckt trainieren) gibt es keine Darstellung; ein Kopftuch
allein reicht nicht, weil alle Oberteile kurz sind und Beine nackt.
Änderung:
- Generator: `hair_parts()` bzw. neues Kopf-Accessoire `hijab` (Schale um Kopf, Hals und Schulteransatz, aus
  `hair_cap(...)` mit tiefem `h_back` und Halsverlängerung), Materialgruppe `headwear`, Farbe frei (Trikotpalette).
- Kleidung: `shirtStyle` `longsleeve` (Ärmel bis Handgelenk: `forearm`-Mesh mit `split_faces` wie bei `tee`) und
  `leggings` (Shorts-Prädikat `shorts_pred(0.48)` + `shin`-Split bis Socke) – im Generator je S.
- UI: „Kopf“ = keine / Cap / Stirnband / Sport-Kopftuch / Patka (M5); „Beine“ = kurz / lang.

### SOLLTE (bald nach Start)

**S1 Patka/Turban, Bart (M).** Patka (der im Sport übliche kleine Turban) als Kopf-Accessoire wie M4; Bart
(kurz/voll) als eigene Option mit Haarfarbe – heute gibt es überhaupt keine Gesichtsbehaarung, was Masters-Männer,
Sikhs und viele andere ausschliesst. Generator: Bart = Schale am Unterkiefer (`_shell_dirs` mit negativem `h_front`).
Kippa: als kleines Kopf-Accessoire (S), unter Cap ausblenden.

**S2 Körperbau und Alter breiter fassen (M).**
Heute: `slim`/`athletic`/`broad` – alle drei sind Leistungssportkörper. Rudern am Ergometer betreiben viele mit
höherem Gewicht und viele über 60.
- `build`: `slim`, `athletic`, `strong` (heute broad), `full` (Torso mit Bauch: `_torso_rings(..., inflate=)` mit
  zusätzlichem Profil im unteren Rumpf, Gliedradius +18 %). Grösse unabhängig (M1).
- Alter sichtbar machen: graues/silbernes Haar bei einer Vorlage **ohne** Cap; optional „Haaransatz zurückgehend“
  als Frisur (`hair_cap` mit kleinerem `h_front`).
- Vorsicht Proteus-Effekt: Zugewiesene schwere Avatare senkten in Experimenten die Aktivität (Peña et al. 2016).
  Deshalb `full` nur als **eigene Wahl** anbieten – nie als Standard, nie für Bots/Verkehr, nie als
  „Strafe“/Visualisierung von Gewicht. Für Bots die Vorlagen ohne `full` ziehen.

**S3 Para-Rudern darstellen (M–L).**
Realistisch am Ergometer: PR1 (Arme und Schultern, fester Sitz mit Rückenlehne/Gurt), PR2 (Rumpf und Arme, fester
Sitz), PR3 (Beine, Rumpf, Arme – u. a. Amputation, Sehbehinderung); Concept2 und World Rowing Indoor führen diese
Klassen. Vorbilder: Xbox (Prothesen, Rollstuhl seit 2017), Zwift (Handbike; Prothesen angekündigt), Apple Memoji
(Cochlea-Implantat, Sauerstoffschlauch, Soft-Helm seit 2021).
- Stufe 1 (S–M): **Unterschenkelprothese** links/rechts – Carbon-Pylon statt `shin__skin` auf einer Seite. Die Szene
  hat je Seite eigene Slots (`shinA[i]`), es braucht nur ein zweites Mesh `shin_prosthesis__accessory`.
- Stufe 2 (M): **Fester Sitz (PR1/PR2)** – Animation mit konstanter Hüfte (`hipZ` fix, Bewegung aus Rumpf/Armen),
  Sitz mit Rückenlehne; auf dem Wasser Ausleger mit Schwimmern. Sinnvoll, weil die Trainingsdaten bei PR1/PR2
  ohnehin ohne Rollbewegung entstehen.
- Stufe 3 (L, kann): Armprothese mit Griffadapter.
- Sehbehinderung nicht über Klischee-Symbole darstellen; wer will, kann eine Brille wählen.
- Mit Betroffenen testen (z. B. über einen Para-Ruderverein), bevor es veröffentlicht wird – Zwift hat das mit der
  Challenged Athletes Foundation gemacht und trotzdem Kritik für zu wenig Optionen bekommen.

**S4 Geschlechtsfeld: Zweck klären, sonst streichen (S).**
Befund: `gender` wird nirgends im Code benutzt (nur gespeichert). Das widerspricht der Datensparsamkeit (DSGVO Art. 5
Abs. 1 lit. c, revDSG Art. 6) und schafft eine heikle Frage ohne Nutzen. Dazu: „Divers“ ist ein deutscher Rechtsbegriff
(Personenstand), im Ausland unverständlich; die englische Übersetzung „Non-binary“ meint etwas anderes. „Weiblich/
Männlich“ sind Adjektive, die eher nach biologischem Geschlecht klingen; im Polnischen und Französischen sind solche
Adjektive selbst gegendert („niebinarna/niebinarny“).
Empfehlung (in dieser Reihenfolge):
1. **Feld vorerst entfernen**, bis eine Funktion es braucht (S). Gespeicherte Werte beim nächsten Speichern verwerfen.
2. Wenn Ranglisten kommen: nicht „Geschlecht“ fragen, sondern **„Wertung in Ranglisten“: Frauen / Männer / Offene
   Wertung / nicht teilnehmen**, mit einem Satz, wofür es dient (Concept2 und World Rowing werten nach Frauen/Männern,
   Alter, Gewicht, PR-Klasse). Das trennt Identität von Wettkampfklasse und ist international verständlich.
3. Wenn Berechnungen Referenzwerte brauchen (Kalorien, Pulsformeln): eigene, erklärte Frage „Referenzwerte für
   Berechnungen: weiblich / männlich / keine (Durchschnitt)“ – nicht mit Identität vermischen.
4. Falls doch ein Identitätsfeld gewünscht ist: optional, Substantive statt Adjektive – de „Frau / Mann / Nicht-binär /
   Selbst beschreiben … / Möchte ich nicht sagen“, en „Woman / Man / Non-binary / Prefer to self-describe / Prefer
   not to say“ (Spiel, Haimson & Lottridge 2019). „Keine Angabe“ ist als Standard gut.

**S5 Hautton-Namen neutral (S).**
„Porzellan, Elfenbein … Espresso, Ebenholz“ folgen dem bekannten Muster, Haut mit Lebensmitteln und Luxusmaterialien
zu benennen (Elfenbein/Ebenholz ist ein historisch rassifiziertes Begriffspaar); „Oliv“ für MST 6 beschreibt eher einen
Unterton als eine Helligkeit. Änderung `appearance.json`: Namen „Hautton 1“ … „Hautton 10“ (en „Skin tone 1“ …),
VoiceOver-Zusatz „sehr hell“, „hell“, „mittel“, „dunkel“, „sehr dunkel“. DESIGN.md sagt selbst: „in der Auswahl reichen
die Farbtupfer“.

**S6 Standard-Zuordnung Hautton ↔ Frisur/Körper entstereotypisieren (S).**
Heute: Afro nur bei MST 9, die beiden breiten Typen bei MST 8 und 10, Kahl+gross+Uhr+Brille bei MST 10, Blond nur bei
MST 2, Masters nur bei MST 1. Einzeln ist jede Kombination plausibel; als Satz ergibt sich „dunkel = gross, kräftig,
kahl“ und „hell = alt, schlank, Pferdeschwanz“. Da die Vorlagen der erste Eindruck sind (und Bots sie verwenden):
neue Verteilung siehe Typenliste unten. Dunkle Töne bekommen auch „neutrale“ Frisuren (Kurzhaar, Pferdeschwanz),
damit sie nicht nur über Haartextur definiert sind.

**S7 Deutsche Beschreibungen gendern im generischen Maskulinum (S).**
„Klassischer Rennruderer“ (char-01), „Masters-Ruderer“ (char-10) – im Englischen neutral, im Deutschen nicht.
Änderung: „Klassischer Renn-Look: …“, „Masters-Look mit Schirmmütze …“. Auch „Glatze“ (umgangssprachlich, im Deutschen
teils mit Skinheads verbunden) → „Kahl rasiert“; „Buzzcut“ → „Raspelkurz“ (en bleibt „Buzz cut“).

**S8 Keine Vorauswahl einer hellen Standardfigur (S).**
`defaultCharacterId = "char-01"` (heller Hautton, kurze Haare) erscheint, bevor jemand wählt – die implizite Norm.
Änderung: im Onboarding Figur wählen lassen („Wie willst du im Boot aussehen?“) oder zufällige Vorlage; bis dahin eine
Vorlage mit mittlerem Hautton.

### KANN (später)

- **K1 Haartexturen ergänzen (M):** Box Braids/Cornrows, Locs (gebunden), Afro-Puffs, kurze Locken/TWA, Hijab-Variante
  „Sport-Unterkappe“. Generator: Zöpfe aus `tube_path` (wie `braid`), Locs als Bündel von Kapseln.
- **K2 Grösse unabhängig von Körperbau** mit drei Stufen (0,94 / 1,0 / 1,06) – schon in M1 enthalten, hier nur, falls
  M1 schrittweise kommt.
- **K3 Brillen** (normale Sportbrille mit klaren Gläsern), Hörgerät/Cochlea-Implantat (Memoji-Vorbild), Kompressions-
  socken, Knie-Tape.
- **K4 Nationalität**: „Land/Flagge, für das du ruderst“ statt „Nationalität“ (Doppelbürger, Wohnsitzland, staatenlos);
  mehrere Flaggen nicht nötig, aber Wortlaut offener.
- **K5 Lokalisierung**: Heute nur de/en (`Localizable.xcstrings`). Für FR, JA, PL Gender- und Hautton-Begriffe mit
  Muttersprachlern prüfen (Polnisch: gegenderte Adjektive vermeiden).
- **K6 Optionaler Oberkörper „mit Brust“** als freie Formwahl, nie an das Geschlechtsfeld gekoppelt. Der neutrale
  Torso ist eine gute Standardlösung; kein Muss.

---

## Vorschlag: überarbeitete Vorlagen (12) + freie Kombination

Grundsatz: Vorlagen sind Startpunkte, jede Eigenschaft ist einzeln änderbar (M1). Jeder Hautton genau einmal plus
zwei Wiederholungen im mittleren Bereich; jede Körperform mindestens einmal bei hellem und dunklem Ton; Brille nur
zweimal; `full` und Prothese nie für Bots.

| id | Name de / en | Hautton | Frisur / Kopf | Haar | Körper, Grösse | Oberteil / Beine | Extras |
|---|---|---|---|---|---|---|---|
| char-01 | Kurzhaar / Short hair | MST 6 | short | dunkelbraun | athletic, mittel | Einteiler / kurz | – |
| char-02 | Raspelkurz, kräftig / Buzz cut, strong | MST 3 | buzz | hellbraun | strong, mittel | Tanktop / kurz | Uhr |
| char-03 | Pferdeschwanz / Ponytail | MST 9 | ponytail | schwarz (mit Glanzkante) | strong, gross | Einteiler / kurz | – |
| char-04 | Dutt / Bun | MST 2 | bun | kastanienrot | athletic, klein | Tanktop / kurz | Sportbrille |
| char-05 | Box Braids / Box braids | MST 8 | braids (K1) bzw. braid | schwarz | athletic, mittel | T-Shirt / kurz | Stirnband |
| char-06 | Locken / Curls | MST 5 | curly | braun | slim, mittel | T-Shirt / kurz | – |
| char-07 | Afro / Afro | MST 7 | afro | dunkelbraun | slim, gross | Einteiler / kurz | – |
| char-08 | Sport-Kopftuch / Sports hijab | MST 4 | hijab | – | athletic, klein | Langarm / lang | Uhr |
| char-09 | Patka mit Bart / Patka with beard | MST 6 | patka | schwarz, Vollbart | strong, gross | T-Shirt / kurz | – |
| char-10 | Kahl rasiert mit Bart / Shaved head with beard | MST 1 | bald | grau, kurzer Bart | full, mittel | T-Shirt / kurz | – |
| char-11 | Silberhaar / Silver hair (Masters) | MST 10 | short oder long, ohne Cap | silberweiss | slim, klein | Langarm / lang | Sportbrille |
| char-12 | Langes Haar, Prothese / Long hair, prosthetic leg | MST 5 | long | blond | athletic, mittel | Tanktop / kurz | Unterschenkelprothese rechts |

Freie Optionen daneben: Frisur (alle), Haarfarbe, Bart (keiner/kurz/voll), Kopf (keine/Cap/Stirnband/Kopftuch/Patka/
Kippa), Brille (keine/Sportbrille/klar), Körper (slim/athletic/strong/full), Grösse (klein/mittel/gross), Oberteil
(Einteiler/Tanktop/T-Shirt/Langarm), Beine (kurz/lang), Prothese (keine/links/rechts), Sitz (rollend/fest – S3).
Namen der Vorlagen nur nach Aussehen; char-12 alternativ „Langes Haar“ mit Prothese nur als Option, falls Para-Nutzer
im Test eine Vorlage lieber nicht wollen (mit ihnen klären).

---

## Vorbilder (Kurzvergleich)

| Vorbild | Was es gut macht | Lücke |
|---|---|---|
| Apple Memoji | Alles frei kombinierbar; Cochlea-Implantat, Sauerstoffschlauch, Soft-Helm (2021) | Kein Körper |
| Xbox Avatars (2017) | Körperformen, Prothesen, Rollstühle, Schwangerschaft | Prothese nicht mit Accessoires kombinierbar |
| Zwift | Handbike für adaptive Athleten, mit Challenged Athletes Foundation erforscht | Prothesen nur angekündigt, Kritik aus der Community |
| Nike Run Club, Strava | Kein Ganzkörper-Avatar (Foto/Initialen) – umgehen das Thema | Keine Repräsentation im Spiel |
| Microsoft Inclusive Design | „Recognize exclusion, solve for one – extend to many, learn from diversity“ | Methodik, keine Vorgaben |

---

## Umsetzung in Reihenfolge

1. M3, S5, S7, S8, S6 – nur `appearance.json` und Strings (zusammen ≈ ½–1 Tag).
2. M1 Entkoppeln (Kit + UI), S4 Geschlechtsfeld (≈ 2–3 Tage).
3. M2 Licht/Augen mit Abnahmebogen (≈ 1–2 Tage, braucht Render auf dem Mac).
4. M4 + S1 Kopfbedeckungen, Langarm, Leggings, Bart (≈ 3 Tage Generator).
5. S2 `full` und Masters, S3 Para Stufe 1–2 (≈ 3–5 Tage, mit Nutzertest).

---

## Quellen

- Peña, J., Khan, S. & Alexopoulos, C. (2016): I Am What I See: How Avatar and Opponent Agent Body Size Affects
  Physical Activity Among Men Playing Exergames. Journal of Computer-Mediated Communication 21(3), 195–209.
  https://doi.org/10.1111/jcc4.12151 (Fundus study:1066)
- Kao, D. et al. (2022): Audio Matters Too: How Audial Avatar Customization Enhances Visual Avatar Customization.
  CHI 2022. https://arxiv.org/pdf/2202.05315 (Fundus study:1067)
- Birk, M. V., Atkins, C., Bowey, J. T. & Mandryk, R. L. (2016): Fostering Intrinsic Motivation through Avatar
  Identification in Digital Games. CHI 2016, 2982–2995. https://doi.org/10.1145/2858036.2858062
- (2021): Exercising With a Six Pack in Virtual Reality (Proteus-Effekt Körperform und Geschlecht).
  Frontiers in Psychology. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8531811/
- (2021): Exercising With Embodied Young Avatars (ältere Personen, junge vs. alte Avatare).
  https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8572814/
- Spiel, K., Haimson, O. L. & Lottridge, D. (2019): How to do better with gender on surveys. Interactions 26(4), 62–65.
  https://doi.org/10.1145/3338283 ; PDF https://deepblue.lib.umich.edu/bitstream/2027.42/154050/1/SpielHowTo.pdf
  (Fundus fact:2444)
- Concept2: Adaptive Classifications (PR1, PR2, PR3, FES). https://www.concept2.co.uk/training/adaptive/classifications
  (Fundus fact:2445); World Rowing: Indoor Adaptive Rowing Categories and Eligibility Requirements (11/2025).
  https://worldrowing.com/wp-content/uploads/2025/11/World-Rowing-Indoor-Adaptive-Rowing-Categories-and-Eligibility-Requirements.pdf
- Zwift: Handcycle FAQ. https://support.zwift.com/en_us/handcycle-faq-Sk_Zm9Rys (Fundus practice:996);
  Cycling Weekly: Zwift will add disabled athlete representation …
  https://cyclingweekly.com/news/zwift-will-add-disabled-athlete-representation-to-platform-after-completing-large-research-study
- Apple Newsroom (05/2021): Apple previews powerful software updates designed for people with disabilities (Memoji:
  Sauerstoffschlauch, Cochlea-Implantat, Soft-Helm).
  https://www.apple.com/newsroom/2021/05/apple-previews-powerful-software-updates-designed-for-people-with-disabilities/
- GamesRadar: Xbox One Avatars will support wheelchairs, prosthetic limbs, pregnancy …
  https://gamesradar.com/xbox-one-avatars-will-support-wheelchairs-prosthetic-limbs-pregnancy-unicorns-and-a-lot-more
- Microsoft Inclusive Design Toolkit. https://inclusive.microsoft.design/
- Monk Skin Tone Scale (Google, CC BY 4.0). https://skintone.google/ (Fundus fact:2438)

Recherche: Zotero (`zrag search`) ohne passende Treffer, `zrag semantic` brach mit Zeitüberschreitung ab; Fundus hatte
nichts zu Avataren/Diversity; Rest aus dem Web. Neue Fundus-Einträge (project `rowcoach`, unverifiziert): study:1066,
study:1067, fact:2444, practice:996, fact:2445.


## Entscheidung Falk (26.11.2026)
- Geschlechtsfeld im Profil wird gestrichen: man wählt eine Figur, kein Geschlecht.
- Reihenfolge der Umsetzung: (1) alles einzeln wählbar, Typen als Startvorlagen; (2) Licht und Gesichter für alle Hauttöne, Sonnenbrille selten, neue Cap; (3) Sport-Kopftuch mit Langarm/langen Beinen, Patka, Bart; (4) Geschlechtsfeld entfernen; schnelle Korrekturen (Namen, Vorlagen-Verteilung, keine helle Vorauswahl); danach (5) füllig, Masters silber, Para in Stufen.
