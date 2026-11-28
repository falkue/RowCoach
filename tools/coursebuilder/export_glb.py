"""GLB-Export einer fertigen Streckenszene für Android (Filament/gltfio) – Machbarkeitstest.

Liest die Szene, die export.py gebaut hat (../../courses/<gebiet>/scene-<stufe>/scene.usdc, sonst die USDZ), und schreibt
dieselben Meshes und Texturen als eine glTF-Binärdatei (GLB 2.0):

- Koordinaten unverändert: Meter, y nach oben, rechtshändig – RealityKit und glTF stimmen überein
  (x = E - E0, y = H - Seehöhe, z = -(N - N0); course.json "path_xz" passt also direkt).
- Je USD-Mesh ein glTF-Mesh (Dreiecke, POSITION/NORMAL/TEXCOORD_0, Index uint16 oder uint32) und ein Material
  (baseColorTexture aus der Grundfarb-Textur, metallic 0, roughness aus USD). Texturkoordinaten: v = 1 - t.
- Knoten wie in der USD: Terrain, Buildings, Bridges, Trees (die App kann Gruppen ein-/ausblenden).
- Texturen über --max-tex (Standard 2048 px) werden verkleinert und neu als JPEG gespeichert, sonst unverändert kopiert.
- Optional (Standard an): "Water" – eine Wasserfläche auf y = 0 über der ganzen Szene (blaues, glattes PBR-Material),
  weil die iOS-App das Wasser selbst zeichnet und Android dann kein eigenes Filament-Material (matc) braucht.
- Optional (Standard an): "Boat" – Einer der Detailstufe lite aus tools/avatars/lite.py (Rumpf, Ruderer, Ruder) mit
  einer 16 × 1-Palettentextur, Bug in -z, Ursprung auf der Wasserlinie. Die App setzt nur die Transformation dieses
  Knotens.
- scene.extras: Sonnenrichtung (aus customLayerData), Gebiet, Stufe.

Aufruf (aus tools/coursebuilder):
  .venv/bin/python export_glb.py henley-regatta [standard] [--max-tex 2048] [--no-water] [--no-boat] [--out PFAD]
Ergebnis: ../../courses/<gebiet>/scene-<stufe>.glb (nicht in Git; android/fetch_assets.sh kopiert es in die App)
"""
import argparse
import io
import json
import struct
import sys
import tempfile
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image
from pxr import Usd, UsdGeom, UsdShade

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
COURSES = ROOT / "courses"

# glTF-Konstanten
FLOAT, U16, U32, U8 = 5126, 5123, 5125, 5121
ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER = 34962, 34963
LINEAR, LINEAR_MIPMAP_LINEAR, CLAMP, REPEAT = 9729, 9987, 33071, 10497

# Palette für das Boot (Slots wie PALETTE in tools/avatars/lite.py); Bahnen-Marke: Kobalt #2340FF, Gelb #FFD60A
BOAT_COLORS = {"hull": (245, 245, 240), "deck": (255, 214, 10), "stripe": (35, 64, 255), "rigger": (60, 60, 66),
               "blade": (255, 214, 10), "shaft": (235, 235, 235), "skin": (224, 172, 135), "shirt": (35, 64, 255),
               "hair": (70, 50, 35), "shorts": (30, 30, 36), "fittings": (90, 90, 96), "shoes": (240, 240, 240)}


