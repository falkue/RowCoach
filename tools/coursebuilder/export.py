"""Schritt 4: 3D-Szene (USDZ) und Streckendateien für die App bauen.

Koordinaten der Szene (RealityKit): Meter, y nach oben, Ursprung = origin_lv95 auf Seehöhe.
  x = E - E0,  y = H - Seehöhe,  z = -(N - N0)

Gelände Kerngebiet: Kacheln à 250 m, Auflösung nach Abstand zur Strecke; Textur aus SWISSIMAGE 10 cm.
Gelände Umgebung: grobes Gitter mit Luftbild 2 m. Unter Wasser wird das Gelände 1 m abgesenkt;
die Wasserfläche (y = 0) zeichnet die App selbst.
Gebäude: swissBUILDINGS3D 3.0, nach Materialgruppen (Dächer, Wände) zusammengefasst.

Qualitätsstufen (Konzept Abschnitt 5): standard (A12X) und hoch (M-Chip).

Ergebnis: ../../courses/<area>/scene-<stufe>.usdz, ../../courses/<route>/course.json
Aufruf: .venv/bin/python export.py areas/<area>.json [standard|hoch ...]
"""
import json
import math

import fast_simplification
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
from shapely.geometry import LineString, box, shape

QUALITY = {
    # Gitterabstand (m) je Abstandsband zur Strecke, Texturgrösse (px) je Band, Umgebung
    # bld_bands: (max. Abstand zur Strecke in m, Anteil Dreiecke, der wegvereinfacht wird)
    "standard": {"bands": [(300, 4.0, 512), (1000, 10.0, 256), (1e9, 25.0, 128)],
                 "far_step": 100.0, "far_tex": 2048, "jpeg_q": 82,
                 "bld_bands": [(400, 0.0), (1000, 0.6), (1800, 0.85)]},
    "hoch": {"bands": [(400, 2.0, 1024), (1200, 5.0, 512), (1e9, 10.0, 256)],
             "far_step": 50.0, "far_tex": 4096, "jpeg_q": 88,
             "bld_bands": [(800, 0.0), (2000, 0.4), (1e9, 0.7)]},
}
CHUNK = 250.0
SKIRT = 4.0

ROOF_COLORS = [(0.55, 0.30, 0.24), (0.42, 0.40, 0.40), (0.62, 0.42, 0.33), (0.30, 0.30, 0.32)]
WALL_COLORS = [(0.86, 0.83, 0.77), (0.93, 0.92, 0.89), (0.78, 0.74, 0.68)]


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


def tile_path(folder, e, n, pattern):
    hits = list(folder.glob(f"*_{int(e // 1000)}-{int(n // 1000)}_{pattern}"))
    return hits[0] if hits else None


def read_rgb(path, bounds, size):
    with rasterio.open(path) as src:
        win = from_bounds(*bounds, src.transform)
        img = src.read([1, 2, 3], window=win, out_shape=(3, size, size), resampling=Resampling.average)
    return Image.fromarray(np.moveaxis(img, 0, -1))


class SceneWriter:
    def __init__(self, path):
        self.stage = Usd.Stage.CreateNew(str(path))
        UsdGeom.SetStageUpAxis(self.stage, UsdGeom.Tokens.y)
        UsdGeom.SetStageMetersPerUnit(self.stage, 1.0)
        self.root = UsdGeom.Xform.Define(self.stage, "/Scene")
        self.stage.SetDefaultPrim(self.root.GetPrim())
        UsdGeom.Scope.Define(self.stage, "/Scene/Materials")
        self.n_tris = 0

    def material_tex(self, name, tex_rel):
        m = UsdShade.Material.Define(self.stage, f"/Scene/Materials/{name}")
        sh = UsdShade.Shader.Define(self.stage, f"/Scene/Materials/{name}/PBR")
        sh.CreateIdAttr("UsdPreviewSurface")
        sh.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.95)
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

    def material_color(self, name, rgb, rough=0.85):
        m = UsdShade.Material.Define(self.stage, f"/Scene/Materials/{name}")
        sh = UsdShade.Shader.Define(self.stage, f"/Scene/Materials/{name}/PBR")
        sh.CreateIdAttr("UsdPreviewSurface")
        sh.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*rgb))
        sh.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(rough)
        sh.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0.0)
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


