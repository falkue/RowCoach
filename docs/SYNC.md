# Konto und Synchronisation (Online-Funktion a), Stand 27.11.2026

Ziel (Falk): Fahrten, Profil und Trainingseinstellungen zwischen den eigenen Geräten abgleichen, iOS jetzt, Android
später. **Kostenlos, freiwillig, offline zuerst.** Die App funktioniert ohne Konto und ohne Netz vollständig; ohne
Anmeldung stellt sie keine einzige Anfrage an unseren Server (Ausnahme: der Streckenkatalog beim Laden einer Strecke,
docs/STRECKEN-SERVER.md). Rennen (Abo) und Forschung sind eigene Bausteine; hier liegen nur ihre Grundlagen.

## Überblick

```
 SwiftData (Fahrten) ─┐                         ┌─ FirestoreSyncBackend ── Firestore europe-west6 (Zürich)
 UserDefaults (Einst.)┼─ AppSyncStore ─ SyncEngine (Kit) ─┤      users/{uid}/rides, settings, consent, …
 Sync/<uid>.json ─────┘   (SyncLocalStore)  │             └─ NoopSyncBackend (Standard, kein Netz)
                                            └─ AuthProvider: FirebaseAuthProvider | NoopAuthProvider
```

| Ort | Inhalt |
|---|---|
| `App/RowCoachKit/Sources/RowCoachKit/Sync/` | `HybridLogicalClock.swift` (Zeitstempel), `SampleCodec.swift` (Zeitreihe binär), `SyncModels.swift` (Serverform, Einstellungskatalog, Einwilligung, Berechtigung, Export), `SyncMerge.swift` (Konfliktregeln, Abgleichsstand `SyncLedger`), `SyncEngine.swift` (Ablauf), `SyncProviders.swift` (Schnittstellen + No-op + In-Memory) |
| `App/RowCoachKit/Tests/RowCoachKitTests/SyncTests.swift` | 28 Tests (Linux): Uhr, Binärform, Stückelung, Merge, Konflikte, Löschung, Idempotenz, Abbruch, „ohne Konto keine Anfrage“ |
| `App/RowCoach/Sync/` | `FirebaseBootstrap` (Firebase erst bei Bedarf), `FirebaseAuthProvider`, `FirestoreSyncBackend`, `AppSyncStore`, `SyncController`, `AccountSyncView` (Einstellungen → Konto & Synchronisation) |
| `firebase/firestore.rules`, `firebase/firestore.indexes.json` | Sicherheitsregeln, Index-Ausnahmen für grosse Felder |
| `firebase/tests/` | Regeltests für den Emulator (siehe „Regeln testen“) |

Alles ausser Firebase-SDK und Oberfläche liegt im Kit (nur Foundation) und gilt damit auch für Android
(docs/ANDROID.md); Android braucht nur eine eigene `SyncBackend`/`AuthProvider`-Umsetzung über das Firebase-Android-SDK.

## Offline zuerst und „ohne Konto nichts“

- Die App liest und schreibt immer nur ihren lokalen Speicher (SwiftData, UserDefaults). Der Abgleich läuft daneben.
- `SyncEngine.sync()` prüft zuerst den Schalter „Synchronisation“ (Standard aus) und dann das Konto. Fehlt eins,
  endet sie mit `.disabled` bzw. `.signedOut`, **bevor** sie den Server anspricht. Dasselbe gilt für Einwilligung,
  Export und Löschen. Test: `SyncEngineTests.testNoAccountNoRequest` (Anfragezähler bleibt 0),
  `testSyncOffMeansNoRequestEvenWhenSignedIn`, `testUnverifiedEmailDoesNotPush`, `testOfflineDefaultEngine`.
- Firebase selbst wird erst eingerichtet (`FirebaseBootstrap.configureIfNeeded`), wenn jemand auf „Anmelden“,
  „Registrieren“ oder „Mit Google anmelden“ tippt, oder beim Start, wenn auf dem Gerät schon jemand angemeldet ist
  (`sync.accountActive`). Vorher lädt die App nur den Code des SDK, ruft es aber nicht auf.
