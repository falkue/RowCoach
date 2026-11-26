"""Ruderfigur als Teile (Segmente × Materialgruppen), weiche Formen mit glatten Normalen.

Koordinaten: crew-System von `BoatRig` – die Figur schaut nach −z (zum Heck, also zur Kamera), x = rechts der Figur
von hinten gesehen (= Steuerbord-Dolle bei +x), y = oben, Meter.

Segmente und ihre lokalen Rahmen (Ursprung = Gelenk; so setzt die App sie zusammen, siehe docs/avatar/SPEC.md):
- `pelvis`   Ursprung Hüftgelenk-Mitte (auf dem Rollsitz), dreht mit der Oberkörperneigung. Teile: Becken, Torso, Brustflagge.
- `head`     Ursprung Halsansatz = (0, TORSO_TOP, 0) im pelvis-Rahmen. Teile: Kopf mit Hals/Ohren/Nase, Augen, Frisuren,
             Brille, Cap, Stirnband.
- `upperarm` Ursprung Schulter, +y zum Ellbogen (Länge UPPER_ARM).
- `forearm`  Ursprung Ellbogen, +y zur Griffmitte (Länge FOREARM, Hand am Ende), x = nach aussen. Teile: Unterarm, Hand, Uhr.
- `thigh`    Ursprung Hüftgelenk (±HIP_HALF), +y zum Knie (THIGH).
- `shin`     Ursprung Knie, +y zum Knöchel (SHIN).
- `foot`     Ursprung Knöchel (= Fusspunkt am Stemmbrett), nicht gedreht (Schuh liegt auf dem schrägen Stemmbrett).

Linke und rechte Gliedmassen teilen sich dasselbe Mesh (symmetrisch um x = 0 des Segments; die App spiegelt nicht).
"""
from __future__ import annotations

import numpy as np

from geom import (Part, capsule_y, ellipsoid, grid, loft_y, merge, split_faces, superellipse_ring, thicken,
                  tube_path)

# Masse – müssen zu BoatRig.D / RowerFigure.D in der App passen
HIP_Y = 0.26
FOOT_Y = 0.14
FOOT_Z = -0.45
HIP_HALF = 0.10
FOOT_HALF = 0.12
THIGH = 0.48
SHIN = 0.48
TORSO_TOP = 0.50          # Halsansatz über dem Hüftgelenk
SHOULDER_Y = 0.46         # Schultergelenk über dem Hüftgelenk
SHOULDER_HALF = 0.17
UPPER_ARM = 0.31
FOREARM = 0.37            # Ellbogen → Griffmitte
STRETCHER_ANGLE = 0.6     # Neigung des Stemmbretts (rad, um x), wie heute

HEAD_C = np.array([0.0, 0.165, -0.005])     # Kopfmitte im head-Rahmen
HEAD_R = np.array([0.100, 0.122, 0.108])     # Halbachsen (DESIGN: 0,20 × 0,25 × 0,22)


# ---------------------------------------------------------------------------------------------------------- Rumpf

TORSO_PROF = np.array([
    # y, halbe Breite, halbe Tiefe, z-Versatz – flachere Vorderseite durch Superellipse n=2.6
    (0.02, 0.120, 0.090, 0.010),
    (0.06, 0.140, 0.100, 0.008),
    (0.14, 0.132, 0.095, 0.000),
    (0.24, 0.142, 0.100, -0.004),
    (0.33, 0.162, 0.108, -0.008),
    (0.40, 0.172, 0.104, -0.006),
    (0.45, 0.160, 0.092, -0.002),
    (0.485, 0.120, 0.072, 0.000),
    (0.505, 0.060, 0.048, 0.004),
])
TORSO_N = 2.6


def torso_at(y):
    return [float(np.interp(y, TORSO_PROF[:, 0], TORSO_PROF[:, i])) for i in (1, 2, 3)]


