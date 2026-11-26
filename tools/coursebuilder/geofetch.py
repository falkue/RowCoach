"""Gemeinsame Helfer zum Holen offener Geodaten weltweit (ausserhalb CH/DE), alles direkt im Koordinatensystem des Gebiets.

Regel (docs/WELTWEIT.md): neue Gebiete rechnen in einem UTM-System in Metern – Europa ETRS89/UTM (EPSG:258zz),
Japan JGD2011/UTM (EPSG:6688–6692), Südamerika SIRGAS 2000/UTM (EPSG:31965–31985), sonst WGS84/UTM (326zz Nord,
327zz Süd). Daten in anderen Systemen (British National Grid 27700, Lambert-93 2154, JGD2011 geographisch 6697,
Web-Mercator-Kacheln 3857, WGS84) werden hier beim Holen umgerechnet; die Pipeline danach (prepare.py …) sieht nur
noch das Gebietssystem. Fehlen PROJ-Gitter für eine genaue Datumsumrechnung (z. B. OSTN15 für 27700), lädt
ensure_proj_grids() sie von cdn.proj.org (offene Lizenz) und legt sie auch für GDAL/rasterio ab.

Bausteine (alle höflich: eine Verbindung je Server nacheinander, kurze Pausen, Wiederholung mit wachsender Wartezeit,
User-Agent "RowCoach-coursebuilder/0.2 (private research)"):
  http()/download()     GET/POST mit Wiederholungen (429/5xx/Abbruch), Retry-After wird beachtet
  Grid, km_tiles()      Zielraster im Gebietssystem (Ecke NW, Meter) und 1-km-Kacheln wie in der Pipeline
  write_tif()           GeoTIFF schreiben (float32 mit nodata −9999 bzw. RGB als JPEG/YCbCr)
  warp_array()          beliebiges Raster (Array + Transform + crs) auf ein Grid umrechnen
  cog_read()            Fensterweises Lesen eines (Cloud Optimized) GeoTIFF über /vsicurl/ mit WarpedVRT direkt ins
                        Grid (nur die nötigen Blöcke werden übertragen; Übersichten bei gröberem Ziel)
  wcs_tiles()           WCS 2.0.1 GetCoverage in Blöcken (subset=E/N im Server-System, optional SCALEFACTOR),
                        Cache je Block, dann je km-Kachel ins Gebietssystem
  xyz_read()            XYZ-Kachelmosaik (Web Mercator; JPEG/PNG-Bild oder PNG-Höhen mit Decoder gsi_dem_png,
                        terrarium, mapbox) → Grid
  wms_tiles()           WMS 1.3.0 GetMap (Höhen als GeoTIFF float32 mit Ersatz-Layern für Lücken, Luftbild als JPEG)
                        je Kachel in Teilblöcken bis max_px, Georeferenz aus der BBOX (System der Anfrage erzwungen,
                        z. B. Géoplateforme/IGN mit kaputtem WKT) → Kacheln im Gebietssystem
  wfs_features()        WFS 2.0 GetFeature seitenweise (COUNT/STARTINDEX), GeoJSON in WGS84 (z. B. BD TOPO batiment)
  arcgis_features()     ArcGIS FeatureServer/MapServer query mit Seiten (resultOffset), GeoJSON in WGS84
  s2_scenes()/s2_far()  Sentinel-2 L2A (Earth Search STAC, collection sentinel-2-c1-l2a): wolkenärmste Sommer-
                        szenen, örtlich nach SCL-Wolkenmaske gewählt, Mosaik aus dem Asset "visual" (10 m) → Grid,
                        mit sanfter Tonwertkorrektur (Dunst weg, etwas Sättigung)
  overpass()            Overpass-API mit Ausweich-Instanzen
  copernicus_tiles()    Namen der Copernicus-GLO-30-Kacheln für eine WGS84-Box (für "copernicus_tiles")
  log_source()          Eintrag in <data_dir>/fetch-log.json (Quelle, URL, Lizenz, Datum)
  trees_inputs()        build/<gebiet>/chm.tif (Oberflächen- minus Geländemodell, 0,5 m) und ortho_core.tif (1 m) aus
                        den Rohdaten-Kacheln bdom/ und dgm/ bzw. image_core/, unabhängig von Kachelnamen

Kachelschemata für COG-Sammlungen (Ordner voller Dateien, deren Namen aus der Lage folgen) stehen in TILE_SCHEMES,
z. B. "kartverket" (Norwegen, DTM1/DOM1 15×15 km, EPSG:25833). Ein Land ergänzt sein Schema dort.

Rohdaten-Layout, das die Pipeline erwartet (fetch_world.py schreibt es):
  dgm/dtm_EEE-NNNN.tif      Geländemodell 1 m je km (raster_dirs alti_core)
  dgm_far/dtm_EEE-NNNN.tif  Geländemodell Umgebung (4 m, 4-km-Blöcke; raster_dirs alti_far), Lücken füllt Copernicus
  bdom/dsm_EEE-NNNN.tif     Oberflächenmodell 1 m je km (Bäume, Gebäudehöhen, Brückendecks)
  image_core/dop_EEE-NNNN.tif Luftbild je km (echt oder synth_ortho.py), image_far/*.tif Umgebungsluftbild
  osm/overpass.json (fetch.py), osm/landcover.json (Flächennutzung, Wege, Gebäude), footprints/footprints.geojson
  copernicus/*.tif, fetch-log.json
EEE/NNNN sind Kilometer im Gebietssystem (Süden/Westen der Kachel).
"""
import io
import json
import math
import os
import threading
import time
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from urllib.parse import urlparse

import numpy as np
import rasterio
import requests
from rasterio.enums import Resampling
from rasterio.transform import from_origin
from rasterio.warp import reproject, transform_bounds

UA = {"User-Agent": "RowCoach-coursebuilder/0.2 (private research)"}
NODATA = -9999.0
OVERPASS_MIRRORS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter",
                    "https://overpass.private.coffee/api/interpreter",
                    "https://maps.mail.ru/osm/tools/overpass/api/interpreter"]
if os.environ.get("ROWCOACH_OVERPASS"):  # eigene Reihenfolge, z. B. bei Ausfall von overpass-api.de (Komma-Liste)
    OVERPASS_MIRRORS = os.environ["ROWCOACH_OVERPASS"].split(",") + OVERPASS_MIRRORS