def flat_mesh(v, f):
    """Flache Schattierung für Gebäude: Ecken pro Dreieck duplizieren."""
    vv = v[f.reshape(-1)]
    ff = np.arange(len(vv)).reshape(-1, 3)
    fn = np.cross(vv[1::3] - vv[0::3], vv[2::3] - vv[0::3])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-9)
    return vv, ff, np.repeat(fn, 3, axis=0)


def main(area_file, levels):
    area = json.loads(Path(area_file).read_text())
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
    flat_f = np.abs(dem_f - lake) < 0.3
    dem_f = np.where(flat_f, lake - 1.0, dem_f)

    courses = Path("../../courses")
    for level in levels:
        q = QUALITY[level]
        out_dir = courses / area["id"] / f"scene-{level}"
        if out_dir.exists():
            shutil.rmtree(out_dir)
        out_dir.mkdir(parents=True)
        sw = SceneWriter(out_dir / "scene.usdc")
        UsdGeom.Xform.Define(sw.stage, "/Scene/Terrain")

        # --- Kerngebiet
        img_dir = raw / "image_core"
        n_chunks = 0
        for ce in np.arange(e0c, e1c, CHUNK):
            for cn in np.arange(n0c, n1c, CHUNK):
                b = (ce, cn, ce + CHUNK, cn + CHUNK)
                cbox = box(*b)
                if water.contains(cbox):
                    continue  # reine Seefläche: Wasser deckt alles
                dist = min(r.distance(cbox) for r in route_union)
                _, step, tex = next(bd for bd in q["bands"] if dist <= bd[0])
                pts, uv, faces = grid_mesh(*b, step, lambda e, n: bilinear(dem_c, tr_c, e, n))
                tp = tile_path(img_dir, ce, cn, "0.1_2056.tif")
                if tp is None:
                    continue
                name = f"c_{int(ce)}_{int(cn)}"
                read_rgb(tp, b, tex).save(out_dir / f"{name}.jpg", quality=q["jpeg_q"])
                mat = sw.material_tex(name, f"{name}.jpg")
                v = frame.xyz(pts[:, 0], pts[:, 1], pts[:, 2])
                sw.mesh(f"/Scene/Terrain/{name}", v, faces, mat, uv=uv, normals=vertex_normals(v, faces))
                n_chunks += 1

        # --- Umgebung (ohne Kerngebiet)
        step = q["far_step"]
        pts, uv, faces = grid_mesh(e0f, n0f, e1f, n1f, step, lambda e, n: bilinear(dem_f, tr_f, e, n) - 0.3,
                                   skirt=False)
        inside = (pts[:, 0] > e0c + step) & (pts[:, 0] < e1c - step) & (pts[:, 1] > n0c + step) & (pts[:, 1] < n1c - step)
        faces = faces[~inside[faces].all(axis=1)]
        with rasterio.open(build / "ortho_far.tif") as src:
            img = src.read([1, 2, 3], out_shape=(3, q["far_tex"], q["far_tex"]), resampling=Resampling.average)
        Image.fromarray(np.moveaxis(img, 0, -1)).save(out_dir / "far.jpg", quality=q["jpeg_q"])
        mat = sw.material_tex("far", "far.jpg")
        v = frame.xyz(pts[:, 0], pts[:, 1], pts[:, 2])
        sw.mesh("/Scene/Terrain/far", v, faces, mat, uv=uv, normals=vertex_normals(v, faces))
        terrain_tris = sw.n_tris

        # --- Gebäude
        UsdGeom.Xform.Define(sw.stage, "/Scene/Buildings")
        roof_mats = [sw.material_color(f"roof{i}", c, 0.8) for i, c in enumerate(ROOF_COLORS)]
        wall_mats = [sw.material_color(f"wall{i}", c, 0.9) for i, c in enumerate(WALL_COLORS)]
        cell = 500.0
        groups = {}
        for npz in sorted(build.glob("buildings_*.npz")):
            d = np.load(npz)
            centers = d["centers"]
            if len(centers) == 0:
                continue
            pts_c = [LineString([c[:2], c[:2] + 0.01]) for c in centers]
            dist = np.array([min(r.distance(p) for r in route_union) for p in pts_c])
            band = np.full(len(centers), -1)
            for bi, (maxd, _) in reversed(list(enumerate(q["bld_bands"]))):
                band[dist <= maxd] = bi
            cx = np.floor((centers[:, 0] - e0c) / cell).astype(int)
            cy = np.floor((centers[:, 1] - n0c) / cell).astype(int)
            for kind, mats in (("roof", roof_mats), ("wall", wall_mats)):
                vv, ff, bid = d[f"{kind}_v"], d[f"{kind}_f"], d[f"bid_{kind}"]
                if len(ff) == 0:
                    continue
                var = (bid.astype(np.int64) * 2654435761 % 2**32) % len(mats)
                key = np.stack([var, cx[bid], cy[bid], band[bid]], axis=1)
                ok = band[bid] >= 0
                for k in np.unique(key[ok], axis=0):
                    sel = ok & (key == k).all(axis=1)
                    groups.setdefault((kind, *map(int, k)), []).append((vv, ff[sel]))
        for (kind, i, gx, gy, bi), parts in groups.items():
            vs, fs, off = [], [], 0
            for vv, ff in parts:
                used, inv = np.unique(ff.ravel(), return_inverse=True)
                vs.append(vv[used]); fs.append(inv.reshape(-1, 3) + off); off += len(used)
            V = np.vstack(vs); F = np.vstack(fs)
            lv = frame.xyz(V[:, 0], V[:, 1], V[:, 2])
            # Ecken verschweissen (cm), damit die Vereinfachung Flächen zusammenfassen kann
            key = np.round(lv * 100).astype(np.int64)
            _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
            lv = lv[first]; lf = inv.reshape(-1)[F]
            lf = lf[(lf[:, 0] != lf[:, 1]) & (lf[:, 1] != lf[:, 2]) & (lf[:, 0] != lf[:, 2])]
            red = q["bld_bands"][bi][1]
            if red > 0 and len(lf) > 200:
                lv, lf = fast_simplification.simplify(lv.astype(np.float32), lf.astype(np.int64),
                                                      target_reduction=red)
            fv, fff, fn = flat_mesh(np.asarray(lv, np.float64), np.asarray(lf))
            mats = roof_mats if kind == "roof" else wall_mats
            sw.mesh(f"/Scene/Buildings/{kind}{i}_{gx + 100}_{gy + 100}_b{bi}", fv, fff, mats[i], normals=fn)
        sw.save()

        usdz = courses / area["id"] / f"scene-{level}.usdz"
        if usdz.exists():
            usdz.unlink()
        ok = UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(out_dir / "scene.usdc")), str(usdz))
        size = usdz.stat().st_size / 1e6 if usdz.exists() else 0
        print(f"[{level}] Kacheln {n_chunks}, Dreiecke Gelände {terrain_tris:,}, Gebäude {sw.n_tris - terrain_tris:,}, "
              f"USDZ {size:.0f} MB, ok={ok}", flush=True)

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
            "scene": f"{area['id']}/scene-{{quality}}.usdz", "qualities": list(QUALITY),
            "one_way_m": f["properties"]["one_way_m"], "total_m": f["properties"]["total_m"],
            "turns": 1, "origin_lv95": origin, "lake_level_m": lake,
            "path_xz": [[round(float(x), 2), round(float(z), 2)] for x, _, z in xyz[::2]],
            "attribution": area["attribution"],
        }
        (d / "course.json").write_text(json.dumps(course, ensure_ascii=False))
        print(f"Strecke {rid}: {course['total_m']:.0f} m, {len(course['path_xz'])} Punkte")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:] or ["standard", "hoch"])
