# Figur, Boot und Profil (Spezifikation, Stand 26.11.2026)

Wunsch (Falk, 26.11.):
- Im Profil Angaben zu sich erfassen: Nationalität. (Ein Geschlechtsfeld gab es kurz; gestrichen – Entscheidung Falk
  26.11.: man wählt eine Figur, kein Geschlecht. Alte gespeicherte Werte werden beim Lesen übergangen.)
- Eine Figur im Boot auswählen: etwa 10 Grundtypen (Hautfarbe, Haare, …), schöner gerendert als heute (heute: Kästen
  und Kugeln, „grob, schnitzig“). Kein Fotorealismus, aber ein stimmiger, freundlicher, stilisierter Look.
- Ein Boot auswählen: verschiedene Bootsbauer bzw. Bootsstile.
- Schalter: Flagge der eigenen Nation auf dem Trikot ja/nein, Flagge auf dem Boot ja/nein (aus = nichts zu sehen).
- Später in Turnieren sehen andere genau diese Figur mit Flagge und Boot, beim Vorbeifahren und Überholen.

Heute: `App/RowCoach/Scene3D/BoatRig.swift` baut Skiff, Skulls und Figur prozedural (Kästen/Kugeln) und animiert
die Figur über `StrokePose` (Hüfte, Oberkörper, Kopf, Oberschenkel, Unterschenkel, Arme, Skulls). Benutzt von
`RowingSceneController` (eigenes Boot), `PaceLineEntity` (Geisterboot, einheitlich halbtransparent),
`RaceRowers` (Rennen), `TrafficSystem` (andere Ruderer). Schatten, Geister-Tönung und Farben müssen weiter gehen.

## Bausteine und Zuständigkeit (drei Agenten parallel, Dateien getrennt)
1. **Gestaltung** (docs/avatar/DESIGN.md, `App/RowCoach/Resources/appearance.json`): Bildsprache, 10 Figurtypen,
   6–8 Bootsstile mit allen Parametern im Format unten; Recherche Bootsbauer (Form, Ausleger, Farben) und
   Markenrecht (Namen/Logos), Hautton-Palette, Haarfarben, Trikotfarben.
2. **Profil und Kit** (RowCoachKit + Einstellungen): Modelle, Speichern, Profilseite mit Auswahl, Flaggen-Schalter,
   Weitergabe an Rennen/Turniere.
3. **3D** (tools/avatars + App/RowCoach/Scene3D): Figur und Boot neu modellieren (Generator in Python → USDZ, später
   auch GLB für Android), Rig in der App, Flaggen als Textur, Vorschaubilder.

## Kit-Modelle (RowCoachKit, nur Foundation)
```swift
public struct RowerProfile: Codable, Equatable, Sendable {
    public var displayName: String          // Anzeigename (Turniere), Standard leer → „Ich“
    public var nationality: String?         // ISO 3166-1 alpha-2, z. B. "CH"; nil = keine Angabe
    public var appearance: RowerAppearance
}
public struct RowerAppearance: Codable, Equatable, Hashable, Sendable {
    public var characterId: String          // aus appearance.json
    public var skinToneId: String?          // Überschreibung, sonst die des Typs
    public var hairColorId: String?
    public var shirtColorId: String?
    // Form-Überschreibungen (26.11.2026; nil = wie die Vorlage): alles einzeln wählbar, Typen sind Startvorlagen
    public var hairStyle: String?           // short|buzz|ponytail|bun|braid|curly|afro|long|bald
    public var build: String?               // slim|athletic|broad (Anzeige „kräftig“); Schulterbreite folgt der Statur
    public var heightScale: Double?         // 0,95 klein · 1,0 mittelgross · 1,05 gross (Kit begrenzt 0,85–1,15)
    public var shirtStyle: String?          // unisuit|tank|tee|longsleeve
    public var legStyle: String?            // short|long
    public var beard: String?               // none|short|full
    public var accessories: [String]?       // sunglasses, watch + höchstens eine Kopfbedeckung cap|headband|hijab|patka
    public var boatStyleId: String
    public var flagOnShirt: Bool            // Standard false
    public var flagOnBoat: Bool             // Standard false
    public var nationality: String?         // wird aus dem Profil gesetzt, für andere sichtbar nur, wenn ein Flaggen-Schalter an ist
}
```
- `RaceParticipant` bekommt `appearance: RowerAppearance?` (beim Beitritt einmal gesendet, nicht in jedem LiveFrame).
  Datenschutz: Nationalität geht nur mit, wenn mindestens ein Flaggen-Schalter an ist; Personendaten (Name ausser
  Anzeigename) stecken nie in der Erscheinung.
