"""Schritt 3b: Bäume aus dem Oberflächenmodell erkennen, als Low-Poly-Meshes mit vorgerechnetem Licht bauen.

Nur mit "trees": true in der Gebietsdatei. Läuft nach buildings.py und vor bake.py/bridges.py/export.py
(braucht dem_core.tif, water.geojson, routes.geojson und die Gebäude). Ohne das Feld ändert sich nichts.

Eingaben in build/<gebiet>/ (fehlen sie, erzeugt trees.py sie selbst aus den swisstopo-Rohdaten; ein anderes Gebiet,
z. B. in Deutschland, kann sie mit eigenen Daten vorab ablegen, Koordinatensystem = "crs" der Gebietsdatei,
Standard EPSG:2056):
  chm.tif            Vegetationshöhe über Gelände in m (Oberflächenmodell − Geländemodell), float32, ca. 0,5 m;
                     hier aus swissSURFACE3D Raster (surface_core) − swissALTI3D 0,5 m (alti_core), Kachel für Kachel
  building_mask.tif  uint8, 1 = Gebäude oder Brücke (keine Bäume), gleiche Rasterung wie chm.tif;
                     hier aus den Gebäudedreiecken (buildings_*.npz, 1,5 m gepuffert) und den Brücken aus swissTLM3D
  ortho_core.tif     Luftbild RGB 1 m (Grünanteil, Kronenfarbe); hier aus den Luftbildkacheln image_core
                     (common.ortho_tile: SWISSIMAGE oder fetch_de.py)
  dem_core.tif, water.geojson, routes.geojson   wie für die anderen Schritte
  optional: <data_dir>/../swisstlm3d/<gebiet>.gpkg (fetch_tlm.py): Layer einzelbaum (Kontrolle), bodenbedeckung
                     (Wald, Gehölzfläche: Kronen dort auch ohne deutliches Grün im Luftbild), strasse (Stämme nicht
                     auf Fahrbahnen; Brücken in die Gebäudemaske)

Ergebnis in build/<gebiet>/trees/:
  detected.npz       alle erkannten Bäume und Büsche (Lage, Höhe, Kronenradius, Art, Farbe, Wald, sichtbar)
  veg.tif            1 m, uint8: 0 sonst, 1 niedrige Vegetation (Rasen, Wiese), 2 Baumkrone – für summer.py/export.py
  <stufe>/tree_ao.tif 1 m, uint8 (255 = unverändert): sanfter Kontaktschatten unter den 3D-Bäumen fürs Gelände
  <stufe>/trees.npz  Meshes je 1-km-Zelle (Ecken lokal ENU, Dreiecke, Normalen, UV; Schlüssel wie bake/groups.npz)
  <stufe>/tree_*.jpg Atlas je Mesh: Laubfarbe × Verdeckung × Selbstschattierung × Sonnenschatten (235°/48°)
  <stufe>-ambient/   dieselben Meshes, Atlas ohne Sonnenschatten (für export.py --light ambient)
  <stufe>/meta.json  Zahlen je Mesh und Detailstufe
  stats.json         Erkennung: Zahl je Art, Abgleich mit swissTLM3D-Einzelbäumen

Erkennung: Vegetationshöhe ohne Gebäude/Wasser, morphologisch geöffnet (Laternen, Masten, Leitungen fallen weg) und
geglättet; lokale Maxima über 3 m mit höhenabhängigem Fenster (0,5 m + 0,1 × Höhe), Watershed auf der Kronenhöhe
→ Kronenfläche → Radius. Eine Krone zählt, wenn das Luftbild dort grün ist (oder sie im TLM-Wald/Gehölz liegt).
Art grob aus der Kronenform: schlank und spitz (Höhe/Breite, Kegelform) = Nadelbaum, sehr schlank = Pappel, sonst
Laubbaum in drei Formen (rund, eiförmig, breit). Niedrige grüne Vegetation 1–3 m = Busch.
Detailstufen nach Abstand zur Strecke: nah volle Form, mittel einfache Form, fern keine 3D-Bäume (die Geländetextur
macht summer.py grüner). Nur Bäume, die von der Strecke aus nicht ganz hinter Häusern oder Gelände verschwinden.
Ein Budget an Dreiecken je Stufe begrenzt die Zahl (zuerst die grossen, nahen Bäume).

Aufruf:  .venv/bin/python trees.py areas/<gebiet>.json [standard] [hoch] [--procs 8] [--redetect]
"""
import os
import sys

if "--device" not in sys.argv or sys.argv[sys.argv.index("--device") + 1] == "cpu":
    os.environ["CUDA_VISIBLE_DEVICES"] = ""

import argparse  # noqa: E402
import json  # noqa: E402
import math  # noqa: E402
import multiprocessing as mp  # noqa: E402
import time  # noqa: E402
from pathlib import Path  # noqa: E402

import numpy as np  # noqa: E402
import rasterio  # noqa: E402
from PIL import Image  # noqa: E402
from rasterio.enums import Resampling  # noqa: E402
from rasterio.features import rasterize  # noqa: E402
from rasterio.transform import from_origin  # noqa: E402
from rasterio.windows import Window, from_bounds  # noqa: E402
from scipy import ndimage  # noqa: E402
from scipy.spatial import cKDTree  # noqa: E402
from shapely.geometry import LineString, shape  # noqa: E402

from common import load_area, ortho_tile  # noqa: E402

DEVICE = sys.argv[sys.argv.index("--device") + 1] if "--device" in sys.argv else "cpu"
SUN_AZ, SUN_EL = 235.0, 48.0  # wie bake.py / App (summerSunny)
SUN_CONE = math.radians(1.5)
CELL = 1000.0
RES = 0.5  # m, Raster der Erkennung (chm.tif)
TILE = 1000.0
LANE_CLEAR_M = 12.0  # m, Mindestabstand Kronenrand – Hin- und Rückfahrt
ROUGH_MIN = 0.30  # m, mittlere Rauigkeit einer Krone (Fahrzeuge, Zelte, Kioske sind glatter)
HALO = 30.0

# Arten
DECID, CONIFER, POPLAR, BUSH, PINE = 0, 1, 2, 3, 4
KIND_NAMES = {DECID: "Laubbaum", CONIFER: "Nadelbaum", POPLAR: "Pappel", BUSH: "Busch", PINE: "Kiefer"}

LEVELS = {
    # near_m: volle Form; mid_m: einfache Form; bush_m: Büsche; budget: Dreiecke (Gebietsdatei "trees_budget")
    "standard": {"near_m": 300, "mid_m": 1000, "bush_m": 150, "budget": 250_000, "mid_min_h": 6.0,
                 "full": (7, "full"), "simple": (5, "simple"), "trunk_sides": 3, "atlas_q": 92},
    "hoch": {"near_m": 500, "mid_m": 1500, "bush_m": 250, "budget": 550_000, "mid_min_h": 5.0,
             "full": (9, "hoch"), "simple": (6, "hsimple"), "trunk_sides": 4, "atlas_q": 92},
}

# Kronenprofile: Reihen (z relativ zur Krone 0 unten … 1 oben, Radius relativ) von der Spitze zum unteren Pol.
def _round(n):
    th = np.linspace(0, np.pi, n)
    return np.stack([(1 + np.cos(th)) / 2, np.sin(th)], 1)


def _egg(n):
    p = _round(n)
    p[:, 1] *= 0.72 + 0.42 * p[:, 0]
    p[:, 1] /= p[:, 1].max()
    return p


def _broad(n):
    th = np.linspace(0, np.pi, n)
    z = ((1 + np.cos(th)) / 2) ** 0.75
    return np.stack([z, np.sin(th) ** 0.7], 1)


CONE_ROWS = {
    "full": [(1, 0), (0.72, 0.42), (0.55, 0.33), (0.28, 0.86), (0.06, 1.0), (0.0, 0.0)],
    "simple": [(1, 0), (0.3, 0.78), (0.05, 1.0), (0.0, 0.0)],
    "hoch": [(1, 0), (0.8, 0.34), (0.66, 0.27), (0.46, 0.66), (0.33, 0.56), (0.07, 1.0), (0.0, 0.0)],
    "hsimple": [(1, 0), (0.55, 0.5), (0.3, 0.8), (0.05, 1.0), (0.0, 0.0)],
    "far": [(1, 0), (0.35, 1.0), (0.0, 0.0)],
}
ROWS_N = {"full": 6, "simple": 4, "hoch": 7, "hsimple": 5, "far": 3}
NA = {"full": 7, "simple": 5, "hoch": 9, "hsimple": 6, "far": 5}  # Ecken je Kronenring
# "far": einfachste Krone (5 Ecken, 3 Reihen, 10 Dreiecke + Stamm) für dichten Wald weiter weg (nur "synth_forest")
BUSH_ROWS = np.array([(1, 0), (0.62, 0.9), (0.0, 1.0)])  # offen unten (steht im Boden)

# Laubfarben (sRGB 0–1), Sommer: mehrere Grüntöne, leicht gelblich bis bläulich
DECID_COLS = np.array([(0.33, 0.45, 0.18), (0.29, 0.42, 0.17), (0.36, 0.48, 0.20), (0.27, 0.40, 0.19),
                       (0.39, 0.47, 0.17), (0.25, 0.38, 0.22), (0.31, 0.44, 0.15)])
CONIFER_COLS = np.array([(0.17, 0.29, 0.17), (0.15, 0.27, 0.20), (0.20, 0.31, 0.18), (0.18, 0.30, 0.22)])
POPLAR_COLS = np.array([(0.31, 0.44, 0.17), (0.34, 0.46, 0.19)])
PINE_COLS = np.array([(0.20, 0.31, 0.17), (0.23, 0.33, 0.18), (0.19, 0.30, 0.20)])  # Kiefer: dunkel, leicht oliv
BUSH_COLS = np.array([(0.32, 0.45, 0.19), (0.28, 0.41, 0.18), (0.35, 0.46, 0.20)])
TRUNK_COL = np.array([0.44, 0.38, 0.31])


