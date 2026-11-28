"""Schritt 4: 3D-Szene (USDZ) und Streckendateien für die App bauen.

Koordinaten der Szene (RealityKit): Meter, y nach oben, Ursprung = origin_lv95 auf Seehöhe.
  x = E - E0,  y = H - Seehöhe,  z = -(N - N0)
E, N im Koordinatensystem "crs" der Gebietsdatei (Standard EPSG:2056 = LV95; Berlin/Brandenburg EPSG:25833).
course.json trägt "crs" und "origin" ([E0, N0]); in der Schweiz zusätzlich wie bisher "origin_lv95".

Gelände Kerngebiet: Kacheln à 250 m, fehlerbasiert vereinfacht (RTIN/Martini, max. Höhenfehler nach Abstand
zur Strecke), Ränder (Skirts) nur an den Kachelkanten; Textur aus SWISSIMAGE 10 cm, nahe den Häusern leicht
abgedunkelt mit der Umgebungsverdeckung aus bake.py (Kontaktschatten).
Gelände Umgebung: grobes Gitter mit Luftbild 2 m. Unter Wasser wird das Gelände 1 m abgesenkt;
die Wasserfläche (y = 0) zeichnet die App selbst. Bei "water_source": "osm" senkt export.py in der Umgebung das
OSM-Wasser (water_far.geojson) ab, soweit es höchstens 2 m über der Wasserhöhe liegt (Seen, Fluss nahe Wasserhöhe).
Fehlt im Kerngebiet eine Luftbildkachel oder ist sie teilweise leer (Grenzgebiet), füllt das Luftbild der
Umgebung (ortho_far.tif, dort schon mit Geländefarbe ergänzt) die Lücke.
Gebäude: aus bake.py (build/<area>/bake/<stufe>/): je Zelle und Abstandsband ein Mesh mit eigenem Texturatlas
(Fassaden-/Dachfarbe × Umgebungsverdeckung × Sonnenschatten). Material bleibt beleuchtet (UsdPreviewSurface).
Die Sonnenrichtung des Bakes steht in customLayerData (rowcoach:sunDirection, Szenenkoordinaten).
Brücken: Enthält die Gebietsdatei "bridges", kommen die Meshes aus bridges.py (build/<area>/bridges/) unter
/Scene/Bridges dazu (je Brücke ein Mesh mit eigenem Texturatlas, Licht eingerechnet). Ohne das Feld bleibt alles wie
bisher.
Bäume: Mit "trees": true kommen die Meshes aus trees.py (build/<area>/trees/<stufe>/) unter /Scene/Trees dazu (je
1-km-Zelle ein Mesh mit eigenem Atlas, Licht eingerechnet) und das Gelände bekommt unter den Bäumen einen sanften
Kontaktschatten (trees/<stufe>/tree_ao.tif). Mit "summer_grade": true werden die Geländetexturen sommerlicher
(summer.py: Rasen satter und heller, Kronen satter und dunkler, alles leicht wärmer; Vegetation aus trees/veg.tif).
Ohne die Felder bleibt alles wie bisher.

Qualitätsstufen (Konzept Abschnitt 5): standard (A12X) und hoch (M-Chip).

Ergebnis: ../../courses/<area>/scene-<stufe>.usdz, ../../courses/<route>/course.json
Aufruf: .venv/bin/python export.py areas/<area>.json [standard|hoch ...]

Licht-Variante ohne Sonnenschatten (KONZEPT.md Abschnitt 16):
  .venv/bin/python export.py areas/<area>.json standard hoch --light ambient
legt nur die Texturatlanten aus bake/<stufe>-ambient/ und bridges-ambient/ (zuvor bake.py … --light ambient und
bridges.py … --light ambient) nach ../../courses/<area>/light-ambient-<stufe>/ und trägt in jede course.json des
Gebiets das optionale Feld "light_variants" ein:
  {"ambient": {"textures": "<area>/light-ambient-{quality}", "qualities": [...], "replaces": ["Buildings", "Bridges"]}}
Geometrie und UV müssen mit scene-<stufe>.usdz übereinstimmen (wird geprüft). Die App tauscht bei einem Sonnenstand
≠ 235°/48° unter den Gruppen in "replaces" die Grundfarb-Textur jedes Meshes <name> gegen <name>.jpg aus dem Ordner.
Ein normaler Lauf von export.py behält alle Felder einer vorhandenen course.json, die er nicht selbst berechnet
(minimap, overview, traffic, description, highlights, bridges …; light_variants solange die Ordner da sind);
minimap.py bzw. lanes.py aktualisieren ihre Felder bei Bedarf.
"""
import json
import math

import shutil
import sys
from pathlib import Path

import numpy as np
import rasterio
from PIL import Image
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdUtils, Vt
from rasterio.enums import Resampling
from rasterio.features import rasterize
from rasterio.windows import from_bounds
from pymartini import Martini
from shapely.geometry import LineString, box, shape

import summer
from common import area_crs, load_area, ortho_tile

QUALITY = {
    # bands: (max. Abstand zur Strecke in m, max. Höhenfehler Gelände in m, Texturgrösse px) – Umgebung als Gitter
    "standard": {"bands": [(300, 0.6, 512), (1000, 1.2, 256), (1e9, 3.0, 128)],
                 "far_step": 100.0, "far_tex": 2048, "jpeg_q": 82},
    "hoch": {"bands": [(400, 0.3, 1024), (1200, 0.6, 512), (1e9, 1.5, 256)],
             "far_step": 50.0, "far_tex": 4096, "jpeg_q": 88},
}
CHUNK = 250.0
BLOCK = 1000.0  # m, Kacheln eines Blocks teilen sich Mesh und Atlas
GRID = 257  # Stützpunkte je Kachelkante für die Vereinfachung (≈ 0,98 m)
SKIRT = 4.0