- Abmelden lässt alle Daten auf dem Gerät. Meldet sich danach ein anderes Konto an, beginnt dessen Abgleich bei null
  (eigener Abgleichsstand je uid) und lädt die Fahrten des Geräts in dieses Konto.

## Datenmodell (Firestore)

```
users/{uid}                              (kein eigenes Dokument)
  rides/{rideId}                         eine Fahrt; rideId = WorkoutRecord.id (UUID, gross)
    chunks/{0…7}                         nur sehr lange Fahrten: Teile der Binärdaten
  settings/{profile|program|motivation}  Einstellungen, je Feld mit Zeitstempel
  consent/{research|sync}                aktueller Stand jeder Einwilligung
  consentLog/{autoId}                    Protokoll aller Entscheidungen (nur anhängen)
  entitlements/{races}                   Berechtigungen (nur der Server schreibt)
```

### Fahrten: unveränderlich, angehängt

| Feld | Inhalt |
|---|---|
| `v` | Schemaversion (`SyncSchema.version` = 1). Neuere Version auf dem Server → die App meldet „bitte aktualisieren“ statt falsch zu lesen. |
| `id`, `start`, `distance`, `activeDuration` | Kennung und Listenfelder (lesbar ohne die Binärdaten) |
| `record` | `WorkoutRecord` als JSON **ohne** Zeitreihe, RR und Belastung (Kopf, Zusammenfassung, Splits, Phasen); ≤ 200 KB |
| `samples` | Zeitreihe + RR binär (`SampleCodec`), wenn ≤ 700 KB; sonst fehlt das Feld und `chunks/` trägt die Teile |
| `codec`, `chunkCount`, `thinned` | Format der Binärdaten, Zahl der Teile, ggf. Ausdünnungsschritt |
| `effort`, `effortClock` | Belastung (`WorkoutEffort` als JSON) und ihr HLC-Zeitstempel – der einzige veränderliche Teil |
| `deleted`, `deletedClock` | Tombstone (siehe Löschungen) |
| `updatedAt` | Serverzeit (`request.time`), Grundlage der Abfrage „was hat sich seit … geändert“ |

- Eine Fahrt wird einmal angelegt und dann nie mehr verändert, nur die Belastung kann nachträglich wechseln (eigene
  Einschätzung nach der Fahrt). Entdoppelt wird über die id: legt ein zweites Gerät dieselbe Fahrt an, bleibt die erste.
- Nicht synchronisiert: Beispielfahrten (`-seedDemoHistory`) und Simulatorfahrten im Release-Build. Im Debug-Build
  gehen Simulatorfahrten mit (dort ist alles `rowcoach-dev`).
- Vom Server geholte Fahrten werden lokal als „in Apple Health gespeichert“ markiert (das andere Gerät hat sie
  geschrieben; Health gleicht selbst ab), damit kein zweites Health-Training entsteht.

### Grössenbudget

Firestore erlaubt 1 MiB je Dokument (inklusive Feldnamen). `SampleCodec` speichert jede Spalte (Zeit in ms, Distanz in
cm, Tempo in 0,01 s, Schlagzahl, Leistung, Puls) als Differenz zum Vorwert mit ZigZag-Varint; RR in ms ebenso.
Auflösung feiner als der PM5 liefert, also ohne Informationsverlust. Keine Kompressionsbibliothek nötig (auf
Linux/Android fehlt `NSData.compressed`).

| Fahrt | JSON (heute lokal) | Server |
|---|---|---|
| 1 h, 1 Hz, mit Puls und RR | ≈ 250 KB | ≈ 30–40 KB Binär + ≈ 5–10 KB `record` |
| 12 h (Marathon-Rekordversuch) | ≈ 3 MB | ≈ 0,4–0,5 MB, noch im Hauptdokument |
| 24 h mit stark schwankenden Werten | ≈ 6 MB | in `chunks/` (je ≤ 700 KB, höchstens 8) |

Erst wenn auch 8 Teile nicht reichen (≈ 5,6 MB Binär), dünnt `RideWireCodec` die Zeitreihe aus (jeder 2., 4., …
Punkt; ab Schritt 8 ohne RR) und vermerkt das in `thinned`. Test: `RideWireTests`.

### Einstellungen: feldweise, neuester Stand gewinnt

