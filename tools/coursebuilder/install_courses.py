"""Kartenpakete in die App übernehmen: courses/ → App/Courses/.

Kopiert je Strecke course.json und die Vorschaubilder (preview-*.jpg) und je Szene die USDZ-Dateien, die
course.json verlangt (Feld "scene" mit Platzhalter {quality}, z. B. zuerichsee-unteres-becken/scene-{quality}.usdz).
Die Ordnerstruktur unter App/Courses entspricht courses/, deshalb gilt Course.scenePath(quality:) relativ zu
Courses/ im App-Bundle. Ausgangsordner der Szenen (scene-<stufe>/ mit scene.usdc und Texturen) werden nicht kopiert.

Steht in course.json das optionale Feld "bundle_qualities" (von export.py aus "app_qualities" der Gebietsdatei),
kommen von dieser Strecke nur diese Stufen ins Bundle (z. B. nur standard für neue Gebiete, damit das Bundle klein
bleibt); --all-qualities übergeht das. Die App nimmt automatisch die vorhandene Stufe (CourseLibrary.sceneURL).

Licht-Varianten (optionales Feld "light_variants" in course.json: Texturordner wie
<gebiet>/light-ambient-{quality}/ von export.py --light ambient) kommen in denselben Stufen mit wie die Hauptszene,
soweit es sie gibt (alle *.jpg des Ordners).

Kopiert wird nur, was sich geändert hat (Grösse oder Zeitstempel); Dateien in App/Courses, die zu keinem
Paket mehr gehören, werden entfernt. Die USDZ-Dateien sind in .gitignore ausgeschlossen.

Aufruf (aus tools/coursebuilder, kein venv nötig):
  python3 install_courses.py                     # alle Strecken unter courses/, alle Stufen
  python3 install_courses.py zuerichsee-utoquai  # nur bestimmte Strecken
  python3 install_courses.py --quality standard  # nur eine Stufe (kleineres App-Bundle)
  python3 install_courses.py --all-qualities     # auch Stufen, die bundle_qualities ausschliesst
  python3 install_courses.py --bundled-only      # Auslieferung: nur Standardstrecken (courses/bundled.json)
  python3 install_courses.py --dry-run
"""
import argparse
import json
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "courses"
DST = REPO / "App" / "Courses"


def needs_copy(src: Path, dst: Path) -> bool:
    if not dst.exists():
        return True
    s, d = src.stat(), dst.stat()
    return s.st_size != d.st_size or int(s.st_mtime) > int(d.st_mtime)


def course_files(rid: str, course: dict, qualities: list[str]) -> list[tuple[Path, str]]:
    """Dateien eines Kartenpakets als (Quelle, Pfad relativ zu Courses/); auch von publish_catalog.py genutzt."""
    cdir = SRC / rid
    out = [(cdir / "course.json", f"{rid}/course.json")]
    for jpg in sorted(cdir.glob("preview-*.jpg")) + sorted(cdir.glob("minimap.jpg")) + sorted(cdir.glob("overview.jpg")):
        out.append((jpg, f"{rid}/{jpg.name}"))
    for q in qualities:
        rel = course["scene"].replace("{quality}", q)
        src = SRC / rel
        if not src.exists():
            print(f"Fehlt: courses/{rel} (für {rid}, Stufe {q}) – export.py laufen lassen", file=sys.stderr)
            continue
        out.append((src, rel))
        for vid, v in (course.get("light_variants") or {}).items():
            if q not in v.get("qualities", []):
                continue
            vrel = v["textures"].replace("{quality}", q)
            if (SRC / vrel).is_dir():
                for jpg in sorted((SRC / vrel).glob("*.jpg")):
                    out.append((jpg, f"{vrel}/{jpg.name}"))
            else:
                print(f"Fehlt: courses/{vrel} (Licht-Variante {vid}) – export.py --light {vid}", file=sys.stderr)
    return out


