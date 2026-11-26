"""Schritt 4a: Licht für die Gebäude vorrechnen (Raytracing mit NVIDIA Warp).

Was hier entsteht (build/<area>/bake/):
  visible.npz            welche Gebäudedreiecke überhaupt sichtbar sind (Brandmauern, Flächen im Nachbarhaus
                         und unter dem Gelände fallen weg); für alle Stufen gleich
  roof_colors.npy        Dachfarbe je Gebäude, Median aus dem Luftbild (SWISSIMAGE) – keine erfundene Farbe
  terrain_ao.tif         Umgebungsverdeckung durch Gebäude auf dem Gelände (1 m, Kerngebiet), für Kontaktschatten
  <stufe>/groups.npz     Gebäude-Meshes je Zelle (1 km, alle Abstandsbänder zusammen): Ecken (lokal ENU), Dreiecke, UV
  <stufe>/b_*.jpg        ein Texturatlas je Mesh: Fassaden-/Dachfarbe × Umgebungsverdeckung × Sonnenschatten
  <stufe>/meta.json      Sonne, Dichte, Statistik
  <stufe>-ambient/       nur mit --light ambient: dieselben Meshes, Atlas ohne Sonnenschatten (nur Verdeckung und
                         Himmelssichtbarkeit, richtungsunabhängig); für Sonnenstände ≠ 235°/48° in der App
                         (export.py --light ambient → light-ambient-<stufe>.usdz, KONZEPT.md Abschnitt 16)

Licht: Umgebungsverdeckung (Strahlen bis R_AO, linear abfallend), Himmelssichtbarkeit (nur obere Halbkugel,
relativ zur freien Fläche) und Sonnenschatten (weiche Sonne). Das Material bleibt beleuchtet (UsdPreviewSurface,
diffuseColor = Atlas): die App-Sonne (DirectionalLight) liefert weiter die Richtungshelligkeit (N·L), der Atlas
liefert Verdeckung und Schatten, die das iPad nicht selbst rechnet. Die Sonnenrichtung des Bakes steht in
meta.json und in der USDZ (customLayerData rowcoach:sunDirection) – die App sollte ihre Sonne genau so stellen.

Koordinaten intern: lokales ENU (x = E − E0, y = N − N0, z = H − Seehöhe), z nach oben.

Aufruf:
  .venv/bin/python bake.py areas/<area>.json [standard] [hoch] [--device cpu|cuda] [--procs 8]
                           [--clip E0 N0 E1 N1] [--rays 7] [--light sun|ambient]
Mit --clip nur ein Ausschnitt (Test); Ergebnis dann unter bake-clip/.
Mit --light ambient (Standard: sun) ohne Sonnenschatten nach bake/<stufe>-ambient/; die Sonne macht dann die App live.
GPU nur über die Warteschlange:  ~/.local/bin/gpu run -n rowcoach-bake -p 0 -o "SPARK SW RowCoach" -e <min> -- \
  .venv/bin/python bake.py areas/<area>.json --device cuda
"""
import os
import sys

DEVICE = sys.argv[sys.argv.index("--device") + 1] if "--device" in sys.argv else "cpu"
if DEVICE == "cpu":
    os.environ["CUDA_VISIBLE_DEVICES"] = ""  # CPU-Läufe fassen die GPU nicht an

import argparse  # noqa: E402
import json  # noqa: E402
import math  # noqa: E402
import multiprocessing as mp  # noqa: E402
import time  # noqa: E402
from pathlib import Path  # noqa: E402

import fast_simplification  # noqa: E402
import numpy as np  # noqa: E402
import rasterio  # noqa: E402
from PIL import Image  # noqa: E402
from rasterio.enums import Resampling  # noqa: E402
from rasterio.features import rasterize  # noqa: E402
from rasterio.transform import from_origin  # noqa: E402
from rasterio.windows import from_bounds  # noqa: E402
from scipy import ndimage  # noqa: E402
from scipy.sparse import coo_matrix  # noqa: E402
from scipy.sparse.csgraph import connected_components  # noqa: E402
from scipy.spatial import cKDTree  # noqa: E402
from shapely.geometry import LineString, Point, shape  # noqa: E402

import warp as wp  # noqa: E402

wp.config.quiet = True

# Sonne (Azimut ab Nord im Uhrzeigersinn, Höhe): genau die Sonne der App (Team B: DirectionalLight 235°/48°).
SUN_AZ, SUN_EL = 235.0, 48.0
SUN_CONE = math.radians(1.2)  # weicher Schatten (Sonne 0,27°, etwas Halbschatten für ruhigere Kanten)
R_AO = 12.0       # m, Reichweite der Umgebungsverdeckung
T_SKY = 400.0     # m, Reichweite für Himmel und Sonne
R_AO_GROUND = 9.0
CELL = 1000.0  # m; ein Mesh mit einem Atlas je Zelle (wenige Draw Calls)
TERRAIN_STEP = 3.0  # m, Gelände im Strahlenmodell

LEVELS = {
    # bands: (max. Abstand Gebäude–Strecke in m, Anteil Dreiecke, der wegvereinfacht wird, m pro Texel)
    "standard": {"bands": [(400, 0.0, 0.7), (1000, 0.45, 1.5), (1800, 0.75, 3.0), (1e9, 0.9, 5.0)],
                 "atlas_max": 2048, "jpeg_q": 85},
    "hoch": {"bands": [(800, 0.0, 0.5), (2000, 0.3, 1.2), (1e9, 0.65, 2.6)],
             "atlas_max": 4096, "jpeg_q": 88},
}

def level_cfg(A, level):
    """Stufe aus LEVELS; die Gebietsdatei kann die Abstandsbänder je Stufe ersetzen ("bake_bands": {stufe: [...]}),
    z. B. weniger Vereinfachung in der Ferne, wo das Vereinfachen bei schmalen Flüssen sichtbare Spitzen erzeugt."""
    q = dict(LEVELS[level])
    bands = A.cfg.get("bake_bands", {}).get(level)
    if bands:
        q["bands"] = [tuple(b) for b in bands]
    elif A.cfg.get("buildings_source") == "footprints":
        # Gebäude aus Grundrissen (buildings_footprints.py) haben schon nur wenige Dreiecke: Vereinfachen würde aus
        # Satteldächern Spitzen und Scherben machen
        q["bands"] = [(d, 0.0, t) for d, _, t in q["bands"]]
    return q