def sun_enu():
    az, el = math.radians(SUN_AZ), math.radians(SUN_EL)
    return np.array([math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)])


# ============================================================================= Eingaben

class Ctx:
    def __init__(self, area_file):
        self.area_file = area_file
        self.cfg = load_area(area_file)
        a = self.cfg
        self.id = a["id"]
        self.crs = a.get("crs", "EPSG:2056")
        self.build = Path("build") / a["id"]
        self.out = self.build / "trees"
        self.out.mkdir(parents=True, exist_ok=True)
        self.raw = (Path.cwd() / a["data_dir"]).resolve()
        self.core = [float(v) for v in a["core_lv95"]]
        self.lake = float(a["lake_level_m"])
        e0, n0, e1, n1 = self.core
        self.origin = a.get("origin_lv95", [(e0 + e1) / 2, (n0 + n1) / 2])
        self.water = shape(json.loads((self.build / "water.geojson").read_text())["geometry"])
        feats = json.loads((self.build / "routes.geojson").read_text())["features"]
        self.routes = [LineString(f["geometry"]["coordinates"]) for f in feats]
        tlm = self.raw.parent / "swisstlm3d" / f"{a['id']}.gpkg"
        self.tlm = tlm if tlm.exists() else None

    def tlm_layer(self, layer, objektart=None, extra=None):
        """Geometrien (shapely) eines swissTLM3D-Layers, optional gefiltert; [] ohne gpkg/Layer."""
        if self.tlm is None:
            return []
        import pyogrio
        import shapely
        try:
            meta, _, geom, fields = pyogrio.raw.read(self.tlm, layer=layer)
        except Exception:
            return []
        names = list(meta["fields"])
        gs = shapely.from_wkb(geom)
        keep = np.ones(len(gs), bool)
        if objektart is not None:
            oa = fields[names.index("OBJEKTART")]
            keep &= np.isin(oa, objektart)
        if extra is not None:
            keep &= extra(names, fields)
        if objektart is None and extra is None:
            return list(gs)
        return [(g, fields[names.index("OBJEKTART")][i]) for i, g in enumerate(gs) if keep[i]]


def raster_profile(ctx, res, dtype, count=1):
    e0, n0, e1, n1 = ctx.core
    w, h = int(round((e1 - e0) / res)), int(round((n1 - n0) / res))
    return dict(driver="GTiff", width=w, height=h, count=count, dtype=dtype, crs=ctx.crs,
                transform=from_origin(e0, n1, res, res), compress="deflate", tiled=True,
                blockxsize=512, blockysize=512)


def tiles(ctx):
    e0, n0, e1, n1 = ctx.core
    for e in np.arange(e0, e1, TILE):
        for n in np.arange(n0, n1, TILE):
            yield float(e), float(n), float(min(e + TILE, e1)), float(min(n + TILE, n1))


def make_chm(ctx):
    """chm.tif = swissSURFACE3D Raster − swissALTI3D (beide 0,5 m, gleiche Kacheln), Kachel für Kachel."""
    f = ctx.build / "chm.tif"
    if f.exists():
        return f
    sdir, adir = ctx.raw / "surface_core", ctx.raw / "alti_core"
    if not sdir.exists():
        sys.exit(f"Fehlt: {sdir} (fetch.py mit Job surface_core) oder {f}")
    prof = raster_profile(ctx, RES, "float32")
    n_ok = 0
    with rasterio.open(f, "w", **prof) as dst:
        for b in tiles(ctx):
            key = f"_{int(b[0] // 1000)}-{int(b[1] // 1000)}_"
            s = [p for p in sdir.glob(f"*{key}0.5_*.tif")]
            a = [p for p in adir.glob(f"*{key}0.5_*.tif")]
            win = from_bounds(*b, dst.transform).round_offsets().round_lengths()
            out = np.zeros((int(win.height), int(win.width)), np.float32)
            if s and a:
                with rasterio.open(s[0]) as ss, rasterio.open(a[0]) as aa:
                    zs = ss.read(1, window=from_bounds(*b, ss.transform), out_shape=out.shape)
                    za = aa.read(1, window=from_bounds(*b, aa.transform), out_shape=out.shape)
                ok = (zs > -1000) & (za > -1000)
                out = np.where(ok, np.clip(zs - za, 0, 80), 0).astype(np.float32)
                n_ok += 1
            dst.write(out, 1, window=win)
    print(f"chm.tif: {prof['width']}×{prof['height']} px ({RES} m), {n_ok} Kacheln Oberflächenmodell", flush=True)
    return f


def make_ortho(ctx):
    f = ctx.build / "ortho_core.tif"
    if f.exists():
        return f
    idir = ctx.raw / "image_core"
    prof = raster_profile(ctx, 1.0, "uint8", 3)
    prof["photometric"] = "RGB"
    with rasterio.open(f, "w", **prof) as dst:
        for b in tiles(ctx):
            tp = ortho_tile(idir, b[0] // 1000, b[1] // 1000)
            hits = [tp] if tp is not None else []
            win = from_bounds(*b, dst.transform).round_offsets().round_lengths()
            shp = (3, int(win.height), int(win.width))
            img = np.zeros(shp, np.uint8)
            if hits:
                with rasterio.open(hits[0]) as src:
                    img = src.read([1, 2, 3], window=from_bounds(*b, src.transform), out_shape=shp,
                                   resampling=Resampling.average)
            dst.write(img, window=win)
    print("ortho_core.tif: 1 m", flush=True)
    return f


def make_building_mask(ctx):
    f = ctx.build / "building_mask.tif"
    if f.exists():
        return f
    from shapely.geometry import Polygon
    prof = raster_profile(ctx, RES, "uint8")
    polys = []
    for npz in sorted(ctx.build.glob("buildings_*.npz")):
        d = np.load(npz)
        for kind in ("roof", "wall"):
            v, fc = d[f"{kind}_v"], d[f"{kind}_f"]
            if len(fc) == 0:
                continue
            t = v[fc][:, :, :2]
            area2 = np.abs(np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]))
            polys += [Polygon(x) for x in t[area2 > 0.02]]
    m = rasterize(polys, out_shape=(prof["height"], prof["width"]), transform=prof["transform"]).astype(bool) \
        if polys else np.zeros((prof["height"], prof["width"]), bool)
    m = ndimage.binary_dilation(m, iterations=3)  # 1,5 m
    # Brücken (swissTLM3D Strassen/Bahnen mit Kunstbaute Brücke), 6 m beidseits der Achse
    br = []
    for layer in ("strasse", "eisenbahn"):
        br += [g for g, _ in ctx.tlm_layer(layer, extra=lambda nm, fl: np.char.find(
            np.asarray(fl[nm.index("KUNSTBAUTE")], dtype=str), "Bruecke") >= 0)]
    if br:
        m |= rasterize([g.buffer(6.0) for g in br], out_shape=m.shape, transform=prof["transform"]).astype(bool)
    with rasterio.open(f, "w", **prof) as dst:
        dst.write(m.astype(np.uint8), 1)
    print(f"building_mask.tif: {m.mean() * 100:.1f} % Gebäude/Brücken ({len(polys):,} Dreiecke, {len(br)} Brückenachsen)",
          flush=True)
    return f


# ============================================================================= Erkennung

def road_mask(ctx, shape_hw, transform):
    """Fahrbahnen (Strassen ≥ 4 m) nach swissTLM3D: dort keine Stämme."""
    widths = {"Autobahn": 11.0, "10m Strasse": 4.5, "8m Strasse": 3.5, "6m Strasse": 2.5, "4m Strasse": 1.6,
              "Ausfahrt": 3.0, "Einfahrt": 3.0}
    gs = ctx.tlm_layer("strasse", objektart=list(widths))
    if not gs:
        return np.zeros(shape_hw, bool)
    return rasterize([g.buffer(widths[o]) for g, o in gs], out_shape=shape_hw, transform=transform).astype(bool)