class GlbWriter:
    def __init__(self):
        self.bin = bytearray()
        self.gltf = {"asset": {"version": "2.0", "generator": "RowCoach export_glb.py"},
                     "scene": 0, "scenes": [{"nodes": []}], "nodes": [], "meshes": [], "materials": [],
                     "textures": [], "images": [], "samplers": [], "accessors": [], "bufferViews": [],
                     "buffers": []}
        self.tris = 0
        self.tex_bytes = 0

    def _view(self, data: bytes, target=None) -> int:
        while len(self.bin) % 4:
            self.bin.append(0)
        v = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data)}
        if target:
            v["target"] = target
        self.bin += data
        self.gltf["bufferViews"].append(v)
        return len(self.gltf["bufferViews"]) - 1

    def _accessor(self, arr: np.ndarray, ctype, typ, target, minmax=False) -> int:
        a = {"bufferView": self._view(arr.tobytes(), target), "componentType": ctype, "count": int(arr.shape[0]),
             "type": typ}
        if minmax:
            a["min"] = arr.min(axis=0).astype(float).tolist()
            a["max"] = arr.max(axis=0).astype(float).tolist()
        self.gltf["accessors"].append(a)
        return len(self.gltf["accessors"]) - 1

    def sampler(self, wrap) -> int:
        s = {"magFilter": LINEAR, "minFilter": LINEAR_MIPMAP_LINEAR, "wrapS": wrap, "wrapT": wrap}
        if s in self.gltf["samplers"]:
            return self.gltf["samplers"].index(s)
        self.gltf["samplers"].append(s)
        return len(self.gltf["samplers"]) - 1

    def image(self, data: bytes, mime: str, name: str, wrap=CLAMP) -> int:
        self.tex_bytes += len(data)
        self.gltf["images"].append({"bufferView": self._view(data), "mimeType": mime, "name": name})
        self.gltf["textures"].append({"source": len(self.gltf["images"]) - 1, "sampler": self.sampler(wrap)})
        return len(self.gltf["textures"]) - 1

    def material(self, name, tex=None, color=(1, 1, 1, 1), roughness=0.9, metallic=0.0, double=False) -> int:
        pbr = {"baseColorFactor": list(color), "metallicFactor": metallic, "roughnessFactor": roughness}
        if tex is not None:
            pbr["baseColorTexture"] = {"index": tex}
        m = {"name": name, "pbrMetallicRoughness": pbr, "doubleSided": bool(double)}
        self.gltf["materials"].append(m)
        return len(self.gltf["materials"]) - 1

    def mesh(self, name, pos, nrm, uv, idx, mat) -> int:
        pos = np.ascontiguousarray(pos, dtype="<f4")
        attrs = {"POSITION": self._accessor(pos, FLOAT, "VEC3", ARRAY_BUFFER, minmax=True)}
        if nrm is not None:
            n = np.asarray(nrm, dtype=np.float64)
            ln = np.linalg.norm(n, axis=1, keepdims=True)
            n = np.where(ln > 1e-12, n / np.maximum(ln, 1e-12), [0.0, 1.0, 0.0])
            attrs["NORMAL"] = self._accessor(np.ascontiguousarray(n, dtype="<f4"), FLOAT, "VEC3", ARRAY_BUFFER)
        if uv is not None:
            attrs["TEXCOORD_0"] = self._accessor(np.ascontiguousarray(uv, dtype="<f4"), FLOAT, "VEC2", ARRAY_BUFFER)
        idx = np.asarray(idx).reshape(-1)
        it = U16 if len(pos) < 65536 else U32
        ia = np.ascontiguousarray(idx, dtype="<u2" if it == U16 else "<u4")
        prim = {"attributes": attrs, "indices": self._accessor(ia, it, "SCALAR", ELEMENT_ARRAY_BUFFER),
                "material": mat, "mode": 4}
        self.tris += len(idx) // 3
        self.gltf["meshes"].append({"name": name, "primitives": [prim]})
        return len(self.gltf["meshes"]) - 1

    def node(self, name, mesh=None, children=None, translation=None, rotation=None, extras=None, root=False) -> int:
        n = {"name": name}
        if mesh is not None:
            n["mesh"] = mesh
        if children:
            n["children"] = children
        if translation is not None:
            n["translation"] = [float(x) for x in translation]
        if rotation is not None:
            n["rotation"] = [float(x) for x in rotation]
        if extras:
            n["extras"] = extras
        self.gltf["nodes"].append(n)
        i = len(self.gltf["nodes"]) - 1
        if root:
            self.gltf["scenes"][0]["nodes"].append(i)
        return i

    def write(self, path: Path):
        while len(self.bin) % 4:
            self.bin.append(0)
        self.gltf["buffers"] = [{"byteLength": len(self.bin)}]
        for k in ("textures", "images", "samplers"):
            if not self.gltf[k]:
                del self.gltf[k]
        js = json.dumps(self.gltf, separators=(",", ":")).encode()
        js += b" " * (-len(js) % 4)
        total = 12 + 8 + len(js) + 8 + len(self.bin)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
            f.write(struct.pack("<II", len(self.bin), 0x004E4942) + bytes(self.bin))


