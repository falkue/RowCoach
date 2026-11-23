"""Lädt Geobasisdaten für Gebiete in Berlin und Brandenburg (ETRS89/UTM 33N, EPSG:25833).

Quellen (nur offizielle Download-Wege, höflich: eine Verbindung, kurze Pausen, eindeutiger User-Agent):
  Brandenburg (LGB, data.geobasis-bb.de, Datenlizenz Deutschland – Namensnennung – 2.0, „© GeoBasis-DE/LGB“):
    dgm   DGM1 (GeoTIFF, 1-km-Kacheln dgm_33EEE-NNNN.zip); deckt auch Berlin ab → dgm/
    dop   DOP20 RGBI (GeoTIFF, 1-km-Kacheln dop_33EEE-NNNN.zip) → image_core/ (wo Berlin fehlt)
    lod2  3D-Gebäude LoD2 (CityGML 1.0, lod2_33EEE-NNNN.zip) → buildings_x/bb_EEE_NNNN.gml
    bdom  bildbasiertes Oberflächenmodell (GeoTIFF, 1-km-Kacheln) → bdom/ (für Bäume: chm = bDOM − DGM; Brückendecks)
    WMS   bebb_dop20c (isk.geobasis-bb.de) für das Umgebungsluftbild (2 m)
  Berlin (Geoportal Berlin, gdi.berlin.de, Datenlizenz Deutschland – Zero – 2.0):
    truedop  TrueOrthophotos Sommer 2025 (DOP20RGBI, JPEG 2000, 2-km-Kacheln in neun Regions-ZIPs von 0,1–3,4 GB);
             über HTTP-Range-Anfragen wird nur das Inhaltsverzeichnis gelesen und nur die nötigen Kacheln entpackt
             → truedop_be/ (Rohdaten) und image_core/ (je km ein RGB-GeoTIFF 0,2 m)
    lod2     3D-Gebäudemodelle LoD2 (CityGML 1.0, 1-km-Kacheln LoD2_EEE_NNNN.zip) → buildings_x/be_EEE_NNNN.gml
    bdom/dgm bDOM bzw. DGM1 als ASCII-XYZ (1 m, 2-km-Kacheln) → je km GeoTIFF wie Brandenburg ("bdom": "be",
             "dgm": "be"; DGM1 Berlin reicht nur 250 m nach Brandenburg)
    WMS      truedop_2025_sommer_rgb für das Umgebungsluftbild (2 m), Vorrang vor Brandenburg
  OpenStreetMap (Overpass, ODbL) wie fetch.py → osm/overpass.json

Gebietsdatei: "crs": "EPSG:25833", Ausdehnungen in den Feldern core_lv95/far_lv95/buildings_lv95 (Name aus
Kompatibilität, Werte im Koordinatensystem "crs"), dazu
  "fetch_de": {"dgm": true, "ortho": ["be", "bb"], "ortho_far": ["be", "bb"], "lod2": ["be", "bb"], "bdom": true}
"ortho": Reihenfolge = Vorrang; je km-Kachel wird die erste Quelle genommen und Lücken (z. B. ausserhalb Berlins)
aus der nächsten gefüllt. Bereits vorhandene Dateien werden übersprungen.

Ergebnis in data_dir: dgm/, image_core/dop_EEE-NNNN.tif, image_far/wms_EEE-NNNN.tif, buildings_x/, bdom/,
osm/overpass.json, truedop_be/, fetch-log.json (Quelle, URL, Lizenz, Datum je Paket).

Aufruf:  .venv/bin/python fetch_de.py areas/<gebiet>.json
         .venv/bin/python fetch_de.py areas/<gebiet>.json --trees-inputs   # build/<gebiet>/chm.tif, ortho_core.tif
                                                                            # für trees.py ("trees": true)
"""
import io
import json
import shutil
import sys
import tempfile
import time
import zipfile
from datetime import date
from pathlib import Path