def _torso_rings(ylev, k=28, inflate=0.0):
    """ylev: Funktion (Reihe, Winkel) → y. Liefert Ringe (R, k, 3)."""
    th = np.linspace(0, 2 * np.pi, k, endpoint=False)
    c, s = np.cos(th), np.sin(th)
    rings = []
    for r in range(len(ylev)):
        pts = []
        for i in range(k):
            y = ylev[r](th[i])
            a, b, cz = torso_at(y)
            x = (a + inflate) * np.sign(c[i]) * abs(c[i]) ** (2 / TORSO_N)
            z = cz + (b + inflate) * np.sign(s[i]) * abs(s[i]) ** (2 / TORSO_N)
            pts.append((x, y, z))
        rings.append(pts)
    return np.array(rings)


def torso_mesh(k=24):
    ys = [0.02, 0.05, 0.10, 0.17, 0.25, 0.32, 0.38, 0.43, 0.465, 0.488, 0.50]
    P = _torso_rings([(lambda t, y=y: y) for y in ys], k)
    return grid(P, True, [0, 0.0, 0.010], [0, 0.507, 0.004]).outward()


def neckline(front, side, back):
    def y(t):
        sn = np.sin(t)          # +1 = hinten, −1 = vorne
        return side + (front - side) * max(-sn, 0) ** 1.5 + (back - side) * max(sn, 0) ** 1.5
    return y


def torso_split(cut, strap_x, strap_w, k=24):
    """Tanktop/Einteiler: Trikot bis zur Linie `cut`, darüber Haut, Träger als eigene, leicht aufliegende Bänder."""
    lo = [0.02, 0.05, 0.10, 0.17, 0.25]
    lower_lev = [(lambda t, y=y: y) for y in lo] + [(lambda t, f=f: 0.25 + (cut(t) - 0.25) * f) for f in (0.5, 1)]
    upper_lev = [(lambda t, f=f: cut(t) + (0.50 - cut(t)) * f) for f in (0, 0.4, 0.7, 0.9, 1.0)]
    lower = grid(_torso_rings(lower_lev, k), True, [0, 0.0, 0.010], None)
    upper = grid(_torso_rings(upper_lev, k), True, None, [0, 0.507, 0.004])
    lower = _orient_shell(lower, np.array([0, 0.25, 0.0]))
    upper = _orient_shell(upper, np.array([0, 0.35, 0.0]))
    straps = []
    for sgn in (1, -1):
        rows = []
        y_top = float(np.interp(-(strap_x + strap_w / 2), -TORSO_PROF[:, 1], TORSO_PROF[:, 0]))
        y_top = min(y_top, 0.50)
        for t in np.linspace(-1, 1, 9):
            row = []
            front = t < 0
            th = -np.pi / 2 if front else np.pi / 2
            y0 = cut(th) - 0.012
            y = y_top - (y_top - y0) * abs(t) ** 1.4
            for dx in (-strap_w / 2, 0, strap_w / 2):
                x = sgn * (strap_x + dx)
                a, b, cz = torso_at(y)
                a, b = a + 0.004, b + 0.004
                r = min(abs(x) / a, 0.999)
                dz = b * (1 - r ** TORSO_N) ** (1 / TORSO_N)
                row.append((x, y, cz + (-dz if front else dz)))
            rows.append(row)
        straps.append(thicken(np.array(rows), 0.004))
    return upper, merge([lower] + straps)


def hips_mesh():
    # Becken/Gesäss: abgeflachtes Ellipsoid, etwas nach hinten (+z) versetzt
    def deform(d):
        return 1 - 0.10 * np.clip(-d[:, 1], 0, 1) ** 2
    return ellipsoid((0, 0.0, 0.015), (0.150, 0.095, 0.120), ku=14, kv=7, deform=deform)


# ---------------------------------------------------------------------------------------------------------- Kopf