`settings/{doc}` = `{ v, fields: { <feld>: { v: <JSON-Text oder null>, c: <HLC> } }, updatedAt }`.

| Dokument | Felder (lokaler Schlüssel) |
|---|---|
| `profile` | `rower` (`profile.rower`: Anzeigename, Nationalität, Figur, Boot, Flaggen – **ohne Geschlecht**), `maxHR`, `restHR`, `best2k`, `weightKg` |
| `program` | `active` (`trainingProgram.active`, Zustand des Trainingsplans) |
| `motivation` | `weeklyGoal` (`home.weeklyGoal`), `successLines`, `milestones`, `goalKind`, `goalMinutes`, `goalSince`, `goalReviewDismissed`, `pauses`, `intention` |

Die Liste steht einmal im Kit (`SyncSettingsCatalog`) und in `firestore.rules` (Test prüft die Feldliste).
Gerätebezogenes bleibt lokal: gekoppelte Geräte, Erinnerungsprotokoll, Darstellung, Coach-Stimme, Strecken-Server.
Ein entfernter Wert (z. B. Plan beendet) ist ein Feld mit `v: null` und eigenem Zeitstempel.

## Sync-Engine

Ablauf von `SyncEngine.sync()` (Kit, Actor, immer nur ein Lauf gleichzeitig):

1. Schalter und Konto prüfen (sonst Ende ohne Anfrage); E-Mail-Konto ohne Bestätigung → `.notVerified`.
2. **Lokal beobachten** (`SyncLedger.observe`): neue Fahrten merken, geänderte Belastung und gelöschte Fahrten mit
   HLC stempeln, geänderte Einstellungen stempeln. Der Abgleichsstand liegt je Konto in
   `Application Support/Sync/<uid>.json`; die SwiftData-Datenbank bleibt unverändert.
3. **Holen**: Fahrten mit `updatedAt` > letzter Cursor (Seiten à 100), zusammenführen, lokal anwenden (einfügen,
   Belastung ersetzen, löschen).
4. **Senden**: neue Fahrten, neuere Belastungen, Tombstones (je 20 pro Anfrage; Stand nach jedem Paket gesichert).
5. **Einstellungen**: holen, feldweise zusammenführen, lokal anwenden, eigene neuere Felder senden. Der Server führt in
   einer Transaktion noch einmal zusammen (gleiche Regel), die Regeln lehnen ältere Stände ab.

Auslöser in der App (`SyncController`): App wird aktiv, 15 s nach einer gespeicherten Fahrt, „Jetzt abgleichen“,
Einschalten, Anmelden. Lokale Änderungen werden 2 s nach dem Speichern gestempelt (`noteLocalChanges`, ohne Netz),
damit ein Konflikt nach dem Zeitpunkt der Änderung entschieden wird und nicht nach dem des nächsten Abgleichs.
Ein abgebrochener Abgleich (Netz weg) wiederholt beim nächsten Mal genau das Fehlende (Test
`testFailureMidwayRecoversWithoutDuplicates`).

### Konflikte

- **Uhr:** Hybrid Logical Clock je Gerät (`HybridTimestamp`: Wanduhr ms, Zähler, Geräte-Id). Streng wachsend, auch
  wenn die Geräteuhr zurückspringt; übernimmt beim Empfang den grössten bekannten Stand; Zeitstempel mehr als einen Tag
  in der Zukunft werden gekappt. Als Text lexikografisch sortierbar, damit die Regeln vergleichen können.
- **Fahrten:** angehängt, entdoppelt nach id (Inhalt unveränderlich).
- **Belastung:** neuester Zeitstempel gewinnt (Test `testEffortConflictLaterChangeWins`: B ändert später, gleicht
  aber zuerst ab – trotzdem gilt B auf allen Geräten).
- **Einstellungen:** je Feld neuester Zeitstempel (A ändert den Maximalpuls, B die Bestzeit → beides bleibt). Merge ist
  kommutativ, assoziativ und idempotent (Test).
- **Erstabgleich eines Geräts:** Werte, die schon vor der Anmeldung auf dem Gerät lagen, bekommen den „Erststand“
  (Wanduhr 0) und verlieren gegen den Server. So überschreibt ein neues iPad mit Standardwerten nicht das Profil vom
  iPhone; Werte, die der Server noch nicht kennt, gehen hinauf (Test `testNewDeviceWithDefaultsDoesNotOverwriteServer`).