- Speicherung: UserDefaults (JSON unter `profile.rower`), bestehende `profile.*`-Schlüssel bleiben.
- Bots und Verkehr: zufällige, aber pro Teilnehmer stabile Erscheinung (`RowerAppearance.random(seed:)`).

## Katalog `App/RowCoach/Resources/appearance.json`
```json
{"version": 1,
 "skinTones": [{"id": "skin-1", "rgb": "#F3D5C0", "name": {"de": "…", "en": "…"}}],
 "hairColors": [{"id": "hair-black", "rgb": "#1E1A18", "name": {…}}],
 "shirtColors": [{"id": "shirt-navy", "rgb": "#1A2F66", "name": {…}}],
 "characters": [{"id": "char-01", "name": {"de": "…", "en": "…"},
                 "build": "slim|athletic|broad", "heightScale": 1.0, "shoulderScale": 1.0,
                 "skinToneId": "skin-3", "hairStyle": "short|buzz|ponytail|bun|braid|curly|afro|long|bald|cap|headband",
                 "hairColorId": "hair-black", "shirtColorId": "shirt-navy", "shirtStyle": "tank|tee|unisuit",
                 "accessories": ["sunglasses", "cap", "headband", "watch"], "description": {"de": "…", "en": "…"}}],
 "boatStyles": [{"id": "boat-classic-yellow", "name": {"de": "…", "en": "…"}, "inspiredBy": "…",
                 "hullColor": "#…", "deckColor": "#…", "stripeColor": "#…", "riggerType": "wing|traditional|backwing",
                 "riggerColor": "#…", "bladeShape": "macon|bigblade|fat2", "bladeColor": "#…", "shaftColor": "#…",
                 "finish": "gloss|matte|carbon", "bowBall": true, "description": {…}}]}
```
- Typen (seit 26.11.2026: Vorlagen, 12 Stück, alles frei kombinierbar) beschreiben Erscheinung, nicht Geschlecht oder
  Herkunft (Namen neutral, z. B. „Zopf mit Stirnband“). Hautton-Namen neutral nummeriert („Hautton 1…10“, VoiceOver-
  Zusatz in `accessibility`). Standardvorlage char-01 mit mittlerem Hautton (keine helle Vorauswahl).
- Neue Felder: `characters[].legStyle` (short|long), `characters[].beard` (none|short|full), Accessoires
  `hijab`/`patka`, `shirtStyle` `longsleeve`, `boatStyles[].tipColor` (Bug-/Heckspitzen je 0,6 m).
- Bootsstile: keine Logos und keine geschützten Schriftzüge; Herstellernamen nur, wenn markenrechtlich unbedenklich
  (die Gestaltung prüft und begründet; sonst „inspiriert von“ nur in DESIGN.md, Anzeige generisch).

## 3D-Anforderungen
- Stilisiert, weich (abgerundete Formen statt Kästen), ca. 2–4 k Dreiecke je Figur, 1–3 k je Boot (iPad A12X muss
  mehrere Boote im Bild halten; Verkehr hat bis zu ~8 Ruderer). Segmente für die Animation wie heute (Hüfte,
  Oberkörper, Kopf mit Haaren, Ober-/Unterarm oder Arm, Hände, Ober-/Unterschenkel, Füsse) mit Gelenkpunkten.
- Material-Gruppen je Segment (skin, hair, shirt, shorts, shoes, accessory), Farben zur Laufzeit gesetzt.
- Flagge: Trikot (Brust und/oder Rücken – die Kamera sieht den Rücken! Figur schaut zum Heck = zur Kamera? siehe
  BoatRig-Kommentar: Gesicht zum Heck, also zur Kamera → Brust sichtbar) und Boot (Bugdeck oder Seiten nahe Bug).
  Textur aus dem Flaggen-Emoji (iOS zeichnet 🇨🇭 als Bild), keine Flaggendateien nötig.
