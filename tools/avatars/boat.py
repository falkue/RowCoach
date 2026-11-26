"""Skiff (Einer) als Teile: Rumpf als Spanten-Loft, Deck mit offenem Cockpit, Zierstreifen, Finne, Bugball, Flaggen,
Rollsitz, Schienen, Stemmbrett, drei Ausleger-Arten und Skulls mit drei Blattformen.

Rahmen (wie BoatRig):
- `boat`  Ursprung Wasserlinie unter dem Ausleger, Bug = −z, x = rechts, y = oben (Rumpf, Deck, Finne, Bugball, Flaggen).
- `crew`  derselbe Ursprung, um 180° um y gedreht (Figur schaut nach −z = zum Heck): Sitz, Schienen, Stemmbrett,
          Ausleger, Dollen. Der Sitz wird in der App entlang z verschoben (Ursprung = Sitzmitte).
- `oar`   Ursprung Dolle, +x entlang des Schafts nach aussen, Griff bei −INBOARD, Blatt aussen; ein Skull je Seite,
          das linke mit gespiegelter Wölbung (die hohle Seite zeigt immer zum Heck).
"""
from __future__ import annotations

import numpy as np

from figure import FOOT_HALF, FOOT_Y, FOOT_Z, STRETCHER_ANGLE
from geom import Part, ellipsoid, grid, merge, superellipse_ring, thicken, tube_path

BOW_Z = -4.55
STERN_Z = 3.65
BEAM_Z = -0.45              # Lage der grössten Breite
HALF_BEAM = 0.150
SHEER_Y = 0.115
KEEL_D = 0.075
COCKPIT = (-0.95, 0.70)     # Cockpit in Bootskoordinaten (z)

PIN_X, PIN_Y, PIN_Z = 0.80, 0.36, -0.05      # crew
INBOARD, OUTBOARD = 0.88, 2.0


def tau(z):
    half = (BEAM_Z - BOW_Z) if z < BEAM_Z else (STERN_Z - BEAM_Z)
    return (z - BEAM_Z) / half


def section(z):
    t = abs(tau(z))
    t = min(t, 0.999)
    hw = HALF_BEAM * (1 - t ** 2.0) ** 0.62 + 0.002
    ys = SHEER_Y + (0.022 * t ** 2 if z < BEAM_Z else 0.008 * t ** 2)
    hk = KEEL_D * (1 - t ** 2.2) ** 0.5 + 0.004
    n = 1.5 + 0.9 * (1 - t ** 2)
    return hw, ys, hk, n


LEVELS = [0.0, 0.030, 0.050, 0.40, 0.68, 0.88, 1.0]   # Anteil von Deckkante bis Kiel (die ersten zwei in Metern)


def hull_x(hw, ys, hk, n, y):
    H = ys + hk
    s = np.clip((ys - y) / H, 0, 1)
    return hw * (1 - s ** n) ** (1 / n)


def z_stations(count=28):
    t = np.linspace(0, 1, count)
    z = BOW_Z + (STERN_Z - BOW_Z) * (0.5 - 0.5 * np.cos(np.pi * t))   # dichter an den Enden
    z = np.concatenate([z, [COCKPIT[0], COCKPIT[1], -0.30, 0.20]])
    return np.unique(np.round(z, 4))


def hull_parts():
    zs = z_stations()
    rings = []
    meta = []
    for z in zs:
        hw, ys, hk, n = section(z)
        H = ys + hk
        side = []
        for i, lv in enumerate(LEVELS):
            if i in (1, 2):
                y = ys - lv
            else:
                y = ys - lv * H
            side.append((hull_x(hw, ys, hk, n, y), y))
        right = [(x, y, z) for x, y in side]
        left = [(-x, y, z) for x, y in side[::-1][1:]]
        rings.append(right + left)
        meta.append((hw, ys))
    P = np.array(rings)
    hull = grid(P, wrap=False)
    # Kiel nach unten → Normalen nach aussen prüfen (Mehrheit zeigt weg von der Mittelachse)
    c = hull.v[hull.f].mean(axis=1)
    fn = np.cross(hull.v[hull.f[:, 1]] - hull.v[hull.f[:, 0]], hull.v[hull.f[:, 2]] - hull.v[hull.f[:, 0]])
    out = c - np.stack([np.zeros(len(c)), np.full(len(c), 0.03), c[:, 2]], axis=1)
    if np.sum(np.einsum("ij,ij->i", fn, out)) < 0:
        hull = hull.flipped()
    # Streifen = Band zwischen Level 1 und 2 (Reihen-Spalten 1–2 und deren Spiegel)
    K = P.shape[1]
    nlev = len(LEVELS)
    col = np.arange(K)
    band_cols = {1, K - 3}          # Band rechts (zwischen Punkt 1 und 2) und links
    faces_col = []
    R = P.shape[0]
    for r in range(R - 1):
        for k in range(K - 1):
            faces_col += [k, k]
    faces_col = np.array(faces_col)
    stripe_mask = np.isin(faces_col, list(band_cols))
    from geom import subset
    stripe = subset(hull, stripe_mask)
    body = subset(hull, ~stripe_mask)
    return body, stripe, zs, meta