import numpy as np
import rasterio
import requests
from PIL import Image
from rasterio.enums import Resampling
from rasterio.transform import from_origin
from rasterio.windows import from_bounds

from fetch import fetch_osm
from fetch_tlm import HttpFile

UA = {"User-Agent": "RowCoach-coursebuilder/0.1 (open-source rowing app, non-commercial)"}
BB = "https://data.geobasis-bb.de/geobasis/daten"
BE_TRUEDOP = "https://gdi.berlin.de/data/truedop_2025_sommer/atom"
BE_REGIONS = ["Mitte", "Nord", "Nordost", "Nordwest", "Ost", "Süd", "Südost", "Südwest", "West"]
BE_LOD2 = "https://gdi.berlin.de/data/a_lod2/atom/LoD2_{e}_{n}.zip"
WMS = {"be": ("https://gdi.berlin.de/services/wms/truedop_2025_sommer", "truedop_2025_sommer_rgb"),
       "bb": ("https://isk.geobasis-bb.de/mapproxy/dop20c/service/wms", "bebb_dop20c")}
LIC = {"bb": "Datenlizenz Deutschland – Namensnennung – Version 2.0 (dl-de/by-2-0), © GeoBasis-DE/LGB",
       "be": "Datenlizenz Deutschland – Zero – Version 2.0 (dl-de/zero-2-0), Geoportal Berlin"}
CRS = "EPSG:25833"
ORTHO_RES = 0.2
LOG = []


