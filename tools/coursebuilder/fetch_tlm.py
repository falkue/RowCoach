"""swissTLM3D (© swisstopo, Open Government Data) für Brücken und Bäume holen und je Gebiet ausschneiden.

Das landesweite Paket (Shapefile-ZIP, ~3,6 GB) wird nicht ganz geladen: Über HTTP-Range-Anfragen liest das
Skript nur das Inhaltsverzeichnis des ZIP und entpackt daraus die nötigen Layer (Strassen, Eisenbahn, übrige
Bahnen ~0,55 GB komprimiert; für trees.py Einzelbäume/Gebüsch und Bodenbedeckung, Ost und West, ~1,5 GB) nach data/raw/swisstlm3d/<ausgabe>/. Danach schneidet es für jedes übergebene
Gebiet das Kerngebiet (core_lv95 + 200 m) aus: data/raw/swisstlm3d/<gebiet>.gpkg mit den Layern strasse,
eisenbahn, uebrige_bahn, einzelbaum (Punkte: Einzelbaum, Gebüsch …), bodenbedeckung (Flächen: Wald, Gebüschwald,
Gehölzfläche …) (3D-Linien, LV95/LN02, alle Attribute; Brücken: KUNSTBAUTE = "Bruecke" bzw.
"Bruecke mit Galerie" …). Bereits vorhandene Dateien werden übersprungen.

Aufruf:  .venv/bin/python fetch_tlm.py areas/<gebiet>.json [areas/<gebiet2>.json ...] [--release 2026-02]
"""
import argparse
import io
import json
import shutil
import sys
import zipfile
from datetime import date
from pathlib import Path

import numpy as np
import pyogrio
import requests
from pyogrio import raw

STAC = "https://data.geo.admin.ch/api/stac/v0.9/collections/ch.swisstopo.swisstlm3d/items"
UA = {"User-Agent": "RowCoach-coursebuilder/0.1 (private, non-commercial)"}
LAYERS = {"strasse": ["TLM_STRASSEN/swissTLM3D_TLM_STRASSE"],
          "eisenbahn": ["TLM_OEV/swissTLM3D_TLM_EISENBAHN"],
          "uebrige_bahn": ["TLM_OEV/swissTLM3D_TLM_UEBRIGE_BAHN"],
          # für trees.py (Bäume, Kontrolle und Ergänzung): landesweit in Ost und West geteilt, im gpkg ein Layer
          "einzelbaum": ["TLM_BB/swissTLM3D_TLM_EINZELBAUM_OST", "TLM_BB/swissTLM3D_TLM_EINZELBAUM_WEST"],
          "bodenbedeckung": ["TLM_BB/swissTLM3D_TLM_BODENBEDECKUNG_OST",
                             "TLM_BB/swissTLM3D_TLM_BODENBEDECKUNG_WEST"]}
EXTS = (".shp", ".shx", ".dbf", ".prj", ".cpg")
OUT = Path(__file__).resolve().parents[2] / "data" / "raw" / "swisstlm3d"


class HttpFile(io.RawIOBase):
    """Datei über HTTP-Range-Anfragen (nur lesen, seekbar)."""

    def __init__(self, url):
        self.url, self.pos = url, 0
        self.size = int(requests.head(url, headers=UA, timeout=60).headers["content-length"])

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else (self.pos + off if whence == 1 else self.size + off)
        return self.pos

    def readinto(self, b):
        n = min(len(b), self.size - self.pos)
        if n <= 0:
            return 0
        r = requests.get(self.url, headers={**UA, "Range": f"bytes={self.pos}-{self.pos + n - 1}"}, timeout=300)
        r.raise_for_status()
        d = r.content
        b[:len(d)] = d
        self.pos += len(d)
        return len(d)


def latest_item(release=None):
    url, params, best = STAC, {"limit": 100}, None
    while url:
        d = requests.get(url, params=params, headers=UA, timeout=60).json()
        for f in d["features"]:
            if release and not f["id"].endswith(release):
                continue
            if any(k.endswith(".shp.zip") for k in f["assets"]):
                best = f
        url = next((l["href"] for l in d.get("links", []) if l["rel"] == "next"), None)
        params = None
    if best is None:
        sys.exit("Keine swissTLM3D-Ausgabe mit Shapefile-ZIP gefunden")
    href = next(a["href"] for k, a in best["assets"].items() if k.endswith(".shp.zip"))
    return best["id"], href


def extract_layers(item_id, href):
    dest = OUT / item_id
    dest.mkdir(parents=True, exist_ok=True)
    want = {stem + ext for stems in LAYERS.values() for stem in stems for ext in EXTS}
    todo = [w for w in want if not (dest / Path(w).name).exists()]
    if not todo:
        return dest
    hf = HttpFile(href)
    z = zipfile.ZipFile(hf)
    for info in z.infolist():
        name = info.filename.replace("\\", "/")
        if name not in todo:
            continue
        target = dest / Path(name).name
        print(f"  entpacke {name} ({info.compress_size / 1e6:.0f} MB komprimiert)", flush=True)
        tmp = target.with_suffix(target.suffix + ".part")
        # grosse Blöcke, damit nicht jede kleine Leseoperation eine eigene Anfrage wird
        hf_seq = HttpFile(href)
        zz = zipfile.ZipFile(io.BufferedReader(hf_seq, buffer_size=8 << 20))
        with zz.open(info) as src, open(tmp, "wb") as dst:
            shutil.copyfileobj(src, dst, 4 << 20)
        tmp.replace(target)
    meta = {"item": item_id, "href": href, "retrieved_at": date.today().isoformat(),
            "members": sorted(want), "licence": "swisstopo Open Government Data (OGD), Quellenangabe © swisstopo"}
    (dest / "fetch-meta.json").write_text(json.dumps(meta, indent=1))
    return dest


def clip(area_file, src_dir, item_id):
    area = json.loads(Path(area_file).read_text())
    e0, n0, e1, n1 = area["core_lv95"]
    bbox = (e0 - 200, n0 - 200, e1 + 200, n1 + 200)
    out = OUT / f"{area['id']}.gpkg"
    if out.exists():
        out.unlink()
    for layer, stems in LAYERS.items():
        n = 0
        for stem in stems:
            shp = src_dir / (Path(stem).name + ".shp")
            meta, _, geom, fields = raw.read(shp, bbox=bbox)
            if len(geom) == 0:
                continue
            raw.write(out, geometry=geom, field_data=fields, fields=meta["fields"], layer=layer, driver="GPKG",
                      crs=meta["crs"], geometry_type=meta["geometry_type"], encoding="UTF-8",
                      append=out.exists())
            n += len(geom)
        print(f"  {area['id']}: {layer} {n} Objekte", flush=True)
    info = {"source": f"swissTLM3D {item_id}, © swisstopo (OGD)", "bbox_lv95": bbox,
            "layers": list(LAYERS), "retrieved_at": date.today().isoformat()}
    (OUT / f"{area['id']}.json").write_text(json.dumps(info, indent=1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("areas", nargs="+")
    ap.add_argument("--release")
    a = ap.parse_args()
    item_id, href = latest_item(a.release)
    print(f"swissTLM3D: {item_id}", flush=True)
    src = extract_layers(item_id, href)
    for f in a.areas:
        clip(f, src, item_id)


if __name__ == "__main__":
    main()
