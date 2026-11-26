# Figur und Boot – Gestaltung (Stand 26.11.2026)

Baustein 1 „Gestaltung“ aus [SPEC.md](SPEC.md). Verbindlicher Katalog: `App/RowCoach/Resources/appearance.json`
(10 Hauttöne, 10 Haarfarben, 10 Trikotfarben, 10 Figurtypen, 8 Bootsstile). Übersichtsbild: [palette.png](palette.png)
(mit PIL gezeichnet, keine fremden Bilder).

Offene Entscheidung für Falk: **Herstellernamen anzeigen oder nicht?** (Abschnitt 5, Frage am Ende).

---

## 1. Bildsprache

### Vorbilder und was wir von ihnen übernehmen
| Vorbild | Was es gut macht | Was wir übernehmen |
|---|---|---|
| Zwift-Avatare (Rad/Lauf-Plattform mit vielen Mitfahrenden) | Figuren in einer realistischen Landschaft, aus Distanz an Trikotfarbe und Silhouette erkennbar | Trikot als grösste Farbfläche und Erkennungsmerkmal; Figur nicht comicartig von der Szene abgelöst |
| Apple Memoji / Nintendo Mii | Vielfalt aus wenigen Bausteinen (Kopfform, Haarform, Haut, Accessoire), freundliche Proportionen | Baukasten: Haut, Haar, Trikot frei kombinierbar; leicht vergrösserter Kopf, minimale Gesichter |
| Alto’s Odyssey / Monument Valley | Reduzierte, weiche Formen, ruhige Flächenfarben, die im Tageslicht stimmig wirken | Einfarbige Flächen ohne Texturrauschen, weiche Übergänge, keine harten Kanten |
| Low-Poly mit glatten Normalen (z. B. „Smooth Low Poly“ in Mobile-Spielen) | Wenig Dreiecke, aber durch glatte Normalen rund wirkend | 2–4 k Dreiecke je Figur, Kapseln und Ellipsoide statt Kästen, Smooth Shading |

### Regeln
1. **Proportionen:** Kopf etwas grösser als real, Kopfhöhe ≈ 1/6,5 der (gedachten) Stehhöhe statt ≈ 1/7,5.
   Bei 1,80 m Stehhöhe: Kopfhöhe 0,27–0,28 m (Kopf-Ellipsoid ca. 0,20 × 0,25 × 0,22 m B × H × T; heute Kugel r = 0,11).
   Hände und Füsse leicht vergrössert (+10 %), damit Griff und Stemmbrett lesbar sind. Rumpf-Segmentlängen wie heute
   (`BoatRig.D`: Oberkörper 0,50, Ober-/Unterschenkel je 0,48), damit `StrokePose` passt.
2. **Formen:** Kapseln (Arme, Beine, Hals), abgerundeter Torso (Kapsel mit flacher Vorderseite, Taille leicht schmaler),
   Ellipsoid-Kopf, Gelenke durch Überlappung der Kapseln statt sichtbarer Kugeln. Keine Kästen, keine scharfen Kanten
   ausser Blatt und Ausleger.
3. **Flächen:** einfarbig, keine Fototexturen. Unterscheidung über Roughness:
   Haut 0,65, Haar 0,8 (Locken/Afro 0,9), Trikot 0,75 (Einteiler-Lycra 0,45 mit leichtem Glanz), Shorts 0,8,
   Schuhe/Socken 0,7, Sonnenbrille 0,15 (Gläser leicht metallisch, metallic 0,6), Boot `gloss` 0,25,
   `matte` 0,7, `carbon` 0,35 + sehr feines Köpermuster nur als Normal-/Roughness-Variation (optional, ab LOD 0).
4. **Gesichter:** minimal. Entweder Sportsonnenbrille (Rahmen in Akzentfarbe, Gläser dunkel verspiegelt) oder zwei
   angedeutete Augen (flache dunkle Ellipsen, 0,018 m) – keine Münder, keine Brauen, keine Grimassen.
   Nase als sanfte Ausbuchtung im Ellipsoid (aus 20 m nicht mehr sichtbar, aber gibt Richtung).
