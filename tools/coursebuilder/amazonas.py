"""Amazonas-Strecken: Überschwemmungswald (Igapó), Pfahlbauten (Palafitas), zwei Wasserfarben (Encontro das Águas)
und ebener Waldboden unter Copernicus-Kronen. Alles nur mit den Gebietsfeldern unten aktiv; andere Gebiete bleiben
unverändert. docs/amazonas/SPEC.md („Umsetzung“), docs/WELTWEIT.md Abschnitt „Amazonas“.

Schritte (zwischen den üblichen der Pipeline):
  prepare.py → amazonas.py dem <gebiet>      Waldboden nahe der Strecke ("canopy_ground")
  routes.py → buildings_footprints.py → amazonas.py palafitas <gebiet>   Pfahlbauten ("palafitas")
  trees.py (ruft amazonas.forest auf, wenn "synth_forest" gesetzt ist) → bake.py → export.py (hängt Pfahlbauten
  unter /Scene/Palafitas und die Wasserfarbe unter /Scene/WaterTint an) → lanes.py (Stämme und Pfahlbauten als
  Hindernisse, "lane_rules")

Gebietsfelder
  "flood_lv95": [[[E, N], ...], ...]   überflutete Flächen bei der festen Wasserhöhe (common.osm_water nimmt sie
        als Wasser dazu: Gelände darunter abgesenkt, routes.py/lanes.py sehen Wasser).
  "canopy_ground": {"flat_m": 320, "ramp_m": 260, "ground_m": 0.8}
        Copernicus GLO-30 misst über dem Regenwald die Kronen (20–35 m über dem Boden). Land bis flat_m von den
        Strecken (via_lv95) kommt auf Wasserhöhe + ground_m (dort stehen die 3D-Bäume), dahinter steigt es über ramp_m
        weich auf die Copernicus-Fläche an: die bleibt als grünes Kronendach (Impostor) für den fernen Wald.
  "synth_forest": {"chm": "meta", "spacing_m": 7.5, "max_route_m": 420, "flood_depth_m": 4.0, "giants_per_ha": 1.2,
                   "min_chm_m": 4.0, "lane_clear_m": 3.0, "low_crown_clear_m": 5.0, "far_from_m": 110,
                   "land_spacing_m": 9.0, "palms": 0.0}
        Bäume aus der Kronenhöhe von Meta/WRI (High Resolution Canopy Height Maps, 1 m, CC BY 4.0; S3
        dataforgood-fb-data, Kachel = Quadkey Stufe 9, EPSG:3857) statt aus einem Oberflächenmodell: Wald = Kronenhöhe
        ≥ min_chm_m; Stämme auf einem verrüttelten Gitter (spacing_m im Wasser, land_spacing_m an Land), Höhe aus der
        Kronenhöhe (lokales Maximum 6 m) × 0,72–1,05, einzelne Urwaldriesen (giants_per_ha) 30–44 m mit breiter
        Schirmkrone. Im Wasser (Wasserfläche inkl. flood_lv95): Stamm steht im Wasser, Höhe über Wasser = Kronenhöhe −
        flood_depth_m, Kronenansatz 35–60 % (Stämme sichtbar). Nur bis max_route_m von den Strecken. trees.py: im
        Wasser erlaubt, Korridor nur lane_clear_m um die Stämme (Kronen dürfen über die Bahn ragen, wenn ihr Ansatz
        ≥ low_crown_clear_m über dem Wasser liegt), ab far_from_m eine einfachere Form (16 Dreiecke).
        Vielfalt ("variety", Standard an; forest_variety): Dickichte und Lücken ("clumping"), Palmen ("palms" Anteil,
        Açaí in Büscheln, Buriti), säulige und flache Schirmkronen, Stelzwurzeln, Lianen, Büsche knapp über dem Wasser
        ("bush_spacing_m", am Waldrand dicht); trees.py färbt synth-Bäume mit Dunst in der Tiefe (ab 35 m).
  "palafitas": {"zones_lv95": [[[E, N], ...]], "near_water_m": 30, "max_area_m2": 260, "min_area_m2": 14,
                "detail_m": 110, "mid_m": 320, "tex_m": 0.07, "tex_mid_m": 0.18, "group_size": 45,
                "walkways": true, "canoes": 0.35, "lane_min_m": 2.5, "veranda_to_route_m": 0, "seed": 7}
        Pfahlbauten: OSM-Gebäude (footprints.geojson) in zones_lv95 oder bis near_water_m vom Wasser, 14–260 m²,
        werden aus buildings_fp_*.npz genommen und als Holzhaus auf Pfählen gebaut (Boden 1,5–2,5 m über dem Wasser,
        Pfähle, Veranda mit Geländer, Bretterwände in bunten Farben mit Tür und Fenstern, Wellblech-Satteldach oder
        Palmdach, Stege zwischen Nachbarhäusern, Kanus). Bis detail_m von der Bahn volle Form (alle Pfähle, Geländer,
        Stege, Kanus) mit Textur tex_m m/Texel in Paketen zu group_size Häusern, bis mid_m einfache Form (Eckpfähle)
        mit tex_mid_m, dahinter 0,5 m/Texel. Häuser, deren Rand näher als lane_min_m an Hin- oder Rückfahrt käme,
        werden verkleinert oder weggelassen. Licht wie bridges.py vorgerechnet.
  "water_tint": {"dark": [r, g, b], "light": [r, g, b], "alpha": [0.55, 0.9], "bounds_lv95": [E0, N0, E1, N1],
                 "px_m": 4, "smooth_m": 18, "feather_m": 500, "levels": [L0, L1], "roughness": 0.25}
        Zwei Wasserfarben: die App zeichnet eine Wasserfarbe; export.py legt 3 cm darüber eine halbdurchsichtige
        Fläche (UsdPreviewSurface mit Deckkraft aus dem Alphakanal). Mischungsgrad je Pixel aus der Helligkeit des
        Sentinel-2-Mosaiks im Wasser (dunkles Schwarzwasser des Rio Negro, helles Weisswasser des Solimões; L0/L1
        sonst 15./85. Perzentil), geglättet, mit feinen Schlieren an der Grenze; zum Rand hin ausgeblendet.
  "lane_rules": {"ROWER_SHORE": 3.0, "ROWER_OBSTACLE": 2.0, "ROWER_OWN": 5.0}   lanes.py: Abstände der Ruderer-Bahnen.
  "traffic": {"follow_lane": true}   lanes.py: ohne Platz neben der eigenen Bahn fahren die Mitruderer auf derselben Linie.
  palafitas.veranda_to_route_m: Häuser bis zu diesem Abstand drehen die Veranda zur Strecke (Hausfront vorne).

Aufruf: .venv/bin/python amazonas.py dem|palafitas|forest|tint areas/<gebiet>.json
"""
import json
import math
import sys
from pathlib import Path

import numpy as np

META_CHM = "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/{q}.tif"
META_LIC = ("Meta and World Resources Institute (WRI) – High Resolution Canopy Height Maps (2024), CC BY 4.0 "
            "(https://creativecommons.org/licenses/by/4.0/); source imagery © 2016 Maxar")


def _area(path):
    from common import load_area
    return load_area(path)


def route_lines(area, build=None):
    """Strecken als LineStrings: routes.geojson, sonst via_lv95 der Gebietsdatei."""
    from shapely.geometry import LineString
    build = build or Path("build") / area["id"]
    f = build / "routes.geojson"
    if f.exists():
        return [LineString(ft["geometry"]["coordinates"]) for ft in json.loads(f.read_text())["features"]]
    return [LineString(r["via_lv95"]) for r in area.get("routes", []) if len(r.get("via_lv95", [])) >= 2]


def lane_lines(area, build=None):
    """Hin- und Rückfahrt (App: Rückfahrt 12 m links der Hinfahrt)."""
    out = []
    for ln in route_lines(area, build):
        out.append(ln)
        try:
            out.append(ln.parallel_offset(12.0, "left", join_style=2))
        except Exception:  # noqa: BLE001
            pass
    return out


def _hash(*a):
    """Deterministisches Rauschen 0..1 je Ganzzahl-Gitterpunkt (vektorisiert)."""
    h = np.zeros_like(np.asarray(a[0], np.float64))
    for k, v in enumerate(a):
        h = h + np.asarray(v, np.float64) * (12.9898 + 65.233 * k)
    return (np.sin(h) * 43758.5453) % 1.0


def vnoise(x, y, scale):
    """Wertrauschen (bilinear) mit Gitterweite scale, 0..1."""
    gx, gy = np.asarray(x) / scale, np.asarray(y) / scale
    x0, y0 = np.floor(gx), np.floor(gy)
    fx, fy = gx - x0, gy - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = _hash(x0, y0), _hash(x0 + 1, y0)
    c, d = _hash(x0, y0 + 1), _hash(x0 + 1, y0 + 1)
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


# ============================================================================= Gelände: Waldboden

