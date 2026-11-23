"""Schritt 4b: Brücken (swissBUILDINGS3D enthält keine Strassen- und Fussgängerbrücken).

Baut je Brücke ein schlankes Mesh (Fahrbahnplatte mit Brüstung bzw. Geländer, Unterseite als Balken mit Voute
oder als Bögen, Pfeiler mit Vorköpfen bis unter die Wasserlinie, Widerlager) und rechnet das Licht vor wie bake.py
für die Gebäude: Umgebungsverdeckung, Himmelssichtbarkeit und Sonnenschatten (Strahlen gegen Brücke, Gelände,
nahe Gebäude und die Wasserfläche), dazu eine Verdunkelung der Unterseiten, damit sie beim Durchfahren nicht hell
leuchten. Ergebnis je Gebiet (für alle Stufen gleich):
  build/<area>/bridges/bridges.npz   je Brücke br_<slug>__v/__f/__n/__uv (lokales ENU wie bake.py)
  build/<area>/bridges/br_<slug>.jpg Texturatlas (Material × Licht, Stein-/Betonstruktur aus der Weltlage)
  build/<area>/bridges/meta.json     Brücken, Pfeiler (Quelle), lichte Höhe an der Bahn, Abstände, Dreiecke
export.py hängt die Meshes unter /Scene/Bridges an, wenn die Gebietsdatei "bridges" enthält.

Daten:
  Grundriss: OpenStreetMap man_made=bridge (Umriss → Achse und Breite; © OpenStreetMap contributors, ODbL) oder
             eine Achse aus der Gebietsdatei (axis_lv95, z. B. aus swissTLM3D) bzw. ein OSM-Weg (axis_osm_way).
  Deckhöhe:  Fahrbahnachsen von swissTLM3D (3D-Linien mit KUNSTBAUTE = Bruecke; © swisstopo, OGD) aus
             data/raw/swisstlm3d/<area>.gpkg (fetch_tlm.py); deck_m in der Gebietsdatei ersetzt sie.
             "deck_from": "dsm" (Gebiete ohne swissTLM3D, z. B. Berlin): Höhe aus dem Oberflächenmodell
             (<data_dir>/bdom/*.tif, fetch_de.py) entlang der Achse, Median der mittleren Hälfte der Breite je 10 m,
             abzüglich deck_dsm_offset_m (Standard 0,3 m für Fahrzeuge, Geländer und Lampen).
  Pfeiler:   piers_lv95 (Luftbild, OSM bridge:support), piers_s (Lage auf der Achse in m), spans_m (bekannte
             Spannweiten, mittig auf dem Wasserabschnitt) oder spans_equal (geschätzt, gleiche Felder).

Gebietsdatei, Feld "bridges": Liste von Brücken, je Brücke u. a.
  name, slug, style ("beam" | "arch" | "substructure"), osm_outline | axis_lv95 | axis_osm_way, width_m,
  deck_m, depth_m ([Feldmitte, Pfeiler]), haunch_m, underside_m, spring_m, crown_m, pier_t_m, pier_len_m,
  pier_nose_m, parapet ("stone" | "railing" | "none"), pattern ("stone" | "concrete" | "truss" | "wood"),
  color, pier_color, pile_spacing_m (Holzjoche), pier_source (Text für den Bericht).

Aufruf: .venv/bin/python bridges.py areas/<area>.json [--procs 8] [--rays 7] [--light sun|ambient]
Mit --light ambient (Standard: sun) ohne Sonnenschatten nach build/<area>/bridges-ambient/ (für
export.py --light ambient; die Sonne macht dann die App live).
"""
import os
import sys

if "--device" not in sys.argv:
    os.environ["CUDA_VISIBLE_DEVICES"] = ""  # nur CPU, die GPU bleibt unberührt

import argparse  # noqa: E402
import json  # noqa: E402
from pathlib import Path  # noqa: E402

import mapbox_earcut as earcut  # noqa: E402
import numpy as np  # noqa: E402
import shapely  # noqa: E402
from shapely.geometry import LineString, Point, Polygon, shape  # noqa: E402

from common import _xy, load_area, osm_elements, to_proj  # noqa: E402

TEX_M = 0.12            # m je Texel
ATLAS_MAX = 2048
PARAPET = {"stone": (1.0, 0.45), "railing": (1.1, 0.14), "none": (0.0, 0.0)}  # Höhe, Dicke
ASPHALT = (0.30, 0.30, 0.31)
RAILING = (0.28, 0.30, 0.32)
UNDERSIDE = 0.55        # zusätzliche Verdunkelung nach unten gerichteter Flächen
PIER_BOTTOM = -3.0      # m unter Wasser
TLM_DIR = Path(__file__).resolve().parents[2] / "data" / "raw" / "swisstlm3d"