ROOF_FALLBACK = [(0.55, 0.30, 0.24), (0.42, 0.40, 0.40), (0.62, 0.42, 0.33), (0.30, 0.30, 0.32)]
# Putzfarben Zürcher Stadthäuser: hell, wenig gesättigt; je Gebäude leicht variiert
WALL_PALETTE = [(0.88, 0.85, 0.79), (0.92, 0.91, 0.88), (0.83, 0.79, 0.72), (0.86, 0.82, 0.74),
                (0.82, 0.82, 0.80), (0.89, 0.84, 0.78)]


def sun_enu():
    az, el = math.radians(SUN_AZ), math.radians(SUN_EL)
    return np.array([math.sin(az) * math.cos(el), math.cos(az) * math.cos(el), math.sin(el)])


def sun_scene_light_dir():
    """Richtung des Sonnenlichts (vom Licht weg) in Szenenkoordinaten (x = E, y = oben, z = −N)."""
    s = sun_enu()
    return [-s[0], -s[2], s[1]]


# ----------------------------------------------------------------------------- Warp-Kernels

@wp.func
def tangent_of(n: wp.vec3):
    a = wp.vec3(1.0, 0.0, 0.0)
    if wp.abs(n[0]) > 0.9:
        a = wp.vec3(0.0, 1.0, 0.0)
    return wp.normalize(wp.cross(a, n))


@wp.kernel
def k_light(mid: wp.uint64, pos: wp.array(dtype=wp.vec3), nrm: wp.array(dtype=wp.vec3), side: int,
            r_ao: float, t_sky: float, sun: wp.vec3, n_sun: int, cone: float, eps: float, seed: int,
            out: wp.array(dtype=wp.vec3)):
    """Je Messpunkt: (Umgebungsverdeckung, Himmelssichtbarkeit relativ, Sonne sichtbar)."""
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
    lit = float(1.0)
    if wp.dot(n, sun) > 0.0:
        cnt = float(0.0)
        for k in range(n_sun):
            jit = wp.vec3(wp.randf(st) - 0.5, wp.randf(st) - 0.5, wp.randf(st) - 0.5) * (2.0 * cone)
            ds = wp.normalize(sun + jit)
            qs = wp.mesh_query_ray(mid, o, ds, t_sky)
            if not qs.result:
                cnt += 1.0
        lit = cnt / float(n_sun)
    sky = float(1.0)
    if up > 0.0:
        sky = free / up
    out[i] = wp.vec3(1.0 - occ / float(side * side), sky, lit)


@wp.kernel
def k_visible(mid: wp.uint64, pos: wp.array(dtype=wp.vec3), nrm: wp.array(dtype=wp.vec3), n_rays: int,
              seed: int, out: wp.array(dtype=wp.int32)):
    """1, wenn von diesem Punkt aus ein Strahl der oberen Halbkugel frei ist oder eine Aussenfläche trifft.
    Punkte in einem Nachbarhaus (Brandmauer) sehen nach oben nur Rückseiten von Dächern und Wänden."""
    i = wp.tid()
    st = wp.rand_init(seed, i)
    n = nrm[i]
    t = tangent_of(n)
    b = wp.cross(n, t)
    o = pos[i] + n * 0.05
    vis = int(0)
    valid = int(0)
    for j in range(n_rays):
        u1 = wp.randf(st)
        phi = 6.2831853 * wp.randf(st)
        r = wp.sqrt(u1)
        d = t * (r * wp.cos(phi)) + b * (r * wp.sin(phi)) + n * wp.sqrt(wp.max(0.0, 1.0 - u1))
        if d[2] > -0.05:
            valid += 1
            q = wp.mesh_query_ray(mid, o, d, 300.0)
            if q.result:
                if q.sign > 0.0 and q.t > 0.3:
                    vis = 1
            else:
                vis = 1
    if valid == 0:
        vis = 1
    out[i] = vis


@wp.kernel
def k_raster(ta: wp.array(dtype=wp.vec2), tb: wp.array(dtype=wp.vec2), tc: wp.array(dtype=wp.vec2),
             pa: wp.array(dtype=wp.vec3), pb: wp.array(dtype=wp.vec3), pc: wp.array(dtype=wp.vec3),
             fn: wp.array(dtype=wp.vec3), off: wp.array(dtype=wp.int64), aw: wp.array(dtype=wp.int32),
             ah: wp.array(dtype=wp.int32),
             best: wp.array(dtype=float), opos: wp.array(dtype=wp.vec3), onrm: wp.array(dtype=wp.vec3),
             oface: wp.array(dtype=wp.int32)):
    """Dreieck in Texelraum rastern: Weltposition und Normale je Texelmitte (mit 0,75 Texel Saum)."""
    i = wp.tid()
    a = ta[i]
    b = tb[i]
    c = tc[i]
    area = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    if wp.abs(area) < 1.0e-9:
        return
    W = aw[i]
    H = ah[i]
    x0 = wp.max(int(wp.floor(wp.min(a[0], wp.min(b[0], c[0])) - 1.0)), 0)
    x1 = wp.min(int(wp.ceil(wp.max(a[0], wp.max(b[0], c[0])) + 1.0)), W - 1)
    y0 = wp.max(int(wp.floor(wp.min(a[1], wp.min(b[1], c[1])) - 1.0)), 0)
    y1 = wp.min(int(wp.ceil(wp.max(a[1], wp.max(b[1], c[1])) + 1.0)), H - 1)
    lbc = wp.max(wp.length(c - b), 1.0e-6)
    lca = wp.max(wp.length(a - c), 1.0e-6)
    lab = wp.max(wp.length(b - a), 1.0e-6)
    aa = wp.abs(area)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            p = wp.vec2(float(x) + 0.5, float(y) + 0.5)
            w0 = ((b[0] - p[0]) * (c[1] - p[1]) - (b[1] - p[1]) * (c[0] - p[0])) / area
            w1 = ((c[0] - p[0]) * (a[1] - p[1]) - (c[1] - p[1]) * (a[0] - p[0])) / area
            w2 = 1.0 - w0 - w1
            dm = wp.min(w0 * aa / lbc, wp.min(w1 * aa / lca, w2 * aa / lab))
            if dm > -0.75:
                idx = off[i] + wp.int64(y * W + x)
                if dm > best[idx]:
                    c0 = wp.max(w0, 0.0)
                    c1 = wp.max(w1, 0.0)
                    c2 = wp.max(w2, 0.0)
                    s = c0 + c1 + c2
                    best[idx] = dm
                    opos[idx] = (pa[i] * c0 + pb[i] * c1 + pc[i] * c2) / s
                    onrm[idx] = fn[i]
                    oface[idx] = i