def dem(area_file):
    """canopy_ground: Land nahe den Strecken auf Waldboden absenken, weicher Anstieg zum Copernicus-Kronendach."""
    import rasterio
    from rasterio.features import rasterize
    from scipy import ndimage
    from shapely.geometry import shape
    area = _area(area_file)
    cfg = area.get("canopy_ground")
    if not cfg:
        sys.exit("Gebietsdatei ohne \"canopy_ground\" – nichts zu tun")
    build = Path("build") / area["id"]
    lake = float(area["lake_level_m"])
    flat, ramp = float(cfg.get("flat_m", 320)), float(cfg.get("ramp_m", 260))
    ground = lake + float(cfg.get("ground_m", 0.8))
    lines = route_lines(area, build)
    water = shape(json.loads((build / "water.geojson").read_text())["geometry"])
    marker = build / "canopy_ground.json"
    with rasterio.open(build / "dem_core.tif") as s:
        z = s.read(1).astype(np.float32)
        tr, meta = s.transform, s.meta.copy()
    if marker.exists():
        print("canopy_ground: schon angewendet (build/<gebiet>/canopy_ground.json) – erneut auf dem Ergebnis")
    res = abs(tr.a)
    f = 4  # Abstand auf 4-m-Raster (Speicher)
    lm = rasterize([ln.buffer(2.0) for ln in lines], out_shape=z.shape, transform=tr).astype(bool)
    d = ndimage.distance_transform_edt(~lm[::f, ::f]) * res * f
    d = ndimage.zoom(d, f, order=1)[:z.shape[0], :z.shape[1]]
    if d.shape != z.shape:
        d = np.pad(d, ((0, z.shape[0] - d.shape[0]), (0, z.shape[1] - d.shape[1])), mode="edge")
    w = np.clip((d - flat) / max(ramp, 1.0), 0, 1)
    w = w * w * (3 - 2 * w)
    wm = rasterize([water], out_shape=z.shape, transform=tr).astype(bool)
    land = ~wm
    new = np.where(land, ground * (1 - w) + np.maximum(z, ground) * w, z)
    # Uferkante: an Land nie unter Wasserhöhe + 0,3 m (sonst steht Wasser im Wald, wo es nicht soll)
    new = np.where(land, np.maximum(new, lake + 0.3), new)
    drop = np.where(land, z - new, 0)
    meta.update(compress="deflate", tiled=True)
    with rasterio.open(build / "dem_core.tif", "w", **meta) as dst:
        dst.write(new.astype(meta["dtype"]), 1)
    info = {"flat_m": flat, "ramp_m": ramp, "ground_m": round(ground, 2), "lowered_mean_m": round(float(drop[land].mean()), 2),
            "lowered_max_m": round(float(drop.max()), 1), "land_flat_km2": round(float((land & (w == 0)).sum()) * res * res / 1e6, 3)}
    marker.write_text(json.dumps(info, indent=1))
    print("canopy_ground:", json.dumps(info), flush=True)


# ============================================================================= Wald (Meta/WRI-Kronenhöhe)

def _quadkey(lon, lat, z=9):
    s = math.sin(math.radians(lat))
    x = (lon + 180) / 360
    y = 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)
    n = 2 ** z
    tx, ty = int(x * n), int(y * n)
    q = ""
    for i in range(z, 0, -1):
        m = 1 << (i - 1)
        q += str((1 if tx & m else 0) + (2 if ty & m else 0))
    return q


def meta_chm(area, res=1.0):
    """Kronenhöhe (m) von Meta/WRI auf dem Kerngebiet (Gebiets-crs, res m), Cache data_dir/meta_chm/chm.tif."""
    import rasterio
    from rasterio.enums import Resampling
    from rasterio.transform import from_origin
    from rasterio.warp import reproject
    from geofetch import bounds_in, log_source
    raw = (Path.cwd() / area["data_dir"]).resolve()
    out = raw / "meta_chm" / "chm.tif"
    e0, n0, e1, n1 = area["core_lv95"]
    W, H = int(round((e1 - e0) / res)), int(round((n1 - n0) / res))
    tr = from_origin(e0, n1, res, res)
    if out.exists():
        with rasterio.open(out) as s:
            if s.shape == (H, W) and abs(s.transform.c - e0) < 0.01:
                return s.read(1).astype(np.float32), s.transform
    lon0, lat0, lon1, lat1 = bounds_in(area["core_lv95"], area["crs"], "EPSG:4326")
    qks = sorted({_quadkey(lo, la) for lo in (lon0, lon1) for la in (lat0, lat1)})
    dst = np.zeros((H, W), np.float32)
    for q in qks:
        part = np.zeros((H, W), np.float32)
        with rasterio.open("/vsicurl/" + META_CHM.format(q=q)) as s:
            from rasterio.windows import from_bounds
            x0, y0, x1, y1 = bounds_in(area["core_lv95"], area["crs"], "EPSG:3857")
            win = from_bounds(x0 - 50, y0 - 50, x1 + 50, y1 + 50, s.transform).intersection(
                rasterio.windows.Window(0, 0, s.width, s.height))
            src = s.read(1, window=win).astype(np.float32)
            reproject(src, part, src_transform=s.window_transform(win), src_crs=s.crs, dst_transform=tr,
                      dst_crs=area["crs"], resampling=Resampling.bilinear, src_nodata=255, dst_nodata=0)
        dst = np.maximum(dst, part)
        print(f"  Meta-CHM Kachel {q}: Kronenhöhe bis {part.max():.0f} m", flush=True)
    out.parent.mkdir(parents=True, exist_ok=True)
    with rasterio.open(out, "w", driver="GTiff", width=W, height=H, count=1, dtype="float32", crs=area["crs"],
                       transform=tr, compress="deflate", tiled=True) as d:
        d.write(dst, 1)
    log_source(raw, {"source": "Meta/WRI High Resolution Canopy Height Maps (alsgedi_global_v6_float)",
                     "role": "chm", "tiles": qks, "url": "https://registry.opendata.aws/dataforgood-fb-forests/",
                     "licence": META_LIC})
    return dst, tr


def blue_noise(region, sp, rng, dmin_f=0.85):
    """Zufällige Punkte mit Mindestabstand dmin_f · sp (Poisson-Scheibe, gierig) in region – keine Reihen wie beim
    Gitter. Dichte ≈ 1 / sp²."""
    from scipy.spatial import cKDTree
    from shapely import contains_xy
    x0, y0, x1, y1 = region.bounds
    n = int((x1 - x0) * (y1 - y0) / sp ** 2 * 1.6) + 1
    X = x0 + rng.random(n) * (x1 - x0)
    Y = y0 + rng.random(n) * (y1 - y0)
    ok = contains_xy(region, X, Y)
    P = np.column_stack([X[ok], Y[ok]])
    if not len(P):
        return P[:, 0], P[:, 1]
    tree = cKDTree(P)
    gone = np.zeros(len(P), bool)
    keep = np.zeros(len(P), bool)
    for i in rng.permutation(len(P)):
        if gone[i]:
            continue
        keep[i] = True
        gone[tree.query_ball_point(P[i], dmin_f * sp)] = True
    return P[keep, 0], P[keep, 1]


TROPICAL_GREENS = np.array([(0.20, 0.36, 0.13), (0.24, 0.40, 0.15), (0.17, 0.32, 0.14), (0.27, 0.42, 0.17),
                            (0.21, 0.33, 0.11), (0.30, 0.44, 0.18), (0.19, 0.35, 0.18), (0.25, 0.37, 0.12),
                            (0.33, 0.43, 0.13), (0.36, 0.46, 0.16), (0.16, 0.30, 0.20), (0.14, 0.27, 0.16),
                            (0.28, 0.36, 0.10), (0.22, 0.42, 0.22), (0.38, 0.42, 0.18), (0.13, 0.24, 0.11)])
PALM_GREENS = np.array([(0.30, 0.44, 0.15), (0.34, 0.46, 0.14), (0.27, 0.40, 0.16), (0.38, 0.45, 0.17)])
BUSH_GREENS = np.array([(0.24, 0.38, 0.12), (0.20, 0.34, 0.13), (0.30, 0.42, 0.16), (0.17, 0.29, 0.12)])


def _append(D, add):
    n = len(D["x"])
    for k, v in D.items():
        if isinstance(v, np.ndarray) and v.shape[:1] == (n,):
            a = np.asarray(add[k], dtype=v.dtype)
            D[k] = np.concatenate([v, a.reshape((-1,) + v.shape[1:])])
    return D