# ----------------------------------------------------------------------------- Achse, Höhe, Pfeiler

class Axis:
    """Polylinie in LV95 mit Bogenlänge s; u = Abstand nach links."""

    def __init__(self, pts):
        self.p = np.asarray(pts, float)
        d = np.diff(self.p, axis=0)
        self.seg = np.linalg.norm(d, axis=1)
        self.cum = np.r_[0, np.cumsum(self.seg)]
        self.L = float(self.cum[-1])
        t = d / self.seg[:, None]
        tv = np.vstack([t[:1], t[:-1] + t[1:], t[-1:]])
        self.tv = tv / np.linalg.norm(tv, axis=1, keepdims=True)
        self.line = LineString(self.p)

    def at(self, s):
        s = np.clip(np.asarray(s, float), 0, self.L)
        i = np.clip(np.searchsorted(self.cum, s, side="right") - 1, 0, len(self.seg) - 1)
        f = (s - self.cum[i]) / self.seg[i]
        pos = self.p[i] + (self.p[i + 1] - self.p[i]) * f[..., None]
        # Tangente: an Knicken gemittelt, damit die Querschnitte nicht überlappen
        t = self.tv[i] * (1 - f[..., None]) + self.tv[i + 1] * f[..., None]
        t /= np.linalg.norm(t, axis=-1, keepdims=True)
        n = np.stack([-t[..., 1], t[..., 0]], -1)  # links
        return pos, t, n

    def project(self, e, n):
        return self.line.project(Point(e, n))


def outline_axis(poly):
    rect = poly.minimum_rotated_rectangle
    c = np.array(rect.exterior.coords)[:4]
    e = [np.linalg.norm(c[(k + 1) % 4] - c[k]) for k in range(4)]
    k = int(np.argmax(e))
    a = (c[(k + 3) % 4] + c[k]) / 2
    b = (c[(k + 1) % 4] + c[(k + 2) % 4]) / 2
    return [a, b], float(e[(k + 1) % 4])


def dsm_deck_profile(area, axis, width, lake, offset=0.3, step=10.0):
    """Deckhöhe über Wasser [(s, z)] aus dem Oberflächenmodell (bDOM-Kacheln) entlang der Achse."""
    import rasterio
    from rasterio.merge import merge
    raw = (Path.cwd() / area["data_dir"]).resolve() / "bdom"
    e0, n0, e1, n1 = axis.line.buffer(width).bounds
    files = [f for f in sorted(raw.glob("*.tif"))
             if (lambda b: b.left < e1 and b.right > e0 and b.bottom < n1 and b.top > n0)(rasterio.open(f).bounds)]
    if not files:
        raise SystemExit(f"keine bDOM-Kachel unter der Brücke ({raw}) – fetch_de.py mit \"bdom\" oder deck_m setzen")
    srcs = [rasterio.open(f) for f in files]
    z, tr = merge(srcs, bounds=(e0, n0, e1, n1), res=0.5)
    for s_ in srcs:
        s_.close()
    z = z[0]
    out = []
    for s0 in np.arange(0, axis.L, step):
        ss = np.linspace(s0, min(s0 + step, axis.L), 9)
        pos, t, nrm = axis.at(ss)
        us = np.linspace(-width / 4, width / 4, 7)
        P = (pos[:, None, :] + nrm[:, None, :] * us[None, :, None]).reshape(-1, 2)
        col = ((P[:, 0] - tr.c) / tr.a).astype(int)
        row = ((P[:, 1] - tr.f) / tr.e).astype(int)
        ok = (col >= 0) & (col < z.shape[1]) & (row >= 0) & (row < z.shape[0])
        v = z[row[ok], col[ok]]
        v = v[v > -1000]
        if len(v):
            out.append((float(ss.mean()), float(np.median(v)) - lake - offset))
    return out


def tlm_bridge_lines(area):
    f = TLM_DIR / f"{area['id']}.gpkg"
    if not f.exists():
        return []
    from pyogrio import raw
    out = []
    for layer in ("strasse", "eisenbahn"):
        try:
            meta, _, geom, fields = raw.read(f, layer=layer)
        except Exception:
            continue
        fd = dict(zip(meta["fields"], fields))
        if "KUNSTBAUTE" not in fd:
            continue
        g = shapely.from_wkb(geom)
        for i in range(len(g)):
            if str(fd["KUNSTBAUTE"][i]).startswith("Bruecke"):
                out.append(g[i])
    return out