# ----------------------------------------------------------------------------- Strahlen verteilen

_RT = {}


def _rt_worker(args):
    name, lo, hi = args
    st = _RT[name]
    n = hi - lo
    pos = wp.array(st["pos"][lo:hi], dtype=wp.vec3, device="cpu")
    nrm = wp.array(st["nrm"][lo:hi], dtype=wp.vec3, device="cpu")
    if name == "visible":
        out = wp.zeros(n, dtype=wp.int32, device="cpu")
        wp.launch(k_visible, n, [st["mesh"].id, pos, nrm, st["n_rays"], lo + 1, out], device="cpu")
    else:
        out = wp.zeros(n, dtype=wp.vec3, device="cpu")
        wp.launch(k_light, n, [st["mesh"].id, pos, nrm, st["side"], st["r_ao"], T_SKY,
                               wp.vec3(*sun_enu()), 4, SUN_CONE, 0.04, lo + 7, out], device="cpu")
    wp.synchronize()
    return lo, out.numpy()


def trace(name, verts, faces, pos, nrm, procs, **kw):
    """Strahlen für alle Punkte. CPU: Prozesse teilen sich das BVH per fork (Copy-on-Write)."""
    t0 = time.time()
    mesh = wp.Mesh(points=wp.array(verts.astype(np.float32), dtype=wp.vec3, device=DEVICE),
                   indices=wp.array(faces.astype(np.int32).ravel(), dtype=int, device=DEVICE))
    n = len(pos)
    if DEVICE != "cpu":
        p = wp.array(pos.astype(np.float32), dtype=wp.vec3, device=DEVICE)
        q = wp.array(nrm.astype(np.float32), dtype=wp.vec3, device=DEVICE)
        if name == "visible":
            out = wp.zeros(n, dtype=wp.int32, device=DEVICE)
            wp.launch(k_visible, n, [mesh.id, p, q, kw["n_rays"], 1, out], device=DEVICE)
        else:
            out = wp.zeros(n, dtype=wp.vec3, device=DEVICE)
            wp.launch(k_light, n, [mesh.id, p, q, kw["side"], kw["r_ao"], T_SKY, wp.vec3(*sun_enu()), 4,
                                   SUN_CONE, 0.04, 7, out], device=DEVICE)
        res = out.numpy()
    else:
        _RT[name] = dict(mesh=mesh, pos=pos.astype(np.float32), nrm=nrm.astype(np.float32), **kw)
        # Kernel einmal im Elternprozess laden, damit die Kinder ihn erben
        _rt_worker((name, 0, min(n, 8)))
        chunk = max(2000, n // (procs * 6))
        jobs = [(name, lo, min(n, lo + chunk)) for lo in range(0, n, chunk)]
        res = np.zeros((n,) if name == "visible" else (n, 3), np.int32 if name == "visible" else np.float32)
        with mp.get_context("fork").Pool(procs) as pool:
            for lo, r in pool.imap_unordered(_rt_worker, jobs):
                res[lo:lo + len(r)] = r
        del _RT[name]
    rays = n * (kw.get("n_rays") or (kw["side"] ** 2 + 4))
    dt = time.time() - t0
    print(f"  {name}: {n:,} Punkte, {len(faces):,} Dreiecke im BVH, {rays / 1e6:.0f} Mio. Strahlen, {dt:.0f} s "
          f"({rays / max(dt, 1e-6) / 1e6:.1f} Mio./s)", flush=True)
    return res


# ----------------------------------------------------------------------------- Daten

class Area:
    def __init__(self, area_file, clip=None):
        from common import load_area
        self.cfg = load_area(area_file)
        a = self.cfg
        self.build = Path("build") / a["id"]
        self.raw = (Path.cwd() / a["data_dir"]).resolve()
        self.lake = a["lake_level_m"]
        e0c, n0c, e1c, n1c = a["core_lv95"]
        self.core = a["core_lv95"]
        self.origin = a.get("origin_lv95", [(e0c + e1c) / 2, (n0c + n1c) / 2])
        self.clip = clip
        routes = json.loads((self.build / "routes.geojson").read_text())["features"]
        self.routes = [LineString(f["geometry"]["coordinates"]) for f in routes]
        self.water = shape(json.loads((self.build / "water.geojson").read_text())["geometry"])
        with rasterio.open(self.build / "dem_core.tif") as s:
            self.dem, self.dem_tr = s.read(1), s.transform
        wmask = rasterize([self.water], out_shape=self.dem.shape, transform=self.dem_tr)
        self.dem = np.where(wmask == 1, self.lake - 1.0, self.dem)
        self._load_buildings()

    def enu(self, v):
        return np.column_stack([v[:, 0] - self.origin[0], v[:, 1] - self.origin[1], v[:, 2] - self.lake])

    def _load_buildings(self):
        """Alle Blätter zu einem Satz zusammenfassen; Gebäude-Nr. global."""
        V, F, B, K, C = [], [], [], [], []
        voff = boff = 0
        for npz in sorted(self.build.glob("buildings_*.npz")):
            d = np.load(npz)
            c = d["centers"]
            for kind_i, kind in enumerate(("roof", "wall")):
                vv, ff, bid = d[f"{kind}_v"], d[f"{kind}_f"], d[f"bid_{kind}"]
                V.append(vv); F.append(ff + voff); B.append(bid + boff); K.append(np.full(len(ff), kind_i, np.int8))
                voff += len(vv)
            C.append(c)
            boff += len(c)
        self.V = self.enu(np.vstack(V))
        self.F = np.vstack(F).astype(np.int64)
        self.B = np.concatenate(B).astype(np.int64)
        self.K = np.concatenate(K)
        self.centers = np.vstack(C)
        if self.clip:
            e0, n0, e1, n1 = self.clip
            c = self.centers
            keep_b = (c[:, 0] >= e0) & (c[:, 0] <= e1) & (c[:, 1] >= n0) & (c[:, 1] <= n1)
            self.face_ok = keep_b[self.B]
        else:
            self.face_ok = np.ones(len(self.F), bool)
        dist = np.array([min(r.distance(Point(p[:2])) for r in self.routes) for p in self.centers])
        self.dist = dist

    def dem_at(self, x, y):
        """Geländehöhe (lokal) an lokalen Koordinaten."""
        tr = self.dem_tr
        e, n = x + self.origin[0], y + self.origin[1]
        col = np.clip((e - tr.c) / tr.a - 0.5, 0, self.dem.shape[1] - 1.001)
        row = np.clip((n - tr.f) / tr.e - 0.5, 0, self.dem.shape[0] - 1.001)
        c0, r0 = col.astype(int), row.astype(int)
        fc, fr = col - c0, row - r0
        d = self.dem
        h = (d[r0, c0] * (1 - fc) + d[r0, c0 + 1] * fc) * (1 - fr) + (d[r0 + 1, c0] * (1 - fc) + d[r0 + 1, c0 + 1] * fc) * fr
        return h - self.lake

    def terrain_mesh(self, step=None, bounds=None):
        """Gelände als Dreiecksgitter (lokales ENU) fürs Strahlenmodell. Gebietsfeld "bake_terrain_step_m" (Standard
        3 m) vergröbert es für grosse, flache Gebiete (Tokio: 6 m), damit der Speicher reicht."""
        step = step or float(self.cfg.get("bake_terrain_step_m", TERRAIN_STEP))
        e0, n0, e1, n1 = bounds or self.core
        xs = np.arange(e0, e1 + 0.1, step) - self.origin[0]
        ys = np.arange(n0, n1 + 0.1, step) - self.origin[1]
        X, Y = np.meshgrid(xs, ys)
        Z = self.dem_at(X.ravel(), Y.ravel())
        v = np.column_stack([X.ravel(), Y.ravel(), Z])
        nx, ny = len(xs), len(ys)
        idx = np.arange(nx * ny).reshape(ny, nx)
        a, b, c, d = idx[:-1, :-1], idx[:-1, 1:], idx[1:, :-1], idx[1:, 1:]
        f = np.concatenate([np.stack([a, b, d], -1).reshape(-1, 3), np.stack([a, d, c], -1).reshape(-1, 3)])
        return v, f


def face_normals(v, f):
    n = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    a = np.linalg.norm(n, axis=1)
    return n / np.maximum(a, 1e-12)[:, None], 0.5 * a


# ----------------------------------------------------------------------------- 1. Sichtbarkeit

def compute_visible(A, out_dir, procs):
    f_path = out_dir / "visible.npz"
    if f_path.exists():
        d = np.load(f_path)
        if len(d["visible"]) == len(A.F):
            return d["visible"]
    print("Sichtbarkeit der Gebäudedreiecke …", flush=True)
    V, F = A.V, A.F
    fn, _ = face_normals(V, F)
    tv, tf = A.terrain_mesh(bounds=A.cfg.get("buildings_lv95", A.core))
    allv = np.vstack([V, tv]); allf = np.vstack([F, tf + len(V)])
    # 4 Punkte je Dreieck: Schwerpunkt und drei Punkte zwischen Schwerpunkt und Ecken
    c = V[F].mean(axis=1)
    pts = [c] + [0.6 * V[F[:, k]] + 0.4 * c for k in range(3)]
    pos = np.vstack(pts)
    nrm = np.tile(fn, (4, 1))
    sel = np.tile(A.face_ok, 4)
    vis = np.zeros(len(pos), np.int32)
    vis[sel] = trace("visible", allv, allf, pos[sel], nrm[sel], procs, n_rays=24)
    vis = vis.reshape(4, -1).max(axis=0) > 0
    # ganz unter dem Gelände (mehr als 0,3 m)
    under = np.ones(len(F), bool)
    for k in range(3):
        p = V[F[:, k]]
        under &= p[:, 2] < A.dem_at(p[:, 0], p[:, 1]) - 0.3
    vis &= ~under
    vis |= ~A.face_ok  # ausserhalb des Ausschnitts nicht beurteilt
    if not A.clip:
        np.savez_compressed(f_path, visible=vis)
    k = A.face_ok
    print(f"  sichtbar {vis[k].sum():,} von {k.sum():,} Dreiecken ({vis[k].mean() * 100:.0f} %), "
          f"unter Gelände {(under & k).sum():,}", flush=True)
    return vis


# ----------------------------------------------------------------------------- 2. Farben

def roof_colors(A, out_dir):
    f_path = out_dir / "roof_colors.npy"
    nb = len(A.centers)
    if f_path.exists():
        rc = np.load(f_path)
        if len(rc) == nb:
            return rc
    print("Dachfarben aus dem Luftbild …", flush=True)
    sel = np.where(A.K == 0)[0]
    F = A.F[sel]
    c = A.V[F].mean(axis=1)
    e = c[:, 0] + A.origin[0]
    n = c[:, 1] + A.origin[1]
    col = np.full((len(sel), 3), np.nan)
    res = 0.5
    img_dir = A.raw / "image_core"
    tiles = np.stack([np.floor(e / 1000), np.floor(n / 1000)], 1).astype(int)
    for te, tn in np.unique(tiles, axis=0):
        from common import ortho_tile
        tp = ortho_tile(img_dir, te, tn)  # SWISSIMAGE oder fetch_de.py (crs des Gebiets)
        hits = [tp] if tp is not None else []
        if not hits:
            continue
        m = (tiles[:, 0] == te) & (tiles[:, 1] == tn)
        size = int(1000 / res)
        with rasterio.open(hits[0]) as src:
            win = from_bounds(te * 1000, tn * 1000, te * 1000 + 1000, tn * 1000 + 1000, src.transform)
            img = src.read([1, 2, 3], window=win, out_shape=(3, size, size), resampling=Resampling.average)
        cc = np.clip(((e[m] - te * 1000) / res).astype(int), 0, size - 1)
        rr = np.clip(((tn * 1000 + 1000 - n[m]) / res).astype(int), 0, size - 1)
        col[m] = img[:, rr, cc].T / 255.0
    bid = A.B[sel]
    out = np.full((nb, 3), np.nan)
    ok = ~np.isnan(col[:, 0])
    order = np.argsort(bid[ok], kind="stable")
    b_sorted = bid[ok][order]
    c_sorted = col[ok][order]
    starts = np.r_[0, np.flatnonzero(np.diff(b_sorted)) + 1]
    for s, t in zip(starts, np.r_[starts[1:], len(b_sorted)]):
        out[b_sorted[s]] = np.median(c_sorted[s:t], axis=0)
    miss = np.isnan(out[:, 0])
    fb = np.array(ROOF_FALLBACK)
    out[miss] = fb[np.arange(nb)[miss] % len(fb)]
    # Luftbild ist schon beleuchtet und leicht dunstig: etwas Kontrast/Sättigung zurück, Helligkeit begrenzen
    g = out.mean(axis=1, keepdims=True)
    out = np.clip(g + (out - g) * 1.25, 0.08, 0.85)
    np.save(f_path, out)
    print(f"  {nb - miss.sum():,} Gebäude mit Luftbildfarbe, {miss.sum():,} mit Ersatzfarbe", flush=True)
    return out


def wall_colors(nb, palette=None):
    """Leichte, feste Variation je Gebäude (Hash der Nummer), keine erfundenen Details. palette: Gebietsfeld
    "wall_palette" ([[r, g, b], ...], 0–1), z. B. Backstein und Kalkstein in Grossbritannien; sonst Zürcher Putz."""
    h = (np.arange(nb, dtype=np.uint64) * np.uint64(2654435761)) % np.uint64(2**32)
    pal = np.array(palette or WALL_PALETTE)
    base = pal[(h % np.uint64(len(pal))).astype(int)]
    jit = (((h >> np.uint64(8)) % np.uint64(1000)).astype(float) / 1000.0 - 0.5) * 0.08
    return np.clip(base * (1.0 + jit[:, None]), 0, 1)


# ----------------------------------------------------------------------------- 3. Meshes je Zelle/Band

def weld(v, f, tol=0.01):
    key = np.round(v / tol).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    v2 = v[first]
    f2 = inv.reshape(-1)[f]
    ok = (f2[:, 0] != f2[:, 1]) & (f2[:, 1] != f2[:, 2]) & (f2[:, 0] != f2[:, 2])
    return v2, f2, ok


def build_groups(A, level, visible):
    q = level_cfg(A, level)
    bands = q["bands"]
    nb = len(A.centers)
    band = np.full(nb, -1)
    for bi, (maxd, _, _) in reversed(list(enumerate(bands))):
        band[A.dist <= maxd] = bi
    tall = A.cfg.get("bake_keep_tall_m")  # z. B. 150: Türme (Tokyo Skytree) nicht vereinfachen, sonst zerfallen sie
    if tall:
        band[(A.centers[:, 3] - A.centers[:, 2] > tall) & (band >= 0)] = 0
    cx = np.floor((A.centers[:, 0] - A.core[0]) / CELL).astype(int)
    cy = np.floor((A.centers[:, 1] - A.core[1]) / CELL).astype(int)
    fsel = visible & A.face_ok & (band[A.B] >= 0)
    key = np.stack([cx[A.B], cy[A.B]], 1)
    groups = []
    keys, inv = np.unique(key[fsel], axis=0, return_inverse=True)
    idx_all = np.flatnonzero(fsel)
    order = np.argsort(inv.ravel(), kind="stable")
    inv_s = inv.ravel()[order]
    starts = np.r_[0, np.flatnonzero(np.diff(inv_s)) + 1]
    for gi, s in enumerate(starts):
        t = starts[gi + 1] if gi + 1 < len(starts) else len(inv_s)
        fidx = idx_all[order[s:t]]
        gx, gy = map(int, keys[inv_s[s]])
        Vs, Fs, Bs, Ks, Ns = [], [], [], [], []
        off = 0
        fb = band[A.B[fidx]]
        for bi in np.unique(fb):
            red = bands[bi][1]
            for kind in (0, 1):
                fk = fidx[(A.K[fidx] == kind) & (fb == bi)]
                if len(fk) == 0:
                    continue
                used, loc = np.unique(A.F[fk].ravel(), return_inverse=True)
                v, f, ok = weld(A.V[used], loc.reshape(-1, 3))
                f, fk = f[ok], fk[ok]
                bid = A.B[fk]
                if red > 0 and len(f) > 200:
                    v2, f2 = fast_simplification.simplify(v.astype(np.float32), f.astype(np.int64),
                                                          target_reduction=red)
                    v2 = np.asarray(v2, np.float64); f2 = np.asarray(f2, np.int64)
                    if len(f2):
                        # Gebäude-Nr. vom nächsten Originaldreieck übernehmen
                        tree = cKDTree(v[f].mean(axis=1))
                        _, nn = tree.query(v2[f2].mean(axis=1))
                        bid = bid[nn]
                        v, f = v2, f2
                Vs.append(v); Fs.append(f + off); Bs.append(bid); Ks.append(np.full(len(f), kind, np.int8))
                Ns.append(np.full(len(f), bi, np.int8))
                off += len(v)
        V = np.vstack(Vs); F = np.vstack(Fs)
        _, area = face_normals(V, F)
        ok = area > 1e-4
        groups.append(dict(name=f"b_{gx + 100}_{gy + 100}", V=V, F=F[ok], bid=np.concatenate(Bs)[ok],
                           kind=np.concatenate(Ks)[ok], fband=np.concatenate(Ns)[ok]))
    return groups


# ----------------------------------------------------------------------------- 4. Karten und Atlas

def make_charts(V, F):
    """Ebene, zusammenhängende Flächen mit gleicher Normalenrichtung (±~5°) zu Karten zusammenfassen."""
    fn, area = face_normals(V, F)
    bucket = np.round(fn / 0.09).astype(np.int64)
    bkey = (bucket[:, 0] + 64) * 16384 + (bucket[:, 1] + 64) * 128 + (bucket[:, 2] + 64)
    nf = len(F)
    e = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 0]]])
    e.sort(axis=1)
    ek = e[:, 0] * (len(V) + 1) + e[:, 1]
    fid = np.tile(np.arange(nf), 3)
    o = np.argsort(ek, kind="stable")
    ek, fid = ek[o], fid[o]
    same = ek[1:] == ek[:-1]
    a, b = fid[:-1][same], fid[1:][same]
    keep = bkey[a] == bkey[b]
    a, b = a[keep], b[keep]
    g = coo_matrix((np.ones(len(a)), (a, b)), shape=(nf, nf))
    _, lab = connected_components(g, directed=False)
    return lab.astype(np.int64), fn, area