STAC_SEARCH = "https://earth-search.aws.element84.com/v1/search"
COPERNICUS = "https://copernicus-dem-30m.s3.amazonaws.com/{t}/{t}.tif"
LIC_COPERNICUS_DEM = ("© DLR e.V. 2010–2014 und © Airbus Defence and Space GmbH 2014–2018, bereitgestellt unter "
                      "COPERNICUS von der Europäischen Union und der ESA")
LIC_OSM = "ODbL, © OpenStreetMap contributors"

if os.environ.get("ROWCOACH_IPV4"):  # z. B. wenn die IPv6-Route zu Overpass hängt: nur IPv4 (gilt für requests)
    import socket
    import urllib3.util.connection as _uc
    _uc.allowed_gai_family = lambda: socket.AF_INET

os.environ.setdefault("GDAL_DISABLE_READDIR_ON_OPEN", "EMPTY_DIR")
os.environ.setdefault("GDAL_HTTP_USERAGENT", UA["User-Agent"])
os.environ.setdefault("CPL_VSIL_CURL_ALLOWED_EXTENSIONS", ".tif,.tiff,.TIF,.jp2,.vrt")
os.environ.setdefault("GDAL_HTTP_MAX_RETRY", "5")
os.environ.setdefault("GDAL_HTTP_RETRY_DELAY", "3")
os.environ.setdefault("GDAL_HTTP_MULTIRANGE", "YES")
os.environ.setdefault("GDAL_HTTP_MERGE_CONSECUTIVE_RANGES", "YES")

# ----------------------------------------------------------------------------- HTTP (höflich)

_LOCKS = {}
_LAST = {}
_GUARD = threading.Lock()


def _host_lock(url):
    host = urlparse(url).netloc
    with _GUARD:
        return host, _LOCKS.setdefault(host, threading.Lock())


def http(url, method="GET", params=None, data=None, json_body=None, headers=None, timeout=(30, 300), retries=6,
         pause=0.3, ok_status=(200,), stream=False):
    """Eine Anfrage, eine Verbindung je Server nacheinander, mit Pause und Wiederholung.
    Status in ok_status → Antwort; 404 → None (sofort); sonst nach max. retries Ausnahme."""
    host, lock = _host_lock(url)
    hdr = {**UA, **(headers or {})}
    last_err = None
    for attempt in range(retries):
        with lock:
            wait = _LAST.get(host, 0) + pause - time.time()
            if wait > 0:
                time.sleep(wait)
            try:
                r = requests.request(method, url, params=params, data=data, json=json_body, headers=hdr,
                                     timeout=timeout, stream=stream)
                if not stream:
                    _ = r.content
            except requests.RequestException as ex:
                r, last_err = None, ex
            finally:
                _LAST[host] = time.time()
        if r is not None:
            if r.status_code in ok_status:
                return r
            if r.status_code == 404:
                return None
            last_err = f"HTTP {r.status_code}: {r.text[:200] if not stream else ''}"
            ra = r.headers.get("Retry-After")
            if r.status_code < 500 and r.status_code != 429:
                raise RuntimeError(f"{url}: {last_err}")
        delay = min(120, 5 * 2 ** attempt)
        if r is not None and r.headers.get("Retry-After", "").isdigit():
            delay = max(delay, int(r.headers["Retry-After"]))
        print(f"  {host}: {last_err} – neuer Versuch in {delay} s", flush=True)
        time.sleep(delay)
    raise RuntimeError(f"{url}: aufgegeben nach {retries} Versuchen ({last_err})")


def download(url, dest: Path, **kw):
    """Datei laden, falls nicht vorhanden (atomar über .part). True = neu geladen, None = 404."""
    dest = Path(dest)
    if dest.exists() and dest.stat().st_size > 0:
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    r = http(url, stream=True, **kw)
    if r is None:
        return None
    tmp = dest.with_suffix(dest.suffix + ".part")
    with open(tmp, "wb") as f:
        for chunk in r.iter_content(1 << 20):
            f.write(chunk)
    tmp.rename(dest)
    return True


# ----------------------------------------------------------------------------- PROJ-Gitter

def ensure_proj_grids(src_crs, dst_crs="EPSG:4326"):
    """Fehlende PROJ-Gitter für die beste Umrechnung src → dst laden (cdn.proj.org, nur offene Lizenzen) und in den
    PROJ-Ordner von rasterio verlinken (GDAL im rasterio-Paket sucht nicht im Benutzerordner von pyproj).
    Beispiel: EPSG:27700 → OSTN15 (sonst bis 2 m Versatz gegenüber OpenStreetMap)."""
    import warnings
    from pyproj import datadir
    from pyproj.transformer import TransformerGroup
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        g = TransformerGroup(src_crs, dst_crs, always_xy=True)
        if not g.best_available:
            g.download_grids(open_license_only=True)
    user = Path(datadir.get_user_data_dir())
    rio = Path(rasterio.__file__).parent / "proj_data"
    if rio.is_dir() and os.access(rio, os.W_OK):
        for f in user.glob("*.tif"):
            link = rio / f.name
            if not link.exists():
                link.symlink_to(f)


# ----------------------------------------------------------------------------- Raster im Gebietssystem

@dataclass
class Grid:
    """Zielraster: bounds (E0, N0, E1, N1) im crs, Auflösung res (m); Ecke NW wie in der Pipeline."""
    bounds: tuple
    res: float
    crs: str

    @property
    def width(self):
        return int(round((self.bounds[2] - self.bounds[0]) / self.res))

    @property
    def height(self):
        return int(round((self.bounds[3] - self.bounds[1]) / self.res))

    @property
    def shape(self):
        return self.height, self.width

    @property
    def transform(self):
        return from_origin(self.bounds[0], self.bounds[3], self.res, self.res)

    def xy(self, step=1):
        """Mittelpunkte (E, N) der Pixel, jedes step-te."""
        e = self.bounds[0] + (np.arange(0, self.width, step) + 0.5) * self.res
        n = self.bounds[3] - (np.arange(0, self.height, step) + 0.5) * self.res
        return np.meshgrid(e, n)