class Bridge:
    def __init__(self, cfg, area, water, els, tlm):
        self.cfg = cfg
        self.area = area
        self.name = cfg["name"]
        self.slug = cfg["slug"]
        self.style = cfg.get("style", "beam")
        self.sources = []
        if "axis_osm_way" in cfg:
            pts = _xy(els[cfg["axis_osm_way"]]["geometry"], to_proj(area))
            width = cfg["width_m"]
            self.sources.append(f"Achse OSM way {cfg['axis_osm_way']}")
        elif "axis_lv95" in cfg:
            pts, width = cfg["axis_lv95"], cfg["width_m"]
            self.sources.append("Achse aus swissTLM3D (Gebietsdatei)")
        else:
            poly = Polygon(_xy(els[cfg["osm_outline"]]["geometry"], to_proj(area))).buffer(0)
            pts, width = outline_axis(poly)
            self.sources.append(f"Umriss OSM way {cfg['osm_outline']}")
        if cfg.get("reverse"):
            pts = pts[::-1]
        self.axis = Axis(pts)
        self.W = float(cfg.get("width_m", width))
        L = self.axis.L
        # Wasserabschnitt auf der Achse
        wi = self.axis.line.intersection(water)
        parts = [g for g in getattr(wi, "geoms", [wi]) if not g.is_empty and g.length > 2]
        if parts:
            ss = [self.axis.project(*c) for g in parts for c in (g.coords[0], g.coords[-1])]
            self.w0, self.w1 = max(0.0, min(ss)), min(L, max(ss))
        else:
            self.w0, self.w1 = 0.0, L
        self._deck(tlm)
        self._piers()

    # Deckhöhe (Fahrbahn) über Wasser in Abhängigkeit von s
    def _deck(self, tlm):
        c = self.cfg
        lake = self.lake
        if "deck_m" in c:
            d = c["deck_m"]
            pts = [(0.0, d), (self.axis.L, d)] if np.isscalar(d) else [tuple(p) for p in d]
            self.deck_src = "deck_m (Gebietsdatei)"
        elif c.get("deck_from") == "dsm":
            pts = dsm_deck_profile(self.area, self.axis, self.W, lake, c.get("deck_dsm_offset_m", 0.3))
            self.deck_src = f"Oberflächenmodell bDOM ({len(pts)} Abschnitte à 10 m)"
        else:
            zone = self.axis.line.buffer(self.W / 2 + 2, cap_style="flat")
            sz = []
            for g in tlm:
                if not g.intersects(zone):
                    continue
                for x, y, z in shapely.get_coordinates(g, include_z=True):
                    if zone.contains(Point(x, y)):
                        sz.append((self.axis.project(x, y), z - lake))
            if not sz:
                raise SystemExit(f"{self.name}: keine swissTLM3D-Brückenachse gefunden – deck_m setzen")
            sz = np.array(sz)
            pick = self.cfg.get("deck_select", "max")
            bins = np.arange(0, self.axis.L + 10, 10.0)
            pts = []
            for b0 in bins:
                m = (sz[:, 0] >= b0) & (sz[:, 0] < b0 + 10)
                if m.any():
                    z = sz[m, 1].max() if pick == "max" else np.median(sz[m, 1])
                    pts.append((float(sz[m, 0].mean()), float(z)))
            self.deck_src = f"swissTLM3D ({len(sz)} Stützpunkte)"
        pts = sorted(pts)
        self.deck_s = np.array([p[0] for p in pts])
        self.deck_z = np.array([p[1] for p in pts])
        if len(pts) >= 3:  # leicht glätten (3er-Mittel), Enden bleiben
            z = self.deck_z.copy()
            z[1:-1] = (self.deck_z[:-2] + self.deck_z[1:-1] + self.deck_z[2:]) / 3
            self.deck_z = z

    def zt(self, s):
        return np.interp(s, self.deck_s, self.deck_z)

    def _piers(self):
        c = self.cfg
        a = self.axis
        s = []
        if "piers_lv95" in c:
            s = [a.project(*p) for p in c["piers_lv95"]]
        elif "piers_s" in c:
            s = list(c["piers_s"])
        elif "spans_m" in c:
            sp = np.array(c["spans_m"], float)
            mid = (self.w0 + self.w1) / 2 if c.get("spans_center", "water") == "water" else a.L / 2
            start = mid - sp.sum() / 2
            s = list(start + np.cumsum(sp)[:-1])
        elif "spans_equal" in c:
            n = int(c["spans_equal"])
            s = list(self.w0 + (self.w1 - self.w0) * np.arange(1, n) / n)
        elif "pile_spacing_m" in c:
            sp = c["pile_spacing_m"]
            n = max(1, int(round((self.w1 - self.w0) / sp)))
            s = list(self.w0 + (self.w1 - self.w0) * np.arange(1, n) / n)
        self.pier_s = sorted(float(x) for x in s)
        self.pier_t = c.get("pier_t_m", 2.5)
        self.pier_len = c.get("pier_len_m", self.W + 2 * c.get("pier_nose_m", 1.5))
        self.pier_nose = c.get("pier_nose_m", 1.5)

    def pier_footprints(self):
        """Pfeilergrundrisse in LV95 (Sechseck mit Vorköpfen, quer zur Achse)."""
        out = []
        if self.style == "substructure":
            for sp in self.pier_s:
                pos, t, n = self.axis.at(sp)
                for u in (-self.W / 2 + 0.4, self.W / 2 - 0.4):
                    out.append(Point(pos + n * u).buffer(0.25, cap_style="square"))
            return out
        h, half, nose = self.pier_t / 2, self.pier_len / 2, self.pier_nose
        for sp in self.pier_s:
            pos, t, n = self.axis.at(sp)
            ring = [(-h, -(half - nose)), (0, -half), (h, -(half - nose)), (h, half - nose), (0, half),
                    (-h, half - nose)]
            out.append(Polygon([tuple(pos + t * a_ + n * b_) for a_, b_ in ring]))
        return out