def deck_parts(zs, meta):
    fr = np.array([-1, -0.82, -0.4, 0.4, 0.82, 1])
    rows = []
    for z, (hw, ys) in zip(zs, meta):
        x = fr * hw
        y = ys + 0.016 * (1 - fr ** 2) * min(1, hw / 0.08)
        rows.append(np.stack([x, y, np.full_like(x, z)], axis=1))
    P = np.array(rows)
    deck = grid(P, wrap=False)
    fn = np.cross(deck.v[deck.f[:, 1]] - deck.v[deck.f[:, 0]], deck.v[deck.f[:, 2]] - deck.v[deck.f[:, 0]])
    if fn[:, 1].sum() < 0:
        deck = deck.flipped()
    c = deck.v[deck.f].mean(axis=1)
    hw_at = np.interp(c[:, 2], zs, [m[0] for m in meta])
    inside = (c[:, 2] > COCKPIT[0]) & (c[:, 2] < COCKPIT[1]) & (np.abs(c[:, 0]) < 0.80 * hw_at)
    from geom import subset
    deck = subset(deck, ~inside)
    # Süllrand um die Öffnung (Deckfarbe), Boden, Spritzschutz
    zc = [z for z in zs if COCKPIT[0] <= z <= COCKPIT[1]]
    edge_r = [(0.82 * section(z)[0], section(z)[1] + 0.016 * (1 - 0.82 ** 2)) for z in zc]
    loop = [(x, y + 0.006, z) for (x, y), z in zip(edge_r, zc)]
    loop += [(-x, y + 0.006, z) for (x, y), z in list(zip(edge_r, zc))[::-1]]
    coaming = tube_path(np.array(loop + [loop[0]]), 0.010, k=4, close=False)
    floor_rows = []
    for z in zc:
        hw = 0.80 * section(z)[0]
        floor_rows.append([(-hw, 0.055, z), (0, 0.050, z), (hw, 0.055, z)])
    floor = grid(np.array(floor_rows), wrap=False)
    fn = np.cross(floor.v[floor.f[:, 1]] - floor.v[floor.f[:, 0]], floor.v[floor.f[:, 2]] - floor.v[floor.f[:, 0]])
    if fn[:, 1].sum() < 0:
        floor = floor.flipped()
    # Innenwände des Cockpits (vom Süll zum Boden)
    walls = []
    for s in (1, -1):
        rows = [[(s * x, y, z), (s * 0.8 * section(z)[0], 0.055, z)] for (x, y), z in zip(edge_r, zc)]
        w = grid(np.array(rows), wrap=False)
        fn = np.cross(w.v[w.f[:, 1]] - w.v[w.f[:, 0]], w.v[w.f[:, 2]] - w.v[w.f[:, 0]])
        if (fn[:, 0] * -s).sum() < 0:
            w = w.flipped()
        walls.append(w)
    hw0, ys0 = section(COCKPIT[0] - 0.05)[:2]
    wb = []
    for s in (1, -1):
        a = np.array([s * 0.75 * hw0, ys0 + 0.012, COCKPIT[0] - 0.02])
        b = np.array([0, ys0 + 0.018, COCKPIT[0] - 0.28])
        P2 = np.array([[a, b], [a + [0, 0.055, 0.01], b + [0, 0.065, 0.0]]])
        wb.append(thicken(P2, 0.006))
    return merge([deck, coaming] + wb + walls), floor


def fin_part():
    z0 = 2.75
    hw, ys, hk, n = section(z0)
    y0 = -hk + 0.01
    prof = []
    for t in np.linspace(0, 1, 5):
        chord = 0.13 * (1 - 0.45 * t)
        zz = z0 + 0.02 * t
        y = y0 - 0.095 * t
        prof.append([(0.0, y, zz - chord * 0.4), (0.0, y, zz + chord * 0.6)])
    P = np.array(prof)
    return thicken(np.concatenate([P[:, :1] + [0.004, 0, 0], P[:, 1:] + [0.004, 0, 0]], axis=1), 0.008)