### Löschungen (Tombstones)

- Löscht man eine Fahrt auf einem Gerät, ersetzt der Server sie durch einen Tombstone `{v, id, deleted: true,
  deletedClock, updatedAt}` – **ohne** Trainingsdaten (Datenschutz), Zusatzstücke werden im selben Batch gelöscht.
- Ein Tombstone gewinnt immer: die Fahrt verschwindet auf allen Geräten und kommt nie zurück, auch nicht, wenn ein
  anderes Gerät gleichzeitig die Belastung geändert hat oder die Fahrt erneut hochladen will (Regeln: keine Änderung
  an Tombstones). Test `testDeletionPropagatesAndNeverResurrects`.
- Wird eine Fahrt gelöscht, bevor sie je hochgeladen war, geht nichts hinaus (`testLocalDeleteBeforeUploadSendsNothing`).
- Tombstones bleiben liegen (wenige Byte). „Alle Server-Daten löschen“ entfernt auch sie.

## Schnittstellen (Kit)

| Protokoll | Zweck | Umsetzungen |
|---|---|---|
| `SyncBackend` | `fetchRides(since:)`, `push([RideChange])`, `fetchSettings`/`pushSettings`, `fetchConsents`/`pushConsent`, `exportAll`, `deleteAllUserData` | `NoopSyncBackend` (wirft `unavailable`), `InMemorySyncBackend` (Tests, gleiche Regeln wie Firestore), `FirestoreSyncBackend` (App) |
| `AuthProvider` | Konto: aktueller Nutzer, E-Mail anmelden/registrieren, Bestätigung, Passwort zurücksetzen, abmelden, Konto löschen | `NoopAuthProvider`, `InMemoryAuthProvider`, `FirebaseAuthProvider` (+ Google in der Hülle) |
| `EntitlementProvider` | Berechtigungen (Rennen-Abo, später) | `NoopEntitlementProvider` (immer inaktiv), `InMemoryEntitlementProvider` |
| `SyncLocalStore` | lokaler Speicher für die Engine | `InMemorySyncStore` (Tests), `AppSyncStore` (SwiftData/UserDefaults) |

`SyncEngine.offline(store:)` ist die Standardverdrahtung ohne Konto.

## Sicherheitsregeln (firebase/firestore.rules)

- Nur das eigene `users/{uid}`; kein Zugriff auf andere Konten, alles andere gesperrt.
- Schreiben nur mit bestätigter E-Mail oder über Google/Apple (`email_verified` bzw. Anmeldeanbieter).
- **Fahrten:** Anlegen nur mit gültiger Form (Feldliste, Typen, `id` = Dokument-Id im UUID-Format, `record` ≤ 200 KB,
  `samples` ≤ 700 KB oder Zusatzstücke, `updatedAt == request.time`, `deleted == false`). Ändern nur (a) Belastung mit
  neuerem HLC-Zeitstempel, sonst nichts, oder (b) Ersetzen durch einen gültigen Tombstone. Tombstones sind endgültig.
  Zusatzstücke nur im selben Batch wie die Fahrt (`getAfter`), Index < `chunkCount`, nicht änderbar.
- **Einstellungen:** nur die drei Dokumente, nur Felder aus dem Katalog, Wert Text ≤ 16 KB oder null, Zeitstempel im
  HLC-Format; kein Feld darf durch einen älteren Zeitstempel ersetzt werden.
- **Einwilligungen:** nur die Person selbst; Art `research` oder `sync`, `granted` bool, Textfassung, Sprache,
  Gerätezeit und **Serverzeit** (`at == request.time`). Das Protokoll ist nur anhängbar.
- **Berechtigungen:** lesen ja, schreiben nie (nur Admin SDK des Servers).
- Löschen der eigenen Dokumente ist erlaubt (Export/Löschen, Konto löschen).
- Index-Ausnahmen (`firestore.indexes.json`): `record`, `samples`, `effort`, Zeitstempel-Texte, `chunks.data`,
  `settings.fields` werden nicht indiziert (spart Speicher und Schreibkosten; abgefragt wird nur `updatedAt`).

