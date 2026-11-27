"""Schritt 4c: Wahrzeichen als prozedurale Modelle (Eiffelturm, Notre-Dame, Big Ben, London Eye, Tower Bridge,
Rialto, Accademia, Salute …).

Höhenmodelle und Grundrisse liefern Wahrzeichen nur als Klotz (Gitterturm = Säule aus dem Oberflächenmodell, Kuppel =
Flachdach). Dieses Modul baut die zentralen Wahrzeichen eines Gebiets als vereinfachte, aber klar erkennbare Modelle
nach Massen aus offenen Quellen (Literatur, Wikipedia, OSM-Umrisse für Lage und Ausrichtung) und rechnet das Licht vor
wie bridges.py (Umgebungsverdeckung, Himmel, Sonnenschatten gegen Gelände, Wasser, nahe Gebäude).

Gebietsdatei, Feld "landmarks": Liste, je Wahrzeichen
  type        Bauart (siehe TYPES unten), name, slug (a–z, 0–9, _ → Meshname lm_<slug>)
  at_lv95     Bezugspunkt [E, N] im System "crs" (Mitte bzw. Mitte der Westfassade, siehe Typ)
  axis_deg    Azimut der lokalen y-Achse (Grad, im Uhrzeigersinn ab Nord): Blickrichtung der Hauptfassade bzw.
              Brückenachse bzw. Ebene des Riesenrads
  base_m      Fusshöhe über der Wasserfläche (Standard: Geländemodell am Bezugspunkt)
  clear_box_m [halbe Breite x, halbe Tiefe y] (lokal, gedreht) bzw. clear_lv95 (Ring): Grundrisse, deren Fläche zu
              ≥ 30 % darin liegt, entfallen in buildings_footprints.py, Bäume darin in trees.py (der „Klotz“ aus dem
              Oberflächenmodell verschwindet so). Standard: Ausdehnung des Typs
  colors      {Materialname: [r, g, b]} ersetzt Farben (0–1); weitere Parameter je Typ (Standardwerte im Code)
  source      Text für Bericht und meta.json (Masse, Herkunft)

Typen: eiffel_tower, cathedral (Notre-Dame), tower (Big Ben, Victoria Tower, Campanile), gothic_block (Parlament),
ferris_wheel (London Eye), tower_bridge (Aufbauten auf einer Brücke aus bridges.py), arch_bridge (Steinbogen, optional
mit Ladenzeilen wie Rialto), truss_arch_bridge (Holzbogen Accademia), domed_church (Salute, St Paul's),
drawbridge_gallows (Galgen der Magere Brug).

Ergebnis (für alle Stufen gleich): build/<area>/landmarks/landmarks.npz (je Wahrzeichen lm_<slug>__v/__f/__n/__uv),
lm_<slug>.jpg (Texturatlas), meta.json. export.py hängt sie unter /Scene/Landmarks an.
Aufruf: .venv/bin/python landmarks.py areas/<area>.json [--procs 8] [--rays 7] [--only slug,slug]
Nach bake.py (nahe Gebäude verdecken) und bridges.py; vor export.py.
"""
import os
import sys

if "--device" not in sys.argv:
    os.environ["CUDA_VISIBLE_DEVICES"] = ""  # nur CPU

import argparse  # noqa: E402
import json  # noqa: E402
import math  # noqa: E402
from pathlib import Path  # noqa: E402

import mapbox_earcut as earcut  # noqa: E402
import numpy as np  # noqa: E402
from shapely.geometry import Polygon  # noqa: E402

from bridges import MeshBuilder, beam3d  # noqa: E402

TEX_M = 0.15
ATLAS_MAX = 2048

# ----------------------------------------------------------------------------- Materialien

DARK = (0.10, 0.11, 0.13)


def mat_table(defaults, cfg):
    """defaults: {name: {"color": …, "pattern": …, …}} → (Liste, {name: index}) mit Farben aus cfg["colors"]."""
    names = list(defaults)
    lst = []
    for n in names:
        m = dict(defaults[n])
        if n in cfg.get("colors", {}):
            m["color"] = cfg["colors"][n]
        lst.append(m)
    return lst, {n: i for i, n in enumerate(names)}


def _rng(a, b):
    return (np.sin(a * 12.9898 + b * 78.233) * 43758.5453) % 1.0


def albedo_fn(mats, base_z):
    """Albedo je Texel aus Materialliste (Muster in Weltlage, z relativ zum Fuss des Wahrzeichens)."""
    cols = np.array([m["color"] for m in mats], np.float32)

    def f(_b, mat, P, N):
        alb = cols[mat].copy()
        vert = np.abs(N[:, 2]) < 0.5
        tx = P[:, 0] * -N[:, 1] + P[:, 1] * N[:, 0]
        z = P[:, 2] - base_z
        for k, m in enumerate(mats):
            sel = mat == k
            if not sel.any():
                continue
            pat = m.get("pattern", "plain")
            t, zz, v = tx[sel], z[sel], vert[sel]
            fac = np.ones(sel.sum(), np.float32)
            if pat in ("stone", "windows", "ribs"):
                row = np.floor(zz / 0.6)
                col = np.floor((t + row * 0.5) / 1.2)
                jz, jx = (zz / 0.6) % 1.0, ((t + row * 0.5) / 1.2) % 1.0
                fac *= np.where(v, 0.93 + 0.12 * _rng(row, col), 1.0)
                fac *= np.where(v & ((jz < 0.06) | (jx < 0.03)), 0.86, 1.0)
            if pat == "brick":
                row = np.floor(zz / 0.22)
                col = np.floor((t + row * 0.12) / 0.5)
                fac *= np.where(v, 0.88 + 0.22 * _rng(row, col), 1.0)
                fac *= np.where(v & (((zz / 0.22) % 1.0) < 0.12), 0.82, 1.0)
            if pat == "ribs":  # gotisches Masswerk: senkrechte Stäbe, waagrechte Gesimse
                dx = m.get("rib_dx", 1.8)
                fac *= np.where(v & (((t / dx) % 1.0) < 0.12), 1.12, 1.0)
                fac *= np.where(v & (((zz / m.get("rib_dz", 4.0)) % 1.0) < 0.06), 1.1, 1.0)
            if pat == "roof":  # Blech/Blei: Falze auf geneigten Flächen
                fac *= np.where(((t / 0.7) % 1.0) < 0.1, 0.85, 1.0)
            if pat == "tiles":
                fac *= np.where(((zz / 0.35) % 1.0) < 0.18, 0.8, 1.0) * (0.92 + 0.12 * _rng(np.floor(zz / 0.35),
                                                                                             np.floor(t / 0.3)))
            if pat == "wood":
                fac *= 0.86 + 0.24 * _rng(np.floor(t / 0.22), np.floor(zz / 3.0))
            if pat == "truss":
                hgt = np.clip((zz - m.get("t_z0", 0)) / max(m.get("t_h", 4), 0.5), 0, 1)
                Pm = m.get("t_dx", 4.0)
                d1, d2 = ((t + hgt * Pm / 2) / Pm) % 1.0, ((t - hgt * Pm / 2) / Pm) % 1.0
                member = (np.minimum(d1, 1 - d1) < 0.06) | (np.minimum(d2, 1 - d2) < 0.06) | (hgt < 0.12) | \
                         (hgt > 0.88)
                fac *= np.where(v & ~member, 0.35, 1.0)
            sub = alb[sel] * fac[:, None]
            if pat == "windows":
                for dx, w, z0, z1 in m.get("win", []):
                    ph = ((t + m.get("win_off", 0.0)) / dx) % 1.0
                    ww = w / dx
                    inwin = v & (np.abs(ph - 0.5) < ww / 2) & (zz > z0) & (zz < z1)
                    # Spitzbogen oben: Breite nimmt im obersten Fünftel ab
                    top = (zz - z0) / max(z1 - z0, 0.1)
                    shrink = np.where(top > 0.8, 1 - (top - 0.8) / 0.2, 1.0)
                    inwin &= np.abs(ph - 0.5) < ww / 2 * np.sqrt(np.clip(shrink, 0, 1))
                    sub[inwin] = np.array(m.get("win_color", DARK), np.float32)
            alb[sel] = sub
        return alb
    return f


# ----------------------------------------------------------------------------- lokaler Baukasten

