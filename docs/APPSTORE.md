# App Store: Version 1.0 „Basis“

Stand: 28.11.2026. Ziel: RowCoach so schnell wie möglich als Version 1.0 in den Apple App Store bringen – zunächst nur
Apple (kein Google Play), kostenlos, ohne Server. Store-Auftritt auf Englisch (Entscheid Falk 28.11.2026), deutsche
Store-Lokalisierung optional später.

## 1. Editionen

Zwei Targets in `App/project.yml` teilen sich alle Quellen. Die Schalter stehen an einer Stelle:
`App/RowCoach/App/AppEdition.swift`.

| | **RowCoach** (Basis, Store) | **RowCoachDev** (Entwicklung) |
|---|---|---|
| Scheme | `RowCoach` | `RowCoachDev` |
| Kompilier-Bedingung | `EDITION_BASIC` | `EDITION_FULL` |
| Anzeigename | RowCoach | RowCoach Dev |
| Version / Build | 1.0.0 / 1 | 0.3.0 / 3 |
| Bundle-ID | com.falkue.RowCoach | com.falkue.RowCoach (vorerst gleich, siehe 1.3) |
| App-Symbol | AppIcon (Bahnen; hell, dunkel, getönt) | AppIconDev (Bahnen mit Band „DEV“) |
| Firebase, GoogleSignIn | **nicht gelinkt** | gelinkt |
| Build-Phase „Firebase-Konfiguration“ | – | ja |
| Datenschutz-Manifest | `App/Privacy/Basic/PrivacyInfo.xcprivacy` (keine Daten) | `App/Privacy/Dev/PrivacyInfo.xcprivacy` |
| Netzanfragen | **keine** (nur Apple-Dienste wie HealthKit, lokal) | Konto, Sync, Rennen, Strecken-Server |

### 1.1 Was in der Basis enthalten ist
- 16 mitgelieferte Strecken (`courses/bundled.json` → `App/Courses`, Stufe standard) plus `anavilhanas-kanal`
  (teilt die Szene mit `anavilhanas-igapo`).
- Coach-Stimme, Programme, Trainingspläne, Schwellentest und Zonen, Tempo-Linie, Verkehr auf dem Wasser, Figur/Boot/
  Flaggen, Statistik, Verlauf, Motivation, Bestzeiten und „Gegen meine Bestfahrt“ (Geisterboot, lokal).
- Apple Health, Concept2 PM5, Bluetooth-FTMS-Rudergeräte (Beta), Pulsgurte.
- **Demo ohne Rudergerät:** Geräte → „Ohne Rudergerät ausprobieren (Demo)“ (auch im ersten Start). Startet den
  eingebauten Simulator (`SimulatorDevice`). Demofahrten laufen mit der Gerätequelle Simulator und zählen deshalb nie
  in Statistik, Bestzeiten, Plan oder Apple Health (`TrainingSession.countsInStats`, `SessionController`,
  `ProgramStore.countsSimulatedRides`); im Release-Verlauf sind sie ausgeblendet.

### 1.2 Was in der Basis fehlt (weder sichtbar noch Netzverkehr)
| Funktion | Wie getrennt |
|---|---|
| Online-Rennen (Taste „Rennen“, RacesView, Warteraum, OnlineRaceStore) | `Race/**` und `Views/RacesView.swift` nicht im Target; Taste hinter `AppEdition.racesEnabled`; Aufrufe in RootView/RowingView unter `#if EDITION_FULL` |
| Turniere mit virtuellen Teilnehmenden | Einstieg nur über Rennen bzw. `-demoTournament` (im Basis-Release gesperrt); `VirtualTournamentStore` bleibt kompiliert, ist aber unerreichbar |
| Konto, Anmeldung, Synchronisation, Forschungs-Einwilligung | `Sync/**` nicht im Target; Einstellungsabschnitt „Konto & Synchronisation“, SyncController-Aufrufe in RowCoachApp und der Sync-Beobachter in ProgramStore unter `#if EDITION_FULL` |
| Strecken-Download, Katalog vom Server | `AppEdition.courseDownloadsEnabled = false`: `CourseDownloads.serverURL` immer nil (kein Katalog-Abruf), `CourseLibrary.catalogOnly` leer (keine ausgegrauten „ladbar“-Kacheln), geladene Strecken aus Application Support werden nicht gelesen, Feld „Strecken-Server“ ausgeblendet |
| Käufe, Abo | gibt es noch nicht (`AppEdition.purchasesEnabled = false`) |
| Testbetrieb-Startargumente | `AppEdition.applyLaunchArgumentPolicy()` verwirft im Basis-Release alle ausser `-photoMode`; im Debug-Build und in RowCoachDev gelten alle |