def load_texture(path: Path, max_tex: int, quality: int):
    """Gibt (bytes, mime, (w, h), verkleinert?) zurück."""
    raw = path.read_bytes()
    im = Image.open(io.BytesIO(raw))
    w, h = im.size
    mime = "image/png" if im.format == "PNG" else "image/jpeg"
    if max(w, h) <= max_tex and im.format in ("JPEG", "PNG"):
        return raw, mime, (w, h), False
    s = max_tex / max(w, h)
    im = im.convert("RGB").resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=quality, optimize=True)
    return buf.getvalue(), "image/jpeg", im.size, True


def bound_texture(prim):
    """Pfad der Grundfarb-Textur (UsdUVTexture inputs:file) und roughness des gebundenen Materials."""
    mat = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0]
    tex, rough, color = None, 0.9, None
    if not mat:
        return tex, rough, color
    for sh in mat.GetPrim().GetChildren():
        s = UsdShade.Shader(sh)
        if not s:
            continue
        sid = s.GetIdAttr().Get()
        if sid == "UsdUVTexture":
            f = s.GetInput("file").Get()
            if f is not None:
                tex = Path(f.resolvedPath or f.path)
        elif sid == "UsdPreviewSurface":
            r = s.GetInput("roughness")
            if r and r.Get() is not None:
                rough = float(r.Get())
            d = s.GetInput("diffuseColor")
            if d and not d.HasConnectedSource() and d.Get() is not None:
                color = tuple(float(x) for x in d.Get())
    return tex, rough, color


def triangulate(counts, indices, left_handed):
    counts = np.asarray(counts)
    indices = np.asarray(indices)
    if (counts == 3).all():
        tri = indices.reshape(-1, 3)
    else:  # Fächer
        out, o = [], 0
        for c in counts:
            for k in range(1, c - 1):
                out.append((indices[o], indices[o + k], indices[o + k + 1]))
            o += c
        tri = np.array(out, dtype=np.int64)
    if left_handed:
        tri = tri[:, [0, 2, 1]]
    return tri


def open_scene(area: str, quality: str, tmp: Path) -> Path:
    d = COURSES / area / f"scene-{quality}" / "scene.usdc"
    if d.exists():
        return d
    z = COURSES / area / f"scene-{quality}.usdz"
    if not z.exists():
        z = ROOT / "App" / "Courses" / area / f"scene-{quality}.usdz"
    if not z.exists():
        sys.exit(f"keine Szene für {area}/{quality} gefunden (erst export.py laufen lassen)")
    with zipfile.ZipFile(z) as zf:
        zf.extractall(tmp)
    usd = [p for p in tmp.rglob("*.usd*")]
    if not usd:
        sys.exit(f"{z}: keine USD-Datei im Paket")
    return usd[0]


