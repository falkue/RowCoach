"""Schritt 1: Kacheln zu Mosaiken zusammensetzen und die Wasserfläche bestimmen.

Ergebnis in build/<area>/:
  dem_core.tif     Höhenmodell Kerngebiet, 1 m (aus swissALTI3D 0,5 m gemittelt)
  dem_far.tif      Höhenmodell Umgebung, 4 m (aus swissALTI3D 2 m)
  ortho_far.tif    Luftbild Umgebung, 2 m
  water.geojson    Wasserfläche im Kerngebiet (LV95)

Zwei Arten, die Wasserfläche zu bestimmen ("water_source" in der Gebietsdatei):
  "dem" (Standard, Seen): zusammenhängende ebene Fläche auf fester Seehöhe lake_level_m im Höhenmodell.
  "osm" (Flüsse; auch Seen möglich): Wasserpolygone aus OpenStreetMap (fetch.py → osm/overpass.json), am
        Höhenmodell nachgeschärft: sicher Wasser ist das OSM-Polygon 3 m nach innen; dazu kommt, was bis 8 m
        ausserhalb liegt und höchstens 0,5 m über dem örtlichen Wasserspiegel. Die Wasserhöhe (Szene y = 0) ist
        der Median des Höhenmodells im Wasser nahe den Start-/Zielpunkten der Strecken → water_meta.json
        (lake_level_m darf dann in der Gebietsdatei fehlen). "water_level_m" gibt die Wasserhöhe fest vor (Japan:
        GSI-Höhen sind über Wasser leer); dann bleiben grosse Gewässer (> 2 ha) auch bei abweichender Füllhöhe
        Wasser und das Gelände darunter kommt 0,8 m unter den Spiegel. Ufergelände, das tiefer als Wasserhöhe + 0,3 m
        liegt (flussabwärts fällt der Spiegel), wird auf diese Höhe angehoben, damit es nicht versinkt.
        Zusätzlich water_far.geojson (OSM-Wasser der Umgebung), damit export.py dort Seen/Fluss absenkt.
        "water_cut_lv95" (Polygone) trennt das OSM-Wasser, z. B. an einem Wehr, das OSM als eine Fläche mit Ober- und
        Unterwasser führt (Linz-Ottensheim): das Gewässer auf anderer Höhe bleibt dann Gelände.

Grenzgebiete: Lücken im Höhenmodell (Kacheln ausserhalb der Schweiz) werden mit dem Copernicus DEM GLO-30 gefüllt
("copernicus_tiles", fetch.py), Höhenversatz geschätzt, Übergang über 250 m weich; Lücken im Luftbild bekommen
eine ruhige, aus dem Gelände abgeleitete Farbe mit Schummerung (Sonne wie in der App), Übergang über 300 m.

Aufruf: .venv/bin/python prepare.py areas/<area>.json
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.features import rasterize, shapes
from rasterio.merge import merge
from rasterio.warp import reproject
from scipy import ndimage
from shapely.geometry import Point, box, mapping, shape
from shapely.ops import unary_union

from common import area_crs

NODATA_Z = -1000.0  # alles darunter gilt als Lücke (swissALTI3D: −9999)
SUN_AZ, SUN_EL = 235.0, 48.0  # wie bake.py / App


def mosaic(files, bounds, res, out, resampling=Resampling.average, dtype=None, post=None):
    srcs = [rasterio.open(f) for f in files]
    arr, transform = merge(srcs, bounds=bounds, res=res, resampling=resampling)
    meta = srcs[0].meta.copy()
    meta.update(height=arr.shape[1], width=arr.shape[2], transform=transform, driver="GTiff",
                compress="deflate", tiled=True)
    if dtype:
        meta["dtype"] = dtype
        arr = arr.astype(dtype)
    if post is not None:
        arr = post(arr, transform, meta)
    with rasterio.open(out, "w", **meta) as dst:
        dst.write(arr)
    for s in srcs:
        s.close()
    print(f"{out.name}: {arr.shape[2]}×{arr.shape[1]} px, {res} m", flush=True)


def water_polygon(dem_path, lake_level, tol=0.35, min_area=200_000):
    with rasterio.open(dem_path) as src:
        z = src.read(1)
        transform = src.transform
    flat = np.abs(z - lake_level) < tol
    # Seeoberfläche ist im Höhenmodell eben: zusätzlich sehr kleine Steigung verlangen
    gy, gx = np.gradient(z)
    flat &= (np.hypot(gx, gy) < 0.05)
    flat = ndimage.binary_opening(flat, iterations=2)
    lab, n = ndimage.label(flat)
    sizes = ndimage.sum(flat, lab, range(1, n + 1))
    keep = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s * abs(transform.a * transform.e) >= min_area])
    keep = ndimage.binary_closing(keep, iterations=3)
    keep = ndimage.binary_fill_holes(keep)
    polys = [shape(g) for g, v in shapes(keep.astype(np.uint8), mask=keep, transform=transform) if v == 1]
    water = unary_union(polys).simplify(1.0)
    return water


# ----------------------------------------------------------------------------- Lücken füllen (Grenzgebiete)

def copernicus_on_grid(raw, area, shape_hw, transform):
    """Copernicus GLO-30 (EGM2008) auf ein LV95-Raster umrechnen; NaN, wo keine Kachel vorliegt."""
    out = np.full(shape_hw, np.nan, np.float32)
    for t in area.get("copernicus_tiles", []):
        f = raw / "copernicus" / f"{t}.tif"
        if not f.exists():
            print(f"  fehlt: {f} – fetch.py laufen lassen", file=sys.stderr)
            continue
        tmp = np.full(shape_hw, np.nan, np.float32)
        with rasterio.open(f) as src:
            reproject(rasterio.band(src, 1), tmp, src_nodata=None, dst_transform=transform, dst_crs=area_crs(area),
                      dst_nodata=np.nan, resampling=Resampling.bilinear)
        out = np.where(np.isnan(out), tmp, out)
    return out


def fill_dem_far(arr, transform, meta, raw, area, feather_m=250.0):
    z = arr[0]
    hole = z < NODATA_Z
    if not hole.any():
        return arr
    res = abs(transform.a)
    cop = copernicus_on_grid(raw, area, z.shape, transform)
    both = ~hole & ~np.isnan(cop)
    if both.sum() < 1000:
        print("  Warnung: zu wenig Überlappung mit Copernicus – Lücken bleiben", file=sys.stderr)
        return arr
    d = (cop - z)[both]
    # Versatz Copernicus (Oberflächenmodell, EGM2008) → swissALTI3D (Gelände, LN02): häufigster Unterschied
    # (offenes Gelände), nicht der Mittelwert (Wald und Häuser stehen im Oberflächenmodell höher)
    hist, edges = np.histogram(d, bins=np.arange(-20, 40.25, 0.25))
    off = float(edges[np.argmax(hist)] + 0.125)
    cop = cop - off
    dist = ndimage.distance_transform_edt(~hole).astype(np.float32) * res  # Abstand zur Lücke (in den CH-Daten)
    w = np.clip(dist / feather_m, 0, 1)
    filled = np.where(hole, cop, w * z + (1 - w) * np.where(np.isnan(cop), z, cop))
    still = np.isnan(filled)
    if still.any():  # ausserhalb aller Kacheln: nächster Wert
        idx = ndimage.distance_transform_edt(still, return_distances=False, return_indices=True)
        filled = filled[tuple(idx)]
    print(f"  Höhenlücken gefüllt (Copernicus GLO-30): {hole.mean() * 100:.1f} % der Umgebung, "
          f"Versatz {off:+.2f} m, Übergang {feather_m:.0f} m", flush=True)
    arr[0] = filled.astype(arr.dtype)
    return arr


def fill_dem_core(arr, transform, meta, far_path, crs="EPSG:2056"):
    z = arr[0]
    hole = z < NODATA_Z
    if not hole.any():
        return arr
    tmp = np.full(z.shape, np.nan, np.float32)
    with rasterio.open(far_path) as src:
        reproject(rasterio.band(src, 1), tmp, dst_transform=transform, dst_crs=crs,
                  resampling=Resampling.bilinear)
    arr[0] = np.where(hole, tmp, z)
    print(f"  Kerngebiet: {hole.mean() * 100:.1f} % aus der Umgebung gefüllt", flush=True)
    return arr


def hillshade(z, res, az=SUN_AZ, el=SUN_EL):
    gy, gx = np.gradient(z, res)
    # Zeilen laufen nach Süden: Nordkomponente = −gy
    nx, ny, nz = -gx, gy, np.ones_like(z)
    ln = np.sqrt(nx * nx + ny * ny + 1)
    a, e = math.radians(az), math.radians(el)
    s = (math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e))
    return np.clip((nx * s[0] + ny * s[1] + nz * s[2]) / ln, 0, 1)


def fill_ortho_far(arr, transform, meta, dem_far_path, water_far, feather_m=300.0, coarse=4, strip=1024,
                   crs="EPSG:2056"):
    """Lücken im Luftbild (alle Kanäle 0) mit ruhiger Geländefarbe × Schummerung füllen.
    Farbe, Schummerung und Überblendgewicht entstehen auf einem 4× gröberen Raster (8 m) und werden
    streifenweise hochgerechnet, damit der Speicher klein bleibt."""
    hole = (arr[0] == 0) & (arr[1] == 0) & (arr[2] == 0)
    if not hole.any():
        return arr
    res = abs(transform.a)
    h, w = hole.shape
    hc, wc = (h + coarse - 1) // coarse, (w + coarse - 1) // coarse
    tr_c = transform * transform.scale(coarse, coarse)
    z = np.zeros((hc, wc), np.float32)
    with rasterio.open(dem_far_path) as src:
        reproject(rasterio.band(src, 1), z, dst_transform=tr_c, dst_crs=crs, resampling=Resampling.bilinear)
    z = ndimage.gaussian_filter(z, 1.0)  # 30-m-Höhen sind körnig: ruhiger
    shade = hillshade(z, res * coarse)
    flat = hillshade(np.zeros((3, 3)), 1.0)[1, 1]
    # Grundfarbe: Median der echten Luftbildpixel (Wiesen/Wald der Gegend), etwas entsättigt
    sel = np.flatnonzero(~hole.ravel()[::97]) * 97
    base = np.median(np.stack([arr[k].ravel()[sel] for k in range(3)]).astype(np.float32), axis=1)
    g = base.mean()
    base = g + (base - g) * 0.7
    synth = base[:, None, None] * (0.55 + 0.45 * (shade / flat))[None]
    if water_far is not None and not water_far.is_empty:
        wm = rasterize([water_far], out_shape=(hc, wc), transform=tr_c).astype(bool)
        synth[:, wm] = np.array([46, 66, 76], np.float32)[:, None]
    hole_c = hole[::coarse, ::coarse]
    hole_c = np.pad(hole_c, ((0, hc - hole_c.shape[0]), (0, wc - hole_c.shape[1])), mode="edge")
    # Gewicht des echten Luftbilds: 0 im Loch, steigt über feather_m an
    wreal = np.clip(ndimage.distance_transform_edt(~hole_c).astype(np.float32) * res * coarse / feather_m, 0, 1)
    wreal = np.where(hole_c, 0, wreal).astype(np.float32)
    rows_c = (np.arange(h) + 0.5) / coarse - 0.5
    cols_c = (np.arange(w) + 0.5) / coarse - 0.5
    for r0 in range(0, h, strip):
        r1 = min(h, r0 + strip)
        rr, cc = np.meshgrid(rows_c[r0:r1], cols_c, indexing="ij")
        coords = np.stack([rr.ravel(), cc.ravel()])
        wr = ndimage.map_coordinates(wreal, coords, order=1, mode="nearest").reshape(r1 - r0, w)
        wr[hole[r0:r1]] = 0
        for k in range(3):
            sy = ndimage.map_coordinates(synth[k], coords, order=1, mode="nearest").reshape(r1 - r0, w)
            arr[k, r0:r1] = np.clip(arr[k, r0:r1] * wr + sy * (1 - wr) + 0.5, 0, 255).astype(arr.dtype)
    print(f"  Luftbildlücken gefüllt: {hole.mean() * 100:.1f} % der Umgebung (Geländefarbe + Schummerung)",
          flush=True)
    return arr


# ----------------------------------------------------------------------------- Wasser aus OpenStreetMap

def osm_water_mask(area, out, core):
    from common import osm_water
    water_osm = osm_water(area)
    far = box(*area["far_lv95"])
    water_far = water_osm.intersection(far).simplify(2.0)
    (out / "water_far.geojson").write_text(json.dumps({"type": "Feature", "properties": {"crs": area_crs(area),
                                                       "source": "OpenStreetMap"},
                                                       "geometry": mapping(water_far)}))
    with rasterio.open(out / "dem_core.tif") as src:
        z = src.read(1).astype(np.float32)
        tr = src.transform
        meta = src.meta.copy()
    res = abs(tr.a)
    wo = rasterize([water_osm.intersection(box(*core).buffer(50))], out_shape=z.shape, transform=tr).astype(bool)
    # "water_cut_lv95": Polygone, die das OSM-Wasser trennen (z. B. Wehr/Kraftwerk zwischen Ober- und Unterwasser,
    # die OSM als eine Fläche führt): danach ist das Oberwasser ein eigenes Gewässer auf anderer Höhe und bleibt Gelände
    cut = None
    if area.get("water_cut_lv95"):
        from shapely.geometry import Polygon
        cut = rasterize([Polygon(pg) for pg in area["water_cut_lv95"]], out_shape=z.shape, transform=tr).astype(bool)
        wo &= ~cut
    sure = ndimage.binary_erosion(wo, iterations=int(3 / res))
    # Wasserhöhe für die Szene: Median nahe den Strecken
    refs = [r[k] for r in area.get("routes", []) for k in ("start_lv95", "toward_lv95") if k in r]
    refs += area.get("water_level_ref_lv95", [])
    rows, cols = np.nonzero(sure)
    E = tr.c + (cols + 0.5) * tr.a
    N = tr.f + (rows + 0.5) * tr.e
    if refs:
        near = np.zeros(len(E), bool)
        for e, n in refs:
            near |= (E - e) ** 2 + (N - n) ** 2 < 300.0 ** 2
    else:
        near = np.ones(len(E), bool)
    level = float(np.median(z[rows[near], cols[near]]))
    forced = area.get("water_level_m")  # fest vorgegeben (z. B. Japan: GSI-Höhen haben über Wasser keine Werte,
    if forced is not None:              # dort steht nur die Füllung aus der Umgebung)
        level = float(forced)
    spread = [float(np.median(z[rows[(E - e) ** 2 + (N - n) ** 2 < 300.0 ** 2],
                                cols[(E - e) ** 2 + (N - n) ** 2 < 300.0 ** 2]])) for e, n in refs] if refs else []
    # örtlicher Wasserspiegel (Fluss fällt ab): gewichtetes Mittel über ~60 m
    s = 60.0 / res
    num = ndimage.gaussian_filter(np.where(sure, z, 0).astype(np.float32), s)
    den = ndimage.gaussian_filter(sure.astype(np.float32), s)
    local = np.where(den > 1e-3, num / np.maximum(den, 1e-6), level)
    near_osm = ndimage.binary_dilation(wo, iterations=int(8 / res))
    cand = sure | (near_osm & (z < local + 0.5))
    if cut is not None:
        cand &= ~cut
    lab, n = ndimage.label(cand)
    keep_ids = np.unique(lab[sure])
    keep_ids = keep_ids[keep_ids > 0]
    # nur Gewässer auf Höhe des Hauptgewässers (Teiche, Kanäle oder Bäche auf anderer Höhe blieben sonst als
    # tiefe Gruben mit dem Wasser der Szene auf y = 0 stehen)
    med = ndimage.median(z, lab, keep_ids) if len(keep_ids) else []
    if forced is not None:  # grosse Gewässer (> 2 ha) behalten, auch wenn die Füllung darunter höher liegt
        big = ndimage.sum(sure, lab, keep_ids) * res * res if len(keep_ids) else []
        keep_ids = [i for i, m, a in zip(keep_ids, np.atleast_1d(med), np.atleast_1d(big))
                    if abs(m - level) < 1.5 or a > 20000]
    else:
        keep_ids = [i for i, m in zip(keep_ids, np.atleast_1d(med)) if abs(m - level) < 1.5]
    water = np.isin(lab, keep_ids)
    water = ndimage.binary_closing(ndimage.binary_opening(water, iterations=1), iterations=2)
    # kleine Löcher (< 30 m², z. B. Bojen, Messfehler) schliessen, grössere (Inseln, Pfeiler) behalten
    holes = ndimage.binary_fill_holes(water) & ~water
    hl, hn = ndimage.label(holes)
    if hn:
        hs = ndimage.sum(holes, hl, range(1, hn + 1)) * res * res
        hole_max = 300 if forced is not None else 30  # feste Wasserhöhe: dort steht unter Löchern nur die Füllung
        water |= np.isin(hl, [i + 1 for i, a in enumerate(hs) if a < hole_max])
    # Ufergelände nicht versinken lassen: Land bis 60 m vom Wasser mindestens level + 0.3
    # (nicht unterhalb eines Wehrs: liegt der örtliche Spiegel mehr als 1 m unter der Wasserhöhe, bleibt das Ufer)
    landnear = ~water & ndimage.binary_dilation(water, iterations=int(60 / res)) & (local >= level - 1.0)
    low = landnear & (z < level + 0.3)
    lift = np.where(low, level + 0.3 - z, 0)
    sunk = water & (z > level - 0.8) if forced is not None else np.zeros_like(water)
    if low.any() or sunk.any():
        z = np.where(low, level + 0.3, z)
        z = np.where(sunk, level - 0.8, z)  # Füllung unter dem Wasser unter den Spiegel legen
        meta.update(compress="deflate", tiled=True)
        with rasterio.open(out / "dem_core.tif", "w", **meta) as dst:
            dst.write(z.astype(meta["dtype"]), 1)
    polys = [shape(g) for g, v in shapes(water.astype(np.uint8), mask=water, transform=tr) if v == 1]
    wpoly = unary_union(polys).intersection(box(*core)).simplify(1.0)
    meta_out = {"water_level_m": round(level, 2), "method": "osm",
                "level_at_refs_m": [round(v, 2) for v in spread],
                "local_level_range_m": [round(float(np.percentile(local[water], 1)), 2),
                                        round(float(np.percentile(local[water], 99)), 2)],
                "lifted_land_px": int(low.sum()), "lifted_max_m": round(float(lift.max()), 2),
                "lifted_mean_m": round(float(lift[low].mean()), 2) if low.any() else 0.0,
                "osm_area_km2": round(water_osm.intersection(box(*core)).area / 1e6, 3),
                "water_area_km2": round(wpoly.area / 1e6, 3)}
    (out / "water_meta.json").write_text(json.dumps(meta_out, indent=1))
    print("Wasser (OSM + Höhenmodell):", json.dumps(meta_out), flush=True)
    return wpoly


def main(area_file):
    area_path = Path(area_file)
    area = json.loads(area_path.read_text())
    raw = (area_path.parent / area["data_dir"]).resolve() if not Path(area["data_dir"]).is_absolute() else Path(area["data_dir"])
    if not raw.exists():
        raw = (Path.cwd() / area["data_dir"]).resolve()
    out = Path("build") / area["id"]
    out.mkdir(parents=True, exist_ok=True)
    core = area["core_lv95"]
    far = area["far_lv95"]
    osm = area.get("water_source", "dem") == "osm"
    water_far = None
    if osm:
        from common import osm_water
        water_far = osm_water(area).intersection(box(*far))

    # Rohdaten-Ordner: swisstopo (fetch.py) bzw. "raster_dirs" der Gebietsdatei, z. B. für fetch_de.py
    # {"alti_core": "dgm", "alti_far": "dgm"} (DGM1-Kacheln für Kern und Umgebung)
    rd = {"alti_core": "alti_core", "alti_far": "alti_far", "image_far": "image_far", **area.get("raster_dirs", {})}
    crs = area_crs(area)
    if not (out / "dem_far.tif").exists():
        mosaic(sorted((raw / rd["alti_far"]).glob("*.tif")), far, 4.0, out / "dem_far.tif",
               post=lambda a, t, m: fill_dem_far(a, t, m, raw, area))
    if not (out / "dem_core.tif").exists():
        mosaic(sorted((raw / rd["alti_core"]).glob("*.tif")), core, 1.0, out / "dem_core.tif",
               post=lambda a, t, m: fill_dem_core(a, t, m, out / "dem_far.tif", crs))
    if not (out / "ortho_far.tif").exists() and (raw / rd["image_far"]).exists():
        mosaic(sorted((raw / rd["image_far"]).glob("*.tif")), far, 2.0, out / "ortho_far.tif",
               resampling=Resampling.bilinear,
               post=lambda a, t, m: fill_ortho_far(a, t, m, out / "dem_far.tif", water_far, crs=crs))

    if osm:
        water = osm_water_mask(area, out, core)
    else:
        water = water_polygon(out / "dem_core.tif", area["lake_level_m"])
    (out / "water.geojson").write_text(json.dumps({"type": "Feature", "properties": {"crs": area_crs(area)},
                                                   "geometry": mapping(water)}))
    print(f"Seefläche im Kerngebiet: {water.area / 1e6:.2f} km²")


if __name__ == "__main__":
    main(sys.argv[1])