- Geisterboot, Schatten, `StrokePose` bleiben kompatibel; Performance nicht schlechter als heute.

## Umsetzung Profil (Baustein 2, Stand 26.11.2026)
**Kit** (`App/RowCoachKit/Sources/RowCoachKit/Avatar/`, nur Foundation, Tests `AvatarTests.swift`, Linux):
- `RowerProfile.swift`: `RowerProfile` und `RowerAppearance` wie oben, tolerant dekodiert (fehlende Felder →
  Standard, unbekannte Felder wie ein altes `gender` werden übergangen, ungültiger Ländercode → nil). `publicAppearance`
  setzt die Datenschutzregel um (Nationalität nur mit Flaggen-Schalter, ohne Nationalität beide Schalter aus, Name
  nie in der Erscheinung). Form-Überschreibungen tolerant (falscher Typ = nicht gesetzt), `resetToTemplate(_:)`,
  `hasShapeOverrides`. `shirtFlag`/`boatFlag` liefern das Flaggen-Emoji nur bei eingeschaltetem Schalter.
  `RowerAppearance.random(seed:catalog:)`: Figur, Trikotfarbe und Boot aus dem Katalog, keine Flaggen; stabil je
  Seed über FNV-1a + SplitMix64 (nicht `Hasher`), also gleich auf allen Geräten, solange der Katalog gleich bleibt.
  Anzeigename höchstens 24 Zeichen (`maxDisplayNameLength`), leer → „Ich“.
- `AppearanceCatalog.swift`: lädt appearance.json (`load(from:)`; fehlende Listen aus dem eingebauten Ersatz
  `builtin`), `resolve(_:)` → `Resolved` (Figurtyp, Haut/Haar/Trikot als `RGBColor`, Bootsstil mit RGB-Accessoren,
  Flaggen) mit Ersatzkette Überschreibung → Farbe des Typs → erste Farbe → Grau, unbekannte Figur/Boot → erster
  Eintrag; `Resolved` enthält auch die wirksame Form (`hairStyle`, `build`, `heightScale`, `shoulderScale`,
  `shirtStyle`, `legStyle`, `beard`, `accessories`: Überschreibung → Vorlage); `normalized(_:)`; `validate()`
  (Version, doppelte Ids, Hex-Farben, Verweise, 8–16 Vorlagen, 6–8 Boote).
  `AppearanceCatalog.current` setzt die App beim Start (Bots, `resolvedAppearance()`).
- `CountryList.swift`: 249 ISO-3166-1-Codes, Flagge über `Course.flag(_:)`, Namen über `Locale` (ohne
  Systemnamen der Code), Sortierung ohne Akzente, Suche nach Namen (auch englisch) oder Code.
- `RaceParticipant.appearance` (optional, abwärtskompatibel) und `resolvedAppearance()`.

**App:**
- `Storage/RowerProfileStore.swift` (`@MainActor @Observable`, `RowerProfileStore.shared`): Profil als JSON unter
  `profile.rower`; lädt appearance.json und setzt `AppearanceCatalog.current`.
  **Schnittstelle für die 3D-Seite:** `RowerProfileStore.shared.appearance` (= `publicAppearance`, gilt auch fürs
  eigene Boot), `.resolved` (aufgelöste Farben und Boot), `.catalog`; bei Änderung der Erscheinung steigt
  `appearanceRevision` und es kommt `RowerProfileStore.didChangeAppearance` (NotificationCenter). Fremde Boote:
  `participant.resolvedAppearance()` und `catalog.resolve(_:)`.
- `Views/ProfileView.swift`: Einstellungen → Profil → „Profil & Figur“: Anzeigename, Nationalität (durchsuchbare
  Länderliste mit Flagge, „Keine Angabe“), Raster der Vorlagen (eine neue Vorlage setzt alle Anpassungen zurück),
  „Anpassen“: Farbpunkte für Hautton/Haarfarbe/Trikotfarbe, Frisur, Bart, Kopfbedeckung, Sportbrille, Sportuhr,
  Körperbau, Grösse, Oberteil, Beine (der Wert der Vorlage = keine Überschreibung), „Auf die Vorlage zurücksetzen“, Bootsliste, Flaggen-Schalter (ohne Nationalität deaktiviert), Hinweis „Was
  andere sehen“. Vorschaubilder `Resources/AvatarPreviews/<characterId>.png` bzw. `<boatStyleId>.png` (im Bundle
  mit oder ohne Unterordner gesucht), bis dahin Platzhalter aus den Katalogfarben.