def forest_variety(D, cfg, rng, near, water, chm_max, ctr, mn, bu):
    """Igapó lebendiger (2. Runde, Falk 28.11.2026): Palmen (Açaí in Büscheln, Buriti einzeln), säulige Kronen,
    unregelmässige und flache Schirmkronen, Stelzwurzeln, Lianen, dichte Büsche knapp über dem Wasser am Waldrand und
    in Dickichten, mehr Grüntöne. Arbeitet auf dem dict aus forest()."""
    from scipy import ndimage
    from scipy.spatial import cKDTree
    from shapely import contains_xy
    from trees import BUSH, DECID, PALM, POPLAR, bilinear
    n = len(D["x"])
    X, Y = D["x"], D["y"]
    flood, giant, under = D["flood"], D["giant"], D["under"]
    fd = float(cfg.get("flood_depth_m", 4.0))
    D["palm"] = np.zeros(n, np.int8)
    D["irreg"] = np.where(under, 0.30 + 0.25 * rng.random(n), 0.16 + 0.32 * rng.random(n))
    D["roots"] = np.zeros(n, np.int8)
    D["liana"] = np.zeros(n, np.int8)
    free = flood & ~giant & ~under
    # Palmen: Açaí in Büscheln (Rauschen 30 m), Buriti einzeln und höher
    pp = float(cfg.get("palms", 0.14)) * (0.4 + 1.6 * vnoise(X, Y + 57.0, 30.0))
    palm = free & (rng.random(n) < pp)
    buriti = palm & (rng.random(n) < 0.25)
    acai = palm & ~buriti
    D["kind"] = np.where(palm, PALM, D["kind"]).astype(np.int8)
    D["palm"] = np.where(buriti, 2, np.where(acai, 1, 0)).astype(np.int8)
    D["h"] = np.where(acai, 8.0 + 6.0 * rng.random(n), np.where(buriti, 12.0 + 8.0 * rng.random(n), D["h"]))
    D["r"] = np.where(acai, 2.2 + 0.9 * rng.random(n), np.where(buriti, 3.6 + 1.4 * rng.random(n), D["r"]))
    D["trunk_r"] = np.where(acai, 0.08 + 0.03 * rng.random(n), np.where(buriti, 0.22 + 0.08 * rng.random(n),
                                                                          D["trunk_r"]))
    D["rgb"] = np.where(palm[:, None], PALM_GREENS[rng.integers(0, len(PALM_GREENS), n)], D["rgb"])
    D["trunk_rgb"] = np.where(palm[:, None], np.array([0.47, 0.42, 0.35]) * (0.85 + 0.3 * rng.random((n, 1))),
                              D["trunk_rgb"])
    D["roots"] = np.where(acai & (rng.random(n) < 0.5), rng.integers(3, 6, n), D["roots"]).astype(np.int8)
    # säulige Kronen (8 %), flache Schirmkronen (Variante 2) mit höherem Ansatz
    col = free & ~palm & (rng.random(n) < 0.08)
    D["kind"] = np.where(col, POPLAR, D["kind"]).astype(np.int8)
    D["r"] = np.where(col, 0.16 * D["h"] + 0.6, D["r"])
    umb = ~palm & ~col & ~under & (D["seed"] % 3 == 2)
    D["cbf"] = np.where(umb, np.maximum(D["cbf"], 0.5 + 0.15 * rng.random(n)), D["cbf"])
    D["r"] = np.where(umb, D["r"] * (1.1 + 0.25 * rng.random(n)), D["r"])
    # Stelzwurzeln am Wasser, Lianen unter höheren Kronen
    big = free & ~palm & (D["trunk_r"] > 0.16)
    D["roots"] = np.where(big & (rng.random(n) < 0.45), rng.integers(3, 6, n), D["roots"]).astype(np.int8)
    cb_abs = D["z"] + D["cbf"] * D["h"]
    D["liana"] = np.where(~palm & ~under & (cb_abs > 3.5) & (rng.random(n) < 0.2), rng.integers(1, 3, n),
                          0).astype(np.int8)
    # Açaí-Büschel: 1–2 weitere Stämme daneben
    sib = np.flatnonzero(acai & (rng.random(n) < 0.6))
    if len(sib):
        k = len(sib)
        a = rng.random(k) * 2 * np.pi
        dd = 0.7 + 0.6 * rng.random(k)
        add = {key: (v[sib].copy() if isinstance(v, np.ndarray) and v.shape[:1] == (n,) else None) for key, v in D.items()}
        add["x"] = X[sib] + np.cos(a) * dd
        add["y"] = Y[sib] + np.sin(a) * dd
        add["h"] = D["h"][sib] * (0.7 + 0.25 * rng.random(k))
        add["seed"] = (D["seed"][sib] * 7 + 13) % 2_147_483_647
        add["roots"] = np.zeros(k, np.int8)
        D = _append(D, add)
    # Büsche knapp über dem Wasser: dichter am Waldrand (hängen ins Wasser) und in Dickichten
    bs = float(cfg.get("bush_spacing_m", 3.6))
    if bs > 0:
        BX, BY = blue_noise(near.intersection(water), bs, rng)
        cmb = bilinear(chm_max, ctr, BX, BY)
        forest_px = chm_max >= mn
        de = ndimage.distance_transform_edt(~forest_px) * abs(ctr.a)      # Abstand ausserhalb des Waldes
        di = ndimage.distance_transform_edt(forest_px) * abs(ctr.a)       # Abstand innerhalb zum Rand
        e_out = bilinear(de, ctr, BX, BY)
        e_in = bilinear(di, ctr, BX, BY)
        th = vnoise(BX + 311.0, BY, 22.0)
        pb = np.where(cmb >= mn, 0.10 + 0.55 * th, 0.0)
        pb = np.where((e_out < 7.0) | ((cmb >= mn) & (e_in < 10.0)), np.maximum(pb, 0.75), pb)
        sel = rng.random(len(BX)) < pb
        if bu:
            sel &= ~contains_xy(bu, BX, BY)
        if len(D["x"]):
            dd, _ = cKDTree(np.column_stack([D["x"], D["y"]])).query(np.column_stack([BX, BY]))
            sel &= dd > 1.2
        m = int(sel.sum())
        if m:
            nn = len(D["x"])
            add = {key: (np.zeros((m,) + v.shape[1:], v.dtype) if isinstance(v, np.ndarray) and v.shape[:1] == (nn,)
                         else None) for key, v in D.items()}
            add.update(x=BX[sel], y=BY[sel], h=1.0 + 1.7 * rng.random(m), r=1.2 + 1.5 * rng.random(m),
                       kind=np.full(m, BUSH, np.int8), green=np.ones(m), forest=np.ones(m, bool),
                       rgb=BUSH_GREENS[rng.integers(0, len(BUSH_GREENS), m)] * (0.85 + 0.3 * rng.random((m, 1))),
                       shape=np.full(m, 0.7), rough=np.ones(m), z=np.zeros(m), flood=np.ones(m, bool),
                       cbf=np.full(m, -1.0), trunk_r=np.zeros(m), trunk_rgb=np.tile([0.3, 0.27, 0.22], (m, 1)),
                       under=np.ones(m, bool), lean=np.ones(m), stain_m=np.zeros(m), irreg=0.3 + 0.2 * rng.random(m),
                       seed=(np.abs(np.round(BX[sel] * 5.0).astype(np.int64) * 83492791 ^
                                    np.round(BY[sel] * 5.0).astype(np.int64)) % 2_147_483_647))
            D = _append(D, add)
    print(f"  Vielfalt: Palmen {int((D['kind'] == PALM).sum()):,} (Buriti {int((D['palm'] == 2).sum())}), "
          f"säulig {int((D['kind'] == POPLAR).sum())}, Büsche {int((D['kind'] == BUSH).sum()):,}, "
          f"Stelzwurzeln {int((D['roots'] > 0).sum()):,}, Lianen {int((D['liana'] > 0).sum()):,}", flush=True)
    return D
FLOWER = np.array([(0.80, 0.70, 0.22), (0.70, 0.42, 0.55), (0.62, 0.66, 0.35)])   # Ipê gelb/rosa, helles Laub


