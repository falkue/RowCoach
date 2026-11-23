"""Himmel, Sonnenlicht und Dunst je Sonnenstand – Python-Fassung von SceneEnvironment.forSun und
ProceduralTextures.skyEquirect (App/RowCoach/Scene3D). Für Vorschauen (preview.py --time); die Zahlen müssen mit
der Swift-Fassung übereinstimmen, ändert sich eine, die andere nachziehen.

Szenenkoordinaten: x = Ost, y = oben, z = −Nord. Azimut ab Nord im Uhrzeigersinn.
"""
from pathlib import Path

import numpy as np
from PIL import Image

CLOUDS = Path(__file__).resolve().parents[2] / "App/RowCoach/Resources/sky-clouds.png"


def smoothstep(a, b, x):
    t = np.clip((np.asarray(x, float) - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    return np.asarray(a, float) + (np.asarray(b, float) - np.asarray(a, float)) * t


def env_for_sun(az, el):
    """Farben und Stärken wie SceneEnvironment.forSun (el in Grad, schon auf ≥ 2° geklemmt)."""
    h = float(smoothstep(2, 30, el))
    return {
        "sun_az": az, "sun_el": el, "h": h,
        "sun_color": mix([1.00, 0.58, 0.32], [1.0, 0.96, 0.88], h),
        "sun_intensity": 3000 * (0.30 + 0.70 * float(smoothstep(2, 40, el))),
        "zenith": mix([0.14, 0.26, 0.54], [0.20, 0.42, 0.80], h),
        "horizon": mix([0.88, 0.62, 0.46], [0.72, 0.82, 0.93], h),
        "below": mix([0.42, 0.38, 0.38], [0.55, 0.62, 0.66], h),
        "exponent": 0.55,
        "glow_color": mix([1.0, 0.50, 0.22], [1.0, 0.97, 0.90], h),
        "glow_strength": float(mix(0.85, 0.22, h)),
        "haze_color": mix([0.84, 0.70, 0.62], [0.78, 0.84, 0.90], h),
        "haze_opacity": float(mix(0.55, 0.45, h)),
        "cirrus_color": mix([1.0, 0.72, 0.58], [1.0, 1.0, 1.0], h),
        "cumulus_lit": mix([1.0, 0.80, 0.64], [1.0, 1.0, 1.0], h),
        "cumulus_shadow": mix([0.52, 0.44, 0.50], [0.68, 0.72, 0.79], h),
        "cloud_opacity": 0.8,
    }


def to_sun(env):
    a, e = np.radians(env["sun_az"]), np.radians(env["sun_el"])
    return np.array([np.sin(a) * np.cos(e), np.sin(e), -np.cos(a) * np.cos(e)])


_mask = None


def cloud_mask():
    global _mask
    if _mask is None:
        _mask = np.asarray(Image.open(CLOUDS).convert("RGB"), np.float32) / 255.0 if CLOUDS.exists() else False
    return _mask


def sky_color(d, env, clouds=True):
    """Himmelsfarbe für Blickrichtungen d (N×3, Einheitsvektoren, Szenenkoordinaten)."""
    lat = np.degrees(np.arcsin(np.clip(d[:, 1], -1, 1)))
    az = np.degrees(np.arctan2(d[:, 0], -d[:, 2])) % 360
    up = lat >= 0
    t = np.where(up, (np.clip(lat, 0, 90) / 90) ** env["exponent"], 0.0)
    c = np.where(up[:, None], mix(env["horizon"], env["zenith"], t[:, None]),
                 mix(env["horizon"], env["below"], np.clip(-lat / 8, 0, 1)[:, None]))
    ang = np.arccos(np.clip(d @ to_sun(env), -1, 1))
    g = env["glow_strength"] * (0.65 * np.exp(-(ang / 0.50) ** 2) + 0.35 * np.exp(-(ang / 0.12) ** 2))
    g *= (1 - 0.5 * t) * np.where(up, 1.0, np.clip(1 + lat / 8, 0, 1))
    g = np.clip(g, 0, 1)
    c = mix(c, env["glow_color"], g[:, None])
    m = cloud_mask() if clouds else False
    if m is not False:
        Hm, Wm = m.shape[:2]
        row = np.clip(((90 - lat) / 90 * Hm).astype(int), 0, Hm - 1)
        col = np.clip((az / 360 * Wm).astype(int), 0, Wm - 1)
        s = m[row, col] * up[:, None]
        ci = s[:, 0] * env["cloud_opacity"]
        ccol = mix(env["cirrus_color"], env["glow_color"], np.clip(g * 0.6, 0, 1)[:, None]) * (0.92 + 0.08 * t)[:, None]
        c = mix(c, ccol, ci[:, None])
        cu = s[:, 1] * env["cloud_opacity"]
        ucol = mix(env["cumulus_shadow"], env["cumulus_lit"], s[:, 2:3])
        ucol = mix(ucol, env["horizon"], 0.25)
        c = mix(c, ucol, cu[:, None])
    return np.clip(c, 0, 1)


def haze_color(az_deg, env):
    """Dunstfarbe je Azimut: zur Sonne hin wärmer (wie die Dunsttextur der App)."""
    da = np.radians((np.asarray(az_deg) - env["sun_az"] + 540) % 360 - 180)
    lobe = np.clip(np.cos(da), 0, 1) ** 3
    return mix(env["haze_color"], env["glow_color"], (0.6 * env["glow_strength"] * lobe)[..., None])