5. **Kleidung:** Einteiler (`unisuit`, Träger + Shorts in einem, durchgehend Trikotfarbe mit dunkleren Seitenblenden),
   Tanktop (`tank`) oder T-Shirt (`tee`, kurze Ärmel bis Mitte Oberarm) mit Shorts in Anthrazit #2B2C30.
   Kurze Socken weiss #F2F2EE, Schuhe am Stemmbrett dunkelgrau #3A3C40 (sind im Boot fest). Flagge als
   Brustaufnäher 0,10 × 0,07 m (Figur schaut zur Kamera) und optional Rücken.
6. **Lesbarkeit 5–60 m:** Auf 60 m ist eine Figur nur noch ~20–40 px hoch. Erkennbar bleiben müssen: Trikotfarbe,
   Kopfsilhouette (Frisur!), Blattfarbe, Rumpffarbe. Deshalb: Frisuren als klare Grossformen (Afro, Dutt, Pferdeschwanz
   ragen sichtbar aus dem Kopfumriss), Blätter in kräftiger Farbe, Trikotpalette auf Unterscheidbarkeit geprüft (Abschnitt 4).
   LOD-Vorschlag: ab ~30 m Hände/Füsse und Accessoires weglassen, Haar-Detailformen zu einer Kapsel/Kugel zusammenfassen.