def forest(ctx):
    """Bäume für trees.py aus der Meta/WRI-Kronenhöhe (Gebietsfeld "synth_forest"); gleiches Format wie detect().
    Zusatzfelder: flood (Stamm im Wasser), cbf (Kronenansatz als Anteil der Höhe), trunk_r, trunk_rgb, giant."""
    import rasterio
    from rasterio.features import rasterize
    from scipy import ndimage
    from shapely import contains_xy
    from shapely.geometry import shape
    from trees import BUSH, DECID, PINE, bilinear  # noqa: F401
    area = ctx.cfg
    cfg = area["synth_forest"]
    rng = np.random.default_rng(int(cfg.get("seed", 11)))
    chm, ctr = meta_chm(area)
    chm_max = ndimage.maximum_filter(chm, size=7)
    lines = route_lines(area, ctx.build)
    max_d = float(cfg.get("max_route_m", 420))
    e0, n0, e1, n1 = ctx.core
    water = ctx.water
    # Gebäude (Grundrisse) frei halten
    bld = []
    fp = ctx.raw / "footprints" / "footprints.geojson"
    if fp.exists():
        bld = [shape(f["geometry"]).buffer(2.5) for f in json.loads(fp.read_text())["features"]
               if f.get("geometry")]
    pf = ctx.build / "palafitas" / "footprints.geojson"
    if pf.exists():
        bld += [shape(f["geometry"]).buffer(4.0) for f in json.loads(pf.read_text())["features"]]
    from shapely.ops import unary_union
    near = unary_union([ln.buffer(max_d) for ln in lines]).intersection(
        __import__("shapely.geometry", fromlist=["box"]).box(e0, n0, e1, n1))
    pts = []
    for sp, in_water in ((float(cfg.get("spacing_m", 7.5)), True), (float(cfg.get("land_spacing_m", 9.0)), False)):
        X, Y = blue_noise(near, sp * (0.82 if in_water else 1.0), rng)
        wet = contains_xy(water, X, Y)
        sel = wet if in_water else ~wet
        if in_water and cfg.get("clumping", True):
            # Dickichte und Lücken statt gleichmässiger Pflanzung: Behalten nach grossräumigem Rauschen (45 m, 14 m)
            pk = np.clip(0.12 + 1.3 * vnoise(X + 731.0, Y, 45.0) + 0.35 * (vnoise(X, Y + 113.0, 14.0) - 0.5), 0, 1)
            sel &= rng.random(len(X)) < pk
        pts.append((X[sel], Y[sel], np.full(sel.sum(), in_water)))
    X = np.concatenate([p[0] for p in pts]); Y = np.concatenate([p[1] for p in pts])
    flood = np.concatenate([p[2] for p in pts])
    c = bilinear(chm, ctr, X, Y)
    cm = bilinear(chm_max, ctr, X, Y)
    mn = float(cfg.get("min_chm_m", 4.0))
    keep = cm >= mn
    spread = float(cfg.get("edge_spread_m", 0))
    if spread:
        # überfluteter Saum: einzelne Bäume bis edge_spread_m vor dem Waldrand (Sentinel-2 zeigt dort lose Kronen)
        cs = bilinear(ndimage.maximum_filter(chm, size=int(2 * spread + 1)), ctr, X, Y)
        edge = ~keep & (cs >= mn + 3) & flood & (rng.random(len(X)) < 0.55)
        c = np.where(edge, 0.55 * cs, c)
        cm = np.where(edge, 0.65 * cs, cm)
        keep |= edge
    with rasterio.open(ctx.build / "dem_core.tif") as s:
        demv, dtr = s.read(1), s.transform
    zg = bilinear(demv, dtr, X, Y) - ctx.lake
    keep &= flood | (zg < 4.0)   # an Land nur auf dem Waldboden, nicht auf dem Copernicus-Kronendach (Impostor)
    if bld:
        bu = unary_union(bld)
        keep &= ~contains_xy(bu, X, Y)
    X, Y, c, cm, flood, zg = X[keep], Y[keep], c[keep], cm[keep], flood[keep], zg[keep]
    n = len(X)
    Htot = np.maximum(c, 0.6 * cm) * (0.72 + 0.33 * rng.random(n))
    Htot = np.clip(Htot, 5.0 + float(cfg.get("flood_depth_m", 4.0)) * flood, 38.0)
    # Urwaldriesen
    ha = (near.area / 1e4)
    n_g = int(round(min(float(cfg.get("giants_per_ha", 1.2)) * ha, 0.025 * n)))   # höchstens 2,5 % der Bäume
    giant = np.zeros(n, bool)
    if n_g and n:
        p = np.clip(cm - 12, 0.1, None) ** 2
        p /= p.sum()
        gi = rng.choice(n, size=min(n_g, n // 8 or 1), replace=False, p=p)
        giant[gi] = True
        Htot[gi] = 30 + 14 * rng.random(len(gi))
    fd = float(cfg.get("flood_depth_m", 4.0))
    under = np.zeros(n, bool)
    uf = float(cfg.get("understory", 0.45))
    if uf > 0 and n:
        # Unterholz im Wasser: kleine Bäume mit tiefen Kronen in den Lücken (Igapó ist unten dicht, nicht nur Stämme)
        from scipy.spatial import cKDTree
        su = float(cfg.get("spacing_m", 7.5))
        UX, UY = blue_noise(near.intersection(water), su * 0.9, rng)
        dd, _ = cKDTree(np.column_stack([X, Y])).query(np.column_stack([UX, UY]))
        cu = bilinear(chm_max, ctr, UX, UY)
        sel = (dd > 0.45 * su) & (cu >= mn) & (rng.random(len(UX)) < uf)
        if bld:
            sel &= ~contains_xy(bu, UX, UY)
        m = int(sel.sum())
        X = np.concatenate([X, UX[sel]]); Y = np.concatenate([Y, UY[sel]])
        c = np.concatenate([c, np.full(m, 0.0)]); cm = np.concatenate([cm, cu[sel]])
        flood = np.concatenate([flood, np.ones(m, bool)]); zg = np.concatenate([zg, np.zeros(m)])
        Htot = np.concatenate([Htot, fd + 3.5 + 4.0 * rng.random(m)])
        giant = np.concatenate([giant, np.zeros(m, bool)])
        under = np.concatenate([under, np.ones(m, bool)])
        n = len(X)
    z = np.where(flood, 0.0, zg)
    h = np.where(flood, np.maximum(Htot - fd, 4.0), Htot)
    # Kronenansatz (Anteil der Höhe über dem Stammfuss): im Wasser sichtbare Stämme 2,5–8 m
    cb_abs = np.where(flood, np.maximum(2.5, (0.42 + 0.2 * rng.random(n)) * Htot - fd), (0.38 + 0.22 * rng.random(n)) * Htot)
    cb_abs = np.where(giant, (0.55 + 0.1 * rng.random(n)) * h, cb_abs)
    cb_abs = np.where(under, 1.0 + 1.3 * rng.random(n), cb_abs)
    cbf = np.clip(cb_abs / h, 0.15, 0.8)
    sp = np.where(flood, float(cfg.get("spacing_m", 7.5)), float(cfg.get("land_spacing_m", 9.0)))
    r = np.clip(sp * (0.55 + 0.35 * rng.random(n)) + 0.08 * h, 2.0, 0.36 * h + 1.5)
    r = np.where(giant, 0.30 * h + 2.0 * rng.random(n), r)
    r = np.where(under, 1.3 + 1.6 * rng.random(n), r)
    trunk_r = np.clip(0.022 * Htot + 0.06 * rng.random(n), 0.14, 0.55)
    trunk_r = np.where(under, 0.07 + 0.08 * rng.random(n), trunk_r)
    trunk_r = np.where(giant, 0.7 + 0.35 * rng.random(n), trunk_r)
    # Farben: Laub tropisch dunkelgrün mit Streuung, selten blühend; Stämme hellgrau (Igapó) bis braun
    rgb = TROPICAL_GREENS[rng.integers(0, len(TROPICAL_GREENS), n)] * (0.9 + 0.25 * rng.random((n, 1)))
    fl = rng.random(n) < float(cfg.get("flowering", 0.015))
    rgb[fl] = FLOWER[rng.integers(0, len(FLOWER), fl.sum())]
    trunk_rgb = np.where(flood[:, None], np.array([0.56, 0.53, 0.47]), np.array([0.42, 0.36, 0.29]))
    trunk_rgb = trunk_rgb * (0.85 + 0.25 * rng.random((n, 1)))
    kind = np.full(n, DECID, np.int8)
    shape_ = np.where(giant, 0.95, 0.75 + 0.2 * rng.random(n))
    D = {"x": X, "y": Y, "h": h.astype(np.float64), "r": r, "kind": kind, "green": np.ones(n), "forest": np.ones(n, bool),
         "rgb": rgb, "shape": shape_, "rough": np.ones(n), "tlm": np.zeros(n, bool), "z": z,
         "flood": flood.astype(bool), "cbf": cbf, "trunk_r": trunk_r, "trunk_rgb": trunk_rgb, "giant": giant,
         "under": under,
         # schiefer im Wasser, dunkler Wasserrand 1,0–2,2 m über dem Wasser
         "lean": np.where(flood, 0.6 + 2.6 * rng.random(n), 1.0),
         "stain_m": np.where(flood, 1.0 + 1.2 * rng.random(n), 0.0)}
    D["seed"] = (np.abs(np.round(X * 7.0).astype(np.int64) * 73856093 ^ np.round(Y * 7.0).astype(np.int64)
                        * 19349663) % 2_147_483_647).astype(np.int64)
    # Form: Riesen breit (Schirm), sonst gemischt; Variante über seed % 3 in trees.build_tree → seed für Riesen setzen
    # Kronenform (trees.build_tree: Variante = seed % 3 → rund, eiförmig, breit): tropisch meist breit, Riesen immer
    var = np.where(giant, 2, rng.choice(3, size=n, p=[0.28, 0.17, 0.55]))
    D["seed"] = D["seed"] - (D["seed"] % 3) + var
    if cfg.get("variety", True):
        D = forest_variety(D, cfg, rng, near, water, chm_max, ctr, mn, bld and bu)
        X, Y, flood, trunk_r, n = D["x"], D["y"], D["flood"], D["trunk_r"], len(D["x"])
        giant, under = D["giant"], D["under"]
    np.save(ctx.build / "flooded_trunks.npy", np.column_stack([X[flood], Y[flood], np.maximum(trunk_r[flood], 0.3)]))
    print(f"synth_forest: {n:,} Bäume (im Wasser {int(flood.sum()):,}, Riesen {int(giant.sum())}, "
          f"Unterholz {int(under.sum()):,}), "
          f"Höhe über Fuss Median {np.median(h):.1f} m, max {h.max():.1f} m", flush=True)
    return D


# ============================================================================= Pfahlbauten

M_WALL, M_FLOOR, M_PILE, M_METAL, M_THATCH, M_RAIL, M_HULL = range(7)
FACADES = [(0.20, 0.60, 0.60), (0.86, 0.47, 0.56), (0.93, 0.79, 0.32), (0.36, 0.56, 0.82), (0.36, 0.66, 0.36),
           (0.89, 0.53, 0.26), (0.62, 0.48, 0.74), (0.86, 0.84, 0.78), (0.95, 0.93, 0.88), (0.80, 0.25, 0.22),
           (0.52, 0.39, 0.27), (0.47, 0.35, 0.24), (0.58, 0.45, 0.31)]   # die letzten drei: rohes Holz
FACADE_P = np.array([8, 7, 8, 7, 6, 5, 4, 6, 5, 4, 14, 14, 12], float)


class House:
    pass


def select_palafitas(area, build, raw):
    """Grundrisse, die Pfahlbauten werden (Polygon, Mittelpunkt, Achsen)."""
    from shapely.geometry import Polygon, shape
    from shapely.ops import unary_union
    cfg = area["palafitas"]
    water = shape(json.loads((build / "water.geojson").read_text())["geometry"])
    zones = unary_union([Polygon(z) for z in cfg.get("zones_lv95", [])]) if cfg.get("zones_lv95") else None
    near = water.buffer(float(cfg.get("near_water_m", 30)))
    lo, hi = float(cfg.get("min_area_m2", 14)), float(cfg.get("max_area_m2", 260))
    e0, n0, e1, n1 = area.get("buildings_lv95", area["core_lv95"])
    out = []
    for ft in json.loads((raw / "footprints" / "footprints.geojson").read_text())["features"]:
        g = shape(ft["geometry"])
        if g.geom_type != "Polygon" or not (lo <= g.area <= hi):
            continue
        c = g.centroid
        if not (e0 <= c.x <= e1 and n0 <= c.y <= n1):
            continue
        if (zones is not None and zones.contains(c)) or near.contains(c):
            out.append(g)
    return out, water


def house_params(g, rng, water, dem, dtr, lake):
    from trees import bilinear
    h = House()
    mrr = g.minimum_rotated_rectangle
    cs = np.array(mrr.exterior.coords)[:4]
    e1v, e2v = cs[1] - cs[0], cs[2] - cs[1]
    l1, l2 = np.linalg.norm(e1v), np.linalg.norm(e2v)
    if l1 >= l2:
        u, L, W = e1v / l1, l1, l2
    else:
        u, L, W = e2v / l2, l2, l1
    h.c = np.array(mrr.centroid.coords[0])
    h.u = u
    h.v = np.array([-u[1], u[0]])
    h.L = float(np.clip(L * 0.95, 4.5, 13.0))
    h.W = float(np.clip(W * 0.95, 3.6, 8.5))
    zg = float(bilinear(dem, dtr, np.array([h.c[0]]), np.array([h.c[1]]))[0]) - lake
    h.wet = water.contains(g.centroid) or zg < 0.4
    h.ground = -1.2 if h.wet else zg - 0.2
    h.floor = (1.5 + 1.0 * rng.random()) if h.wet else max(zg + 0.9 + 0.6 * rng.random(), 1.4)
    h.wall = 2.5 + 0.4 * rng.random()
    h.two = rng.random() < 0.10 and h.L > 7
    if h.two:
        h.wall *= 1.9
    h.thatch = rng.random() < 0.30
    h.pitch = math.radians(34 if h.thatch else 16 + 8 * rng.random())
    h.over = 0.8 if h.thatch else 0.45
    h.ver = 1.4 + 0.5 * rng.random()          # Veranda (Tiefe) auf einer Längsseite
    h.ver_side = 1 if rng.random() < 0.5 else -1
    h.col = np.array(FACADES[rng.choice(len(FACADES), p=FACADE_P / FACADE_P.sum())])
    h.trim = np.array([(0.95, 0.94, 0.9), (0.25, 0.45, 0.7), (0.75, 0.2, 0.2), (0.2, 0.5, 0.3)][rng.integers(0, 4)])
    h.rust = rng.random()
    return h


def build_house(mb, h, origin, detail, rng, hid):
    """Haus h in den MeshBuilder (lokales ENU, z über Wasser). Liefert nichts; mb.H (Haus je Dreieck) wird ergänzt."""
    from bridges import beam3d
    n0 = len(mb.F)
    c = h.c - origin
    u, v = h.u, h.v
    L2, W2 = h.L / 2, h.W / 2
    # Boden: Haus + Veranda auf der ver_side
    vlo = -W2 - (h.ver if h.ver_side < 0 else 0)
    vhi = W2 + (h.ver if h.ver_side > 0 else 0)

    def P(a, b, z):
        p = c + u * a + v * b
        return [p[0], p[1], z]

    def ring(a0, a1, b0, b1):
        return np.array([P(a0, b0, 0)[:2], P(a1, b0, 0)[:2], P(a1, b1, 0)[:2], P(a0, b1, 0)[:2]]) + origin
    ft = 0.22
    mb.prism(ring(-L2 - 0.3, L2 + 0.3, vlo, vhi), h.floor - ft, h.floor, M_FLOOR, origin)
    # Unterseite des Bodens (von unten sichtbar vom Boot aus)
    r = ring(-L2 - 0.3, L2 + 0.3, vlo, vhi) - origin
    mb.quad([*r[0], h.floor - ft], [*r[3], h.floor - ft], [*r[2], h.floor - ft], [*r[1], h.floor - ft],
            np.array([0, 0, -1.0]), M_FLOOR)
    # Wände (ohne Deckel)
    mb.prism(ring(-L2, L2, -W2, W2), h.floor, h.floor + h.wall, M_WALL, origin, top=False)
    # Pfähle
    ps = 0.18
    na = max(2, int(round((h.L + 0.6) / 2.3)) + 1) if detail else 2
    nb = max(2, int(round((vhi - vlo) / 2.3)) + 1) if detail else 2
    for a in np.linspace(-L2 - 0.15, L2 + 0.15, na):
        for b in np.linspace(vlo + 0.15, vhi - 0.15, nb):
            if not detail and not (abs(abs(a) - (L2 + 0.15)) < 0.01):
                continue
            jit = (rng.random(2) - 0.5) * 0.12
            q = c + u * (a + jit[0]) + v * (b + jit[1])
            rq = np.array([q + (u + v) * ps / 2, q + (u - v) * ps / 2, q + (-u - v) * ps / 2, q + (-u + v) * ps / 2])
            mb.prism(rq + origin, h.ground, h.floor - ft, M_PILE, origin, top=False)
    # Dach: Satteldach (First längs) bzw. Walmdach (Palmdach), über Haus + Veranda
    zt = h.floor + h.wall
    a0, a1 = -L2 - h.over, L2 + h.over
    b0, b1 = vlo - h.over * 0.6, vhi + h.over * 0.6
    bm = (b0 + b1) / 2
    hw = (b1 - b0) / 2
    rise = math.tan(h.pitch) * hw
    zr = zt + rise
    # Traufe über der Veranda nicht unter 2,1 m über dem Boden
    ze = zt - 0.15
    mat = M_THATCH if h.thatch else M_METAL
    up = np.array([0, 0, 1.0])
    if h.thatch:
        inset = min(hw * 0.9, (a1 - a0) / 2 * 0.6)
        ra0, ra1 = a0 + inset, a1 - inset
        A, B = P(a0, b0, ze), P(a1, b0, ze)
        Cc, Dd = P(a1, b1, ze), P(a0, b1, ze)
        R0, R1 = P(ra0, bm, zr), P(ra1, bm, zr)
        mb.quad(A, B, R1, R0, np.array([-v[0], -v[1], 1.0]), mat)
        mb.quad(Cc, Dd, R0, R1, np.array([v[0], v[1], 1.0]), mat)
        mb.tri(B, Cc, R1, np.array([u[0], u[1], 1.0]), mat)
        mb.tri(Dd, A, R0, np.array([-u[0], -u[1], 1.0]), mat)
        th = 0.25  # sichtbare Dicke der Traufe
        for p0, p1, nn in ((A, B, -v), (B, Cc, u), (Cc, Dd, v), (Dd, A, -u)):
            mb.quad(p0, p1, [p1[0], p1[1], p1[2] - th], [p0[0], p0[1], p0[2] - th], np.array([nn[0], nn[1], 0.0]), mat)
        # Unterseite
        mb.quad(P(a0, b0, ze - th), P(a0, b1, ze - th), P(a1, b1, ze - th), P(a1, b0, ze - th), -up, mat)
    else:
        A, B = P(a0, b0, ze), P(a1, b0, ze)
        Cc, Dd = P(a1, b1, ze), P(a0, b1, ze)
        R0, R1 = P(a0, bm, zr), P(a1, bm, zr)
        mb.quad(A, B, R1, R0, np.array([-v[0], -v[1], 1.0]), mat)
        mb.quad(Cc, Dd, R0, R1, np.array([v[0], v[1], 1.0]), mat)
        # Unterseiten (Blech dünn, von unten sichtbar)
        th = 0.06
        mb.quad(P(a0, b0, ze - th), P(a0, bm, zr - th), P(a1, bm, zr - th), P(a1, b0, ze - th), np.array([v[0], v[1], -1.0]), mat)
        mb.quad(P(a0, b1, ze - th), P(a1, b1, ze - th), P(a1, bm, zr - th), P(a0, bm, zr - th), np.array([-v[0], -v[1], -1.0]), mat)
        # Giebel (Wandfarbe) über den Schmalseiten bis unter die Dachfläche
        def zroof(bb):
            return ze + math.tan(h.pitch) * (hw - abs(bb - bm)) - th
        prof = [(-W2, zt), (W2, zt), (W2, zroof(W2))] + ([(bm, zroof(bm))] if -W2 < bm < W2 else []) + \
               [(-W2, zroof(-W2))]
        for a_s in (-L2, L2):
            nn = np.array([u[0] * np.sign(a_s), u[1] * np.sign(a_s), 0.0])
            for k in range(1, len(prof) - 1):
                mb.tri(P(a_s, *prof[0]), P(a_s, *prof[k]), P(a_s, *prof[k + 1]), nn, M_WALL)
    if detail:
        # Veranda: Geländer (Pfosten + Handlauf) aussen, Stützen fürs Dach
        bo = vhi - 0.08 if h.ver_side > 0 else vlo + 0.08
        for a in np.linspace(-L2 - 0.2, L2 + 0.2, max(3, int(h.L / 1.6))):
            beam3d(mb, P(a, bo, h.floor), P(a, bo, h.floor + 0.95), 0.08, 0.08, M_RAIL)
        for a in (-L2 - 0.2, L2 + 0.2):
            beam3d(mb, P(a, bo, h.floor + 0.95), P(a, bo, ze), 0.12, 0.12, M_RAIL)
        beam3d(mb, P(-L2 - 0.2, bo, h.floor + 0.95), P(L2 + 0.2, bo, h.floor + 0.95), 0.07, 0.09, M_RAIL)
        beam3d(mb, P(-L2 - 0.2, bo, h.floor + 0.5), P(L2 + 0.2, bo, h.floor + 0.5), 0.05, 0.06, M_RAIL)
    mb.H += [hid] * (len(mb.F) - n0)


def build_walkway(mb, p0, p1, z, origin, hid):
    """Steg aus Brettern (1 m breit) auf Pfählen alle 2,5 m."""
    n0 = len(mb.F)
    p0, p1 = np.asarray(p0, float) - origin, np.asarray(p1, float) - origin
    d = p1 - p0
    Ln = np.linalg.norm(d)
    if Ln < 1.0:
        return
    t = d / Ln
    nrm = np.array([-t[1], t[0]])
    w = 0.55
    q = np.array([p0 + nrm * w, p1 + nrm * w, p1 - nrm * w, p0 - nrm * w]) + origin
    mb.prism(q, z - 0.12, z, M_FLOOR, origin)
    for s in np.arange(0.0, Ln + 0.01, 2.5):
        for side in (-1, 1):
            cpt = p0 + t * s + nrm * side * (w - 0.08)
            rq = np.array([cpt + (t + nrm) * 0.07, cpt + (t - nrm) * 0.07, cpt + (-t - nrm) * 0.07,
                           cpt + (-t + nrm) * 0.07]) + origin
            mb.prism(rq, -1.2, z - 0.12, M_PILE, origin, top=False)
    mb.H += [hid] * (len(mb.F) - n0)


def build_canoe(mb, c, t, origin, hid, length=6.0, width=0.9):
    """Einbaum/Peque-peque: spitzer Rumpf, 0,35 m über dem Wasser, offen oben (dunkles Inneres über Material)."""
    n0 = len(mb.F)
    c = np.asarray(c, float) - origin
    t = t / np.linalg.norm(t)
    nrm = np.array([-t[1], t[0]])
    xs = np.array([-0.5, -0.36, 0.0, 0.36, 0.5]) * length
    ws = np.array([0.05, 0.85, 1.0, 0.85, 0.05]) * width / 2
    top, bot = 0.32, -0.15
    for i in range(4):
        for side in (-1, 1):
            a = c + t * xs[i] + nrm * ws[i] * side
            b = c + t * xs[i + 1] + nrm * ws[i + 1] * side
            out = np.array([nrm[0] * side, nrm[1] * side, 0.0])
            mb.quad([*a, bot], [*b, bot], [*b, top], [*a, top], out, M_HULL)
            # Innenseite
            ai = c + t * xs[i] + nrm * max(ws[i] - 0.05, 0.0) * side
            bi = c + t * xs[i + 1] + nrm * max(ws[i + 1] - 0.05, 0.0) * side
            mb.quad([*ai, top], [*bi, top], [*bi, 0.05], [*ai, 0.05], -out, M_HULL)
    for i in range(4):
        a1, b1 = c + t * xs[i] + nrm * (ws[i] - 0.05), c + t * xs[i + 1] + nrm * (ws[i + 1] - 0.05)
        a2, b2 = c + t * xs[i] - nrm * (ws[i] - 0.05), c + t * xs[i + 1] - nrm * (ws[i + 1] - 0.05)
        mb.quad([*a1, 0.05], [*b1, 0.05], [*b2, 0.05], [*a2, 0.05], np.array([0, 0, 1.0]), M_HULL)
    mb.H += [hid] * (len(mb.F) - n0)


def palafita_albedo(M, P, N, fid, houses, face_house):
    """Farbe je Texel: Bretterwände mit Tür und Fenstern, Wellblech mit Rost, Palmdach, Holzböden, nasse Pfähle."""
    n = len(P)
    alb = np.zeros((n, 3), np.float32)
    hid = face_house[fid]
    col = np.array([h.col for h in houses])
    trim = np.array([h.trim for h in houses])
    cen = np.array([h.c for h in houses])
    uu = np.array([h.u for h in houses])
    vv = np.array([h.v for h in houses])
    Ls = np.array([h.L for h in houses]); Ws = np.array([h.W for h in houses])
    fl = np.array([h.floor for h in houses]); wl = np.array([h.wall for h in houses])
    vs = np.array([h.ver_side for h in houses])
    rust = np.array([h.rust for h in houses])
    two = np.array([h.two for h in houses])
    valid = hid >= 0
    hh = np.where(valid, hid, 0)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    rel = P[:, :2] - cen[hh]
    a = np.einsum("ij,ij->i", rel, uu[hh])     # längs
    b = np.einsum("ij,ij->i", rel, vv[hh])     # quer
    zr = z - fl[hh]
    # ---- Wände
    m = M == M_WALL
    if m.any():
        base = col[hh[m]].copy()
        plank = np.floor(zr[m] / 0.2)
        var = 0.9 + 0.16 * _hash(plank, hh[m] * 3.1, np.floor((a[m] + b[m]) / 2.4))
        gap = (zr[m] / 0.2) % 1.0 < 0.1
        f = var * np.where(gap, 0.78, 1.0)
        # Verwitterung unten und fleckig
        f *= 0.86 + 0.14 * vnoise(x[m] + y[m], z[m], 0.7)
        f *= np.where(zr[m] < 0.5, 0.85, 1.0)
        c_ = base * f[:, None]
        long_side = np.abs(np.abs(b[m]) - Ws[hh[m]] / 2) < 0.12
        front = long_side & (np.sign(b[m]) == vs[hh[m]])
        s = np.where(long_side, a[m], b[m])
        half = np.where(long_side, Ls[hh[m]] / 2, Ws[hh[m]] / 2)
        zz = zr[m] % np.where(two[hh[m]], wl[hh[m]] / 2, 1e9)
        # Fenster: Längsseite bei ±L/4 (bzw. ±L/3 und 0 an langen Häusern), Schmalseite mittig
        win = np.zeros(m.sum(), bool); frame = np.zeros(m.sum(), bool); door = np.zeros(m.sum(), bool)
        for wpos in (-0.5, 0.5):
            cx = np.where(long_side, wpos * half, np.where(wpos < 0, 0.0, 1e9))
            inside = (np.abs(s - cx) < 0.5) & (zz > 0.95) & (zz < 1.95)
            ring_ = (np.abs(s - cx) < 0.6) & (zz > 0.85) & (zz < 2.05) & ~inside
            win |= inside; frame |= ring_
        dmask = front & (np.abs(s) < 0.48) & (zr[m] < 2.05) & (zr[m] > 0.0)
        dframe = front & (np.abs(s) < 0.58) & (zr[m] < 2.15) & ~dmask
        door = dmask
        win &= ~(dmask | dframe)
        frame &= ~(dmask | dframe)
        c_[win] = np.array([0.07, 0.07, 0.08]) + 0.04 * (np.sin(z[m][win] * 9) > 0.6)[:, None]
        c_[frame | dframe] = trim[hh[m]][frame | dframe]
        c_[door] = np.array([0.30, 0.20, 0.13]) * (0.85 + 0.15 * ((s[door] / 0.18) % 1.0 > 0.15))[:, None]
        alb[m] = c_
    # ---- Böden, Stege
    m = M == M_FLOOR
    if m.any():
        tw = np.where(valid[m], b[m], x[m] + y[m])
        pl = np.floor(tw / 0.25)
        f = 0.82 + 0.25 * _hash(pl, np.floor((x[m] - y[m]) / 3.0))
        f *= np.where((tw / 0.25) % 1.0 < 0.08, 0.7, 1.0)
        alb[m] = np.array([0.46, 0.36, 0.25]) * f[:, None]
    # ---- Pfähle: über Wasser grau-braun, unten nass und dunkel mit Algenrand
    m = M == M_PILE
    if m.any():
        f = 0.85 + 0.25 * _hash(np.floor(x[m] * 3), np.floor(y[m] * 3))
        c_ = np.array([0.36, 0.30, 0.24]) * f[:, None]
        wet = z[m] < 0.45
        c_[wet] = np.array([0.15, 0.14, 0.11])
        c_[(z[m] >= 0.45) & (z[m] < 0.75)] = np.array([0.24, 0.24, 0.17])
        alb[m] = c_
    # ---- Wellblech: Rippen in Fallrichtung, Rost fleckig
    m = M == M_METAL
    if m.any():
        rib = (a[m] / 0.16) % 1.0
        f = 0.8 + 0.3 * np.abs(np.sin(rib * np.pi))
        metal = np.array([0.66, 0.67, 0.66])
        rustc = np.array([0.52, 0.31, 0.18])
        rn = vnoise(x[m] * 1.0, y[m] + z[m], 1.3)
        rw = np.clip((rn - (0.85 - 0.7 * rust[hh[m]])) * 4, 0, 1)
        c_ = metal * (1 - rw[:, None]) + rustc * rw[:, None]
        down = N[m, 2] < -0.2
        c_[down] = np.array([0.32, 0.30, 0.28])
        alb[m] = c_ * f[:, None]
    # ---- Palmdach: Lagen, Fasern
    m = M == M_THATCH
    if m.any():
        layer = (z[m] / 0.28) % 1.0
        f = 0.72 + 0.3 * layer + 0.15 * (_hash(np.floor(a[m] * 12), np.floor(z[m] / 0.28)) - 0.5)
        c_ = np.array([0.56, 0.46, 0.29]) * f[:, None]
        c_ *= (0.85 + 0.2 * vnoise(x[m], y[m], 1.5))[:, None]
        alb[m] = c_
    m = M == M_RAIL
    if m.any():
        alb[m] = np.where(_hash(hh[m])[:, None] < 0.5, trim[hh[m]] * 0.9, np.array([0.45, 0.35, 0.24]))
    m = M == M_HULL
    if m.any():
        hc = np.array([(0.30, 0.22, 0.15), (0.18, 0.35, 0.60), (0.65, 0.20, 0.18), (0.20, 0.45, 0.30)])
        k = (hh[m] * 7) % 4
        c_ = hc[k] * (0.85 + 0.2 * _hash(np.floor(z[m] * 10)))[:, None]
        c_[N[m, 2] > 0.5] = np.array([0.22, 0.17, 0.12])
        alb[m] = c_
    return np.clip(alb, 0, 1)


def palafita_occluders(area, origin, bbox, extra=()):
    from bridges import occluders
    return occluders(area, origin, bbox)


def bake_group(name, V, F, M, FH, houses, occ_v, occ_f, out, procs, tex_m, light_mode="sun", origin=(0.0, 0.0)):
    """Atlas und Licht wie bridges.bake_bridge, Material über palafita_albedo."""
    import warp as wp
    import bake as bk
    from PIL import Image
    from scipy import ndimage
    # Ecken verschweissen: MeshBuilder legt je Dreieck eigene Ecken an, dann wäre jedes Dreieck eine eigene Karte im
    # Atlas (Rand und Hüllrechteck je Dreieck, ~3× mehr Texel); verschweisst fasst atlas_layout ebene Flächen zusammen
    V, F, ok = bk.weld(V, F, 0.003)
    F, M, FH = F[ok], M[ok], FH[ok]
    g = {"V": V, "F": F, "fband": np.zeros(len(F), np.int8)}
    bk.atlas_layout(g, [tex_m], 2048)
    cF, cV, tx = g["cF"], g["cV"], g["tx"]
    n, T = len(cF), g["aw"] * g["ah"]
    dev = "cpu"
    w2 = lambda a: wp.array(a.astype(np.float32), dtype=wp.vec2, device=dev)  # noqa: E731
    w3 = lambda a: wp.array(a.astype(np.float32), dtype=wp.vec3, device=dev)  # noqa: E731
    best = wp.full(T, -1e9, dtype=float, device=dev)
    opos = wp.zeros(T, dtype=wp.vec3, device=dev)
    onrm = wp.zeros(T, dtype=wp.vec3, device=dev)
    oface = wp.full(T, -1, dtype=wp.int32, device=dev)
    wp.launch(bk.k_raster, n, [w2(tx[cF[:, 0]]), w2(tx[cF[:, 1]]), w2(tx[cF[:, 2]]),
                               w3(cV[cF[:, 0]]), w3(cV[cF[:, 1]]), w3(cV[cF[:, 2]]), w3(g["cN"][cF[:, 0]]),
                               wp.zeros(n, dtype=wp.int64, device=dev),
                               wp.full(n, g["aw"], dtype=wp.int32, device=dev),
                               wp.full(n, g["ah"], dtype=wp.int32, device=dev), best, opos, onrm, oface],
              device=dev)
    wp.synchronize()
    cov = best.numpy() > -1e8
    P, N, fid = opos.numpy()[cov], onrm.numpy()[cov], oface.numpy()[cov]
    allv = np.vstack([V, occ_v]); allf = np.vstack([F, occ_f + len(V)])
    light = bk.trace("pfahlbau", allv, allf, P.astype(np.float64), N.astype(np.float64), procs, side=5,
                     r_ao=6.0)
    facing = (N @ bk.sun_enu()) > 0
    sun_vis = np.ones(len(light)) if light_mode == "ambient" else light[:, 2]
    sh = bk.shade(light[:, 0], light[:, 1], sun_vis, facing)
    down = np.clip(-N[:, 2], 0, 1)
    sh = sh * (1 - 0.45 * down)
    Pw = P.astype(np.float64) + np.array([origin[0], origin[1], 0.0])   # Weltlage (Häuser in Gebietskoordinaten)
    alb = palafita_albedo(M[fid], Pw, N, fid, houses, FH)
    H, Wd = g["ah"], g["aw"]
    shi = np.zeros((H * Wd, 3), np.float32)
    shi[cov] = sh[:, None]
    ch = np.full(H * Wd, -1, np.int64)
    ch[cov] = g["chart_of_face"][fid]
    c2, ch = cov.reshape(H, Wd), ch.reshape(H, Wd)
    shi = bk.smooth_in_chart(bk.smooth_in_chart(shi.reshape(H, Wd, 3), c2, ch), c2, ch).reshape(-1, 3)
    img = np.zeros((H * Wd, 3), np.float32)
    img[cov] = alb * shi[cov]
    img = img.reshape(H, Wd, 3)
    if (~c2).any() and c2.any():
        _, (ri, ci) = ndimage.distance_transform_edt(~c2, return_indices=True)
        img = img[ri, ci]
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)).save(out / f"{name}.jpg", quality=88,
                                                                            subsampling=0)
    uv = g["tx"] / np.array([g["aw"], g["ah"]])
    uv[:, 1] = 1.0 - uv[:, 1]
    return {f"{name}__v": cV.astype(np.float32), f"{name}__f": cF.astype(np.int32),
            f"{name}__n": g["cN"].astype(np.float32), f"{name}__uv": uv.astype(np.float32)}, (Wd, H)