def head_mesh():
    def deform(d):
        # Kinn schmaler, Hinterkopf voller
        chin = np.clip(-d[:, 1], 0, 1) * np.clip(-d[:, 2] + 0.2, 0, 1.2)
        back = np.clip(d[:, 2], 0, 1) * np.clip(d[:, 1] + 0.3, 0, 1)
        return 1 - 0.16 * chin ** 1.5 + 0.04 * back
    head = ellipsoid(HEAD_C, HEAD_R, ku=20, kv=12, deform=deform)
    neck = capsule_y(0.11, 0.050, 0.046, k=10, rings_body=1, rings_cap=1).transformed(t=(0, -0.025, 0.012))
    nose = ellipsoid(HEAD_C + [0, -0.012, -0.100], (0.016, 0.026, 0.020), ku=6, kv=4)
    ears = [ellipsoid(HEAD_C + [s * 0.097, -0.002, 0.010], (0.014, 0.028, 0.020), ku=6, kv=4) for s in (1, -1)]
    return merge([head, neck, nose] + ears)


def eyes_mesh():
    return merge([ellipsoid(HEAD_C + [s * 0.036, 0.012, -0.096], (0.012, 0.015, 0.007), ku=6, kv=4) for s in (1, -1)])


def _shell_dirs(h_front, h_side, h_back, ku, kv, top_bias=0.0, wave=(0.0, 0)):
    """Richtungen einer Haarkappe: je Azimut ein Bogen vom Scheitel bis zur Haarlinie (Höhe cosθ = h(φ))."""
    phis = np.linspace(0, 2 * np.pi, ku, endpoint=False)
    cols = []
    for phi in phis:
        # φ = 0 → +x, φ = −π/2 → −z (vorne)
        fz = -np.sin(phi)  # Anteil nach vorne (1 = vorne)
        if fz >= 0:
            h = h_side + (h_front - h_side) * fz ** 1.5 + wave[0] * np.sin(wave[1] * phi) * fz ** 2
        else:
            h = h_side + (h_back - h_side) * (-fz) ** 1.2
        thmax = np.arccos(np.clip(h, -0.98, 0.98))
        th = np.linspace(0, 1, kv + 1)[1:] ** (1 - top_bias) * thmax
        d = np.stack([np.sin(th) * np.cos(phi), np.cos(th), np.sin(th) * np.sin(phi)], axis=1)
        cols.append(d)
    return np.array(cols).transpose(1, 0, 2)  # (Ringe, ku, 3)


def hair_cap(scale=1.06, h_front=0.42, h_side=0.05, h_back=-0.62, ku=22, kv=7, bumps=0.0, bump_freq=(5, 4),
             lift=0.0, center=None, radii=None, lip=0.02, back_scale=1.0, wave=(0.0, 0)):
    """Haarkappe als Schale über dem Kopf-Ellipsoid mit sauberer Haarlinie und Rand, der zum Kopf hin einrollt."""
    c = HEAD_C if center is None else np.asarray(center)
    r = HEAD_R if radii is None else np.asarray(radii)
    D = _shell_dirs(h_front, h_side, h_back, ku, kv, wave=wave)
    R, K = D.shape[:2]
    fac = np.full((R, K), scale)
    if bumps:
        th = np.arccos(np.clip(D[..., 1], -1, 1))
        ph = np.arctan2(D[..., 2], D[..., 0])
        fac = fac + bumps * (np.sin(bump_freq[0] * ph) * np.sin(bump_freq[1] * th * 2) * 0.5 + 0.5) * \
            np.clip(D[..., 1] + 0.6, 0.3, 1.0)
    back = np.clip(D[..., 2], 0, 1)
    fac = fac * (1 + (back_scale - 1) * back)
    P = c + D * r * fac[..., None] + np.array([0, lift, 0]) * (D[..., 1:2] > 0)
    # Rand: eine Reihe nach innen auf die Kopfoberfläche (verhindert Durchblick unter die Schale)
    # Rand auf die Kopfhaut einziehen (Richtung vom Kopfmittelpunkt aus), damit keine Helmkante entsteht
    edge = P[-1]
    dn = (edge - HEAD_C) / HEAD_R
    dn = dn / np.linalg.norm(dn, axis=1, keepdims=True)
    inner = HEAD_C + dn * HEAD_R * (1.0 - lip)
    P = np.concatenate([P, inner[None]], axis=0)
    top = c + np.array([0, r[1] * scale + lift, 0])
    return _orient_shell(grid(P, True, top, None), c)


