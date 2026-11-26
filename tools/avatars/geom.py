"""Kleine Mesh-Bausteine für Figur und Boot (numpy, ohne Blender).

Konventionen
- Ein Teil ist ein `Part(v, f, uv=None)`: Punkte (n, 3) float32, Dreiecke (m, 3) int32, gegen den Uhrzeigersinn von
  aussen gesehen (wie RealityKit und USD „rightHanded“), optional Texturkoordinaten (n, 2).
- Gitter `grid(P)`: P hat die Form (Ringe, Punkte je Ring, 3); Ringe laufen entlang der Länge, die Punkte im Ring
  rundherum. `wrap=True` schliesst den Ring (ohne doppelte Naht), Kappen schliessen Anfang/Ende mit einem Polpunkt.
- Normalen glatt (flächengewichtet) über `normals()`; Nähte gibt es keine, weil Gitter geschlossen indiziert werden.
"""
from __future__ import annotations

import numpy as np


class Part:
    def __init__(self, v, f, uv=None):
        self.v = np.asarray(v, dtype=np.float64).reshape(-1, 3)
        self.f = np.asarray(f, dtype=np.int64).reshape(-1, 3)
        self.uv = None if uv is None else np.asarray(uv, dtype=np.float64).reshape(-1, 2)

    def copy(self):
        return Part(self.v.copy(), self.f.copy(), None if self.uv is None else self.uv.copy())

    @property
    def tris(self):
        return len(self.f)

    def transformed(self, m=None, t=(0, 0, 0)):
        v = self.v if m is None else self.v @ np.asarray(m, dtype=np.float64).T
        return Part(v + np.asarray(t, dtype=np.float64), self.f.copy(), self.uv)

    def scaled(self, s):
        s = np.asarray(s, dtype=np.float64)
        p = Part(self.v * s, self.f.copy(), self.uv)
        if np.prod(np.sign(s) if s.shape else [np.sign(s)]) < 0:
            p.f = p.f[:, ::-1].copy()
        return p

    def flipped(self):
        return Part(self.v.copy(), self.f[:, ::-1].copy(), self.uv)

    def signed_volume(self):
        a, b, c = self.v[self.f[:, 0]], self.v[self.f[:, 1]], self.v[self.f[:, 2]]
        return float(np.einsum("ij,ij->i", a, np.cross(b, c)).sum() / 6)

    def outward(self):
        """Für geschlossene Körper: Dreiecke so drehen, dass das Volumen positiv ist."""
        return self.flipped() if self.signed_volume() < 0 else self


def merge(parts):
    parts = [p for p in parts if p is not None and len(p.f)]
    if not parts:
        return None
    vs, fs, uvs, off = [], [], [], 0
    has_uv = all(p.uv is not None for p in parts)
    for p in parts:
        vs.append(p.v)
        fs.append(p.f + off)
        if has_uv:
            uvs.append(p.uv)
        off += len(p.v)
    return Part(np.vstack(vs), np.vstack(fs), np.vstack(uvs) if has_uv else None)


def normals(p: Part):
    v, f = p.v, p.f
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    n = np.zeros_like(v)
    for k in range(3):
        np.add.at(n, f[:, k], fn)
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    ln[ln == 0] = 1
    return n / ln


def grid(P, wrap=True, cap0=None, cap1=None, uv=None):
    """Gitter aus Ringen. P: (R, K, 3). cap0/cap1: Polpunkt (3,) oder None. Reihenfolge der Dreiecke: aussen = Ring
    gegen den Uhrzeigersinn gesehen in Richtung absteigender Ringe; bei Bedarf danach `outward()` oder `flipped()`."""
    P = np.asarray(P, dtype=np.float64)
    R, K = P.shape[:2]
    v = P.reshape(-1, 3)
    faces = []
    kk = K if wrap else K - 1
    for r in range(R - 1):
        for k in range(kk):
            k1 = (k + 1) % K
            a, b, c, d = r * K + k, r * K + k1, (r + 1) * K + k, (r + 1) * K + k1
            faces += [(a, c, b), (b, c, d)]
    v = list(v)
    uvl = None if uv is None else list(np.asarray(uv, dtype=np.float64).reshape(-1, 2))
    if cap0 is not None:
        i = len(v)
        v.append(np.asarray(cap0, dtype=np.float64))
        if uvl is not None:
            uvl.append(uvl[0])
        for k in range(kk):
            faces.append((i, k, (k + 1) % K))
    if cap1 is not None:
        i = len(v)
        v.append(np.asarray(cap1, dtype=np.float64))
        if uvl is not None:
            uvl.append(uvl[-2])
        base = (R - 1) * K
        for k in range(kk):
            faces.append((i, base + (k + 1) % K, base + k))
    return Part(np.array(v), np.array(faces), None if uvl is None else np.array(uvl))