def km_tiles(bbox):
    e0, n0, e1, n1 = bbox
    return [(e, n) for e in range(int(e0 // 1000), int(np.ceil(e1 / 1000))) for n in range(int(n0 // 1000),
                                                                                           int(np.ceil(n1 / 1000)))]


def get(url, dest: Path, missing: set):
    """Datei laden (nur wenn nicht vorhanden); 404 → None und merken."""
    if dest.exists() and dest.stat().st_size > 0:
        return dest
    if url in missing:
        return None
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    for attempt in range(4):
        try:
            with requests.get(url, headers=UA, stream=True, timeout=(30, 300)) as r:
                if r.status_code == 404:
                    missing.add(url)
                    return None
                r.raise_for_status()
                with open(tmp, "wb") as f:
                    for chunk in r.iter_content(1 << 20):
                        f.write(chunk)
            break
        except requests.RequestException as ex:
            print(f"  Fehler {url}: {ex} – neuer Versuch", flush=True)
            time.sleep(5 * (attempt + 1))
    else:
        raise SystemExit(f"Download fehlgeschlagen: {url}")
    tmp.rename(dest)
    time.sleep(0.25)
    return dest


def unzip_member(zpath: Path, suffix, dest: Path):
    if dest.exists():
        return dest
    with zipfile.ZipFile(zpath) as z:
        m = next((n for n in z.namelist() if n.lower().endswith(suffix)), None)
        if m is None:
            return None
        tmp = dest.with_suffix(dest.suffix + ".part")
        with z.open(m) as src, open(tmp, "wb") as dst:
            shutil.copyfileobj(src, dst, 1 << 22)
        tmp.rename(dest)
    return dest


# ----------------------------------------------------------------------------- Brandenburg (LGB)

def bb_tiles(kind, tiles, root, missing):
    """kind: dgm | dop | bdom | lod2 → Pfade je (e, n)."""
    url = {"dgm": BB + "/dgm/tif/dgm_33{e}-{n}.zip", "dop": BB + "/dop/rgbi_tif/dop_33{e}-{n}.zip",
           "bdom": BB + "/bdom/tif/bdom_33{e}-{n}.zip",
           "lod2": BB + "/3d_gebaeude/lod2_gml/lod2_33{e}-{n}.zip"}[kind]
    zdir = root / f"zip_bb_{kind}"
    out = {}
    n_new = 0
    for e, n in tiles:
        if kind == "lod2":
            target = root / "buildings_x" / f"bb_{e}_{n}.gml"
        elif kind == "dop":
            target = zdir / f"dop_33{e}-{n}.tif"
        else:
            target = root / kind / f"{kind}_33{e}-{n}.tif"
        if target.exists():
            out[(e, n)] = target
            continue
        z = get(url.format(e=e, n=n), zdir / f"{kind}_33{e}-{n}.zip", missing)
        if z is None:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        if unzip_member(z, ".gml" if kind == "lod2" else ".tif", target) is not None:
            out[(e, n)] = target
            n_new += 1
            z.unlink()  # entpackte Datei = Rohdatei (Metadaten-HTML im ZIP: Quelle und Datum siehe fetch-log.json)
    LOG.append({"source": f"LGB {kind}", "url": url, "tiles": len(out), "licence": LIC["bb"],
                "retrieved_at": date.today().isoformat()})
    print(f"bb {kind}: {len(out)} Kacheln ({n_new} neu)", flush=True)
    return out


# ----------------------------------------------------------------------------- Berlin

def be_truedop_index(root):
    f = root.parent / "berlin-truedop-2025-sommer-index.json"
    if f.exists():
        return json.loads(f.read_text())
    idx = {}
    for reg in BE_REGIONS:
        url = f"{BE_TRUEDOP}/{reg}.zip"
        z = zipfile.ZipFile(io.BufferedReader(HttpFile(url), 1 << 16))
        for i in z.infolist():
            name = Path(i.filename).name
            if name.endswith(".jp2"):  # dop20rgbi_33_EEE_NNNN_2_be_2025.jp2 (2 × 2 km, Ecke SW)
                p = name.split("_")
                idx[f"{p[2]}_{p[3]}"] = {"zip": url, "member": i.filename, "size": i.file_size}
        time.sleep(0.3)
    f.write_text(json.dumps(idx, indent=0))
    return idx


def be_truedop(tiles, root):
    """2-km-Kacheln, die die km-Kacheln berühren, aus den Regions-ZIPs entpacken → truedop_be/*.jp2."""
    idx = be_truedop_index(root)
    need = sorted({(e - e % 2, n - n % 2) for e, n in tiles})
    out = {}
    for e2, n2 in need:
        k = f"{e2}_{n2}"
        if k not in idx:
            continue
        dest = root / "truedop_be" / Path(idx[k]["member"]).name
        if not dest.exists():
            dest.parent.mkdir(parents=True, exist_ok=True)
            print(f"  entpacke {idx[k]['member']} ({idx[k]['size'] / 1e6:.0f} MB) aus {idx[k]['zip']}", flush=True)
            zz = zipfile.ZipFile(io.BufferedReader(HttpFile(idx[k]["zip"]), buffer_size=8 << 20))
            tmp = dest.with_suffix(".part")
            with zz.open(idx[k]["member"]) as src, open(tmp, "wb") as dst:
                shutil.copyfileobj(src, dst, 4 << 20)
            tmp.rename(dest)
            time.sleep(0.5)
        out[(e2, n2)] = dest
    LOG.append({"source": "Geoportal Berlin, TrueOrthophotos Sommer 2025 (DOP20RGBI)", "url": BE_TRUEDOP,
                "tiles_2km": len(out), "licence": LIC["be"], "retrieved_at": date.today().isoformat()})
    print(f"be truedop: {len(out)} Kacheln à 2 km", flush=True)
    return out


def be_lod2(tiles, root, missing):
    out, n_new = {}, 0
    for e, n in tiles:
        target = root / "buildings_x" / f"be_{e}_{n}.gml"
        if not target.exists():
            z = get(BE_LOD2.format(e=e, n=n), root / "zip_be_lod2" / f"LoD2_{e}_{n}.zip", missing)
            if z is None:
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            unzip_member(z, ".xml", target) or unzip_member(z, ".gml", target)
            z.unlink()
            n_new += 1
        out[(e, n)] = target
    LOG.append({"source": "Geoportal Berlin, 3D-Gebäudemodelle LoD2", "url": BE_LOD2, "tiles": len(out),
                "licence": LIC["be"], "retrieved_at": date.today().isoformat()})
    print(f"be lod2: {len(out)} Kacheln ({n_new} neu)", flush=True)
    return out


BE_XYZ = {"bdom": "https://gdi.berlin.de/data/bdom/atom/{e}_{n}.zip",
          "dgm": "https://gdi.berlin.de/data/dgm1/atom/DGM1_{e}_{n}.zip"}


def be_xyz(kind, tiles, root, missing):
    """Berlin bDOM bzw. DGM1 (ASCII-XYZ, 1 m, 2-km-Kacheln) → je km ein GeoTIFF kind/<kind>_33EEE-NNNN.tif
    (gleiche Namen wie Brandenburg, damit die weiteren Schritte nicht unterscheiden müssen)."""
    out, n_new = {}, 0
    for e2, n2 in sorted({(e - e % 2, n - n % 2) for e, n in tiles}):
        quads = [(e2 + i, n2 + j) for i in (0, 1) for j in (0, 1)]
        dests = {q: root / kind / f"{kind}_33{q[0]}-{q[1]}.tif" for q in quads}
        if all(d.exists() for d in dests.values()):
            out.update({q: d for q, d in dests.items() if (q in tiles)})
            continue
        z = get(BE_XYZ[kind].format(e=e2, n=n2), root / f"zip_be_{kind}" / f"{kind}_{e2}_{n2}.zip", missing)
        if z is None:
            continue
        with zipfile.ZipFile(z) as zf:
            m = next(x for x in zf.namelist() if x.lower().endswith((".xyz", ".txt", ".csv")))
            xyz = np.fromstring(zf.read(m).decode("ascii"), sep=" ").reshape(-1, 3)  # x y z je Zeile
        grid = np.full((2000, 2000), -9999.0, np.float32)
        col = np.floor(xyz[:, 0] - e2 * 1000).astype(int)
        row = np.floor(n2 * 1000 + 2000 - xyz[:, 1]).astype(int)
        ok = (col >= 0) & (col < 2000) & (row >= 0) & (row < 2000)
        grid[row[ok], col[ok]] = xyz[ok, 2]
        del xyz
        for (qe, qn), d in dests.items():
            d.parent.mkdir(parents=True, exist_ok=True)
            r0 = (n2 + 1 - qn) * 1000
            c0 = (qe - e2) * 1000
            prof = dict(driver="GTiff", width=1000, height=1000, count=1, dtype="float32", crs=CRS, nodata=-9999.0,
                        transform=from_origin(qe * 1000, qn * 1000 + 1000, 1.0, 1.0), compress="deflate",
                        predictor=3, tiled=True)
            with rasterio.open(d, "w", **prof) as dst:
                dst.write(grid[r0:r0 + 1000, c0:c0 + 1000], 1)
            if (qe, qn) in tiles:
                out[(qe, qn)] = d
        z.unlink()
        n_new += 1
    LOG.append({"source": f"Geoportal Berlin, {kind} (XYZ 1 m)", "url": BE_XYZ[kind], "tiles": len(out),
                "licence": LIC["be"], "retrieved_at": date.today().isoformat()})
    print(f"be {kind}: {len(out)} km-Kacheln ({n_new} neue 2-km-Kacheln)", flush=True)
    return out


# ----------------------------------------------------------------------------- Luftbild Kerngebiet

def read_rgb_window(path, bounds, size):
    """RGB (Bänder 1–3) eines Ausschnitts, 0 = keine Daten (ausserhalb der Kachel)."""
    with rasterio.open(path) as src:
        b = src.bounds
        inside = b.left <= bounds[0] and b.bottom <= bounds[1] and b.right >= bounds[2] and b.top >= bounds[3]
        win = from_bounds(*bounds, src.transform)
        same = abs(src.res[0] * size - (bounds[2] - bounds[0])) < 1e-6
        rs = Resampling.nearest if same else Resampling.average
        if inside:  # ohne boundless (bei JPEG 2000 sehr viel schneller)
            return src.read([1, 2, 3], window=win, out_shape=(3, size, size), resampling=rs)
        return src.read([1, 2, 3], window=win, out_shape=(3, size, size), boundless=True, fill_value=0,
                        resampling=rs)


def build_core_ortho(area, root, sources, missing):
    """Je km-Kachel ein RGB-GeoTIFF (0,2 m, JPEG) aus den Quellen in Vorrangreihenfolge → image_core/."""
    tiles = km_tiles(area["core_lv95"])
    out_dir = root / "image_core"
    out_dir.mkdir(parents=True, exist_ok=True)
    be = be_truedop(tiles, root) if "be" in sources else {}
    size = int(round(1000 / ORTHO_RES))
    n_bb = 0
    for e, n in tiles:
        dest = out_dir / f"dop_{e}-{n}.tif"
        if dest.exists():
            continue
        b = (e * 1000, n * 1000, e * 1000 + 1000, n * 1000 + 1000)
        img = np.zeros((3, size, size), np.uint8)
        hole = np.ones((size, size), bool)
        for s in sources:
            if not hole.any():
                break
            if s == "be":
                src = be.get((e - e % 2, n - n % 2))
            else:
                src = bb_tiles("dop", [(e, n)], root, missing).get((e, n))
                n_bb += src is not None
            if src is None:
                continue
            part = read_rgb_window(src, b, size)
            ok = part.max(axis=0) > 0
            if s == "be":
                ok &= part.min(axis=0) < 255  # Berlin: ausserhalb des Landes weiss bzw. schwarz
            take = hole & ok
            img[:, take] = part[:, take]
            hole &= ~take
            if hole.mean() < 0.002:  # einzelne schwarze Pixel (Schatten) sind keine Lücke
                hole[:] = False
        if hole.all():
            print(f"  km {e}-{n}: kein Luftbild", flush=True)
            continue
        prof = dict(driver="GTiff", width=size, height=size, count=3, dtype="uint8", crs=CRS,
                    transform=from_origin(b[0], b[3], ORTHO_RES, ORTHO_RES), compress="jpeg", jpeg_quality=90,
                    photometric="YCBCR", tiled=True, blockxsize=512, blockysize=512)
        tmp = dest.with_suffix(".part.tif")
        with rasterio.open(tmp, "w", **prof) as dst:
            dst.write(img)
        tmp.rename(dest)
        print(f"  image_core {dest.name}: Lücken {hole.mean() * 100:.1f} %", flush=True)
    print(f"image_core: {len(list(out_dir.glob('dop_*.tif')))} km-Kacheln (Brandenburg {n_bb})", flush=True)


# ----------------------------------------------------------------------------- Umgebungsluftbild (WMS)

def wms_far(area, root, sources, block=2000, res=2.0):
    e0, n0, e1, n1 = area["far_lv95"]
    out_dir = root / "image_far"
    out_dir.mkdir(parents=True, exist_ok=True)
    px = int(block / res)
    n_req = 0
    for e in range(int(e0), int(e1), block):
        for n in range(int(n0), int(n1), block):
            dest = out_dir / f"wms_{e // 1000}-{n // 1000}.tif"
            if dest.exists():
                continue
            rgb = np.zeros((px, px, 3), np.uint8)
            hole = np.ones((px, px), bool)
            for s in sources:
                if not hole.any():
                    break
                url, layer = WMS[s]
                params = {"SERVICE": "WMS", "VERSION": "1.3.0", "REQUEST": "GetMap", "LAYERS": layer, "STYLES": "",
                          "CRS": CRS, "BBOX": f"{e},{n},{e + block},{n + block}", "WIDTH": px, "HEIGHT": px,
                          "FORMAT": "image/png", "TRANSPARENT": "TRUE"}
                for attempt in range(4):
                    try:
                        r = requests.get(url, params=params, headers=UA, timeout=120)
                        r.raise_for_status()
                        if "xml" in r.headers.get("content-type", ""):  # Ausnahmebericht: dort keine Daten
                            im = None
                            break
                        im = np.asarray(Image.open(io.BytesIO(r.content)).convert("RGBA"))
                        break
                    except Exception as ex:  # noqa: BLE001
                        print(f"  WMS {s} Fehler: {ex}", flush=True)
                        time.sleep(5 * (attempt + 1))
                else:
                    continue
                n_req += 1
                if im is None:
                    continue
                time.sleep(0.3)
                ok = (im[..., 3] > 200) & (im[..., :3].max(axis=2) > 0)
                take = hole & ok
                rgb[take] = im[..., :3][take]
                hole &= ~take
            prof = dict(driver="GTiff", width=px, height=px, count=3, dtype="uint8", crs=CRS,
                        transform=from_origin(e, n + block, res, res), compress="deflate")
            with rasterio.open(dest, "w", **prof) as dst:
                dst.write(np.moveaxis(rgb, -1, 0))
    for s in sources:
        LOG.append({"source": f"WMS {WMS[s][1]}", "url": WMS[s][0], "res_m": res, "licence": LIC[s],
                    "retrieved_at": date.today().isoformat()})
    print(f"image_far: {len(list(out_dir.glob('wms_*.tif')))} Blöcke à {block / 1000:.0f} km ({n_req} Anfragen)",
          flush=True)


def trees_inputs(area):
    """Eingaben für trees.py (Team N) aus den Rohdaten ablegen: build/<gebiet>/chm.tif (Vegetationshöhe = bDOM − DGM1,
    0,5 m, float32) und ortho_core.tif (Luftbild RGB 1 m), Raster wie trees.py (Kerngebiet, Ecke NW)."""
    from rasterio.merge import merge
    root = (Path.cwd() / area["data_dir"]).resolve()
    build = Path("build") / area["id"]
    build.mkdir(parents=True, exist_ok=True)
    e0, n0, e1, n1 = area["core_lv95"]
    for name, res, count, dtype in (("chm.tif", 0.5, 1, "float32"), ("ortho_core.tif", 1.0, 3, "uint8")):
        f = build / name
        if f.exists():
            continue
        w, h = int(round((e1 - e0) / res)), int(round((n1 - n0) / res))
        prof = dict(driver="GTiff", width=w, height=h, count=count, dtype=dtype, crs=CRS,
                    transform=from_origin(e0, n1, res, res), compress="deflate", tiled=True, blockxsize=512,
                    blockysize=512)
        if count == 3:
            prof["photometric"] = "RGB"
        with rasterio.open(f, "w", **prof) as dst:
            for e, n in km_tiles(area["core_lv95"]):
                b = (max(e * 1000, e0), max(n * 1000, n0), min(e * 1000 + 1000, e1), min(n * 1000 + 1000, n1))
                win = from_bounds(*b, dst.transform).round_offsets().round_lengths()
                shp = (int(win.height), int(win.width))
                if count == 3:
                    src = root / "image_core" / f"dop_{e}-{n}.tif"
                    if not src.exists():
                        continue
                    with rasterio.open(src) as s_:
                        img = s_.read([1, 2, 3], window=from_bounds(*b, s_.transform), out_shape=(3, *shp),
                                      resampling=Resampling.average)
                    dst.write(img, window=win)
                else:
                    fs, fd = root / "bdom" / f"bdom_33{e}-{n}.tif", root / "dgm" / f"dgm_33{e}-{n}.tif"
                    if not (fs.exists() and fd.exists()):
                        continue
                    with rasterio.open(fs) as ss, rasterio.open(fd) as dd:
                        zs = ss.read(1, window=from_bounds(*b, ss.transform), out_shape=shp,
                                     resampling=Resampling.average)
                        zd = dd.read(1, window=from_bounds(*b, dd.transform), out_shape=shp,
                                     resampling=Resampling.bilinear)
                    ok = (zs > -1000) & (zd > -1000)
                    dst.write(np.where(ok, np.clip(zs - zd, 0, 80), 0).astype(np.float32), 1, window=win)
        print(f"{f}: {w}×{h} px, {res} m", flush=True)


def main(area_file):
    area = json.loads(Path(area_file).read_text())
    if area.get("crs") != CRS:
        sys.exit(f"fetch_de.py: Gebiet braucht \"crs\": \"{CRS}\"")
    root = (Path.cwd() / area["data_dir"]).resolve()
    root.mkdir(parents=True, exist_ok=True)
    cfg = area.get("fetch_de", {})
    missing_f = root / "missing-urls.json"
    missing = set(json.loads(missing_f.read_text())) if missing_f.exists() else set()
    try:
        if cfg.get("dgm", True) == "be":  # Berlin (XYZ, nur Berlin + 250 m), sonst Brandenburg (deckt Berlin ab)
            be_xyz("dgm", km_tiles(area["far_lv95"]), root, missing)
        elif cfg.get("dgm", True):
            bb_tiles("dgm", km_tiles(area["far_lv95"]), root, missing)
        if cfg.get("ortho"):
            build_core_ortho(area, root, cfg["ortho"], missing)
        if cfg.get("ortho_far"):
            wms_far(area, root, cfg["ortho_far"])
        btiles = km_tiles(area.get("buildings_lv95", area["core_lv95"]))
        for s in cfg.get("lod2", []):
            be_lod2(btiles, root, missing) if s == "be" else bb_tiles("lod2", btiles, root, missing)
        if cfg.get("bdom") == "be":  # Berlin (XYZ), sonst Brandenburg
            be_xyz("bdom", km_tiles(area["core_lv95"]), root, missing)
        elif cfg.get("bdom"):
            bb_tiles("bdom", km_tiles(area["core_lv95"]), root, missing)
        if area.get("water_source") == "osm":
            import fetch as fetch_mod
            mirrors = [fetch_mod.OVERPASS, "https://overpass.kumi.systems/api/interpreter",
                       "https://overpass.private.coffee/api/interpreter"]  # öffentliche Instanzen (OSM-Wiki)
            for attempt in range(6):  # Overpass ist manchmal überlastet (502/504): andere Instanz, später erneut
                fetch_mod.OVERPASS = mirrors[attempt % len(mirrors)]
                try:
                    fetch_osm(area, root)
                    break
                except requests.RequestException as ex:
                    print(f"osm: {ex} – neuer Versuch in {30 * (attempt + 1)} s", flush=True)
                    time.sleep(30 * (attempt + 1))
            else:
                print("osm: fehlgeschlagen – fetch_de.py später erneut laufen lassen", flush=True)
            LOG.append({"source": "OpenStreetMap (Overpass API)", "licence": "ODbL, © OpenStreetMap contributors",
                        "retrieved_at": date.today().isoformat()})
    finally:
        missing_f.write_text(json.dumps(sorted(missing), indent=0))
        log_f = root / "fetch-log.json"
        old = json.loads(log_f.read_text()) if log_f.exists() else []
        log_f.write_text(json.dumps(old + LOG, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    if "--trees-inputs" in sys.argv:  # nach prepare.py: chm.tif und ortho_core.tif für trees.py
        trees_inputs(json.loads(Path(sys.argv[1]).read_text()))
    else:
        main(sys.argv[1])
