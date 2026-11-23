# RowCoach bauen

## App (Mac, Session „Private QNAP“)
Voraussetzungen: Xcode 26, Apple-Entwicklerkonto, `brew install xcodegen` (einmalig).

```bash
cd ~/Projects/Software/RowCoach/App
ROWCOACH_TEAM_ID=<Team-ID aus developer.apple.com> xcodegen generate   # erzeugt RowCoach.xcodeproj
open RowCoach.xcodeproj
```
- Gerät: Falks iPad Pro (A12X, iPadOS 26). Schema RowCoach, Run.
- Capability HealthKit ist über `RowCoach/RowCoach.entitlements` gesetzt. Xcode legt das Provisioning-Profil automatisch an.
- Tests der plattformunabhängigen Logik: `cd App/RowCoachKit && swift test` (macOS) oder in Xcode Product → Test.
- `RowCoach.xcodeproj` nie von Hand ändern, sondern `project.yml` anpassen und neu erzeugen.

### Etappe 0 testen
1. PM5 einschalten, im Menü „Connect“ wählen. Polar H10/H9 anlegen und die Elektroden befeuchten.
2. App → Geräte → Suchen → PM5 und Gurt antippen. Beide merkt sich die App für die nächsten Starts.
3. Einstellungen → „Apple Health verbinden“ → alle Freigaben erteilen.
4. Live → „Aufzeichnung starten“, ein paar Minuten rudern, dann „Beenden und in Health speichern“.
5. In Health prüfen: Training „Rudern“ (indoor) mit Distanz, Energie und Pulskurve, ohne doppelte Pulswerte.

## Kartenpakete (Spark)
```bash
cd ~/Projects/Software/RowCoach/tools/coursebuilder
.venv/bin/python fetch.py   areas/zuerichsee-unteres-becken.json   # swisstopo laden (nur Neues)
.venv/bin/python prepare.py areas/zuerichsee-unteres-becken.json   # Mosaike, Seefläche
.venv/bin/python routes.py  areas/zuerichsee-unteres-becken.json   # Strecken + route_preview.png
.venv/bin/python buildings.py areas/zuerichsee-unteres-becken.json # CityGML → Dreiecke (~1,5 min)
.venv/bin/python export.py  areas/zuerichsee-unteres-becken.json   # USDZ standard + hoch, course.json
./run_preview.sh zuerichsee-unteres-becken standard zuerichsee-utoquai zuerichsee-mythenquai  # Vorschau (CPU)
```
Die Rohdaten liegen unter `data/raw/…` (nicht in Git) und sind in Fundus als `dataset:832` registriert.
GPU-Jobs (vorgerechnetes Licht, sobald gebaut) laufen über `gpu run -p 0 -o "SPARK SW RowCoach" …`.