def palafitas(area_file, procs=8, light="sun"):
    import rasterio
    import warp as wp
    from shapely.geometry import LineString, Point, mapping
    from bridges import MeshBuilder
    from buildings import drop_over_water  # noqa: F401
    wp.config.quiet = True
    wp.init()
    area = _area(area_file)
    cfg = area.get("palafitas")
    if not cfg:
        sys.exit("Gebietsdatei ohne \"palafitas\" – nichts zu tun")
    build = Path("build") / area["id"]
    raw = (Path.cwd() / area["data_dir"]).resolve()
    out = build / ("palafitas" if light == "sun" else "palafitas-ambient")
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("pf_*.jpg"):
        f.unlink()
    lake = float(area["lake_level_m"])
    e0c, n0c, e1c, n1c = area["core_lv95"]
    origin = np.array(area.get("origin_lv95", [(e0c + e1c) / 2, (n0c + n1c) / 2]))
    rng = np.random.default_rng(int(cfg.get("seed", 7)))
    polys, water = select_palafitas(area, build, raw)
    with rasterio.open(build / "dem_core.tif") as s:
        demv, dtr = s.read(1), s.transform
    lines = lane_lines(area, build)
    houses = [house_params(g, rng, water, demv, dtr, lake) for g in polys]
    for h, g in zip(houses, polys):
        h.poly = g
        h.dist = min(ln.distance(Point(h.c)) for ln in lines) if lines else 1e9
        if lines and h.dist < float(cfg.get("veranda_to_route_m", 0)):
            # Veranda zur Strecke (zum Wasser) drehen: die Hausfront liegt dann vorne an der Bahn
            ln = min(lines, key=lambda L_: L_.distance(Point(h.c)))
            q = ln.interpolate(ln.project(Point(h.c)))
            h.ver_side = 1 if (np.array([q.x, q.y]) - h.c) @ h.v > 0 else -1
    # Häuser nicht in die Bahn bauen: Mindestabstand 2,5 m (Kante – Bahn)
    keep = []
    for h in houses:
        rad = math.hypot(h.L / 2 + 0.3, h.W / 2 + h.ver)
        if h.dist - rad < float(cfg.get("lane_min_m", 2.5)):
            # kleinere Hausbreite versuchen
            h.L = max(4.5, h.L * 0.75); h.W = max(3.6, h.W * 0.8); h.ver = 1.2
            rad = math.hypot(h.L / 2 + 0.3, h.W / 2 + h.ver)
            if h.dist - rad < float(cfg.get("lane_min_m", 2.5)) * 0.6:
                continue
        keep.append(h)
    houses = keep
    print(f"palafitas: {len(polys)} Grundrisse ausgewählt, {len(houses)} Pfahlbauten "
          f"(nah ≤ {cfg.get('detail_m', 110)} m: {sum(h.dist <= float(cfg.get('detail_m', 110)) for h in houses)})",
          flush=True)
    # Gruppen: nah (detailliert, feine Textur) in Paketen zu ~45 Häusern entlang der Strecke, fern grob
    detail_m = float(cfg.get("detail_m", 110))
    mid_m = float(cfg.get("mid_m", 320))
    near = sorted([h for h in houses if h.dist <= detail_m], key=lambda h: (h.c[0] + h.c[1]))
    far_ = [h for h in houses if h.dist > detail_m]
    groups = []
    if near:
        # räumlich: nach Projektion auf die Hauptrichtung sortiert
        C = np.array([h.c for h in near]); d0 = C - C.mean(0)
        ax = np.linalg.svd(d0, full_matrices=False)[2][0]
        near.sort(key=lambda h: float((h.c - C.mean(0)) @ ax))
        k = int(cfg.get("group_size", 45))
        for i in range(0, len(near), k):
            groups.append((near[i:i + k], True, float(cfg.get("tex_m", 0.07))))
    if far_:
        # mittel (bis mid_m) und fern: einfache Form, je km-Zelle ein Mesh, gröbere Textur
        C = np.array([h.c for h in far_])
        key = np.floor((C - [e0c, n0c]) / 1000.0).astype(int)
        band = np.array([0 if h.dist <= mid_m else 1 for h in far_])
        for b_ in (0, 1):
            for kk in sorted({tuple(x) for x, bb in zip(key, band) if bb == b_}):
                hs_ = [h for h, x, bb in zip(far_, key, band) if tuple(x) == kk and bb == b_]
                groups.append((hs_, False, float(cfg.get("tex_mid_m", 0.18)) if b_ == 0 else 0.5))
    save, meta = {}, {"groups": [], "houses": len(houses), "light": light}
    feats = []
    gi = 0
    for hs, detail, tex_m in groups:
        mb = MeshBuilder()
        mb.H = []
        idx0 = {id(h): j for j, h in enumerate(hs)}
        for j, h in enumerate(hs):
            build_house(mb, h, origin, detail, rng, j)
            feats.append({"type": "Feature", "properties": {"floor_m": round(h.floor, 2)},
                          "geometry": mapping(h.poly.minimum_rotated_rectangle)})
        if detail and cfg.get("walkways", True):
            C = np.array([h.c for h in hs])
            done = set()
            for j, h in enumerate(hs):
                d = np.linalg.norm(C - h.c, axis=1)
                d[j] = 1e9
                for k_ in np.argsort(d)[:2]:
                    if d[k_] > 22 or (min(j, k_), max(j, k_)) in done:
                        continue
                    done.add((min(j, k_), max(j, k_)))
                    o = hs[k_]
                    seg = LineString([h.c, o.c])
                    # Steg nur, wo er nicht über die Bahn führt
                    if any(seg.distance(ln) < 3.0 for ln in lines):
                        continue
                    z = min(h.floor, o.floor) - 0.15
                    build_walkway(mb, h.c, o.c, z, origin, j)
        if detail and cfg.get("canoes", 0.35):
            for j, h in enumerate(hs):
                if not h.wet or rng.random() > float(cfg.get("canoes", 0.35)):
                    continue
                # an der der Strecke abgewandten Seite
                side = 1.0
                if lines:
                    p_plus = Point(h.c + h.v * 3); p_min = Point(h.c - h.v * 3)
                    side = 1.0 if min(ln.distance(p_plus) for ln in lines) > min(ln.distance(p_min) for ln in lines) else -1.0
                cc = h.c + h.v * side * (h.W / 2 + (h.ver if h.ver_side == side else 0) + 1.1) + h.u * (rng.random() - 0.5) * h.L * 0.5
                build_canoe(mb, cc, h.u, origin, j, length=5.0 + 2.5 * rng.random(), width=0.8 + 0.25 * rng.random())
        V, F, M = mb.arrays()
        if len(F) == 0:
            continue
        FH = np.array(mb.H, np.int64)
        name = f"pf_{gi}"
        gi += 1
        lo = V[:, :2].min(0) + origin - 120; hi = V[:, :2].max(0) + origin + 120
        occ_v, occ_f = palafita_occluders(area, origin, (lo[0], lo[1], hi[0], hi[1]))
        arrs, atlas = bake_group(name, V, F, M, FH, hs, occ_v, occ_f, out, procs, tex_m, light, origin)
        save.update(arrs)
        meta["groups"].append({"name": name, "houses": len(hs), "detail": detail, "tris": int(len(arrs[f"{name}__f"])),
                               "atlas": list(atlas)})
        print(f"  {name}: {len(hs)} Häuser, {len(arrs[f'{name}__f']):,} Dreiecke, Atlas {atlas}", flush=True)
        del idx0
    np.savez_compressed(out / "palafitas.npz", **save)
    meta["meshes"] = [g["name"] for g in meta["groups"]]
    meta["tris"] = sum(g["tris"] for g in meta["groups"])
    (out / "meta.json").write_text(json.dumps(meta, indent=1))
    if light == "sun":
        (out / "footprints.geojson").write_text(json.dumps({"type": "FeatureCollection", "features": feats}))
        remove_from_buildings(build, [h.poly for h in houses], polys)
    print(f"palafitas: {len(houses)} Häuser, {meta['tris']:,} Dreiecke → {out}", flush=True)