def load_bridges(area):
    """Brücken aus der Gebietsdatei (ohne Licht), z. B. für routes.py (Pfeilerabstände)."""
    from shapely.geometry import shape as _shape
    if not area.get("bridges"):
        return []
    build = Path("build") / area["id"]
    water = _shape(json.loads((build / "water.geojson").read_text())["geometry"])
    els = {el["id"]: el for el in osm_elements(area)} if (Path(area["data_dir"]) / "osm" / "overpass.json").exists() \
        else {}
    tlm = tlm_bridge_lines(area)
    Bridge.lake = area["lake_level_m"]
    return [Bridge(c, area, water, els, tlm) for c in area["bridges"]]


def pier_footprints(area):
    return [fp for b in load_bridges(area) for fp in b.pier_footprints()]


# ----------------------------------------------------------------------------- Geometrie

class MeshBuilder:
    def __init__(self):
        self.V, self.F, self.N, self.M = [], [], [], []  # Ecken, Dreiecke, Soll-Normale je Dreieck, Material
        self.n = 0

    def tri(self, a, b, c, normal, mat):
        a, b, c = np.asarray(a, float), np.asarray(b, float), np.asarray(c, float)
        fn = np.cross(b - a, c - a)
        if np.linalg.norm(fn) < 1e-8:
            return
        if fn @ normal < 0:
            b, c = c, b
        self.V += [a, b, c]
        self.F.append([self.n, self.n + 1, self.n + 2])
        self.n += 3
        self.M.append(mat)

    def quad(self, a, b, c, d, normal, mat):
        self.tri(a, b, c, normal, mat)
        self.tri(a, c, d, normal, mat)

    def prism(self, ring_en, z0, z1, mat, origin, top=True):
        """Senkrechtes Prisma über einem Ring (LV95), Seiten nach aussen, Deckel oben."""
        r = np.asarray(ring_en, float) - origin
        if Polygon(r).exterior.is_ccw is False:
            r = r[::-1]
        k = len(r)
        for i in range(k):
            a, b = r[i], r[(i + 1) % k]
            d = b - a
            nrm = np.array([d[1], -d[0], 0.0])
            self.quad([*a, z0], [*b, z0], [*b, z1], [*a, z1], nrm, mat)
        if top:
            idx = earcut.triangulate_float64(r.astype(np.float64), np.array([k], np.uint32)).reshape(-1, 3)
            for t in idx:
                self.tri([*r[t[0]], z1], [*r[t[1]], z1], [*r[t[2]], z1], np.array([0, 0, 1.0]), mat)

    def arrays(self):
        return np.array(self.V), np.array(self.F, np.int64), np.array(self.M, np.int32)


MAT_MAIN, MAT_TOP, MAT_PARAPET, MAT_PIER, MAT_UNDER = 0, 1, 2, 3, 4