- Demo-Rennen (`-demoRace 1`, `RowingView.demoRace`): eigener Teilnehmer mit Anzeigename und `publicAppearance`,
  Bots mit `RowerAppearance.random(seed: <participantId>)`.
- Hauttöne (Monk Skin Tone Scale, CC BY 4.0): Namensnennung in NOTICE und unter Einstellungen → Quellen.

## Umsetzung 3D (Baustein 3, Stand 26.11.2026)

### Generator `tools/avatars/` (Python, venv der coursebuilder, keine GPU, kein Blender)
```bash
cd tools/avatars
../coursebuilder/.venv/bin/python build.py --glb   # USDZ in die App (+ GLB nach dist/avatars/ für Android)
./run_preview.sh                                    # Vorschaubilder + Übersichtstafeln (CPU, llvmpipe, ~10 s)
./run_preview.sh --only char-03,boat-wood-classic   # einzelne Bilder (ohne Tafeln)
```
| Datei | Inhalt |
|---|---|
| `geom.py` | Mesh-Bausteine: Loft, Ellipsoid, Kapsel, Rohr, Verdicken, Aufteilen nach Materialgruppe, glatte Normalen |
| `figure.py` | Figur: Segmente, Trikotformen, 11 Frisuren, Accessoires, Brustflagge; Masse (`HIP_Y`, `UPPER_ARM`, …) |
| `boat.py` | Skiff 8,2 m (Spanten-Loft, Breite 0,30 an der Wasserlinie), Deck mit Cockpit, Streifen, Finne, Bugball, Flaggen, Sitz, Schienen, Stemmbrett, Ausleger wing/backwing/traditional, Skulls mit Blattform macon/bigblade/fat2 |
| `lite.py` | Detailstufe lite (Palettentextur) |
| `rig.py` | Gelenkrechnung wie in der App (Vorschau, Referenz) |
| `preview.py`, `run_preview.sh` | Vorschaubilder (pyrender offscreen) |
| `build.py` | Export USDZ/GLB und `avatar_parts.json` |

Ergebnis in `App/RowCoach/Resources/Avatars/`: `rower_parts.usdz` (39 Teile, 169 KB), `boat_parts.usdz` (30 Teile,
69 KB), `lite_parts.usdz` (4 Teile, 15 KB), `avatar_parts.json` (Prim → Rahmen, Gruppe, Dreiecke).
Vorschauen: `App/RowCoach/Resources/AvatarPreviews/<id>.png` (512 px, transparent; Figur in der Auslage vom Heck,
Boot schräg von vorne), Übersicht für Falk: `docs/avatar/overview-figures.png`, `docs/avatar/overview-boats.png`.

**USDZ-Aufbau:** `/Parts` mit je einem Mesh-Prim pro Teil, Name `<teil>__<gruppe>` (z. B. `forearm__skin`,
`hair_ponytail__hair`, `rigger_backwing__rigger`, `blade_fat2_L__blade`). Punkte im lokalen Rahmen des Segments
(Ursprung = Gelenk), glatte Vertex-Normalen, keine Unterteilung, einseitig (gegen den Uhrzeigersinn = aussen), Flaggen
und lite mit `st`. Jedes Mesh hat ein Vorschau-Material seiner Gruppe; die App setzt eigene Materialien.
Materialgruppen Figur: skin, hair, shirt, shorts, socks, shoes, eyes (Iris), eyes_hl (Sklera + Glanzpunkt),
headwear (Kopftuch, Patka), accessory, flag. Boot: hull, deck, stripe, fin,
bowball, fittings (Sitz, Schienen, Stemmbrett, Dollen, Griffe, Cockpitboden), rigger, shaft, sleeve, blade, flag.

