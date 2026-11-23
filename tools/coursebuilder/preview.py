"""Schritt 5: Vorschaubilder aus der Bootsperspektive (Kamera leicht erhöht hinter dem Ruderer).

Rendert auf der CPU (Mesa llvmpipe), braucht also keine GPU. Liest die Szene direkt aus scene.usdc;
die Sonnenrichtung kommt aus customLayerData (rowcoach:sunDirection), wie sie bake.py eingerechnet hat.
Ergebnis: ../../courses/<route>/preview-<stufe>-<n>.jpg

Aufruf (Umgebungsvariablen setzt run_preview.sh):
  .venv/bin/python preview.py <area-id> <stufe> <route-id> [<route-id> ...] [--checks]

Mit --checks zusätzlich Kontrollbilder (nicht für die App) nach build/<area>/checks/: Blick quer zur Fahrt nach
links und rechts (Ufer, Promenade, Löcher, schwebende oder versunkene Teile) an drei Stellen der Hinfahrt, und eine
Schrägansicht von oben auf die Wende.
"""
import json
import sys
from pathlib import Path

import numpy as np
import pyrender
from OpenGL.GL import GL_CLAMP_TO_EDGE, GL_LINEAR, GL_LINEAR_MIPMAP_LINEAR
import trimesh
from PIL import Image
from pxr import Usd, UsdGeom, UsdShade

W, H = 1600, 1000
LINEAR = pyrender.Sampler(magFilter=GL_LINEAR, minFilter=GL_LINEAR_MIPMAP_LINEAR, wrapS=GL_CLAMP_TO_EDGE,
                          wrapT=GL_CLAMP_TO_EDGE)
SKY = np.array([0.62, 0.76, 0.92])


def load_scene(usdc: Path):
    stage = Usd.Stage.Open(str(usdc))
    scene = pyrender.Scene(bg_color=[*SKY, 1.0], ambient_light=[0.35, 0.35, 0.38])
    tex_cache = {}
    n = 0
    for prim in stage.Traverse():
        if not prim.IsA(UsdGeom.Mesh):
            continue
        m = UsdGeom.Mesh(prim)
        pts = np.array(m.GetPointsAttr().Get(), dtype=np.float32)
        idx = np.array(m.GetFaceVertexIndicesAttr().Get(), dtype=np.int64).reshape(-1, 3)
        nrm = m.GetNormalsAttr().Get()
        mat, _ = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()
        pbr = UsdShade.Shader(stage.GetPrimAtPath(mat.GetPath().AppendChild("PBR")))
        tex_prim = stage.GetPrimAtPath(mat.GetPath().AppendChild("tex"))
        if tex_prim and tex_prim.IsValid():
            f = UsdShade.Shader(tex_prim).GetInput("file").Get().path
            img = tex_cache.get(f) or Image.open(usdc.parent / f).convert("RGB")
            tex_cache[f] = img
            st = np.array(UsdGeom.PrimvarsAPI(m).GetPrimvar("st").Get(), dtype=np.float32)
            tm = trimesh.Trimesh(pts, idx, vertex_normals=np.array(nrm) if nrm else None, process=False,
                                 visual=trimesh.visual.TextureVisuals(uv=st, image=img))
        else:
            c = pbr.GetInput("diffuseColor").Get()
            tm = trimesh.Trimesh(pts, idx, process=False)
            tm.visual.face_colors = np.array([*(np.array(c) * 255), 255], dtype=np.uint8)
        pm = pyrender.Mesh.from_trimesh(tm, smooth=nrm is not None and tex_prim.IsValid())
        for prim_ in pm.primitives:
            t = getattr(prim_.material, "baseColorTexture", None)
            if t is not None:  # wie RealityKit: linear mit Mipmaps (pyrender nimmt sonst GL_NEAREST)
                t.sampler = LINEAR
        scene.add(pm)
        n += 1
    # Wasser: grosse Fläche auf Seehöhe (die App zeichnet später ein richtiges Wassermaterial)
    water = trimesh.creation.box(extents=[30000, 0.02, 30000])
    water.visual.face_colors = [38, 74, 96, 255]
    scene.add(pyrender.Mesh.from_trimesh(water, smooth=False))
    sun = stage.GetRootLayer().customLayerData.get("rowcoach:sunDirection", (-0.4, -0.7, -0.5))
    return scene, n, np.array(sun, dtype=float)


def look_at(eye, target, up=(0, 1, 0)):
    f = target - eye; f /= np.linalg.norm(f)
    r = np.cross(f, up); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    m = np.eye(4)
    m[:3, 0], m[:3, 1], m[:3, 2], m[:3, 3] = r, u, -f, eye
    return m