def superellipse_ring(a, b, n=2.0, k=16, cx=0.0, cz=0.0, y=0.0, phase=0.0):
    """Ring in der x/z-Ebene (Höhe y): Halbachsen a (x) und b (z), Exponent n (2 = Ellipse, grösser = eckiger)."""
    t = np.linspace(0, 2 * np.pi, k, endpoint=False) + phase
    c, s = np.cos(t), np.sin(t)
    x = a * np.sign(c) * np.abs(c) ** (2 / n)
    z = b * np.sign(s) * np.abs(s) ** (2 / n)
    return np.stack([x + cx, np.full(k, y), z + cz], axis=1)


def loft_y(profile, k=16, n=2.0, close0=True, close1=True):
    """Körper entlang +y: profile = Liste (y, a, b[, cz]) mit Halbachsen a (x), b (z) und Versatz cz. Enden werden
    mit einem Polpunkt geschlossen (abgerundet, wenn das erste/letzte Profil klein ist)."""
    rings = []
    for row in profile:
        y, a, b = row[:3]
        cz = row[3] if len(row) > 3 else 0.0
        rings.append(superellipse_ring(a, b, n, k, cz=cz, y=y))
    P = np.array(rings)
    c0 = [0, profile[0][0], profile[0][3] if len(profile[0]) > 3 else 0] if close0 else None
    c1 = [0, profile[-1][0], profile[-1][3] if len(profile[-1]) > 3 else 0] if close1 else None
    return grid(P, True, c0, c1).outward()


def capsule_y(length, r0, r1=None, k=12, rings_body=4, rings_cap=3, bulge=None):
    """Weicher Stab von y=0 bis y=length: Halbkugeln an beiden Enden, Radius r0 → r1, `bulge(t)` (0…1) multipliziert
    den Radius entlang des Schafts (z. B. Wade, Oberarm)."""
    r1 = r0 if r1 is None else r1
    prof = []
    for i in range(rings_cap, 0, -1):  # untere Halbkugel
        th = (i / (rings_cap + 0.0)) * (np.pi / 2)
        prof.append((-r0 * np.sin(th) * 0.85, r0 * np.cos(th), r0 * np.cos(th)))
    for i in range(rings_body + 1):
        t = i / rings_body
        r = r0 + (r1 - r0) * t
        if bulge is not None:
            r *= bulge(t)
        prof.append((length * t, r, r))
    for i in range(1, rings_cap + 1):
        th = (i / (rings_cap + 0.0)) * (np.pi / 2)
        prof.append((length + r1 * np.sin(th) * 0.85, r1 * np.cos(th), r1 * np.cos(th)))
    prof = [p for p in prof if p[1] > 1e-4] or prof
    y0 = -r0 * 0.85
    y1 = length + r1 * 0.85
    rings = [superellipse_ring(a, b, 2, k, y=y) for y, a, b in prof]
    return grid(np.array(rings), True, [0, y0, 0], [0, y1, 0]).outward()


def ellipsoid(center, radii, ku=16, kv=10, deform=None):
    """Ellipsoid; `deform(d)` bekommt Einheitsrichtungen (n, 3) und liefert Radiusfaktoren (n,)."""
    cx, cy, cz = center
    rx, ry, rz = radii
    rings = []
    for i in range(1, kv):
        th = np.pi * i / kv
        phi = np.linspace(0, 2 * np.pi, ku, endpoint=False)
        d = np.stack([np.sin(th) * np.cos(phi), np.full(ku, np.cos(th)), np.sin(th) * np.sin(phi)], axis=1)
        rings.append(d)
    D = np.array(rings)
    flat = D.reshape(-1, 3)
    fac = deform(flat).reshape(D.shape[:2]) if deform is not None else np.ones(D.shape[:2])
    P = D * np.array([rx, ry, rz]) * fac[..., None] + np.array(center)
    top = np.array([cx, cy + ry * (deform(np.array([[0, 1, 0]]))[0] if deform else 1), cz])
    bot = np.array([cx, cy - ry * (deform(np.array([[0, -1, 0]]))[0] if deform else 1), cz])
    # Ringe laufen von oben nach unten: Kappe oben = cap0
    return grid(P, True, top, bot).outward()