def _orient_shell(p: Part, center):
    """Offene Schale: Dreiecke so drehen, dass die Normalen von `center` weg zeigen (Mehrheit)."""
    v, f = p.v, p.f
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    out = v[f].mean(axis=1) - center
    if np.sum(np.einsum("ij,ij->i", fn, out)) < 0:
        return p.flipped()
    return p


def hair_parts():
    """Frisuren (Name → Part, alle im head-Rahmen). bald hat kein Teil."""
    H = {}
    H["short"] = hair_cap(1.05, h_front=0.42, h_side=0.02, h_back=-0.55, ku=24, kv=7, bumps=0.035, bump_freq=(8, 2),
                          lift=0.008, wave=(0.07, 7))
    H["buzz"] = hair_cap(1.022, h_front=0.40, h_side=0.0, h_back=-0.55, ku=20, kv=6, lip=0.01)
    curly = hair_cap(1.09, h_front=0.34, h_side=-0.05, h_back=-0.55, ku=28, kv=9, bumps=0.07, bump_freq=(9, 5),
                     lift=0.025, wave=(0.08, 9))
    H["curly"] = curly
    # Afro: grosse, leicht abgeflachte Kugel über und hinter der Kopfmitte, unten zur Haarlinie eingezogen
    H["afro"] = hair_cap(1.0, h_front=0.12, h_side=-0.45, h_back=-0.72, ku=30, kv=11, bumps=0.05, bump_freq=(11, 6),
                         center=HEAD_C + [0, 0.045, 0.045], radii=(0.168, 0.158, 0.170), wave=(0.06, 8))
    sleek = hair_cap(1.035, h_front=0.40, h_side=0.0, h_back=-0.45, ku=22, kv=7, back_scale=1.03, wave=(0.03, 5))
    # Pferdeschwanz: Haargummi + Schwanz nach hinten unten
    pts = np.array([[0, 0.205, 0.105], [0, 0.185, 0.150], [0, 0.130, 0.185], [0, 0.060, 0.195],
                    [0, -0.005, 0.185], [0, -0.050, 0.165]])
    tail = tube_path(pts, [0.024, 0.034, 0.038, 0.034, 0.025, 0.010], k=10)
    tie = tube_path(np.array([[0, 0.212, 0.090], [0, 0.198, 0.124]]), [0.026, 0.026], k=10)
    H["ponytail"] = merge([sleek, tail, tie])
    # Dutt: Kugel oben hinten
    bun = ellipsoid(HEAD_C + [0, 0.115, 0.075], (0.055, 0.050, 0.055), ku=14, kv=9)
    H["bun"] = merge([sleek, bun])
    # Zopf: abnehmende Glieder vom Hinterkopf über den Nacken
    links = []
    zp = [(0.145, 0.115, 0.042), (0.085, 0.130, 0.040), (0.030, 0.135, 0.036), (-0.020, 0.135, 0.032),
          (-0.065, 0.130, 0.028), (-0.105, 0.124, 0.022)]
    for i, (y, z, r) in enumerate(zp):
        links.append(ellipsoid((0.004 * (-1) ** i, y, z), (r, r * 1.25, r * 0.85), ku=8, kv=5))
    H["braid"] = merge([sleek] + links)
    # Lang offen: Kappe + Vorhang hinten bis über die Schultern + zwei Strähnen vorn
    long_cap = hair_cap(1.05, h_front=0.42, h_side=-0.05, h_back=-0.30, ku=24, kv=8, lift=0.008, wave=(0.05, 4))
    curtain = _curtain()
    H["long"] = merge([long_cap, curtain])
    H["cap"] = hair_cap(1.03, h_front=0.30, h_side=-0.05, h_back=-0.55, ku=20, kv=6)
    H["headband"] = hair_cap(1.07, h_front=0.40, h_side=0.02, h_back=-0.55, ku=24, kv=7, bumps=0.04, bump_freq=(8, 2),
                             lift=0.02, wave=(0.06, 7))
    return H


