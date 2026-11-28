# Strecken vom Server (Stand 26.11.2026, Staging auf Firebase Hosting in Betrieb)

Ziel (Falk, 26.11.): Nicht alle Strecken mit der App ausliefern. Standard sind **Rhein Basel** (`rhein-basel`) und
**Spree Berlin-Mitte** (`berlin-spree-mitte`), festgelegt in `courses/bundled.json`. Alle anderen Strecken erscheinen in
der Auswahl ausgegraut. Ein Tippen lädt sie, danach sind sie auch offline fahrbar. Ein Turnier verlangt seine Strecke:
Bei der Anmeldung fordert die App zum Laden auf, ohne Strecke ist keine Teilnahme möglich.

## Aufbau
- **Server**: nur statische Dateien (später Firebase Hosting oder Cloud Storage, auch signierte URLs möglich):
  - `catalog.json`: Katalog aller Strecken (Titel, Region, Land, Stadt, Form, Länge, Grösse je Stufe, Version,
    `bundled`, `min_app_version`, Vorschaubild).
  - `packages/<id>/manifest-<stufe>.json`: Dateien der Strecke relativ zu `Courses/` mit Grösse und SHA-256.
  - `files/<pfad>`: die Dateien. Geteilte Szenen (z. B. Utoquai und Mythenquai) liegen nur einmal.
  - Erzeugt von `tools/coursebuilder/publish_catalog.py` nach `dist/courses/` (Hardlinks, kein Platzbedarf).
- **Kit** (RowCoachKit, portabel für Android):
  - `CourseCatalog.swift`: Katalog, Manifest, `CourseAvailability` (mitgeliefert / geladen / Update / nicht geladen /
    App zu alt), `CourseRequirement.check` (Start und Turnier-Anmeldung, optional Mindestfassung), Download-Planer.
  - `CourseInstaller.swift`: `CoursePackageSource` (HTTP, „kein Server“), `CourseInstaller` (lädt nur fehlende Dateien,
    prüft Grösse und SHA-256, schreibt `installed.json` erst am Schluss, entfernt nur nicht geteilte Dateien).
- **App**:
  - `CourseLibrary` liest Bundle und `Application Support/Courses` und kennt den Katalog (`catalogOnly`,
    `availability`, `readiness`).
  - `CourseDownloads` lädt Katalog und Strecken (Server-Adresse in den Entwicklereinstellungen,
    `courseServerURL`).
  - Strecken-Tab: ausgegraute Kacheln mit „Laden · 62 MB“, Fortschritt, Fehlertext.
- **Auslieferung**:
  - `install_courses.py --bundled-only` packt nur die Standardstrecken und den Katalog ins Bundle.
  - Solange es keinen Server gibt, liefert der Entwicklungs-Build weiter alle Strecken aus (`install_courses.py` ohne
    Option).

## Firebase später
- Hosting: `dist/courses/` deployen (`firebase deploy --only hosting`), Cache-Header für `files/` lang, für
  `catalog.json` kurz.
- Oder Storage plus Cloud Function für signierte URLs, falls Strecken einmal nur angemeldeten Nutzern gehören sollen.
- Die App braucht dafür nur eine andere `CoursePackageSource`.
- Turniere (docs/MULTIPLAYER.md) führen `courseId` und optional `courseVersion`. Die Anmeldung prüft
  `CourseLibrary.readiness(courseId:requiredVersion:)`.

## Lizenzen
Die Geodaten der Strecken stehen unter offenen Lizenzen mit Namensnennung (course.json `attribution`). Bevor Strecken
öffentlich auf einem Server liegen, die Bedingungen je Quelle prüfen (Weitergabe der abgeleiteten Szenen). Das
entscheidet Falk.

## Staging (seit 26.11.2026)
- Firebase Hosting im Projekt `rowcoach-dev`: https://rowcoach-dev.web.app/catalog.json (öffentlich, kein Konto).
- Testversionen der App (DEBUG) laden standardmässig von dort (`CourseDownloads.defaultServer`); die Store-Version
  zeigt erst auf `rowcoach-prod`, wenn dort Hosting (Blaze-Tarif) eingerichtet ist. Entwicklereinstellungen
  überschreiben die Adresse.
- Veröffentlichen: `cd tools/coursebuilder && python3 publish_catalog.py` → `dist/courses/`, dann
  `firebase deploy --only hosting --project dev`. Cache: Katalog und Manifeste 5 min, Dateien und Vorschauen 1 Tag.
- Nicht veröffentlicht: `courses/unpublished.json` (Japan bis zur GSI-Genehmigung, docs/LIZENZEN-GEODATEN.md).
- Quellenangaben nach der Lizenzprüfung: `tools/coursebuilder/fix_attribution.py`.
- Spark-Tarif: 10 GB Speicher, ca. 360 MB Übertragung pro Tag – genug zum Testen, nicht für Nutzer.
- Zum Testen des Ladens: App mit `install_courses.py --bundled-only` bauen (nur die zwei Standardstrecken im Bundle).

## Speicher im Spark-Tarif (28.11.2026)
Hosting speichert jede Fassung; im kostenlosen Tarif sind 10 GB Gesamtspeicher frei. Mit 50 Strecken in zwei Stufen
ist eine Fassung ~3–4 GB gross. Deshalb `maxVersions = 2` gesetzt (Site-Config über die Hosting-REST-API,
`PATCH sites/rowcoach-dev/config?updateMask=maxVersions`); ältere Fassungen werden automatisch gelöscht. Bei HTTP 429
„Hosting storage quota“ alte Fassungen löschen (`DELETE …/versions/<id>`, nie die aktuelle) oder auf Blaze wechseln.