### Regeln testen

Der Firestore-Emulator braucht **Java ≥ 21**; auf der Spark ist nur Java 8 – dort nicht installieren. Auf dem Mac
(oder einem Rechner mit Java 21):

```
brew install openjdk@21            # einmalig, falls nötig; JAVA_HOME setzen
npm install -g firebase-tools      # einmalig (oder npx firebase-tools)
cd firebase/tests && npm install
npm run emulator-test              # startet den Emulator (Port 8085, Projekt demo-rowcoach) und node --test
```

`firebase/tests/firestore.rules.test.mjs` prüft: Anlegen nur eigenes Konto/bestätigt/gültige Form, Lesen nur eigenes
Konto, Unveränderlichkeit, Belastung nur neuer, Tombstone endgültig, Zusatzstücke, Einstellungen (Feldliste, Form,
kein älterer Stand), Einwilligung mit Serverzeit, Berechtigungen nur Server, fremde Pfade gesperrt.
Das Projekt `demo-rowcoach` ist ein reines Emulator-Projekt (kein Zugriff auf rowcoach-dev/prod).

**Deploy erst nach Prüfung (Falk):** `firebase deploy --only firestore:rules,firestore:indexes -P dev`, nach Test auf
dem Gerät `-P prod`. Die Realtime-Database-Regeln bleiben gesperrt (Rennen später).

## Anmeldung

- **E-Mail/Passwort:** Registrieren schickt sofort den Bestätigungslink; bis zur Bestätigung zeigt die App nur
  „Ich habe bestätigt“ / „Link erneut senden“ (die Regeln würden Schreibvorgänge ohnehin ablehnen). „Passwort
  vergessen?“ schickt die Firebase-Mail zum Zurücksetzen (Text ohne Hinweis, ob das Konto existiert).
  E-Mail-Vorlagen (Absender, Sprache de/en) in der Firebase-Konsole unter Authentication → Templates einstellen.
- **Google:** GoogleSignIn-SDK; braucht `CLIENT_ID`/`REVERSED_CLIENT_ID` in der GoogleService-Info.plist. Die heutigen
  plists (dev/prod) enthalten sie **noch nicht** → nach dem Einschalten von Google die plists neu aus der Konsole laden.
  Die Build-Phase trägt `REVERSED_CLIENT_ID` als URL-Schema in die gebaute Info.plist ein; ohne den Schlüssel ist der
  Knopf ausgegraut.
- **Sign in with Apple:** vor dem Store-Start nötig (App-Store-Richtlinie 4.8: wer Google-Anmeldung anbietet, muss eine
  gleichwertige datensparsame Anmeldung anbieten). Braucht die Berechtigung „Sign in with Apple“ im App-Profil,
  Anbieter „Apple“ in Firebase und `ASAuthorizationAppleIDProvider` + `OAuthProvider.appleCredential` in
  `FirebaseAuthProvider`. Noch nicht gebaut.
- **Konto löschen** in der App (Pflicht nach Richtlinie 5.1.1(v)): erst alle Server-Daten, dann das Firebase-Konto.
  Verlangt Firebase eine frische Anmeldung, meldet die App das.

## App Check

- Debug-Build: `AppCheckDebugProviderFactory` – das Debug-Token steht beim ersten Start im Xcode-Protokoll und wird in
  der Konsole (App Check → Apps → Debug-Tokens) eingetragen.
- Release: `DeviceCheckProviderFactory` (ohne zusätzliche Berechtigung). Besser später App Attest (braucht die
  Berechtigung `com.apple.developer.devicecheck.appattest-environment`).
- Durchsetzung (Enforcement) für Firestore und Authentication erst einschalten, wenn die Metriken in der Konsole nur
  noch gültige Anfragen zeigen.

## Datenschutz

- **Ort:** Firestore `(default)` in europe-west6 (Zürich) – Fahrten, Einstellungen, Einwilligungen liegen in der
  Schweiz. **Firebase Authentication** (E-Mail-Adresse, Google-Kennung) ist ein globaler Dienst von Google und
  verarbeitet auch in den USA (Grundlage: Google Cloud Data Processing Addendum mit Standardvertragsklauseln bzw.
  Swiss-U.S. Data Privacy Framework). Das steht im Einwilligungstext der Synchronisation. Die Realtime Database
  (europe-west1, Belgien) betrifft nur Rennen.
