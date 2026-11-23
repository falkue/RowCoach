"""Lädt swisstopo-Open-Data (OGD, © swisstopo) für ein Gebiet über die STAC-API.

Pro Kachel wird nur die neueste Ausgabe geladen. Bereits vorhandene Dateien werden übersprungen.
Höflich: eine Verbindung nach der anderen, kurze Pause, eindeutiger User-Agent.

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


def main(area_file):
    area = json.loads(Path(area_file).read_text())
    root = Path(area["data_dir"])
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


if __name__ == "__main__":
    main(sys.argv[1])