def build_mesh(b, origin):
    """Mesh einer Brücke in lokalen ENU-Koordinaten (x = E − E0, y = N − N0, z über Wasser)."""
    c = b.cfg
    mb = MeshBuilder()
    W = b.W
    L = b.axis.L
    ph, pt = PARAPET[c.get("parapet", "railing")]
    if b.style == "substructure":
        ph, pt = 0.0, 0.0
    # Unterseite z_b(s)
    faces = []  # Pfeilerflächen (s) für Bögen
    for sp in b.pier_s:
        faces += [sp - b.pier_t / 2, sp + b.pier_t / 2]
    openings = []
    if b.style == "arch":
        edges = [b.w0] + faces + [b.w1]
        openings = [(edges[i], edges[i + 1]) for i in range(0, len(edges), 2)]
    spring = c.get("spring_m", 2.5)
    crown = c.get("crown_m", 1.3)
    dmid, dpier = (c.get("depth_m", 1.5), c.get("depth_m", 1.5)) if np.isscalar(c.get("depth_m", 1.5)) \
        else c["depth_m"]
    haunch = c.get("haunch_m", 30.0)

    def zb(s):
        s = np.asarray(s, float)
        top = b.zt(s)
        if "underside_m" in c:
            return np.minimum(np.full_like(s, c["underside_m"]), top - 0.5)
        if b.style == "substructure":
            return top - c.get("depth_m", 0.45)
        if b.style == "arch":
            z = np.full_like(s, spring)
            for a0, a1 in openings:
                m = (s >= a0) & (s <= a1)
                mid, half = (a0 + a1) / 2, (a1 - a0) / 2
                rise = max(0.5, float(b.zt(mid)) - crown - spring)
                z[m] = spring + rise * (1 - ((s[m] - mid) / half) ** 2)
            z[(s < b.w0) | (s > b.w1)] = -2.0  # Widerlager massiv bis ins Gelände
            return np.minimum(z, top - crown * 0.6)
        if b.pier_s:
            dist = np.min(np.abs(s[:, None] - np.array(b.pier_s)[None, :]), axis=1)
            w = np.clip(1 - dist / haunch, 0, 1) ** 2
        else:
            w = np.zeros_like(s)
        return top - (dmid + (dpier - dmid) * w)

    # Stationen
    step = 1.0 if b.style == "arch" else 2.0
    st = np.unique(np.r_[np.arange(0, L, step), L, [f for f in faces if 0 < f < L], b.w0, b.w1,
                         [p for p in b.pier_s if 0 < p < L]])
    pos, tan, nor = b.axis.at(st)
    pos = pos - origin
    ztop, zbot = b.zt(st), zb(st)
    # Querschnitt gegen den Uhrzeigersinn in (u, z): Unterseite, aussen rechts, Brüstung, Fahrbahn, …
    hw = W / 2

    def section(i):
        zt_, zb_ = ztop[i], zbot[i]
        if ph > 0:
            pts = [(-hw, zb_), (hw, zb_), (hw, zt_ + ph), (hw - pt, zt_ + ph), (hw - pt, zt_), (-hw + pt, zt_),
                   (-hw + pt, zt_ + ph), (-hw, zt_ + ph)]
            mats = [MAT_UNDER, MAT_MAIN, MAT_PARAPET, MAT_PARAPET, MAT_TOP, MAT_PARAPET, MAT_PARAPET, MAT_MAIN]
        else:
            pts = [(-hw, zb_), (hw, zb_), (hw, zt_), (-hw, zt_)]
            mats = [MAT_UNDER, MAT_MAIN, MAT_TOP, MAT_MAIN]
        return pts, mats

    def p3(i, u, z):
        return [pos[i][0] + nor[i][0] * u, pos[i][1] + nor[i][1] * u, z]

    for i in range(len(st) - 1):
        s0, m0 = section(i)
        s1, _ = section(i + 1)
        k = len(s0)
        for e in range(k):
            a0, b0 = s0[e], s0[(e + 1) % k]
            a1, b1 = s1[e], s1[(e + 1) % k]
            du, dz = b0[0] - a0[0], b0[1] - a0[1]
            nu, nz = dz, -du  # aussen (CCW)
            nn = np.array([nor[i][0] * nu, nor[i][1] * nu, nz])
            if np.linalg.norm(nn) < 1e-9:
                continue
            mb.quad(p3(i, *a0), p3(i, *b0), p3(i + 1, *b1), p3(i + 1, *a1), nn, m0[e])
    # Stirnseiten bis unter das Gelände (Widerlager)
    for i, sgn in ((0, -1.0), (len(st) - 1, 1.0)):
        pts, _ = section(i)
        pts = [(u, min(z, -2.5) if j < 2 else z) for j, (u, z) in enumerate(pts)]
        ring = np.array(pts)
        idx = earcut.triangulate_float64(ring.astype(np.float64), np.array([len(ring)], np.uint32)).reshape(-1, 3)
        nn = np.array([tan[i][0] * sgn, tan[i][1] * sgn, 0.0])
        for t in idx:
            mb.tri(p3(i, *ring[t[0]]), p3(i, *ring[t[1]]), p3(i, *ring[t[2]]), nn, MAT_MAIN)
    # Pfeiler bzw. Joche
    for fp, sp in zip(b.pier_footprints(), [s for s in b.pier_s for _ in (range(2) if b.style == "substructure"
                                                                           else range(1))]):
        top = float(zb(np.array([sp]))[0]) + 0.3
        mb.prism(list(fp.exterior.coords)[:-1], PIER_BOTTOM, top, MAT_PIER, origin)
    if b.style == "substructure":  # Querholm je Joch
        for sp in b.pier_s:
            p, t, n = b.axis.at(sp)
            z1 = float(zb(np.array([sp]))[0]); z0 = z1 - 0.35
            ring = [p + t * dt + n * du for dt, du in ((-0.15, -hw + 0.2), (0.15, -hw + 0.2), (0.15, hw - 0.2),
                                                      (-0.15, hw - 0.2))]
            mb.prism(ring, z0, z1, MAT_PIER, origin)
    V, F, M = mb.arrays()
    return V, F, M, (st, ztop, zbot, zb)


