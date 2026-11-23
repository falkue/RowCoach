"""Schritt 6: kleine Luftbildkarte je Strecke für den Navigator in der App.

Schneidet aus dem Luftbild (SWISSIMAGE 2 m) ein quadratisches Gebiet um die Strecke und trägt Datei und
Ausschnitt (Szenenkoordinaten x/z) als optionales Feld `minimap` in course.json ein. Genordet: x nach rechts,
z (= −Nord) nach unten, wie die Bildzeilen.

Aufruf (nach export.py): .venv/bin/python minimap.py areas/<area>.json
"""
import json
import sys
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image, ImageEnhance
from rasterio.enums import Resampling
from rasterio.windows import from_bounds

SIZE = 512
MARGIN = 250.0  # m um die Strecke


def main(area_file):
    from common import course_origin, load_area
    area = load_area(area_file)
    build = Path("build") / area["id"]
    courses = Path("../../courses")
    for r in area["routes"]:
        cj = courses / r["id"] / "course.json"
        c = json.loads(cj.read_text())
        e0, n0 = course_origin(c)
        p = np.array(c["path_xz"])
        xmin, xmax = p[:, 0].min() - MARGIN, p[:, 0].max() + MARGIN
        zmin, zmax = p[:, 1].min() - MARGIN, p[:, 1].max() + MARGIN
        # quadratisch machen
        side = max(xmax - xmin, zmax - zmin)
        cx, cz = (xmin + xmax) / 2, (zmin + zmax) / 2
        xmin, xmax, zmin, zmax = cx - side / 2, cx + side / 2, cz - side / 2, cz + side / 2
        # Szenen-z → LV95-N: N = N0 − z
        bounds = (e0 + xmin, n0 - zmax, e0 + xmax, n0 - zmin)
        with rasterio.open(build / "ortho_far.tif") as src:
            win = from_bounds(*bounds, src.transform)
            img = src.read([1, 2, 3], window=win, out_shape=(3, SIZE, SIZE), resampling=Resampling.average,
                           boundless=True, fill_value=40)
        im = Image.fromarray(np.moveaxis(img, 0, -1))
        im = ImageEnhance.Brightness(ImageEnhance.Color(im).enhance(0.8)).enhance(0.85)  # ruhiger Hintergrund
        im.save(cj.parent / "minimap.jpg", quality=85)
        c["minimap"] = {"image": "minimap.jpg",
                        "bounds_xz": [round(xmin, 2), round(zmin, 2), round(xmax, 2), round(zmax, 2)]}
        # Übersicht für die Streckenauswahl: weiter gefasst (Seite 2,6 × Streckenausdehnung, mind. 3 km), damit
        # auch breite Kacheln ohne Ränder gefüllt werden
        oside = max(side * 2.6, 3000.0)
        oxmin, oxmax, ozmin, ozmax = cx - oside / 2, cx + oside / 2, cz - oside / 2, cz + oside / 2
        obounds = (e0 + oxmin, n0 - ozmax, e0 + oxmax, n0 - ozmin)
        with rasterio.open(build / "ortho_far.tif") as src:
            win = from_bounds(*obounds, src.transform)
            img = src.read([1, 2, 3], window=win, out_shape=(3, 900, 900), resampling=Resampling.average,
                           boundless=True, fill_value=40)
        om = Image.fromarray(np.moveaxis(img, 0, -1))
        om = ImageEnhance.Brightness(ImageEnhance.Color(om).enhance(0.85)).enhance(0.9)
        om.save(cj.parent / "overview.jpg", quality=82)
        c["overview"] = {"image": "overview.jpg",
                         "bounds_xz": [round(oxmin, 2), round(ozmin, 2), round(oxmax, 2), round(ozmax, 2)]}
        cj.write_text(json.dumps(c, ensure_ascii=False))
        print(f"{r['id']}: minimap.jpg, {side:.0f} m Seitenlänge")


if __name__ == "__main__":
    main(sys.argv[1])
