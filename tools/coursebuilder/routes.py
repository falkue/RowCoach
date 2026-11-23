"""Schritt 2: Ruderstrecken entlang des Ufers erzeugen.

Jede Strecke folgt der Uferlinie in festem Abstand (offset_m) auf dem See, von einem Startpunkt
Richtung eines Zielpunkts, bis die halbe Länge erreicht ist; dort liegt der Wendepunkt.
Die Rückfahrt ist dieselbe Linie rückwärts (im 3D etwas versetzt, damit sich die Bahnen nicht decken).

Ergebnis: build/<area>/routes.geojson und route_preview.png (Luftbild + Strecken zur Kontrolle).
"""
import json
import sys
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image, ImageDraw
from rasterio.windows import from_bounds
from shapely.geometry import LineString, Point, mapping, shape
from shapely.ops import substring


def shore_path(water, offset, start, toward, length):
    inner = water.buffer(-offset, join_style="round").buffer(0)
    if inner.geom_type == "MultiPolygon":
        inner = max(inner.geoms, key=lambda g: g.area)
    ring = LineString(inner.exterior.coords)
    L = ring.length
    s0 = ring.project(Point(start))
    s1 = ring.project(Point(toward))
    # Richtung wählen, in der toward schneller erreicht wird
    fwd = (s1 - s0) % L
    direction = 1 if fwd <= L / 2 else -1
    pts = []
    step = 2.0
    for d in np.arange(0, length * 1.15 + step, step):
        s = (s0 + direction * d) % L
        pts.append(ring.interpolate(s).coords[0])
    line = LineString(pts)
    # leicht glätten (gleitender Mittelwert), dann auf 1 m neu abtasten
    xy = np.array(line.coords)
    k = 30
    pad = np.pad(xy, ((k, k), (0, 0)), mode="edge")
    kernel = np.ones(2 * k + 1) / (2 * k + 1)
    sm = np.column_stack([np.convolve(pad[:, 0], kernel, "valid"), np.convolve(pad[:, 1], kernel, "valid")])
    line = LineString(sm)
    line = substring(line, 0, min(length, line.length))
    n = int(line.length) + 1
    return LineString([line.interpolate(i).coords[0] for i in range(n)] + [line.coords[-1]])


def main(area_file):
    area = json.loads(Path(area_file).read_text())
    out = Path("build") / area["id"]
    water = shape(json.loads((out / "water.geojson").read_text())["geometry"])
    feats = []
    for r in area["routes"]:
        half = r["length_m"] / 2
        line = shore_path(water, r["offset_m"], r["start_lv95"], r["toward_lv95"], half)
        feats.append({"type": "Feature", "properties": {"id": r["id"], "title": r["title"],
                      "one_way_m": round(line.length, 1), "total_m": round(2 * line.length, 1)},
                      "geometry": mapping(line)})
        print(f"{r['id']}: {line.length:.0f} m hin, Wende bei {tuple(round(c) for c in line.coords[-1])}")
    (out / "routes.geojson").write_text(json.dumps({"type": "FeatureCollection", "features": feats}))

    # Vorschau
    e0, n0, e1, n1 = area["core_lv95"]
    with rasterio.open(out / "ortho_far.tif") as src:
        win = from_bounds(e0, n0, e1, n1, src.transform)
        img = src.read([1, 2, 3], window=win)
    im = Image.fromarray(np.moveaxis(img, 0, -1)).convert("RGB")
    sx = im.width / (e1 - e0)
    sy = im.height / (n1 - n0)
    px = lambda c: ((c[0] - e0) * sx, (n1 - c[1]) * sy)
    dr = ImageDraw.Draw(im)
    polys = water.geoms if water.geom_type == "MultiPolygon" else [water]
    for p in polys:
        dr.line([px(c) for c in p.exterior.coords], fill=(0, 200, 255), width=2)
    colors = [(255, 60, 60), (255, 220, 0), (60, 255, 60)]
    for f, col in zip(feats, colors):
        cs = f["geometry"]["coordinates"]
        dr.line([px(c) for c in cs], fill=col, width=5)
        a, b = px(cs[0]), px(cs[-1])
        dr.ellipse([a[0] - 9, a[1] - 9, a[0] + 9, a[1] + 9], fill=(255, 255, 255))
        dr.ellipse([b[0] - 9, b[1] - 9, b[0] + 9, b[1] + 9], fill=col, outline=(0, 0, 0))
        dr.text((a[0] + 12, a[1] - 8), f["properties"]["title"], fill=(255, 255, 255))
    im.save(out / "route_preview.png")
    print("Vorschau:", out / "route_preview.png")


if __name__ == "__main__":
    main(sys.argv[1])