# ----------------------------------------------------------------------------- Material und Muster

def albedo(b, mat, P, N):
    c = b.cfg
    main = np.array(c.get("color", (0.68, 0.68, 0.66)))
    cols = {MAT_MAIN: main, MAT_UNDER: main, MAT_TOP: np.array(ASPHALT),
            MAT_PARAPET: np.array(c.get("parapet_color", main if c.get("parapet") == "stone" else RAILING)),
            MAT_PIER: np.array(c.get("pier_color", main))}
    if b.style == "substructure":
        cols[MAT_TOP] = main
    alb = np.array([cols[m] for m in range(5)])[mat].astype(np.float32)
    pat = c.get("pattern", "concrete")
    vert = np.abs(N[:, 2]) < 0.5
    # horizontale Koordinate in der Fläche (für senkrechte Flächen)
    tx = P[:, 0] * -N[:, 1] + P[:, 1] * N[:, 0]
    z = P[:, 2]
    rng = lambda a, b_: (np.sin(a * 12.9898 + b_ * 78.233) * 43758.5453) % 1.0  # noqa: E731
    if pat == "stone":
        row = np.floor(z / 0.5)
        col = np.floor((tx + row * 0.45) / 0.95)
        jz = (z / 0.5) % 1.0
        jx = ((tx + row * 0.45) / 0.95) % 1.0
        joint = vert & ((jz < 0.07) | (jx < 0.035))
        var = 0.88 + 0.2 * rng(row, col)
        f = np.where(vert, var, 1.0)
        f = np.where(joint, f * 0.72, f)
        alb *= f[:, None].astype(np.float32)
    elif pat in ("concrete", "truss"):
        panel = np.floor(tx / 2.5)
        f = 0.96 + 0.06 * rng(panel, np.floor(z / 1.25))
        alb *= np.where(vert, f, 1.0)[:, None].astype(np.float32)
    elif pat == "wood":
        f = 0.85 + 0.25 * rng(np.floor(tx / 0.25), 1.0)
        alb *= f[:, None].astype(np.float32)
    if c.get("parapet", "railing") == "railing" and b.style != "substructure":
        # Geländer: oberster Streifen der Aussenseite dunkel, mit hellem Handlauf und Pfosten alle 2 m
        s_ax = axis_s(b, P[:, 0] + b.origin[0], P[:, 1] + b.origin[1])
        zt_p = b.zt(s_ax)
        band = vert & (mat == MAT_MAIN) & (z > zt_p - 0.02)
        post = ((tx / 2.0) % 1.0) < 0.05
        rail = z > zt_p + PARAPET["railing"][0] - 0.12
        col = np.where((post | rail)[:, None], np.array([0.55, 0.57, 0.58]), np.array([0.20, 0.21, 0.22]))
        alb[band] = col[band].astype(np.float32)
    if pat == "truss":
        # Fachwerk auf den Seitenflächen andeuten: helle Diagonalen und Pfosten vor dunklem Inneren
        side = vert & (mat == MAT_MAIN)
        zb0, zt0 = c.get("underside_m", 5.0) + 0.9, P[:, 2].max() - 1.2
        inside = side & (z > zb0) & (z < zt0)
        Pm = 11.0
        hgt = np.clip((z - zb0) / max(zt0 - zb0, 1), 0, 1)
        d1 = ((tx + hgt * Pm / 2) / Pm) % 1.0
        d2 = ((tx - hgt * Pm / 2) / Pm) % 1.0
        member = (np.minimum(d1, 1 - d1) < 0.03) | (np.minimum(d2, 1 - d2) < 0.03) | \
                 (np.abs(z - zb0) < 0.35) | (np.abs(z - zt0) < 0.35)
        dark = inside & ~member
        alb[dark] = np.array([0.12, 0.12, 0.13], np.float32)
    return alb