class LB:
    """Baukasten in lokalen Koordinaten (x rechts, y vorne, z oben ab Fuss); transform() → Szene."""

    def __init__(self):
        self.mb = MeshBuilder()

    def tri(self, a, b, c, n, m):
        self.mb.tri(a, b, c, np.asarray(n, float), m)

    def quad(self, a, b, c, d, n, m):
        self.mb.quad(a, b, c, d, np.asarray(n, float), m)

    def prism(self, ring, z0, z1, m, top=True, bottom=False):
        self.mb.prism(ring, z0, z1, m, np.zeros(2), top=top)
        if bottom:
            r = np.asarray(ring, float)
            idx = earcut.triangulate_float64(r, np.array([len(r)], np.uint32)).reshape(-1, 3)
            for t in idx:
                self.tri([*r[t[0]], z0], [*r[t[1]], z0], [*r[t[2]], z0], [0, 0, -1], m)

    def box(self, x0, y0, x1, y1, z0, z1, m, top=True, bottom=False):
        self.prism([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], z0, z1, m, top, bottom)

    def boxc(self, cx, cy, hx, hy, z0, z1, m, top=True, bottom=False):
        self.box(cx - hx, cy - hy, cx + hx, cy + hy, z0, z1, m, top, bottom)

    @staticmethod
    def ngon(cx, cy, r, n, rot=0.0):
        a = rot + np.arange(n) * 2 * np.pi / n
        return np.column_stack([cx + r * np.cos(a), cy + r * np.sin(a)])

    def loft(self, rings, m, center=None, cap_top=True, cap_bottom=False):
        """rings: [(ring (k×2), z), …] von unten nach oben, gleiche Eckenzahl."""
        R = [np.column_stack([np.asarray(r, float), np.full(len(r), z)]) for r, z in rings]
        k = len(R[0])
        for a, b in zip(R[:-1], R[1:]):
            c3 = np.array([*a[:, :2].mean(axis=0), (a[0, 2] + b[0, 2]) / 2]) if center is None else \
                np.asarray(center, float)
            for i in range(k):
                j = (i + 1) % k
                mid = (a[i] + a[j] + b[i] + b[j]) / 4
                hint = mid - c3
                if center is None:
                    hint[2] = 0.0
                    if np.linalg.norm(hint) < 1e-6:
                        hint = np.array([0, 0, 1.0])
                pts = [a[i], a[j], b[j], b[i]]
                if np.linalg.norm(b[i] - b[j]) < 1e-6:     # Spitze
                    self.tri(a[i], a[j], b[i], hint, m)
                else:
                    self.quad(*pts, hint, m)
        for ring, up in ((R[-1], 1.0), (R[0], -1.0)) if cap_bottom else ((R[-1], 1.0),):
            if not cap_top and up > 0:
                continue
            r2 = ring[:, :2]
            if Polygon(r2).area < 1e-4:
                continue
            idx = earcut.triangulate_float64(r2.astype(np.float64), np.array([len(r2)], np.uint32)).reshape(-1, 3)
            for t in idx:
                self.tri(ring[t[0]], ring[t[1]], ring[t[2]], [0, 0, up], m)

    def cyl(self, cx, cy, r, z0, z1, n, m, top=True, r1=None, rot=0.0):
        self.loft([(self.ngon(cx, cy, r, n, rot), z0), (self.ngon(cx, cy, r if r1 is None else r1, n, rot), z1)],
                  m, cap_top=top)

    def cone(self, cx, cy, r, z0, z1, n, m, rot=0.0):
        self.loft([(self.ngon(cx, cy, r, n, rot), z0), (self.ngon(cx, cy, 0.0, n, rot), z1)], m, cap_top=False)

    def pyramid_rect(self, cx, cy, hx, hy, z0, z1, m):
        r = [(cx - hx, cy - hy), (cx + hx, cy - hy), (cx + hx, cy + hy), (cx - hx, cy + hy)]
        self.loft([(r, z0), ([(cx, cy)] * 4, z1)], m, cap_top=False)

    def dome(self, cx, cy, r, z0, h, m, n=16, rings=6, open_top=0.0):
        """Kuppel (Halbellipsoid, Höhe h); open_top: Radius der Öffnung oben für eine Laterne."""
        phis = np.linspace(0, np.pi / 2, rings + 1)
        R = []
        for p in phis:
            rr = r * math.cos(p)
            if open_top and rr < open_top:
                rr = open_top
                R.append((self.ngon(cx, cy, rr, n), z0 + h * math.sin(math.acos(min(1, open_top / r)))))
                break
            R.append((self.ngon(cx, cy, rr, n), z0 + h * math.sin(p)))
        self.loft(R, m, center=(cx, cy, z0), cap_top=bool(open_top))

    def beam(self, p0, p1, w, h, m):
        beam3d(self.mb, p0, p1, w, h, m)

    def gable(self, x0, y0, x1, y1, z0, h, m_roof, m_wall, ridge="y", over=0.3):
        """Satteldach über einem Rechteck (Traufe z0, First z0 + h); Giebeldreiecke in m_wall."""
        if ridge == "y":
            xm = (x0 + x1) / 2
            a, b = (x0 - over, y0 - over), (x1 + over, y1 + over)
            self.quad([a[0], a[1], z0], [a[0], b[1], z0], [xm, b[1], z0 + h], [xm, a[1], z0 + h], [-h, 0, xm - a[0]],
                      m_roof)
            self.quad([b[0], a[1], z0], [b[0], b[1], z0], [xm, b[1], z0 + h], [xm, a[1], z0 + h], [h, 0, b[0] - xm],
                      m_roof)
            for yy, s in ((y0, -1), (y1, 1)):
                self.tri([x0, yy, z0], [x1, yy, z0], [xm, yy, z0 + h], [0, s, 0], m_wall)
        else:
            ym = (y0 + y1) / 2
            a, b = (x0 - over, y0 - over), (x1 + over, y1 + over)
            self.quad([a[0], a[1], z0], [b[0], a[1], z0], [b[0], ym, z0 + h], [a[0], ym, z0 + h], [0, -h, ym - a[1]],
                      m_roof)
            self.quad([a[0], b[1], z0], [b[0], b[1], z0], [b[0], ym, z0 + h], [a[0], ym, z0 + h], [0, h, b[1] - ym],
                      m_roof)
            for xx, s in ((x0, -1), (x1, 1)):
                self.tri([xx, y0, z0], [xx, y1, z0], [xx, ym, z0 + h], [s, 0, 0], m_wall)

    def opening(self, c, nrm, up, w, h, m, arch="round", off=0.04):
        """Dunkle Öffnung (Fenster, Tor, Arkade) als flaches Polygon knapp vor einer Fläche; c = Mitte unten,
        nrm = Aussennormale der Fläche."""
        c, out, up = np.asarray(c, float), np.asarray(nrm, float), np.asarray(up, float)
        out = out / np.linalg.norm(out)
        right = np.cross(up, out)
        right /= np.linalg.norm(right)
        c = c + out * off
        pts = [(-w / 2, 0), (w / 2, 0)]
        if arch == "round":
            r = w / 2
            hs = max(h - r, 0)
            pts += [(w / 2, hs)] + [(r * math.cos(a), hs + r * math.sin(a)) for a in np.linspace(0, np.pi, 9)[1:-1]] \
                + [(-w / 2, hs)]
        elif arch == "pointed":
            r = w * 0.8
            hs = max(h - math.sqrt(r * r - (r - w / 2) ** 2), 0)
            right_arc = [((w / 2 - r) + r * math.cos(a), hs + r * math.sin(a))
                         for a in np.linspace(0, math.acos((r - w / 2) / r), 5)]
            pts += right_arc[:-1] + [(0, hs + math.sqrt(r * r - (r - w / 2) ** 2))] + \
                [(-x, y) for x, y in right_arc[::-1][1:]]
        elif arch == "circle":
            r = w / 2
            pts = [(r * math.cos(a), r + r * math.sin(a)) for a in np.linspace(0, 2 * np.pi, 17)[:-1]]
        else:
            pts += [(w / 2, h), (-w / 2, h)]
        P = np.array(pts)
        idx = earcut.triangulate_float64(P.astype(np.float64), np.array([len(P)], np.uint32)).reshape(-1, 3)
        for t in idx:
            self.tri(*[c + right * P[i, 0] + up * P[i, 1] for i in t], out, m)

    def arrays(self):
        return self.mb.arrays()


FACES = {"+y": ((1, 0, 0), (0, 1, 0)), "-y": ((-1, 0, 0), (0, -1, 0)), "+x": ((0, -1, 0), (1, 0, 0)),
         "-x": ((0, 1, 0), (-1, 0, 0))}  # Richtung „rechts“ auf der Fläche, Normale


def face_openings(lb, cx, cy, hx, hy, z, w, h, m, n=1, arch="pointed", sides=("+y", "-y", "+x", "-x"), dx=None):
    """n Öffnungen je Seite eines Rechtecks (Mitte cx, cy, halbe Seiten hx, hy) ab Höhe z."""
    for s in sides:
        right, nrm = FACES[s]
        half = hx if s in ("+y", "-y") else hy
        cxs = cx + nrm[0] * hx
        cys = cy + nrm[1] * hy
        step = dx or (2 * half / n)
        for k in range(n):
            u = -step * (n - 1) / 2 + k * step
            lb.opening([cxs + right[0] * u, cys + right[1] * u, z], (nrm[0], nrm[1], 0), (0, 0, 1), w, h, m, arch)


# ----------------------------------------------------------------------------- Typen