### Segmente und Gelenke (crew-System: Figur schaut nach −z = zum Heck = zur Kamera)
| Segment | Ursprung (Gelenk) | Achse | Teile (Prims) |
|---|---|---|---|
| pelvis | Hüfte (0, 0,26, hipZ), hipZ = 0,05 + 0,45 · slide | Neigung −lean um x; Skalierung (Statur·Schulter, Höhe, Tiefe) | `hips__shorts`, `torso_{tee,tank,unisuit}__{shirt,skin}`, `flag_chest__flag` |
| head | pelvis + (0, 0,50 · Höhe, 0) | 40 % der Neigung (Kopf bleibt aufrechter), Skalierung √Höhe | `head__skin`, `eyes__eyes`, `eyes_white__eyes_hl`, `hair_<stil>__hair`, `beard_{short,full}__hair`, `acc_{sunglasses,cap,headband}__accessory`, `acc_{hijab,patka}__headwear` |
| upperarm R/L | Schulter pelvis + (±0,17 · Schulter, 0,46 · Höhe, 0) | +y zum Ellbogen, Länge 0,31 | `upperarm_bare__skin` bzw. `upperarm_tee__{shirt,skin}` |
| forearm R/L | Ellbogen (Zwei-Gelenk-IK, Ellbogen nach aussen/hinten/unten) | +y zur Griffmitte, Länge 0,37 inkl. Faust | `forearm__skin` bzw. Langarm `forearm_long__{shirt,skin}`, `acc_watch__accessory` (links) |
| thigh R/L | (±0,10, 0,26, hipZ) | +y zum Knie, 0,48 (IK, Knie nach oben) | `thigh__shorts`, `thigh__skin` |
| shin R/L | Knie | +y zum Knöchel, 0,48 | `shin__skin`, `shin__socks` |
| foot R/L | Knöchel (±0,12, 0,14, −0,45) | fest (Schuh liegt auf dem Stemmbrett, 0,6 rad) | `foot__shoes` |
| seat | (0, 0,16, hipZ) | – | `seat__fittings` |
| oar R/L | Dolle (±0,80, 0,36, −0,05), Schwenk + Neigung wie früher | +x nach aussen, Griff bei −0,88; Abdrehen um x mit Vorzeichen der Seite | `oar_shaft__shaft`, `oar_grip__fittings`, `oar_sleeve__sleeve`, `blade_<form>_<R/L>__blade` |
| crew (fest) | – | – | `tracks`, `stretcher`, `gates`, `rigger_<art>`, `flag_rigger_<art>__flag` |
| boat (fest, Bug −z) | – | – | `hull__hull`, `hull_stripe__stripe`, `deck__deck`, `cockpit__fittings`, `fin__fin`, `bowball__bowball`, `hull_tips__tips`, `deck_tips__tips`, `flag_side_{R,L}__flag`, `flag_deck__flag` |

Gliederdicke über Statur (slim 0,90, athletic 1,0, broad 1,12, nur quer zur Achse); Längen über `heightScale`
(Arme; ist der Griff zu weit, strecken sich die Arme bis 8 %). Statur `broad`: Torso 10 % tiefer.

**Budget (gemessen, Stand 26.11. spät):** Figur 3,6–4,3 k Dreiecke je Vorlage (Afro, Zopf, langes Haar oben), Boot 2,8–2,9 k je Stil,
lite 589 je Boot (Rumpf mit Auslegern 208, Figur 325, Skulls 2 × 28). Draw-Calls voll: Figur ≈ 18–21, Boot ≈ 17
(je Teil ein Material); lite: 4. Früher: Figur ≈ 10, Boot ≈ 14 (Kugeln/Boxen mit vielen Dreiecken). Auf dem A12X zu
messen (siehe „Auf dem Mac prüfen“).

### App (`App/RowCoach/Scene3D`)
- `AvatarAssets.swift`: lädt die drei USDZ einmal (`AvatarAssets.shared.load()`, in `RowingSceneController.build`),
  hält nur die `MeshResource`s je Prim-Name; `RigLook` (aufgelöste Erscheinung), `AvatarMaterials` (geteilte PBR-
  Materialien, Geistermaterial, Flaggen-Textur aus dem Emoji über `UIGraphicsImageRenderer` → `TextureResource`,
  Cache je Land; Palettentextur für lite), `PartSlot` (Platz für ein Teil, Mesh/Material austauschbar),
  `AvatarParts` (Mesh aus USDZ, sonst prozeduraler Ersatz wie früher).