def shelf_pack(sizes, width):
    """Rechtecke (w, h) zeilenweise packen. Liefert Positionen und benötigte Höhe."""
    order = np.lexsort((-sizes[:, 0], -sizes[:, 1]))
    pos = np.zeros_like(sizes)
    x = y = row_h = 0
    for i in order:
        w, h = sizes[i]
        if w > width:
            return None, None
        if x + w > width:
            y += row_h; x = 0; row_h = 0
        pos[i] = (x, y)
        x += w
        row_h = max(row_h, h)
    return pos, y + row_h


def atlas_layout(g, mpt_bands, atlas_max):
    """Karten bilden, im Atlas anordnen, UV und Texelkoordinaten je Ecke berechnen."""
    V, F = g["V"], g["F"]
    lab, fn, area = make_charts(V, F)
    nc = lab.max() + 1
    cn = np.zeros((nc, 3))
    np.add.at(cn, lab, fn * area[:, None])
    cn /= np.maximum(np.linalg.norm(cn, axis=1, keepdims=True), 1e-12)
    up = np.array([0.0, 0.0, 1.0])
    U = np.cross(up, cn)
    flat = np.linalg.norm(U, axis=1) < 0.3
    U[flat] = [1.0, 0.0, 0.0]
    U /= np.linalg.norm(U, axis=1, keepdims=True)
    Vax = np.cross(cn, U)
    # Ecken je Karte (geteilte Ecken innerhalb einer Karte)
    ckey = lab[:, None] * (len(V) + 1) + F
    uk, inv = np.unique(ckey.ravel(), return_inverse=True)
    vchart = uk // (len(V) + 1)
    vorig = uk % (len(V) + 1)
    P = V[vorig]
    u = np.einsum("ij,ij->i", P, U[vchart])
    v = np.einsum("ij,ij->i", P, Vax[vchart])
    # flache Dächer: Achsen nach der Hauptrichtung der Fläche drehen (weniger leere Texel)
    fl = flat[vchart]
    if fl.any():
        cnt = np.bincount(vchart, minlength=nc).astype(float)
        mu = np.bincount(vchart, u, nc) / np.maximum(cnt, 1)
        mv = np.bincount(vchart, v, nc) / np.maximum(cnt, 1)
        du, dv = u - mu[vchart], v - mv[vchart]
        suu = np.bincount(vchart, du * du, nc); svv = np.bincount(vchart, dv * dv, nc)
        suv = np.bincount(vchart, du * dv, nc)
        ang = 0.5 * np.arctan2(2 * suv, suu - svv)
        ang[~flat] = 0.0
        ca, sa = np.cos(ang), np.sin(ang)
        U2 = U * ca[:, None] + Vax * sa[:, None]
        V2 = -U * sa[:, None] + Vax * ca[:, None]
        U, Vax = U2, V2
        u = np.einsum("ij,ij->i", P, U[vchart])
        v = np.einsum("ij,ij->i", P, Vax[vchart])
    cmpt = np.zeros(nc)
    cmpt[lab] = np.asarray(mpt_bands)[g["fband"]]  # Karten liegen immer in einem Band
    umin = np.full(nc, np.inf); vmin = np.full(nc, np.inf); umax = np.full(nc, -np.inf); vmax = np.full(nc, -np.inf)
    np.minimum.at(umin, vchart, u); np.minimum.at(vmin, vchart, v)
    np.maximum.at(umax, vchart, u); np.maximum.at(vmax, vchart, v)
    scale = 1.0
    while True:
        dens = 1.0 / (cmpt * scale)
        W = np.maximum(2, np.ceil((umax - umin) * dens).astype(int) + 1)
        H = np.maximum(2, np.ceil((vmax - vmin) * dens).astype(int) + 1)
        sizes = np.stack([W + 2, H + 2], 1)  # 1 Texel Rand ringsum
        total = sizes.prod(axis=1).sum()
        side = 256
        while side * side < total * 1.15 and side < atlas_max:
            side *= 2
        placed = None
        for aw in sorted({side // 2, side} - {0}):
            if aw < 64:
                continue
            pos, need = shelf_pack(sizes, aw)
            if pos is not None and need <= atlas_max:
                ah = int(math.ceil(need / 16.0) * 16)
                if ah <= aw * 2:
                    placed = (aw, ah, pos)
                    break
        if placed:
            break
        scale *= 1.15
    aw, ah, pos = placed
    tx = (u - umin[vchart]) * dens[vchart] + 1.5 + pos[vchart, 0]
    ty = (v - vmin[vchart]) * dens[vchart] + 1.5 + pos[vchart, 1]
    ty = ah - ty  # v nach oben → Bildzeile nach unten
    g.update(cV=P, cF=inv.reshape(-1, 3), cN=cn[vchart], tx=np.stack([tx, ty], 1), aw=aw, ah=ah,
             chart_of_face=lab, n_charts=nc, scale=scale)
    return g


# ----------------------------------------------------------------------------- 5. Licht je Texel

def shade(ao, sky, sun, facing_sun):
    occl = ao * (0.55 + 0.45 * sky)
    s = 1.0 - 0.85 * (1.0 - occl)
    s = np.where(facing_sun, s * (1.0 - 0.55 * (1.0 - sun)), s)
    return s


def bake_level(A, level, visible, rcol, wcol, out, procs, side, light_mode="sun"):
    q = level_cfg(A, level)
    t0 = time.time()
    groups = build_groups(A, level, visible)
    print(f"[{level}] {len(groups)} Meshes, {sum(len(g['F']) for g in groups):,} Dreiecke "
          f"({time.time() - t0:.0f} s)", flush=True)
    t0 = time.time()
    for g in groups:
        atlas_layout(g, [b[2] for b in q["bands"]], q["atlas_max"])
    texels = sum(g["aw"] * g["ah"] for g in groups)
    print(f"  Atlanten: {texels / 1e6:.1f} Mio. Texel, {sum(g['n_charts'] for g in groups):,} Karten "
          f"({time.time() - t0:.0f} s)", flush=True)
    # Rastern je Atlas (Speicher bleibt pro Atlas begrenzt); nur belegte Texel werden gesammelt
    dev = "cpu"
    Ps, Ns, covs, faces = [], [], [], []
    n_cov = 0
    for g in groups:
        cF, cV, tx = g["cF"], g["cV"], g["tx"]
        n, T = len(cF), g["aw"] * g["ah"]
        w2 = lambda a: wp.array(a.astype(np.float32), dtype=wp.vec2, device=dev)  # noqa: E731
        w3 = lambda a: wp.array(a.astype(np.float32), dtype=wp.vec3, device=dev)  # noqa: E731
        best = wp.full(T, -1e9, dtype=float, device=dev)
        opos = wp.zeros(T, dtype=wp.vec3, device=dev)
        onrm = wp.zeros(T, dtype=wp.vec3, device=dev)
        oface = wp.full(T, -1, dtype=wp.int32, device=dev)
        wp.launch(k_raster, n, [w2(tx[cF[:, 0]]), w2(tx[cF[:, 1]]), w2(tx[cF[:, 2]]),
                                w3(cV[cF[:, 0]]), w3(cV[cF[:, 1]]), w3(cV[cF[:, 2]]), w3(g["cN"][cF[:, 0]]),
                                wp.zeros(n, dtype=wp.int64, device=dev),
                                wp.full(n, g["aw"], dtype=wp.int32, device=dev),
                                wp.full(n, g["ah"], dtype=wp.int32, device=dev),
                                best, opos, onrm, oface], device=dev)
        wp.synchronize()
        cov = best.numpy() > -1e8
        Ps.append(opos.numpy()[cov]); Ns.append(onrm.numpy()[cov]); faces.append(oface.numpy()[cov])
        covs.append(np.packbits(cov))
        n_cov += int(cov.sum())
        del best, opos, onrm, oface
    print(f"  gerastert: {n_cov / 1e6:.1f} Mio. belegte Texel ({n_cov / texels * 100:.0f} %)", flush=True)
    # Strahlenmodell: diese Stufe selbst + Gelände
    bv = np.vstack([g["V"] for g in groups])
    bf = np.vstack([g["F"] + o for g, o in zip(groups, np.cumsum([0] + [len(g["V"]) for g in groups])[:-1])])
    tv, tf = A.terrain_mesh(bounds=A.cfg.get("buildings_lv95", A.core))
    allv = np.vstack([bv, tv]); allf = np.vstack([bf, tf + len(bv)])
    lens = [len(p) for p in Ps]
    P = np.vstack(Ps); del Ps
    N = np.vstack(Ns); del Ns
    light = trace("licht", allv, allf, P, N, procs, side=side, r_ao=R_AO)
    del P, allv, allf
    facing = (N @ sun_enu()) > 0
    del N
    if light_mode == "ambient":
        # richtungsunabhängig: Sonne überall „sichtbar“, nur Verdeckung und Himmel bleiben (Sonne live in der App)
        sh = shade(light[:, 0], light[:, 1], np.ones(len(light), np.float32), facing).astype(np.float32)
    else:
        sh = shade(light[:, 0], light[:, 1], light[:, 2], facing).astype(np.float32)
    del light, facing
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("b_*.jpg"):
        f.unlink()
    save = {}
    starts = np.cumsum([0] + lens)
    for gi, g in enumerate(groups):
        H, W = g["ah"], g["aw"]
        c = np.unpackbits(covs[gi], count=H * W).astype(bool)
        fid = faces[gi]
        b, k = g["bid"][fid], g["kind"][fid]
        alb = np.where((k == 0)[:, None], rcol[b], wcol[b]).astype(np.float32)
        img = np.zeros((H * W, 3), np.float32)
        img[c] = alb * sh[starts[gi]:starts[gi + 1], None]
        ch = np.full(H * W, -1, np.int64)
        ch[c] = g["chart_of_face"][fid]
        img, c, ch = img.reshape(H, W, 3), c.reshape(H, W), ch.reshape(H, W)
        img = smooth_in_chart(img, c, ch)
        # leere Texel mit dem nächsten belegten füllen (Rand für Filter und Mipmaps)
        if (~c).any() and c.any():
            _, (ri, ci) = ndimage.distance_transform_edt(~c, return_indices=True)
            img = img[ri, ci]
        Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)).save(
            out / f"{g['name']}.jpg", quality=q["jpeg_q"], subsampling=0)
        uv = g["tx"] / np.array([g["aw"], g["ah"]])
        uv[:, 1] = 1.0 - uv[:, 1]
        save[f"{g['name']}__v"] = g["cV"].astype(np.float32)
        save[f"{g['name']}__f"] = g["cF"].astype(np.int32)
        save[f"{g['name']}__n"] = g["cN"].astype(np.float32)
        save[f"{g['name']}__uv"] = uv.astype(np.float32)
    np.savez_compressed(out / "groups.npz", **save)
    meta = {"level": level, "light": light_mode,
            "sun_az_deg": SUN_AZ if light_mode == "sun" else None,
            "sun_el_deg": SUN_EL if light_mode == "sun" else None,
            "sun_light_dir_scene": [round(x, 5) for x in sun_scene_light_dir()],
            "meshes": [{"name": g["name"], "tris": int(len(g["cF"])), "atlas": [int(g["aw"]), int(g["ah"])],
                        "m_per_texel_scale": round(float(g["scale"]), 3)} for g in groups],
            "tris": int(sum(len(g["cF"]) for g in groups)), "atlas_texels": int(texels),
            "clip": A.clip, "seconds": round(time.time() - t0)}
    (out / "meta.json").write_text(json.dumps(meta, indent=1))
    print(f"[{level}] fertig: {meta['tris']:,} Dreiecke, {texels / 1e6:.1f} Mio. Texel, "
          f"{time.time() - t0:.0f} s", flush=True)