def bowball_part():
    hw, ys, hk, n = section(BOW_Z + 0.01)
    return ellipsoid((0, ys + 0.008, BOW_Z - 0.004), (0.022, 0.022, 0.024), ku=8, kv=6)


def flag_patch(points_fn, nu=5, nv=3):
    pts, uv = [], []
    for j in range(nv):
        for i in range(nu):
            u, v = i / (nu - 1), j / (nv - 1)
            pts.append(points_fn(u, v))
            uv.append((u, v))
    P = np.array(pts).reshape(nv, nu, 3)
    p = grid(P, wrap=False)
    p.uv = np.array(uv)
    return p


def _facing(p: Part, normal):
    fn = np.cross(p.v[p.f[0, 1]] - p.v[p.f[0, 0]], p.v[p.f[0, 2]] - p.v[p.f[0, 0]])
    return p.flipped() if np.dot(fn, normal) < 0 else p


def flag_parts():
    """Flaggen am Boot (boat-Rahmen): beidseitig nahe Bug (0,8 hinter der Spitze, 0,12 × 0,08) und auf dem Heckdeck
    direkt hinter dem Cockpit (0,14 × 0,09, Oberkante zum Bug – liest sich von der Kamera hinter dem Boot)."""
    out = {}
    zc = BOW_Z + 0.80
    W, Hh = 0.12, 0.08
    for s, name in ((1, "flag_side_R"), (-1, "flag_side_L")):
        def fn(u, v, s=s):
            # rechts (+x) von aussen gesehen: rechts vom Betrachter = Richtung Bug (−z); links umgekehrt
            z = zc + (-(u - 0.5) * W if s > 0 else (u - 0.5) * W)
            hw, ys, hk, n = section(z)
            y = ys - 0.012 - (1 - v) * Hh
            x = hull_x(hw, ys, hk, n, y) + 0.0025
            return (s * x, y, z)
        out[name] = _facing(flag_patch(fn), [s, 0, 0])
    zd = COCKPIT[1] + 0.12
    Wd, Hd = 0.14, 0.09

    def fd(u, v):
        x = (u - 0.5) * Wd                  # Kamera schaut nach −z: rechts = +x
        z = zd + 0.10 - v * Hd               # oben (v = 1) zum Bug
        hw, ys = section(z)[:2]
        fr = x / hw
        return (x, ys + 0.016 * (1 - fr * fr) + 0.002, z)
    out["flag_deck"] = _facing(flag_patch(fd), [0, 1, 0])
    return out


# ------------------------------------------------------------------------------------------------- crew-Teile

def seat_part():
    prof = [(-0.022, 0.110, 0.120), (-0.012, 0.130, 0.140), (0.012, 0.130, 0.140), (0.022, 0.112, 0.122)]
    from geom import loft_y
    return loft_y(prof, k=16, n=3.0)


def tracks_part():
    rails = []
    for s in (1, -1):
        rails.append(tube_path(np.array([[s * 0.075, 0.125, -0.12], [s * 0.075, 0.125, 0.78]]), 0.009, k=6))
    return merge(rails)


def stretcher_part():
    a = STRETCHER_ANGLE
    d = np.array([0, np.sin(a + 0.38), -np.cos(a + 0.38)])
    n = np.array([0, -d[2], d[1]])
    if np.dot(n, [0, 1, 0.3]) < 0:
        n = -n
    ankle = np.array([0, FOOT_Y, FOOT_Z])
    heel = ankle + np.array([0, -0.045, 0.035]) - n * 0.012
    P = np.array([[heel - d * 0.02 + [-0.17, 0, 0], heel - d * 0.02 + [0.17, 0, 0]],
                  [heel + d * 0.24 + [-0.17, 0, 0], heel + d * 0.24 + [0.17, 0, 0]]])
    plate = thicken(P, 0.010)
    plate = _facing_closed(plate)
    struts = [tube_path(np.array([[s * 0.17, 0.06, FOOT_Z + 0.10], heel + d * 0.16 + [s * 0.16, 0, 0] - n * 0.01]),
                        0.009, k=6) for s in (1, -1)]
    bar = tube_path(np.array([[-0.17, 0.06, FOOT_Z + 0.10], [0.17, 0.06, FOOT_Z + 0.10]]), 0.009, k=6)
    return merge([plate, bar] + struts)


def _facing_closed(p):
    return p.outward()