- `RowerFigure.swift` (Figur, Gelenke), `BoatModel.swift` (Boot, Skulls, Flaggen am Boot), `BoatRig.swift` (setzt
  beides zusammen, `StrokePose` unverändert, `LiteBoat`, `BoatRigPool`).
- Flaggen (26.11. spät): Bug- und Heckdeck liegen ausserhalb des Kamerabilds der App (Kamera 4,5 m hinter und 2,2 m
  über dem Bezugspunkt, Blick fast waagrecht, unterer Bildrand ≈ 27° unter der Waagrechten – sichtbar ist das Boot
  erst ab dem Ausleger). Deshalb jetzt: flach auf dem Ausleger beidseitig (`flag_rigger_<art>`, 0,12 × 0,075, am
  unteren Bildrand neben der Figur – mit `views.py app` im Kamerabild geprüft), seitlich am Rumpf direkt hinter dem
  Ausleger (0,105 × 0,07, beim Überholen und schräg von hinten) und weiter auf dem Heckdeck (für Boote vor einem).
  Alt: Boot = beidseitig am Bug (0,8 hinter der
  Spitze, 0,12 × 0,08) und auf dem Heckdeck direkt hinter dem Cockpit (0,14 × 0,09, Oberkante zum Bug, für die Kamera
  hinter dem Boot und beim Überholen). Nur wenn `shirtFlag`/`boatFlag` gesetzt (Schalter an und Nationalität), nie
  beim Geist.
- Eigenes Boot: `RowerProfileStore.shared.appearance`, Neu-Einkleiden auf `didChangeAppearance` (gleiche Entities).
  Rennen: `RaceParticipant.resolvedAppearance()`; Verkehr: `RowerAppearance.random(seed: "traffic-<platz>")`;
  Tempo-Linie: Geisterboot mit Grundfigur (unverändert).
- Ohne USDZ (oder bis sie geladen sind): prozedurale Grundform wie früher; nach dem Laden tauschen alle Rigs ihre
  Meshes (`BoatRig.assetsDidLoad`).

### Schnittstelle für grosse Felder (RaceScenePlanner → RaceRowers)
```swift
let rig = BoatRig(appearance: a, catalog: .current, ghostTint: nil, detail: .full)  // oder aus dem Pool:
let pool = BoatRigPool(root: raceRoot); pool.prewarm(18)                          // vor dem Laden der Landschaft
let rig = pool.acquire(appearance: participant.resolvedAppearance(), detail: .full)
rig.setDetail(.lite)        // full ↔ lite ↔ hidden: nur isEnabled zweier vorgehaltener Zweige, kein Neuaufbau
rig.setAppearance(other)    // tauscht Meshes/Materialien derselben Entities
rig.setFade(0.4)            // OpacityComponent (1 = entfernt); A12X-Hinweis in BoatRig.setFade beachten
rig.apply(.at(phase: p, strokeRate: r))   // nur die aktive Stufe wird bewegt
pool.release(rig)           // versteckt und parkt das Rig 400 m unter Wasser
```
`RaceRowersSystem` nutzt bereits Pool und Erscheinung; für den Planer gibt es `setTier(_:for:)` (Schild nur bei
`.full`) und `setFade(_:for:)`. Abbildung `RaceSceneItem.tier`: `full` → `.full`, `lite` → `.lite`, `impostor`/
`hidden` → `.hidden` (Impostoren als eigenes instanziertes Mesh sind noch offen).

### Auf dem Mac prüfen
1. Bauen (Swift 6 / RealityKit); Szene öffnen: eigene Figur und Boot nach Profil, Wechsel im Profil wirkt sofort.
2. Entity-Namen nach dem USDZ-Laden: Log „Avatar: N Teile geladen“ muss 73 zeigen (39 + 30 + 4). Bei 0 heissen die
   Entities anders als die Prims – dann `AvatarAssets.collect` anpassen.
3. Flaggen: richtig herum und nicht gespiegelt (Brust, Bug beidseitig, Heckdeck)? Falls kopfstehend: in
   `figure.chest_flag`/`boat.flag_parts` v umkehren und `build.py` neu laufen lassen.