### 1.3 Später einzeln freischalten
1. Schalter in `AppEdition` auf eine Bedingung setzen (z. B. Kauf des Strecken-Pakets, aktives Abo).
2. Benötigte Dateien im Basis-Target wieder aufnehmen (`project.yml`, `excludes` des Targets RowCoach) und die
   Pakete dort verlinken (Firebase-Produkte nur, wenn wirklich nötig).
3. `#if EDITION_FULL` an den Aufrufstellen durch den Laufzeitschalter ersetzen.
4. Datenschutzangaben (Manifest, App Store Connect, privacy.html) **vor** dem Release anpassen.

Reihenfolge-Vorschlag: Strecken-Paket (StoreKit, Download vom statischen Server, keine Personendaten) → Sync (Konto)
→ Rennen (Abo).

**Später: eigene Bundle-ID für die Dev-Fassung.** Heute ersetzen sich beide Fassungen auf dem Gerät gegenseitig
(gleiche ID, gleicher Datenbestand). Für eine parallele Installation `PRODUCT_BUNDLE_IDENTIFIER` von RowCoachDev auf
z. B. `com.falkue.RowCoach.dev` setzen und die App in beiden Firebase-Projekten (rowcoach-dev, rowcoach-prod) neu
registrieren: neue `GoogleService-Info.plist` laden, OAuth-Client/REVERSED_CLIENT_ID für Google-Anmeldung, App Check
(DeviceCheck) für die neue ID, ggf. Authorized Domains/Links. Daten aus der alten Installation wandern dabei nicht mit.

## 2. Bauen und archivieren (Mac)

```bash
cd ~/Projects/Software/RowCoach/App
ROWCOACH_TEAM_ID=<Team-ID> xcodegen generate
open RowCoach.xcodeproj
```
1. Scheme **RowCoach**, Ziel „Any iOS Device (arm64)“.
2. Product → **Archive**. Im Organizer: **Validate App** (prüft Signatur, Symbole, Privacy-Manifest, Icons).
3. **Distribute App → App Store Connect → Upload**. Danach erscheint der Build nach einigen Minuten unter
   TestFlight; Exportkonformität ist über `ITSAppUsesNonExemptEncryption = NO` schon beantwortet.
4. Neuer Upload derselben Version: `CURRENT_PROJECT_VERSION` des Targets RowCoach erhöhen (2, 3, …).
5. Store-Screenshots: Scheme RowCoach im **Debug**-Build (dort gelten `-demoCourse`, `-seedDemoHistory`,
   `-photoMode`), Simulator iPhone 17 Pro Max (6,9″) und iPad Pro 13″.

## 3. Checkliste App Store Connect (Falk)

### 3.1 Einmalig
- [ ] Apple Developer Program aktiv; Agreements, Tax and Banking (auch für Gratis-Apps das „Free Apps Agreement“).
- [ ] Identifier `com.falkue.RowCoach` mit Capability **HealthKit** (legt Xcode bei automatischer Signierung an).
- [ ] Datenschutz- und Support-Seite veröffentlichen: Repo → Settings → Pages → Source **GitHub Actions**, dann
      läuft `.github/workflows/pages.yml` beim nächsten Push auf `docs/site/**` (oder von Hand „Run workflow“).
      Adressen: https://falkue.github.io/RowCoach/privacy.html und https://falkue.github.io/RowCoach/support.html
      (stehen auch in der App: Einstellungen → Über RowCoach). Kontakt-E-Mail auf `support.html`: admin@rowcoach.uk
      (Cloudflare Email Routing auf rowcoach.uk, eingerichtet 28.11.2026).

### 3.2 App-Datensatz (My Apps → +  → New App)
- **Angelegt 28.11.2026:** Platform iOS · Name im Store **Row-Coach** („RowCoach“ war belegt) · Primary Language
  English (U.S.) · Bundle ID com.falkue.RowCoach · SKU `ROWCOACH-IOS-1` · User Access Full Access.
- Anzeigename auf dem Gerät bleibt „RowCoach“ (CFBundleDisplayName); Apple erlaubt einen kürzeren Anzeigenamen,
  solange er dem Store-Namen entspricht. Website, Support- und Datenschutzseite sprechen von „RowCoach“.