def remove_from_buildings(build, used, selected):
    """Die als Pfahlbau gebauten (und die wegen der Bahn verworfenen) Grundrisse aus buildings_fp_*.npz nehmen."""
    from shapely import STRtree
    from shapely.geometry import Point
    tree = STRtree(selected)
    n_drop = 0
    for f in sorted(build.glob("buildings_fp_*.npz")):
        d = dict(np.load(f))
        nb = len(d["centers"])
        if nb == 0:
            continue
        drop = np.zeros(nb, bool)
        for i, (cx, cy, _, _) in enumerate(d["centers"]):
            hit = tree.query(Point(cx, cy), predicate="within")
            drop[i] = len(hit) > 0
        if not drop.any():
            continue
        keep_ids = np.flatnonzero(~drop)
        remap = -np.ones(nb, np.int64)
        remap[keep_ids] = np.arange(len(keep_ids))
        out = {"centers": d["centers"][keep_ids]}
        for k in ("roof", "wall"):
            fm = ~drop[d[f"bid_{k}"]]
            out[f"{k}_v"] = d[f"{k}_v"]
            out[f"{k}_f"] = d[f"{k}_f"][fm]
            out[f"bid_{k}"] = remap[d[f"bid_{k}"][fm]].astype(np.int32)
        np.savez_compressed(f, **out)
        n_drop += int(drop.sum())
    print(f"  aus den Gebäuden genommen: {n_drop}", flush=True)