- **Gesundheitsdaten:** Puls und RR sind Gesundheitsdaten – DSGVO Art. 9 („besondere Kategorien“) bzw. nDSG Art. 5
  lit. c („besonders schützenswerte Personendaten“). Rechtsgrundlage der Synchronisation ist die **ausdrückliche
  Einwilligung** (Art. 9 Abs. 2 lit. a DSGVO; Art. 6 Abs. 7 nDSG): Einschalten nur über den Dialog mit dem Text
  `SyncSettings.syncConsentText`, gespeichert als `consent/sync` mit Textfassung (`sync-2026-11`), Sprache, Gerätezeit
  und Serverzeit, dazu ein Eintrag im `consentLog`. Ausschalten speichert `granted: false`; die Daten bleiben, bis man
  „Alle Server-Daten löschen“ wählt.
- **Forschung:** eigene, ausdrückliche, widerrufbare Einwilligung (`consent/research`, Fassung `research-2026-11`),
  **Standard aus**, nicht an die Synchronisation gekoppelt (eigener Schalter, eigener Text). Gespeichert mit Zeitpunkt
  und Textfassung, Widerruf ebenso (Protokoll bleibt bis zur Löschung). Auswertungen nur über Konten mit
  `granted == true` zum Zeitpunkt der Auswertung; veröffentlicht werden nur anonymisierte bzw. aggregierte Ergebnisse
  (keine Einzelfahrten, keine Anzeigenamen, Mindestgruppengrösse festlegen). Eine Auswertung ist **nicht** gebaut.
- **Datensparsamkeit:** kein Analytics, keine Werbe-Id, kein Geschlecht; der Anzeigename steckt nur im Profil.
  Gerätenamen von PM5/Pulsgurt stehen im `record` (wie lokal) – siehe offene Entscheidungen.
- **Auskunft und Übertragbarkeit (Art. 15/20 DSGVO, Art. 25/28 nDSG):** „Server-Daten exportieren“ erzeugt eine
  JSON-Datei mit allen Fahrten (vollständig, inkl. Zeitreihe), Einstellungen, Einwilligungen und Berechtigungen
  (`SyncExport`) und öffnet das Teilen-Menü.
- **Löschung (Art. 17):** „Alle Server-Daten löschen“ entfernt Fahrten, Zusatzstücke, Einstellungen, Einwilligungen und
  das Protokoll; das Gerät behält alles. „Konto löschen“ zusätzlich das Firebase-Konto. Berechtigungen (Abo) darf nur
  der Server löschen → beim Rennen-Abo eine Cloud Function `auth.user().onDelete` (oder die Erweiterung „Delete User
  Data“), die `users/{uid}` vollständig entfernt, auch was der Client nicht löschen darf. Backups: Firestore-PITR/Backups
  nur mit kurzer Aufbewahrung (≤ 7 Tage) einschalten und in der Datenschutzerklärung nennen.
- **Datenschutzerklärung und App-Store-Angaben** (App Privacy: Gesundheit & Fitness, Kontaktinfo E-Mail, nicht mit
  Tracking verknüpft) vor dem Store-Start anpassen.

## Kosten (grob)

Annahme „typische Nutzung“: 4 Fahrten/Woche (≈ 17/Monat) à 40 min, 2 Geräte, je Gerät ≈ 2 Abgleiche/Tag.

| Vorgang je Konto und Monat | Anzahl |
|---|---|
| Schreiben (Fahrten, Belastung, Einstellungen, Einwilligung) | ≈ 50 |
| Lesen (Abfrage je Abgleich ≥ 1, Einstellungen 3, Prüfen vor dem Anlegen, geholte Fahrten) | ≈ 500–600 |
| Speicher-Zuwachs (≈ 30 KB je Fahrt inkl. Index) | ≈ 0,5 MB/Monat, ≈ 6 MB nach einem Jahr |
| Download beim Einrichten eines neuen Geräts | einmal die ganze Historie (≈ 6 MB/Jahr Training) |