def tube_path(points, radii, k=10, close=True, n=2.0, aspect=1.0, up=(0, 1, 0)):
    """Rohr entlang einer Punktfolge mit Radien je Punkt (Rahmen nach Bishop-Art über einen festen Hilfsvektor)."""
    pts = np.asarray(points, dtype=np.float64)
    radii = np.broadcast_to(np.asarray(radii, dtype=np.float64), (len(pts),))
    up = np.asarray(up, dtype=np.float64)
    rings = []
    for i, p in enumerate(pts):
        t = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        t /= np.linalg.norm(t)
        side = np.cross(t, up)
        if np.linalg.norm(side) < 1e-6:
            side = np.cross(t, [1, 0, 0])
        side /= np.linalg.norm(side)
        nrm = np.cross(side, t)
        ang = np.linspace(0, 2 * np.pi, k, endpoint=False)
        c, s = np.cos(ang), np.sin(ang)
        cx = np.sign(c) * np.abs(c) ** (2 / n)
        sy = np.sign(s) * np.abs(s) ** (2 / n)
        r = radii[i]
        rings.append(p + np.outer(cx * r, side) + np.outer(sy * r * aspect, nrm))
    cap0 = pts[0] if close else None
    cap1 = pts[-1] if close else None
    return grid(np.array(rings), True, cap0, cap1).outward()


def thicken(sheet_P, thickness, wrap=False):
    """Fläche (R, K, 3) zu einem geschlossenen dünnen Körper: zweite Lage entlang der Normalen nach innen, Ränder
    vernäht. Für Brillengläser, Mützenschild, Stirnband."""
    P = np.asarray(sheet_P, dtype=np.float64)
    R, K = P.shape[:2]
    top = grid(P, wrap)
    n = normals(top).reshape(R, K, 3)
    Q = P - n * thickness
    v = np.vstack([P.reshape(-1, 3), Q.reshape(-1, 3)])
    off = R * K
    faces = list(top.f) + list(top.f[:, ::-1] + off)
    def ring_edge(idx):
        for a, b in zip(idx[:-1], idx[1:]):
            faces.append((a, b, b + off))
            faces.append((a, b + off, a + off))
    kk = list(range(K)) + ([0] if wrap else [])
    ring_edge([0 * K + k for k in kk][::-1])
    ring_edge([(R - 1) * K + k for k in kk])
    if not wrap:
        ring_edge([r * K + 0 for r in range(R)])
        ring_edge([r * K + (K - 1) for r in range(R)][::-1])
    return Part(v, np.array(faces)).outward()


def split_faces(p: Part, pred):
    """Teilt ein Mesh nach Flächenmitte: pred(centers (m,3)) → bool (m,). Liefert (Teil True, Teil False), jeweils
    mit eigenen Punkten (gleiche Geometrie, die Naht ist unsichtbar)."""
    c = p.v[p.f].mean(axis=1)
    mask = np.asarray(pred(c), dtype=bool)
    return subset(p, mask), subset(p, ~mask)


def subset(p: Part, mask):
    f = p.f[mask]
    if not len(f):
        return None
    used = np.unique(f)
    remap = -np.ones(len(p.v), dtype=np.int64)
    remap[used] = np.arange(len(used))
    return Part(p.v[used], remap[f], None if p.uv is None else p.uv[used])


def basis_y(direction, hint):
    """Rotationsmatrix, deren y-Achse `direction` ist und deren x-Achse möglichst nahe an `hint` liegt."""
    y = np.asarray(direction, dtype=np.float64)
    y = y / np.linalg.norm(y)
    x = np.asarray(hint, dtype=np.float64) - y * np.dot(hint, y)
    if np.linalg.norm(x) < 1e-6:
        x = np.cross(y, [0, 0, 1])
    x /= np.linalg.norm(x)
    z = np.cross(x, y)
    return np.stack([x, y, z], axis=1)


def rot_x(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def rot_y(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_z(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
