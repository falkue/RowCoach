"""Wolkenschicht für den Himmel der App (eigene Arbeit, Lizenz wie der Code): feine Cirrus-/Federwolken und
Schönwetter-Cumuli am Horizont (einzelne Haufen und Felder in der Ferne), als Maske für die obere Himmelshälfte.

Ergebnis: App/RowCoach/Resources/sky-clouds.png (RGB, 2048 × 512, equirektangular, Zeile 0 = Zenit, letzte Zeile
= Horizont; Spalten = Azimut, Lage beliebig):
  R = Deckkraft der Cirrus-Wolken, G = Deckkraft der Cumuli, B = Licht auf den Cumuli (0 = Unterseite, 1 = Kuppe)
Die App (ProceduralTextures.skyEquirect) färbt die Maske je Sonnenstand ein (weiss am Tag, rosa/orange am Abend)
und legt sie über den Himmelsverlauf. preview.py nutzt dieselbe Maske und dieselbe Einfärbung (sky.py).

Die Wolken liegen auf einer gedachten Ebene über der Kamera (Perspektive: zum Horizont hin flacher und dichter),
werden 2× überabgetastet und zum Horizont hin ausgeblendet (dort übernimmt der Dunst).

Aufruf: .venv/bin/python sky_clouds.py [--seed 7] [--out ../../App/RowCoach/Resources/sky-clouds.png]
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image

W, H = 2048, 512  # Ausgabe: obere Himmelshälfte (90° … 0°)
SS = 2            # Überabtastung


def _hash(ix, iy, seed):
    h = (ix.astype(np.int64) * 374761393 + iy.astype(np.int64) * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF).astype(np.float64) / float(0xFFFFFF)


def vnoise(x, y, seed):
    """Wertrauschen 0…1 mit weicher Interpolation (quintisch)."""
    x0 = np.floor(x); y0 = np.floor(y)
    fx = x - x0; fy = y - y0
    ux = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
    uy = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
    ix, iy = x0.astype(np.int64), y0.astype(np.int64)
    a = _hash(ix, iy, seed); b = _hash(ix + 1, iy, seed)
    c = _hash(ix, iy + 1, seed); d = _hash(ix + 1, iy + 1, seed)
    return (a + (b - a) * ux) + ((c + (d - c) * ux) - (a + (b - a) * ux)) * uy


def fbm(x, y, seed, octaves=5, gain=0.5, lac=2.03):
    s = np.zeros_like(x); amp = 0.5; norm = 0.0
    for o in range(octaves):
        s += amp * vnoise(x, y, seed + 17 * o)
        norm += amp
        x = x * lac + 3.1; y = y * lac + 1.7
        amp *= gain
    return s / norm


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--out", default=str(Path(__file__).resolve().parents[2] / "App/RowCoach/Resources/sky-clouds.png"))
    a = ap.parse_args()
    seed = a.seed
    w, h = W * SS, H * SS
    out = Path(a.out)
    step = 16  # Zeilen je Block: kleine Arrays (die Spark wird bei grossen Arrays unter Speicherdruck sehr langsam)
    img = np.concatenate([block(r0, min(h, r0 + step), w, h, seed) for r0 in range(0, h, step)], axis=0)
    out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)).save(out, optimize=True)
    print(f"{out}: {W}×{H}, Cirrus-Bedeckung {np.mean(img[..., 0] > 0.1) * 100:.0f} %, "
          f"Cumuli {np.mean(img[..., 1] > 0.1) * 100:.1f} %, {out.stat().st_size / 1e6:.2f} MB")


def block(r0, r1, w, h, seed):
    """Überabgetastete Zeilen r0…r1 → Ausgabezeilen r0/SS … r1/SS (R, G, B wie oben)."""
    lat = 90.0 - (np.arange(r0, r1) + 0.5) / h * 90.0          # Grad, Zeile 0 = Zenit
    az = (np.arange(w) + 0.5) / w * 360.0
    LAT, AZ = np.meshgrid(np.radians(lat), np.radians(az), indexing="ij")
    y = np.sin(LAT)
    cx, cz = np.cos(LAT) * np.sin(AZ), np.cos(LAT) * np.cos(AZ)

    # --- Cirrus: Ebene über der Kamera, Strähnen entlang der Windrichtung
    inv = 1.0 / np.maximum(y, 0.02)
    px, pz = cx * inv, cz * inv
    wind = np.radians(32.0)
    u = px * np.cos(wind) + pz * np.sin(wind)
    v = -px * np.sin(wind) + pz * np.cos(wind)
    warp = fbm(u * 0.35, v * 0.35, seed + 101, 4)
    v2 = v + 0.9 * (warp - 0.5)
    streak = fbm(u * 0.9, v2 * 7.0, seed + 202, 6, gain=0.55)            # lange, feine Fasern
    hooks = fbm(u * 2.2 + 4.0 * warp, v2 * 2.2, seed + 303, 5)           # Federn, Haken
    cover = fbm(px * 0.16 + 11.0, pz * 0.16 - 7.0, seed + 404, 4)        # Felder mit und ohne Wolken
    base = 0.62 * streak + 0.38 * hooks
    cirrus = smoothstep(0.47, 0.70, base) * smoothstep(0.34, 0.58, cover)
    cirrus *= 0.55 + 0.45 * smoothstep(0.35, 0.75, fbm(u * 3.5, v2 * 22.0, seed + 505, 3))  # Faserstruktur
    cirrus *= smoothstep(0.025, 0.12, y)                                   # zum Horizont in den Dunst
    cirrus = np.clip(cirrus * 1.5, 0, 1)

    # --- Cumuli: wenige kleine Haufen knapp über dem Horizont, je Haufen einige runde Quellwolken (Kreise in
    #     Grad Azimut × Grad Höhe), unten flach abgeschnitten; leicht ausgefranster Rand
    lat_d = np.degrees(LAT)
    az_d = np.degrees(AZ)
    rng = np.random.default_rng(seed)
    cum = np.zeros_like(lat_d)
    shade = np.zeros_like(lat_d)
    rx3, ry3 = np.cos(AZ) * 60.0, np.sin(AZ) * 60.0
    fray = fbm(rx3 + lat_d * 0.6, ry3 + lat_d * 0.6, seed + 909, 3) - 0.5
    for _ in range(13):
        c_az = rng.uniform(0, 360)
        base = rng.uniform(0.7, 1.8)                       # Unterkante in Grad (über den Hügeln am Ufer)
        width = rng.uniform(4.0, 12.0)                     # Breite des Haufens in Grad
        for _ in range(int(rng.integers(4, 9))):
            r = rng.uniform(1.0, 3.0) * min(1.0, width / 7)
            pa = c_az + rng.uniform(-width / 2, width / 2)
            pl = base + r * rng.uniform(0.15, 0.85)
            da = (az_d - pa + 540) % 360 - 180
            dist = np.sqrt(da ** 2 + ((lat_d - pl) * 1.15) ** 2) / r + 0.40 * fray
            dens = smoothstep(1.0, 0.75, dist) * smoothstep(base - 0.05, base + 0.12, lat_d)
            lit = np.clip(0.55 + 0.6 * (lat_d - pl) / r - 0.15 * dist, 0, 1)
            shade = np.where(dens > cum, lit, shade)
            cum = np.maximum(cum, dens)

    # --- Zweite Schicht: Felder flacher Schönwetter-Cumuli in der Ferne (tiefe Ebene, perspektivisch zum
    #     Horizont hin verdichtet), sichtbar zwischen ca. 1° und 12° – also im Bild der fast waagrechten Kamera
    inv2 = 1.0 / np.maximum(y, 0.012)
    qx, qz = cx * inv2 * 0.55, cz * inv2 * 0.55
    n2 = fbm(qx * 1.3 + 5.0, qz * 1.3 + 9.0, seed + 1212, 4)
    field = fbm(qx * 0.12 + 3.0, qz * 0.12 - 4.0, seed + 1313, 3)
    band = smoothstep(0.014, 0.035, y) * (1 - smoothstep(0.10, 0.24, y))
    d2 = smoothstep(0.53, 0.65, n2) * smoothstep(0.36, 0.56, field) * band
    lit2 = np.clip(0.35 + 3.0 * (n2 - 0.53), 0, 1)
    shade = np.where(d2 > cum, lit2, shade)
    cum = np.maximum(cum, d2 * 0.9)

    def down(x):
        return x.reshape((r1 - r0) // SS, SS, W, SS).mean(axis=(1, 3))

    return np.stack([down(cirrus), down(cum), down(shade * (cum > 0.01))], -1)


if __name__ == "__main__":
    main()