def _curtain():
    # Haarvorhang hinten: oben in der Kappe verborgen, nach unten etwas breiter und zum Rücken hin auslaufend
    rows = []
    ys = np.linspace(HEAD_C[1] + 0.03, -0.04, 7)
    for i, y in enumerate(ys):
        t = i / (len(ys) - 1)
        span = 1.20 - 0.30 * t
        a = np.linspace(-span, span, 11)  # Winkel um y, 0 = hinten
        rad_x = 0.098 + 0.010 * t
        rad_z = 0.104 + 0.022 * t + 0.012 * t * t
        x = rad_x * np.sin(a)
        z = HEAD_C[2] + 0.004 + rad_z * np.cos(a)
        rows.append(np.stack([x, np.full_like(x, y), z], axis=1))
    P = np.array(rows)
    return thicken(P, 0.030)


# ---------------------------------------------------------------------------------------------------------- Accessoires

def _band(dirs_fn, f_out, center=HEAD_C, radii=HEAD_R):
    D = dirs_fn()
    return center + D * radii * f_out


def sunglasses_mesh():
    # Band um die Augenpartie: Azimut ±80° um vorne, Höhe −0.10…+0.20 (normiert)
    phis = np.linspace(-np.pi / 2 - 1.45, -np.pi / 2 + 1.45, 15)
    rows = []
    for hy in np.linspace(0.04, 0.21, 3):
        d = np.stack([np.cos(phis) * np.sqrt(1 - hy * hy), np.full_like(phis, hy), np.sin(phis) * np.sqrt(1 - hy * hy)],
                     axis=1)
        front = np.clip(-d[:, 2], 0, 1)
        f = 1.05 + 0.04 * front ** 2
        rows.append(HEAD_C + d * HEAD_R * f[:, None])
    P = np.array(rows)
    return thicken(P[::-1], 0.006)


def cap_mesh():
    crown = hair_cap(1.10, h_front=0.40, h_side=0.12, h_back=-0.10, ku=20, kv=5)
    # Schirm: flache, gerundete Platte vorne, leicht nach unten geneigt
    rows = []
    phis = np.linspace(-np.pi / 2 - 1.1, -np.pi / 2 + 1.1, 11)
    hy = 0.40
    for t in (0.0, 0.55, 1.0):
        out = 1.11 + t * 0.62 * np.cos((phis + np.pi / 2) * 0.95) ** 1.2
        d = np.stack([np.cos(phis), np.zeros_like(phis), np.sin(phis)], axis=1)
        y = HEAD_C[1] + HEAD_R[1] * hy * 1.11 - t * 0.010
        p = np.stack([HEAD_C[0] + d[:, 0] * HEAD_R[0] * out, np.full_like(phis, y),
                      HEAD_C[2] + d[:, 2] * HEAD_R[2] * out], axis=1)
        rows.append(p)
    brim = thicken(np.array(rows), 0.008)
    return merge([crown, brim])


def headband_mesh():
    rows = []
    phis = np.linspace(0, 2 * np.pi, 24, endpoint=False)
    for hy_front, hy_back in ((0.40, 0.12), (0.60, 0.34)):
        fz = -np.sin(phis)
        hy = hy_back + (hy_front - hy_back) * (fz * 0.5 + 0.5)
        d = np.stack([np.cos(phis) * np.sqrt(1 - hy ** 2), hy, np.sin(phis) * np.sqrt(1 - hy ** 2)], axis=1)
        rows.append(HEAD_C + d * HEAD_R * 1.16)
    return thicken(np.array(rows[::-1]), 0.010, wrap=True)


