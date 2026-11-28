# Gesundheitsdaten: Apple Health und Health Connect (Android)

RowCoach schreibt jedes echte Training (nicht Simulator oder Demo) in den Gesundheitsspeicher des Systems, wenn
der Nutzer das einschaltet. Auf iOS ist das Apple Health (`App/RowCoach/Health/HealthService.swift`), auf Android
**Health Connect** (`androidx.health.connect:connect-client`, ab Android 14 im System, davor als App).

## Gemeinsamer Teil (RowCoachKit, portabel)
- `HealthExportRule.shouldExport`: nie Simulator- oder Demofahrten.
- `HealthWorkoutExport(record:title:)`: plattformneutraler Inhalt eines Trainings:
  - Zeitraum, Titel und Bemerkung
  - Gesamtdistanz und Energie
  - Abschnitte von 60 s mit Distanz und Energie
  - Puls, Leistung und Tempo alle 5 s
  - Anstrengung (eigene und geschätzte)
  - stabile Kennung `rowcoach-<UUID>` mit Version
- `HealthStoreAdapter`: Schnittstelle der Hülle: verfügbar?, Schreibfreigabe anfragen, Training schreiben.

## Zuordnung
| Inhalt | Apple Health | Health Connect |
|---|---|---|
| Training | `HKWorkout` Rudern, indoor | `ExerciseSessionRecord`, `EXERCISE_TYPE_ROWING_MACHINE` |
| Distanz | `distanceRowing` | `DistanceRecord` je Abschnitt |
| Energie | `activeEnergyBurned` (aktive Energie mit Körpergewicht, ohne Ruheumsatz; docs/KALORIEN.md) | `ActiveCaloriesBurnedRecord` je Abschnitt |
| Puls | `heartRate` | `HeartRateRecord` (Samples) |
| Leistung | – | `PowerRecord` (Samples, Watt) |
| Tempo | – | `SpeedRecord` (Samples, m/s) |
| Anstrengung | `workoutEffortScore`, `estimatedWorkoutEffortScore` | keine Entsprechung; bleibt in RowCoach |
| Kennung | `HKMetadataKeyExternalUUID` | `Metadata.clientRecordId` und `clientRecordVersion` (kein Doppeleintrag beim Nachtragen) |

## Android-Hülle (zu bauen, wenn die Android-App beginnt)
1. Abhängigkeit `androidx.health.connect:connect-client` und in `AndroidManifest.xml` die Berechtigungen
   `android.permission.health.WRITE_EXERCISE`, `WRITE_DISTANCE`, `WRITE_ACTIVE_CALORIES_BURNED`,
   `WRITE_HEART_RATE`, `WRITE_POWER` und `WRITE_SPEED`. Dazu die Activity für die Begründung der Berechtigungen
   (`ACTION_SHOW_PERMISSIONS_RATIONALE`) mit einem Link zur Datenschutzerklärung.
2. Einstellung „In Health Connect speichern“ (aus, bis der Nutzer sie einschaltet). Beim Einschalten zuerst
   `HealthConnectClient.getSdkStatus` prüfen, dann über `PermissionController.createRequestPermissionResultContract()`
   die Freigabe anfragen.
3. Ein Kotlin-Adapter, der `HealthStoreAdapter` erfüllt (über swift-java bzw. Skip): `HealthWorkoutExport` 1:1 in
   die Records übersetzen und mit `insertRecords` in einem Aufruf schreiben. Dieselbe `clientRecordId` ersetzt den
   alten Eintrag.
4. Wiederherstellung und Nachtragen wie auf iOS: Nach einer unterbrochenen Fahrt wird beim nächsten Start
   nachgetragen.

Auf iOS bleibt `HealthService` vorerst wie er ist. Die Übertragung auf `HealthWorkoutExport` folgt, sobald beide
Hüllen ihn nutzen, damit beide Plattformen dieselben Werte schreiben.

## Körpergewicht aus Apple Health (nur lesend, 28.11.2026)
Code: `App/RowCoach/Health/BodyWeightService.swift`, Regel im Kit `Profile/BodyWeightRule.swift` (Tests
`RowingEnergyTests.swift` → `BodyWeightRuleTests`).

- **Lesen:** `HKQuantityType(.bodyMass)` steht in den Lese-Typen von `HealthService`, ohne Schreibrecht. Es zählt die
  neueste Messung nach Enddatum (eine Abfrage mit limit 1). Nur Werte von 30 bis 250 kg gelten, auf 0,1 kg gerundet.
  Datum und Quelle werden mitgelesen.
