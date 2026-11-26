"""Detailstufe `lite` (Massenrennen, 12–20 Boote in mittlerer Entfernung): ≤ 600 Dreiecke je Boot, ein Material.

Farben über eine kleine Palettentextur (16 × 1 Pixel, je Erscheinung in der App erzeugt): jedes Teil hat konstante
Texturkoordinaten (u = (Slot + 0,5) / 16, v = 0,5). Slots siehe PALETTE (muss zu `AvatarPalette` in der App passen).

Teile:
- `lite_hull`  boat-Rahmen: Rumpf, Deck, Streifen, beide Ausleger (≈ 200 Dreiecke)
- `lite_rower` crew-Rahmen, starre Figur in mittlerer Durchzugsstellung (Ursprung wie crew; die App verschiebt sie
               leicht mit dem Rollsitz) (≈ 250)
- `lite_oar_R` / `lite_oar_L` oar-Rahmen: Schaft und Blatt (je ≈ 24)
"""
from __future__ import annotations

import math

import numpy as np

import boat as B
import figure as F
import rig
from geom import Part, capsule_y, ellipsoid, grid, merge, tube_path, basis_y, rot_y

PALETTE = ["hull", "deck", "stripe", "rigger", "blade", "shaft", "skin", "shirt", "hair", "shorts", "fittings",
           "shoes"]
SLOTS = 16


def paint(p: Part, slot_name):
    i = PALETTE.index(slot_name)
    p = p.copy()
    p.uv = np.tile([(i + 0.5) / SLOTS, 0.5], (len(p.v), 1))
    return p


def lite_hull():
    zs = np.array([B.BOW_Z, -3.9, -3.0, -2.0, -1.0, -0.3, 0.4, 1.2, 2.0, 2.8, 3.3, B.STERN_Z])
    levels = [0.0, 0.04, 0.45, 1.0]
    rings_body, rings_stripe = [], []
    for z in zs:
        hw, ys, hk, n = B.section(z)
        H = ys + hk
        side = []
        for i, lv in enumerate(levels):
            y = ys - (lv if i == 1 else lv * H)
            side.append((B.hull_x(hw, ys, hk, n, y), y))
        right = [(x, y, z) for x, y in side]
        left = [(-x, y, z) for x, y in side[::-1][1:]]
        rings_body.append(right + left)
    P = np.array(rings_body)
    hull = grid(P, wrap=False)
    c = hull.v[hull.f].mean(axis=1)
    fn = np.cross(hull.v[hull.f[:, 1]] - hull.v[hull.f[:, 0]], hull.v[hull.f[:, 2]] - hull.v[hull.f[:, 0]])
    if np.einsum("ij,ij->i", fn, c * [1, 0, 0] + [0, -1, 0] * (c[:, 1:2] < 0.05)).sum() < 0:
        hull = hull.flipped()
    # oberstes Band (Level 0–1) als Streifen
    K = P.shape[1]
    cols = np.tile(np.repeat(np.arange(K - 1), 2), len(zs) - 1)
    from geom import subset
    stripe = subset(hull, np.isin(cols, [0, K - 2]))
    body = subset(hull, ~np.isin(cols, [0, K - 2]))
    deck_rows = []
    for z in zs:
        hw, ys = B.section(z)[:2]
        deck_rows.append([(-hw, ys, z), (0, ys + 0.012, z), (hw, ys, z)])
    deck = grid(np.array(deck_rows), wrap=False)
    fn = np.cross(deck.v[deck.f[:, 1]] - deck.v[deck.f[:, 0]], deck.v[deck.f[:, 2]] - deck.v[deck.f[:, 0]])
    if fn[:, 1].sum() < 0:
        deck = deck.flipped()
    riggers = []
    for s in (1, -1):
        # crew → boat: x und z spiegeln
        a = np.array([-s * 0.14, 0.13, 0.10])
        b = np.array([-s * B.PIN_X, B.PIN_Y - 0.03, -B.PIN_Z])
        riggers.append(tube_path(np.array([a, b]), 0.018, k=4))
    return merge([paint(body, "hull"), paint(stripe, "stripe"), paint(deck, "deck")] +
                 [paint(r, "rigger") for r in riggers])