def bundled_ids() -> list[str]:
    """Standardstrecken aus courses/bundled.json"""
    f = SRC / "bundled.json"
    return json.loads(f.read_text())["bundled"] if f.exists() else []


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("routes", nargs="*", help="Strecken-IDs (Ordner unter courses/ mit course.json); leer = alle")
    ap.add_argument("--quality", action="append", help="nur diese Stufe(n), z. B. standard; mehrfach möglich")
    ap.add_argument("--all-qualities", action="store_true",
                    help="bundle_qualities aus course.json nicht beachten (alle Stufen kopieren)")
    ap.add_argument("--bundled-only", action="store_true",
                    help="nur die Standardstrecken aus courses/bundled.json (Auslieferung; alle anderen kommen vom Server)")
    ap.add_argument("--dry-run", action="store_true", help="nur anzeigen, nichts kopieren oder löschen")
    args = ap.parse_args()

    all_routes = sorted(p.parent.name for p in SRC.glob("*/course.json"))
    routes = args.routes or (bundled_ids() if args.bundled_only else all_routes)
    missing = [r for r in routes if r not in all_routes]
    if missing:
        print(f"Unbekannte Strecken: {', '.join(missing)} (vorhanden: {', '.join(all_routes)})", file=sys.stderr)
        return 1

    plan: list[tuple[Path, Path]] = []      # (Quelle, Ziel)
    for rid in routes:
        cdir = SRC / rid
        course = json.loads((cdir / "course.json").read_text())
        if course.get("id") != rid:
            print(f"Warnung: {rid}/course.json hat id={course.get('id')!r}", file=sys.stderr)
        qualities = [q for q in course["qualities"] if not args.quality or q in args.quality]
        if course.get("bundle_qualities") and not args.all_qualities:
            qualities = [q for q in qualities if q in course["bundle_qualities"]]
        plan += [(src, DST / rel) for src, rel in course_files(rid, course, qualities)]

    # Katalog aller Strecken (von publish_catalog.py) mitliefern: zeigt nicht geladene Strecken ausgegraut
    catalog_dir = REPO / "dist" / "courses"
    if (catalog_dir / "catalog.json").exists():
        plan.append((catalog_dir / "catalog.json", DST / "catalog.json"))
        for jpg in sorted((catalog_dir / "previews").glob("*.jpg")):
            plan.append((jpg, DST / "_previews" / jpg.name))
    else:
        print("Hinweis: dist/courses/catalog.json fehlt (publish_catalog.py) – ohne Katalog zeigt die App nur "
              "mitgelieferte Strecken", file=sys.stderr)

    # Doppelte Ziele (mehrere Strecken teilen eine Szene) nur einmal kopieren
    unique = {dst: src for src, dst in plan}
    copied = skipped = 0
    total_bytes = 0
    for dst, src in sorted(unique.items()):
        total_bytes += src.stat().st_size
        if not needs_copy(src, dst):
            skipped += 1
            continue
        print(f"kopiere {src.relative_to(REPO)} → {dst.relative_to(REPO)}")
        if not args.dry_run:
            dst.parent.mkdir(parents=True, exist_ok=True)
            tmp = dst.with_name(dst.name + ".part")
            shutil.copy2(src, tmp)
            tmp.replace(dst)
        copied += 1

    # Aufräumen: nur bei vollständigem Lauf (alle Strecken, alle Stufen), sonst würde Gewolltes gelöscht
    removed = 0
    if not args.routes and not args.quality and not args.all_qualities and DST.exists():
        # auch nach --bundled-only: entfernt alle nicht mitgelieferten Strecken aus dem Bundle
        keep = set(unique)
        for f in sorted(DST.rglob("*")):
            if f.is_file() and f not in keep and f.name != ".gitkeep":
                print(f"entferne {f.relative_to(REPO)}")
                if not args.dry_run:
                    f.unlink()
                removed += 1
        if not args.dry_run:
            for d in sorted((p for p in DST.rglob("*") if p.is_dir()), key=lambda p: len(p.parts), reverse=True):
                if not any(d.iterdir()):
                    d.rmdir()

    print(f"{len(routes)} Strecken, {len(unique)} Dateien ({total_bytes / 1e6:.0f} MB): "
          f"{copied} kopiert, {skipped} unverändert, {removed} entfernt{' (Probelauf)' if args.dry_run else ''}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