def axis_s(b, e, n):
    """Lage s auf der Achse für viele Punkte (nächstes Segment), vektorisiert."""
    P = np.column_stack([e, n])
    best_d = np.full(len(P), np.inf)
    best_s = np.zeros(len(P))
    for i in range(len(b.axis.seg)):
        a = b.axis.p[i]
        d = b.axis.p[i + 1] - a
        L = b.axis.seg[i]
        t = np.clip((P - a) @ d / L ** 2, 0, 1)
        dist = np.linalg.norm(P - (a + t[:, None] * d), axis=1)
        m = dist < best_d
        best_d[m] = dist[m]
        best_s[m] = b.axis.cum[i] + t[m] * L
    return best_s


# ----------------------------------------------------------------------------- Licht

def occluders(area, origin, bbox, level="standard"):
    """Gelände (3 m), Wasserfläche und Gebäude (bake/<stufe>/groups.npz) um die Brücken, lokales ENU."""
    import rasterio
    from rasterio.features import rasterize
    build = Path("build") / area["id"]
    lake = area["lake_level_m"]
    e0, n0, e1, n1 = bbox
    with rasterio.open(build / "dem_core.tif") as s:
        dem, tr = s.read(1), s.transform
    water = shape(json.loads((build / "water.geojson").read_text())["geometry"])
    wm = rasterize([water], out_shape=dem.shape, transform=tr)
    dem = np.where(wm == 1, lake - 1.0, dem)
    xs = np.arange(e0, e1, 3.0); ys = np.arange(n0, n1, 3.0)
    X, Y = np.meshgrid(xs, ys)
    col = np.clip(((X - tr.c) / tr.a).astype(int), 0, dem.shape[1] - 1)
    row = np.clip(((Y - tr.f) / tr.e).astype(int), 0, dem.shape[0] - 1)
    Z = dem[row, col] - lake
    v = np.column_stack([X.ravel() - origin[0], Y.ravel() - origin[1], Z.ravel()])
    nx, ny = len(xs), len(ys)
    idx = np.arange(nx * ny).reshape(ny, nx)
    a, b_, c, d = idx[:-1, :-1], idx[:-1, 1:], idx[1:, :-1], idx[1:, 1:]
    f = np.concatenate([np.stack([a, b_, d], -1).reshape(-1, 3), np.stack([a, d, c], -1).reshape(-1, 3)])
    Vs, Fs, off = [v], [f], len(v)
    # Wasserfläche (y = 0): verdeckt die Unterseiten von unten
    q = np.array([[e0, n0], [e1, n0], [e1, n1], [e0, n1]]) - origin
    Vs.append(np.column_stack([q, np.zeros(4)])); Fs.append(np.array([[0, 1, 2], [0, 2, 3]]) + off); off += 4
    gz = build / "bake" / level / "groups.npz"
    if gz.exists():
        g = np.load(gz)
        for k in [k for k in g.files if k.endswith("__v")]:
            gv = g[k].astype(np.float64)
            gf = g[k[:-3] + "__f"].astype(np.int64)
            c0 = gv[gf].mean(axis=1)
            m = (c0[:, 0] > e0 - origin[0]) & (c0[:, 0] < e1 - origin[0]) & (c0[:, 1] > n0 - origin[1]) & \
                (c0[:, 1] < n1 - origin[1])
            if m.any():
                Vs.append(gv); Fs.append(gf[m] + off); off += len(gv)
    return np.vstack(Vs), np.vstack(Fs)


def bake_bridge(b, V, F, M, occ_v, occ_f, out, procs, side, light_mode="sun"):
    import warp as wp
    import bake as bk
    from PIL import Image
    from scipy import ndimage
    g = {"V": V, "F": F, "fband": np.zeros(len(F), np.int8)}
    bk.atlas_layout(g, [TEX_M], ATLAS_MAX)
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
    light = bk.trace("bruecke", allv, allf, P.astype(np.float64), N.astype(np.float64), procs, side=side,
                     r_ao=bk.R_AO)
    facing = (N @ bk.sun_enu()) > 0
    sun_vis = np.ones(len(light)) if light_mode == "ambient" else light[:, 2]
    sh = bk.shade(light[:, 0], light[:, 1], sun_vis, facing)
    down = np.clip(-N[:, 2], 0, 1)
    sh = sh * (1 - (1 - UNDERSIDE) * down)
    alb = albedo(b, M[fid], P, N)
    H, Wd = g["ah"], g["aw"]
    # Licht (verrauscht) innerhalb der Karten glätten, Material (Fugen, Fachwerk) bleibt scharf
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
    name = f"br_{b.slug}"
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)).save(out / f"{name}.jpg", quality=88,
                                                                            subsampling=0)
    uv = g["tx"] / np.array([g["aw"], g["ah"]])
    uv[:, 1] = 1.0 - uv[:, 1]
    return name, {f"{name}__v": cV.astype(np.float32), f"{name}__f": cF.astype(np.int32),
                  f"{name}__n": g["cN"].astype(np.float32), f"{name}__uv": uv.astype(np.float32)}, (Wd, H)