class Frame:
    def __init__(self, e0, n0, h0):
        self.e0, self.n0, self.h0 = e0, n0, h0

    def xyz(self, e, n, h):
        return np.column_stack([e - self.e0, h - self.h0, -(n - self.n0)])


def bilinear(arr, transform, e, n):
    """Höhe an LV95-Punkten (Arrays) aus einem Raster."""
    col = (e - transform.c) / transform.a - 0.5
    row = (n - transform.f) / transform.e - 0.5
    c0 = np.clip(np.floor(col).astype(int), 0, arr.shape[1] - 2)
    r0 = np.clip(np.floor(row).astype(int), 0, arr.shape[0] - 2)
    fc = np.clip(col - c0, 0, 1)
    fr = np.clip(row - r0, 0, 1)
    a = arr[r0, c0] * (1 - fc) + arr[r0, c0 + 1] * fc
    b = arr[r0 + 1, c0] * (1 - fc) + arr[r0 + 1, c0 + 1] * fc
    return a * (1 - fr) + b * fr


def grid_mesh(e0, n0, e1, n1, step, height_fn, skirt=True):
    """Regelmässiges Gitter mit UV (0..1) und optionalem Rand (Skirt) gegen Risse zwischen Kacheln."""
    nx = int(round((e1 - e0) / step)) + 1
    ny = int(round((n1 - n0) / step)) + 1
    es = np.linspace(e0, e1, nx)
    ns = np.linspace(n1, n0, ny)  # von Nord nach Süd (Zeilen wie im Bild)
    E, N = np.meshgrid(es, ns)
    H = height_fn(E.ravel(), N.ravel())
    U = ((E - e0) / (e1 - e0)).ravel()
    V = ((N - n0) / (n1 - n0)).ravel()
    idx = np.arange(nx * ny).reshape(ny, nx)
    a, b, c, d = idx[:-1, :-1], idx[:-1, 1:], idx[1:, :-1], idx[1:, 1:]
    # Dreiecke gegen den Uhrzeigersinn von oben gesehen (y nach oben, z = -N)
    faces = np.concatenate([np.stack([a, c, b], -1).reshape(-1, 3), np.stack([b, c, d], -1).reshape(-1, 3)])
    pts = np.column_stack([E.ravel(), N.ravel(), H])
    uv = np.column_stack([U, V])
    if skirt:
        border = np.concatenate([idx[0, :], idx[:, -1], idx[-1, ::-1], idx[::-1, 0]])
        base = len(pts)
        low = pts[border].copy(); low[:, 2] -= SKIRT
        pts = np.vstack([pts, low]); uv = np.vstack([uv, uv[border]])
        k = len(border)
        sf = []
        for i in range(k - 1):
            t0, t1 = border[i], border[i + 1]
            l0, l1 = base + i, base + i + 1
            sf += [[t0, l0, t1], [t1, l0, l1]]
        faces = np.vstack([faces, np.array(sf)])
    return pts, uv, faces


_MARTINI = None


def rtin_mesh(e0, n0, e1, n1, max_err, height_fn):
    """Fehlerbasiert vereinfachtes Gelände (Martini/RTIN) mit UV und Skirts an den Kachelrändern."""
    global _MARTINI
    if _MARTINI is None:
        _MARTINI = Martini(GRID)
    s = GRID - 1
    es = np.linspace(e0, e1, GRID)
    ns = np.linspace(n1, n0, GRID)  # Zeile 0 = Nord
    E, N = np.meshgrid(es, ns)
    Hh = height_fn(E.ravel(), N.ravel()).reshape(GRID, GRID).astype(np.float32)
    tile = _MARTINI.create_tile(Hh)
    v, f = tile.get_mesh(max_err)
    v = v.reshape(-1, 2).astype(int)
    f = f.reshape(-1, 3).astype(np.int64)
    x, y = v[:, 0], v[:, 1]
    pts = np.column_stack([es[x], ns[y], Hh[y, x]])
    uv = np.column_stack([x / s, 1.0 - y / s])
    # gegen den Uhrzeigersinn von oben (E, N)
    a, b, c = pts[f[:, 0]], pts[f[:, 1]], pts[f[:, 2]]
    cw = ((b[:, 0] - a[:, 0]) * (c[:, 1] - a[:, 1]) - (b[:, 1] - a[:, 1]) * (c[:, 0] - a[:, 0])) < 0
    f[cw] = f[cw][:, [0, 2, 1]]
    # Randkanten (nur ein Dreieck) nach unten verlängern
    e = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    key = np.minimum(e[:, 0], e[:, 1]) * len(pts) + np.maximum(e[:, 0], e[:, 1])
    uk, cnt = np.unique(key, return_counts=True)
    border = e[np.isin(key, uk[cnt == 1])]
    if len(border):
        bv = np.unique(border.ravel())
        low_idx = np.full(len(pts), -1); low_idx[bv] = len(pts) + np.arange(len(bv))
        low = pts[bv].copy(); low[:, 2] -= SKIRT
        A, B = border[:, 0], border[:, 1]
        sf = np.concatenate([np.stack([A, low_idx[A], B], 1), np.stack([B, low_idx[A], low_idx[B]], 1)])
        pts = np.vstack([pts, low]); uv = np.vstack([uv, uv[bv]]); f = np.vstack([f, sf])
    return pts, uv, f


def tile_path(folder, e, n, pattern):
    hits = list(folder.glob(f"*_{int(e // 1000)}-{int(n // 1000)}_{pattern}"))
    return hits[0] if hits else None


