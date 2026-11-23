"""Schritt 5: Vorschaubilder aus der Bootsperspektive (Kamera leicht erhöht hinter dem Ruderer).

Rendert auf der CPU (Mesa llvmpipe), braucht also keine GPU. Liest die Szene direkt aus scene.usdc;
die Sonnenrichtung kommt aus customLayerData (rowcoach:sunDirection), wie sie bake.py eingerechnet hat.
Ergebnis: ../../courses/<route>/preview-<stufe>-<n>.jpg

Aufruf (Umgebungsvariablen setzt run_preview.sh):
  .venv/bin/python preview.py <area-id> <stufe> <route-id> [<route-id> ...] [--checks]

Mit --checks zusätzlich Kontrollbilder (nicht für die App) nach build/<area>/checks/: Blick quer zur Fahrt nach
links und rechts (Ufer, Promenade, Löcher, schwebende oder versunkene Teile) an drei Stellen der Hinfahrt, und eine
Schrägansicht von oben auf die Wende.

Mit --at d1,d2,… (Meter Ruderdistanz ab Start, Rückfahrt 12 m links wie in der App) Bilder an frei gewählten Stellen,
mit --bridges an jeder Durchfahrt unter einer Brücke (je 60 m und 20 m davor und direkt darunter, Hin- und
Rückfahrt; Achsen aus build/<area>/bridges/meta.json). Beides nach build/<area>/checks/<strecke>-<stufe>-at<d>.jpg.

Mit --time morgen,mittag,abend[,nachmittag] Bilder zu Tageszeiten (Sonnenstand am Ort nach sun.py, Himmel mit
Wolken, Sonnenfarbe und Dunst nach sky.py wie in der App) nach build/<area>/checks/<strecke>-<stufe>-<zeit>-<n>.jpg;
nicht ins App-Bundle. Mit --light ambient nutzen alle Zeiten ausser "nachmittag" (= Bake-Sonne 235°/48°) die
Gebäudetexturen ohne Sonnenschatten aus ../../courses/<area>/light-ambient-<stufe>/ (export.py --light ambient),
wie die App. --year (Standard 2026) wählt das Jahr der Sommersonnenwende.
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

import sky
import sun

W, H = 1600, 1000
LINEAR = pyrender.Sampler(magFilter=GL_LINEAR, minFilter=GL_LINEAR_MIPMAP_LINEAR, wrapS=GL_CLAMP_TO_EDGE,
                          wrapT=GL_CLAMP_TO_EDGE)
SKY = np.array([0.62, 0.76, 0.92])


def load_scene(usdc: Path, tex_override: Path = None, bg_alpha=1.0, ambient=(0.35, 0.35, 0.38),
               water_color=(38, 74, 96)):
    """tex_override: Ordner mit Ersatz-Texturen gleichen Namens (Licht-Variante), sonst die Texturen der Szene."""
    stage = Usd.Stage.Open(str(usdc))
    scene = pyrender.Scene(bg_color=[*SKY, bg_alpha], ambient_light=list(ambient))
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
            src = usdc.parent / f
            if tex_override is not None and (tex_override / Path(f).name).exists():
                src = tex_override / Path(f).name
                f = str(src)
            img = tex_cache.get(f) or Image.open(src).convert("RGB")
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
    water.visual.face_colors = [*[int(c) for c in water_color], 255]
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


def pose_at(p, d, back_off=12.0):
    """Position und Fahrtrichtung (x, z) bei Ruderdistanz d; Rückfahrt 12 m links (vereinfachte Wende)."""
    seg = np.linalg.norm(np.diff(p, axis=0), axis=1)
    cum = np.r_[0, np.cumsum(seg)]
    L = cum[-1]
    ret = d > L
    s = 2 * L - d if ret else d
    s = float(np.clip(s, 0, L - 1e-6))
    i = int(np.clip(np.searchsorted(cum, s, side="right") - 1, 0, len(seg) - 1))
    f = (s - cum[i]) / max(seg[i], 1e-9)
    pos = p[i] + (p[i + 1] - p[i]) * f
    t = (p[i + 1] - p[i]) / max(seg[i], 1e-9)
    if ret:
        # links der Hinfahrt in Szenenkoordinaten (x = Ost, z = −Nord): (t.z, −t.x)
        pos = pos + np.array([t[1], -t[0]]) * back_off
        t = -t
    return pos, t, L


def bridge_crossings(area_id, p):
    """Ruderdistanzen, an denen Hin- oder Rückfahrt eine Brückenachse kreuzt."""
    meta = Path("build") / area_id / "bridges" / "meta.json"
    if not meta.exists():
        return []
    from shapely.geometry import LineString
    seg = np.linalg.norm(np.diff(p, axis=0), axis=1)
    L = float(seg.sum())
    out = LineString(p)
    t = np.diff(p, axis=0); t = np.vstack([t, t[-1:]]); t /= np.linalg.norm(t, axis=1, keepdims=True)
    back = LineString(p + np.column_stack([t[:, 1], -t[:, 0]]) * 12.0)
    res = []
    for b in json.loads(meta.read_text())["bridges"]:
        ax = LineString(b["axis_xz"])
        for line, ret in ((out, False), (back, True)):
            x = line.intersection(ax)
            for pt in getattr(x, "geoms", [x]) if not x.is_empty else []:
                d = line.project(pt)
                res.append((b["mesh"], 2 * L - d if ret else d, ret))
    return res


def render_at(scene, r, cam_node, boat_nodes, offsets, p, d):
    pos2, h2, _ = pose_at(p, d)
    pos = np.array([pos2[0], 0, pos2[1]])
    h = np.array([h2[0], 0, h2[1]])
    yaw = np.arctan2(h[0], h[2])
    rot = trimesh.transformations.rotation_matrix(yaw, [0, 1, 0])
    for node, off in zip(boat_nodes, offsets):
        m = rot.copy(); m[:3, 3] = pos + rot[:3, :3] @ np.array(off)
        scene.set_pose(node, m)
    eye = pos - h * 4.5 + np.array([0, 2.2, 0])
    scene.set_pose(cam_node, look_at(eye, pos + h * 60 + np.array([0, 0.3, 0])))
    color, _ = r.render(scene)
    return color


def camera_rays(pose, yfov=np.radians(55)):
    """Blickrichtung je Pixel (H×W×3, Welt) und Länge des Kamerastrahls je Einheit Tiefe (H×W)."""
    ty = np.tan(yfov / 2)
    xs = ((np.arange(W) + 0.5) / W * 2 - 1) * ty * W / H
    ys = (1 - (np.arange(H) + 0.5) / H * 2) * ty
    X, Y = np.meshgrid(xs, ys)
    d = np.stack([X, Y, -np.ones_like(X)], -1)
    norm = np.linalg.norm(d, axis=-1)
    d = d / norm[..., None]
    return d @ pose[:3, :3].T, norm


def haze_alpha(d, eye_y, env, dist):
    """Deckkraft der Dunstringe (App: 6 Bänder bei 4 km, bis hazeHeight) für Strahlen, die weiter als 4 km reichen."""
    horiz = np.maximum(np.linalg.norm(d[..., [0, 2]], axis=-1), 1e-6)
    y = eye_y + 4000.0 * d[..., 1] / horiz
    hh, bands = 550.0, 6
    a = np.zeros(y.shape)
    for b in range(bands):
        y0 = -40.0 if b == 0 else hh * (b / bands) ** 1.6
        y1 = hh * ((b + 1) / bands) ** 1.6
        op = env["haze_opacity"] * (1 - b / bands) ** 1.5
        a = np.where((y >= y0) & (y < y1), op, a)
    return a * (dist > 4000.0) * (d[..., 1] > -0.5)


def render_time(scene, r, cam_node, env, eye_y=2.2):
    """Rendern mit Himmel hinter der Szene und Dunst wie in der App."""
    color, depth = r.render(scene, flags=pyrender.RenderFlags.RGBA)
    pose = scene.get_pose(cam_node)
    d, norm = camera_rays(pose)
    col = color[..., :3].astype(np.float32) / 255.0
    bg = color[..., 3] == 0
    dist = np.where(depth > 0, depth * norm, 1e9)
    skyc = sky.sky_color(d.reshape(-1, 3), env).reshape(H, W, 3)
    col = np.where(bg[..., None], skyc, col)
    a = haze_alpha(d, pose[1, 3], env, dist)
    az = np.degrees(np.arctan2(d[..., 0], -d[..., 2])) % 360
    col = col * (1 - a[..., None]) + sky.haze_color(az, env) * a[..., None]
    return (np.clip(col, 0, 1) * 255 + 0.5).astype(np.uint8)


def main_times(area_id, level, route_ids, times, light="sun", year=2026):
    courses = Path("../../courses")
    c0 = json.loads((courses / route_ids[0] / "course.json").read_text())
    lat, lon = sun.lv95_to_wgs84(*c0["origin_lv95"])
    usdc = courses / area_id / f"scene-{level}" / "scene.usdc"
    variant = courses / area_id / f"light-{light}-{level}" if light != "sun" else None
    if variant is not None and not variant.is_dir():
        sys.exit(f"Fehlt: {variant} – export.py areas/{area_id}.json {level} --light {light}")
    cdir = Path("build") / area_id / "checks"
    cdir.mkdir(parents=True, exist_ok=True)
    r = pyrender.OffscreenRenderer(W, H)
    for t in times:
        az, el = sun.preset_position(t, lat, lon, year)
        el = max(el, sun.MIN_SCENE_ELEVATION)
        env = sky.env_for_sun(az, el)
        h = env["h"]
        amb = np.array([0.35, 0.35, 0.38]) * (0.55 + 0.45 * h) * sky.mix([1.0, 0.85, 0.80], [1, 1, 1], h)
        wc = sky.mix([38, 74, 96], np.asarray(env["horizon"]) * 255 * 0.55, 0.25)
        over = variant if (variant is not None and t != "nachmittag") else None
        scene, n, _ = load_scene(usdc, tex_override=over, bg_alpha=0.0, ambient=amb, water_color=wc)
        light_dir = -sky.to_sun(env)
        sl = pyrender.DirectionalLight(color=list(env["sun_color"]), intensity=3.2 * env["sun_intensity"] / 3000)
        scene.add(sl, pose=look_at(np.array([0.0, 0, 0]), light_dir))
        cam_node = scene.add(pyrender.PerspectiveCamera(yfov=np.radians(55), znear=0.3, zfar=20000))
        boat_nodes = [scene.add(pyrender.Mesh.from_trimesh(m, smooth=False)) for m, _ in boat_meshes()]
        offsets = [o for _, o in boat_meshes()]
        tag = t + ("-" + light if over is not None else "")
        print(f"{t}: Sonne {az:.1f}°/{el:.1f}° (Breite {lat:.4f}, Länge {lon:.4f}), Gebäude "
              f"{'ohne Sonnenschatten' if over is not None else 'Bake 235°/48°'}", flush=True)
        for rid in route_ids:
            c = json.loads((courses / rid / "course.json").read_text())
            p = np.array(c["path_xz"])
            fwd = np.vstack([p, p[::-1]])
            for k, frac in enumerate([0.02, 0.3, 0.6, 0.85]):
                i = int(frac * (len(fwd) - 12))
                pos = np.array([fwd[i][0], 0, fwd[i][1]])
                ahead = np.array([fwd[i + 10][0], 0, fwd[i + 10][1]])
                hd = (ahead - pos) / np.linalg.norm(ahead - pos)
                rot = trimesh.transformations.rotation_matrix(np.arctan2(hd[0], hd[2]), [0, 1, 0])
                for node, off in zip(boat_nodes, offsets):
                    m = rot.copy(); m[:3, 3] = pos + rot[:3, :3] @ np.array(off)
                    scene.set_pose(node, m)
                eye = pos - hd * 4.5 + np.array([0, 2.2, 0])
                scene.set_pose(cam_node, look_at(eye, pos + hd * 60 + np.array([0, 0.3, 0])))
                out = cdir / f"{rid}-{level}-{tag}-{k + 1}.jpg"
                Image.fromarray(render_time(scene, r, cam_node, env)).save(out, quality=88)
                print(out, flush=True)
    r.delete()


def main(area_id, level, route_ids, checks=False, at=(), bridges=False):
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
        if at or bridges:
            cdir = Path("build") / area_id / "checks"
            cdir.mkdir(parents=True, exist_ok=True)
            todo = [(f"at{int(d)}", d) for d in at]
            if bridges:
                for mesh, d, ret in bridge_crossings(area_id, p):
                    for back in (60, 20, -2):
                        dd = d - back
                        todo.append((f"{mesh}-{'rueck' if ret else 'hin'}-{'unter' if back < 0 else f'{back}m'}", dd))
            for name, d in todo:
                color = render_at(scene, r, cam_node, boat_nodes, offsets, p, d)
                out = cdir / f"{rid}-{level}-{name}.jpg"
                Image.fromarray(color).save(out, quality=88)
                print(out, f"(d = {d:.0f} m)", flush=True)
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
    argv = sys.argv[1:]
    at = []
    if "--at" in argv:
        i = argv.index("--at")
        at = [float(x) for x in argv[i + 1].split(",")]
        del argv[i:i + 2]
    opts = {}
    for key in ("--time", "--light", "--year"):
        if key in argv:
            i = argv.index(key)
            opts[key] = argv[i + 1]
            del argv[i:i + 2]
    args = [a for a in argv if not a.startswith("--")]
    if "--time" in opts:
        main_times(args[0], args[1], args[2:], opts["--time"].split(","), opts.get("--light", "sun"),
                   int(opts.get("--year", 2026)))
    else:
        main(args[0], args[1], args[2:], checks="--checks" in argv, at=at, bridges="--bridges" in argv)