# ----------------------------------------------------------------------------- Kontrolle

def lane_lines(area):
    build = Path("build") / area["id"]
    out = []
    for f in json.loads((build / "routes.geojson").read_text())["features"]:
        line = LineString(f["geometry"]["coordinates"])
        out.append((f["properties"]["id"], line, line.parallel_offset(12, "left")))
    return out


def check_bridge(b, lanes, zb_fn):
    """Abstand der Bahnen zu den Pfeilern und lichte Höhe dort, wo die Bahnen die Brücke kreuzen."""
    res = {}
    fps = b.pier_footprints()
    for rid, out, back in lanes:
        r = {}
        for nm, ln in (("hin", out), ("rueck", back)):
            near = ln.distance(b.axis.line)
            d = {"axis_dist_m": round(near, 1)}
            if fps:
                d["pier_edge_m"] = round(min(fp.distance(ln) for fp in fps), 1)
                d["pier_center_m"] = round(min(fp.centroid.distance(ln) for fp in fps), 1)
            x = ln.intersection(b.axis.line)
            if not x.is_empty:
                pts = getattr(x, "geoms", [x])
                s = [b.axis.project(p.x, p.y) for p in pts]
                d["cross_s_m"] = [round(v, 1) for v in s]
                d["clearance_m"] = round(float(min(zb_fn(np.array(s)))), 2)
                d["deck_m"] = round(float(min(b.zt(np.array(s)))), 2)
            r[nm] = d
        res[rid] = r
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("area")
    ap.add_argument("--procs", type=int, default=8)
    ap.add_argument("--rays", type=int, default=7)
    ap.add_argument("--light", choices=["sun", "ambient"], default="sun")
    a = ap.parse_args()
    import warp as wp
    wp.config.quiet = True
    wp.init()
    area = load_area(a.area)
    if not area.get("bridges"):
        sys.exit("Gebietsdatei ohne \"bridges\" – nichts zu tun")
    build = Path("build") / area["id"]
    out = build / ("bridges" if a.light == "sun" else "bridges-ambient")
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("br_*.jpg"):
        f.unlink()
    e0c, n0c, e1c, n1c = area["core_lv95"]
    origin = np.array(area.get("origin_lv95", [(e0c + e1c) / 2, (n0c + n1c) / 2]))
    bridges = load_bridges(area)
    lanes = lane_lines(area)
    save, meta = {}, {"bridges": [], "sun_az_deg": None}
    for b in bridges:
        b.origin = origin
        V, F, M, (st, ztop, zbot, zb_fn) = build_mesh(b, origin)
        bb = b.axis.line.buffer(b.W + 150).bounds
        occ_v, occ_f = occluders(area, origin, bb)
        name, arrs, atlas = bake_bridge(b, V, F, M, occ_v, occ_f, out, a.procs, a.rays, a.light)
        save.update(arrs)
        over = (st >= b.w0) & (st <= b.w1)
        info = {"name": b.name, "mesh": name, "tris": int(len(arrs[f"{name}__f"])), "atlas": list(atlas),
                "style": b.style, "length_m": round(b.axis.L, 1), "width_m": round(b.W, 1),
                "water_s_m": [round(b.w0, 1), round(b.w1, 1)], "geometry": b.sources, "deck": b.deck_src,
                "deck_over_water_m": [round(float(ztop[over].min()), 2), round(float(ztop[over].max()), 2)],
                "underside_over_water_m": [round(float(zbot[over].min()), 2), round(float(zbot[over].max()), 2)],
                "axis_xz": [[round(float(e - origin[0]), 2), round(float(-(n - origin[1])), 2)] for e, n in b.axis.p],
                "piers_s_m": [round(s, 1) for s in b.pier_s],
                "piers_lv95": [[round(c, 1) for c in fp.centroid.coords[0]] for fp in b.pier_footprints()],
                "pier_source": b.cfg.get("pier_source", ""), "check": check_bridge(b, lanes, zb_fn)}
        meta["bridges"].append(info)
        print(json.dumps(info, ensure_ascii=False), flush=True)
    np.savez_compressed(out / "bridges.npz", **save)
    import bake as bk
    meta["light"] = a.light
    if a.light == "sun":
        meta["sun_az_deg"], meta["sun_el_deg"] = bk.SUN_AZ, bk.SUN_EL
    meta["meshes"] = [m["mesh"] for m in meta["bridges"]]
    (out / "meta.json").write_text(json.dumps(meta, indent=1, ensure_ascii=False))
    print(f"{len(bridges)} Brücken, {sum(m['tris'] for m in meta['bridges']):,} Dreiecke → {out}")


if __name__ == "__main__":
    main()
