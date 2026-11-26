"""Vorschaubilder mit pyrender (Offscreen, Mesa llvmpipe auf der CPU) – über run_preview.sh starten.

- je Figurtyp: Figur in der Auslage im Boot (Kamera schräg vorne, also vom Heck her aufs Gesicht), 512 × 512, transparent
- je Bootsstil: Boot schräg von vorne (vom Bug her), Skulls flach auf dem Wasser, 512 × 512, transparent
- Übersichtstafeln docs/avatar/overview-figures.png und overview-boats.png (neutraler Hintergrund, mit Namen)

Aufruf: ./run_preview.sh [--only char-03,boat-wood-classic] [--no-sheets]
"""
from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path

import numpy as np

np.infty = np.inf  # pyrender 0.1.x nutzt noch np.infty
import pyrender  # noqa: E402
import trimesh
from PIL import Image, ImageDraw, ImageFont

import boat as B
import figure as F
import rig
from geom import normals, rot_y

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "App/RowCoach/Resources/appearance.json"
OUT = ROOT / "App/RowCoach/Resources/AvatarPreviews"
DOCS = ROOT / "docs/avatar"
SIZE = 512

FIXED = {"shorts": "#2B2C30", "socks": "#F2F2EE", "shoes": "#3A3C40", "eyes": "#1C1A1A", "fittings": "#2B2C30",
         "sleeve": "#E8E8E4", "bowball": "#F4F4F1", "flag": "#FFFFFF"}
ROUGH = {"skin": 0.65, "hair": 0.8, "shirt": 0.75, "shorts": 0.8, "socks": 0.8, "shoes": 0.7, "eyes": 0.3,
         "accessory": 0.35, "hull": 0.25, "deck": 0.3, "stripe": 0.3, "fin": 0.4, "bowball": 0.5, "fittings": 0.5,
         "rigger": 0.35, "shaft": 0.35, "blade": 0.3, "sleeve": 0.5, "flag": 0.6}


