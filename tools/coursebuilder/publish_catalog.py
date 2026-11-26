"""Streckenkatalog für den Download-Server erzeugen: courses/ → dist/courses/.

Ergebnis (statische Dateien, so wie sie später auf Firebase Hosting/Storage liegen):
  dist/courses/catalog.json                       Katalog aller Strecken (RowCoachKit CourseCatalog)
  dist/courses/packages/<id>/manifest-<stufe>.json  Dateiliste je Strecke und Qualitätsstufe (Pfad, Grösse, SHA-256)
  dist/courses/files/<pfad>                       die Dateien selbst (Hardlinks auf courses/, kein Platzbedarf)
  dist/courses/previews/<id>.jpg                  kleines Vorschaubild für die ausgegraute Kachel

Pfade in den Manifesten sind relativ zu `Courses/` (wie im App-Bundle); geteilte Szenen erscheinen in mehreren
Manifesten, die App lädt sie nur einmal. Standardstrecken (courses/bundled.json) tragen "bundled": true.
Version je Strecke: Zeitstempel der neuesten Paketdatei (JJJJMMTTHH, UTC) – jede neu gebaute Fassung zählt höher.
Prüfsummen werden zwischengespeichert (dist/courses/.sha-cache.json, Schlüssel Pfad+Grösse+Zeitstempel).

Aufruf (aus tools/coursebuilder, kein venv nötig):
  python3 publish_catalog.py            # alle Strecken
  python3 publish_catalog.py --no-files # nur Katalog und Manifeste (ohne files/)
Danach `python3 install_courses.py` (liefert catalog.json und Vorschaubilder mit der App aus).
"""
import argparse
import hashlib
import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

from install_courses import REPO, SRC, bundled_ids, course_files

DIST = REPO / "dist" / "courses"
MIN_APP_VERSION = "0.2.0"  # erste App-Version, die Pakete laden kann


def sha256(path: Path, cache: dict) -> str:
    st = path.stat()
    key = f"{path.relative_to(REPO)}|{st.st_size}|{int(st.st_mtime)}"
    if key not in cache:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        cache[key] = h.hexdigest()
    return cache[key]


def shape_of(course: dict) -> str:
    if course.get("turns", 1) > 0:
        return "out_and_back"
    return "loop" if course.get("loop") else "one_way"


def place(src: Path, dst: Path) -> None:
    """Datei nach dist/ legen: Hardlink (gleiches Dateisystem), sonst Kopie; unverändertes bleibt"""
    if dst.exists():
        if dst.stat().st_ino == src.stat().st_ino or (dst.stat().st_size == src.stat().st_size
                                                      and dst.stat().st_mtime >= src.stat().st_mtime):
            return
        dst.unlink()
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.link(src, dst)
    except OSError:
        shutil.copy2(src, dst)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-files", action="store_true", help="files/ nicht anlegen")
    args = ap.parse_args()
    # Strecken, die (noch) nicht öffentlich auf den Server dürfen (courses/unpublished.json, z. B. Japan bis zur
    # GSI-Genehmigung, docs/LIZENZEN-GEODATEN.md); ihre alten Dateien werden aus dist/ entfernt
    unpub_file = REPO / "courses" / "unpublished.json"
    unpublished = set(json.loads(unpub_file.read_text()).get("unpublished", [])) if unpub_file.exists() else set()
    for rid in sorted(unpublished):
        for d in (DIST / "packages" / rid,):
            if d.exists():
                shutil.rmtree(d)
        (DIST / "previews" / f"{rid}.jpg").unlink(missing_ok=True)

    cache_file = DIST / ".sha-cache.json"
    cache = json.loads(cache_file.read_text()) if cache_file.exists() else {}
    bundled = set(bundled_ids())
    entries = []
    for cj in sorted(SRC.glob("*/course.json")):
        rid = cj.parent.name
        if rid in unpublished:
            print(f"{rid}: nicht veröffentlicht (courses/unpublished.json)")
            continue
        course = json.loads(cj.read_text())
        by_quality = {}
        newest = 0.0
        for q in course["qualities"]:
            files = course_files(rid, course, [q])
            manifest = {"course_id": rid, "version": 0, "files": []}
            for src, rel in files:
                manifest["files"].append({"path": rel, "size": src.stat().st_size, "sha256": sha256(src, cache)})
                newest = max(newest, src.stat().st_mtime)
                if not args.no_files:
                    place(src, DIST / "files" / rel)
            by_quality[q] = manifest
        version = int(datetime.fromtimestamp(newest, timezone.utc).strftime("%Y%m%d%H"))
        for q, m in by_quality.items():
            m["version"] = version
            out = DIST / "packages" / rid / f"manifest-{q}.json"
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(json.dumps(m, indent=1))
        preview = None
        for name in ("overview.jpg", "minimap.jpg", "preview-standard-1.jpg"):
            if (cj.parent / name).exists():
                (DIST / "previews").mkdir(parents=True, exist_ok=True)
                place(cj.parent / name, DIST / "previews" / f"{rid}.jpg")
                preview = f"previews/{rid}.jpg"
                break
        sizes = {q: sum(f["size"] for f in m["files"]) for q, m in by_quality.items()}
        entries.append({
            "id": rid, "version": version, "title": course["title"], "region": course["region"],
            "country": course.get("country"), "city": course.get("city"), "shape": shape_of(course),
            "length_m": course["total_m"], "total_bytes": sizes.get("standard", max(sizes.values(), default=0)),
            "bytes_by_quality": sizes, "manifest": f"packages/{rid}/manifest-{{quality}}.json",
            "preview": preview, "bundled": rid in bundled, "min_app_version": MIN_APP_VERSION,
        })
        print(f"{rid}: Version {version}, " + ", ".join(f"{q} {b / 1e6:.0f} MB" for q, b in sizes.items())
              + (" (Standardstrecke)" if rid in bundled else ""))
    missing = bundled - {e["id"] for e in entries}
    if missing:
        print(f"Standardstrecken ohne Paket: {', '.join(sorted(missing))}", file=sys.stderr)
    catalog = {"format_version": 1,
               "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
               "courses": entries}
    DIST.mkdir(parents=True, exist_ok=True)
    (DIST / "catalog.json").write_text(json.dumps(catalog, indent=1, ensure_ascii=False))
    cache_file.write_text(json.dumps(cache))
    print(f"{len(entries)} Strecken im Katalog → {DIST.relative_to(REPO)}/catalog.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