def add_scene(w: GlbWriter, usd_path: Path, max_tex: int, jpeg_q: int, stats: dict):
    stage = Usd.Stage.Open(str(usd_path))
    if UsdGeom.GetStageUpAxis(stage) != UsdGeom.Tokens.y:
        sys.exit("Szene ist nicht y-oben – nicht unterstützt")
    mpu = UsdGeom.GetStageMetersPerUnit(stage)
    groups: dict[str, list[int]] = {}
    tex_cache: dict[Path, int] = {}
    lo, hi = np.full(3, np.inf), np.full(3, -np.inf)
    xcache = UsdGeom.XformCache()
    for prim in stage.Traverse():
        if not prim.IsA(UsdGeom.Mesh):
            continue
        m = UsdGeom.Mesh(prim)
        pts = np.asarray(m.GetPointsAttr().Get(), dtype=np.float64)
        if len(pts) == 0:
            continue
        xf = np.asarray(xcache.GetLocalToWorldTransform(prim), dtype=np.float64)  # Zeilenvektoren
        pts = (np.c_[pts, np.ones(len(pts))] @ xf)[:, :3] * mpu
        tri = triangulate(m.GetFaceVertexCountsAttr().Get(), m.GetFaceVertexIndicesAttr().Get(),
                          m.GetOrientationAttr().Get() == UsdGeom.Tokens.leftHanded)
        nrm = m.GetNormalsAttr().Get()
        if nrm is not None and m.GetNormalsInterpolation() in (UsdGeom.Tokens.vertex, UsdGeom.Tokens.varying) \
                and len(nrm) == len(pts):
            nrm = np.asarray(nrm, dtype=np.float64) @ np.linalg.inv(xf[:3, :3]).T
        else:
            nrm = None  # gltfio rechnet dann flache Normalen
        uv = None
        st = UsdGeom.PrimvarsAPI(prim).GetPrimvar("st")
        if st and st.HasValue():
            vals = st.ComputeFlattened()
            if vals is not None and len(vals) == len(pts):
                uv = np.asarray(vals, dtype=np.float64)
                uv[:, 1] = 1.0 - uv[:, 1]
        tex_path, rough, color = bound_texture(prim)
        tex = None
        if tex_path is not None and uv is not None:
            tex_path = tex_path if tex_path.exists() else usd_path.parent / tex_path.name
            if tex_path not in tex_cache:
                data, mime, size, resized = load_texture(tex_path, max_tex, jpeg_q)
                tex_cache[tex_path] = w.image(data, mime, tex_path.stem)
                stats["textures"].append((tex_path.name, size, len(data), resized))
            tex = tex_cache[tex_path]
        name = prim.GetName()
        mat = w.material(name, tex=tex, color=(*color, 1.0) if color and tex is None else (1, 1, 1, 1),
                         roughness=rough, double=bool(m.GetDoubleSidedAttr().Get()))
        mi = w.mesh(name, pts, nrm, uv if tex is not None else None, tri, mat)
        group = prim.GetParent().GetName()
        groups.setdefault(group, []).append(w.node(name, mesh=mi))
        stats["meshes"].setdefault(group, [0, 0])
        stats["meshes"][group][0] += 1
        stats["meshes"][group][1] += len(tri)
        lo, hi = np.minimum(lo, pts.min(0)), np.maximum(hi, pts.max(0))
    for g, kids in groups.items():
        w.node(g, children=kids, root=True)
    sun = stage.GetRootLayer().customLayerData.get("rowcoach:sunDirection")
    return lo, hi, (list(map(float, sun)) if sun is not None else None)


def add_water(w: GlbWriter, lo, hi, stats):
    pad = 2000.0
    x0, x1, z0, z1 = lo[0] - pad, hi[0] + pad, lo[2] - pad, hi[2] + pad
    pos = np.array([[x0, 0, z0], [x1, 0, z0], [x1, 0, z1], [x0, 0, z1]], dtype=np.float64)
    nrm = np.tile([0.0, 1.0, 0.0], (4, 1))
    tri = np.array([[0, 2, 1], [0, 3, 2]])  # Normale nach oben (gegen den Uhrzeigersinn von oben gesehen)
    mat = w.material("Water", color=(0.10, 0.22, 0.30, 1.0), roughness=0.12, metallic=0.0)
    w.node("Water", mesh=w.mesh("Water", pos, nrm, None, tri, mat), root=True)
    stats["meshes"]["Water"] = [1, 2]