Kostenloser Rahmen von Firestore (Firebase-Dokumentation „Understand Cloud Firestore billing“, abgerufen 27.11.2026):
50 000 Lesevorgänge, 20 000 Schreib- und 20 000 Löschvorgänge pro Tag, 1 GiB Speicher, 10 GiB Datenübertragung pro
Monat. Damit reichen die Lesevorgänge für grob 2500 aktive Konten am Tag; zuerst wird der **Speicher** knapp
(1 GiB ≈ 170 Konten mit einem Jahr Historie).

Darüber (Blaze): Die Preise je Region stehen nur im Google-Cloud-Preisrechner; europe-west6 ist teurer als die
US-Regionen. Zur Abschätzung mit vorsichtigen Obergrenzen gerechnet (vor dem Start prüfen): 0,12 USD je 100 000
Lesevorgänge, 0,35 USD je 100 000 Schreibvorgänge, 0,30 USD je GiB und Monat. Ergibt je Konto und Monat:
Lesen ≈ 0,0007 USD, Schreiben ≈ 0,0002 USD, Speicher nach einem Jahr ≈ 0,002 USD – **zusammen weniger als 0,01 USD
je Konto und Monat**, 1000 Konten ≈ 2–3 USD/Monat, fast nur Speicher. Firebase Authentication (E-Mail, Google, Apple)
liegt bei diesen Zahlen im kostenlosen Rahmen. Die Synchronisation kann also dauerhaft gratis bleiben; ein Budget-Alarm
im Google-Cloud-Konto (z. B. 10 USD) gehört trotzdem dazu.

## Rennen-Abo (später, nur Platzhalter)

- Datenmodell: `users/{uid}/entitlements/races` = `{active, expiresAt, source (appStore|playStore|promo), productId,
  verifiedAt, originalTransactionId}`; im Kit `Entitlement`, `EntitlementStatus` (`isActive(at:)`).
- Kauf in der App über StoreKit 2 bzw. Play Billing; der Beleg geht an eine Cloud Function (App Store Server API /
  Google Play Developer API), die prüft und `entitlements/races` mit dem Admin SDK schreibt; App Store Server
  Notifications V2 / Real-time Developer Notifications halten den Stand aktuell. Die App liest nur
  (`EntitlementProvider`, heute `NoopEntitlementProvider` = immer inaktiv). Regeln: Clients dürfen dort nie schreiben.

## Auf dem Mac prüfen (stumm testen)

1. `cd App && xcodegen generate`, Xcode öffnen; Pakete (Firebase ≥ 12, GoogleSignIn ≥ 8) auflösen lassen.
2. **Ohne plist:** `App/Firebase/dev` kurz umbenennen → Build läuft (Warnung „fehlt – App ohne Konto“), App startet,
   Einstellungen → Konto & Synchronisation zeigt „kein Server eingerichtet“. Zurückbenennen.
3. **Ohne Anmeldung kein Netz:** App frisch installieren, normal benutzen (Fahrt mit Simulator, Einstellungen ändern),
   dabei im Xcode-Protokoll bzw. mit dem Network-Instrument prüfen: keine Verbindung zu `firestore.googleapis.com`,
   `identitytoolkit.googleapis.com`, `firebaseappcheck.googleapis.com`.
4. Regeln (nach Prüfung) nach `rowcoach-dev` deployen, App-Check-Debug-Token aus dem Protokoll in der Konsole eintragen.
5. Registrieren mit E-Mail → Bestätigungsmail → „Ich habe bestätigt“ → Synchronisation einschalten (Dialog) →
   Fahrten erscheinen in der Konsole unter `users/{uid}/rides`. „Passwort vergessen?“ testen.
6. Zweites Gerät (iPad + iPhone oder Simulator): anmelden, einschalten → Fahrten, Profil/Figur, Plan, Wochenziel kommen
   an; Belastung auf einem Gerät ändern → anderes Gerät; Fahrt löschen → verschwindet auf beiden.
7. Forschung an/aus → `consent/research` + `consentLog` in der Konsole; Export teilen (JSON ansehen); „Alle
   Server-Daten löschen“ → Konsole leer, Gerät unverändert; „Konto löschen“.
8. Google erst nach neuen plists (mit `CLIENT_ID`/`REVERSED_CLIENT_ID`).