def read_rgb(path, bounds, size):
    with rasterio.open(path) as src:
        win = from_bounds(*bounds, src.transform)
        img = src.read([1, 2, 3], window=win, out_shape=(3, size, size), resampling=Resampling.average)
    return Image.fromarray(np.moveaxis(img, 0, -1))


def read_rgb_filled(path, bounds, size, fallback):
    """Wie read_rgb, aber fehlende Kachel oder leere Pixel (alle Kanäle 0) aus dem Umgebungsluftbild."""
    img = np.asarray(read_rgb(path, bounds, size)) if path is not None else np.zeros((size, size, 3), np.uint8)
    hole = (img == 0).all(axis=2)
    if hole.any():
        with rasterio.open(fallback) as src:
            win = from_bounds(*bounds, src.transform)
            fb = np.moveaxis(src.read([1, 2, 3], window=win, out_shape=(3, size, size),
                                      resampling=Resampling.bilinear, boundless=True), 0, -1)
        # weicher Rand, damit keine harte Kante entsteht
        from scipy import ndimage
        w = np.clip(ndimage.distance_transform_edt(hole) / 4.0, 0, 1)[..., None]
        w[hole] = 1.0
        img = (img * (1 - w) + fb * w).astype(np.uint8)
    return Image.fromarray(img)


def steep_rock(img, dem, transform, bounds, lake, cfg):
    """Gebietsfeld "steep_rock" (nur wenn gesetzt, z. B. Fjorde): Auf sehr steilen Flächen zieht das von oben
    projizierte Luftbild senkrechte Streifen (ein Texel deckt viele Meter Wand). Dort wird die Textur zu einer
    Felsfarbe überblendet, deren Muster von der Höhe abhängt (waagrechte Schichtung statt Streifen) und nur
    grossräumig waagrecht variiert. cfg: {"slope_deg": [ab, voll], "color": [r, g, b], "strength": 0..1}.
    img: float32 (h, w, 3) für das Rechteck bounds (E0, N0, E1, N1); dem/transform: Höhenmodell."""
    from scipy import ndimage
    h_px, w_px = img.shape[:2]
    e0, n0, e1, n1 = bounds
    px_e, px_n = (e1 - e0) / w_px, (n1 - n0) / h_px
    ee = e0 + (np.arange(w_px) + 0.5) * px_e
    nn = n1 - (np.arange(h_px) + 0.5) * px_n
    E, N = np.meshgrid(ee, nn)
    inv = ~transform
    col, row = inv * (E, N)
    h = ndimage.map_coordinates(dem, [row - 0.5, col - 0.5], order=1, mode="nearest").astype(np.float32)
    gy, gx = np.gradient(h, px_n, px_e)
    slope = np.degrees(np.arctan(np.hypot(gx, gy)))
    s0, s1 = cfg.get("slope_deg", [48.0, 66.0])
    w = np.clip((slope - s0) / max(s1 - s0, 1e-3), 0, 1)
    w = w * w * (3 - 2 * w) * float(cfg.get("strength", 0.92))
    w[h < lake + 3.0] = 0.0  # Uferkante (Wasser abgesenkt) nicht
    if not w.any():
        return img
    strata = 0.5 * np.sin(h / 5.3) + 0.3 * np.sin(h / 2.1 + 1.7) + 0.2 * np.sin(h / 13.7 + 0.4)
    broad = np.sin(E / 173.0 + N / 251.0) * np.sin(N / 137.0 - E / 311.0)
    base = np.asarray(cfg.get("color", [118, 116, 110]), np.float32)
    # grossräumige Helligkeit des Luftbilds behalten (Schatten, Schneereste; weichgezeichnet, sonst kehren die
    # Streifen über die Helligkeit zurück), Farbe vom Fels
    lum = ndimage.gaussian_filter(img.mean(axis=2), max(2.0, 12.0 / px_e))[..., None]
    rock = base * (1.0 + 0.10 * strata[..., None] + 0.08 * broad[..., None]) * (0.75 + 0.25 * lum / max(base.mean(), 1))
    return img * (1 - w[..., None]) + rock * w[..., None]