def eiffel_tower(lb, c):
    """Eiffelturm (Paris, 1889): 330 m mit Antennen, Grundquadrat 125 m zwischen den Pfeileraussenkanten, Plattformen
    auf 57,6 m (70,7 m Quadrat, Ring), 115,7 m (40,9 m Quadrat) und 276 m; vier Pfeiler als Gitterstützen mit Gurten,
    Diagonalen und Riegeln, die sich an der zweiten Plattform zu einem Schaft vereinen; Zierbögen unter der ersten Plattform."""
    mats, M = mat_table({"steel": {"color": (0.42, 0.35, 0.28)}, "deck": {"color": (0.47, 0.40, 0.32)},
                         "glass": {"color": (0.30, 0.33, 0.35)}, "top": {"color": (0.55, 0.50, 0.44)}}, c)
    Wz = [(0, 62.5), (30, 48.0), (57.6, 35.8), (85, 27.0), (115.7, 20.5), (150, 14.5), (200, 10.0), (240, 7.8),
          (276, 6.2), (300, 4.4)]
    Lz = [(0, 26.0), (57.6, 16.0), (100, 15.5), (115.7, 20.5)]
    w = lambda z: float(np.interp(z, *zip(*Wz)))  # noqa: E731
    lw = lambda z: float(np.interp(z, *zip(*Lz)))  # noqa: E731
    ch = lambda z: float(np.interp(z, [0, 115, 300], [2.6, 1.5, 0.8]))  # noqa: E731
    S = M["steel"]
    zs = np.unique(np.r_[np.linspace(0, 57.6, 6), np.linspace(57.6, 115.7, 6)])
    for sx in (-1, 1):
        for sy in (-1, 1):
            def corners(z):
                a, b = w(z), w(z) - lw(z)
                return [np.array([sx * a, sy * a, z]), np.array([sx * b, sy * a, z]),
                        np.array([sx * b, sy * b, z]), np.array([sx * a, sy * b, z])]
            for z0, z1 in zip(zs[:-1], zs[1:]):
                c0, c1 = corners(z0), corners(z1)
                t = ch((z0 + z1) / 2)
                for k in range(4):
                    j = (k + 1) % 4
                    lb.beam(c0[k], c1[k], t, t, S)
                    lb.beam(c0[k], c1[j], t * 0.45, t * 0.45, S)
                    lb.beam(c0[j], c1[k], t * 0.45, t * 0.45, S)
                    lb.beam(c1[k], c1[j], t * 0.5, t * 0.6, S)
            # Fuss (Mauerwerkssockel)
            a = w(0)
            lb.box(min(sx * a, sx * (a - lw(0))) - 1, min(sy * a, sy * (a - lw(0))) - 1,
                   max(sx * a, sx * (a - lw(0))) + 1, max(sy * a, sy * (a - lw(0))) + 1, -1, 2.5, M["top"])
    # Schaft über der zweiten Plattform
    zs2 = np.unique(np.r_[np.linspace(115.7, 274, 14), np.linspace(282, 300, 3)])
    for z0, z1 in zip(zs2[:-1], zs2[1:]):
        c0 = [np.array([sx * w(z0), sy * w(z0), z0]) for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
        c1 = [np.array([sx * w(z1), sy * w(z1), z1]) for sx, sy in ((1, 1), (-1, 1), (-1, -1), (1, -1))]
        t = ch((z0 + z1) / 2)
        for k in range(4):
            j = (k + 1) % 4
            lb.beam(c0[k], c1[k], t, t, S)
            lb.beam(c0[k], c1[j], t * 0.45, t * 0.45, S)
            lb.beam(c0[j], c1[k], t * 0.45, t * 0.45, S)
            lb.beam(c1[k], c1[j], t * 0.5, t * 0.5, S)
    # Zierbögen unter der ersten Plattform, mit Stützen bis zur Plattform
    zsp, zap = 9.0, 39.5
    A = w(zsp) - lw(zsp)
    for rot in range(4):
        ca, sa = math.cos(rot * np.pi / 2), math.sin(rot * np.pi / 2)
        R2 = lambda x, y, z: np.array([ca * x - sa * y, sa * x + ca * y, z])  # noqa: E731
        ts = np.linspace(-1, 1, 17)
        pts = []
        for t in ts:
            z = zsp + (zap - zsp) * math.sqrt(max(0.0, 1 - t * t))
            pts.append(R2(t * A, w(z) - 0.6, z))
        for p0, p1 in zip(pts[:-1], pts[1:]):
            lb.beam(p0, p1, 1.6, 1.3, S)
        for t in np.linspace(-0.8, 0.8, 7):
            z = zsp + (zap - zsp) * math.sqrt(max(0.0, 1 - t * t))
            lb.beam(R2(t * A, w(z) - 0.6, z), R2(t * A, w(52.5) - 0.6, 52.5), 0.7, 0.7, S)
    # Plattformen
    D = M["deck"]
    o1, i1 = 35.4, 22.0
    for x0, y0, x1, y1 in ((-o1, i1, o1, o1), (-o1, -o1, o1, -i1), (-o1, -i1, -i1, i1), (i1, -i1, o1, i1)):
        lb.box(x0, y0, x1, y1, 52.5, 57.6, D, bottom=True)
    lb.box(-o1 + 2, -o1 + 2, o1 - 2, -o1 + 9, 57.6, 61.5, M["glass"])           # Pavillons
    lb.box(-o1 + 2, o1 - 9, o1 - 2, o1 - 2, 57.6, 61.5, M["glass"])
    lb.boxc(0, 0, 20.5, 20.5, 112.5, 115.7, D, bottom=True)
    lb.boxc(0, 0, 11.0, 11.0, 115.7, 120.5, M["glass"])
    lb.boxc(0, 0, 9.3, 9.3, 273.5, 276.2, D, bottom=True)
    lb.boxc(0, 0, 7.0, 7.0, 276.2, 282.0, M["glass"])
    lb.boxc(0, 0, 4.6, 4.6, 299.0, 304.0, M["top"])
    lb.boxc(0, 0, 3.0, 3.0, 304.0, 311.0, M["top"])
    lb.cyl(0, 0, 1.3, 311.0, 322.0, 8, M["top"], r1=0.8)
    lb.cyl(0, 0, 0.5, 322.0, 330.0, 6, M["top"], r1=0.2)
    return mats


def cathedral(lb, c):
    """Gotische Kathedrale wie Notre-Dame de Paris: Westfassade (lokal y = 0, Blick nach +y) 41 m breit mit zwei
    Türmen 69 m, Fensterrose, drei Portale, Königsgalerie; Langhaus nach −y mit Seitenschiffen, Querhaus, Chor mit
    Apsis und Strebebögen, Dachreiter (Vierungsturm) 96 m. Masse in m, alle Werte überschreibbar."""
    mats, M = mat_table({
        "stone": {"color": (0.80, 0.76, 0.66), "pattern": "windows",
                  "win": [[7.0, 3.0, 23.0, 32.0], [7.0, 3.2, 5.0, 15.5]]},
        "facade": {"color": (0.82, 0.78, 0.68), "pattern": "stone"},
        "roof": {"color": (0.40, 0.44, 0.48), "pattern": "roof"},
        "dark": {"color": DARK}, "rose": {"color": (0.22, 0.22, 0.30)},
        "gold": {"color": (0.78, 0.64, 0.32)}}, c)
    L = c.get("length_m", 128.0)
    hw = c.get("facade_w_m", 41.0) / 2
    tw = c.get("tower_m", 69.0)
    ridge = c.get("ridge_m", 43.0)
    wall = c.get("wall_m", 33.0)
    aisle = c.get("aisle_m", 21.0)
    nave_hw, out_hw = 6.5, 24.0
    fd = 12.5                                   # Tiefe des Fassadenblocks
    St, F, R = M["stone"], M["facade"], M["roof"]
    # Fassade: Mittelteil bis Galerie, Türme
    lb.box(-hw, -fd, hw, 0, 0, 45.0, F)
    for s in (-1, 1):
        x0, x1 = sorted((s * hw, s * 6.3))
        lb.box(x0, -fd, x1, 0, 45.0, tw, F)
        lb.box(x0 - 0.4, -fd - 0.4, x1 + 0.4, 0.4, tw - 1.2, tw, F)       # Gesims oben
        for k in (-1, 1):                                                  # Schallöffnungen
            lb.opening([(x0 + x1) / 2 + k * 3.4, 0, 49.0], (0, 1, 0), (0, 0, 1), 2.4, 15.0, M["dark"], "pointed")
            lb.opening([x0 if s < 0 else x1, -fd / 2 + k * 3.0, 49.0], (s, 0, 0), (0, 0, 1), 2.4, 15.0,
                       M["dark"], "pointed")
    # Portale, Königsgalerie, Rose, Galerie
    for xx, ww in ((-13.2, 7.5), (0, 8.5), (13.2, 7.5)):
        lb.opening([xx, 0, 0.0], (0, 1, 0), (0, 0, 1), ww, 13.0, M["dark"], "pointed")
    lb.box(-hw, -0.1, hw, 0.6, 16.5, 17.0, F)
    for k in range(28):
        lb.opening([-hw + 1.0 + k * (2 * hw - 2) / 27, 0.6, 17.3], (0, 1, 0), (0, 0, 1), 0.8, 3.0, M["dark"], "round")
    lb.opening([0, 0, 21.0], (0, 1, 0), (0, 0, 1), 9.6, 9.6, M["rose"], "circle")
    for s in (-1, 1):
        lb.opening([s * 13.2, 0, 22.0], (0, 1, 0), (0, 0, 1), 4.0, 8.0, M["dark"], "pointed")
    for k in range(12):
        lb.opening([-hw + 2 + k * (2 * hw - 4) / 11, 0, 36.0], (0, 1, 0), (0, 0, 1), 1.6, 7.0, M["dark"], "pointed")
    # Langhaus und Chor (Mittelschiff), Seitenschiffe
    yA = -L + 6.5
    lb.box(-nave_hw, yA, nave_hw, -fd, 0, wall, St, top=False)
    lb.gable(-nave_hw, yA, nave_hw, -fd + 0.01, wall, ridge - wall, R, St, ridge="y")
    ap = [(nave_hw * math.cos(a), yA + nave_hw * math.sin(a) * -1) for a in np.linspace(0, np.pi, 7)]
    lb.prism(ap[::-1], 0, wall, St, top=False)
    lb.loft([(ap[::-1], wall), ([(0, yA)] * len(ap), ridge - 1.0)], R, cap_top=False)
    ya2 = -L + 18
    lb.box(-out_hw, ya2, -nave_hw, -fd, 0, aisle, St)
    lb.box(nave_hw, ya2, out_hw, -fd, 0, aisle, St)
    ap2 = [(18.0 * math.cos(a), ya2 - 18.0 * math.sin(a)) for a in np.linspace(0, np.pi, 9)]
    lb.prism([(out_hw, ya2)] + ap2 + [(-out_hw, ya2)], 0, aisle - 2, St)
    # Pultdächer der Seitenschiffe
    for s in (-1, 1):
        xo, xi = s * out_hw, s * nave_hw
        lb.quad([xo, ya2, aisle], [xo, -fd, aisle], [xi, -fd, aisle + 4], [xi, ya2, aisle + 4], [s * 4, 0, 18], R)
    # Querhaus
    yc = c.get("crossing_y_m", -60.0)
    lb.box(-out_hw - 1.5, yc - 7, out_hw + 1.5, yc + 7, 0, wall, St, top=False)
    lb.gable(-out_hw - 1.5, yc - 7, out_hw + 1.5, yc + 7, wall, ridge - wall, R, St, ridge="x")
    for s in (-1, 1):
        lb.opening([s * (out_hw + 1.5), yc, 15.0], (s, 0, 0), (0, 0, 1), 9.0, 9.0,
                   M["rose"], "circle")
    # Strebebögen am Chor und Langhaus
    for y in np.r_[np.arange(yc - 12, yA, -7.0), np.arange(-fd - 6, yc + 9, -7.0)]:
        for s in (-1, 1):
            lb.box(s * out_hw - 0.9, y - 0.9, s * out_hw + 0.9, y + 0.9, 0, aisle + 6, St)
            lb.cone(s * out_hw, y, 1.0, aisle + 6, aisle + 10, 4, St, rot=np.pi / 4)
            lb.beam([s * out_hw, y, aisle + 5], [s * nave_hw, y, wall - 3], 0.7, 1.0, St)
    # Dachreiter
    zr = ridge - 1.0
    lb.cyl(0, yc, 3.6, zr, zr + 10, 8, R, rot=np.pi / 8)
    lb.cone(0, yc, 3.6, zr + 10, c.get("spire_m", 96.0), 8, R, rot=np.pi / 8)
    lb.beam([0, yc, c.get("spire_m", 96.0) - 0.5], [0, yc, c.get("spire_m", 96.0) + 2.5], 0.25, 0.25, M["gold"])
    return mats


def tower(lb, c):
    """Quadratischer Turm (Big Ben/Elizabeth Tower, Victoria Tower, Campanile di San Marco): Stufen "stages"
    [{h, w, mat, openings: [n, w, h], clock: r}], Dach "roof" {type: pyramid|spire|flat|lantern_spire, h},
    "pinnacles" (Höhe der Eckfialen), "turrets" {r, h} (achteckige Ecktürme bis über den Schaft)."""
    mats, M = mat_table({
        "wall": {"color": c.get("wall_color", (0.80, 0.70, 0.50)), "pattern": c.get("wall_pattern", "ribs")},
        "upper": {"color": c.get("upper_color", c.get("wall_color", (0.80, 0.70, 0.50))), "pattern": "stone"},
        "roof": {"color": c.get("roof_color", (0.30, 0.33, 0.36)), "pattern": "roof"},
        "dark": {"color": DARK}, "clock": {"color": (0.92, 0.90, 0.82)}, "gold": {"color": (0.82, 0.66, 0.30)}}, c)
    z = 0.0
    w0 = c.get("w", 12.0)
    for st in c.get("stages", [{"h": 60}]):
        w = st.get("w", w0) / 2
        m = M[st.get("mat", "wall")]
        lb.boxc(0, 0, w, w, z, z + st["h"], m)
        if st.get("cornice"):
            lb.boxc(0, 0, w + st["cornice"], w + st["cornice"], z + st["h"] - 0.8, z + st["h"], m)
        if st.get("openings"):
            n, ow, oh = st["openings"]
            face_openings(lb, 0, 0, w, w, z + (st["h"] - oh) / 2, ow, oh, M["dark"], n=n,
                          arch=st.get("arch", "pointed"), dx=st.get("open_dx"))
        if st.get("clock"):
            r = st["clock"]
            for s in FACES:
                right, nrm = FACES[s]
                cc = np.array([nrm[0] * w, nrm[1] * w, z + st["h"] / 2 - r])
                lb.opening(cc - np.array([0, 0, 0.35]), (nrm[0], nrm[1], 0), (0, 0, 1), 2 * r + 0.7, 2 * r + 0.7,
                           M["gold"], "circle", off=0.03)
                lb.opening(cc, (nrm[0], nrm[1], 0), (0, 0, 1), 2 * r, 2 * r, M["clock"], "circle", off=0.08)
                right = np.cross([0, 0, 1], [nrm[0], nrm[1], 0])
                hub = cc + np.array([0, 0, r]) + np.array(nrm) * 0.14
                lb.beam(hub, hub + np.array([0, 0, r * 0.75]), 0.22, 0.05, M["dark"])
                lb.beam(hub, hub + np.array(right) * r * 0.5 + np.array([0, 0, -r * 0.2]), 0.28, 0.05, M["dark"])
        z += st["h"]
        w0 = st.get("w", w0)
    w = w0 / 2
    tur = c.get("turrets")
    if tur:
        for sx in (-1, 1):
            for sy in (-1, 1):
                lb.cyl(sx * (w - tur["r"] * 0.4), sy * (w - tur["r"] * 0.4), tur["r"], z - tur.get("below", 30), z +
                       tur["h"], 8, M["wall"], rot=np.pi / 8)
                lb.cone(sx * (w - tur["r"] * 0.4), sy * (w - tur["r"] * 0.4), tur["r"] * 1.05, z + tur["h"],
                        z + tur["h"] + tur.get("cap", 4.0), 8, M["roof"], rot=np.pi / 8)
    rf = c.get("roof", {"type": "pyramid", "h": 10})
    if rf["type"] == "pyramid":
        lb.pyramid_rect(0, 0, w + 0.3, w + 0.3, z, z + rf["h"], M["roof"])
        top = z + rf["h"]
    elif rf["type"] == "lantern_spire":  # Big Ben: steiles Dach, Laterne, Nadel
        hl = rf.get("h1", 9.0)
        lb.loft([(LB.ngon(0, 0, (w + 0.3) * 1.414, 4, np.pi / 4), z), (LB.ngon(0, 0, w * 0.55 * 1.414, 4, np.pi / 4),
                                                                         z + hl)], M["roof"], cap_top=True)
        lb.boxc(0, 0, w * 0.45, w * 0.45, z + hl, z + hl + 3.0, M["gold"])
        face_openings(lb, 0, 0, w * 0.45, w * 0.45, z + hl + 0.4, 1.0, 2.2, M["dark"], n=2)
        lb.pyramid_rect(0, 0, w * 0.5, w * 0.5, z + hl + 3.0, z + rf["h"], M["roof"])
        top = z + rf["h"]
        for k, (dx, dy) in enumerate(((1, 0), (0, 1), (-1, 0), (0, -1))):   # Gauben
            lb.pyramid_rect(dx * w * 0.75, dy * w * 0.75, 0.9, 0.9, z + 1.0, z + 4.5, M["gold"])
    elif rf["type"] == "spire":
        lb.cone(0, 0, (w + 0.2) * 1.414, z, z + rf["h"], 4, M["roof"], rot=np.pi / 4)
        top = z + rf["h"]
    else:
        lb.boxc(0, 0, w + 0.4, w + 0.4, z, z + 1.0, M["upper"])
        top = z + 1.0
    if rf.get("finial"):
        lb.beam([0, 0, top - 0.3], [0, 0, top + rf["finial"]], 0.4, 0.4, M["gold"])
    if c.get("pinnacles"):
        ph = c["pinnacles"]
        for sx in (-1, 1):
            for sy in (-1, 1):
                lb.boxc(sx * (w - 0.5), sy * (w - 0.5), 0.6, 0.6, z, z + ph * 0.4, M["upper"])
                lb.pyramid_rect(sx * (w - 0.5), sy * (w - 0.5), 0.6, 0.6, z + ph * 0.4, z + ph, M["gold"])
    return mats


def gothic_block(lb, c):
    """Neugotischer Baukörper aus einem Grundriss (Palace of Westminster): Wände mit Masswerk und Fensterreihen,
    flaches Dach mit dunklem Dachrand, Fialen in festem Abstand entlang des Aussenrings. ring_lv95 wird beim Laden
    ins lokale System umgerechnet (Feld _ring_local)."""
    mats, M = mat_table({
        "wall": {"color": (0.78, 0.69, 0.50), "pattern": "windows", "rib_dx": 1.6,
                 "win": [[c.get("win_dx", 3.2), 1.5, 3.0, 7.5], [c.get("win_dx", 3.2), 1.5, 10.0, 15.0],
                         [c.get("win_dx", 3.2), 1.5, 17.5, 21.5]]},
        "roof": {"color": (0.34, 0.37, 0.40), "pattern": "roof"}, "pin": {"color": (0.74, 0.65, 0.47)}}, c)
    h = c.get("height_m", 25.0)
    for ring in c["_rings_local"]:
        r = np.asarray(ring, float)
        lb.prism(r, 0, h, M["wall"], top=False)
        poly = Polygon(r)
        inner = poly.buffer(-1.0, join_style=2)
        lb.prism(r, h, h + 1.6, M["pin"], top=False)                         # Brüstung
        if not inner.is_empty and inner.geom_type == "Polygon":
            ir = np.array(inner.exterior.coords)[:-1]
            idx = earcut.triangulate_float64(ir, np.array([len(ir)], np.uint32)).reshape(-1, 3)
            for t in idx:
                lb.tri([*ir[t[0]], h + 0.4], [*ir[t[1]], h + 0.4], [*ir[t[2]], h + 0.4], [0, 0, 1], M["roof"])
            # Walmdach: Mittellinie des Grundrisses angehoben
            lb.prism(ir, h, h + 0.4, M["roof"], top=False)
        ext = poly.exterior
        dd = c.get("pinnacle_dx_m", 9.0)
        for s in np.arange(dd / 2, ext.length, dd):
            p = ext.interpolate(s)
            lb.boxc(p.x, p.y, 0.45, 0.45, h + 1.6, h + 3.5, M["pin"], top=False)
            lb.pyramid_rect(p.x, p.y, 0.5, 0.5, h + 3.5, h + 3.5 + c.get("pinnacle_m", 4.0), M["pin"])
    return mats


def ferris_wheel(lb, c):
    """Riesenrad (London Eye, 1999): Durchmesser 120 m, Nabe 75 m über Grund (Höhe 135 m), Felge als Doppelring mit
    Fachwerk, 64 Speichenseile, 32 Kapseln aussen an der Felge, Nabe auf einer A-Stütze, die von der Landseite
    (lokal −x bzw. "support_side") schräg aufsteigt. Radebene = lokale y-z-Ebene (axis_deg = Richtung der Ebene)."""
    mats, M = mat_table({"white": {"color": (0.90, 0.91, 0.92)}, "cable": {"color": (0.62, 0.64, 0.66)},
                         "glass": {"color": (0.45, 0.55, 0.62)}, "grey": {"color": (0.55, 0.57, 0.6)}}, c)
    R = c.get("diameter_m", 120.0) / 2
    hz = c.get("hub_m", 75.0)
    n = 48
    depth = c.get("rim_depth_m", 6.0)
    ang = np.arange(n) * 2 * np.pi / n
    rim = lambda a, x, r=R: np.array([x, r * math.cos(a), hz + r * math.sin(a)])  # noqa: E731
    for xr in (-depth / 2, depth / 2):
        for a0, a1 in zip(ang, np.r_[ang[1:], ang[:1]]):
            lb.beam(rim(a0, xr), rim(a1, xr), 0.9, 0.9, M["white"])
    for k, a0 in enumerate(ang):
        a1 = ang[(k + 1) % n]
        lb.beam(rim(a0, -depth / 2), rim(a1, depth / 2), 0.35, 0.35, M["white"])
        lb.beam(rim(a0, -depth / 2), rim(a0, depth / 2), 0.35, 0.35, M["white"])
    # Speichen
    for k in range(64):
        a = k * 2 * np.pi / 64
        xh = 9.0 if k % 2 else -9.0
        lb.beam([xh, 0, hz], rim(a, xh / 9.0 * depth / 2), 0.14, 0.14, M["cable"])
    # Nabe und Spindel
    lb.beam([-11, 0, hz], [11, 0, hz], 3.5, 3.5, M["grey"])
    # Kapseln (eiförmig, quer zur Radebene)
    for k in range(c.get("capsules", 32)):
        a = k * 2 * np.pi / c.get("capsules", 32)
        p = rim(a, 0, R + 2.6)
        rr, ln = 2.0, 8.0
        rings = ((-ln / 2, 0.35), (-ln / 2 + 1.2, 0.95), (ln / 2 - 1.2, 0.95), (ln / 2, 0.35))
        # einfache Kapsel: Prisma (8 Ecken) entlang x mit verjüngten Enden
        prev = None
        for xx, sc in rings:
            pts = [p + np.array([xx, rr * sc * math.cos(t), rr * sc * math.sin(t)]) for t in
                   np.linspace(0, 2 * np.pi, 9)[:-1]]
            if prev is not None:
                for i in range(8):
                    j = (i + 1) % 8
                    mid = (prev[i] + prev[j] + pts[i] + pts[j]) / 4
                    hint = mid - np.array([mid[0], p[1], p[2]])
                    lb.quad(prev[i], prev[j], pts[j], pts[i], hint, M["glass"])
            prev = pts
        lb.beam(p - np.array([0, 2.4 * math.cos(a) * 0.5, 2.4 * math.sin(a) * 0.5]), rim(a, 0, R + 0.4), 0.4, 0.4,
                M["white"])
    # A-Stütze von der Landseite
    side = c.get("support_side", -1)
    foot = c.get("support_foot_m", 58.0)
    for yy in (-c.get("support_spread_m", 22.0), c.get("support_spread_m", 22.0)):
        lb.beam([side * foot, yy, 0], [side * 4.0, 0, hz], 3.2, 3.2, M["white"])
    lb.beam([side * foot * 0.5, -11, hz * 0.5], [side * foot * 0.5, 11, hz * 0.5], 1.2, 1.2, M["white"])
    for yy in (-c.get("support_spread_m", 22.0), c.get("support_spread_m", 22.0)):
        lb.boxc(side * foot, yy, 3, 3, -1, 1.5, M["grey"])
    # Halteseile zur Rückseite
    for yy in (-30.0, 30.0):
        lb.beam([side * 4.0, 0, hz], [side * (foot + 10), yy, 0], 0.25, 0.25, M["cable"])
    return mats


def tower_bridge(lb, c):
    """Tower Bridge (London, 1894): zwei neugotische Türme (Mitte ±tower_c_m auf der Brückenachse = lokale y), 65 m
    hoch, mit vier achteckigen Ecktürmchen, Durchfahrt für die Fahrbahn, obere Fusswege auf 42–47 m (Fachwerk), Ketten
    der Seitenfelder (Hängebrücke) zu den Ufertürmen. Deck, Pfeiler und Klappen kommen aus bridges.py ("bridges")."""
    mats, M = mat_table({"stone": {"color": (0.76, 0.71, 0.62), "pattern": "stone"},
                         "roof": {"color": (0.34, 0.38, 0.42), "pattern": "roof"},
                         "blue": {"color": (0.52, 0.68, 0.84), "pattern": "truss", "t_z0": 42.0, "t_h": 5.0,
                                  "t_dx": 4.5},
                         "chain": {"color": (0.50, 0.66, 0.82)}, "dark": {"color": DARK},
                         "gold": {"color": (0.82, 0.68, 0.36)}, "white": {"color": (0.88, 0.89, 0.9)}}, c)
    tc = c.get("tower_c_m", 41.0)
    tl, tw = c.get("tower_l_m", 19.0) / 2, c.get("tower_w_m", 27.0) / 2
    deck = c.get("deck_m", 9.0)
    road = c.get("road_hw_m", 7.0)
    H = c.get("height_m", 65.0)
    body = H - 19.0
    side = c.get("side_span_m", 82.3)
    S = M["stone"]
    for sy in (-1, 1):
        cy = sy * tc
        # Seitenteile neben der Fahrbahn bis Wasser, Teil über der Durchfahrt
        lb.box(-tw, cy - tl, -road, cy + tl, -1.0, body, S)
        lb.box(road, cy - tl, tw, cy + tl, -1.0, body, S)
        lb.box(-road, cy - tl, road, cy + tl, deck + 7.5, body, S, bottom=True)
        for s in (-1, 1):                                                 # Torbögen der Fahrbahn
            lb.opening([0, cy + s * tl, deck + 0.05], (0, s, 0), (0, 0, 1), 2 * road - 0.3, 7.4, M["dark"],
                       "pointed", off=0.06)
        # Fenster
        for zz in (deck + 10.0, deck + 19.0, deck + 27.0):
            face_openings(lb, 0, cy, tw, tl, zz, 1.6, 4.5, M["dark"], n=3, arch="pointed", sides=("+y", "-y"))
            face_openings(lb, 0, cy, tw, tl, zz, 1.6, 4.5, M["dark"], n=2, arch="pointed", sides=("+x", "-x"))
        # Ecktürmchen und Dach
        for sx in (-1, 1):
            for sz in (-1, 1):
                x, y = sx * (tw - 1.6), cy + sz * (tl - 1.6)
                lb.cyl(x, y, 2.3, body - 6.0, body + 6.0, 8, S, rot=np.pi / 8)
                lb.cone(x, y, 2.5, body + 6.0, H - 2.0, 8, M["roof"], rot=np.pi / 8)
                lb.beam([x, y, H - 2.3], [x, y, H], 0.25, 0.25, M["gold"])
        lb.pyramid_rect(0, cy, tw - 2.5, tl - 2.0, body, body + 12.0, M["roof"])
        lb.boxc(0, cy, 1.6, 1.6, body + 11.0, body + 14.5, S)
        lb.pyramid_rect(0, cy, 1.8, 1.8, body + 14.5, H, M["roof"])
    # obere Fusswege
    for x in (-c.get("walk_x_m", 7.5), c.get("walk_x_m", 7.5)):
        lb.box(x - 1.6, -tc + tl, x + 1.6, tc - tl, 42.0, 47.0, M["blue"], bottom=True)
    # Ketten der Seitenfelder (lokal ±y nach aussen) und Hänger
    for sy in (-1, 1):
        y0, y1 = sy * (tc + tl), sy * (tc + tl + side)
        for x in (-tw + 1.0, tw - 1.0):
            pts = []
            for t in np.linspace(0, 1, 15):
                z = deck + 2.0 + (40.0 - deck - 2.0) * (1 - t) ** 2 + 6.0 * max(0, t - 0.85) / 0.15
                pts.append(np.array([x, y0 + (y1 - y0) * t, z]))
            for p0, p1 in zip(pts[:-1], pts[1:]):
                lb.beam(p0, p1, 1.2, 1.8, M["chain"])
            for t in np.linspace(0.1, 0.8, 8):
                z = deck + 2.0 + (40.0 - deck - 2.0) * (1 - t) ** 2
                if z - deck > 1.5:
                    lb.beam([x, y0 + (y1 - y0) * t, deck + 1.0], [x, y0 + (y1 - y0) * t, z], 0.3, 0.3, M["chain"])
        # Uferturm (klein)
        lb.box(-tw + 2, y1 - 4 * sy - 4, tw - 2, y1 - 4 * sy + 4, -1.0, deck + 9.0, S)
        for sx in (-1, 1):
            lb.cyl(sx * (tw - 2.5), y1 - 4 * sy, 1.6, deck + 6.0, deck + 12.0, 8, S)
            lb.cone(sx * (tw - 2.5), y1 - 4 * sy, 1.7, deck + 12.0, deck + 17.0, 8, M["roof"])
    return mats


def arch_bridge(lb, c):
    """Steinbogenbrücke mit einem Bogen (Rialto, Scalzi): lokale y = Brückenachse, Bogen über |y| < span/2,
    Fahrbahn bzw. Treppen als Rampe von deck_end_m auf deck_crown_m, Brüstungen. "shops": true (Rialto) setzt zwei
    getreppte Ladenzeilen mit Arkaden und Dächern und den Portikus im Scheitel darauf."""
    mats, M = mat_table({"stone": {"color": (0.88, 0.86, 0.80), "pattern": "stone"},
                         "roof": {"color": c.get("roof_color", (0.62, 0.44, 0.34)), "pattern": "tiles"},
                         "dark": {"color": DARK}, "step": {"color": (0.78, 0.76, 0.71)}}, c)
    span, W, L = c.get("span_m", 28.8), c.get("width_m", 22.9) / 2, c.get("length_m", 48.0) / 2
    spring, soffit = c.get("spring_m", 0.3), c.get("soffit_m", 6.6)
    zc, ze = c.get("deck_crown_m", 9.2), c.get("deck_end_m", 1.6)
    ys = np.unique(np.r_[np.linspace(-L, L, 49), [-span / 2, span / 2]])
    top = lambda y: ze + (zc - ze) * (1 - (abs(y) / L) ** 1.6)  # noqa: E731

    def bot(y):
        if abs(y) >= span / 2:
            return -2.0
        R = (soffit - spring)
        return spring + R * math.sqrt(max(0.0, 1 - (2 * y / span) ** 2)) ** 0.8
    S = M["stone"]
    for y0, y1 in zip(ys[:-1], ys[1:]):
        t0, t1, b0, b1 = top(y0), top(y1), bot(y0), bot(y1)
        for s in (-1, 1):                                         # Seitenflächen
            lb.quad([s * W, y0, b0], [s * W, y1, b1], [s * W, y1, t1 + 1.0], [s * W, y0, t0 + 1.0], [s, 0, 0], S)
        lb.quad([-W, y0, b0], [W, y0, b0], [W, y1, b1], [-W, y1, b1], [0, 0, -1], S)           # Untersicht
        lb.quad([-W + 0.5, y0, t0], [W - 0.5, y0, t0], [W - 0.5, y1, t1], [-W + 0.5, y1, t1], [0, 0, 1], M["step"])
        for s in (-1, 1):                                         # Brüstung innen und oben
            lb.quad([s * (W - 0.5), y0, t0], [s * (W - 0.5), y1, t1], [s * (W - 0.5), y1, t1 + 1.0],
                    [s * (W - 0.5), y0, t0 + 1.0], [-s, 0, 0], S)
            lb.quad([s * (W - 0.5), y0, t0 + 1.0], [s * W, y0, t0 + 1.0], [s * W, y1, t1 + 1.0],
                    [s * (W - 0.5), y1, t1 + 1.0], [0, 0, 1], S)
    for y in (-L, L):
        s = 1 if y > 0 else -1
        lb.quad([-W, y, -2], [W, y, -2], [W, y, top(y) + 1.0], [-W, y, top(y) + 1.0], [0, s, 0], S)
    # Bogenring betonen (Keilsteine als etwas dunklere Leiste)
    if not c.get("shops"):
        return mats
    # Ladenzeilen: je Seite zwei Reihen |x| in [x0, x1], getreppt
    x0, x1 = c.get("shop_x_m", [3.5, 8.6])
    hs = c.get("shop_h_m", 4.6)
    nseg = c.get("shop_steps", 6)
    yp = c.get("portico_hy_m", 3.6)
    for sy in (-1, 1):
        edges = np.linspace(yp, L - 2.0, nseg + 1)
        for a, b in zip(edges[:-1], edges[1:]):
            ya, yb = sorted((sy * a, sy * b))
            zb = top((a + b) / 2) - 0.2
            for sx in (-1, 1):
                xa, xb = sorted((sx * x0, sx * x1))
                lb.box(xa, ya, xb, yb, zb, zb + hs, S, top=False)
                lb.gable(xa, ya, xb, yb, zb + hs, 1.5, M["roof"], S, ridge="y", over=0.4)
                for xf, nrm in ((xa, -1), (xb, 1)):              # Arkaden zu beiden Gängen
                    lb.opening([xf, (ya + yb) / 2, zb + 0.3], (nrm, 0, 0), (0, 0, 1),
                               (yb - ya) * 0.62, hs * 0.66, M["dark"], "round")
    # Portikus im Scheitel
    zp = top(0) - 0.2
    lb.box(-x1, -yp, x1, yp, zp, zp + 8.5, S, top=False)
    lb.gable(-x1, -yp, x1, yp, zp + 8.5, 2.6, M["roof"], S, ridge="x", over=0.4)
    for s in (-1, 1):
        lb.opening([0, s * yp, zp], (0, s, 0), (0, 0, 1), 5.6, 7.2, M["dark"], "round", off=0.05)
        for xx in (-x0 - 2.6, x0 + 2.6):
            lb.opening([xx, s * yp, zp + 0.3], (0, s, 0), (0, 0, 1), 2.4, 4.0, M["dark"], "round", off=0.05)
    return mats


def truss_arch_bridge(lb, c):
    """Holzbogenbrücke (Ponte dell'Accademia, 1933/1986): Fahrbahn als flacher Bogen von deck_end_m auf
    deck_crown_m, darunter Bogenrippen (rib_x_m) vom Widerlager knapp über Wasser bis unter den Scheitel, verbunden
    mit Pfosten und Diagonalen; Geländer als Fachwerk; steinerne Widerlager."""
    mats, M = mat_table({"wood": {"color": (0.50, 0.37, 0.24), "pattern": "wood"},
                         "deck": {"color": (0.56, 0.45, 0.32), "pattern": "wood"},
                         "steel": {"color": (0.28, 0.29, 0.30)}, "stone": {"color": (0.84, 0.82, 0.76),
                                                                          "pattern": "stone"}}, c)
    span, L = c.get("span_m", 48.0), c.get("length_m", 56.0) / 2
    W = c.get("width_m", 8.0) / 2
    zc, ze = c.get("deck_crown_m", 8.0), c.get("deck_end_m", 1.8)
    rs, rc = c.get("rib_spring_m", 0.4), c.get("rib_crown_m", 6.8)
    deck = lambda y: ze + (zc - ze) * (1 - (y / L) ** 2)  # noqa: E731
    rib = lambda y: rs + (rc - rs) * (1 - (2 * y / span) ** 2)  # noqa: E731
    ys = np.linspace(-L, L, 41)
    for y0, y1 in zip(ys[:-1], ys[1:]):
        d0, d1 = deck(y0), deck(y1)
        lb.quad([-W, y0, d0], [W, y0, d0], [W, y1, d1], [-W, y1, d1], [0, 0, 1], M["deck"])
        lb.quad([-W, y0, d0 - 0.6], [W, y0, d0 - 0.6], [W, y1, d1 - 0.6], [-W, y1, d1 - 0.6], [0, 0, -1], M["wood"])
        for s in (-1, 1):
            lb.quad([s * W, y0, d0 - 0.6], [s * W, y1, d1 - 0.6], [s * W, y1, d1], [s * W, y0, d0], [s, 0, 0],
                    M["wood"])
            # Geländer
            lb.beam([s * (W - 0.1), y0, d0 + 1.1], [s * (W - 0.1), y1, d1 + 1.1], 0.18, 0.14, M["wood"])
            lb.beam([s * (W - 0.1), y0, d0], [s * (W - 0.1), y0, d0 + 1.1], 0.12, 0.12, M["wood"])
    ysr = np.linspace(-span / 2, span / 2, 25)
    for x in c.get("rib_x_m", [-W + 0.4, -1.4, 1.4, W - 0.4]):
        for y0, y1 in zip(ysr[:-1], ysr[1:]):
            lb.beam([x, y0, rib(y0)], [x, y1, rib(y1)], 0.5, 0.9, M["wood"])
        for k, y in enumerate(ysr[1:-1]):
            if deck(y) - 0.6 - rib(y) > 0.4:
                lb.beam([x, y, rib(y)], [x, y, deck(y) - 0.6], 0.22, 0.22, M["wood"])
                yn = ysr[k + 2] if k % 2 == 0 else ysr[k]
                lb.beam([x, y, rib(y)], [x, yn, deck(yn) - 0.6], 0.16, 0.16, M["steel"])
    for y in (-span / 2 - 2.5, span / 2 + 2.5):
        lb.boxc(0, y, W + 0.3, 3.0, -2.0, deck(y) - 0.6, M["stone"])
    return mats


def domed_church(lb, c):
    """Kuppelkirche (Santa Maria della Salute, St Paul's): Grundkörper "body" (Achteck mit Radius r oder Kreuz aus
    nave/transept), Tambour "drums" [{r, h}], Kuppel {r, h}, Laterne {r, h}, Voluten (Salute) um den Tambour,
    Portal mit Giebel auf der Hauptfassade (+y), Nebenkuppel und Glockentürme "extras"."""
    mats, M = mat_table({"stone": {"color": c.get("stone_color", (0.88, 0.86, 0.80)), "pattern": "stone"},
                         "dome": {"color": c.get("dome_color", (0.58, 0.60, 0.62)), "pattern": "roof"},
                         "dark": {"color": DARK}, "gold": {"color": (0.80, 0.66, 0.34)},
                         "roof": {"color": c.get("roof_color", (0.56, 0.52, 0.50)), "pattern": "tiles"}}, c)
    S = M["stone"]
    b = c.get("body", {"type": "octagon", "r": 24.0, "h": 26.0})
    if b["type"] == "octagon":
        ring = LB.ngon(0, 0, b["r"], 8, np.pi / 8)
        lb.prism(ring, -1.0, b["h"], S)
        lb.prism(LB.ngon(0, 0, b["r"] + 0.6, 8, np.pi / 8), b["h"] - 1.2, b["h"], S)
        for k in range(8):                                     # Fenster je Achteckseite
            a = np.pi / 8 + k * np.pi / 4
            a2 = a + np.pi / 4
            p0, p1 = np.array([math.cos(a), math.sin(a)]) * b["r"], np.array([math.cos(a2), math.sin(a2)]) * b["r"]
            mid, right = (p0 + p1) / 2, (p1 - p0) / np.linalg.norm(p1 - p0)
            lb.opening([mid[0], mid[1], b["h"] * 0.55], [mid[0], mid[1], 0], (0, 0, 1), 3.2, 6.5, M["dark"],
                       "round")
        zb = b["h"]
    else:   # Kreuz: Langhaus entlang y, Querhaus entlang x
        nl, nw, nh = b["nave"]
        tl, tw_ = b["transept"][:2]
        lb.box(-nw / 2, -nl / 2, nw / 2, nl / 2, -1.0, nh, S)
        lb.box(-tl / 2, -tw_ / 2, tl / 2, tw_ / 2, -1.0, nh, S)
        for s in (-1, 1):
            face_openings(lb, 0, 0, nw / 2, nl / 2, nh * 0.25, 2.5, 6.0, M["dark"], n=int(nl / 10),
                          arch="round", sides=("+x", "-x"))
        zb = nh
    for d in c.get("drums", [{"r": 15.0, "h": 12.0}]):
        lb.cyl(0, 0, d["r"], zb, zb + d["h"], 24, S)
        if d.get("columns"):
            lb.cyl(0, 0, d["r"] + 2.5, zb, zb + 1.0, 24, S)
            for k in range(d["columns"]):
                a = k * 2 * np.pi / d["columns"]
                lb.cyl(math.cos(a) * (d["r"] + 1.8), math.sin(a) * (d["r"] + 1.8), 0.55, zb + 1.0, zb + d["h"] - 1.0,
                       6, S, top=False)
            lb.cyl(0, 0, d["r"] + 2.5, zb + d["h"] - 1.0, zb + d["h"], 24, S)
        nwin = d.get("windows", 16)
        for k in range(nwin):
            a = (k + 0.5) * 2 * np.pi / nwin
            rr = d["r"] + 0.02
            lb.opening([math.cos(a) * rr, math.sin(a) * rr, zb + d["h"] * 0.3], [math.cos(a), math.sin(a), 0],
                       (0, 0, 1), 1.8, d["h"] * 0.45, M["dark"], "round")
        zb += d["h"]
    dm = c.get("dome", {"r": 16.0, "h": 19.0})
    lt = c.get("lantern", {"r": 3.5, "h": 8.0})
    lb.dome(0, 0, dm["r"], zb, dm["h"], M["dome"], n=24, rings=7, open_top=lt["r"])
    zt = zb + dm["h"] * math.sin(math.acos(min(1, lt["r"] / dm["r"])))
    for k in range(8):                                          # Rippen
        a = k * np.pi / 4
        pts = [np.array([math.cos(a) * dm["r"] * math.cos(p) * 1.01, math.sin(a) * dm["r"] * math.cos(p) * 1.01,
                         zb + dm["h"] * math.sin(p) * 1.01]) for p in np.linspace(0, math.acos(lt["r"] / dm["r"]), 6)]
        for p0, p1 in zip(pts[:-1], pts[1:]):
            lb.beam(p0, p1, 0.6, 0.3, M["stone"])
    lb.cyl(0, 0, lt["r"], zt, zt + lt["h"], 8, S, rot=np.pi / 8)
    face_openings(lb, 0, 0, lt["r"] * 0.9, lt["r"] * 0.9, zt + 1.0, 1.0, lt["h"] * 0.55, M["dark"], n=1,
                  arch="round")
    lb.dome(0, 0, lt["r"], zt + lt["h"], lt["r"] * 1.1, M["dome"], n=8, rings=3)
    ztop = zt + lt["h"] + lt["r"] * 1.1
    lb.beam([0, 0, ztop - 0.3], [0, 0, ztop + c.get("finial_m", 4.0)], 0.4, 0.4, M["gold"])
    if c.get("volutes"):
        v = c["volutes"]
        d0 = c.get("drums", [{"r": 15.0}])[0]["r"]
        rb = b.get("r", 24.0) * 0.92
        h0 = b["h"]
        for k in range(v.get("n", 16)):
            a = (k + 0.5) * 2 * np.pi / v.get("n", 16)
            u = np.array([math.cos(a), math.sin(a), 0])
            t = np.array([-math.sin(a), math.cos(a), 0])
            prof = [(d0 + (rb - d0) * (1 - math.cos(p)), v.get("h", 9.0) * math.cos(p) ** 0.7)
                    for p in np.linspace(0, np.pi / 2, 7)]
            for (r0, z0), (r1, z1) in zip(prof[:-1], prof[1:]):
                for s in (-1, 1):
                    pa = u * r0 + t * s * 0.9 + np.array([0, 0, h0 + z0])
                    pb = u * r1 + t * s * 0.9 + np.array([0, 0, h0 + z1])
                    lb.quad(pa, pb, pb - np.array([0, 0, z1]), pa - np.array([0, 0, z0]), t * s, S)
                pa = u * r0 + np.array([0, 0, h0 + z0])
                pb = u * r1 + np.array([0, 0, h0 + z1])
                lb.quad(pa + t * 0.9, pa - t * 0.9, pb - t * 0.9, pb + t * 0.9,
                        u * (z0 - z1) + np.array([0, 0, r1 - r0]), S)
    pf = c.get("portal")
    if pf:
        yf = pf.get("y_m", b.get("r", 24.0) * 0.92)
        w2, hp, dp = pf.get("w_m", 14.0) / 2, pf.get("h_m", 22.0), pf.get("d_m", 3.0)
        lb.box(-w2, yf - dp, w2, yf, -1.0, hp, S, top=False)
        lb.gable(-w2, yf - dp, w2, yf, hp, pf.get("pediment_m", 4.0), S, S, ridge="y", over=0.5)
        lb.opening([0, yf, 0.5], (0, 1, 0), (0, 0, 1), pf.get("door_w_m", 5.0), pf.get("door_h_m", 11.0), M["dark"],
                   "round")
        for xx in (-w2 + 2.0, w2 - 2.0):                           # Säulen
            for dx in (-0.9, 0.9):
                lb.cyl(xx + dx, yf + 0.7, 0.55, 0.0, hp - 0.6, 6, S, top=False)
        lb.box(-w2 - 1.0, yf - dp - 2.0, w2 + 1.0, yf + 4.0, -1.0, 0.6, S)   # Treppe
    for e in c.get("extras", []):
        if e["type"] == "dome":
            x, y = e["at"]
            lb.boxc(x, y, e["hx"], e["hy"], -1.0, e["h"], S)
            lb.cyl(x, y, e["r"] * 0.9, e["h"], e["h"] + e.get("drum", 4.0), 16, S)
            lb.dome(x, y, e["r"], e["h"] + e.get("drum", 4.0), e["r"] * 1.1, M["dome"], n=16, rings=5)
            zz = e["h"] + e.get("drum", 4.0) + e["r"] * 1.1
            lb.cyl(x, y, 1.4, zz - 0.3, zz + 3.0, 8, S)
            lb.dome(x, y, 1.5, zz + 3.0, 1.6, M["dome"], n=8, rings=2)
        elif e["type"] == "belltower":
            x, y = e["at"]
            w = e.get("w", 4.0) / 2
            lb.boxc(x, y, w, w, -1.0, e["h"], S)
            face_openings(lb, x, y, w, w, e["h"] - 6.0, w * 0.8, 3.5, M["dark"], n=1, arch="round")
            if e.get("cap") == "spire":
                lb.pyramid_rect(x, y, w, w, e["h"], e["h"] + e.get("cap_h", 5.0), M["dome"])
            else:
                lb.dome(x, y, w, e["h"], e.get("cap_h", 2.5), M["dome"], n=8, rings=3)
        elif e["type"] == "box":
            lb.box(*e["xy"], -1.0, e["h"], S)
            if e.get("roof"):
                lb.gable(*e["xy"], e["h"], e["roof"], M["roof"], S, ridge=e.get("ridge", "y"))
    return mats


def drawbridge_gallows(lb, c):
    """Galgen einer holländischen Zugbrücke (Magere Brug): je Klappe zwei Portalrahmen (Pfosten neben der Fahrbahn,
    Riegel oben) und darüber zwei Waagebalken, die über die Öffnung ragen, mit Querriegeln und Zugstangen zu den
    Klappenenden. Lokale y = Brückenachse, Mitte der Durchfahrt im Ursprung; Deck aus bridges.py."""
    mats, M = mat_table({"white": {"color": (0.93, 0.93, 0.90)}, "dark": {"color": (0.20, 0.21, 0.22)}}, c)
    open_hw = c.get("opening_m", 7.0) / 2
    hw = c.get("width_m", 8.0) / 2 + 0.3
    deck = c.get("deck_m", 3.0)
    ph = c.get("post_m", 7.5)
    bl = c.get("beam_len_m", 12.0)
    for sy in (-1, 1):
        yp = sy * (open_hw + 1.0)
        for x in (-hw, hw):
            lb.beam([x, yp - 0.8, deck], [x, yp, deck + ph], 0.45, 0.45, M["white"])
            lb.beam([x, yp + 0.8, deck], [x, yp, deck + ph], 0.45, 0.45, M["white"])
            # Waagebalken: über die Öffnung (Richtung −sy) und nach hinten
            lb.beam([x, yp - sy * (open_hw + 0.5), deck + ph + 1.6], [x, yp + sy * (bl - open_hw - 1.0),
                                                                    deck + ph - 0.8], 0.4, 0.55, M["white"])
            lb.beam([x, yp - sy * (open_hw + 0.5), deck + ph + 1.6], [x, yp - sy * (open_hw + 0.5), deck + 0.6],
                    0.08, 0.08, M["dark"])
        lb.beam([-hw, yp, deck + ph], [hw, yp, deck + ph], 0.4, 0.5, M["white"])
        for t in (-(open_hw + 0.5), bl - open_hw - 1.0):
            z = deck + ph + 1.6 if t < 0 else deck + ph - 0.8
            lb.beam([-hw, yp + sy * t, z], [hw, yp + sy * t, z], 0.3, 0.3, M["white"])
        lb.beam([-hw, yp, deck + ph], [hw, yp + sy * 0.0, deck + 0.4], 0.12, 0.12, M["white"])
    return mats


TYPES = {"eiffel_tower": (eiffel_tower, (70, 70)), "cathedral": (cathedral, (26, 70)), "tower": (tower, (9, 9)),
         "gothic_block": (gothic_block, None), "ferris_wheel": (ferris_wheel, (12, 64)),
         "tower_bridge": (tower_bridge, (15, 30)), "arch_bridge": (arch_bridge, (0, 0)),
         "truss_arch_bridge": (truss_arch_bridge, (0, 0)), "domed_church": (domed_church, (30, 30)),
         "drawbridge_gallows": (drawbridge_gallows, (0, 0))}


# ----------------------------------------------------------------------------- Lage und Freistellung

def frame(cfg):
    a = math.radians(cfg.get("axis_deg", 0.0))
    f = np.array([math.sin(a), math.cos(a)])
    r = np.array([math.cos(a), -math.sin(a)])
    return np.asarray(cfg["at_lv95"], float), r, f


def to_world(cfg, xy):
    at, r, f = frame(cfg)
    xy = np.asarray(xy, float)
    return at + xy[..., :1] * r + xy[..., 1:2] * f


def to_local(cfg, en):
    at, r, f = frame(cfg)
    d = np.asarray(en, float) - at
    return np.column_stack([d @ r, d @ f])


def clear_polygons(area):
    """Freistellflächen (Gebietssystem) aller Wahrzeichen: [(slug, Polygon)]."""
    out = []
    for c in area.get("landmarks", []):
        if c.get("clear_lv95"):
            out.append((c["slug"], Polygon(c["clear_lv95"])))
            continue
        if c["type"] == "gothic_block":
            from shapely.ops import unary_union
            out.append((c["slug"], unary_union([Polygon(r) for r in c["ring_lv95"]]).buffer(c.get("clear_m", 2.0))))
            continue
        hx, hy = c.get("clear_box_m") or TYPES[c["type"]][1]
        if hx <= 0 or hy <= 0:
            continue
        loc = np.array([(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)])
        if c["type"] == "cathedral":  # Fassade bei y = 0, Kirche nach −y
            L = c.get("length_m", 128.0)
            loc = np.array([(-hx, 2), (hx, 2), (hx, -L - 4), (-hx, -L - 4)])
        out.append((c["slug"], Polygon(to_world(c, loc))))
    return out


def ground_height(area, en):
    import rasterio
    with rasterio.open(Path("build") / area["id"] / "dem_core.tif") as s:
        r, cidx = s.index(*en)
        win = s.read(1, window=((r - 3, r + 4), (cidx - 3, cidx + 4)))
    return float(np.median(win)) - area["lake_level_m"]


def build_landmark(area, c, origin):
    fn = TYPES[c["type"]][0]
    if c["type"] == "gothic_block":
        c = {**c, "_rings_local": [to_local(c, r) for r in c["ring_lv95"]]}
    lb = LB()
    mats = fn(lb, c)
    V, F, Mt = lb.arrays()
    base = c["base_m"] if "base_m" in c else ground_height(area, c["at_lv95"])
    at, r, f = frame(c)
    off = at - origin
    W = np.column_stack([off[0] + V[:, 0] * r[0] + V[:, 1] * f[0], off[1] + V[:, 0] * r[1] + V[:, 1] * f[1],
                         V[:, 2] + base])
    return W, F, Mt, mats, base


class _Ref:
    def __init__(self, slug):
        self.slug = slug


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("area")
    ap.add_argument("--procs", type=int, default=8)
    ap.add_argument("--rays", type=int, default=7)
    ap.add_argument("--light", choices=["sun", "ambient"], default="sun")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    import warp as wp
    import bridges as br
    from common import load_area
    wp.config.quiet = True
    wp.init()
    area = load_area(a.area)
    if not area.get("landmarks"):
        sys.exit("Gebietsdatei ohne \"landmarks\" – nichts zu tun")
    build = Path("build") / area["id"]
    out = build / ("landmarks" if a.light == "sun" else "landmarks-ambient")
    out.mkdir(parents=True, exist_ok=True)
    e0c, n0c, e1c, n1c = area["core_lv95"]
    origin = np.array(area.get("origin_lv95", [(e0c + e1c) / 2, (n0c + n1c) / 2]))
    only = set(a.only.split(",")) if a.only else None
    old = {}
    if only and (out / "landmarks.npz").exists():
        old = dict(np.load(out / "landmarks.npz"))
        oldmeta = {m["mesh"]: m for m in json.loads((out / "meta.json").read_text())["landmarks"]}
    save, meta = {}, {"landmarks": []}
    for c in area["landmarks"]:
        name = f"lm_{c['slug']}"
        if only and c["slug"] not in only and f"{name}__v" in old:
            save.update({k: v for k, v in old.items() if k.startswith(name + "__")})
            meta["landmarks"].append(oldmeta[name])
            continue
        V, F, Mt, mats, base = build_landmark(area, c, origin)
        lo, hi = V.min(axis=0), V.max(axis=0)
        bb = (lo[0] + origin[0] - 150, lo[1] + origin[1] - 150, hi[0] + origin[0] + 150, hi[1] + origin[1] + 150)
        occ_v, occ_f = br.occluders(area, origin, bb)
        name_, arrs, atlas = br.bake_bridge(_Ref(c["slug"]), V, F, Mt, occ_v, occ_f, out, a.procs, a.rays, a.light,
                                            albedo=albedo_fn(mats, base), prefix="lm", tex_m=c.get("tex_m", TEX_M))
        save.update(arrs)
        info = {"name": c["name"], "type": c["type"], "mesh": name_, "tris": int(len(arrs[f"{name_}__f"])),
                "atlas": list(atlas), "base_m": round(base, 2), "height_m": round(float(hi[2] - base), 1),
                "at_lv95": c["at_lv95"], "axis_deg": c.get("axis_deg", 0.0), "source": c.get("source", "")}
        meta["landmarks"].append(info)
        print(json.dumps(info, ensure_ascii=False), flush=True)
    np.savez_compressed(out / "landmarks.npz", **save)
    meta["light"] = a.light
    meta["meshes"] = [m["mesh"] for m in meta["landmarks"]]
    (out / "meta.json").write_text(json.dumps(meta, indent=1, ensure_ascii=False))
    print(f"{len(meta['meshes'])} Wahrzeichen, {sum(m['tris'] for m in meta['landmarks']):,} Dreiecke → {out}")


if __name__ == "__main__":
    main()