def watch_mesh():
    # Ring ums Handgelenk (forearm-Rahmen) + Zifferblatt auf der Oberseite (−z ≈ Handrücken? hier: aussen +x)
    y = FOREARM - 0.115
    band = tube_path(np.array([[0, y - 0.012, 0], [0, y + 0.012, 0]]), [0.039, 0.039], k=10)
    face = ellipsoid((0.0, y, -0.038), (0.019, 0.019, 0.008), ku=8, kv=4)
    return merge([band, face])


# ---------------------------------------------------------------------------------------------------------- Glieder

def upperarm_mesh():
    def bulge(t):
        return 1 + 0.10 * np.sin(np.pi * np.clip(t * 1.4, 0, 1))
    arm = capsule_y(UPPER_ARM, 0.050, 0.038, k=9, rings_body=4, rings_cap=2, bulge=bulge)
    # Schulterkappe (Deltamuskel): weicher Ellipsoid am Gelenk
    delt = ellipsoid((0.006, 0.020, 0.0), (0.060, 0.070, 0.058), ku=9, kv=5)
    return merge([arm, delt])


def sleeve_pred(c):
    return c[:, 1] < 0.15


def forearm_mesh():
    def bulge(t):
        return 1 + 0.12 * np.sin(np.pi * np.clip(t * 1.6, 0, 1))
    fore = capsule_y(FOREARM - 0.085, 0.038, 0.028, k=9, rings_body=4, rings_cap=2, bulge=bulge)
    return fore


def hand_mesh():
    # Faust um den Griff: ellipsoid, Daumen als kleiner Wulst
    c = np.array([0.0, FOREARM - 0.005, 0.0])
    fist = ellipsoid(c, (0.040, 0.058, 0.045), ku=9, kv=6)
    thumb = ellipsoid(c + [-0.018, -0.015, -0.035], (0.016, 0.030, 0.016), ku=6, kv=4)
    return merge([fist, thumb])


def thigh_mesh():
    def bulge(t):
        return 1 + 0.08 * np.sin(np.pi * np.clip(t * 1.2, 0, 1))
    return capsule_y(THIGH, 0.078, 0.052, k=12, rings_body=5, rings_cap=2, bulge=bulge)


def shorts_pred(length):
    return lambda c: c[:, 1] < length


def shin_mesh():
    def bulge(t):
        return 1 + 0.18 * np.exp(-((t - 0.28) / 0.22) ** 2)
    return capsule_y(SHIN, 0.050, 0.034, k=10, rings_body=5, rings_cap=2, bulge=bulge)


def sock_pred(c):
    return c[:, 1] > SHIN - 0.07


def foot_mesh():
    """Schuh auf dem Stemmbrett: Sohle entlang d (steigt zum Heck hin an), Ursprung am Knöchel."""
    a = STRETCHER_ANGLE
    d = np.array([0, np.sin(a + 0.38), -np.cos(a + 0.38)])     # Ferse → Zehen (nach −z und oben)
    n = np.array([0, -d[2], d[1]])                               # Sohlennormale (nach oben, zur Figur hin)
    if np.dot(n, [0, 1, 0.3]) < 0:
        n = -n
    heel = np.array([0, -0.045, 0.035])
    prof = []
    L = 0.27
    for i, t in enumerate(np.linspace(0, 1, 5)):
        w = 0.040 + 0.012 * np.sin(np.pi * min(t * 1.2, 1)) - 0.010 * t
        h = 0.055 * (1 - 0.55 * t) + 0.012
        prof.append((t, w, h))
    rings = []
    for t, w, h in prof:
        c = heel + d * (t * L) + n * (h * 0.55)
        ang = np.linspace(0, 2 * np.pi, 10, endpoint=False)
        side = np.array([1.0, 0, 0])
        ring = c + np.outer(np.cos(ang) * w, side) + np.outer(np.sin(ang) * h * 0.6, n)
        rings.append(ring)
    P = np.array(rings)
    return grid(P, True, heel + n * 0.025 - d * 0.02, heel + d * (L + 0.02) + n * 0.02).outward()