class SceneWriter:
    def __init__(self, path):
        self.stage = Usd.Stage.CreateNew(str(path))
        UsdGeom.SetStageUpAxis(self.stage, UsdGeom.Tokens.y)
        UsdGeom.SetStageMetersPerUnit(self.stage, 1.0)
        self.root = UsdGeom.Xform.Define(self.stage, "/Scene")
        self.stage.SetDefaultPrim(self.root.GetPrim())
        UsdGeom.Scope.Define(self.stage, "/Scene/Materials")
        self.n_tris = 0

    def material_tex(self, name, tex_rel, rough=0.95):
        m = UsdShade.Material.Define(self.stage, f"/Scene/Materials/{name}")
        sh = UsdShade.Shader.Define(self.stage, f"/Scene/Materials/{name}/PBR")
        sh.CreateIdAttr("UsdPreviewSurface")
        sh.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(rough)
        sh.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0.0)
        st = UsdShade.Shader.Define(self.stage, f"/Scene/Materials/{name}/st")
        st.CreateIdAttr("UsdPrimvarReader_float2")
        st.CreateInput("varname", Sdf.ValueTypeNames.Token).Set("st")
        tx = UsdShade.Shader.Define(self.stage, f"/Scene/Materials/{name}/tex")
        tx.CreateIdAttr("UsdUVTexture")
        tx.CreateInput("file", Sdf.ValueTypeNames.Asset).Set(tex_rel)
        tx.CreateInput("st", Sdf.ValueTypeNames.Float2).ConnectToSource(st.ConnectableAPI(), "result")
        tx.CreateInput("wrapS", Sdf.ValueTypeNames.Token).Set("clamp")
        tx.CreateInput("wrapT", Sdf.ValueTypeNames.Token).Set("clamp")
        tx.CreateOutput("rgb", Sdf.ValueTypeNames.Float3)
        sh.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).ConnectToSource(tx.ConnectableAPI(), "rgb")
        m.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(), "surface")
        return m

    def mesh(self, path, pts, faces, material, uv=None, normals=None):
        if len(faces) == 0:
            return
        mesh = UsdGeom.Mesh.Define(self.stage, path)
        mesh.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(pts.astype(np.float32)))
        mesh.CreateFaceVertexCountsAttr(Vt.IntArray.FromNumpy(np.full(len(faces), 3, np.int32)))
        mesh.CreateFaceVertexIndicesAttr(Vt.IntArray.FromNumpy(faces.astype(np.int32).ravel()))
        mesh.CreateSubdivisionSchemeAttr("none")
        mesh.CreateDoubleSidedAttr(False)
        if normals is not None:
            mesh.CreateNormalsAttr(Vt.Vec3fArray.FromNumpy(normals.astype(np.float32)))
            mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
        if uv is not None:
            pv = UsdGeom.PrimvarsAPI(mesh).CreatePrimvar("st", Sdf.ValueTypeNames.TexCoord2fArray,
                                                         UsdGeom.Tokens.vertex)
            pv.Set(Vt.Vec2fArray.FromNumpy(uv.astype(np.float32)))
        lo, hi = pts.min(axis=0), pts.max(axis=0)
        mesh.CreateExtentAttr([Gf.Vec3f(*lo.astype(float)), Gf.Vec3f(*hi.astype(float))])
        UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(material)
        self.n_tris += len(faces)

    def save(self):
        self.stage.GetRootLayer().Save()


def vertex_normals(v, f):
    n = np.zeros_like(v)
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    for k in range(3):
        np.add.at(n, f[:, k], fn)
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    return n / np.maximum(ln, 1e-9)