def detect(ctx, only=None):
    from skimage.segmentation import watershed
    t0 = time.time()
    chm_f, bm_f, or_f = make_chm(ctx), make_building_mask(ctx), make_ortho(ctx)
    forest = [g for g, _ in ctx.tlm_layer("bodenbedeckung", objektart=["Wald", "Gehoelzflaeche", "Gebueschwald",
                                                                       "Wald offen"])]
    veg_prof = raster_profile(ctx, 1.0, "uint8")
    veg_dst = rasterio.open(ctx.out / "veg.tif", "w", **veg_prof)
    T = {k: [] for k in ("x", "y", "h", "r", "kind", "green", "forest", "rgb", "shape", "rough", "tlm")}
    tlm_pts = [(g.x, g.y) for g in ctx.tlm_layer("einzelbaum")]
    n_rej = {"grau": 0, "klein": 0, "strasse": 0}
    with rasterio.open(chm_f) as cs, rasterio.open(bm_f) as bs, rasterio.open(or_f) as os_:
        for b in (only or tiles(ctx)):
            hb = (b[0] - HALO, b[1] - HALO, b[2] + HALO, b[3] + HALO)
            win = from_bounds(*hb, cs.transform).round_offsets().round_lengths()
            chm = cs.read(1, window=win, boundless=True, fill_value=0).astype(np.float32)
            bm = bs.read(1, window=win, boundless=True, fill_value=0).astype(bool)
            tr = cs.window_transform(win)
            H, W = chm.shape
            rgb = os_.read([1, 2, 3], window=from_bounds(*hb, os_.transform), out_shape=(3, H, W),
                           boundless=True, fill_value=0, resampling=Resampling.bilinear).astype(np.float32)
            wm = rasterize([ctx.water], out_shape=(H, W), transform=tr).astype(bool)
            fm = rasterize(forest, out_shape=(H, W), transform=tr).astype(bool) if forest else np.zeros((H, W), bool)
            rm = road_mask(ctx, (H, W), tr)
            s = rgb.sum(0)
            exg = (2 * rgb[1] - rgb[0] - rgb[2]) / np.maximum(s, 1)
            green = ((exg > 0.05) & (s > 45)) | ((exg > 0.02) & (s > 45) & (rgb[1] >= rgb[0]) & (rgb[1] >= rgb[2]))
            c = np.where(bm | wm, 0, chm)
            # Rauigkeit: Kronen (auch unbelaubt, Befliegung oft im Frühjahr) sind unruhig, Fahrzeuge, Zelte,
            # Kioske und Container glatt
            rough_px = np.abs(c - ndimage.gaussian_filter(c, 1.0))
            c = ndimage.grey_opening(c, footprint=disk(1))     # dünne Dinge (Masten, Leitungen) weg
            cs_ = ndimage.gaussian_filter(c, 2.0)
            tlm_r = np.zeros((H, W), bool)
            if tlm_pts:
                P = np.array(tlm_pts)
                cc_ = ((P[:, 0] - tr.c) / tr.a).astype(int); rr_ = ((P[:, 1] - tr.f) / tr.e).astype(int)
                okp = (cc_ >= 0) & (cc_ < W) & (rr_ >= 0) & (rr_ < H)
                tlm_r[rr_[okp], cc_[okp]] = True
            canopy = cs_ > 2.0
            # lokale Maxima mit höhenabhängigem Fenster
            mx3 = ndimage.maximum_filter(cs_, footprint=disk(5))   # r 2,5 m
            mx6 = ndimage.maximum_filter(cs_, footprint=disk(8))   # r 4 m
            peak = (cs_ >= 3.0) & canopy & (cs_ >= mx3 - 1e-4)
            peak &= (cs_ < 25.0) | (cs_ >= mx6 - 1e-4)
            pr, pc = np.nonzero(peak)
            # Plateaus: nur ein Maximum je zusammenhängender Fläche gleicher Höhe
            lab_p, n_p = ndimage.label(peak)
            if n_p == 0:
                write_veg(veg_dst, b, tr, H, W, canopy & green, green & (chm < 1.0) & ~bm & ~wm, None)
                continue
            first = ndimage.labeled_comprehension(np.arange(H * W).reshape(H, W), lab_p, np.arange(1, n_p + 1),
                                                  np.min, np.int64, -1)
            markers = np.zeros((H, W), np.int32)
            markers.flat[first] = np.arange(1, n_p + 1)
            seg_mask = canopy & (cs_ > 1.5)
            seg = watershed(-cs_, markers, mask=seg_mask)
            idx = np.arange(1, n_p + 1)
            area = ndimage.sum(seg_mask, seg, idx) * RES * RES
            hmax = ndimage.maximum(np.where(bm | wm, 0, chm) * seg_mask, seg, idx)
            hmean = ndimage.mean(cs_, seg, idx)
            gfrac = ndimage.mean(green, seg, idx)
            ffrac = ndimage.mean(fm, seg, idx)
            mr = [ndimage.mean(rgb[k], seg, idx) for k in range(3)]
            rmean = ndimage.mean(rough_px, seg, idx)
            tlm_hit = ndimage.maximum(tlm_r, seg, idx) > 0
            pr_, pc_ = np.unravel_index(first, (H, W))
            X = tr.c + (pc_ + 0.5) * tr.a
            Y = tr.f + (pr_ + 0.5) * tr.e
            inside = (X >= b[0]) & (X < b[2]) & (Y >= b[1]) & (Y < b[3])
            r = np.sqrt(area / np.pi)
            ok = inside & (area >= 4.0) & (hmax >= 3.0)
            n_rej["klein"] += int((inside & ~ok).sum())
            isgreen = (gfrac >= 0.3) | (ffrac >= 0.5) | (rmean >= ROUGH_MIN) | tlm_hit
            n_rej["grau"] += int((ok & ~isgreen).sum())
            ok &= isgreen
            # Stamm nicht auf der Fahrbahn: zum höchsten Kronenpixel ausserhalb verschieben, sonst weglassen
            onroad = rm[pr_, pc_] & ok
            for i in np.flatnonzero(onroad):
                sel = (seg == i + 1) & ~rm
                if sel.sum() >= 4:
                    rr, cc = np.nonzero(sel)
                    k = np.argmax(cs_[rr, cc])
                    pr_[i], pc_[i] = rr[k], cc[k]
                    X[i] = tr.c + (cc[k] + 0.5) * tr.a
                    Y[i] = tr.f + (rr[k] + 0.5) * tr.e
                else:
                    ok[i] = False
                    n_rej["strasse"] += 1
            sel = np.flatnonzero(ok)
            h = hmax[sel]
            rr = r[sel]
            ratio = h / (2 * rr)
            # Kronenprofil: mittlere Höhe auf dem Ring 0,35–0,65 r um die Spitze relativ zur Spitze
            # (Kegel bis fast zum Boden ≈ 0,5; Laubkrone mit Stamm ≈ 0,85–0,95)
            ay = np.zeros(n_p + 1); ax = np.zeros(n_p + 1); rs = np.ones(n_p + 1)
            ay[1:], ax[1:], rs[1:] = pr_, pc_, np.maximum(r / RES, 1)
            yy, xx = np.nonzero(seg)
            lb = seg[yy, xx]
            dd = np.hypot(yy - ay[lb], xx - ax[lb]) / rs[lb]
            ring = (dd > 0.35) & (dd < 0.65)
            num = np.bincount(lb[ring], weights=cs_[yy[ring], xx[ring]], minlength=n_p + 1)
            den = np.bincount(lb[ring], minlength=n_p + 1)
            pk = np.zeros(n_p + 1); pk[1:] = cs_[pr_, pc_]
            q = np.where(den > 3, num / np.maximum(den, 1) / np.maximum(pk, 1e-3), 1.0)[1:]
            fill = q[sel]
            col = np.stack([mr[k][sel] for k in range(3)], 1) / 255.0
            dark = col.sum(1) < 0.75
            kind = np.full(len(sel), DECID)
            kind[(ratio > 0.9) & (fill < 0.66) & (h > 6)] = CONIFER
            kind[(ratio > 0.75) & (fill < 0.6) & dark & (h > 8)] = CONIFER
            kind[(kind == DECID) & (ratio > 2.6) & (h > 15)] = POPLAR
            for k, v in (("x", X[sel]), ("y", Y[sel]), ("h", h), ("r", rr), ("kind", kind),
                         ("green", gfrac[sel]), ("forest", ffrac[sel] >= 0.5), ("rgb", col),
                         ("shape", fill), ("rough", rmean[sel]), ("tlm", tlm_hit[sel])):
                T[k].append(v)
            # Büsche: niedrige grüne Vegetation 1–3 m ausserhalb der Kronen
            low = (cs_ > 0.9) & (cs_ < 3.0) & green & ~bm & ~wm & (seg == 0) & ~rm
            lab_b, nb = ndimage.label(ndimage.binary_opening(low, iterations=1))
            if nb:
                bi = np.arange(1, nb + 1)
                ba = ndimage.sum(low, lab_b, bi) * RES * RES
                cy, cx = np.array(ndimage.center_of_mass(low, lab_b, bi)).T
                bh = ndimage.maximum(cs_, lab_b, bi)
                bmr = [ndimage.mean(rgb[k], lab_b, bi) for k in range(3)]
                BX = tr.c + (cx + 0.5) * tr.a
                BY = tr.f + (cy + 0.5) * tr.e
                kb = (ba >= 3.0) & (BX >= b[0]) & (BX < b[2]) & (BY >= b[1]) & (BY < b[3])
                # grosse Gebüschflächen: mehrere Büsche (je ~12 m²), auf der Fläche verteilt
                for i in np.flatnonzero(kb):
                    nsub = int(min(6, max(1, ba[i] // 12)))
                    if nsub == 1:
                        pts = [(BX[i], BY[i])]
                    else:
                        rr2, cc2 = np.nonzero(lab_b == i + 1)
                        pick = np.linspace(0, len(rr2) - 1, nsub).astype(int)
                        pts = [(tr.c + (cc2[p] + 0.5) * tr.a, tr.f + (rr2[p] + 0.5) * tr.e) for p in pick]
                    rb = min(3.0, math.sqrt(ba[i] / nsub / np.pi) * 1.1)
                    for (px, py) in pts:
                        T["x"].append([px]); T["y"].append([py]); T["h"].append([max(1.2, bh[i])])
                        T["r"].append([max(0.8, rb)]); T["kind"].append([BUSH]); T["green"].append([1.0])
                        T["forest"].append([False]); T["shape"].append([0.7]); T["rough"].append([0.0])
                        T["tlm"].append([False])
                        T["rgb"].append(np.array([[bmr[0][i], bmr[1][i], bmr[2][i]]]) / 255.0)
            write_veg(veg_dst, b, tr, H, W, (seg > 0) & np.isin(seg, sel + 1),
                      green & (cs_ < 1.0) & ~bm & ~wm, None)
            print(f"  Kachel {int(b[0])}/{int(b[1])}: {len(sel)} Bäume ({time.time() - t0:.0f} s)", flush=True)
    veg_dst.close()
    D = {k: np.concatenate(v) if v and np.ndim(v[0]) == 1 else (np.vstack(v) if v else np.zeros(0))
         for k, v in T.items()}
    D["kind"] = D["kind"].astype(np.int8)
    D["tlm"] = D["tlm"].astype(bool)
    D["forest"] = D["forest"].astype(bool)
    # Kronenradius begrenzen
    D["r"] = np.clip(D["r"] * 1.05, 0.8, 0.45 * D["h"] + 1.5)
    D["r"] = np.where(D["kind"] == POPLAR, np.minimum(D["r"], 0.22 * D["h"] + 0.5), D["r"])
    # Geländehöhe (lokal, Szene y = 0 = Wasser)
    with rasterio.open(ctx.build / "dem_core.tif") as s:
        dem, dtr = s.read(1), s.transform
    D["z"] = bilinear(dem, dtr, D["x"], D["y"]) - ctx.lake
    D["seed"] = (np.abs(np.round(D["x"] * 7.0).astype(np.int64) * 73856093 ^ np.round(D["y"] * 7.0).astype(np.int64)
                        * 19349663) % 2_147_483_647).astype(np.int64)
    if only:
        return D
    np.savez_compressed(ctx.out / "detected.npz", **D)
    stats = detection_stats(ctx, D, n_rej)
    print(f"Erkennung fertig in {time.time() - t0:.0f} s: {json.dumps(stats, ensure_ascii=False)}", flush=True)
    return D


def pine_mix(cfg):
    """Gebietsoption "tree_mix": "pine" (Kiefernwald, z. B. Brandenburg), "alpine" oder "broadleaf" (Laubbaum-Stadtgrün,
    z. B. Hamburg; siehe postprocess); ohne Angabe: "pine" ausserhalb der Schweiz (crs ≠ EPSG:2056)."""
    mix = cfg.get("tree_mix")
    if mix is None:
        mix = "pine" if cfg.get("crs", "EPSG:2056") != "EPSG:2056" else "alpine"
    return mix == "pine"


def postprocess(D, cfg=None):
    """Säulenförmige Bäume ausserhalb des Waldes = Pappel. Im geschlossenen Wald zerlegt die Watershed grosse Kronen oft in schmale Stücke: dort keine Pappeln, und die
    Krone mindestens 0,2 × Höhe breit (sonst wirkt der Wald wie lauter Säulen)."""
    f = D["forest"] & (D["kind"] != BUSH)
    # sehr schlank und hoch ausserhalb des Waldes = Säulenform (Pappelreihen an Quais), auch wenn das Profil spitz ist
    ratio = D["h"] / np.maximum(2 * D["r"], 0.1)
    col = ~f & (D["kind"] != BUSH) & (ratio > 2.6) & (D["h"] > 15)
    D["kind"] = np.where(col, POPLAR, D["kind"])
    D["kind"] = np.where(f & (D["kind"] == POPLAR), np.where(D["shape"] < 0.66, CONIFER, DECID), D["kind"]).astype(np.int8)
    D["r"] = np.where(f & (D["kind"] == DECID), np.maximum(D["r"], 0.2 * D["h"]), D["r"])
    # Watershed fasst in dichten Beständen mehrere Kronen zusammen: Kronenradius begrenzen
    # (Nadelbaum höchstens 0,15 × Höhe + 2 m, Laubbaum 0,35 × Höhe + 1,5 m), sonst stehen riesige Kegel am Ufer und ragen ins Bild (Stein am Rhein, 30 s)
    D["r"] = np.where(D["kind"] == CONIFER, np.minimum(D["r"], 0.15 * D["h"] + 2.0), D["r"])
    D["r"] = np.where(D["kind"] == DECID, np.minimum(D["r"], 0.35 * D["h"] + 1.5), D["r"])
    if cfg is not None and cfg.get("tree_mix") == "broadleaf":
        # Laubbaum-Stadtgrün (z. B. Hamburg: Linden, Eichen, Buchen, Weiden an der Alster, kaum Nadelholz): als
        # Nadelbaum gilt nur eine klar spitze, schlanke Krone (Profil < 0,5, Höhe > 1,2 × Breite); alles andere wird
        # Laubbaum mit der Kronenbegrenzung für Laubbäume. Pappeln (Säulenform) bleiben.
        ratio = D["h"] / np.maximum(2 * D["r"], 0.1)
        keep = (D["shape"] < 0.5) & (ratio > 1.2)
        D["kind"] = np.where((D["kind"] == CONIFER) & ~keep, DECID, D["kind"]).astype(np.int8)
        D["r"] = np.where(D["kind"] == DECID, np.minimum(D["r"], 0.35 * D["h"] + 1.5), D["r"])
    if cfg is not None and pine_mix(cfg):
        # Kiefernwald: schlanke hohe Kronen in waldartiger Dichte sind Kiefern, keine Pappeln. Pappel bleibt nur
        # einzeln oder in Reihen (wenige Nachbarn); dichte Bestände ohne TLM-Wald erkennt die Nachbarzahl.
        trees = D["kind"] != BUSH
        P = np.column_stack([D["x"], D["y"]])
        nb = np.zeros(len(P), int)
        linear = np.zeros(len(P), bool)
        ti = np.flatnonzero(trees)
        if len(ti):
            tr = cKDTree(P[ti])
            for k, idx in enumerate(tr.query_ball_point(P[ti], 15.0)):
                nb[ti[k]] = len(idx) - 1
                if len(idx) >= 4:   # Reihe (Allee, Uferreihe): Nachbarn liegen fast auf einer Linie
                    ev = np.linalg.eigvalsh(np.cov(P[ti[idx]].T))
                    linear[ti[k]] = ev[0] < 0.08 * ev[1]
        dense = ((nb >= 4) & ~linear) | D["forest"]
        ratio = D["h"] / np.maximum(2 * D["r"], 0.1)
        slim = trees & (ratio > 1.3) & (D["h"] > 10)
        pine = dense & slim & np.isin(D["kind"], [POPLAR, CONIFER, DECID]) & ((D["kind"] != DECID) | (ratio > 1.8))
        D["kind"] = np.where(pine, PINE, D["kind"]).astype(np.int8)
        D["r"] = np.where(D["kind"] == PINE, np.clip(D["r"], 1.5, 0.15 * D["h"] + 2.5), D["r"])
    if cfg is not None and cfg.get("tree_max_h_m"):
        # Gebietsoption "tree_max_h_m": höhere „Bäume“ ausserhalb des Waldes sind Gebäudeteile, die in den Grundrissen
        # fehlen oder neben ihnen liegen (Boston: OSM-Umrisse + laubfreies Lidar-DSM gaben 40–70 m hohe Säulen an
        # Hochhauswänden); sie fallen weg
        keep = D["forest"] | (D["h"] <= float(cfg["tree_max_h_m"]))
        n = len(keep)
        D = {k: (v[keep] if isinstance(v, np.ndarray) and v.shape[:1] == (n,) else v) for k, v in D.items()}
    if cfg is not None and cfg.get("landmarks") and len(D["x"]):
        # Wahrzeichen (landmarks.py): Oberflächen- minus Geländemodell zeigt Gitterturm, Riesenrad usw. als „Bäume“;
        # in den Freistellflächen der Wahrzeichen fallen alle Bäume weg
        import shapely
        from landmarks import clear_polygons
        zone = shapely.union_all([p for _, p in clear_polygons(cfg)])
        keep = ~shapely.contains_xy(zone, D["x"], D["y"])
        n = len(keep)
        print(f"  landmarks: {int((~keep).sum())} Bäume in Freistellflächen entfernt", flush=True)
        D = {k: (v[keep] if isinstance(v, np.ndarray) and v.shape[:1] == (n,) else v) for k, v in D.items()}
    if cfg is not None and cfg.get("tree_max_slope_deg") and len(D["x"]):
        # Gebietsoption "tree_max_slope_deg" (Fjorde): an fast senkrechten Wänden liefert Oberflächen- minus
        # Geländemodell Scheinkronen (wenige Meter Versatz = Dutzende Meter „Baumhöhe“); sie hängen als lange Säulen
        # an der Wand. Bäume, wo das Gelände (5 m geglättet) steiler ist als der Wert, fallen weg.
        with rasterio.open(Path("build") / cfg["id"] / "dem_core.tif") as src:
            dem = ndimage.uniform_filter(src.read(1).astype(np.float32), 5)
            px = abs(src.transform.a)
            gy, gx = np.gradient(dem, px)
            slope = np.degrees(np.arctan(np.hypot(gx, gy)))
            rows, cols = rasterio.transform.rowcol(src.transform, D["x"], D["y"])
        rows = np.clip(np.asarray(rows), 0, slope.shape[0] - 1)
        cols = np.clip(np.asarray(cols), 0, slope.shape[1] - 1)
        keep = slope[rows, cols] <= float(cfg["tree_max_slope_deg"])
        n = len(keep)
        print(f"  tree_max_slope_deg: {int((~keep).sum())} von {n} Bäumen an steilen Wänden entfernt", flush=True)
        D = {k: (v[keep] if isinstance(v, np.ndarray) and v.shape[:1] == (n,) else v) for k, v in D.items()}
    return D


def write_veg(dst, b, tr, H, W, crown, low, _):
    """veg.tif (1 m) im Innenbereich der Kachel schreiben: 2 Krone, 1 niedrige Vegetation."""
    v = np.zeros((H, W), np.uint8)
    v[low] = 1
    v[crown] = 2
    h2 = H // 2 * 2
    w2 = W // 2 * 2
    # 0,5 m → 1 m: Mehrheit (Krone vor Rasen)
    blk = v[:h2, :w2].reshape(h2 // 2, 2, w2 // 2, 2)
    v1 = np.where((blk == 2).sum((1, 3)) >= 2, 2, np.where((blk >= 1).sum((1, 3)) >= 2, 1, 0)).astype(np.uint8)
    halo = int(HALO)
    inner = v1[halo:halo + int(b[3] - b[1]), halo:halo + int(b[2] - b[0])]
    win = from_bounds(*b, dst.transform).round_offsets().round_lengths()
    dst.write(inner[:int(win.height), :int(win.width)], 1, window=win)


def disk(r):
    y, x = np.mgrid[-r:r + 1, -r:r + 1]
    return (x * x + y * y) <= r * r + 0.5


def bilinear(arr, tr, e, n):
    col = (e - tr.c) / tr.a - 0.5
    row = (n - tr.f) / tr.e - 0.5
    c0 = np.clip(np.floor(col).astype(int), 0, arr.shape[1] - 2)
    r0 = np.clip(np.floor(row).astype(int), 0, arr.shape[0] - 2)
    fc = np.clip(col - c0, 0, 1)
    fr = np.clip(row - r0, 0, 1)
    a = arr[r0, c0] * (1 - fc) + arr[r0, c0 + 1] * fc
    b = arr[r0 + 1, c0] * (1 - fc) + arr[r0 + 1, c0 + 1] * fc
    return a * (1 - fr) + b * fr


def detection_stats(ctx, D, n_rej):
    st = {"baeume": int((D["kind"] != BUSH).sum()), "buesche": int((D["kind"] == BUSH).sum()),
          "je_art": {KIND_NAMES[k]: int((D["kind"] == k).sum()) for k in KIND_NAMES},
          "im_wald": int((D["forest"] & (D["kind"] != BUSH)).sum()),
          "hoehe_median_m": round(float(np.median(D["h"][D["kind"] != BUSH])), 1) if len(D["h"]) else 0,
          "radius_median_m": round(float(np.median(D["r"][D["kind"] != BUSH])), 1) if len(D["r"]) else 0,
          "verworfen": n_rej}
    pts = ctx.tlm_layer("einzelbaum")
    if pts:
        e0, n0, e1, n1 = ctx.core
        P = np.array([[g.x, g.y] for g in pts])
        P = P[(P[:, 0] >= e0) & (P[:, 0] < e1) & (P[:, 1] >= n0) & (P[:, 1] < n1)]
        trees = D["kind"] != BUSH
        if len(P) and trees.any():
            tree = cKDTree(np.column_stack([D["x"][trees], D["y"][trees]]))
            d, _ = tree.query(P)
            st["tlm_einzelbaeume"] = int(len(P))
            st["tlm_davon_erkannt_4m"] = int((d <= 4.0).sum())
            st["tlm_anteil_erkannt"] = round(float((d <= 4.0).mean()), 3)
    (ctx.out / "stats.json").write_text(json.dumps(st, indent=1, ensure_ascii=False))
    return st


# ============================================================================= Auswahl je Stufe

def route_samples(ctx, step=25.0):
    pts = []
    for r in ctx.routes:
        n = max(2, int(r.length / step))
        for d in np.linspace(0, r.length, n):
            p = r.interpolate(d)
            pts.append((p.x, p.y))
    return np.array(pts)


def dist_to_routes(ctx, x, y):
    s = route_samples(ctx, 5.0)
    d, _ = cKDTree(s).query(np.column_stack([x, y]))
    return d


def lane_samples(ctx, step=2.0, back_off=12.0):
    """Punkte auf Hin- und Rückfahrt (App: Rückfahrt 12 m links der Hinfahrt)."""
    pts = []
    for r in ctx.routes:
        n = max(2, int(r.length / step))
        ds = np.linspace(0, r.length, n)
        P = np.array([(r.interpolate(d).x, r.interpolate(d).y) for d in ds])
        t = np.gradient(P, axis=0)
        t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-9)
        pts += [P, P + np.column_stack([-t[:, 1], t[:, 0]]) * back_off]
    return np.vstack(pts)


def crown_rim(D):
    """Äusserster Kronenrand vom Stamm aus (Radius mit Streuung und Beulen, Schieflage)."""
    return 1.25 * D["r"] + 0.03 * D["h"]


def visibility(ctx, D, cand, occ_v, occ_f, procs, max_d):
    """Bäume, deren Krone von mindestens einem Punkt der Strecke (2,2 m über Wasser) frei zu sehen ist."""
    import warp as wp
    S = route_samples(ctx, 25.0)
    tree = cKDTree(S)
    idx = np.flatnonzero(cand)
    O, Tt, owner = [], [], []
    for i in idx:
        near = tree.query_ball_point([D["x"][i], D["y"][i]], max_d)
        if not near:
            continue
        near = np.array(near)[np.linspace(0, len(near) - 1, min(len(near), 10)).astype(int)]
        zc = D["z"][i] + 0.75 * D["h"][i]
        for j in near:
            o = np.array([S[j, 0] - ctx.origin[0], S[j, 1] - ctx.origin[1], 2.2])
            for dz in (0.0, -0.3 * D["h"][i]):
                t = np.array([D["x"][i] - ctx.origin[0], D["y"][i] - ctx.origin[1], zc + dz])
                O.append(o); Tt.append(t); owner.append(i)
    vis = np.zeros(len(D["x"]), bool)
    if not O:
        return vis
    O = np.array(O, np.float32); Tt = np.array(Tt, np.float32); owner = np.array(owner)
    wp.init()
    mesh = wp.Mesh(points=wp.array(occ_v.astype(np.float32), dtype=wp.vec3, device=DEVICE),
                   indices=wp.array(occ_f.astype(np.int32).ravel(), dtype=int, device=DEVICE))
    out = wp.zeros(len(O), dtype=wp.int32, device=DEVICE)
    wp.launch(k_seg, len(O), [mesh.id, wp.array(O, dtype=wp.vec3, device=DEVICE),
                              wp.array(Tt, dtype=wp.vec3, device=DEVICE), out], device=DEVICE)
    free = out.numpy() > 0
    vis[owner[free]] = True
    print(f"  Sichtbarkeit: {len(O):,} Strahlen, {vis[idx].sum():,} von {len(idx):,} Kandidaten frei sichtbar",
          flush=True)
    return vis


def _warp_kernels():
    import warp as wp
    wp.config.quiet = True

    @wp.kernel
    def k_seg_(mid: wp.uint64, o: wp.array(dtype=wp.vec3), t: wp.array(dtype=wp.vec3),
               out: wp.array(dtype=wp.int32)):
        i = wp.tid()
        d = t[i] - o[i]
        L = wp.length(d)
        q = wp.mesh_query_ray(mid, o[i], d / L, L - 1.0)
        out[i] = 1
        if q.result:
            out[i] = 0

    @wp.func
    def tangent_of(n: wp.vec3):
        a = wp.vec3(1.0, 0.0, 0.0)
        if wp.abs(n[0]) > 0.9:
            a = wp.vec3(0.0, 1.0, 0.0)
        return wp.normalize(wp.cross(a, n))

    @wp.kernel
    def k_light_(mid: wp.uint64, pos: wp.array(dtype=wp.vec3), nrm: wp.array(dtype=wp.vec3), side: int,
                 r_ao: float, t_sky: float, sun: wp.vec3, n_sun: int, cone: float, eps: float, seed: int,
                 out: wp.array(dtype=wp.vec3)):
        """(Umgebungsverdeckung, Himmelssichtbarkeit, Sonne sichtbar) je Ecke."""
        i = wp.tid()
        st = wp.rand_init(seed, i)
        n = nrm[i]
        t = tangent_of(n)
        b = wp.cross(n, t)
        o = pos[i] + n * eps
        rot = wp.randf(st)
        occ = float(0.0)
        up = float(0.0)
        free = float(0.0)
        for ia in range(side):
            for ib in range(side):
                u1 = (float(ia) + wp.randf(st)) / float(side)
                u2 = (float(ib) + wp.randf(st)) / float(side)
                r = wp.sqrt(u1)
                phi = 6.2831853 * (u2 + rot)
                d = t * (r * wp.cos(phi)) + b * (r * wp.sin(phi)) + n * wp.sqrt(wp.max(0.0, 1.0 - u1))
                q = wp.mesh_query_ray(mid, o, d, t_sky)
                hit = float(0.0)
                if q.result:
                    hit = 1.0
                    if q.t < r_ao:
                        occ += 1.0 - q.t / r_ao
                if d[2] > 0.0:
                    up += 1.0
                    free += 1.0 - hit
        cnt = float(0.0)
        for k in range(n_sun):
            jit = wp.vec3(wp.randf(st) - 0.5, wp.randf(st) - 0.5, wp.randf(st) - 0.5) * (2.0 * cone)
            ds = wp.normalize(sun + jit)
            qs = wp.mesh_query_ray(mid, pos[i] + ds * 0.3, ds, t_sky)
            if not qs.result:
                cnt += 1.0
        sky = float(1.0)
        if up > 0.0:
            sky = free / up
        out[i] = wp.vec3(1.0 - occ / float(side * side), sky, cnt / float(n_sun))

    return k_seg_, k_light_


k_seg = k_light = None


def init_warp():
    global k_seg, k_light
    import warp as wp
    wp.init()
    if k_seg is None:
        k_seg, k_light = _warp_kernels()


_RT = {}


def _light_worker(args):
    import warp as wp
    lo, hi = args
    st = _RT
    n = hi - lo
    out = wp.zeros(n, dtype=wp.vec3, device="cpu")
    wp.launch(k_light, n, [st["mesh"].id, wp.array(st["pos"][lo:hi], dtype=wp.vec3, device="cpu"),
                           wp.array(st["nrm"][lo:hi], dtype=wp.vec3, device="cpu"), 5, 6.0, 300.0,
                           wp.vec3(*sun_enu()), 6, SUN_CONE, 0.12, lo + 11, out], device="cpu")
    wp.synchronize()
    return lo, out.numpy()


def trace_light(verts, faces, pos, nrm, procs):
    import warp as wp
    t0 = time.time()
    mesh = wp.Mesh(points=wp.array(verts.astype(np.float32), dtype=wp.vec3, device=DEVICE),
                   indices=wp.array(faces.astype(np.int32).ravel(), dtype=int, device=DEVICE))
    n = len(pos)
    if DEVICE != "cpu":
        out = wp.zeros(n, dtype=wp.vec3, device=DEVICE)
        wp.launch(k_light, n, [mesh.id, wp.array(pos.astype(np.float32), dtype=wp.vec3, device=DEVICE),
                               wp.array(nrm.astype(np.float32), dtype=wp.vec3, device=DEVICE), 5, 6.0, 300.0,
                               wp.vec3(*sun_enu()), 6, SUN_CONE, 0.12, 11, out], device=DEVICE)
        res = out.numpy()
    else:
        _RT.update(mesh=mesh, pos=pos.astype(np.float32), nrm=nrm.astype(np.float32))
        _light_worker((0, min(n, 8)))
        chunk = max(2000, n // (procs * 6))
        res = np.zeros((n, 3), np.float32)
        with mp.get_context("fork").Pool(procs) as pool:
            for lo, r in pool.imap_unordered(_light_worker, [(lo, min(n, lo + chunk)) for lo in range(0, n, chunk)]):
                res[lo:lo + len(r)] = r
    print(f"  Licht: {n:,} Ecken, {len(faces):,} Dreiecke im Strahlenmodell, {n * 31 / 1e6:.0f} Mio. Strahlen, "
          f"{time.time() - t0:.0f} s", flush=True)
    return res


# ============================================================================= Geometrie

def crown_rows(kind, form, variant):
    n = ROWS_N[form]
    if kind == CONIFER:
        return np.array(CONE_ROWS[form], float)
    if kind == BUSH:
        return BUSH_ROWS
    if kind == PINE:   # Kiefer: rundliche, oben flache Krone erst im oberen Drittel
        return _broad(n)
    if kind == POPLAR:
        p = _round(n)
        p[:, 1] = np.sin(np.linspace(0, np.pi, n)) ** 0.8
        return p
    return [_round, _egg, _broad][variant](n)


def tris_for(kind, form, trunk_sides):
    na = NA[form]
    if kind == BUSH:
        na = 6 if form in ("full", "simple") else 8
        rows = len(BUSH_ROWS)
        return na + 2 * na * (rows - 2)
    rows = len(crown_rows(kind, form, 0))
    return 2 * na + 2 * na * (rows - 3) + 2 * trunk_sides


def build_tree(D, i, form, trunk_sides, sink):
    """Eine Krone (Gitter Reihen × (na+1), Naht doppelt) und ein Stamm. Liefert dict mit V, N, F, grid (R, C), trunk."""
    kind = int(D["kind"][i])
    rng = np.random.default_rng(int(D["seed"][i]))
    variant = int(D["seed"][i] % 3)
    rows = crown_rows(kind, form, variant)
    na = NA[form]
    if kind == BUSH:
        na = 6 if form in ("full", "simple") else 8
    h, r = float(D["h"][i]), float(D["r"][i])
    x, y, z = float(D["x"][i]), float(D["y"][i]), float(D["z"][i])
    if kind == BUSH:
        zb, zt = z - 0.25, z + h
    else:
        cb = {DECID: (0.33, 0.30, 0.42)[variant], CONIFER: 0.08, POPLAR: 0.12, PINE: 0.64}[kind]
        cb = cb * (0.85 + 0.3 * rng.random())
        if "cbf" in D and D["cbf"][i] > 0:   # synth_forest: Kronenansatz je Baum (Stämme im Wasser sichtbar)
            cb = float(D["cbf"][i])
        zb, zt = z + cb * h, z + h
    hc = zt - zb
    rx = r * (0.92 + 0.16 * rng.random())
    ry = r * (0.92 + 0.16 * rng.random())
    rot = rng.random() * 2 * np.pi
    nr = len(rows)
    ang = rot + np.arange(na + 1) * 2 * np.pi / na
    noise = 1.0 + (0.16 if kind in (DECID, BUSH) else 0.08) * (rng.random((nr, na)) - 0.5) * 2
    noise = np.concatenate([noise, noise[:, :1]], 1)
    zn = (rng.random((nr, na)) - 0.5) * (0.08 * hc if kind != CONIFER else 0.03 * hc)
    zn = np.concatenate([zn, zn[:, :1]], 1)
    zn[0] = 0; zn[-1] = 0
    rho = rows[:, 1:2] * noise
    zz = zb + rows[:, 0:1] * hc + zn
    lean = (rng.random(2) - 0.5) * 0.06 * h   # leicht schief
    if "lean" in D:   # synth_forest: Igapó-Bäume stehen schiefer
        lean = lean * float(D["lean"][i])
    px = x + lean[0] * rows[:, 0:1] + rho * rx * np.cos(ang)[None]
    py = y + lean[1] * rows[:, 0:1] + rho * ry * np.sin(ang)[None]
    V = np.stack([px, py, np.broadcast_to(zz, px.shape)], -1).reshape(-1, 3)
    # weiche Normalen: Gradient eines Ellipsoids (Krone wirkt rund, die Sonne der App schattiert sanft)
    zc = zb + 0.5 * hc
    if kind == CONIFER:
        rad = np.stack([np.cos(ang), np.sin(ang)], -1)[None].repeat(nr, 0).reshape(-1, 2)
        N = np.column_stack([rad * hc, np.full(len(rad), 1.1 * r)])
        N[:na + 1] = [0, 0, 1]
        N[-(na + 1):] = [0, 0, -1]
    else:
        dz = (V[:, 2] - zc) / max(hc / 2, 0.3)
        N = np.column_stack([(V[:, 0] - x) / max(rx, 0.3), (V[:, 1] - y) / max(ry, 0.3), dz * 1.15])
        if kind == BUSH:
            N[:, 2] = np.maximum(N[:, 2], 0.25)
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-6)
    # Dreiecke (gegen den Uhrzeigersinn von aussen)
    C = na + 1
    F = []
    for k in range(nr - 1):
        for j in range(na):
            a, b_, c, d = k * C + j, k * C + j + 1, (k + 1) * C + j, (k + 1) * C + j + 1
            if k == 0:
                F.append([a, c, d])
            elif k == nr - 2 and rows[-1, 1] < 1e-6:
                F.append([a, c, b_])
            else:
                F += [[a, c, d], [a, d, b_]]
    F = np.array(F, np.int64)
    # Ausrichtung prüfen (nach aussen)
    cen = V[F].mean(1)
    fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    out_dir = cen - np.array([x, y, zc])
    if (np.einsum("ij,ij->i", fn, out_dir) < 0).mean() > 0.5:
        F = F[:, [0, 2, 1]]
    t = None
    if kind != BUSH and trunk_sides:
        tr_r = float(np.clip(0.045 * h, 0.12, 0.45)) if "trunk_r" not in D else float(D["trunk_r"][i])
        ta = rot + np.arange(trunk_sides) * 2 * np.pi / trunk_sides
        z0, z1 = z - sink, zb + 0.35 * hc
        bot = np.column_stack([x + tr_r * np.cos(ta), y + tr_r * np.sin(ta), np.full(trunk_sides, z0)])
        top = np.column_stack([x + lean[0] * 0.35 + 0.7 * tr_r * np.cos(ta), y + lean[1] * 0.35 + 0.7 * tr_r * np.sin(ta),
                               np.full(trunk_sides, z1)])
        TN = np.column_stack([np.cos(ta), np.sin(ta), np.zeros(trunk_sides)])
        st = float(D["stain_m"][i]) if "stain_m" in D else 0.0
        if st > 0 and z0 < z + st < z1:
            # Igapó: dunkler Wasserrand am Stamm (unteres Stück eigene Farbe): Ringe unten, Rand (2×), oben
            f = (z + st - z0) / (z1 - z0)
            mid = bot + (top - bot) * f
            TV = np.vstack([bot, mid, mid, top])
            TN = np.vstack([TN, TN, TN, TN])
            TF = []
            for j in range(trunk_sides):
                j2 = (j + 1) % trunk_sides
                for a0, a1 in ((0, 1), (2, 3)):
                    TF += [[a0 * trunk_sides + j, a0 * trunk_sides + j2, a1 * trunk_sides + j2],
                           [a0 * trunk_sides + j, a1 * trunk_sides + j2, a1 * trunk_sides + j]]
            t = (TV, TN, np.array(TF, np.int64), 2 * trunk_sides)   # die ersten 2·n Ecken: Wasserrand
        else:
            TV = np.vstack([bot, top])
            TN = np.vstack([TN, TN])
            TF = []
            for j in range(trunk_sides):
                j2 = (j + 1) % trunk_sides
                TF += [[j, j2, trunk_sides + j2], [j, trunk_sides + j2, trunk_sides + j]]
            t = (TV, TN, np.array(TF, np.int64))
    return dict(V=V, N=N, F=F, R=nr, C=C, rows=rows, trunk=t, kind=kind)


# ============================================================================= Stufe bauen

def select(ctx, D, level, occ_v, occ_f, procs):
    q = dict(LEVELS[level])
    q["budget"] = int(ctx.cfg.get("trees_budget", {}).get(level, q["budget"]))
    d = dist_to_routes(ctx, D["x"], D["y"])
    isbush = D["kind"] == BUSH
    cand = np.where(isbush, d <= q["bush_m"], (d <= q["near_m"]) | ((d <= q["mid_m"]) & (D["h"] >= q["mid_min_h"])))
    synth = ctx.cfg.get("synth_forest")
    flood = D["flood"].astype(bool) if "flood" in D else np.zeros(len(D["x"]), bool)
    cand &= (D["z"] > 0.1) | flood   # nicht im Wasser (ausser Igapó: "synth_forest", Stamm im Wasser)
    # Korridor um Hin- und Rückfahrt: kein Kronenrand näher als LANE_CLEAR_M (Kamera 4,5 m hinter, 2,2 m über dem
    # Boot; eine nahe Krone deckt sonst HUD und Navigator zu)
    dl, _ = cKDTree(lane_samples(ctx)).query(np.column_stack([D["x"], D["y"]]))
    if synth:
        # Igapó (nah vorbeirudern, Falk 27.11.2026): nur die Stämme halten lane_clear_m frei; Kronen dürfen über die
        # Bahn ragen, wenn ihr Ansatz hoch genug liegt (low_crown_clear_m über dem Wasser), sonst werden sie kleiner
        lc = float(synth.get("lane_clear_m", 3.0))
        too_close = cand & (dl - D["trunk_r"] < lc)
        cb_abs = D["z"] + D["cbf"] * D["h"]
        low = cb_abs < float(synth.get("low_crown_clear_m", 5.0))
        rmax = np.maximum((dl - 1.0) / 1.25, 0.8)
        D["r"] = np.where(low & (crown_rim(D) > dl - 1.0), np.minimum(D["r"], rmax), D["r"])
    else:
        # Gebietsoption "tree_lane_clear_m" (Grachten Amsterdam: Ulmen am Kai stehen 6–10 m von der Bahn): kleinerer
        # Korridor, dann ohne die Regel „halbe Baumhöhe“
        lc = float(ctx.cfg.get("tree_lane_clear_m", LANE_CLEAR_M))
        hf = 0.5 if "tree_lane_clear_m" not in ctx.cfg else 0.0
        too_close = cand & (dl - crown_rim(D) < np.maximum(lc, hf * D["h"]))   # hohe Bäume: halbe Höhe
    cand &= ~too_close
    corr = f"{float(synth.get('lane_clear_m', 3.0)):.0f} m um die Stämme" if synth else \
        f"{LANE_CLEAR_M:.0f} m (bzw. halbe Baumhöhe)"
    print(f"[{level}] Korridor {corr} um Hin- und Rückfahrt: {int(too_close.sum())} Bäume/Büsche entfernt", flush=True)
    vis = visibility(ctx, D, cand, occ_v, occ_f, procs, max_d=q["mid_m"] + 200)
    sel = cand & vis
    form = np.where(d <= q["near_m"], 1, 2)   # 1 voll, 2 einfach
    if synth:
        # dichter Wald: volle Form nur bis full_m, einfache bis far_from_m, dahinter die einfachste (3)
        def lv(key, default):
            v = synth.get(key, default)
            return float(v.get(level, default) if isinstance(v, dict) else v)
        form = np.where(d <= lv("full_m", q["near_m"]), 1, np.where(d <= lv("far_from_m", 1e9), 2, 3))
    prio = np.where(isbush, 0.35, 1.0) * D["h"] / np.maximum(d, 40.0) + np.where(form == 1, 10.0, 0.0)
    order = np.flatnonzero(sel)[np.argsort(-prio[sel])]
    fulln, simpn = q["full"][1], q["simple"][1]
    fname = {1: fulln, 2: simpn, 3: "far"}
    total = 0
    chosen = np.zeros(len(D["x"]), np.int8)
    for i in order:
        k = int(D["kind"][i])
        f = fname[int(form[i])]
        tt = tris_for(k, f, q["trunk_sides"] if form[i] == 1 else 3)
        if synth and flood[i] and "stain_m" in D:
            tt += 2 * (q["trunk_sides"] if form[i] == 1 else 3)   # Wasserrand am Stamm
        if total + tt > q["budget"]:
            if form[i] in (1, 2) and k != BUSH:
                nf = 3 if (synth or form[i] == 2) else 2
                if nf == 3 and not synth:
                    continue
                tt = tris_for(k, fname[nf], 3)
                if total + tt > q["budget"]:
                    continue
                form[i] = nf
            else:
                continue
        chosen[i] = form[i]
        total += tt
    print(f"[{level}] Auswahl: {int((chosen == 1).sum()):,} voll, {int((chosen == 2).sum()):,} einfach, "
          f"{int((chosen == 3).sum()):,} fern "
          f"(davon Büsche {int(((chosen > 0) & isbush).sum()):,}), ≈ {total:,} Dreiecke (Budget {q['budget']:,})",
          flush=True)
    return chosen, d, q


def tree_albedo(D, i, rng):
    k = int(D["kind"][i])
    pal = {DECID: DECID_COLS, CONIFER: CONIFER_COLS, POPLAR: POPLAR_COLS, BUSH: BUSH_COLS, PINE: PINE_COLS}[k]
    base = pal[int(D["seed"][i] // 7) % len(pal)].copy()
    photo = np.asarray(D["rgb"][i], float)
    exg = (2 * photo[1] - photo[0] - photo[2]) / max(photo.sum(), 1e-3)
    if photo.sum() > 0.15 and exg > 0.03:   # nur belaubte Kronen (Befliegung teils im Frühjahr)
        # Farbton aus dem Luftbild (z. B. Blutbuche), Helligkeit von der Palette
        pn = photo / max(photo.mean(), 1e-3) * base.mean()
        base = 0.72 * base + 0.28 * np.clip(pn, 0, 1)
    base *= 1.0 + 0.2 * rng.random()   # 1,0–1,2: Sommerlaub kräftig, nicht trist
    return np.clip(base, 0.05, 0.8)


def build_level(ctx, D, level, procs, bvh_cache):
    t0 = time.time()
    occ_v, occ_f = bvh_cache
    chosen, dist, q = select(ctx, D, level, occ_v, occ_f, procs)
    idx = np.flatnonzero(chosen > 0)
    ox, oy = ctx.origin
    trees = []
    for i in idx:
        form = {1: q["full"][1], 2: q["simple"][1], 3: "far"}[int(chosen[i])]
        sink = 0.8 if dist[i] <= 400 else 1.6   # Gelände ist vereinfacht: Stamm reicht sicher in den Boden
        t = build_tree(D, i, form, q["trunk_sides"] if chosen[i] == 1 else 3, sink)
        t["i"] = i
        t["form"] = form
        trees.append(t)
    # Strahlenmodell: alle Bäume dieser Stufe + Gebäude + Gelände
    TV = [t["V"] for t in trees] + [t["trunk"][0] for t in trees if t["trunk"] is not None]
    TF = []
    off = 0
    for t in trees:
        TF.append(t["F"] + off); off += len(t["V"])
    for t in trees:
        if t["trunk"] is not None:
            TF.append(t["trunk"][2] + off); off += len(t["trunk"][0])  # noqa: E702
    tv = np.vstack(TV) - np.array([ox, oy, 0.0])
    tf = np.vstack(TF)
    allv = np.vstack([occ_v, tv]); allf = np.vstack([occ_f, tf + len(occ_v)])
    cv = np.vstack([t["V"] for t in trees]) - np.array([ox, oy, 0.0])
    cn = np.vstack([t["N"] for t in trees])
    light = trace_light(allv, allf, cv, cn, procs)
    ao, sky, sunv = light[:, 0], light[:, 1], light[:, 2]
    facing = (cn @ sun_enu()) > 0
    occl = ao * (0.55 + 0.45 * sky)
    s_amb = 1.0 - 0.8 * (1.0 - occl)
    s_sun = np.where(facing, s_amb * (1.0 - 0.5 * (1.0 - sunv)), s_amb)
    # Gruppen je Zelle
    e0, n0 = ctx.core[0], ctx.core[1]
    cell = {}
    for t in trees:
        gx = int(math.floor((D["x"][t["i"]] - e0) / CELL)); gy = int(math.floor((D["y"][t["i"]] - n0) / CELL))
        cell.setdefault((gx, gy), []).append(t)
    starts = np.cumsum([0] + [len(t["V"]) for t in trees])
    for k, t in enumerate(trees):
        t["sl"] = slice(starts[k], starts[k + 1])
    out_s, out_a = ctx.out / level, ctx.out / f"{level}-ambient"
    for od in (out_s, out_a):
        od.mkdir(parents=True, exist_ok=True)
        for f in od.glob("tree_*.jpg"):
            f.unlink()
    save, meta_m = {}, []
    n_tris = 0
    for (gx, gy), ts in sorted(cell.items()):
        name = f"tree_{gx + 100}_{gy + 100}"
        # Atlas: Kronen-Flecken (C × R Texel) zeilenweise, darunter ein Texelstreifen für die Stämme
        sizes = [(t["C"], t["R"]) for t in ts]
        texels = sum(w * h for w, h in sizes) + 2 * len(ts)
        AW = 128
        while AW * AW < texels * 1.3 and AW < 2048:
            AW *= 2
        x = y = row_h = 0
        pos = []
        for (w, h) in sizes:
            if x + w > AW:
                y += row_h; x = 0; row_h = 0
            pos.append((x, y)); x += w; row_h = max(row_h, h)
        y += row_h
        trunk_y0 = y
        AH = trunk_y0 + int(math.ceil(2 * len(ts) / AW))
        AH = int(math.ceil(AH / 8.0) * 8)
        img_s = np.zeros((AH, AW, 3), np.float32)
        img_a = np.zeros((AH, AW, 3), np.float32)
        Vs, Ns, UVs, Fs = [], [], [], []
        off = 0
        for k, (t, (px, py)) in enumerate(zip(ts, pos)):
            i = t["i"]
            rng = np.random.default_rng(int(D["seed"][i]) + 99)
            alb = tree_albedo(D, i, rng)
            R, C = t["R"], t["C"]
            rows = t["rows"]
            # Krone innen dunkler: unten 0,62, oben 1,0; dazu feine Fleckung (Blattbüschel)
            zrel = np.repeat(rows[:, 0], C)
            inner = 0.68 + 0.32 * zrel ** 0.7
            fleck = 1.0 + 0.09 * (rng.random(R * C) - 0.5) * 2
            tint = 1.0 + 0.05 * (rng.random((R * C, 3)) - 0.5) * 2
            # Naht: gleiche Werte in der doppelten Spalte
            g2 = (inner * fleck)[:, None] * tint
            g2 = g2.reshape(R, C, 3); g2[:, -1] = g2[:, 0]; g2 = g2.reshape(-1, 3)
            col_s = alb * g2 * s_sun[t["sl"]][:, None]
            col_a = alb * g2 * s_amb[t["sl"]][:, None]
            img_s[py:py + R, px:px + C] = col_s.reshape(R, C, 3)
            img_a[py:py + R, px:px + C] = col_a.reshape(R, C, 3)
            rr, cc = np.divmod(np.arange(R * C), C)
            uv = np.column_stack([(px + cc + 0.5) / AW, 1.0 - (py + rr + 0.5) / AH])
            Vs.append(t["V"]); Ns.append(t["N"]); UVs.append(uv); Fs.append(t["F"] + off); off += len(t["V"])
            if t["trunk"] is not None:
                TVv, TNn, TFf = t["trunk"][:3]
                ty, tx = divmod(2 * k, AW)
                ty += trunk_y0
                tcol = D["trunk_rgb"][i] if "trunk_rgb" in D else TRUNK_COL
                floor_ = 0.35 if "trunk_rgb" in D else 0.6   # synth_forest: Stämme im Waldinneren dunkler
                tc = tcol * (0.85 + 0.3 * rng.random()) * float(np.clip(s_amb[t["sl"]].min() + 0.2, floor_, 1.0))
                img_s[ty, tx] = tc; img_a[ty, tx] = tc
                uv_t = np.tile([(tx + 0.5) / AW, 1.0 - (ty + 0.5) / AH], (len(TVv), 1))
                if len(t["trunk"]) == 4:   # Wasserrand: zweiter Texel, dunkel und leicht grünlich
                    ty2, tx2 = divmod(2 * k + 1, AW)
                    ty2 += trunk_y0
                    sc = tc * np.array([0.42, 0.45, 0.40])
                    img_s[ty2, tx2] = sc; img_a[ty2, tx2] = sc
                    uv_t[:t["trunk"][3]] = [(tx2 + 0.5) / AW, 1.0 - (ty2 + 0.5) / AH]
                Vs.append(TVv); Ns.append(TNn)
                UVs.append(uv_t)
                Fs.append(TFf + off); off += len(TVv)
        V = np.vstack(Vs) - np.array([ox, oy, 0.0])
        F = np.vstack(Fs)
        n_tris += len(F)
        # freie Texel: nächster belegter Wert (Filter/Mipmaps)
        for img in (img_s, img_a):
            occ = img.sum(2) > 0
            if (~occ).any():
                _, (ri, ci) = ndimage.distance_transform_edt(~occ, return_indices=True)
                img[:] = img[ri, ci]
        Image.fromarray((np.clip(img_s, 0, 1) * 255 + 0.5).astype(np.uint8)).save(
            out_s / f"{name}.jpg", quality=q["atlas_q"], subsampling=0)
        Image.fromarray((np.clip(img_a, 0, 1) * 255 + 0.5).astype(np.uint8)).save(
            out_a / f"{name}.jpg", quality=q["atlas_q"], subsampling=0)
        save[f"{name}__v"] = V.astype(np.float32)
        save[f"{name}__f"] = F.astype(np.int32)
        save[f"{name}__n"] = np.vstack(Ns).astype(np.float32)
        save[f"{name}__uv"] = np.vstack(UVs).astype(np.float32)
        meta_m.append({"name": name, "trees": len(ts), "tris": int(len(F)), "verts": int(len(V)),
                       "atlas": [AW, AH]})
    for od in (out_s, out_a):
        np.savez_compressed(od / "trees.npz", **save)
    kinds = D["kind"][idx]
    meta = {"level": level, "sun_az_deg": SUN_AZ, "sun_el_deg": SUN_EL, "meshes": meta_m, "tris": int(n_tris),
            "trees_full": int((chosen == 1).sum()), "trees_simple": int((chosen == 2).sum()),
            "trees_far": int((chosen == 3).sum()),
            "per_kind": {KIND_NAMES[k]: int((kinds == k).sum()) for k in KIND_NAMES},
            "near_m": q["near_m"], "mid_m": q["mid_m"], "budget": q["budget"], "seconds": round(time.time() - t0)}
    for od, light in ((out_s, "sun"), (out_a, "ambient")):
        (od / "meta.json").write_text(json.dumps({**meta, "light": light}, indent=1, ensure_ascii=False))
    tree_ao_raster(ctx, D, idx, out_s / "tree_ao.tif")
    print(f"[{level}] {len(meta_m)} Meshes, {n_tris:,} Dreiecke, {sum(m['verts'] for m in meta_m):,} Ecken, "
          f"{time.time() - t0:.0f} s", flush=True)
    return idx


def tree_ao_raster(ctx, D, used, path):
    """Sanfter Kontaktschatten unter den 3D-Bäumen (1 m). Stark nur, wo das Luftbild hell ist (export.py/summer.py
    schützt dunkle Pixel: dort steckt der echte Schatten schon im Luftbild)."""
    prof = raster_profile(ctx, 1.0, "uint8")
    H, W = prof["height"], prof["width"]
    ao = np.ones((H, W), np.float32)
    e0, n1 = ctx.core[0], ctx.core[3]
    for i in used:
        r = float(D["r"][i]) * (0.9 if D["kind"][i] != BUSH else 1.1)
        c0, r0 = (D["x"][i] - e0), (n1 - D["y"][i])
        R = int(math.ceil(r + 1))
        cs, rs = int(c0) - R, int(r0) - R
        yy, xx = np.mgrid[max(rs, 0):min(rs + 2 * R + 1, H), max(cs, 0):min(cs + 2 * R + 1, W)]
        if yy.size == 0:
            continue
        d = np.hypot(xx + 0.5 - c0, yy + 0.5 - r0) / max(r, 0.5)
        f = 1.0 - 0.32 * np.clip(1.0 - d * d, 0, 1)
        ao[yy, xx] = np.minimum(ao[yy, xx], f)
    ao = ndimage.gaussian_filter(ao, 1.0)
    with rasterio.open(path, "w", **prof) as dst:
        dst.write((np.clip(ao, 0, 1) * 255 + 0.5).astype(np.uint8), 1)


def occluders(ctx):
    """Gebäude (alle Dreiecke aus buildings_*.npz) und Gelände (3 m) als Strahlenmodell, lokal ENU."""
    V, F, off = [], [], 0
    o = np.array([ctx.origin[0], ctx.origin[1], ctx.lake])
    for npz in sorted(ctx.build.glob("buildings_*.npz")):
        d = np.load(npz)
        for kind in ("roof", "wall"):
            v, f = d[f"{kind}_v"], d[f"{kind}_f"]
            if len(f):
                V.append(v - o); F.append(f + off); off += len(v)
    with rasterio.open(ctx.build / "dem_core.tif") as s:
        dem, tr = s.read(1), s.transform
    wm = rasterize([ctx.water], out_shape=dem.shape, transform=tr)
    dem = np.where(wm == 1, ctx.lake - 1.0, dem)
    e0, n0, e1, n1 = ctx.core
    step = 3.0
    xs = np.arange(e0, e1 + 0.1, step); ys = np.arange(n0, n1 + 0.1, step)
    X, Y = np.meshgrid(xs, ys)
    Z = bilinear(dem, tr, X.ravel(), Y.ravel()) - ctx.lake
    tv = np.column_stack([X.ravel() - o[0], Y.ravel() - o[1], Z])
    nx, ny = len(xs), len(ys)
    idx = np.arange(nx * ny).reshape(ny, nx)
    a, b, c, dd = idx[:-1, :-1], idx[:-1, 1:], idx[1:, :-1], idx[1:, 1:]
    tf = np.concatenate([np.stack([a, b, dd], -1).reshape(-1, 3), np.stack([a, dd, c], -1).reshape(-1, 3)])
    V.append(tv); F.append(tf + off)
    return np.vstack(V), np.vstack(F).astype(np.int64)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("area")
    ap.add_argument("levels", nargs="*", default=["standard", "hoch"])
    ap.add_argument("--procs", type=int, default=8)
    ap.add_argument("--device", default="cpu")
    ap.add_argument("--redetect", action="store_true", help="Erkennung neu (sonst detected.npz wiederverwenden)")
    ap.add_argument("--detect-only", action="store_true")
    args = ap.parse_args()
    ctx = Ctx(args.area)
    if not ctx.cfg.get("trees"):
        print(f"{ctx.id}: \"trees\" nicht gesetzt – nichts zu tun")
        return
    t0 = time.time()
    f = ctx.out / "detected.npz"
    if ctx.cfg.get("synth_forest"):
        # Amazonas: Bäume aus der Meta/WRI-Kronenhöhe, auch im Wasser (amazonas.forest), kein Oberflächenmodell
        if f.exists() and not args.redetect:
            D = dict(np.load(f))
        else:
            import amazonas
            D = amazonas.forest(ctx)
            np.savez_compressed(f, **D)
        print(f"synth_forest: {len(D['x']):,} Bäume, davon im Wasser {int(D['flood'].sum()):,}")
    elif f.exists() and not args.redetect:
        D = postprocess(dict(np.load(f)), ctx.cfg)
        print(f"Erkennung: {f} ({int((D['kind'] != BUSH).sum()):,} Bäume, {int((D['kind'] == BUSH).sum()):,} Büsche)")
    else:
        D = postprocess(detect(ctx), ctx.cfg)
    if args.detect_only:
        return
    init_warp()
    occ = occluders(ctx)
    for level in args.levels:
        build_level(ctx, D, level, args.procs, occ)
    print(f"trees.py fertig in {time.time() - t0:.0f} s", flush=True)


if __name__ == "__main__":
    main()