def gates_part():
    parts = []
    for s in (1, -1):
        pin = tube_path(np.array([[s * PIN_X, 0.31, PIN_Z], [s * PIN_X, 0.42, PIN_Z]]), 0.007, k=6)
        gate = ellipsoid((s * PIN_X, PIN_Y, PIN_Z), (0.030, 0.042, 0.026), ku=6, kv=4)
        parts += [pin, gate]
    return merge(parts)


def wing_rigger():
    """Flügelausleger vorn: je Seite ein flaches, gewölbtes Carbonprofil vom Bordrand zur Dolle, beide Seiten über
    eine Brücke vor dem Stemmbrett verbunden."""
    parts = []
    for s in (1, -1):
        rows = []
        for t in np.linspace(0, 1, 9):
            x = 0.13 + (PIN_X - 0.13) * t
            y = 0.128 + (0.312 - 0.128) * np.sin(np.pi / 2 * t) ** 0.7
            zc = -0.24 + (PIN_Z + 0.02 + 0.24) * t ** 0.9          # Vorderkante läuft zur Dolle
            hz = 0.075 - 0.040 * t                                   # halbe Profiltiefe
            th = 0.026 - 0.010 * t
            ring = [(s * x, y + np.sin(a) * th / 2, zc + np.cos(a) * hz) for a in np.linspace(0, 2 * np.pi, 10,
                                                                                            endpoint=False)]
            rows.append(ring)
        P = np.array(rows)
        root = np.array([s * 0.125, 0.128, -0.24])
        tip = np.array([s * (PIN_X + 0.012), 0.312, PIN_Z + 0.02])
        parts.append(grid(P, True, root, tip).outward())
    parts.append(tube_path(np.array([[-0.14, 0.13, -0.26], [0, 0.155, -0.27], [0.14, 0.13, -0.26]]), 0.020, k=8,
                           aspect=0.45))
    return merge(parts)


def backwing_rigger():
    path = [(0.80, 0.312, -0.04), (0.66, 0.300, 0.12), (0.46, 0.285, 0.38), (0.26, 0.272, 0.62), (0.0, 0.268, 0.72)]
    pts = path + [(-x, y, z) for x, y, z in path[::-1][1:]]
    pts = np.array(pts)
    # Kurve etwas verdichten
    t = np.linspace(0, 1, len(pts))
    tt = np.linspace(0, 1, 17)
    dense = np.stack([np.interp(tt, t, pts[:, i]) for i in range(3)], axis=1)
    arch = tube_path(dense, 0.030, k=10, aspect=0.38)
    legs = [tube_path(np.array([[s * 0.30, 0.276, 0.58], [s * 0.145, 0.125, 0.55]]), 0.011, k=6) for s in (1, -1)]
    return merge([arch] + legs)


def traditional_rigger():
    parts = []
    for s in (1, -1):
        bottom = np.array([s * PIN_X, 0.315, PIN_Z])
        top = np.array([s * PIN_X, 0.40, PIN_Z])
        for a in ([s * 0.145, 0.125, -0.40], [s * 0.145, 0.125, 0.30]):
            parts.append(tube_path(np.array([a, bottom]), 0.0115, k=8))
        parts.append(tube_path(np.array([[s * 0.13, 0.055, PIN_Z], bottom]), 0.0115, k=8))
        parts.append(tube_path(np.array([[s * 0.145, 0.128, -0.40], top]), 0.009, k=8))
    return merge(parts)


# ------------------------------------------------------------------------------------------------- Skulls

BLADE_NECK_X = 1.52


def blade_outline(shape):
    """Liefert (Länge, top(t), bottom(t)) mit t = 0 am Hals, 1 an der Spitze; y relativ zur Schaftachse."""
    if shape == "macon":
        L = 0.50

        def half(t):
            w = 0.080 * np.sin(np.pi / 2 * np.clip(t / 0.78, 0, 1)) ** 0.75
            w = np.where(t > 0.80, w * np.sqrt(np.clip(1 - ((t - 0.80) / 0.205) ** 2, 0, 1)), w)
            return np.maximum(w, 0.014 * (1 - t))
        return L, (lambda t: half(t)), (lambda t: -half(t))
    if shape == "fat2":
        L = 0.42

        def top(t):
            y = 0.012 + 0.090 * np.sin(np.pi / 2 * np.clip(t / 0.30, 0, 1)) ** 0.9
            return np.where(t > 0.86, y * np.sqrt(np.clip(1 - ((t - 0.86) / 0.145) ** 2, 0, 1)) + 0.0, y)

        def bot(t):
            y = -0.012 - 0.150 * np.sin(np.pi / 2 * np.clip(t / 0.62, 0, 1)) ** 1.1
            return np.where(t > 0.82, y * np.sqrt(np.clip(1 - ((t - 0.82) / 0.185) ** 2, 0, 1)), y)
        return L, top, bot
    # bigblade (Hackbeil): obere Kante lang und gerade, untere kürzer und gebogen
    L = 0.46

    def top(t):
        y = 0.012 + 0.068 * np.sin(np.pi / 2 * np.clip(t / 0.22, 0, 1))
        return np.where(t > 0.92, y * np.sqrt(np.clip(1 - ((t - 0.92) / 0.085) ** 2, 0, 1)), y)

    def bot(t):
        y = -0.012 - 0.130 * np.sin(np.pi / 2 * np.clip(t / 0.70, 0, 1)) ** 1.3
        return np.where(t > 0.70, -0.012 + (y + 0.012) * np.sqrt(np.clip(1 - ((t - 0.70) / 0.305) ** 2, 0, 1)), y)
    return L, top, bot


