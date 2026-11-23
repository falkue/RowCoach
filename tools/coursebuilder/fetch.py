"""Lädt swisstopo-Open-Data (OGD, © swisstopo) für ein Gebiet über die STAC-API.

Pro Kachel wird nur die neueste Ausgabe geladen. Bereits vorhandene Dateien werden übersprungen.
Höflich: eine Verbindung nach der anderen, kurze Pause, eindeutiger User-Agent.

Zusätzlich, je nach Gebietsdatei:
  - Gebäude (swissBUILDINGS3D, ZIP) werden nach buildings_x/ entpackt (nur fehlende GML-Dateien).
  - "water_source": "osm"  → Wasserflächen, Brücken, Stege und Anlegestellen aus OpenStreetMap
    (© OpenStreetMap contributors, ODbL) über die Overpass-API: ein Request je Gebiet → osm/overpass.json.
  - "copernicus_tiles": [...] → Copernicus DEM GLO-30 (AWS Open Data) → copernicus/<kachel>.tif, damit
    prepare.py Lücken ausserhalb der Schweiz füllen kann.

Aufruf:  .venv/bin/python fetch.py area.json
"""
import json
import re
import sys
import time
from pathlib import Path

import requests
from pyproj import Transformer

STAC = "https://data.geo.admin.ch/api/stac/v0.9/collections/{c}/items"
UA = {"User-Agent": "RowCoach-coursebuilder/0.1 (private, non-commercial)"}
TO_WGS = Transformer.from_crs(2056, 4326, always_xy=True)


def lv95_to_bbox(e0, n0, e1, n1):
    lon0, lat0 = TO_WGS.transform(e0, n0)
    lon1, lat1 = TO_WGS.transform(e1, n1)
    return f"{min(lon0, lon1)},{min(lat0, lat1)},{max(lon0, lon1)},{max(lat0, lat1)}"


def items(collection, bbox):
    url = STAC.format(c=collection)
    params = {"bbox": bbox, "limit": 100}
    while url:
        r = requests.get(url, params=params, headers=UA, timeout=60)
        r.raise_for_status()
        d = r.json()
        yield from d["features"]
        url = next((l["href"] for l in d.get("links", []) if l["rel"] == "next"), None)
        params = None


def year_of(item_id):
    m = re.search(r"_(\d{4})(?:-\d{2})?_", item_id + "_")
    return int(m.group(1)) if m else 0


def tile_key(item_id):
    # alles nach dem Jahr = Kachelname
    return re.sub(r"_\d{4}(-\d{2})?_", "_", item_id)


def in_tile_range(item_id, e0, n0, e1, n1):
    m = re.search(r"_(\d{4})-(\d{4})$", item_id)
    if not m:
        return True  # Kartenblatt-Kacheln (Gebäude): bbox-Filter genügt
    e, n = int(m.group(1)) * 1000, int(m.group(2)) * 1000
    return e0 <= e < e1 and n0 <= n < n1


def pick_asset(item, want):
    for name, a in item["assets"].items():
        if re.search(want, name):
            return name, a["href"]
    return None, None


def download(href, dest: Path):
    if dest.exists() and dest.stat().st_size > 0:
        return False
    tmp = dest.with_suffix(dest.suffix + ".part")
    with requests.get(href, headers=UA, stream=True, timeout=300) as r:
        r.raise_for_status()
        with open(tmp, "wb") as f:
            for chunk in r.iter_content(1 << 20):
                f.write(chunk)
    tmp.rename(dest)
    time.sleep(0.2)
    return True


OVERPASS = "https://overpass-api.de/api/interpreter"
COPERNICUS = "https://copernicus-dem-30m.s3.amazonaws.com/{t}/{t}.tif"


def wgs_bbox_overpass(e0, n0, e1, n1):
    lon0, lat0, lon1, lat1 = map(float, lv95_to_bbox(e0, n0, e1, n1).split(","))
    return f"{lat0:.5f},{lon0:.5f},{lat1:.5f},{lon1:.5f}"  # Overpass: Süd, West, Nord, Ost


