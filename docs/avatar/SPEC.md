# Figur, Boot und Profil (Spezifikation, Stand 26.11.2026)

Wunsch (Falk, 26.11.):
- Im Profil Angaben zu sich erfassen: Nationalität, Geschlecht (frei wählbar).
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
    public var gender: Gender?              // nil = keine Angabe
    public var appearance: RowerAppearance
    public enum Gender: String, Codable, CaseIterable, Sendable { case female, male, diverse }
}
public struct RowerAppearance: Codable, Equatable, Hashable, Sendable {
    public var characterId: String          // aus appearance.json
    public var skinToneId: String?          // Überschreibung, sonst die des Typs
    public var hairColorId: String?
    public var shirtColorId: String?
    public var boatStyleId: String
    public var flagOnShirt: Bool            // Standard false
    public var flagOnBoat: Bool             // Standard false
    public var nationality: String?         // wird aus dem Profil gesetzt, für andere sichtbar nur, wenn ein Flaggen-Schalter an ist
}
```
- `RaceParticipant` bekommt `appearance: RowerAppearance?` (beim Beitritt einmal gesendet, nicht in jedem LiveFrame).
  Datenschutz: Nationalität geht nur mit, wenn mindestens ein Flaggen-Schalter an ist; Geschlecht geht nie mit.
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
- Typen beschreiben Erscheinung, nicht Geschlecht oder Herkunft (Namen neutral, z. B. „Kurzhaar mit Stirnband“);
  Geschlecht und Nationalität wählt man im Profil unabhängig davon.
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
  Standard, unbekanntes Geschlecht → keine Angabe, ungültiger Ländercode → nil). `publicAppearance` setzt die
  Datenschutzregel um (Nationalität nur mit Flaggen-Schalter, ohne Nationalität beide Schalter aus, Geschlecht und
  Name nie in der Erscheinung). `shirtFlag`/`boatFlag` liefern das Flaggen-Emoji nur bei eingeschaltetem Schalter.
  `RowerAppearance.random(seed:catalog:)`: Figur, Trikotfarbe und Boot aus dem Katalog, keine Flaggen; stabil je
  Seed über FNV-1a + SplitMix64 (nicht `Hasher`), also gleich auf allen Geräten, solange der Katalog gleich bleibt.
  Anzeigename höchstens 24 Zeichen (`maxDisplayNameLength`), leer → „Ich“.
- `AppearanceCatalog.swift`: lädt appearance.json (`load(from:)`; fehlende Listen aus dem eingebauten Ersatz
  `builtin`), `resolve(_:)` → `Resolved` (Figurtyp, Haut/Haar/Trikot als `RGBColor`, Bootsstil mit RGB-Accessoren,
  Flaggen) mit Ersatzkette Überschreibung → Farbe des Typs → erste Farbe → Grau, unbekannte Figur/Boot → erster
  Eintrag; `normalized(_:)`; `validate()` (Version, doppelte Ids, Hex-Farben, Verweise, 10 Typen, 6–8 Boote).
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
  Länderliste mit Flagge, „Keine Angabe“), Geschlecht (Weiblich/Männlich/Divers/Keine Angabe), Raster der Figurtypen
  (eine neue Figur setzt die Farb-Überschreibungen zurück), Farbpunkte für Hautton/Haarfarbe/Trikotfarbe (die Farbe
  des Typs = keine Überschreibung), Bootsliste, Flaggen-Schalter (ohne Nationalität deaktiviert), Hinweis „Was
  andere sehen“. Vorschaubilder `Resources/AvatarPreviews/<characterId>.png` bzw. `<boatStyleId>.png` (im Bundle
  mit oder ohne Unterordner gesucht), bis dahin Platzhalter aus den Katalogfarben.
- Demo-Rennen (`-demoRace 1`, `RowingView.demoRace`): eigener Teilnehmer mit Anzeigename und `publicAppearance`,
  Bots mit `RowerAppearance.random(seed: <participantId>)`.
- Hauttöne (Monk Skin Tone Scale, CC BY 4.0): Namensnennung in NOTICE und unter Einstellungen → Quellen.