def hex_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def srgb_to_linear(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


class Catalog:
    def __init__(self, path=CATALOG):
        d = json.loads(Path(path).read_text())
        self.d = d
        self.skin = {x["id"]: x["rgb"] for x in d["skinTones"]}
        self.hair = {x["id"]: x["rgb"] for x in d["hairColors"]}
        self.shirt = {x["id"]: x["rgb"] for x in d["shirtColors"]}
        self.chars = d["characters"]
        self.boats = d["boatStyles"]

    def figure_colors(self, ch):
        shirt = self.shirt.get(ch["shirtColorId"], "#1A2F66")
        style = ch.get("shirtStyle")
        c = dict(FIXED)
        c.update(skin=self.skin.get(ch["skinToneId"], "#D7BD96"), hair=self.hair.get(ch["hairColorId"], "#3B2A20"),
                 shirt=shirt)
        if style == "unisuit":
            c["shorts"] = shirt
        return c


def accessory_color(prim, colors, ch):
    if "sunglasses" in prim:
        dark_skin = sum(hex_rgb(colors["skin"])) < 0.9
        return "#C9CCD1" if dark_skin else "#1E1F22"
    if "cap" in prim:
        return "#2B2C30"
    if "headband" in prim:
        return "#F2F2EE"
    return "#1E1F22"   # Uhr


def boat_colors(bs):
    c = dict(FIXED)
    c.update(hull=bs["hullColor"], deck=bs["deckColor"], stripe=bs.get("stripeColor") or bs["hullColor"],
             rigger=bs["riggerColor"], blade=bs["bladeColor"], shaft=bs["shaftColor"], fin=bs["riggerColor"])
    rough = {"gloss": 0.22, "matte": 0.7, "carbon": 0.35}.get(bs.get("finish"), 0.3)
    return c, rough


def assemble(fig_parts, boat_parts, ch, bs, pose, with_figure=True, with_boat=True, colors=None, flag=False):
    """Liste (Part im boat-Rahmen, Gruppe, Farbe, Rauheit)."""
    P = rig.Pose(ch, pose) if ch is not None else rig.Pose({}, pose)
    out = []
    crew = rig.CREW
    if with_figure:
        fc = colors or {}
        for prim, inst in rig.figure_prims(ch):
            seg, group, part = fig_parts[prim]
            M, t = P.T[inst]
            p = part.transformed(M, t).transformed(crew)
            col = accessory_color(prim, fc, ch) if group == "accessory" else fc.get(group, "#888888")
            out.append((p, group, col, ROUGH.get(group, 0.6)))
    if with_boat:
        bc, hull_rough = boat_colors(bs)
        for prim, inst in rig.boat_prims(bs, flag=flag):
            frame, group, part = boat_parts[prim]
            if inst == "boat":
                p = part
            elif inst == "crew":
                p = part.transformed(crew)
            elif inst == "seat":
                M, t = P.T["seat"]
                p = part.transformed(M, t).transformed(crew)
            else:
                s, q, pin = P.oars[0 if inst.endswith("R") else 1]
                p = part.transformed(q, pin).transformed(crew)
            r = hull_rough if group in ("hull", "deck", "stripe") else ROUGH.get(group, 0.5)
            out.append((p, group, bc.get(group, "#888888"), r))
    return out


def to_scene(items, bg):
    scene = pyrender.Scene(bg_color=bg, ambient_light=[0.10, 0.11, 0.12])
    for p, group, col, rough in items:
        nrm = normals(p)
        tm = trimesh.Trimesh(vertices=p.v, faces=p.f, vertex_normals=nrm, process=False)
        rgb = hex_rgb(col)
        mat = pyrender.MetallicRoughnessMaterial(baseColorFactor=[*srgb_to_linear(rgb), 1.0], metallicFactor=0.0,
                                                 roughnessFactor=float(rough), doubleSided=False)
        scene.add(pyrender.Mesh.from_trimesh(tm, material=mat, smooth=True))
    return scene


def look_at(eye, target, up=(0, 1, 0)):
    eye, target, up = map(lambda a: np.asarray(a, dtype=float), (eye, target, up))
    f = target - eye
    f /= np.linalg.norm(f)
    r = np.cross(f, up)
    r /= np.linalg.norm(r)
    u = np.cross(r, f)
    m = np.eye(4)
    m[:3, 0], m[:3, 1], m[:3, 2], m[:3, 3] = r, u, -f, eye
    return m


def add_lights(scene, key_from):
    key = pyrender.DirectionalLight(color=[1.0, 0.97, 0.92], intensity=2.4)
    scene.add(key, pose=look_at(key_from, [0, 0, 0]))
    fill = pyrender.DirectionalLight(color=[0.80, 0.86, 1.0], intensity=0.7)
    kf = np.asarray(key_from, dtype=float)
    scene.add(fill, pose=look_at([-kf[0], kf[1] * 0.4, -kf[2] * 0.6 + 1], [0, 0, 0]))
    rim = pyrender.DirectionalLight(color=[1.0, 1.0, 1.0], intensity=0.6)
    scene.add(rim, pose=look_at([0, 2, -4], [0, 0, 0]))


def tonemap(img_rgba):
    """pyrender liefert schon gammakorrigiert (1/2,2); hier nur RGBA zusammensetzen."""
    a = img_rgba[..., 3:4].astype(float) / 255
    c = img_rgba[..., :3].astype(float) / 255
    c = np.clip(c, 0, 1)
    out = np.concatenate([np.clip(c, 0, 1) * 255, a * 255], axis=-1)
    return out.astype(np.uint8)


def render(renderer, items, cam_pose, yfov, key_from, bg=(0, 0, 0, 0)):
    scene = to_scene(items, bg)
    cam = pyrender.PerspectiveCamera(yfov=yfov, znear=0.05, zfar=60)
    scene.add(cam, pose=cam_pose)
    add_lights(scene, key_from)
    color, _ = renderer.render(scene, flags=pyrender.RenderFlags.RGBA | pyrender.RenderFlags.SHADOWS_DIRECTIONAL)
    return tonemap(color)


def supersample(renderer, items, cam_pose, yfov, key_from):
    img = render(renderer, items, cam_pose, yfov, key_from)
    return Image.fromarray(img, "RGBA").resize((SIZE, SIZE), Image.LANCZOS)


def figure_view(renderer, cat, fig_parts, boat_parts, ch, bs):
    pose = rig.stroke_pose(0.0)  # Auslage
    items = assemble(fig_parts, boat_parts, ch, bs, pose, colors=cat.figure_colors(ch))
    # Kamera: vom Heck (+z) schräg rechts, auf Brusthöhe der vorgebeugten Figur
    target = np.array([0.0, 0.62, 0.02])
    eye = target + np.array([1.55, 0.62, 1.50])
    return supersample(renderer, items, look_at(eye, target), math.radians(28), [2.0, 4.0, 3.0])


def boat_view(renderer, cat, fig_parts, boat_parts, bs):
    pose = dict(sweep=8, blade=0.75, feather=1, slide=0.5, lean=0)
    items = assemble(fig_parts, boat_parts, None, bs, pose, with_figure=False, flag=False)
    target = np.array([0.0, 0.0, -0.9])
    eye = np.array([4.4, 6.4, -6.0])
    return supersample(renderer, items, look_at(eye, target), math.radians(45), [3.0, 5.0, -2.0])


def sheet(images, labels, cols, path, title):
    cell = 300
    pad = 16
    rows = math.ceil(len(images) / cols)
    W = cols * cell + (cols + 1) * pad
    H = rows * (cell + 34) + (rows + 1) * pad + 56
    board = Image.new("RGB", (W, H), (236, 238, 240))
    d = ImageDraw.Draw(board)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 17)
        tfont = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 24)
    except OSError:
        font = tfont = ImageFont.load_default()
    d.text((pad, 16), title, fill=(30, 32, 36), font=tfont)
    for i, (im, lab) in enumerate(zip(images, labels)):
        r, c = divmod(i, cols)
        x = pad + c * (cell + pad)
        y = 56 + pad + r * (cell + 34 + pad)
        bgc = Image.new("RGB", (cell, cell), (250, 251, 252))
        bgc.paste(im.resize((cell, cell), Image.LANCZOS), (0, 0), im.resize((cell, cell), Image.LANCZOS))
        board.paste(bgc, (x, y))
        while d.textlength(lab, font=font) > cell - 6 and len(lab) > 4:
            lab = lab[:-2] + "…" if not lab.endswith("…") else lab[:-2] + "…"
        d.text((x + 4, y + cell + 6), lab, fill=(40, 42, 48), font=font)
    board.save(path, optimize=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--no-sheets", action="store_true")
    ap.add_argument("--out", default=str(OUT))
    args = ap.parse_args()
    only = set(filter(None, args.only.split(",")))
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    cat = Catalog()
    fig_parts = F.build_parts()
    boat_parts = B.build_parts()
    r = pyrender.OffscreenRenderer(SIZE * 2, SIZE * 2)
    figs, flabels, boats, blabels = [], [], [], []
    default_boat = cat.boats[0]
    for ch in cat.chars:
        if only and ch["id"] not in only:
            continue
        im = figure_view(r, cat, fig_parts, boat_parts, ch, default_boat)
        im.save(out / f"{ch['id']}.png", optimize=True)
        figs.append(im)
        flabels.append(f"{ch['id']} · {ch['name']['de']}")
        print("Figur", ch["id"], flush=True)
    for bs in cat.boats:
        if only and bs["id"] not in only:
            continue
        im = boat_view(r, cat, fig_parts, boat_parts, bs)
        im.save(out / f"{bs['id']}.png", optimize=True)
        boats.append(im)
        blabels.append(f"{bs['name']['de']}")
        print("Boot", bs["id"], flush=True)
    r.delete()
    if not args.no_sheets and not only:
        sheet(figs, flabels, 5, DOCS / "overview-figures.png", "RowCoach – 10 Figurtypen (Auslage, Blick vom Heck)")
        sheet(boats, blabels, 4, DOCS / "overview-boats.png", "RowCoach – Bootsstile (schräg von vorne)")
        print("Tafeln", DOCS / "overview-figures.png", DOCS / "overview-boats.png")


if __name__ == "__main__":
    main()