# ---------------------------------------------------------------------------------------------------------- Flagge

def chest_flag():
    """Aufnäher 0,10 × 0,07 vorne auf der Brust (pelvis-Rahmen), mit UV (u nach rechts vom Betrachter aus, v nach oben)."""
    # Vorderseite der Brust bei y ≈ 0.36: halbe Tiefe 0.108, Versatz −0.008, Superellipse n=2.6 → z ≈ −0.116
    W, Hh = 0.10, 0.07
    cx, cy = 0.055, 0.355     # leicht links vom Betrachter? Brust links der Figur (= +x … Herzseite ist −x der Figur?)
    us = np.linspace(0, 1, 5)
    vs = np.linspace(0, 1, 3)
    pts, uv = [], []
    for v in vs:
        for u in us:
            x = cx - (u - 0.5) * W            # Betrachter schaut nach +z: rechts vom Betrachter = −x
            y = cy + (v - 0.5) * Hh
            xn = x / 0.165
            z = -0.008 - 0.108 * (1 - min(abs(xn), 0.99) ** 2.6) ** (1 / 2.6) - 0.004
            pts.append((x, y, z))
            uv.append((u, v))
    P = np.array(pts).reshape(len(vs), len(us), 3)
    p = grid(P, False)
    p.uv = np.array(uv)
    # Normale muss nach −z zeigen
    fn = np.cross(p.v[p.f[0, 1]] - p.v[p.f[0, 0]], p.v[p.f[0, 2]] - p.v[p.f[0, 0]])
    return p.flipped() if fn[2] > 0 else p


# ---------------------------------------------------------------------------------------------------------- alles

def build_parts():
    """Liefert dict prim_name → (segment, group, Part). Name: <segment>_<variante>__<gruppe>."""
    out = {}

    def add(seg, name, group, part):
        if part is not None and len(part.f):
            out[f"{name}__{group}"] = (seg, group, part)

    hips = hips_mesh()
    add("pelvis", "hips", "shorts", hips)
    torso = torso_mesh()
    add("pelvis", "torso_tee", "shirt", torso)
    skin, shirt = torso_split(neckline(0.385, 0.345, 0.405), 0.085, 0.060)
    add("pelvis", "torso_tank", "skin", skin)
    add("pelvis", "torso_tank", "shirt", shirt)
    skin, shirt = torso_split(neckline(0.395, 0.355, 0.425), 0.090, 0.034)
    add("pelvis", "torso_unisuit", "skin", skin)
    add("pelvis", "torso_unisuit", "shirt", shirt)
    add("pelvis", "flag_chest", "flag", chest_flag())

    add("head", "head", "skin", head_mesh())
    add("head", "eyes", "eyes", eyes_mesh())
    for style, part in hair_parts().items():
        add("head", f"hair_{style}", "hair", part)
    add("head", "acc_sunglasses", "accessory", sunglasses_mesh())
    add("head", "acc_cap", "accessory", cap_mesh())
    add("head", "acc_headband", "accessory", headband_mesh())

    ua = upperarm_mesh()
    add("upperarm", "upperarm_bare", "skin", ua)
    sleeve, bare = split_faces(ua, sleeve_pred)
    add("upperarm", "upperarm_tee", "shirt", sleeve)
    add("upperarm", "upperarm_tee", "skin", bare)

    add("forearm", "forearm", "skin", merge([forearm_mesh(), hand_mesh()]))
    add("forearm", "acc_watch", "accessory", watch_mesh())

    th = thigh_mesh()
    sh, sk = split_faces(th, shorts_pred(0.27))
    add("thigh", "thigh", "shorts", sh)
    add("thigh", "thigh", "skin", sk)
    shin = shin_mesh()
    sock, leg = split_faces(shin, sock_pred)
    add("shin", "shin", "skin", leg)
    add("shin", "shin", "socks", sock)
    add("foot", "foot", "shoes", foot_mesh())
    return out