# ============================================================================= Zwei Wasserfarben

def water_tint_texture(area, build):
    """RGBA-Textur (Farbe, Deckkraft) und Grenzen für die Wasserfarbe ("water_tint")."""
    import rasterio
    from rasterio.enums import Resampling
    from rasterio.features import rasterize
    from rasterio.windows import from_bounds
    from scipy import ndimage
    from shapely.geometry import shape
    cfg = area["water_tint"]
    b = cfg.get("bounds_lv95", area["far_lv95"])
    px = float(cfg.get("px_m", 4.0))
    W, H = int(round((b[2] - b[0]) / px)), int(round((b[3] - b[1]) / px))
    with rasterio.open(build / "ortho_far.tif") as s:
        img = s.read([1, 2, 3], window=from_bounds(*b, s.transform), out_shape=(3, H, W), boundless=True,
                     fill_value=0, resampling=Resampling.average).astype(np.float32)
        tr = rasterio.transform.from_bounds(*b, W, H)
    wf = shape(json.loads((build / "water_far.geojson").read_text())["geometry"])
    wm = rasterize([wf], out_shape=(H, W), transform=tr).astype(bool)
    wm = ndimage.binary_erosion(wm, iterations=max(1, int(30 / px)))   # Uferpixel (Mischfarbe mit Land) weg
    L = 0.3 * img[0] + 0.5 * img[1] + 0.2 * img[2]
    # Boote, Wellen, Sonnenglitzern: Median 3 × 3
    L = ndimage.median_filter(L, 5)
    lv = np.asarray(cfg.get("levels") or np.percentile(L[wm], [15, 85]), float)
    t = np.clip((L - lv[0]) / max(lv[1] - lv[0], 1e-3), 0, 1)
    t = t * t * (3 - 2 * t)
    # Werte ausserhalb des Wassers vom nächsten Wasserpixel (unter dem Gelände unsichtbar, keine Säume am Ufer)
    _, (ri, ci) = ndimage.distance_transform_edt(~wm, return_indices=True)
    t = t[ri, ci]
    t = ndimage.gaussian_filter(t, float(cfg.get("smooth_m", 18)) / px)
    # feine Schlieren an der Grenze (Durchmischung)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32) * px
    E = b[0] + xx; N = b[3] - yy
    sw = vnoise(E * 0.8 + 3 * vnoise(E, N, 140.0) * 60, N, 55.0) - 0.5
    sw += 0.5 * (vnoise(E, N * 1.3, 18.0) - 0.5)
    t = np.clip(t + 0.55 * sw * 4 * t * (1 - t), 0, 1)
    dark = np.array(cfg.get("dark", [0.07, 0.045, 0.025]))
    light = np.array(cfg.get("light", [0.50, 0.36, 0.20]))
    al = np.array(cfg.get("alpha", [0.55, 0.9]))
    rgb = dark[None, None] * (1 - t[..., None]) + light[None, None] * t[..., None]
    a = al[0] * (1 - t) + al[1] * t
    fe = float(cfg.get("feather_m", 500))
    edge = np.minimum.reduce([xx, (W - 1) * px - xx, yy, (H - 1) * px - yy])
    a *= np.clip(edge / max(fe, 1), 0, 1)
    rgba = np.dstack([rgb, a[..., None]])
    stats = {"levels": [round(float(v), 1) for v in lv], "light_frac_water": round(float((t[wm] > 0.5).mean()), 3),
             "px_m": px, "size": [W, H]}
    return (np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), b, stats