### 3.3 App Information
- Subtitle (≤ 30 Zeichen), drei Varianten:
  1. `Row the world's waters` (22) – Empfehlung
  2. `Indoor rowing on real water` (27)
  3. `3D courses for indoor rowing` (28)
  („Virtual rowing for your PM5“ wäre griffig, nennt aber eine Marke von Concept2 – Risiko bei der Prüfung, Richtlinie
  5.2; deshalb nur in der Beschreibung mit Hinweis „not affiliated“.)
- Category: **Health & Fitness**, Secondary: **Sports**.
- Content Rights: enthält keine Inhalte Dritter, für die Rechte fehlen (Geodaten: offene Lizenzen, Quellen in der App
  unter Einstellungen → Quellen und Lizenzen, siehe `docs/LIZENZEN-GEODATEN.md`).
- Age Rating: alle Fragen „None“/„No“ → **4+**. (Keine Nutzerinhalte, kein Web, kein Chat.)
- Privacy Policy URL: https://falkue.github.io/RowCoach/privacy.html

### 3.4 App Privacy
- „Do you or your third-party partners collect data from this app?“ → **No, we do not collect data from this app.**
  → Label **„Data Not Collected“**.
- Begründung (für Rückfragen): Die Basis-Fassung linkt kein Analyse-, Werbe- oder Backend-SDK (Firebase/GoogleSignIn
  nur im nicht eingereichten Target RowCoachDev), stellt keine Netzanfrage und überträgt nichts vom Gerät. Apple
  zählt Daten, die nur auf dem Gerät verarbeitet werden, nicht als „collected“. HealthKit-Daten werden lokal
  gelesen/geschrieben; Bluetooth-Daten fliessen nur vom Gerät in die App. Das Manifest
  `App/Privacy/Basic/PrivacyInfo.xcprivacy` sagt dasselbe (NSPrivacyTracking false, keine Datentypen).

### 3.5 Pricing and Availability
- Price: **Free** (Tier 0). Availability: alle Länder (oder Auswahl); nur App Store für iPhone und iPad.
  „Make available on Mac (Apple silicon)“ und „Apple Vision Pro“ **abwählen** (nicht getestet).

### 3.6 Version 1.0 (iOS App)
- Screenshots (je 3–10, Pflicht):
  - iPhone **6,9″**: 1320 × 2868 (oder 1290 × 2796) Hochformat bzw. quer gedreht.
  - iPad **13″**: 2064 × 2752 (oder 2048 × 2732).
  - Vorschlag: Ruderbildschirm auf einer Strecke (Venedig, Geirangerfjord), Seen-Pass, Programm mit Phasen, Statistik/
    Verlauf, Zusammenfassung nach der Fahrt. Keine Rennen, kein Konto zeigen.
- Promotional Text, Description, Keywords: Abschnitt 4.
- Support URL: https://falkue.github.io/RowCoach/support.html · Marketing URL (optional): https://falkue.github.io/RowCoach/
- Version: 1.0 · Copyright: `2026 Falk Uebernickel`
- Build: den hochgeladenen Build wählen.
- App Review Information: Sign-in required **No**; Kontakt (Name, Telefon, E-Mail); Notes: Abschnitt 4.5.
- Version Release: manuell oder automatisch nach Freigabe.

## 4. Store-Texte (English)

### 4.1 Promotional Text (≤ 170)
```
Row through Venice, a Norwegian fjord or the Amazon on your indoor rower. Free, no account, no ads – everything stays on your device.
```

