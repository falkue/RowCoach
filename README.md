RowCoach is an open-source iPad/iPhone app for the Concept2 RowErg (PM5): you row through 3D landscapes built from official open geodata, with heart rate from a Bluetooth chest strap (Polar, Garmin, Wahoo and others), guided workouts and Apple Health integration.

- Status: version 1.0 for the Apple App Store in preparation (free „Basic“ edition: bundled courses, no server, no
  data collected; see [docs/APPSTORE.md](docs/APPSTORE.md)). The development edition (0.3) adds account sync, online
  races and course downloads. iPadOS/iOS 26. An Android version is being prepared.
- License: [Apache-2.0](LICENSE) for the code. Geodata keeps its own open licences, see [NOTICE](NOTICE).

## What it does
- **Rowing on real water.** Each course is a 3D scene computed from official terrain models, aerial imagery, 3D buildings
  and tree heights. Examples: Lake Zurich (Utoquai, Mythenquai), Rhine in Basel and Stein am Rhein, Lucerne, Berlin
  (Grünau regatta course, Spree, Wannsee) and Hamburg (Outer Alster). The boat moves with your actual speed from the PM5.
- **Traffic on the water.** Other rowers and boats (lake steamers, sailboats, pedal boats) share the course with you.
- **Training.** You can row freely with a pace line or follow programmes: intervals, steady state, 2000 m test.
  Spoken cues announce phase changes. A programme that is longer than the course continues in laps.
- **Data.** Each ride stores splits, heart-rate zones, effort (1–10), history and statistics, and saves the workout to
  Apple Health. Simulator and demo rides are never saved to Health.
- **German and English** throughout.

## Architecture
```
App/
  RowCoach/          iOS/iPadOS shell (SwiftUI, RealityKit, CoreBluetooth, HealthKit, SwiftData)
  RowCoachKit/       platform-independent logic in Swift (Foundation only), builds on iOS, macOS, Linux and Android:
                     PM5 protocol, ride session, workout plans, traffic, evaluation, statistics, races,
                     course catalogue and downloads, health export
  Courses/           course packages bundled with the app (built by tools/coursebuilder)
tools/coursebuilder/ Python pipeline: open geodata → 3D course packages (USDZ), mini map, traffic lanes, previews
tools/traffic_sim/   Python twin of the traffic model for tuning
courses/             built course packages (scenes are not in git, only metadata and previews)
docs/                design notes and plans (German)
```

Plans that are already reflected in the architecture:
- **Android** (Swift SDK for Android). RowCoachKit compiles for Android arm64 today. See [docs/ANDROID.md](docs/ANDROID.md).
- **Health Connect** on Android, using the same workout export as Apple Health. See [docs/HEALTH.md](docs/HEALTH.md).
- **Races and tournaments** against other rowers in near real time, through a server that is planned on Firebase.
  See [docs/MULTIPLAYER.md](docs/MULTIPLAYER.md).
- **Course downloads** from a server: only two default courses ship with the app, and the others can be downloaded.
  See [docs/STRECKEN-SERVER.md](docs/STRECKEN-SERVER.md).

## Building
- **iOS app**:
  - You need a Mac with Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
  - Run `cd App && ROWCOACH_TEAM_ID=<your team> xcodegen generate`, then open `RowCoach.xcodeproj`.
  - Details are in [BUILD.md](BUILD.md).
- **Shared logic on Linux/Android**:
  - `tools/kit_check.sh` runs the tests on Linux (Swift 6.4) and builds for Android arm64.
  - The Android build needs the Swift SDK for Android and Android NDK r27 or newer.
- **Courses**:
  - The pipeline in `tools/coursebuilder` downloads open geodata and builds the 3D scene.
  - `bake.py` uses an NVIDIA GPU (warp) to precompute lighting.
  - Each script documents itself in its docstring. The order is in [BUILD.md](BUILD.md).

## Data sources
The courses are built from open government geodata, among others swisstopo (Switzerland), Geoportal Berlin, LGB
Brandenburg, LGV Hamburg, Copernicus DEM, Kartverket, Environment Agency, IGN, GSI/PLATEAU and OpenStreetMap
contributors. The attribution for each course is in its `course.json` (`attribution`) and in the app. See
[NOTICE](NOTICE).

## Hardware
- Concept2 RowErg with a PM5 monitor (Concept2 PM5 Bluetooth protocol; tested)
- Beta, untested with real hardware: other rowing machines with Bluetooth FTMS (Fitness Machine Service, Rower
  Data), e.g. WaterRower with the S4 Bluetooth ComModule, First Degree Fitness Bluetooth consoles, Merach, some
  Domyos models – roughly anything sold as "Kinomap compatible". Rowers that only work with their maker's app
  (Hydrow, Ergatta, Aviron, Echelon, iFit/NordicTrack) are not supported. Details:
  [docs/geraete/RECHERCHE.md](docs/geraete/RECHERCHE.md), [docs/geraete/UMSETZUNG.md](docs/geraete/UMSETZUNG.md).
- Optional: any Bluetooth heart-rate strap or watch using the standard Heart Rate profile, e.g. Polar H9/H10
  (tested), Garmin HRM-Dual/HRM-Pro/HRM 600 or a Garmin watch with heart-rate broadcast, Wahoo TICKR, Suunto,
  Coospo. ANT+-only devices are not supported (iPad has no ANT+).
- iPad or iPhone with iPadOS/iOS 26. Older iPads such as the A12X use the "standard" scene quality.

## Contributing
Issues and pull requests are welcome. The code comments and design notes are mostly in German. User-facing texts
live in `App/RowCoach/Resources/Localizable.xcstrings` (German source, English translation). After changing texts,
regenerate the catalogue with `App/l10n/build_catalog.py`.

---
**Kurz auf Deutsch:** RowCoach ist eine offene App für das Concept2-Rudergerät. Man rudert durch 3D-Landschaften aus
amtlichen offenen Geodaten, mit Puls, Trainingsprogrammen und Apple Health. Die Dokumentation in `docs/` ist deutsch.
