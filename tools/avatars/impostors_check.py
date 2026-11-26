"""Kontrollbild der Renn-Silhouetten (RaceImpostors.swift, gleiche Masse und Farben): mehrere Silhouetten in
100–800 m vor Wasser und Dunst, aus der Kamera der App (2,2 m hoch, fast waagrecht, 55° vertikal) und vergrössert.

Aufruf (CPU): EGL-Variablen wie run_preview.sh, dann ../coursebuilder/.venv/bin/python impostors_check.py
Ergebnis: docs/avatar/check-impostors.png
"""
from __future__ import annotations

import math
import os
from pathlib import Path

os.environ.setdefault("PYOPENGL_PLATFORM", "egl")
import numpy as np

np.infty = np.inf
import pyrender  # noqa: E402
import trimesh  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/avatar/check-impostors.png"

# wie RaceImpostors.swift
BAND_LIMITS = [250, 500]
BAND_HAZE_MIX = [0.15, 0.42, 0.65]
BAND_OPACITY = [0.78, 0.62, 0.48]
BASE = np.array([0.26, 0.31, 0.38])
HAZE = np.array([0.74, 0.80, 0.87])
BODY = [(-0.22, 0.10), (0.22, 0.10), (0.19, 0.45), (0.07, 0.68), (-0.07, 0.68), (-0.19, 0.45)]
OAR_IN, OAR_OUT = (0.34, 0.22, 0.27), (1.30, 0.10, 0.14)
HULL_HALF, HULL_TOP, HULL_END = 4.0, 0.16, 0.05
WATER = np.array([0.30, 0.42, 0.50])


def silhouette(x, z, heading=0.0):
    r = np.array([math.cos(heading), 0, -math.sin(heading)])
    f = np.array([-math.sin(heading), 0, -math.cos(heading)])
    p = np.array([x, 0.0, z])
    at = lambda a, y: p + r * a + np.array([0, y, 0])  # noqa: E731
    v = [at(a, y) for a, y in BODY]
    for s in (1, -1):
        v += [at(s * OAR_IN[0], OAR_IN[1]), at(s * OAR_OUT[0], OAR_OUT[1]), at(s * OAR_OUT[0], OAR_OUT[2]),
              at(s * OAR_IN[0], OAR_IN[2])]
    v += [p - f * HULL_HALF + [0, HULL_END, 0], p + [0, HULL_TOP, 0], p + f * HULL_HALF + [0, HULL_END, 0], p]
    tris = [(0, 1, 2), (0, 2, 3), (0, 3, 4), (0, 4, 5), (6, 7, 8), (6, 8, 9), (10, 11, 12), (10, 12, 13),
            (14, 15, 16), (14, 16, 17)]
    faces = []
    for a, b, c in tris:
        faces += [(a, b, c), (a, c, b)]
    return np.array(v), np.array(faces)


def scene_for(boats, eye):
    scene = pyrender.Scene(bg_color=[*HAZE, 1.0], ambient_light=[0, 0, 0])
    water = trimesh.Trimesh(vertices=[[-3000, 0, -3000], [3000, 0, -3000], [3000, 0, 3000], [-3000, 0, 3000]],
                            faces=[[0, 2, 1], [0, 3, 2]], process=False)
    # unbeleuchtet wie UnlitMaterial: Farbe als Eigenleuchten (pyrender gibt sRGB aus → linear übergeben)
    lin = lambda c: np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)  # noqa: E731
    scene.add(pyrender.Mesh.from_trimesh(water, material=pyrender.MetallicRoughnessMaterial(
        baseColorFactor=[0, 0, 0, 1.0], emissiveFactor=list(WATER ** 1.15)), smooth=False))
    groups = {0: [], 1: [], 2: []}
    for x, z in boats:
        d = math.hypot(x - eye[0], z - eye[2])
        b = 0 if d < BAND_LIMITS[0] else (1 if d < BAND_LIMITS[1] else 2)
        groups[b].append(silhouette(x, z))
    for b, items in groups.items():
        if not items:
            continue
        vs, fs, off = [], [], 0
        for v, f in items:
            vs.append(v)
            fs.append(f + off)
            off += len(v)
        tm = trimesh.Trimesh(vertices=np.vstack(vs), faces=np.vstack(fs), process=False)
        col = BASE + (HAZE - BASE) * BAND_HAZE_MIX[b]
        mat = pyrender.MetallicRoughnessMaterial(baseColorFactor=[0, 0, 0, BAND_OPACITY[b]], alphaMode="BLEND",
                                                 doubleSided=True, emissiveFactor=list(col ** 1.15))
        scene.add(pyrender.Mesh.from_trimesh(tm, material=mat, smooth=False))
    return scene


def look(eye, target):
    eye, target = np.array(eye, float), np.array(target, float)
    fwd = target - eye
    fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, [0, 1, 0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    m = np.eye(4)
    m[:3, 0], m[:3, 1], m[:3, 2], m[:3, 3] = right, up, -fwd, eye
    return m


def main():
    eye = np.array([0.0, 2.2, 4.5])
    rng = np.random.default_rng(4)
    boats = []
    for d in (100, 160, 230, 300, 380, 470, 560, 650, 740, 800):
        for k in range(rng.integers(1, 4)):
            lane = int(rng.integers(1, 5))
            boats.append((7.0 * lane - 14.0 + rng.normal(0, 0.6), -d - rng.uniform(0, 25)))
    r = pyrender.OffscreenRenderer(1280, 720)
    pitch = -math.atan2(1.9, 64.5)
    target = eye + np.array([0, math.sin(pitch), -math.cos(pitch)])
    panels = []
    for fov, label in ((55, "Kamera der App (55°)"), (12, "vergrössert (12°)")):
        scene = scene_for(boats, eye)
        scene.add(pyrender.PerspectiveCamera(yfov=math.radians(fov), aspectRatio=16 / 9), pose=look(eye, target))
        color, _ = r.render(scene)
        im = Image.fromarray(color)
        d = ImageDraw.Draw(im)
        try:
            font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
        except OSError:
            font = ImageFont.load_default()
        d.text((14, 12), f"Silhouetten 100–800 m · {label}", fill=(20, 24, 30), font=font)
        panels.append(im)
    r.delete()
    board = Image.new("RGB", (1280, 1440))
    board.paste(panels[0], (0, 0))
    board.paste(panels[1], (0, 720))
    board.save(OUT, optimize=True)
    print(OUT)


if __name__ == "__main__":
    main()