def blade_part(shape, side=1):
    L, top, bot = blade_outline(shape)
    ts = np.linspace(0, 1, 8)
    ss = np.linspace(-1, 1, 5)
    rows = []
    for t in ts:
        yt, yb = float(top(t)), float(bot(t))
        if yt - yb < 0.004:
            yt, yb = 0.002, -0.002
        ring = []
        for s in ss:
            y = yb + (yt - yb) * (s * 0.5 + 0.5)
            # Wölbung: Mitte nach +z (hohle Seite zeigt nach −z = Heck beim rechten Skull)
            cup = 0.020 * (1 - s * s) * np.clip(t * 3, 0, 1) + 0.022 * t * t
            ring.append((BLADE_NECK_X + t * L, y, cup))
        rows.append(ring)
    P = np.array(rows)
    p = thicken(P, 0.008)
    if side < 0:
        p = p.scaled([1, 1, -1])
    return p


def shaft_part():
    xs = np.linspace(-INBOARD + 0.14, BLADE_NECK_X + 0.10, 6)
    r = np.linspace(0.0185, 0.0150, 6)
    return tube_path(np.stack([xs, np.zeros(6), np.zeros(6)], axis=1), r, k=8, up=(0, 0, 1))


def grip_part():
    xs = np.array([-INBOARD, -INBOARD + 0.14])
    return tube_path(np.stack([xs, np.zeros(2), np.zeros(2)], axis=1), [0.021, 0.021], k=10, up=(0, 0, 1))


def sleeve_part():
    s = tube_path(np.array([[-0.10, 0, 0], [0.14, 0, 0]]), 0.024, k=8, up=(0, 0, 1))
    b = tube_path(np.array([[-0.115, 0, 0], [-0.095, 0, 0]]), 0.036, k=8, up=(0, 0, 1))
    return merge([s, b])


def build_parts():
    """prim_name → (frame, group, Part). frame ∈ boat | crew | oar | seat."""
    out = {}
    body, stripe, zs, meta = hull_parts()
    out["hull__hull"] = ("boat", "hull", body)
    out["hull_stripe__stripe"] = ("boat", "stripe", stripe)
    deck, floor = deck_parts(zs, meta)
    out["deck__deck"] = ("boat", "deck", deck)
    out["cockpit__fittings"] = ("boat", "fittings", floor)
    out["fin__fin"] = ("boat", "fin", fin_part())
    out["bowball__bowball"] = ("boat", "bowball", bowball_part())
    for name, p in flag_parts().items():
        out[f"{name}__flag"] = ("boat", "flag", p)
    out["seat__fittings"] = ("seat", "fittings", seat_part())
    out["tracks__fittings"] = ("crew", "fittings", tracks_part())
    out["stretcher__fittings"] = ("crew", "fittings", stretcher_part())
    out["gates__fittings"] = ("crew", "fittings", gates_part())
    out["rigger_wing__rigger"] = ("crew", "rigger", wing_rigger())
    out["rigger_backwing__rigger"] = ("crew", "rigger", backwing_rigger())
    out["rigger_traditional__rigger"] = ("crew", "rigger", traditional_rigger())
    out["oar_shaft__shaft"] = ("oar", "shaft", shaft_part())
    out["oar_grip__fittings"] = ("oar", "fittings", grip_part())
    out["oar_sleeve__sleeve"] = ("oar", "sleeve", sleeve_part())
    for shape in ("macon", "bigblade", "fat2"):
        out[f"blade_{shape}_R__blade"] = ("oar", "blade", blade_part(shape, 1))
        out[f"blade_{shape}_L__blade"] = ("oar", "blade", blade_part(shape, -1))
    return out
