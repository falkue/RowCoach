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
| Energie | `activeEnergyBurned` | `ActiveCaloriesBurnedRecord` je Abschnitt |
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