- **Nur mit Verbindung:** Abfragen laufen nur, wenn Apple Health verbunden ist (`status == .authorized`) und die
  Lese-Freigabe fürs Gewicht schon angefragt wurde (`statusForAuthorizationRequest`). Wer Health vor diesem Update
  verbunden hat, sieht im Profil „Gewicht aus Apple Health lesen“ und bekommt dann den Dialog. HealthKit verrät
  nicht, ob Lesen abgelehnt wurde: Ein leeres Ergebnis heisst „kein Wert“, und es bleibt beim Drehrad. Kein
  Netzverkehr.
- **Wann:** beim App-Start, beim Öffnen des Profils (Einstellungen, „Profil prüfen“, erster Start) und direkt nach
  dem Verbinden im Einstieg.
- **Schalter „Gewicht aus Apple Health übernehmen“** (je Gerät, `profile.weightFromHealth`). Er ist nur sichtbar,
  wenn Health verbunden ist, und steht standardmässig auf **an**. Begründung: Wer im Health-Dialog das Lesen des
  Gewichts erlaubt, hat damit schon zugestimmt. Eine Waage in Health ist aktueller als ein einmal eingestellter
  Wert. Ein zusätzliches Fenster käme zu den anderen Start-Fenstern hinzu (Profil prüfen, Neue Schwelle). Die
  Herkunft steht sichtbar neben dem Wert, und der Schalter lässt sich jederzeit ausschalten.
  - An und Wert vorhanden: Anzeige „78,4 kg · aus Apple Health, 12.11.“, kein Drehrad.
  - An, aber kein Wert in Health: Drehrad wie bisher, mit Hinweis.
  - Aus: Drehrad wie bisher. Ist eine Messung neuer als der Wert von Hand und weicht sie um mindestens 0,5 kg ab,
    erscheint „Apple Health: 78,4 kg – übernehmen?“ mit „Übernehmen“ und ×.
- **Synchronisation (nur Dev):** Der übernommene Wert landet in `profile.weightKg` und wird wie eine Eingabe von Hand
  synchronisiert. Der Sync-Katalog bleibt unverändert. Gegen das Hin und Her zwischen Geräten merkt sich jedes Gerät
  lokal, seit wann der Profilwert gilt (`profile.weightAsOf`, dazu `profile.weightSeen`):
  - Übernahme aus Health: Stand = Messdatum. Eingabe von Hand: Stand = jetzt.
  - Ändert sich der Wert von aussen (Synchronisation), gilt er ab dem Moment, in dem das Gerät ihn sieht.
  - Ein Gerät übernimmt eine Health-Messung nur, wenn sie **neuer** ist als dieser Stand. Ein Gerät mit einer älteren
    Messung überschreibt einen synchronisierten Wert also nicht. Weil jede Übernahme eine neuere Messung braucht,
    endet jedes Hin und Her.
  - Grenze: Sieht ein Gerät einen synchronisierten älteren Wert, bevor es selbst eine neuere Messung hat, gilt bis
    zur nächsten Wägung der synchronisierte Wert. Da Apple Health die Messungen über iCloud auf alle Geräte bringt,
    gleicht sich das in der Praxis an.
- **Wofür das Gewicht genutzt wird:** nur für die aktive Energie der Fahrten (docs/KALORIEN.md: Zusammenfassung und
  `activeEnergyBurned`). Bisher wurde es nirgends genutzt. W/kg, Ranglisten und Gewichtsklassen gibt es nicht.
- Android: siehe docs/ANDROID.md (Health Connect `WeightRecord`).

## Route und Indoor-Markierung (Entscheidung Falk, 28.11.2026)
Fahrten werden weiter als **Indoor-Rudern** gespeichert (`activityType .rowing`, `locationType .indoor`,
`HKMetadataKeyIndoorWorkout = true`). Die Strecke wird trotzdem als `HKWorkoutRoute` angehängt (geprüft: Fahrt vom
28.11., 1802 Punkte). Die Fitness-App zeigt für Indoor-Workouts offenbar keine Karte; die Strecke ist in RowCoach zu
sehen. Eine Markierung als Outdoor-Rudern (Karte in Fitness) wurde bewusst verworfen: falsche Einordnung des Trainings.