def main(area_file, levels):
    area = load_area(area_file)
    build = Path("build") / area["id"]
    raw = (Path.cwd() / area["data_dir"]).resolve()
    lake = area["lake_level_m"]
    e0c, n0c, e1c, n1c = area["core_lv95"]
    e0f, n0f, e1f, n1f = area["far_lv95"]
    origin = area.get("origin_lv95", [(e0c + e1c) / 2, (n0c + n1c) / 2])
    frame = Frame(origin[0], origin[1], lake)
    water = shape(json.loads((build / "water.geojson").read_text())["geometry"])
    routes = json.loads((build / "routes.geojson").read_text())["features"]
    route_union = [LineString(f["geometry"]["coordinates"]) for f in routes]

    with rasterio.open(build / "dem_core.tif") as s:
        dem_c, tr_c = s.read(1), s.transform
    with rasterio.open(build / "dem_far.tif") as s:
        dem_f, tr_f = s.read(1), s.transform
    # Wasser absenken (Kerngebiet: Polygon; Umgebung: ebene Fläche auf Seehöhe)
    wmask = rasterize([water], out_shape=dem_c.shape, transform=tr_c)
    dem_c = np.where(wmask == 1, lake - 1.0, dem_c)
    if (build / "water_far.geojson").exists() and area.get("water_source") == "osm":
        wfar = shape(json.loads((build / "water_far.geojson").read_text())["geometry"])
        wm_f = rasterize([wfar], out_shape=dem_f.shape, transform=tr_f, all_touched=True) == 1
        dem_f = np.where(wm_f & (dem_f < lake + 2.0), lake - 1.0, dem_f)
    else:
        flat_f = np.abs(dem_f - lake) < 0.3
        dem_f = np.where(flat_f, lake - 1.0, dem_f)

    courses = Path("../../courses")
    for level in levels:
        q = dict(QUALITY[level])
        # Gebietsfelder "far_step_m"/"far_tex" ({stufe: wert} oder eine Zahl): feineres Umgebungsgitter, z. B. Fjorde
        # mit steilen Wänden direkt hinter dem Kerngebiet (Nærøyfjord: 40 m statt 100 m)
        for key, qk in (("far_step_m", "far_step"), ("far_tex", "far_tex")):
            v = area.get(key)
            if v is not None:
                q[qk] = type(q[qk])(v.get(level, q[qk]) if isinstance(v, dict) else v)
        # "terrain_err_scale": erlaubter Höhenfehler des Kerngeländes × Faktor (steile Fjordwände erzeugen sonst
        # Millionen Dreiecke; Nærøyfjord 2,5); auch je Stufe {"standard": 1.0, "hoch": 2.0} (Island: das 10-m-Modell
        # gibt für "hoch" keine Einzelheiten her, die feineren Fehlergrenzen erzeugten nur Dreiecke)
        es = area.get("terrain_err_scale", 1.0)
        es = float(es.get(level, 1.0) if isinstance(es, dict) else es)
        q["bands"] = [(d, e * es, t) for d, e, t in q["bands"]]
        out_dir = courses / area["id"] / f"scene-{level}"
        if out_dir.exists():
            shutil.rmtree(out_dir)
        out_dir.mkdir(parents=True)
        sw = SceneWriter(out_dir / "scene.usdc")
        UsdGeom.Xform.Define(sw.stage, "/Scene/Terrain")

        # --- Kerngebiet
        img_dir = raw / "image_core"
        fill_core = area.get("water_source") == "osm" or "copernicus_tiles" in area
        tao = build / "bake" / "terrain_ao.tif"
        tao = tao if tao.exists() else None
        grade_on, veg_tif, tree_ao = summer_inputs(area, build, level)
        rock_cfg = area.get("steep_rock")  # Felsfarbe auf steilen Wänden (nur mit dem Feld, siehe steep_rock)
        n_chunks = 0
        tex_px = 0
        blocks = {}  # 1-km-Block → Kacheln; je Block ein Mesh mit einem Texturatlas (wenige Draw Calls)
        for ce in np.arange(e0c, e1c, CHUNK):
            for cn in np.arange(n0c, n1c, CHUNK):
                b = (ce, cn, ce + CHUNK, cn + CHUNK)
                cbox = box(*b)
                if water.contains(cbox):
                    continue  # reine Seefläche: Wasser deckt alles
                dist = min(r.distance(cbox) for r in route_union)
                _, max_err, tex = next(bd for bd in q["bands"] if dist <= bd[0])
                tp = ortho_tile(img_dir, ce // 1000, cn // 1000)
                if tp is None and not fill_core:
                    continue
                pts, uv, faces = rtin_mesh(*b, max_err, lambda e, n: bilinear(dem_c, tr_c, e, n))
                pad = 4 if tex >= 256 else 2
                inner = tex - 2 * pad
                if fill_core:
                    img = np.asarray(read_rgb_filled(tp, b, inner, build / "ortho_far.tif"), np.float32)
                else:
                    img = np.asarray(read_rgb(tp, b, inner), np.float32)
                if rock_cfg:
                    img = steep_rock(img, dem_c, tr_c, b, lake, rock_cfg)
                if tao is not None:
                    with rasterio.open(tao) as src:
                        win = from_bounds(*b, src.transform)
                        ao = src.read(1, window=win, out_shape=(inner, inner), resampling=Resampling.bilinear,
                                      boundless=True, fill_value=255)
                    img = img * (ao[..., None] / 255.0)
                if grade_on:
                    img = summer.grade(img, summer.veg_weights(veg_tif, b, img.shape[:2]))
                if tree_ao is not None:
                    img = summer.apply_tree_ao(img, summer.read_layer(tree_ao, b, img.shape[:2], fill=255) / 255.0)
                img = np.pad(img, ((pad, pad), (pad, pad), (0, 0)), mode="edge")
                key = (int((ce - e0c) // BLOCK), int((cn - n0c) // BLOCK))
                blocks.setdefault(key, []).append((pts, uv, faces, img, tex, pad))
                n_chunks += 1
        for (bx, by), items in sorted(blocks.items()):
            total = sum(it[4] ** 2 for it in items)
            aw = 128
            while aw * aw < total:
                aw *= 2
            items.sort(key=lambda it: -it[4])
            x = y = row = 0
            places = []
            for it in items:
                t = it[4]
                if x + t > aw:
                    y += row; x = 0; row = 0
                places.append((x, y)); x += t; row = max(row, t)
            ah = y + row
            atlas = np.zeros((ah, aw, 3), np.float32)
            P, UV, Fc, off = [], [], [], 0
            for (pts, uv, faces, img, t, pad), (x0, y0) in zip(items, places):
                atlas[y0:y0 + t, x0:x0 + t] = img
                inner = t - 2 * pad
                u = (x0 + pad + uv[:, 0] * inner) / aw
                v = 1.0 - (y0 + pad + (1.0 - uv[:, 1]) * inner) / ah
                P.append(frame.xyz(pts[:, 0], pts[:, 1], pts[:, 2])); UV.append(np.column_stack([u, v]))
                Fc.append(faces + off); off += len(pts)
            name = f"t_{bx}_{by}"
            Image.fromarray((atlas + 0.5).clip(0, 255).astype(np.uint8)).save(out_dir / f"{name}.jpg",
                                                                             quality=q["jpeg_q"])
            tex_px += aw * ah
            v = np.vstack(P); f = np.vstack(Fc)
            mat = sw.material_tex(name, f"{name}.jpg")
            sw.mesh(f"/Scene/Terrain/{name}", v, f, mat, uv=np.vstack(UV), normals=vertex_normals(v, f))

        # --- Umgebung (ohne Kerngebiet)
        step = q["far_step"]
        pts, uv, faces = grid_mesh(e0f, n0f, e1f, n1f, step, lambda e, n: bilinear(dem_f, tr_f, e, n) - 0.3,
                                   skirt=False)
        inside = (pts[:, 0] > e0c + step) & (pts[:, 0] < e1c - step) & (pts[:, 1] > n0c + step) & (pts[:, 1] < n1c - step)
        faces = faces[~inside[faces].all(axis=1)]
        with rasterio.open(build / "ortho_far.tif") as src:
            img = src.read([1, 2, 3], out_shape=(3, q["far_tex"], q["far_tex"]), resampling=Resampling.average)
        img = np.moveaxis(img, 0, -1)
        if rock_cfg:
            img = (steep_rock(img.astype(np.float32), dem_f, tr_f, (e0f, n0f, e1f, n1f), lake, rock_cfg) + 0.5
                   ).clip(0, 255).astype(np.uint8)
        if grade_on:
            img = (summer.grade(img.astype(np.float32)) + 0.5).astype(np.uint8)
        Image.fromarray(img).save(out_dir / "far.jpg", quality=q["jpeg_q"])
        tex_px += q["far_tex"] ** 2
        mat = sw.material_tex("far", "far.jpg")
        v = frame.xyz(pts[:, 0], pts[:, 1], pts[:, 2])
        sw.mesh("/Scene/Terrain/far", v, faces, mat, uv=uv, normals=vertex_normals(v, faces))
        terrain_tris = sw.n_tris

        # --- Gebäude (aus bake.py) und Brücken (aus bridges.py)
        meta, px, n_bridge_tris = write_buildings_and_bridges(sw, area, area_file, build, level, out_dir)
        tex_px += px
        n_tree_tris, px = write_trees(sw, area, area_file, build, level, out_dir)
        tex_px += px
        n_pf_tris = n_tint_tris = 0
        if area.get("palafitas") or area.get("water_tint"):
            # Amazonas (nur mit den Feldern): Pfahlbauten unter /Scene/Palafitas, zweite Wasserfarbe als Dateien
            # neben der Szene (die App zeichnet sie selbst, course.json "water_tint"), siehe amazonas.py
            import amazonas
            n_pf_tris, px = amazonas.write_palafitas(sw, area, build, out_dir)
            tex_px += px
            n_tint_tris, px = amazonas.write_water_tint(sw, area, build, out_dir, frame)
            tex_px += px
        sw.stage.GetRootLayer().customLayerData = {
            "rowcoach:sunDirection": Gf.Vec3f(*meta["sun_light_dir_scene"]),
            "rowcoach:sunAzimuthDeg": meta["sun_az_deg"], "rowcoach:sunElevationDeg": meta["sun_el_deg"],
            "rowcoach:bakedLighting": "diffuseColor der Gebäude enthält Umgebungsverdeckung und Sonnenschatten; "
                                      "Material beleuchtet lassen, Sonne als DirectionalLight in sunDirection"}
        sw.save()

        usdz = courses / area["id"] / f"scene-{level}.usdz"
        if usdz.exists():
            usdz.unlink()
        ok = UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(out_dir / "scene.usdc")), str(usdz))
        size = usdz.stat().st_size / 1e6 if usdz.exists() else 0
        n_meshes = len([p for p in sw.stage.Traverse() if p.IsA(UsdGeom.Mesh)])
        print(f"[{level}] Kacheln {n_chunks}, Meshes {n_meshes}, Dreiecke Gelände {terrain_tris:,}, Gebäude {sw.n_tris - terrain_tris - n_bridge_tris - n_tree_tris - n_pf_tris - n_tint_tris:,}, "
              f"Brücken {n_bridge_tris:,}, Bäume {n_tree_tris:,}, "
              + (f"Pfahlbauten {n_pf_tris:,}, Wasserfarbe {n_tint_tris:,}, " if (n_pf_tris or n_tint_tris) else "") +
              f"gesamt {sw.n_tris:,}, Texturen {tex_px / 1e6:.1f} Mpx (≈ {tex_px * 4 * 1.33 / 2**20:.0f} MB RGBA "
              f"mit Mipmaps), USDZ {size:.0f} MB, ok={ok}", flush=True)

    # --- Strecken (unabhängig von der Qualitätsstufe)
    for f in routes:
        cs = np.array(f["geometry"]["coordinates"])
        xyz = frame.xyz(cs[:, 0], cs[:, 1], np.full(len(cs), lake))
        rid = f["properties"]["id"]
        rdef = next(r for r in area["routes"] if r["id"] == rid)
        d = courses / rid
        d.mkdir(parents=True, exist_ok=True)
        course = {
            "id": rid, "title": rdef["title"], "region": area["title"],
            "scene": f"{area['id']}/scene-{{quality}}.usdz",
            # nur Stufen, deren Szene gebaut ist (z. B. ohne "hoch", wenn bake.py dafür nicht lief)
            "qualities": [q for q in QUALITY if (courses / area["id"] / f"scene-{q}.usdz").exists()] or list(QUALITY),
            "one_way_m": f["properties"]["one_way_m"], "total_m": f["properties"]["total_m"],
            "turns": 1 if f["properties"].get("shape", "out_and_back") == "out_and_back" else 0,
            "crs": area_crs(area), "origin": origin, "lake_level_m": lake,
            "path_xz": [[round(float(x), 2), round(float(z), 2)] for x, _, z in xyz[::2]],
            "attribution": area["attribution"],
        }
        if f["properties"].get("shape") == "loop":
            course["loop"] = True  # Rundkurs: Ende = Start, Runden schliessen nahtlos an
        for key in ("country", "city"):  # Land (ISO) und Stadt für die Gruppierung in der Streckenauswahl
            if area.get(key):
                course[key] = area[key]
        if area_crs(area) == "EPSG:2056":
            course["origin_lv95"] = origin  # Schweiz: wie bisher (ältere App-Stände lesen nur dieses Feld)
        if area.get("app_qualities"):
            course["bundle_qualities"] = area["app_qualities"]  # optional, nur für install_courses.py
        tint_meta = courses / area["id"] / "water_tint.json"
        if area.get("water_tint") and tint_meta.exists():
            # Amazonas: zweite Wasserfarbe, die App legt sie als halbdurchsichtige Fläche über ihr Wasser
            course["water_tint"] = {k: v for k, v in json.loads(tint_meta.read_text()).items() if k != "size"}
        # Streckentexte (Beschreibung, Sehenswertes, Brücken) aus der Gebietsdatei – bisher nie übernommen
        texts = next((r.get("course_texts") for r in area.get("routes", []) if r.get("id") == rid), None) or {}
        for key in ("description", "highlights", "bridges"):
            if texts.get(key):
                course[key] = texts[key]
        old = d / "course.json"
        if old.exists():
            # alle Felder behalten, die export.py nicht selbst berechnet: minimap/overview (minimap.py), traffic
            # (lanes.py), description/highlights/bridges (Streckentexte) und künftige; light_variants (export.py
            # --light) nur solange die Ordner da sind; bundle_qualities/origin_lv95 kommen nur aus der Gebietsdatei
            prev = json.loads(old.read_text())
            for key, val in prev.items():
                if key not in course and key not in ("light_variants", "bundle_qualities", "origin_lv95"):
                    course[key] = val
            lv = prev.get("light_variants")
            if lv:
                lv = keep_existing_variants(courses, lv)
                if lv:
                    course["light_variants"] = lv
        (d / "course.json").write_text(json.dumps(course, ensure_ascii=False))
        print(f"Strecke {rid}: {course['total_m']:.0f} m, {len(course['path_xz'])} Punkte")


def write_buildings_and_bridges(sw, area, area_file, build, level, out_dir):
    """Gebäude (bake/<stufe>/) unter /Scene/Buildings und Brücken (bridges/, nur mit "bridges" in der Gebietsdatei)
    unter /Scene/Bridges anhängen. Liefert (Gebäude-meta, Texturpixel, Brückendreiecke)."""
    tex_px = 0
    UsdGeom.Xform.Define(sw.stage, "/Scene/Buildings")
    bake = build / "bake" / level
    if not (bake / "groups.npz").exists():
        sys.exit(f"Fehlt: {bake}/groups.npz – zuerst bake.py {area_file} {level} laufen lassen")
    meta = json.loads((bake / "meta.json").read_text())
    g = np.load(bake / "groups.npz")
    for m in meta["meshes"]:
        nm = m["name"]
        v = g[f"{nm}__v"].astype(np.float64)
        n = g[f"{nm}__n"].astype(np.float64)
        shutil.copy(bake / f"{nm}.jpg", out_dir / f"{nm}.jpg")
        tex_px += m["atlas"][0] * m["atlas"][1]
        mat = sw.material_tex(nm, f"{nm}.jpg", rough=0.9)
        pts = np.column_stack([v[:, 0], v[:, 2], -v[:, 1]])
        nrm = np.column_stack([n[:, 0], n[:, 2], -n[:, 1]])
        sw.mesh(f"/Scene/Buildings/{nm}", pts, g[f"{nm}__f"], mat, uv=g[f"{nm}__uv"], normals=nrm)
    # Brücken (für alle Stufen gleich)
    n_bridge_tris = 0
    if area.get("bridges"):
        bdir = build / "bridges"
        if not (bdir / "bridges.npz").exists():
            sys.exit(f"Fehlt: {bdir}/bridges.npz – zuerst bridges.py {area_file} laufen lassen")
        UsdGeom.Xform.Define(sw.stage, "/Scene/Bridges")
        bmeta = json.loads((bdir / "meta.json").read_text())
        gb = np.load(bdir / "bridges.npz")
        t0 = sw.n_tris
        for nm in bmeta["meshes"]:
            v = gb[f"{nm}__v"].astype(np.float64)
            n = gb[f"{nm}__n"].astype(np.float64)
            shutil.copy(bdir / f"{nm}.jpg", out_dir / f"{nm}.jpg")
            with Image.open(bdir / f"{nm}.jpg") as im:
                tex_px += im.width * im.height
            mat = sw.material_tex(nm, f"{nm}.jpg", rough=0.9)
            pts = np.column_stack([v[:, 0], v[:, 2], -v[:, 1]])
            nrm = np.column_stack([n[:, 0], n[:, 2], -n[:, 1]])
            sw.mesh(f"/Scene/Bridges/{nm}", pts, gb[f"{nm}__f"], mat, uv=gb[f"{nm}__uv"], normals=nrm)
        n_bridge_tris = sw.n_tris - t0
    # Wahrzeichen (landmarks.py, nur mit "landmarks"; zählen in der Ausgabe zu den Brücken)
    if area.get("landmarks"):
        ldir = build / "landmarks"
        if not (ldir / "landmarks.npz").exists():
            sys.exit(f"Fehlt: {ldir}/landmarks.npz – zuerst landmarks.py {area_file} laufen lassen")
        UsdGeom.Xform.Define(sw.stage, "/Scene/Landmarks")
        lmeta = json.loads((ldir / "meta.json").read_text())
        gl = np.load(ldir / "landmarks.npz")
        t0 = sw.n_tris
        for nm in lmeta["meshes"]:
            v = gl[f"{nm}__v"].astype(np.float64)
            n = gl[f"{nm}__n"].astype(np.float64)
            shutil.copy(ldir / f"{nm}.jpg", out_dir / f"{nm}.jpg")
            with Image.open(ldir / f"{nm}.jpg") as im:
                tex_px += im.width * im.height
            mat = sw.material_tex(nm, f"{nm}.jpg", rough=0.85)
            pts = np.column_stack([v[:, 0], v[:, 2], -v[:, 1]])
            nrm = np.column_stack([n[:, 0], n[:, 2], -n[:, 1]])
            sw.mesh(f"/Scene/Landmarks/{nm}", pts, gl[f"{nm}__f"], mat, uv=gl[f"{nm}__uv"], normals=nrm)
        n_lm = sw.n_tris - t0
        print(f"[{level}] Wahrzeichen {len(lmeta['meshes'])}, {n_lm:,} Dreiecke", flush=True)
        n_bridge_tris += n_lm
    return meta, tex_px, n_bridge_tris


def summer_inputs(area, build, level):
    """(Farbanpassung an?, veg.tif oder None, tree_ao.tif oder None) – nur mit "summer_grade" bzw. "trees"."""
    grade_on = bool(area.get("summer_grade"))
    veg = build / "trees" / "veg.tif"
    tao = build / "trees" / level / "tree_ao.tif"
    return grade_on, (veg if grade_on and veg.exists() else None), (tao if area.get("trees") and tao.exists() else None)


def write_trees(sw, area, area_file, build, level, out_dir):
    """Bäume (trees.py → trees/<stufe>/) unter /Scene/Trees anhängen. Liefert (Dreiecke, Texturpixel)."""
    if not area.get("trees"):
        return 0, 0
    tdir = build / "trees" / level
    if not (tdir / "trees.npz").exists():
        sys.exit(f"Fehlt: {tdir}/trees.npz – zuerst trees.py {area_file} {level} laufen lassen")
    UsdGeom.Xform.Define(sw.stage, "/Scene/Trees")
    meta = json.loads((tdir / "meta.json").read_text())
    g = np.load(tdir / "trees.npz")
    t0, px = sw.n_tris, 0
    for m in meta["meshes"]:
        nm = m["name"]
        v = g[f"{nm}__v"].astype(np.float64)
        n = g[f"{nm}__n"].astype(np.float64)
        shutil.copy(tdir / f"{nm}.jpg", out_dir / f"{nm}.jpg")
        px += m["atlas"][0] * m["atlas"][1]
        mat = sw.material_tex(nm, f"{nm}.jpg", rough=0.95)
        pts = np.column_stack([v[:, 0], v[:, 2], -v[:, 1]])
        nrm = np.column_stack([n[:, 0], n[:, 2], -n[:, 1]])
        sw.mesh(f"/Scene/Trees/{nm}", pts, g[f"{nm}__f"], mat, uv=g[f"{nm}__uv"], normals=nrm)
    return sw.n_tris - t0, px


def keep_existing_variants(courses, lv):
    """Nur Licht-Varianten und Stufen behalten, deren USDZ noch da ist."""
    out = {}
    for vid, v in lv.items():
        qs = [q for q in v.get("qualities", []) if (courses / v["textures"].replace("{quality}", q)).is_dir()]
        if qs:
            out[vid] = {**v, "qualities": qs}
    return out


def export_light_variant(area_file, levels, light):
    """Nur die Texturatlanten der Licht-Variante (Gebäude + Brücken ohne Sonnenschatten) neben die Szene legen und
    course.json ergänzen. Geometrie und UV sind dieselben wie in scene-<stufe>.usdz (wird hier geprüft); die App
    tauscht nur die Grundfarb-Textur der gleichnamigen Meshes. Kostet im Bundle nur die Atlanten (Zürich standard
    ≈ 9 MB statt 51 MB für eine zweite Gebäude-USDZ)."""
    area = load_area(area_file)
    build = Path("build") / area["id"]
    courses = Path("../../courses")
    replaces = ["Buildings"] + (["Bridges"] if area.get("bridges") else [])
    pairs = [("bake/{level}", "bake/{level}-" + light, "groups.npz")]
    if area.get("bridges"):
        pairs.append(("bridges", "bridges-" + light, "bridges.npz"))
    if area.get("trees"):
        replaces.append("Trees")
        pairs.append(("trees/{level}", "trees/{level}-" + light, "trees.npz"))
    for level in levels:
        name = f"light-{light}-{level}"
        out_dir = courses / area["id"] / name
        if out_dir.exists():
            shutil.rmtree(out_dir)
        out_dir.mkdir(parents=True)
        n_files = n_bytes = 0
        for sun_rel, var_rel, npz in pairs:
            sun_dir = build / sun_rel.format(level=level)
            var_dir = build / var_rel.format(level=level)
            if not (var_dir / npz).exists():
                flag = {"groups.npz": f"bake.py {area_file} {level}", "bridges.npz": f"bridges.py {area_file}",
                        "trees.npz": f"trees.py {area_file} {level} (schreibt beide Varianten)"}[npz]
                sys.exit(f"Fehlt: {var_dir}/{npz} – zuerst {flag} --light {light} laufen lassen")
            a, b = np.load(sun_dir / npz), np.load(var_dir / npz)
            same = sorted(a.files) == sorted(b.files) and all(np.array_equal(a[k], b[k]) for k in a.files)
            if not same:
                sys.exit(f"{var_dir}: Geometrie/UV weicht von {sun_dir} ab – Szene und Variante neu rechnen "
                         f"(bake.py bzw. bridges.py mit und ohne --light, dann export.py)")
            for jpg in sorted(var_dir.glob("tree_*.jpg" if npz == "trees.npz" else "*.jpg")):
                shutil.copy(jpg, out_dir / jpg.name)
                n_files += 1
                n_bytes += jpg.stat().st_size
        print(f"[{level}, {light}] {n_files} Atlanten, {n_bytes / 1e6:.1f} MB → {out_dir}", flush=True)
    rel = f"{area['id']}/light-{light}-{{quality}}"
    qs = [q for q in QUALITY if (courses / rel.replace("{quality}", q)).is_dir()]
    for r in area["routes"]:
        cj = courses / r["id"] / "course.json"
        if not cj.exists():
            print(f"Fehlt: {cj} – zuerst export.py ohne --light laufen lassen", file=sys.stderr)
            continue
        c = json.loads(cj.read_text())
        lv = c.get("light_variants") or {}
        lv[light] = {"textures": rel, "qualities": qs, "replaces": replaces}
        c["light_variants"] = lv
        cj.write_text(json.dumps(c, ensure_ascii=False))
        print(f"Strecke {r['id']}: light_variants.{light} = {qs}")


if __name__ == "__main__":
    argv = sys.argv[1:]
    light = "sun"
    if "--light" in argv:
        i = argv.index("--light")
        light = argv[i + 1]
        del argv[i:i + 2]
        if light not in ("sun", "ambient"):
            sys.exit("--light sun|ambient")
    if light == "sun":
        main(argv[0], argv[1:] or ["standard", "hoch"])
    else:
        export_light_variant(argv[0], argv[1:] or ["standard", "hoch"], light)