def smooth_in_chart(img, cov, chart):
    """Rauschen der Strahlen glätten: 3×3-Mittel nur über Texel derselben Karte."""
    H, W, _ = img.shape
    acc = np.zeros_like(img); wsum = np.zeros((H, W, 1), np.float32)
    pad_i = np.pad(img, ((1, 1), (1, 1), (0, 0)))
    pad_c = np.pad(chart, 1, constant_values=-2)
    pad_v = np.pad(cov, 1)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            w = 1.0 if (dx == 0 or dy == 0) else 0.7
            sub_c = pad_c[1 + dy:1 + dy + H, 1 + dx:1 + dx + W]
            sub_v = pad_v[1 + dy:1 + dy + H, 1 + dx:1 + dx + W]
            m = ((sub_c == chart) & sub_v & cov)[..., None] * w
            acc += pad_i[1 + dy:1 + dy + H, 1 + dx:1 + dx + W] * m
            wsum += m
    return np.where(wsum > 0, acc / np.maximum(wsum, 1e-6), img)


# ----------------------------------------------------------------------------- 6. Kontaktschatten Gelände

def terrain_ao(A, out_dir, procs, side):
    f_path = out_dir / "terrain_ao.tif"
    if f_path.exists() and not A.clip:
        return
    print("Kontaktschatten auf dem Gelände …", flush=True)
    e0, n0, e1, n1 = A.clip or A.core
    res = 1.0
    w, h = int((e1 - e0) / res), int((n1 - n0) / res)
    tr = from_origin(e0, n1, res, res)
    # Gebäudegrundrisse aus den Dachdreiecken
    sel = np.flatnonzero((A.K == 0) & A.face_ok)
    tri = A.V[A.F[sel]][:, :, :2] + np.array(A.origin)
    from shapely.geometry import Polygon
    polys = [Polygon(t) for t in tri if abs(np.cross(t[1] - t[0], t[2] - t[0])) > 1e-3]
    foot = rasterize(polys, out_shape=(h, w), transform=tr, all_touched=False).astype(bool)
    near = ndimage.distance_transform_edt(~foot) * res <= R_AO_GROUND * 1.3
    wmask = rasterize([A.water], out_shape=(h, w), transform=tr).astype(bool)
    todo = near & ~foot & ~wmask
    rr, cc = np.nonzero(todo)
    x = e0 + (cc + 0.5) * res - A.origin[0]
    y = n1 - (rr + 0.5) * res - A.origin[1]
    z = A.dem_at(x, y) + 0.1
    pos = np.column_stack([x, y, z])
    nrm = np.tile([0.0, 0.0, 1.0], (len(pos), 1))
    ok = A.face_ok
    bv = A.V; bf = A.F[ok]
    light = trace("gelaende", bv, bf, pos, nrm, procs, side=side, r_ao=R_AO_GROUND)
    ao = np.ones((h, w), np.float32)
    ao[rr, cc] = light[:, 0] * (0.6 + 0.4 * light[:, 1])
    ao[foot] = 0.6
    ao = ndimage.gaussian_filter(ao, 0.8)
    out = (np.clip(ao, 0, 1) * 255).astype(np.uint8)
    if A.clip:
        f_path = out_dir / "terrain_ao_clip.tif"
    with rasterio.open(f_path, "w", driver="GTiff", width=w, height=h, count=1, dtype="uint8",
                       crs=A.cfg.get("crs", "EPSG:2056"), transform=tr, compress="deflate") as dst:
        dst.write(out, 1)
    print(f"  {f_path.name}: {w}×{h} px, {len(pos):,} Punkte", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("area")
    ap.add_argument("levels", nargs="*", default=["standard", "hoch"])
    ap.add_argument("--device", default="cpu")
    ap.add_argument("--procs", type=int, default=8)
    ap.add_argument("--clip", type=float, nargs=4)
    ap.add_argument("--rays", type=int, default=7, help="Strahlen je Texel = rays² (+4 Sonne)")
    ap.add_argument("--light", choices=["sun", "ambient"], default="sun",
                    help="sun (Standard): Sonnenschatten 235°/48° einrechnen; ambient: ohne Sonnenschatten → <stufe>-ambient/")
    args = ap.parse_args()
    wp.init()
    t0 = time.time()
    A = Area(args.area, args.clip)
    out_dir = A.build / ("bake-clip" if args.clip else "bake")
    out_dir.mkdir(parents=True, exist_ok=True)
    vis = compute_visible(A, out_dir, args.procs)
    (A.build / "bake").mkdir(exist_ok=True)
    rcol = roof_colors(A, A.build / "bake")
    wcol = wall_colors(len(A.centers), A.cfg.get("wall_palette"))
    terrain_ao(A, out_dir, args.procs, args.rays)
    for level in args.levels:
        sub = level if args.light == "sun" else f"{level}-ambient"
        bake_level(A, level, vis, rcol, wcol, out_dir / sub, args.procs, args.rays, args.light)
    print(f"bake.py fertig in {time.time() - t0:.0f} s", flush=True)


if __name__ == "__main__":
    main()
