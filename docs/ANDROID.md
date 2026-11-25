# Android: Stand und Weg (25.11.2026)

Ziel: dieselbe App für iPad/iPhone und Android, möglichst in Swift.

## Was heute geht
- **RowCoachKit** (alle Logik: PM5-Protokoll, Fahrt, Programme, Verkehr, Auswertung, Statistik, Tagesvorschlag)
  baut und testet auf der Spark unter Linux (Swift 6.4.3, 208 Tests grün) und baut für **Android arm64**
  (Swift SDK für Android 6.4.3, NDK r28c), inkl. Test-Executable.
- Prüfen: `tools/kit_check.sh` (Linux-Tests + Android-Bau).
- Übersetzbare Texte im Kit: auf Apple `String(localized:)` wie bisher; auf Linux/Android ersetzt
  `PortableLocalization` es mit denselben Catalog-Schlüsseln. Der Android-Host setzt `PortableLocalization.lookup`
  (Übersetzungen aus `Localizable.xcstrings`) und `AppLocalization.override` (Sprache).

- Rennen gegeneinander (Grundlage für Turniere): Modelle, Uhr, Transport und Koordinator liegen ebenfalls im Kit
  und laufen damit auf Android; Aufbau und Firebase-Plan in docs/MULTIPLAYER.md.

## Regeln ab jetzt
1. Neue Logik gehört in RowCoachKit und nutzt nur Foundation (kein SwiftUI, RealityKit, HealthKit, CoreBluetooth,
   `os.Logger`, `Bundle.main`). `tools/kit_check.sh` muss grün bleiben.
2. Apple-Frameworks nur in `App/RowCoach` (der iOS-Hülle).

## Weg zur Android-App (noch nicht begonnen, Entscheidung Falk)
| Baustein | iPad heute | Android |
|---|---|---|
| Oberfläche | SwiftUI | Skip Fuse (SwiftUI-Code → Jetpack Compose) oder eigene Compose-Oberfläche |
| 3D-Szene | RealityKit, USDZ | Filament/SceneView, GLB (zusätzlicher Export im Streckenbauer) |
| Geräte | CoreBluetooth | Android BLE (über swift-java) |
| Gesundheit | HealthKit | Health Connect (Inhalt schon im Kit: `HealthWorkoutExport`, siehe docs/HEALTH.md) |
| Speicher | SwiftData | SQLite/Room |
| Ansagen | AVSpeechSynthesizer | TextToSpeech |

Nächster sinnvoller Schritt: die Trainingssteuerung (`SessionController`) hinter schmale Schnittstellen für Geräte,
Health, Speicher und Ansagen legen und in RowCoachKit holen, damit beide Hüllen sie teilen.

## Einrichtung auf der Spark (einmalig, erledigt)
- Swift: swiftly (`~/.local/share/swiftly`), Toolchain 6.4.3.
- Android-SDK: `swift sdk install swift-6.4.3-RELEASE_android.artifactbundle.tar.gz` (download.swift.org).
- NDK r28c nach `~/Android/android-ndk-r28c`, dann `ANDROID_NDK_HOME=… setup-android-sdk.sh` aus dem SDK.
- Auf arm64-Linux mit `--build-system native` bauen (das neue Build-System ruft den x86-Linker des NDK auf).
