"""Schritt 1: Kacheln zu Mosaiken zusammensetzen und die Seefläche bestimmen.

Ergebnis in build/<area>/:
  dem_core.tif   Höhenmodell Kerngebiet, 1 m (aus swissALTI3D 0,5 m gemittelt)
  dem_far.tif    Höhenmodell Umgebung, 4 m (aus swissALTI3D 2 m)
  ortho_far.tif  Luftbild Umgebung, 2 m
  water.geojson  Seefläche (LV95), aus dem Höhenmodell: zusammenhängende Fläche auf Seehöhe

Aufruf: .venv/bin/python prepare.py areas/zuerichsee-unteres-becken.json
"""
import json
import sys
from pathlib import Path

import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.features import shapes
from rasterio.merge import merge
from scipy import ndimage
from shapely.geometry import mapping, shape
from shapely.ops import unary_union


def mosaic(files, bounds, res, out, resampling=Resampling.average, dtype=None):
    srcs = [rasterio.open(f) for f in files]
    arr, transform = merge(srcs, bounds=bounds, res=res, resampling=resampling)
    meta = srcs[0].meta.copy()
    meta.update(height=arr.shape[1], width=arr.shape[2], transform=transform, driver="GTiff",
                compress="deflate", tiled=True)
    if dtype:
        meta["dtype"] = dtype
        arr = arr.astype(dtype)
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

    if not (out / "dem_core.tif").exists():
        mosaic(sorted((raw / "alti_core").glob("*.tif")), core, 1.0, out / "dem_core.tif")
    if not (out / "dem_far.tif").exists():
        mosaic(sorted((raw / "alti_far").glob("*.tif")), far, 4.0, out / "dem_far.tif")
    if not (out / "ortho_far.tif").exists() and (raw / "image_far").exists():
        mosaic(sorted((raw / "image_far").glob("*.tif")), far, 2.0, out / "ortho_far.tif",
               resampling=Resampling.bilinear)

    water = water_polygon(out / "dem_core.tif", area["lake_level_m"])
    (out / "water.geojson").write_text(json.dumps({"type": "Feature", "properties": {"crs": "EPSG:2056"},
                                                   "geometry": mapping(water)}))
    print(f"Seefläche im Kerngebiet: {water.area / 1e6:.2f} km²")


if __name__ == "__main__":
    main(sys.argv[1])