7. **Licht und Szene:** PBR, Tageslicht, Geodaten-Landschaften. Keine reinen Weiss-/Schwarzwerte ausser Akzenten
   (Weiss #F2F2EE/#F4F4F1, Schwarz #1E1E1E–#26272B), damit Belichtung und Schatten nicht ausbrennen bzw. absaufen.

---

## 2. Figurtypen

Namen beschreiben die Erscheinung, nie Geschlecht oder Herkunft; Geschlecht und Nationalität wählt man im Profil
unabhängig. Alle zehn Hauttöne kommen genau einmal als Standard vor; jede Kombination ist im Profil überschreibbar.
Haarstile laut SPEC: 10 von 11 als `hairStyle`, `headband` als Accessoire (char-06).

| id | Name (de / en) | Statur | Höhe / Schulter | Haut | Haar | Haarfarbe | Trikot | Schnitt | Accessoires |
|---|---|---|---|---|---|---|---|---|---|
| char-01 | Kurzhaar mit Sonnenbrille / Short hair with sunglasses | athletic | 1,00 / 1,00 | skin-3 | short | darkbrown | navy | unisuit | sunglasses |
| char-02 | Buzzcut, kräftig / Buzz cut, strong build | broad | 1,04 / 1,12 | skin-8 | buzz | black | orange | tank | watch |
| char-03 | Pferdeschwanz / Ponytail | slim | 0,97 / 0,94 | skin-2 | ponytail | blonde | blue | unisuit | sunglasses |
| char-04 | Dutt / Bun | athletic | 0,98 / 0,98 | skin-6 | bun | black | yellow | tank | – |
| char-05 | Zopf mit Uhr / Braid with watch | slim | 0,95 / 0,93 | skin-5 | braid | auburn | green | unisuit | watch |
| char-06 | Locken mit Stirnband / Curls with headband | athletic | 1,00 / 1,02 | skin-4 | curly | brown | vermillion | tee | headband |
| char-07 | Afro / Afro | athletic | 1,02 / 1,04 | skin-9 | afro | black | skyblue | unisuit | – |
| char-08 | Langes Haar, offen / Long hair, loose | slim | 0,99 / 0,95 | skin-7 | long | darkbrown | white | tank | sunglasses |
| char-09 | Glatze, kräftig / Shaved head, strong build | broad | 1,06 / 1,10 | skin-10 | bald | (black) | purple | tank | sunglasses, watch |
| char-10 | Cap und graues Haar / Cap and grey hair | slim | 0,97 / 0,97 | skin-1 | cap | grey | black | tee | cap, sunglasses |

### Skizzen für den 3D-Agenten
Masse in Metern für `heightScale` = `shoulderScale` = 1,0 (Stehhöhe gedacht 1,80 m); skalieren: Längen mit
`heightScale`, Schulterbreite und Brustumfang mit `shoulderScale`. Statur: `slim` Glieder-Radius −10 %, `broad` +12 %,
Torso-Tiefe `broad` +10 %. Basis-Radien: Oberarm 0,045, Unterarm 0,038, Oberschenkel 0,075, Unterschenkel 0,055,
Hals 0,05 (Länge 0,08), Torso Kapsel 0,34 (B) × 0,50 (L) × 0,21 (T), Schulter-Halbbreite 0,17 (wie heute).
Kopf: Ellipsoid 0,20 × 0,25 × 0,22 (B × H × T), Mittelpunkt 0,16 über Schulterlinie.
Haar ist ein eigenes Teilmesh am Kopf (Materialgruppe `hair`) und folgt dem Kopfgelenk; schwingende Teile
(Pferdeschwanz, Zopf) bekommen ein eigenes Gelenk am Hinterkopf (optional ±12° Pendeln im Takt).

- **char-01 Kurzhaar:** Haarkappe = obere Kopfhälfte um 0,012 aufgedickt, Stirnkante leicht wellig (3 flache Wülste),
  Nacken kurz. Sonnenbrille: Band 0,16 × 0,035, um den Kopf gebogen, 0,005 vor dem Gesicht. Silhouette: klassisch, schlank-athletisch.
- **char-02 Buzzcut:** Haar nur als Farbschicht (Kopf-Ellipsoid +0,003, Haaransatz bis Ohrhöhe), keine Volumenform.
  Breite Schultern, Tanktop zeigt Schultern und Arme (Haut). Sportuhr links: Zylinder r 0,022, h 0,012, dunkel + Akzent.
- **char-03 Pferdeschwanz:** Haarkappe wie char-01, eng anliegend; Haargummi am Hinterkopf oben (Torus r 0,02);
  Schwanz = Kapsel/Tropfen 0,06 dick, 0,24 lang, nach hinten unten, eigenes Pendelgelenk. Muss aus 60 m als Zipfel sichtbar sein.
- **char-04 Dutt:** Haarkappe eng; Dutt = Kugel r 0,055 auf dem Oberkopf hinten (45° nach hinten versetzt). Gibt eine
  markante runde Silhouette – auch von vorn sichtbar.
- **char-05 Zopf:** Haarkappe mit Mittelscheitel (flache Rille); Zopf aus 4–5 abnehmenden Ellipsoiden (0,045 → 0,03),
  zusammen 0,35 lang, vom Nacken über den Rücken; eigenes Gelenk, schwingt weniger als Pferdeschwanz (±6°).
- **char-06 Locken + Stirnband:** Haarvolumen aus 7–9 überlappenden Kugeln r 0,045–0,06 über Kopf und Hinterkopf,
  Gesamthöhe +0,06 über Kopfdach. Stirnband: Torus/Band 0,03 hoch um die Stirn, Farbe Weiss #F2F2EE (Accessoire-Material).
- **char-07 Afro:** eine grosse, leicht abgeflachte Kugel r 0,16 (B 0,32, H 0,28), Mittelpunkt 0,05 über und 0,02 hinter
  der Kopfmitte; Oberfläche mit sehr leichter Wellen-Normalmap oder Roughness 0,9. Wichtig: Haar und Haut sind hier
  beide dunkel (Kontrast 1,4) – die Form trägt die Lesbarkeit, Haar bekommt einen leichten kühlen Glanzunterschied.
- **char-08 Lang offen:** Haarkappe + Haarvorhang hinten: gebogene, abgerundete Platte 0,26 breit, 0,30 lang, 0,03 dick,
  bis über die Schultern, vorn zwei schmale Strähnen neben dem Gesicht. Folgt dem Kopf, kein Pendeln (Durchdringung vermeiden).
- **char-09 Glatze:** keine Haar-Geometrie (Materialgruppe `hair` leer); Kopf etwas runder (0,21 × 0,25 × 0,22).
  Sonnenbrille mit hellem Rahmen #C9CCD1, damit sie auf sehr dunkler Haut sichtbar bleibt. Gross und breit.
- **char-10 Cap:** Kappe = Halbkugel über Kopf (+0,01) mit Schirm 0,09 vorstehend (flach abgerundet, 0,008 dick),
  Kappe in Anthrazit; graue Haare nur als schmaler Streifen an Schläfen und Nacken unter der Kappe.
  Achtung: Schirm zeigt zur Kamera (Gesicht zum Heck).

Accessoires: `sunglasses` (Material accessory, s. o.), `watch` (linkes Handgelenk), `headband` (Stirn), `cap`
(ersetzt Haarform, Haarfarbe für Schläfen). Bei Überschreibung der Haarfarbe im Profil gilt sie für alle Haarteile.

---

## 3. Bootsstile

Ziel: 8 klar unterscheidbare Stile, die reale Bauweisen zitieren (Rumpffarbe, Ausleger, Blattform), ohne Logos,
Schriftzüge oder Herstellernamen in der Anzeige. `inspiredBy` in der JSON beschreibt die Bauart generisch;
die Hersteller-Zuordnung steht nur hier.

| id | Anzeige (de / en) | Inspiriert von (nur intern) | Rumpf / Deck / Streifen | Ausleger | Blatt | Finish |
|---|---|---|---|---|---|---|
| boat-classic-yellow | Klassisch Gelb / Classic Yellow | Empacher (hellgelb mit schwarzen Kanten) | #EFCB5A / #EFCB5A / #1E1E1E | wing | bigblade, weiss | gloss |
| boat-carbon-black | Carbon Schwarz / Carbon Black | Klarlack-Carbon (Swift „clear carbon“ mit weissen Fugenlinien; Hudson, Fluidesign) | #1B1C1F / #1B1C1F / #E8E8E4 | backwing | fat2, hellgrau | carbon |
| boat-white-blue-stripe | Weiss mit blauem Streifen / White with Blue Stripe | Filippi (Standard „white color with blue stripe“) | #F4F4F1 / #F4F4F1 / #1F4E9C | wing (silber) | bigblade, blau | gloss |
| boat-white-black-tips | Weiss mit schwarzen Spitzen / White with Black Tips | Swift Racing (Standard: weisser Rumpf, Canvas-Decks, schwarze Spitzen) | #F4F4F1 / #E4DECF / #1E1E1E | backwing | fat2, zinnober | gloss |
| boat-wood-classic | Holz klassisch / Classic Wood | historische Zedernholz-Boote (Stämpfli Zürich, gegr. 1896; frühe Empacher) | #B9773A / #D9A766 / #6B3E1E | traditional (silber) | macon, weiss; Holzschaft | gloss |
| boat-signal-red | Signalrot / Signal Red | frei gestaltet (Clubfarben) | #C62828 / #F4F4F1 / #F4F4F1 | wing | bigblade, weiss | gloss |
| boat-matte-grey | Silbergrau matt / Matte Silver | frei gestaltet (robuste Trainings-/Clubeiner) | #A9AEB4 / #8A9097 / #1E1E1E | traditional | fat2, gelb | matte |
| boat-midnight-gold | Nachtblau mit Gold / Midnight Blue and Gold | frei gestaltet (traditionelle Club-Lackierung) | #1C2C4C / #1C2C4C / #D4A72C | wing (silber) | macon, gold | gloss |

**Begründung der Auswahl:** Die drei bekanntesten Lackierungen im Regattabild (Gelb, Weiss/Blau, Weiss mit schwarzen
Spitzen) plus Sichtcarbon decken die realen Flotten ab; Holz zitiert die Tradition (Dreiecksausleger + Macon) und
gibt dem Stil „klassisch“ einen eigenen Ausleger und ein eigenes Blatt; Rot, Grau und Nachtblau/Gold sind frei
gestaltet und füllen Farbräume, die aus Distanz unterscheidbar sind. Jede Ausleger-Art (wing, backwing, traditional)
und jede Blattform (macon, bigblade, fat2) kommt mindestens zweimal vor.

**Bauteile für den 3D-Agenten** (Einer, Masse in Metern):
- Rumpf: Länge 8,2, grösste Breite ~0,29 auf Wasserlinie, Spindelform; Deck vorn/hinten geschlossen (Deckfarbe),
  Cockpit offen 1,9 lang. `stripeColor`: Zierstreifen 0,02 hoch, 0,03 unter der Deckkante über die ganze Länge;
  bei `boat-white-black-tips` stattdessen Bug- und Heckspitze je 0,6 in `stripeColor`; bei `boat-classic-yellow`
  als schwarze Deckkante (Süllrand + Kante). `bowBall`: weisser Bugball r 0,02 (Regelpflicht).
- Flagge auf dem Boot (wenn an): beidseitig am Bug, 0,8 hinter der Spitze, 0,12 × 0,08, auf Deckhöhe.
- `wing` (Flügelausleger vorn): ein flaches, gebogenes Profil vom Bordrand vor dem Sitz zur Dolle (Spannweite
  2 × 0,80 = 1,60, wie `D.pinX`), Profil 0,06 × 0,02, leicht nach oben gewölbt.
- `backwing` (Rückflügel): gleiches Profil, aber hinter dem Ruderer (in Fahrtrichtung zum Bug versetzt zum Heck hin),
  Dolle auf kurzer Stütze. Unterscheidet sich aus Distanz durch die Lage hinter dem Rücken.
- `traditional`: je Seite drei Rundrohre r 0,012 (zwei vom Bordrand, eine Diagonale) zur Dolle – wie heute, aber rund.
- Blätter (gegenüber heute 0,46 × 0,19 Kasten): leicht gewölbte Schalen, 0,012 dick, Ecken gerundet.
  `macon`: symmetrisch, Länge 0,50 × Breite 0,16, Spitze oval. `bigblade`: asymmetrische Hackbeil-Form, 0,46 × 0,21,
  obere Kante länger. `fat2`: kürzer und breiter, 0,42 × 0,25, fast rechteckig mit gerundeter Spitze und kleiner Kante.
  Schaft r 0,018 in `shaftColor`, Griff 0,14 dunkel.

---

## 4. Farbpaletten und Prüfung

### Hauttöne – Monk Skin Tone Scale
Die zehn Töne sind exakt die Musterfarben der **Monk Skin Tone Scale** (MST-1 bis MST-10) von Ellis Monk,
mit Google entwickelt, lizenziert unter **CC BY 4.0** (Namensnennung: „Monk Skin Tone Scale by Dr. Ellis Monk, CC BY 4.0“
– gehört in die App-Lizenzseite/NOTICE). Gegenüber der Fitzpatrick-Skala (6 Stufen, für das Hautkrebsrisiko heller
Haut entwickelt) verteilt sie mehr Stufen auf dunkle Töne und ist für Darstellung/Bildverarbeitung gedacht.
Die Anzeige-Namen (Porzellan … Ebenholz) sind unsere; in der Auswahl reichen die Farbtupfer.

Hinweis für das Rendering: MST 1–4 liegen sehr nah beieinander (L* 88–94). Unter Tageslicht mit ACES/Filmic
werden sie kaum unterscheidbar; im Profil daher als Tupfer nebeneinander zeigen (dort sichtbar), im 3D genügt es.

### Haarfarben (10)
Schwarz, Dunkelbraun, Braun, Hellbraun, Dunkelblond, Blond, Kastanienrot, Kupfer, Grau, Silberweiss – Werte in der JSON.

### Trikotfarben (10) – Okabe-Ito plus Marine, Weiss, Anthrazit
Grundlage ist die für Farbsehschwäche entwickelte Palette von **Okabe & Ito** (Color Universal Design, 2002/2008):
Orange #E69F00, Himmelblau #56B4E9, Blaugrün #009E73, Gelb #F0E442, Blau #0072B2, Zinnober #D55E00,
Rosaviolett #CC79A7; dazu Marineblau #1A2F66, Weiss #F2F2EE, Anthrazit #26272B. Eine erste Fassung hatte
zusätzlich Weinrot #7A1F3D – bei Protanopie nur ΔE 5 von Anthrazit entfernt, deshalb gestrichen.

**Prüfung** (Skript im Scratchpad dieser Sitzung, Methode reproduzierbar): Simulation nach Machado, Oliveira &
Fernandes (2009), Schweregrad 1,0, in linearem sRGB; Abstand CIEDE2000 zwischen allen Paaren.

| Sehweise | kleinster Abstand ΔE2000 | engstes Paar |
|---|---|---|
| normal | 18,3 | Marine / Anthrazit |
| Protanopie | 12,2 | Blau / Rosaviolett |
| Deuteranopie | 11,6 | Orange / Gelb |
| Tritanopie | 10,9 | Orange / Rosaviolett |

Alle Paare liegen auch bei vollständiger Farbsehschwäche über ΔE 10 (deutlich unterscheidbar nebeneinander).
Bei Rennen mit mehr als zehn Booten wiederholen sich Farben zwangsläufig – dann helfen Blatt- und Rumpffarbe.
Marine, Blau und Anthrazit sind gegen dunkles Wasser (#2E4A5A) kontrastarm (WCAG-Verhältnis 1,4–1,8), aber die Figur
sitzt über dem Rumpf vor Himmel/Ufer; für Verkehr/Bots daher bevorzugt die hellen Farben ziehen.

Standard-Kombinationen der Typen: Trikot gegen Haut mindestens Kontrast 1,9 (char-05), meist 2,8–12,9.
Haar gegen Haut ist bei dunklen Tönen naturgemäss gering (char-07 1,4, char-09 ohne Haar) – Frisur über Form lesbar.

### Rumpffarben
Kleinster Abstand ΔE2000 zwischen verschiedenen Rumpffarben: normal 14,1 (Carbon / Nachtblau), Deuteranopie 9,3
(Holz / Signalrot – unterscheiden sich zusätzlich durch Deck und Ausleger). Die zwei weissen Stile teilen bewusst
den Rumpf und unterscheiden sich über Streifen/Spitzen, Deck, Ausleger und Blattfarbe.
Kontrast gegen Wasser: helle Rümpfe (Weiss 8,5, Gelb 6,0 gegen dunkles Wasser), dunkle Rümpfe (Carbon 4,9, Nachtblau 4,0
gegen helles Wasser). Signalrot liegt in der Leuchtdichte nahe am Wasser (1,6–1,7), wirkt aber über die Buntheit
(Rot gegen Blau-Grün) – bei Rot-Grün-Schwäche schwächer; deshalb weisses Deck.

---

## 5. Markenrecht: Herstellernamen in der Auswahl?

**Kurzfassung:** Rechtlich wäre eine rein beschreibende Nennung („im Stil von …“) in vielen Fällen vertretbar,
aber nicht risikofrei; der Nutzen ist klein. **Empfehlung: generische Anzeige-Namen, keine Herstellernamen in der App,
keine Logos, keine Schriftzüge.** Die Zuordnung steht nur in dieser Datei (Dokumentation, nicht in der Oberfläche).

Begründung (keine Rechtsberatung):
- **Wo greift Markenrecht?** Herstellernamen wie Empacher, Filippi, Hudson, Swift, Vespoli, Wintech, Concept2 sind
  als Marken eingetragen bzw. benutzt. Eine App, die einen virtuellen Bootsstil „Empacher“ zur Auswahl anbietet,
  benutzt den Namen im geschäftlichen Verkehr für ein Produkt (Software/virtuelle Güter) – auch wenn sie kostenlos
  und Open Source ist, sobald sie z. B. im App Store vertrieben wird.
- **Hinweisende (nominative) Nutzung** ist erlaubt, wenn sie nötig ist, um das fremde Produkt zu bezeichnen, nur so
  viel wie nötig (Wortname, kein Logo) und ohne Eindruck von Sponsoring oder Lizenz:
  EU Art. 14 Abs. 1 lit. c Unionsmarkenverordnung (EU) 2017/1001 („anständige Gepflogenheiten“), Schweiz nach
  Lehre und Praxis zum MSchG analog (Hinweis zulässig, wenn nicht irreführend), USA „nominative fair use“
  (*New Kids on the Block v. News America Publishing*, 9th Cir. 1992).
- **Problem bei uns:** Wir bezeichnen nicht das echte Produkt (z. B. Ersatzteil „passend für Empacher“), sondern bilden
  ein *virtuelles* Boot nach, das wie eines des Herstellers aussieht und dessen Namen trägt. Das kommt einer
  Lizenzierung nahe – Rennspiele lizenzieren Marken deshalb regelmässig. In den USA ist der Schutz für Kunstwerke
  (Rogers-Test) seit *Jack Daniel’s Properties v. VIP Products* (U.S. Supreme Court, 2023) enger, wenn die Marke als
  Herkunftshinweis für das eigene Produkt dient. Verwechslungs- oder Sponsoring-Eindruck ist also plausibel.
- **Farben und Formen:** Eine Farbe allein (z. B. Gelb) ist frei, solange sie nicht als Farbmarke eingetragen und
  durchgesetzt ist; eine Recherche in DPMA/EUIPO/Swissreg zu „Empacher“-Gelb haben wir nicht gemacht (vor einer
  ausdrücklichen Anlehnung prüfen). Allgemeine Bauarten (Flügelausleger, Big-Blade-Form) sind technische Formen und frei;
  die Blatt-Bezeichnungen „Big Blade“, „Fat2“, „Comp“, „Smoothie“ sind Concept2-Produktnamen → in der App nur
  generisch („klassisch schmal“, „Hackbeil“, „breit“), „Macon“ ist ein Gattungsbegriff.
- **Logos, Schriftzüge, typische Dekore** (Hersteller-Schriftzug am Bug, Firmensignets) nie – das wäre klare
  Markenbenutzung. Das gilt auch für Flaggen-Ersatz-Grafiken.
- **Repo öffentlich (Apache-2.0):** Apache-2.0 Abschnitt 6 gewährt ohnehin keine Markenrechte; Herstellernamen in
  Doku-Texten (wie hier, beschreibend) sind unproblematisch.

**Frage an Falk:** *Sollen in der Boot-Auswahl der App Herstellernamen erscheinen (z. B. „Klassisch Gelb – im Stil
von Empacher“), oder bleibt es bei rein generischen Namen und die Herstellerbezüge stehen nur in docs/avatar/DESIGN.md?*
Empfehlung: generisch (Standard umgesetzt). Wer Namen will, sollte sie bei den Herstellern schriftlich anfragen
(ein kurzes „darf ein kostenloses Ruder-Trainingsprogramm einen Bootsstil ‚im Stil von X‘ nennen?“) – eine Zusage
wäre auch eine schöne Kooperation.

---

## 6. Quellen

- Monk Skin Tone Scale (Hexwerte, Lizenz CC BY 4.0, Vergleich Fitzpatrick): https://en.wikipedia.org/wiki/Monk_Skin_Tone_Scale ;
  Google Skin Tone Research: https://skintone.google/ (Fundus fact:2438)
- Okabe, M. & Ito, K.: Color Universal Design (CUD) – How to make figures and presentations that are friendly to
  colorblind people (2002/2008), https://jfly.uni-koeln.de/color/
- Machado, G. M., Oliveira, M. M. & Fernandes, L. A. F. (2009): A Physiologically-based Model for Simulation of
  Color Vision Deficiency. IEEE TVCG 15(6), 1291–1298, doi:10.1109/TVCG.2009.113
- Sharma, G., Wu, W. & Dalal, E. N. (2005): The CIEDE2000 color-difference formula. Color Research & Application 30(1), 21–30.
- Concept2 Blattformen und Geschichte (Macon 1976, Big Blade 1991, Smoothie2, Fat2 2006, Comp 2020):
  https://concept2.co.uk/oars/sweeps/blades , https://www.concept2.com/blog/meet-the-comp-blade (Fundus practice:988)
- Filippi Standardfarbe „white color with blue stripe“, Carbon-Flügelausleger: https://filippiboats.it/eng/boats/coastal/single/f84
  (Fundus practice:989)
- Swift Racing Standardfarben (weisser Rumpf, Canvas-Decks, schwarze Spitzen; Clear Carbon mit weissen Fugenlinien):
  https://swiftracing.com/racing-shells-colours/ (Fundus practice:990)
- Empacher hellgelb mit schwarzer Kante; Finish „yellow“; Reparaturlack „Empacher Yellow“ UR1044:
  https://en.wikipedia.org/wiki/Empacher , https://www.empacher.com/en/products/racing-boats/empacher-racing-single ,
  https://www.r-g.de/en/art/E149100 (Fundus practice:991)
- Stämpfli Racing Boats (gegründet 1896 in Zürich-Wollishofen, heute Holzboot-Restaurierung; Composite-Einer bei
  Janousek & Stampfli): https://en.wikipedia.org/wiki/St%C3%A4mpfli_Racing_Boats
- Vespoli (weisse Gelcoat-/Flat-White-Rümpfe bei einzelnen Modellen): https://vespoli.com/boats/echo-sport/
- Markenrecht: Verordnung (EU) 2017/1001 Art. 14; *New Kids on the Block v. News America Publishing*, 971 F.2d 302
  (9th Cir. 1992); *Jack Daniel’s Properties, Inc. v. VIP Products LLC*, 599 U.S. 140 (2023); Apache License 2.0 §6.
- Nicht gefunden / offen: offizielle Farbcodes von Hudson, Wintech, Fluidesign, BBG, Liangjin, Kaschper (keine
  Standardfarben veröffentlicht) – diese Hersteller deshalb nicht als Vorbild einer bestimmten Lackierung genannt.
  Zotero (`zrag`) war in dieser Sitzung nicht verfügbar (Befehl fehlt); Fundus hatte nichts zu Bootsbauern/Hauttönen.


## Entscheidung Bootsnamen (Falk, 26.11.2026)
Die App zeigt bei den fünf Stilen mit realem Vorbild „<Name> – im Stil von <Hersteller>“ (Empacher, Hudson, Filippi, Swift Racing, Stämpfli); keine Logos oder Schriftzüge. Die übrigen drei bleiben frei gestaltet.