def fetch_osm(area, root: Path):
    dest = root / "osm" / "overpass.json"
    if dest.exists() and dest.stat().st_size > 0:
        print("osm: vorhanden", flush=True)
        return
    far = wgs_bbox_overpass(*area["far_lv95"])
    core = wgs_bbox_overpass(*area["core_lv95"])
    q = f"""[out:json][timeout:180];
(
  nwr["natural"="water"]({far});
  nwr["waterway"="riverbank"]({far});
  way["man_made"="bridge"]({core});
  way["bridge"]["bridge"!="no"]({core});
  nwr["man_made"="pier"]({core});
  nwr["bridge:support"]({core});
  nwr["leisure"="marina"]({core});
  nwr["amenity"="ferry_terminal"]({core});
  way["route"="ferry"]({core});
  way["waterway"~"^(dam|weir)$"]({core});
);
out geom;"""
    dest.parent.mkdir(parents=True, exist_ok=True)
    r = requests.post(OVERPASS, data={"data": q}, headers=UA, timeout=300)
    r.raise_for_status()
    dest.write_bytes(r.content)
    (dest.parent / "query.overpassql").write_text(q)
    print(f"osm: {len(r.json()['elements'])} Elemente → {dest}", flush=True)


def fetch_copernicus(area, root: Path):
    out = root / "copernicus"
    for t in area.get("copernicus_tiles", []):
        out.mkdir(parents=True, exist_ok=True)
        new = download(COPERNICUS.format(t=t), out / f"{t}.tif")
        print(f"copernicus {t}: {'neu geladen' if new else 'vorhanden'}", flush=True)


def unzip_buildings(root: Path):
    import zipfile
    zdir, xdir = root / "buildings", root / "buildings_x"
    for z in sorted(zdir.glob("*.zip")) if zdir.exists() else []:
        with zipfile.ZipFile(z) as zf:
            for m in zf.namelist():
                if m.endswith(".gml") and not (xdir / Path(m).name).exists():
                    xdir.mkdir(parents=True, exist_ok=True)
                    tmp = xdir / (Path(m).name + ".part")
                    with zf.open(m) as src, open(tmp, "wb") as dst:
                        while chunk := src.read(1 << 24):
                            dst.write(chunk)
                    tmp.rename(xdir / Path(m).name)
                    print(f"entpackt {Path(m).name}", flush=True)


def main(area_file):
    area = json.loads(Path(area_file).read_text())
    root = Path(area["data_dir"])
    root.mkdir(parents=True, exist_ok=True)
    if area.get("water_source") == "osm":
        fetch_osm(area, root)
    fetch_copernicus(area, root)
    log = []
    for job in area["fetch"]:
        e0, n0, e1, n1 = job["lv95"]
        bbox = lv95_to_bbox(e0, n0, e1, n1)
        latest = {}
        for it in items(job["collection"], bbox):
            if not in_tile_range(it["id"], e0, n0, e1, n1):
                continue
            k = tile_key(it["id"])
            if k not in latest or year_of(it["id"]) > year_of(latest[k]["id"]):
                latest[k] = it
        out = root / job["name"]
        out.mkdir(parents=True, exist_ok=True)
        n_new = 0
        for k, it in sorted(latest.items()):
            name, href = pick_asset(it, job["asset"])
            if not href:
                print("kein Asset", it["id"], file=sys.stderr)
                continue
            if download(href, out / name):
                n_new += 1
            log.append({"job": job["name"], "item": it["id"], "asset": name, "href": href})
        print(f"{job['name']}: {len(latest)} Kacheln, {n_new} neu geladen", flush=True)
    (root / "fetch-log.json").write_text(json.dumps(log, indent=1))
    unzip_buildings(root)


if __name__ == "__main__":
    main(sys.argv[1])