def lite_rower():
    ch = {"heightScale": 1.0, "shoulderScale": 1.0, "build": "athletic"}
    pose = dict(sweep=10, blade=1, feather=0, slide=0.5, lean=5)
    P = rig.Pose(ch, pose)
    parts = []
    M, t = P.T["pelvis"]
    torso = capsule_y(0.40, 0.13, 0.15, k=6, rings_body=2, rings_cap=1).transformed(np.diag([1.0, 1, 0.68]),
                                                                                    (0, 0.06, 0))
    parts.append(paint(torso.transformed(M, t), "shirt"))
    hips = ellipsoid((0, 0, 0.015), (0.14, 0.09, 0.11), ku=5, kv=3)
    parts.append(paint(hips.transformed(M, t), "shorts"))
    M, t = P.T["head"]
    head = ellipsoid(F.HEAD_C, F.HEAD_R, ku=7, kv=5)
    hair = ellipsoid(F.HEAD_C + [0, 0.02, 0.012], F.HEAD_R * 1.04, ku=7, kv=4)
    keep = hair.v[hair.f].mean(axis=1)[:, 1] > F.HEAD_C[1] + 0.005
    from geom import subset
    hair = subset(hair, keep)
    parts += [paint(head.transformed(M, t), "skin"), paint(hair.transformed(M, t), "hair")]
    for side in ("R", "L"):
        for seg, length, r0, r1, slot in (("upperarm", F.UPPER_ARM, 0.045, 0.036, "skin"),
                                           ("forearm", F.FOREARM, 0.036, 0.034, "skin"),
                                           ("thigh", F.THIGH, 0.070, 0.050, "skin"),
                                           ("shin", F.SHIN, 0.048, 0.034, "skin")):
            M, t = P.T[f"{seg}_{side}"]
            limb = capsule_y(length, r0, r1, k=5, rings_body=1, rings_cap=1)
            parts.append(paint(limb.transformed(M, t), slot))
        M, t = P.T[f"foot_{side}"]
        parts.append(paint(ellipsoid((0, -0.01, -0.07), (0.045, 0.04, 0.12), ku=4, kv=3).transformed(M, t), "shoes"))
    return merge(parts)


def lite_oar(side):
    shaft = tube_path(np.array([[-B.INBOARD, 0, 0], [B.BLADE_NECK_X + 0.05, 0, 0]]), 0.02, k=4, up=(0, 0, 1))
    L, top, bot = B.blade_outline("bigblade")
    x0, x1 = B.BLADE_NECK_X, B.BLADE_NECK_X + L
    yt, yb = 0.07, -0.11
    s = 1 if side > 0 else -1
    v = np.array([[x0, yt * 0.3, 0], [x1, yt, 0.01 * s], [x1, yb, 0.01 * s], [x0, yb * 0.3, 0]])
    blade = Part(np.vstack([v + [0, 0, 0.004], v - [0, 0, 0.004]]),
                 [[0, 1, 2], [0, 2, 3], [4, 6, 5], [4, 7, 6], [0, 4, 5], [0, 5, 1], [1, 5, 6], [1, 6, 2], [2, 6, 7],
                  [2, 7, 3], [3, 7, 4], [3, 4, 0]]).outward()
    return merge([paint(shaft, "shaft"), paint(blade, "blade")])


def build_parts():
    return {"lite_hull": ("boat", "palette", lite_hull()),
            "lite_rower": ("crew", "palette", lite_rower()),
            "lite_oar_R": ("oar", "palette", lite_oar(1)),
            "lite_oar_L": ("oar", "palette", lite_oar(-1))}