4. Unsichtbare Teile (falsche Dreiecksrichtung) – im Simulator von allen Seiten ansehen; notfalls in
   `AvatarMaterials.pbr` `faceCulling = .none` setzen.
5. Geisterboot (Tempo-Linie) einheitlich halbtransparent, keine Schatten; Verkehr ohne Schatten; Rennen mit Bots
   (`-demoRace 1`): Figuren/Boote je Bot verschieden.
6. Bildrate auf dem iPad A12X mit Verkehr (8 Ruderer) und Rennen; bei Bedarf Verkehr auf `.lite` schalten.

### Figuren-Überarbeitung (26.11.2026 spät, nach docs/avatar/REVIEW-DIVERSITY.md)
- Alles einzeln wählbar (Kit: Form-Überschreibungen in `RowerAppearance`, `Resolved` mit wirksamer Form; ProfileView
  „Anpassen“). Die Szene liest nur noch `Resolved` (`RigLook(_:)`), nicht mehr die Vorlage.
- Gesichter: Iris dunkel + helle Sklera mit Glanzpunkt (`eyes_white__eyes_hl`), auf jedem Hautton sichtbar.
- Haut: `AvatarMaterials.skin(look)` – helle Töne leicht wärmer (`RigLook.skinRender`), dunkle Töne mit mehr
  Glanz (specular/clearcoat) und kleinem farbtreuem Eigenleuchten (`AvatarMaterials.skinFill`, auf dem Gerät
  nachstellen). Haar mit Glanzkante (clearcoat). Vorschau rechnet gleich (`preview.skin_render`).
- Abnahme-Kontrollbogen: `docs/avatar/check-skintones.png` (10 Hauttöne × Mittag/Abend/Gegenlicht, schwarzes Kurzhaar
  als härtester Fall). Messung Gesichtsmitte L*: MST 10 ≈ 16 (Mittag/Gegenlicht), 18 (Abend); MST 1 ≈ 51–62.
  Vor jedem Release neu erzeugen und ansehen (`./run_preview.sh`).
- Neu: Sport-Kopftuch (Haube + Halsteil, Gesicht frei; Farbe = Trikot), Patka (Haube mit Knoten), Bart kurz/voll
  (Haarfarbe), Oberteil Langarm (`forearm_long`), lange Beine (Leggings = Shorts-Farbe auf Oberschenkel und Wade),
  Sport-Cap neu (flache Krone, Knopf, langer gebogener Schirm; Farbe = Trikot), Afro runder und tiefer.
  Unter Kopftuch und Patka kein Haar; unter der Cap kurze Haarkappe für kurze Frisuren, lange bleiben sichtbar.
- Boot: `tipColor` (Bug-/Heckspitzen je 0,6 m) – „Weiss mit schwarzen Spitzen“.
- Später (nicht umgesetzt): Para (Prothese, fester Sitz), Körperbau „füllig“, Masters-silber.


### Fehlerrunde nach dem Mac-Test (27.11.2026)
- Patka/Kopftuch: Die Ohren (bis x ≈ 0,111 m) stachen durch Haube bzw. Tuch und wirkten von hinten oben wie helle
  Strähnen bzw. ein Zipfel → Haube und Tuch seitlich breiter, Patka endet über den Ohren. Unter Kopftuch und Patka wird
  die Frisur weiter ausgeblendet. Bart und Haar glänzen weniger (Klarlack spiegelte den Himmel hell), Bart matt;
  Koteletten enden tiefer.
- Renn-Silhouetten (`RaceImpostors`): statt harter schwarzer Dreiecke ein liegendes, flaches Bild (Rumpfstrich, kleine
  runde Figur, zwei kurze geneigte Skull-Striche), Grau mit Blauton, in drei Entfernungsstufen zum Dunst hin heller und
  durchscheinender (< 250 m, < 500 m, darüber), `setHaze(_:)` für die Dunstfarbe der Szene. Kontrollbild
  `docs/avatar/check-impostors.png` (`tools/avatars/impostors_check.py`).
- Logs: „Silhouetten“ (Einzelboote der Stufe impostor) + „Pulk“ einheitlich in Szene und Rennen-Log.