def write_water_tint(sw, area, build, out_dir, frame):
    """Halbdurchsichtige Wasserfarbe 3 cm über dem App-Wasser unter /Scene/WaterTint (export.py). (Dreiecke, Texel)"""
    from PIL import Image
    from pxr import Sdf, UsdGeom, UsdShade
    if not area.get("water_tint"):
        return 0, 0
    rgba, b, stats = water_tint_texture(area, build)
    Image.fromarray(rgba, "RGBA").save(out_dir / "water_tint.png", optimize=True)
    st = sw.stage
    m = UsdShade.Material.Define(st, "/Scene/Materials/water_tint")
    sh = UsdShade.Shader.Define(st, "/Scene/Materials/water_tint/PBR")
    sh.CreateIdAttr("UsdPreviewSurface")
    # "roughness" (Standard 0,25): kleiner = stärker spiegelnd (Schwarzwasser im Igapó 0,08)
    sh.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(float(area["water_tint"].get("roughness", 0.25)))
    sh.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0.0)
    rd = UsdShade.Shader.Define(st, "/Scene/Materials/water_tint/st")
    rd.CreateIdAttr("UsdPrimvarReader_float2")
    rd.CreateInput("varname", Sdf.ValueTypeNames.Token).Set("st")
    tx = UsdShade.Shader.Define(st, "/Scene/Materials/water_tint/tex")
    tx.CreateIdAttr("UsdUVTexture")
    tx.CreateInput("file", Sdf.ValueTypeNames.Asset).Set("water_tint.png")
    tx.CreateInput("st", Sdf.ValueTypeNames.Float2).ConnectToSource(rd.ConnectableAPI(), "result")
    tx.CreateInput("wrapS", Sdf.ValueTypeNames.Token).Set("clamp")
    tx.CreateInput("wrapT", Sdf.ValueTypeNames.Token).Set("clamp")
    tx.CreateOutput("rgb", Sdf.ValueTypeNames.Float3)
    tx.CreateOutput("a", Sdf.ValueTypeNames.Float)
    sh.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).ConnectToSource(tx.ConnectableAPI(), "rgb")
    sh.CreateInput("opacity", Sdf.ValueTypeNames.Float).ConnectToSource(tx.ConnectableAPI(), "a")
    m.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(), "surface")
    UsdGeom.Xform.Define(st, "/Scene/WaterTint")
    # Gitter 16 × 16 (eine Fläche wäre zu gross für Tiefenpuffer/Interpolation), y = +0,03 m
    k = 16
    es = np.linspace(b[0], b[2], k + 1); ns = np.linspace(b[1], b[3], k + 1)
    E, N = np.meshgrid(es, ns)
    pts = frame.xyz(E.ravel(), N.ravel(), np.full(E.size, frame.h0 + 0.03))
    uv = np.column_stack([((E - b[0]) / (b[2] - b[0])).ravel(), ((N - b[1]) / (b[3] - b[1])).ravel()])
    idx = np.arange((k + 1) ** 2).reshape(k + 1, k + 1)
    a_, b_, c_, d_ = idx[:-1, :-1], idx[:-1, 1:], idx[1:, :-1], idx[1:, 1:]
    faces = np.concatenate([np.stack([a_, b_, d_], -1).reshape(-1, 3), np.stack([a_, d_, c_], -1).reshape(-1, 3)])
    # nach oben zeigen (y): Reihenfolge prüfen
    v0, v1, v2 = pts[faces[0, 0]], pts[faces[0, 1]], pts[faces[0, 2]]
    if np.cross(v1 - v0, v2 - v0)[1] < 0:
        faces = faces[:, [0, 2, 1]]
    nrm = np.tile([0.0, 1.0, 0.0], (len(pts), 1))
    sw.mesh("/Scene/WaterTint/tint", pts, faces, m, uv=uv, normals=nrm)
    print(f"  Wasserfarbe: {json.dumps(stats)}", flush=True)
    return len(faces), rgba.shape[0] * rgba.shape[1]


def write_palafitas(sw, area, build, out_dir):
    """Pfahlbauten (amazonas.py palafitas → build/<gebiet>/palafitas/) unter /Scene/Palafitas. (Dreiecke, Texel)"""
    import shutil
    from PIL import Image  # noqa: F401
    from pxr import UsdGeom
    if not area.get("palafitas"):
        return 0, 0
    d = build / "palafitas"
    if not (d / "palafitas.npz").exists():
        sys.exit(f"Fehlt: {d}/palafitas.npz – zuerst amazonas.py palafitas laufen lassen")
    meta = json.loads((d / "meta.json").read_text())
    g = np.load(d / "palafitas.npz")
    UsdGeom.Xform.Define(sw.stage, "/Scene/Palafitas")
    t0, px = sw.n_tris, 0
    for gm in meta["groups"]:
        nm = gm["name"]
        v = g[f"{nm}__v"].astype(np.float64)
        n = g[f"{nm}__n"].astype(np.float64)
        shutil.copy(d / f"{nm}.jpg", out_dir / f"{nm}.jpg")
        px += gm["atlas"][0] * gm["atlas"][1]
        mat = sw.material_tex(nm, f"{nm}.jpg", rough=0.85)
        pts = np.column_stack([v[:, 0], v[:, 2], -v[:, 1]])
        nrm = np.column_stack([n[:, 0], n[:, 2], -n[:, 1]])
        sw.mesh(f"/Scene/Palafitas/{nm}", pts, g[f"{nm}__f"], mat, uv=g[f"{nm}__uv"], normals=nrm)
    return sw.n_tris - t0, px


def lane_obstacles(area, build):
    """Für lanes.py: Stämme im Wasser (1 m gepuffert) und Pfahlbauten (Grundrisse + 1,5 m) als Hindernisse."""
    from shapely.geometry import Point, shape
    from shapely.ops import unary_union
    parts = []
    f = build / "flooded_trunks.npy"
    if area.get("synth_forest") and f.exists():
        # überfluteter Wald als geschlossene Fläche (Stämme 4 m gepuffert, dann 2 m zurück): andere Ruderer und
        # Motorboote fahren nicht zwischen den Stämmen hindurch
        circles = [Point(x, y).buffer(r + 4.0, 4) for x, y, r in np.load(f)]
        if circles:
            g = unary_union(circles).buffer(-2.0).simplify(1.0)
            parts += list(getattr(g, "geoms", [g]))
    pf = build / "palafitas" / "footprints.geojson"
    if area.get("palafitas") and pf.exists():
        parts += [shape(ft["geometry"]).buffer(1.5) for ft in json.loads(pf.read_text())["features"]]
    return parts


if __name__ == "__main__":
    cmd, af = sys.argv[1], sys.argv[2]
    if cmd == "dem":
        dem(af)
    elif cmd == "palafitas":
        palafitas(af, light="ambient" if "--ambient" in sys.argv else "sun")
    elif cmd == "forest":
        from trees import Ctx
        ctx = Ctx(af)
        forest(ctx)
    elif cmd == "tint":
        a = _area(af)
        rgba, b, stats = water_tint_texture(a, Path("build") / a["id"])
        from PIL import Image
        Image.fromarray(rgba, "RGBA").save(Path("build") / a["id"] / "water_tint_check.png")
        print(json.dumps(stats))
    else:
        sys.exit(__doc__)