### 4.2 Description (≤ 4000)
```
RowCoach turns your indoor rowing machine into a boat on real water. Row through 3D landscapes built from official
open geodata, follow guided workouts with a spoken coach, and keep every session in Apple Health.

REAL WATERS
• 17 courses included: the Rhine in Basel, the Spree in Berlin, Lake Zurich, the Thames in London and at Henley,
  Lake Annecy, Lucerne, Vienna's Old Danube, the Grand Canal in Venice, Amsterdam's Amstel, Hamburg's Outer Alster,
  Oslo, the Geirangerfjord and Lysefjord in Norway, and the Amazon near Iquitos and Anavilhanas.
• Terrain, aerial imagery, buildings and trees computed from public data sources.
• Other rowers and boats share the water with you. Your boat moves at your real speed.

TRAINING
• Free rowing with a pace line, or structured workouts: intervals, steady state, pyramids, tests.
• Multi-week training plans that adapt to how your sessions go.
• Threshold test and personal heart-rate and pace zones.
• A spoken coach announces phase changes, halfway and the last 500 m – calm, motivating or cox style.
• Race your own best row as a ghost boat.

YOUR DATA, ON YOUR DEVICE
• Splits, stroke rate, watts, heart-rate zones, effort and history with weekly statistics and personal bests.
• Every row is saved to Apple Health as an indoor rowing workout, with heart rate and – if you allow it – the
  course as a route.
• No account, no ads, no tracking, no server. RowCoach collects no data.

DEVICES
• Concept2 RowErg with PM5 via Bluetooth.
• Other rowing machines with Bluetooth FTMS (beta).
• Bluetooth heart-rate straps (Polar, Garmin, Wahoo and others).
• No rowing machine at hand? Try the built-in demo rower.

Open source (Apache-2.0): github.com/falkue/RowCoach
RowCoach is not affiliated with or endorsed by Concept2, Inc. Concept2, RowErg and PM5 are trademarks of Concept2, Inc.
```

### 4.3 Keywords (≤ 100, Komma ohne Leerzeichen, keine Wörter aus Name/Untertitel, keine fremden Marken)
```
erg,ergometer,rower,workout,intervals,heart rate,zones,3d,lake,river,fjord,cardio,ftms,training
```

### 4.4 What's New (1.0)
```
First release.
```

### 4.5 App Review Notes
```
RowCoach is a training app for indoor rowing machines (Concept2 PM5 and Bluetooth FTMS rowers) and Bluetooth
heart-rate straps. No account or sign-in is needed, and the app makes no network requests.

Testing without hardware: open the device status at the top right (or the "Devices" step during first launch) and
tap "Try without a rowing machine (demo)". A simulated rower then sends the same data a PM5 and a heart-rate strap
would. Go to the "Courses" tab, pick any course (e.g. "Grand Canal – from the Ferrovia to San Marco"), tap "Just row"
and the boat starts moving. Workouts ("Workouts" tab) can be started the same way. Demo rows are labelled "Simulator" and are never
written to Apple Health or counted in statistics.

HealthKit: used to save each row as an indoor rowing workout (distance, energy, heart rate, effort, optional route)
and to read past workouts and heart rate for training analysis. Health data never leaves the device.
Bluetooth: used only to connect to the rowing machine and the heart-rate strap.

RowCoach is not affiliated with Concept2, Inc.; the PM5 protocol is implemented from Concept2's public
"PM CSAFE Communication Definition".
```
Vor dem Absenden die englischen Tab- und Tastennamen in der Notiz gegen die App prüfen (Simulator auf Englisch).

## 5. Prüfschritte auf dem Mac vor dem Upload
1. `xcodegen generate`; beide Schemes bauen (RowCoach, RowCoachDev), jeweils Debug und Release.
2. **Basis ohne Netz:** Release-Build von RowCoach auf dem Gerät im Flugmodus (WLAN aus) durchklicken – alles muss
   gehen. Zusätzlich Instruments → Network (oder Console mit Filter `nw_`/`CFNetwork`): beim Start, im Tab Strecken,
   in den Einstellungen und während einer Fahrt keine Verbindung.
3. **Keine Online-Oberfläche:** keine Taste „Rennen“ im Tab Strecken; Einstellungen ohne „Konto & Synchronisation“
   und ohne Strecken-Server; Seen-Pass nur mit den mitgelieferten Strecken, keine ausgegrauten Kacheln, Untertitel
   „17 Strecken, … noch offen.“
4. **Demo:** Geräte → „Ohne Rudergerät ausprobieren (Demo)“ → Fahrt auf einer Strecke → Zusammenfassung zeigt
   „Simulatorfahrt – nicht in Apple Health“; Statistik/Bestzeiten unverändert; „Demo beenden“ schaltet zurück.
5. Einstellungen → Über RowCoach: Version 1.0.0, Links Datenschutz/Hilfe, Satz „RowCoach erfasst keine Daten …“;
   Quellen und Lizenzen mit Concept2-Hinweis und Geodaten-Quellen.
6. Product → Archive → Validate App ohne Fehler; im Organizer „Generate Privacy Report“ prüfen (keine Datentypen).
7. App-Symbol: hell, dunkel und getönt auf dem Home-Bildschirm (iOS 26: Bildschirm lange drücken → Bearbeiten →
   Anpassen).
