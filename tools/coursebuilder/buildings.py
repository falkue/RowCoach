"""Schritt 3: Gebäude aus swissBUILDINGS3D 3.0 (CityGML) lesen und triangulieren.

Liest die grossen GML-Dateien als Strom (iterparse), behält Gebäude innerhalb von buildings_lv95,
trianguliert Dach- und Wandflächen und speichert sie als kompakte Arrays:
  build/<area>/buildings_<blatt>.npz  mit  roof_v, roof_f, wall_v, wall_f, bid_roof, bid_wall, centers
Koordinaten bleiben LV95/LN02 (Meter), float64 → später in lokale Szenenkoordinaten.

Aufruf: .venv/bin/python buildings.py areas/<area>.json
"""
import json
import sys
from multiprocessing import Pool
from pathlib import Path

import mapbox_earcut as earcut
import numpy as np
from lxml import etree

NS = {
    "bldg": "http://www.opengis.net/citygml/building/2.0",
    "gml": "http://www.opengis.net/gml",
}
BLDG = "{%s}Building" % NS["bldg"]
KINDS = {"RoofSurface": "roof", "WallSurface": "wall"}


def triangulate(rings):
    """rings: [exterior, hole1, ...], jede (n,3). Liefert (verts, faces) oder None."""
    ext = rings[0]
    if len(ext) < 3:
        return None
    # Newell-Normale
    nrm = np.zeros(3)
    for a, b in zip(ext, np.roll(ext, -1, axis=0)):
        nrm += [(a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]), (a[0] - b[0]) * (a[1] + b[1])]
    ln = np.linalg.norm(nrm)
    if ln < 1e-9:
        return None
    nrm /= ln
    # Projektionsebene: die Achse mit grösster Normalkomponente weglassen
    drop = int(np.argmax(np.abs(nrm)))
    keep = [i for i in range(3) if i != drop]
    verts = np.vstack(rings)
    xy = (verts[:, keep] - verts[0, keep]).astype(np.float64)
    ends = np.cumsum([len(r) for r in rings]).astype(np.uint32)
    try:
        idx = earcut.triangulate_float64(xy, ends)
    except Exception:
        return None
    if len(idx) == 0:
        return None
    f = np.asarray(idx, dtype=np.int64).reshape(-1, 3)
    # Orientierung an Newell-Normale angleichen
    a, b, c = verts[f[:, 0]], verts[f[:, 1]], verts[f[:, 2]]
    flip = (np.cross(b - a, c - a) @ nrm) < 0
    f[flip] = f[flip][:, [0, 2, 1]]
    return verts, f


def parse_poslist(el):
    vals = np.array(el.text.split(), dtype=np.float64)
    pts = vals.reshape(-1, 3)
    if len(pts) > 1 and np.allclose(pts[0], pts[-1]):
        pts = pts[:-1]
    return pts


def free(b):
    b.clear()
    p = b.getparent()
    if p is not None:
        gp = p.getparent()
        if gp is not None:
            while p.getprevious() is not None:
                del gp[0]


def process(args):
    gml, bounds, out = args
    e0, n0, e1, n1 = bounds
    acc = {k: {"v": [], "f": [], "bid": [], "off": 0} for k in ("roof", "wall")}
    centers = []
    n_b = 0
    for _, b in etree.iterparse(str(gml), events=("end",), tag=BLDG, huge_tree=True):
        first = b.find(".//gml:posList", NS)
        if first is None:
            free(b); continue
        p0 = parse_poslist(first)[0]
        if not (e0 <= p0[0] <= e1 and n0 <= p0[1] <= n1):
            free(b)
            continue
        bid = len(centers)
        pts_all = []
        for surf in b.iter():
            tag = etree.QName(surf).localname
            kind = KINDS.get(tag)
            if not kind:
                continue
            for poly in surf.iter("{%s}Polygon" % NS["gml"]):
                rings = []
                for ring_parent in poly:
                    pl = ring_parent.find(".//gml:posList", NS)
                    if pl is not None:
                        rings.append(parse_poslist(pl))
                if not rings:
                    continue
                t = triangulate(rings)
                if t is None:
                    continue
                v, f = t
                a = acc[kind]
                a["v"].append(v); a["f"].append(f + a["off"]); a["bid"].append(np.full(len(f), bid, np.int32))
                a["off"] += len(v)
                pts_all.append(v)
        if pts_all:
            allp = np.vstack(pts_all)
            centers.append([*allp[:, :2].mean(axis=0), allp[:, 2].min(), allp[:, 2].max()])
            n_b += 1
        free(b)
    res = {"centers": np.array(centers)}
    for k, a in acc.items():
        res[f"{k}_v"] = np.vstack(a["v"]) if a["v"] else np.zeros((0, 3))
        res[f"{k}_f"] = np.vstack(a["f"]) if a["f"] else np.zeros((0, 3), np.int64)
        res[f"bid_{k}"] = np.concatenate(a["bid"]) if a["bid"] else np.zeros(0, np.int32)
    np.savez_compressed(out, **res)
    return f"{gml.name}: {n_b} Gebäude, Dach {len(res['roof_f'])} / Wand {len(res['wall_f'])} Dreiecke"


def main(area_file):
    area = json.loads(Path(area_file).read_text())
    out = Path("build") / area["id"]
    src = (Path.cwd() / area["data_dir"] / "buildings_x").resolve()
    bounds = area.get("buildings_lv95", area["core_lv95"])
    jobs = [(g, bounds, out / f"buildings_{g.stem.split('_')[-1]}.npz") for g in sorted(src.glob("*.gml"))]
    with Pool(len(jobs)) as p:
        for msg in p.imap_unordered(process, jobs):
            print(msg, flush=True)


if __name__ == "__main__":
    main(sys.argv[1])