def add_boat(w: GlbWriter, stats):
    sys.path.insert(0, str(ROOT / "tools" / "avatars"))
    import boat as B  # noqa: E402
    import lite  # noqa: E402

    pal = Image.new("RGB", (lite.SLOTS, 1), (128, 128, 128))
    for i, slot in enumerate(lite.PALETTE):
        pal.putpixel((i, 0), BOAT_COLORS.get(slot, (128, 128, 128)))
    buf = io.BytesIO()
    pal.save(buf, "PNG")
    # Palette: kein Mipmapping-Verwischen zwischen Slots nötig, u liegt in der Pixelmitte
    tex = w.image(buf.getvalue(), "image/png", "boat_palette")
    mat = w.material("BoatPalette", tex=tex, roughness=0.6, double=False)
    kids = []
    parts = lite.build_parts()
    placement = {"lite_hull": (None, None), "lite_rower": (None, None),
                 "lite_oar_R": ((B.PIN_X, B.PIN_Y, B.PIN_Z), None),
                 "lite_oar_L": ((-B.PIN_X, B.PIN_Y, B.PIN_Z), (0.0, 1.0, 0.0, 0.0))}  # 180° um y
    tris = 0
    for name, (_frame, _grp, part) in parts.items():
        v = np.asarray(part.v, dtype=np.float64)
        f = np.asarray(part.f, dtype=np.int64)
        fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
        vn = np.zeros_like(v)
        for k in range(3):
            np.add.at(vn, f[:, k], fn)
        uv = np.asarray(part.uv, dtype=np.float64).copy()
        uv[:, 1] = 1.0 - uv[:, 1]
        t, r = placement[name]
        kids.append(w.node(name, mesh=w.mesh(name, v, vn, uv, f, mat), translation=t, rotation=r))
        tris += len(f)
    w.node("Boat", children=kids, root=True, extras={"forward": [0, 0, -1], "note": "Bug in -z, Wasserlinie y=0"})
    stats["meshes"]["Boat"] = [len(kids), tris]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("area")
    ap.add_argument("quality", nargs="?", default="standard")
    ap.add_argument("--max-tex", type=int, default=2048, help="grösste Texturkante in px (Mobilgerät)")
    ap.add_argument("--jpeg-q", type=int, default=82)
    ap.add_argument("--no-water", action="store_true")
    ap.add_argument("--no-boat", action="store_true")
    ap.add_argument("--out", type=Path)
    a = ap.parse_args()

    out = a.out or COURSES / a.area / f"scene-{a.quality}.glb"
    stats = {"meshes": {}, "textures": []}
    w = GlbWriter()
    with tempfile.TemporaryDirectory() as td:
        usd = open_scene(a.area, a.quality, Path(td))
        lo, hi, sun = add_scene(w, usd, a.max_tex, a.jpeg_q, stats)
    if not a.no_water:
        add_water(w, lo, hi, stats)
    if not a.no_boat:
        add_boat(w, stats)
    w.gltf["scenes"][0]["extras"] = {"area": a.area, "quality": a.quality, "sunDirection": sun,
                                     "bounds": [lo.tolist(), hi.tolist()]}
    out.parent.mkdir(parents=True, exist_ok=True)
    w.write(out)

    print(f"{out}  {out.stat().st_size / 1e6:.1f} MB, {w.tris:,} Dreiecke, Texturen {w.tex_bytes / 1e6:.1f} MB "
          f"({len(stats['textures'])}, verkleinert {sum(t[3] for t in stats['textures'])})")
    for g, (n, t) in stats["meshes"].items():
        print(f"  {g:10s} {n:3d} Meshes {t:9,d} Dreiecke")
    print(f"  Ausdehnung x {lo[0]:.0f}…{hi[0]:.0f} m, z {lo[2]:.0f}…{hi[2]:.0f} m, Sonne {sun}")


if __name__ == "__main__":
    main()