def boat_meshes():
    hull = trimesh.creation.box(extents=[0.3, 0.25, 7.5]); hull.visual.face_colors = [235, 235, 230, 255]
    body = trimesh.creation.capsule(height=0.5, radius=0.18); body.visual.face_colors = [30, 60, 110, 255]
    head = trimesh.creation.icosphere(radius=0.12); head.visual.face_colors = [225, 190, 160, 255]
    oars = trimesh.creation.box(extents=[5.6, 0.04, 0.05]); oars.visual.face_colors = [60, 60, 60, 255]
    return [(hull, [0, 0.12, 0]), (body, [0, 0.65, 0]), (head, [0, 1.1, 0]), (oars, [0, 0.45, -0.3])]


def check_views(fwd_len, fwd):
    """(Name, Index, Blickrichtung relativ zur Fahrt in Grad, Kamerahöhe, Abstand hinter dem Boot)."""
    v = []
    for frac in (0.15, 0.5, 0.85):
        i = int(frac * (fwd_len / 2 - 12))
        v.append((f"links-{int(frac * 100)}", i, 90.0, 2.2, 0.0))
        v.append((f"rechts-{int(frac * 100)}", i, -90.0, 2.2, 0.0))
    v.append(("wende-oben", int(fwd_len / 2) - 80, 0.0, 60.0, 90.0))
    return v


def main(area_id, level, route_ids, checks=False):
    courses = Path("../../courses")
    scene, n, sun_dir = load_scene(courses / area_id / f"scene-{level}" / "scene.usdc")
    # Sonne wie im Bake (customLayerData der Szene), so soll sie auch die App stellen
    sun = pyrender.DirectionalLight(color=[1.0, 0.97, 0.9], intensity=3.2)
    scene.add(sun, pose=look_at(np.array([0.0, 0, 0]), sun_dir))
    r = pyrender.OffscreenRenderer(W, H)
    cam = pyrender.PerspectiveCamera(yfov=np.radians(55), znear=0.3, zfar=20000)
    cam_node = scene.add(cam)
    boat_nodes = [scene.add(pyrender.Mesh.from_trimesh(m, smooth=False)) for m, _ in boat_meshes()]
    offsets = [o for _, o in boat_meshes()]
    for rid in route_ids:
        c = json.loads((courses / rid / "course.json").read_text())
        p = np.array(c["path_xz"])
        fwd = np.vstack([p, p[::-1]])  # hin und zurück
        for k, frac in enumerate([0.02, 0.3, 0.6, 0.85]):
            i = int(frac * (len(fwd) - 12))
            pos = np.array([fwd[i][0], 0, fwd[i][1]])
            ahead = np.array([fwd[i + 10][0], 0, fwd[i + 10][1]])
            h = (ahead - pos) / np.linalg.norm(ahead - pos)
            yaw = np.arctan2(h[0], h[2])
            rot = trimesh.transformations.rotation_matrix(yaw, [0, 1, 0])
            for node, off in zip(boat_nodes, offsets):
                m = rot.copy(); m[:3, 3] = pos + rot[:3, :3] @ np.array(off)
                scene.set_pose(node, m)
            eye = pos - h * 4.5 + np.array([0, 2.2, 0])
            scene.set_pose(cam_node, look_at(eye, pos + h * 60 + np.array([0, 0.3, 0])))
            color, _ = r.render(scene)
            out = courses / rid / f"preview-{level}-{k + 1}.jpg"
            Image.fromarray(color).save(out, quality=88)
            print(out, flush=True)
        if checks:
            cdir = Path("build") / area_id / "checks"
            cdir.mkdir(parents=True, exist_ok=True)
            for name, i, ang, hgt, back in check_views(len(fwd), fwd):
                i = max(0, min(i, len(fwd) - 12))
                pos = np.array([fwd[i][0], 0, fwd[i][1]])
                ahead = np.array([fwd[i + 10][0], 0, fwd[i + 10][1]])
                h = (ahead - pos) / np.linalg.norm(ahead - pos)
                a = np.radians(ang)  # gegen den Uhrzeigersinn (von oben) = links
                rot_y = np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]])
                d = rot_y @ h
                if hgt > 10:
                    eye = pos - h * back + np.array([0, hgt, 0])
                    tgt = pos + h * 60
                else:
                    eye = pos + np.array([0, hgt, 0])
                    tgt = pos + d * 60 + np.array([0, 1.5, 0])
                scene.set_pose(cam_node, look_at(eye, tgt))
                color, _ = r.render(scene)
                out = cdir / f"{rid}-{level}-{name}.jpg"
                Image.fromarray(color).save(out, quality=85)
                print(out, flush=True)
    r.delete()
    print(f"{n} Meshes gerendert")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    main(args[0], args[1], args[2:], checks="--checks" in sys.argv)