def km_tiles(bounds, size=1000):
    """[(E_km, N_km)] der 1-km-Kacheln (bzw. size-Blöcke, dann in Vielfachen von size), die bounds berühren."""
    e0, n0, e1, n1 = bounds
    return [(e, n) for e in range(int(e0 // size) * size // 1000, int(math.ceil(e1 / size)) * size // 1000,
                                  size // 1000)
            for n in range(int(n0 // size) * size // 1000, int(math.ceil(n1 / size)) * size // 1000, size // 1000)]


def tile_grid(e_km, n_km, res, crs, size=1000):
    return Grid((e_km * 1000, n_km * 1000, e_km * 1000 + size, n_km * 1000 + size), res, crs)


def write_tif(path, arr, grid: Grid, nodata=None, rgb_jpeg=False):
    """float-Raster (H, W) bzw. (B, H, W) oder RGB uint8 (3, H, W) schreiben (atomar)."""
    arr = np.asarray(arr)
    if arr.ndim == 2:
        arr = arr[None]
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    prof = dict(driver="GTiff", width=grid.width, height=grid.height, count=arr.shape[0], dtype=arr.dtype.name,
                crs=grid.crs, transform=grid.transform, tiled=True, blockxsize=512, blockysize=512)
    if rgb_jpeg:
        prof.update(compress="jpeg", jpeg_quality=90, photometric="YCBCR", dtype="uint8")
    else:
        prof.update(compress="deflate", predictor=3 if arr.dtype.kind == "f" else 2)
        if arr.shape[0] == 3 and arr.dtype == np.uint8:
            prof["photometric"] = "RGB"
    if nodata is not None:
        prof["nodata"] = nodata
    tmp = path.with_suffix(".part.tif")
    with rasterio.open(tmp, "w", **prof) as dst:
        dst.write(arr)
    tmp.rename(path)
    return path


def warp_array(src, src_transform, src_crs, grid: Grid, resampling=Resampling.bilinear, src_nodata=None,
               dst_nodata=np.nan, dtype=np.float32):
    """Array (H, W) bzw. (B, H, W) aus beliebigem System auf grid umrechnen (fehlend = dst_nodata)."""
    src = np.asarray(src)
    multi = src.ndim == 3
    bands = src if multi else src[None]
    out = np.full((bands.shape[0], *grid.shape), dst_nodata, dtype)
    for k in range(bands.shape[0]):
        reproject(bands[k], out[k], src_transform=src_transform, src_crs=src_crs, src_nodata=src_nodata,
                  dst_transform=grid.transform, dst_crs=grid.crs, dst_nodata=dst_nodata, resampling=resampling)
    return out if multi else out[0]


def cog_read(url, grid: Grid, bands=None, resampling=Resampling.bilinear, nodata=None, dtype=np.float32,
             dst_nodata=np.nan):
    """(Cloud Optimized) GeoTIFF – Pfad oder https-URL (über /vsicurl/) – fensterweise direkt ins Grid lesen.
    nodata: Nodata-Wert der Quelle (sonst aus der Datei). Ausserhalb der Quelle: dst_nodata."""
    from rasterio.vrt import WarpedVRT
    path = f"/vsicurl/{url}" if str(url).startswith("http") else str(url)
    with rasterio.Env(GDAL_HTTP_USERAGENT=UA["User-Agent"]):
        with rasterio.open(path) as src:
            nd = nodata if nodata is not None else src.nodata
            idx = bands or list(range(1, src.count + 1))
            with WarpedVRT(src, crs=grid.crs, transform=grid.transform, width=grid.width, height=grid.height,
                           resampling=resampling, src_nodata=nd, nodata=nd if nd is not None else 0) as vrt:
                arr = vrt.read(idx, masked=True)
    out = arr.astype(dtype).filled(dst_nodata) if np.issubdtype(np.dtype(dtype), np.floating) else \
        arr.filled(0).astype(dtype)
    return out if bands is None or len(idx) > 1 else out[0]


def bounds_in(bounds, src_crs, dst_crs, margin=0.0):
    """Ausschnitt in ein anderes System (dicht abgetastet), mit Rand."""
    b = transform_bounds(src_crs, dst_crs, *bounds, densify_pts=41)
    return (b[0] - margin, b[1] - margin, b[2] + margin, b[3] + margin)


# ----------------------------------------------------------------------------- WCS 2.0.1

def wcs_tiles(cfg, bounds, area_crs, out_dir: Path, res, prefix="dtm", block_m=None, cache_dir=None):
    """Höhenmodell über WCS 2.0.1 holen und als Kacheln (1 km bei res ≤ 1 m, sonst 4 km) im Gebietssystem ablegen.

    cfg: {"url", "coverage", "crs" (System des Servers, z. B. "EPSG:27700"), "native_res" (m, Standard 1),
          "axes": ["E", "N"] (Achsnamen für subset), "nodata_below": −1e30 (kleiner = keine Daten),
          "block_m": 1000 (Blockgrösse je Anfrage; bei gröberer Auflösung mit SCALEFACTOR entsprechend grösser)}
    Ergebnis: Liste der geschriebenen Dateien; Rohblöcke im Cache (<out_dir>_src/), damit ein Abbruch nichts verliert.
    """
    out_dir = Path(out_dir)
    cache = Path(cache_dir or f"{out_dir}_src")
    cache.mkdir(parents=True, exist_ok=True)
    ncrs = cfg["crs"]
    ensure_proj_grids(ncrs, area_crs)
    nres = float(cfg.get("native_res", 1.0))
    scale = min(1.0, nres / res)
    bm = block_m or cfg.get("block_m") or (2000 if scale < 1 else 1000)  # grosse Blöcke laufen beim EA in Zeitüberschreitungen
    bm = int(bm)
    ax = cfg.get("axes", ["E", "N"])
    nb = cfg.get("nodata_below", -1e30)
    tile = 1000 if res <= 1.0 else 4000
    files = []
    for te, tn in km_tiles(bounds, tile):
        dest = out_dir / f"{prefix}_{te}-{tn}.tif"
        if dest.exists():
            files.append(dest)
            continue
        g = tile_grid(te, tn, res, area_crs, tile)
        nb_ = bounds_in(g.bounds, area_crs, ncrs, margin=3 * nres + 2)
        out = np.full(g.shape, np.nan, np.float32)
        for be in range(int(nb_[0] // bm) * bm, int(math.ceil(nb_[2] / bm)) * bm, bm):
            for bn in range(int(nb_[1] // bm) * bm, int(math.ceil(nb_[3] / bm)) * bm, bm):
                cf = cache / f"{cfg['coverage'][:12]}_{be}_{bn}_{bm}{'_s%g' % scale if scale < 1 else ''}.tif"
                if not cf.exists():
                    params = [("service", "WCS"), ("version", "2.0.1"), ("request", "GetCoverage"),
                              ("CoverageId", cfg["coverage"]), ("format", "image/tiff"),
                              ("subset", f"{ax[0]}({be},{be + bm})"), ("subset", f"{ax[1]}({bn},{bn + bm})")]
                    if scale < 1:
                        params.append(("SCALEFACTOR", f"{scale:g}"))
                    r = http(cfg["url"], params=params, timeout=(30, cfg.get("read_timeout", 120)), pause=cfg.get("pause", 1.0))
                    if r is None or "xml" in r.headers.get("content-type", ""):
                        cf.with_suffix(".empty").write_text((r.text[:500] if r is not None else "404") + "\n")
                        continue
                    tmp = cf.with_suffix(".part")
                    tmp.write_bytes(r.content)
                    tmp.rename(cf)
                with rasterio.open(cf) as src:
                    z = src.read(1).astype(np.float32)
                    z[(z < nb) | ~np.isfinite(z) | (z > 1e5)] = np.nan
                    if src.nodata is not None:
                        z[z == src.nodata] = np.nan
                    part = warp_array(z, src.transform, src.crs or ncrs, g,
                                      Resampling.average if res > 1.5 * nres / scale else Resampling.bilinear,
                                      src_nodata=np.nan)
                out = np.where(np.isnan(out), part, out)
        if np.isnan(out).all():
            print(f"  {prefix} {te}-{tn}: keine Daten", flush=True)
            continue
        write_tif(dest, np.where(np.isnan(out), NODATA, out).astype(np.float32), g, nodata=NODATA)
        files.append(dest)
        print(f"  {dest.name}: {np.isnan(out).mean() * 100:.1f} % Lücken", flush=True)
    return files


def cog_tiles(urls, bounds, area_crs, out_dir: Path, res, prefix="dtm", nodata=None, resampling=None):
    """Höhenmodell aus einer oder mehreren COG-Dateien (URLs/Pfade) als Kacheln ins Gebietssystem (1 km bzw. 4 km)."""
    out_dir = Path(out_dir)
    tile = 1000 if res <= 1.0 else 4000
    files = []
    for te, tn in km_tiles(bounds, tile):
        dest = out_dir / f"{prefix}_{te}-{tn}.tif"
        if dest.exists():
            files.append(dest)
            continue
        g = tile_grid(te, tn, res, area_crs, tile)
        out = np.full(g.shape, np.nan, np.float32)
        for u in urls:
            try:
                part = cog_read(u, g, bands=[1], nodata=nodata,
                                resampling=resampling or (Resampling.average if res > 1.5 else Resampling.bilinear))
            except rasterio.errors.RasterioIOError as ex:
                print(f"  {u}: {ex}", flush=True)
                continue
            part[(part < -1000) | (part > 1e5)] = np.nan
            out = np.where(np.isnan(out), part, out)
        if np.isnan(out).all():
            continue
        write_tif(dest, np.where(np.isnan(out), NODATA, out).astype(np.float32), g, nodata=NODATA)
        files.append(dest)
        print(f"  {dest.name}: {np.isnan(out).mean() * 100:.1f} % Lücken", flush=True)
    return files


# ----------------------------------------------------------------------------- Kachelschemata (COG-Sammlungen)

def kartverket_urls(bounds, area_crs, product="DTM1"):
    """Kartverket DTM1/DOM1 (Norwegen, 1 m, EPSG:25833, 15×15-km-Dateien 33-X-Y.tif)."""
    b = bounds_in(bounds, area_crs, "EPSG:25833", margin=10)
    xs = range(int((b[0] - 5425) // 15000) + 107, int((b[2] - 5425) // 15000) + 108)
    ys = range(int((b[1] - 6755995) // 15000) + 122, int((b[3] - 6755995) // 15000) + 123)
    return [f"https://nedlasting.geonorge.no/hoydedata/{product}/33-{x}-{y}.tif" for x in xs for y in ys]


TILE_SCHEMES = {"kartverket": kartverket_urls}


# ----------------------------------------------------------------------------- WMS GetMap (Höhen und Luftbild)

def _wms_get(cfg, layer, bb, w, h, fmt):
    params = {"SERVICE": "WMS", "VERSION": "1.3.0", "REQUEST": "GetMap", "LAYERS": layer, "STYLES": "",
              "CRS": cfg["crs"], "BBOX": f"{bb[0]:.3f},{bb[1]:.3f},{bb[2]:.3f},{bb[3]:.3f}", "WIDTH": w,
              "HEIGHT": h, "FORMAT": fmt, **cfg.get("params", {})}
    r = http(cfg["url"], params=params, timeout=(30, cfg.get("read_timeout", 180)), pause=cfg.get("pause", 0.3))
    if r is None or "xml" in r.headers.get("content-type", "") or "html" in r.headers.get("content-type", ""):
        return None
    return r.content


def wms_tiles(cfg, bounds, area_crs, out_dir: Path, res, prefix="dtm", rgb=False, tile=None):
    """Höhenmodell (float32-GeoTIFF) oder Luftbild (RGB) über WMS 1.3.0 GetMap holen und als Kacheln im
    Gebietssystem ablegen (Höhen: 1 km bei res ≤ 1 m, sonst 4 km; Luftbild: 1 km bei res ≤ 0,5 m, sonst 4 km).

    cfg: {"url", "layer", "crs" (System der Anfrage, z. B. "EPSG:2154"), "format" ("image/geotiff" bzw.
          "image/jpeg"), "fallback_layers": [...] (füllen Lücken, z. B. RGE ALTI unter LiDAR HD),
          "max_px": 5000 (Höchstbreite des Servers; die Kachel wird dann in Teilblöcke zerlegt),
          "nodata_below": −1000, "params": {...} (weitere Parameter), "pause", "read_timeout"}
    Georeferenz: aus der angefragten BBOX berechnet, nie aus der Datei (die Géoplateforme liefert ein kaputtes WKT
    mit Datum "unknown"; das System ist immer cfg["crs"]). Ergebnis: Liste der Dateien (vorhandene werden behalten).
    """
    from rasterio.io import MemoryFile
    from PIL import Image
    out_dir = Path(out_dir)
    ncrs = cfg["crs"]
    max_px = int(cfg.get("max_px", 5000))
    fmt = cfg.get("format", "image/jpeg" if rgb else "image/geotiff")
    nb = cfg.get("nodata_below", -1000)
    tile = tile or ((1000 if res <= 0.5 else 4000) if rgb else (1000 if res <= 1.0 else 4000))
    layers = [cfg["layer"]] + list(cfg.get("fallback_layers", []))
    files = []
    n_req = 0
    for te, tn in km_tiles(bounds, tile):
        dest = out_dir / f"{prefix}_{te}-{tn}.tif"
        if dest.exists():
            files.append(dest)
            continue
        g = tile_grid(te, tn, res, area_crs, tile)
        margin = 3 * res + 2
        nsub = max(1, math.ceil((tile + 2 * margin) * 1.002 / res / max_px))
        sub = tile / nsub
        out = np.zeros((3, *g.shape), np.uint8) if rgb else np.full(g.shape, np.nan, np.float32)
        for i in range(nsub):
            for j in range(nsub):
                sb = (g.bounds[0] + i * sub, g.bounds[1] + j * sub, g.bounds[0] + (i + 1) * sub,
                      g.bounds[1] + (j + 1) * sub)
                bb = bounds_in(sb, area_crs, ncrs, margin=margin)
                bb = (math.floor(bb[0] / res) * res, math.floor(bb[1] / res) * res,
                      math.ceil(bb[2] / res) * res, math.ceil(bb[3] / res) * res)
                w, h = int(round((bb[2] - bb[0]) / res)), int(round((bb[3] - bb[1]) / res))
                if max(w, h) > max_px + 10:
                    raise RuntimeError(f"wms_tiles: {w}×{h} px > max_px {max_px}")
                tr = from_origin(bb[0], bb[3], res, res)
                sg = Grid(sb, res, area_crs)
                c0 = int(round((sb[0] - g.bounds[0]) / res))
                r0 = int(round((g.bounds[3] - sb[3]) / res))
                win = (slice(r0, r0 + sg.height), slice(c0, c0 + sg.width))
                for layer in layers if not rgb else layers[:1]:
                    data = _wms_get(cfg, layer, bb, w, h, fmt)
                    n_req += 1
                    if data is None:
                        continue
                    if rgb:
                        im = np.moveaxis(np.asarray(Image.open(io.BytesIO(data)).convert("RGB")), -1, 0)
                        part = np.zeros((3, *sg.shape), np.uint8)
                        for k in range(3):
                            reproject(im[k], part[k], src_transform=tr, src_crs=ncrs, dst_transform=sg.transform,
                                      dst_crs=area_crs, resampling=Resampling.bilinear)
                        out[:, win[0], win[1]] = part
                        break
                    with MemoryFile(data) as mf, mf.open() as src:
                        z = src.read(1).astype(np.float32)
                        if src.nodata is not None:
                            z[z == src.nodata] = np.nan
                    z[(z < nb) | ~np.isfinite(z) | (z > 1e5)] = np.nan
                    part = warp_array(z, tr, ncrs, sg, Resampling.bilinear, src_nodata=np.nan)
                    o = out[win]
                    out[win] = np.where(np.isnan(o), part, o)
                    if not np.isnan(out[win]).any():
                        break
        if rgb:
            if out.max() == 0:
                continue
            write_tif(dest, out, g, rgb_jpeg=True)
            print(f"  {dest.name}", flush=True)
        else:
            if np.isnan(out).all():
                print(f"  {prefix} {te}-{tn}: keine Daten", flush=True)
                continue
            write_tif(dest, np.where(np.isnan(out), NODATA, out).astype(np.float32), g, nodata=NODATA)
            print(f"  {dest.name}: {np.isnan(out).mean() * 100:.1f} % Lücken", flush=True)
        files.append(dest)
    print(f"  WMS {cfg['layer']}: {len(files)} Kacheln, {n_req} Anfragen", flush=True)
    return files


# ----------------------------------------------------------------------------- WFS 2.0 (Gebäudeumrisse)

def wfs_features(url, typename, bounds, crs, page=5000, pause=0.3, extra=None):
    """Alle Objekte eines WFS-2.0-Layers im Ausschnitt als GeoJSON-Features (Koordinaten lon/lat, WGS84).
    BBOX in WGS84 (Achsfolge lat, lon nach EPSG:4326), seitenweise mit COUNT/STARTINDEX (sortiert nach Server-Vorgabe).
    Beispiel: data.geopf.fr/wfs/ows, typename "BDTOPO_V3:batiment"."""
    lon0, lat0, lon1, lat1 = bounds_in(bounds, crs, "EPSG:4326")
    feats, start = [], 0
    while True:
        params = {"SERVICE": "WFS", "VERSION": "2.0.0", "REQUEST": "GetFeature", "TYPENAMES": typename,
                  "OUTPUTFORMAT": "application/json", "BBOX": f"{lat0:.6f},{lon0:.6f},{lat1:.6f},{lon1:.6f}",
                  "COUNT": page, "STARTINDEX": start, **(extra or {})}
        d = http(url, params=params, pause=pause, timeout=(30, 300)).json()
        fs = d.get("features", [])
        feats += fs
        start += len(fs)
        matched = d.get("numberMatched")
        if not fs or len(fs) < page or (isinstance(matched, int) and start >= matched):
            break
    print(f"  WFS {typename}: {len(feats)} Objekte", flush=True)
    return feats


# ----------------------------------------------------------------------------- XYZ-Kacheln (Web Mercator)

def gsi_dem_png(rgb):
    """GSI-Höhenkacheln (dem5a_png u. a.): x = R·2¹⁶ + G·2⁸ + B; x < 2²³ → x·0,01 m, x > 2²³ → (x − 2²⁴)·0,01 m,
    x = 2²³ (128,0,0) = keine Daten. Wasser ist oft leer → NaN."""
    r, g, b = (rgb[..., k].astype(np.int64) for k in range(3))
    x = (r << 16) + (g << 8) + b
    z = np.where(x < 2 ** 23, x, x - 2 ** 24).astype(np.float32) * 0.01
    z[x == 2 ** 23] = np.nan
    return z


def terrarium(rgb):
    r, g, b = (rgb[..., k].astype(np.float32) for k in range(3))
    return r * 256 + g + b / 256 - 32768


def mapbox_rgb(rgb):
    r, g, b = (rgb[..., k].astype(np.float32) for k in range(3))
    return -10000 + (r * 65536 + g * 256 + b) * 0.1


DECODERS = {"gsi_dem_png": gsi_dem_png, "terrarium": terrarium, "mapbox": mapbox_rgb}
_R = 6378137.0


def _lonlat_to_tile(lon, lat, z):
    n = 2 ** z
    x = (lon + 180) / 360 * n
    y = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n
    return x, y


def xyz_read(url_tpl, zoom, grid: Grid, cache_dir: Path, decode=None, resampling=None, tile_px=256, pause=0.2,
             max_tiles=6000):
    """XYZ-Kacheln für das Grid holen (Cache cache_dir/z/x/y.ext), als Mosaik in EPSG:3857 zusammensetzen und ins
    Grid umrechnen. decode=None: RGB uint8 (3, H, W), fehlende Kacheln 0; decode=Name/Funktion: Höhen float32 (H, W),
    NaN ohne Daten. url_tpl mit {z}, {x}, {y}."""
    dec = DECODERS.get(decode, decode) if decode else None
    lon0, lat0, lon1, lat1 = bounds_in(grid.bounds, grid.crs, "EPSG:4326")
    x0, y0 = _lonlat_to_tile(lon0, lat1, zoom)
    x1, y1 = _lonlat_to_tile(lon1, lat0, zoom)
    xs, ys = range(int(x0), int(x1) + 1), range(int(y0), int(y1) + 1)
    if len(xs) * len(ys) > max_tiles:
        raise SystemExit(f"xyz_read: {len(xs) * len(ys)} Kacheln > {max_tiles} – Ausschnitt verkleinern")
    ext = Path(urlparse(url_tpl).path).suffix or ".png"
    from PIL import Image
    nb = 1 if dec else 3
    mos = np.full((nb, len(ys) * tile_px, len(xs) * tile_px), np.nan if dec else 0,
                  np.float32 if dec else np.uint8)
    n_new = 0
    for j, y in enumerate(ys):
        for i, x in enumerate(xs):
            f = Path(cache_dir) / str(zoom) / str(x) / f"{y}{ext}"
            if not f.exists() and not f.with_suffix(".none").exists():
                r = http(url_tpl.format(z=zoom, x=x, y=y), pause=pause, timeout=(20, 60))
                f.parent.mkdir(parents=True, exist_ok=True)
                if r is None or not r.content:
                    f.with_suffix(".none").write_text("")
                    continue
                f.write_bytes(r.content)
                n_new += 1
            if not f.exists():
                continue
            im = Image.open(f)
            if dec:
                a = np.asarray(im.convert("RGB"))
                mos[0, j * tile_px:(j + 1) * tile_px, i * tile_px:(i + 1) * tile_px] = dec(a)
            else:
                mos[:, j * tile_px:(j + 1) * tile_px, i * tile_px:(i + 1) * tile_px] = \
                    np.moveaxis(np.asarray(im.convert("RGB")), -1, 0)
    size = 2 * math.pi * _R / 2 ** zoom
    tr = from_origin(-math.pi * _R + xs[0] * size, math.pi * _R - ys[0] * size, size / tile_px, size / tile_px)
    print(f"  xyz z{zoom}: {len(xs) * len(ys)} Kacheln ({n_new} neu)", flush=True)
    if dec:
        return warp_array(mos[0], tr, "EPSG:3857", grid, resampling or Resampling.bilinear, src_nodata=np.nan)
    # direkt als uint8 umrechnen (float32 bräuchte für grosse Umgebungen > 1 GB)
    return warp_array(mos, tr, "EPSG:3857", grid, resampling or Resampling.bilinear, src_nodata=0, dst_nodata=0,
                      dtype=np.uint8)


# ----------------------------------------------------------------------------- ArcGIS REST

def arcgis_features(url, bounds, crs, where="1=1", out_fields="*", page=None, pause=0.3):
    """Alle Objekte eines ArcGIS-Layers (…/FeatureServer/<n> bzw. MapServer/<n>) im Ausschnitt als GeoJSON-Features
    (WGS84). Seitenweise über resultOffset; kann der Dienst das nicht, über die Objekt-IDs in Paketen."""
    lon0, lat0, lon1, lat1 = bounds_in(bounds, crs, "EPSG:4326")
    meta = http(url, params={"f": "json"}).json()
    page = page or int(meta.get("maxRecordCount", 1000))
    base = {"where": where, "outFields": out_fields, "geometry": f"{lon0},{lat0},{lon1},{lat1}",
            "geometryType": "esriGeometryEnvelope", "inSR": 4326, "spatialRel": "esriSpatialRelIntersects",
            "outSR": 4326, "f": "geojson"}
    feats = []
    if meta.get("advancedQueryCapabilities", {}).get("supportsPagination", True):
        off = 0
        while True:
            r = http(f"{url}/query", params={**base, "resultOffset": off, "resultRecordCount": page}, pause=pause)
            d = r.json()
            if "error" in d:
                raise RuntimeError(d["error"])
            fs = d.get("features", [])
            feats += fs
            if len(fs) < page and not d.get("exceededTransferLimit") and not d.get("properties", {}).get(
                    "exceededTransferLimit"):
                break
            if not fs:
                break
            off += len(fs)
    else:
        ids = http(f"{url}/query", params={**base, "returnIdsOnly": "true", "f": "json"}).json()["objectIds"] or []
        for k in range(0, len(ids), page):
            r = http(f"{url}/query", params={"objectIds": ",".join(map(str, ids[k:k + page])),
                                             "outFields": out_fields, "outSR": 4326, "f": "geojson"}, pause=pause)
            feats += r.json().get("features", [])
    print(f"  ArcGIS {url.rsplit('/', 2)[-2]}: {len(feats)} Objekte", flush=True)
    return feats


# ----------------------------------------------------------------------------- Sentinel-2 (Earth Search)

def s2_scenes(bbox_wgs, months=(6, 7, 5, 8), years=None, max_cloud=20, limit=100):
    """Sentinel-2-L2A-Szenen (collection sentinel-2-c1-l2a) über der Box, sortiert nach Bewölkung der Kachel;
    Monate in Vorrangreihenfolge (Frühsommer zuerst: Wiesen grün, Bäume belaubt)."""
    years = years or [date.today().year - 1, date.today().year - 2, date.today().year]
    out = []
    for y in years:
        body = {"collections": ["sentinel-2-c1-l2a"], "bbox": list(bbox_wgs),
                "datetime": f"{y}-{min(months):02d}-01T00:00:00Z/{y}-{max(months):02d}-28T23:59:59Z",
                "query": {"eo:cloud_cover": {"lt": max_cloud}}, "limit": limit,
                "sortby": [{"field": "properties.eo:cloud_cover", "direction": "asc"}]}
        r = http(STAC_SEARCH, method="POST", json_body=body, headers={"Content-Type": "application/json"})
        out += r.json().get("features", [])
    rank = {m: i for i, m in enumerate(months)}
    for f in out:
        f["_month"] = int(f["properties"]["datetime"][5:7])
    out.sort(key=lambda f: (round(f["properties"]["eo:cloud_cover"] / 5), rank.get(f["_month"], 9)))
    return out


def _grade_s2(rgb, valid):
    """Sentinel-2 „visual“ wirkt flau: Schwarzpunkt/Weisspunkt aus den Perzentilen, leichtes Gamma, etwas Sättigung."""
    x = rgb.astype(np.float32)
    v = valid & (x.max(axis=0) > 0)
    if v.sum() < 100:
        return rgb
    lo = np.array([np.percentile(x[k][v], 0.5) for k in range(3)])
    hi = np.array([np.percentile(x[k][v], 99.7) for k in range(3)])
    lo_m, hi_m = lo.min(), hi.max()
    y = np.clip((x - lo_m) / max(hi_m - lo_m, 1), 0, 1) ** 0.9
    g = y.mean(axis=0, keepdims=True)
    y = np.clip(g + (y - g) * 1.15, 0, 1)
    return np.where(v[None], y * 255 + 0.5, 0).astype(np.uint8)


def s2_far(grid: Grid, cache_dir: Path, months=(6, 7, 5, 8), years=None, max_scenes=4, max_cloud=20):
    """Wolkenfreies Sentinel-2-Mosaik (RGB uint8, 10 m Quelle) auf grid. Wählt die Szenen nach dem örtlichen
    Wolkenanteil (SCL 3 Schatten, 8–10 Wolken/Zirren) und füllt Pixel aus der nächsten Szene. Liefert (rgb, Liste der
    verwendeten Szenen-IDs mit Datum)."""
    bb = bounds_in(grid.bounds, grid.crs, "EPSG:4326")
    scenes = s2_scenes(bb, months, years, max_cloud)
    if not scenes:
        raise SystemExit("Sentinel-2: keine Szene gefunden")
    g20 = Grid(grid.bounds, max(grid.res, 20.0), grid.crs)
    rated = []
    for f in scenes[:12]:
        scl = cog_read(f["assets"]["scl"]["href"], g20, bands=[1], resampling=Resampling.nearest, dtype=np.uint8)
        bad = np.isin(scl, [0, 1, 3, 8, 9, 10])
        rated.append((bad.mean(), f, scl))
        if bad.mean() < 0.002:
            break
    rated.sort(key=lambda t: (round(t[0], 3), int(t[1]["_month"] not in months[:2])))
    rgb = np.zeros((3, *grid.shape), np.uint8)
    hole = np.ones(grid.shape, bool)
    used = []
    for frac, f, scl in rated[:max_scenes]:
        if not hole.any():
            break
        img = cog_read(f["assets"]["visual"]["href"], grid, bands=[1, 2, 3], resampling=Resampling.bilinear,
                       dtype=np.uint8)
        badc = warp_array(np.isin(scl, [0, 1, 3, 8, 9, 10]).astype(np.float32), g20.transform, grid.crs, grid,
                          Resampling.nearest, dst_nodata=1.0) > 0.5
        ok = (img.max(axis=0) > 0) & ~badc
        take = hole & ok
        rgb[:, take] = img[:, take]
        hole &= ~take
        used.append({"id": f["id"], "datetime": f["properties"]["datetime"], "cloud_local": round(float(frac), 4)})
        print(f"  Sentinel-2 {f['id']}: örtlich {frac * 100:.1f} % Wolken, offen {hole.mean() * 100:.1f} %", flush=True)
    return _grade_s2(rgb, ~hole), used


# ----------------------------------------------------------------------------- OpenStreetMap, Copernicus, Log

def overpass(query, dest: Path, tries=6):
    """Overpass-Abfrage → Datei (einmal; vorhandene Datei wird behalten). Ausweich-Instanzen bei Überlast."""
    dest = Path(dest)
    if dest.exists() and dest.stat().st_size > 0:
        return json.loads(dest.read_text())
    dest.parent.mkdir(parents=True, exist_ok=True)
    for k in range(tries):
        url = OVERPASS_MIRRORS[k % len(OVERPASS_MIRRORS)]
        try:
            r = http(url, method="POST", data={"data": query}, retries=2, timeout=(30, 400), pause=1.0)
            d = r.json()
            dest.write_bytes(r.content)
            dest.with_suffix(".overpassql").write_text(query)
            return d
        except (RuntimeError, ValueError) as ex:
            print(f"  overpass {url}: {ex} – nächster Versuch in {30 * (k + 1)} s", flush=True)
            time.sleep(30 * (k + 1))
    raise SystemExit("Overpass: fehlgeschlagen – später erneut")


def copernicus_tiles(bbox_wgs):
    """Kachelnamen Copernicus DEM GLO-30 (1°×1°) für eine Box (lon0, lat0, lon1, lat1)."""
    out = []
    for lat in range(math.floor(bbox_wgs[1]), math.floor(bbox_wgs[3]) + 1):
        for lon in range(math.floor(bbox_wgs[0]), math.floor(bbox_wgs[2]) + 1):
            ns, ew = ("N" if lat >= 0 else "S"), ("E" if lon >= 0 else "W")
            out.append(f"Copernicus_DSM_COG_10_{ns}{abs(lat):02d}_00_{ew}{abs(lon):03d}_00_DEM")
    return out


def log_source(root: Path, entry: dict):
    """Eintrag in fetch-log.json (gleiche Quelle → ersetzt), mit Abrufdatum."""
    f = Path(root) / "fetch-log.json"
    log = json.loads(f.read_text()) if f.exists() else []
    entry = {**entry, "retrieved_at": entry.get("retrieved_at", date.today().isoformat())}
    log = [e for e in log if e.get("source") != entry["source"]] + [entry]
    f.write_text(json.dumps(log, indent=1, ensure_ascii=False))


# ----------------------------------------------------------------------------- Eingaben für trees.py

def _mosaic_into(files, grid: Grid, band=1, resampling=Resampling.average):
    out = np.full((grid.height, grid.width), np.nan, np.float32)
    for f in files:
        with rasterio.open(f) as s:
            b = s.bounds
            if b.right <= grid.bounds[0] or b.left >= grid.bounds[2] or b.top <= grid.bounds[1] or \
                    b.bottom >= grid.bounds[3]:
                continue
            a = s.read(band).astype(np.float32)
            if s.nodata is not None:
                a[a == s.nodata] = np.nan
            a[a < -1000] = np.nan
            part = warp_array(a, s.transform, s.crs, grid, resampling, src_nodata=np.nan)
        out = np.where(np.isnan(out), part, out)
    return out


def trees_inputs(area, build: Path = None, raw: Path = None):
    """chm.tif (bdom − dgm, 0,5 m, 0…80 m) und ortho_core.tif (RGB 1 m) im Raster von trees.py (Kerngebiet, Ecke NW),
    aus beliebig benannten Kacheln in <data_dir>/bdom, dgm (bzw. raster_dirs alti_core) und image_core."""
    crs = area["crs"]
    raw = raw or (Path.cwd() / area["data_dir"]).resolve()
    build = build or Path("build") / area["id"]
    build.mkdir(parents=True, exist_ok=True)
    core = tuple(area["core_lv95"])
    alti = area.get("raster_dirs", {}).get("alti_core", "dgm")
    f = build / "chm.tif"
    if not f.exists() and area.get("chm_from") == "ortho":
        chm_from_ortho(area, raw, f)
    if not f.exists():
        g = Grid(core, 0.5, crs)
        dsm = _mosaic_into(sorted((raw / "bdom").glob("*.tif")), g, resampling=Resampling.bilinear)
        dtm = _mosaic_into(sorted((raw / alti).glob("*.tif")), g, resampling=Resampling.bilinear)
        chm = np.where(np.isnan(dsm) | np.isnan(dtm), 0, np.clip(dsm - dtm, 0, 80)).astype(np.float32)
        write_tif(f, chm, g)
        print(f"{f}: {g.width}×{g.height} px, 0.5 m", flush=True)
    f = build / "ortho_core.tif"
    if not f.exists():
        g = Grid(core, 1.0, crs)
        img = np.zeros((3, *g.shape), np.uint8)
        for p in sorted((raw / "image_core").glob("dop_*.tif")):
            with rasterio.open(p) as s:
                a = s.read([1, 2, 3])
                part = warp_array(a.astype(np.float32), s.transform, s.crs, g, Resampling.average, src_nodata=None,
                                  dst_nodata=-1)
            m = part[0] >= 0
            img[:, m] = np.clip(part[:, m] + 0.5, 0, 255).astype(np.uint8)
        write_tif(f, img, g)
        print(f"{f}: {g.width}×{g.height} px, 1 m", flush=True)


def chm_from_ortho(area, raw: Path, dest: Path, res=0.5):
    """Ersatz-Vegetationshöhe (chm.tif) ohne Oberflächenmodell, nur aus dem Luftbild (Gebietsfeld
    "chm_from": "ortho"; z. B. Japan: GSI hat kein offenes DSM). Baumkronen = grün (2G − R − B) UND rau (Anteil
    der Grünpixel mit örtlicher Helligkeitsstreuung über 2,5 m, gemittelt über 4,5 m: Kronen werfen Eigenschatten,
    Rasen und Felder sind glatt); schmale Streifen und kleine Flecken weg. Höhe aus dem Abstand zum Kronenrand
    (3 m + 1,8 × Abstand, höchstens 14 m) plus ortsfestes Rauschen (± 1,2 m, ~4 m), damit trees.py in Reihen und
    Hainen einzelne Kronen findet. Je km-Kachel (Speicher); Gebäude und Wasser schneidet trees.py aus.
    Grenzen: Höhen sind geschätzt; Gebüsch und Schilf am Ufer können als Kronen gelten, kahle Bäume fehlen."""
    from scipy import ndimage
    crs = area["crs"]
    core = tuple(area["core_lv95"])
    G = Grid(core, res, crs)
    chm = np.zeros(G.shape, np.float32)
    n_tree = 0
    for te, tn in km_tiles(core):
        p = raw / "image_core" / f"dop_{te}-{tn}.tif"
        if not p.exists():
            continue
        b = (max(te * 1000, core[0]), max(tn * 1000, core[1]), min(te * 1000 + 1000, core[2]),
             min(tn * 1000 + 1000, core[3]))
        g = Grid(b, res, crs)
        with rasterio.open(p) as s:
            a = warp_array(s.read([1, 2, 3]).astype(np.float32), s.transform, s.crs, g, Resampling.average,
                           src_nodata=None, dst_nodata=0)
        r, gg, bb = a
        bright = (r + gg + bb) / 3
        exg = 2 * gg - r - bb
        green = (exg > 14) & (gg >= r) & (bright < 170) & (bright > 20)
        m1 = ndimage.uniform_filter(bright, 5)
        sd = np.sqrt(np.maximum(ndimage.uniform_filter(bright * bright, 5) - m1 * m1, 0))
        score = ndimage.uniform_filter((green & (sd > 7)).astype(np.float32), 9)  # Anteil rauer Grünpixel, 4,5 m
        tree = (score > 0.45) & green
        tree = ndimage.binary_opening(ndimage.binary_closing(tree, iterations=2), iterations=3)
        lab, n = ndimage.label(tree)
        if n:
            sizes = ndimage.sum(tree, lab, range(1, n + 1)) * res * res
            tree = np.isin(lab, 1 + np.nonzero(sizes >= 20)[0])
        dist = ndimage.distance_transform_edt(tree).astype(np.float32) * res
        rng = np.random.default_rng(abs(hash((te, tn))) % (2 ** 32))
        noise = ndimage.gaussian_filter(rng.standard_normal(tree.shape).astype(np.float32), 4.0 / res)
        noise *= 1.2 / max(float(noise.std()), 1e-6)
        h = np.where(tree, np.clip(3.0 + 1.8 * dist, 3.0, 14.0) + noise, 0).astype(np.float32)
        r0 = int(round((core[3] - b[3]) / res)); c0 = int(round((b[0] - core[0]) / res))
        chm[r0:r0 + h.shape[0], c0:c0 + h.shape[1]] = h
        n_tree += int(tree.sum())
        del a, r, gg, bb, bright, exg, green, m1, sd, dist, noise, h
    write_tif(dest, chm, G)
    print(f"{dest}: aus dem Luftbild, Kronenfläche {n_tree * res * res / 1e4:.1f} ha", flush=True)
