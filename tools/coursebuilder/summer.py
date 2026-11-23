"""Sommerliche Farben für die Geländetexturen (Gebietsoption "summer_grade": true; export.py ruft das auf).

SWISSIMAGE wirkt matt (Dunst, Befliegung teils im Frühjahr). Behutsam:
  - Rasen und Wiesen (niedrige Vegetation): satter und etwas heller grün
  - Baumkronen: satter, etwas dunkler grün
  - alles leicht wärmer; die Sättigung steigt nur, wo schon Farbe ist, und nur bei grünlichen Tönen deutlich –
    graue Dächer, Strassen und Plätze bleiben grau, rote Ziegel werden nicht bunter.
Vegetation kommt aus build/<gebiet>/trees/veg.tif (trees.py: 1 niedrige Vegetation, 2 Krone, aus Vegetationshöhe und
Grünanteil). Fehlt die Datei (oder ausserhalb des Kerngebiets), entscheidet allein der Grünanteil im Luftbild.

Kontaktschatten der 3D-Bäume (trees/<stufe>/tree_ao.tif) wirkt nur auf helle Pixel: wo das Luftbild schon dunkel ist,
steckt der echte Baumschatten bereits drin (nicht doppeln).
"""
import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.windows import from_bounds


def _smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def read_layer(path, bounds, shape, resampling=Resampling.bilinear, fill=0):
    """Raster (1 Band) für bounds auf shape (H, W) lesen; float32."""
    with rasterio.open(path) as src:
        win = from_bounds(*bounds, src.transform)
        return src.read(1, window=win, out_shape=shape, resampling=resampling, boundless=True,
                        fill_value=fill).astype(np.float32)


def veg_weights(veg_path, bounds, shape):
    """(Rasen-Gewicht, Kronen-Gewicht) 0..1, weich, aus veg.tif; None ohne Datei."""
    if veg_path is None:
        return None
    with rasterio.open(veg_path) as src:
        win = from_bounds(*bounds, src.transform)
        v = src.read(1, window=win, boundless=True, fill_value=0)
    grass = (v == 1).astype(np.float32)
    crown = (v == 2).astype(np.float32)
    from PIL import Image
    H, W = shape
    g = np.asarray(Image.fromarray(grass).resize((W, H), Image.BILINEAR))
    c = np.asarray(Image.fromarray(crown).resize((W, H), Image.BILINEAR))
    return g, c


def grade(img, veg=None):
    """img: float32 H×W×3 (0..255, sRGB). veg: (Rasen, Krone) oder None. Liefert float32 0..255."""
    x = img / 255.0
    r, g, b = x[..., 0], x[..., 1], x[..., 2]
    s = r + g + b
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    exg = (2 * g - r - b) / np.maximum(s, 1e-3)
    greenish = _smooth(exg, 0.0, 0.12) * _smooth(s, 0.12, 0.35)   # sehr dunkle Pixel: unsicher
    leafoff = None
    if veg is not None:
        wg, wc = veg
        # Kronen ohne Grün im Luftbild (Befliegung im Frühjahr, unbelaubt): behutsam ins Laubgrün ziehen,
        # Helligkeitsstruktur bleibt (sonst wirken ferne Bäume ohne 3D-Modell grau-braun)
        leafoff = wc * (1 - _smooth(exg, 0.0, 0.08))
        wg = np.maximum(wg * _smooth(exg, -0.03, 0.06), 0.0)
        wc = wc * _smooth(exg, -0.05, 0.04)
        wg = np.maximum(wg, greenish * (1 - wc) * 0.6)
    else:
        wg, wc = greenish * 0.8, greenish * 0.0
    chroma = np.max(x, -1) - np.min(x, -1)
    # 1) Sättigung: global wenig (nur wo schon Farbe ist), Vegetation deutlich
    sat = 1.0 + 0.06 * _smooth(chroma, 0.04, 0.15) + 0.38 * wg + 0.26 * wc
    y = lum[..., None] + (x - lum[..., None]) * sat[..., None]
    if leafoff is not None:
        foliage = (0.10 + 0.38 * lum[..., None]) * np.array([0.78, 1.12, 0.55])
        a = (0.65 * leafoff)[..., None]
        y = y * (1 - a) + foliage * a
    # 2) Helligkeit: Rasen heller, Kronen etwas dunkler
    bright = 1.0 + 0.10 * wg - 0.07 * wc
    y = y * bright[..., None]
    # Rasen leicht ins Sattgrüne (weg vom Gelbgrau), Kronen etwas kühler und tiefer
    y[..., 1] *= 1.0 + 0.04 * wg + 0.02 * wc
    y[..., 0] *= 1.0 - 0.03 * wc
    # 3) leicht wärmer (überall, sehr behutsam)
    y[..., 0] *= 1.025
    y[..., 2] *= 0.975
    return np.clip(y * 255.0, 0, 255).astype(np.float32)


def apply_tree_ao(img, ao):
    """ao: 0..1 (1 = kein Schatten), auf img-Grösse. Dunkle Pixel bleiben (Schatten schon im Luftbild)."""
    lum = (0.299 * img[..., 0] + 0.587 * img[..., 1] + 0.114 * img[..., 2]) / 255.0
    protect = _smooth(lum, 0.12, 0.32)
    f = 1.0 - (1.0 - ao) * protect
    return img * f[..., None]
