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
                        z. B. Géoplateforme/IGN mit kaputtem WKT; "axis_order": "ne" für Server, die in WMS 1.3.0
                        die EPSG-Achsfolge Nord, Ost verlangen, z. B. GUGiK in EPSG:2180) → Kacheln im Gebietssystem
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
z. B. "kartverket" (Norwegen, DTM1/DOM1 15×15 km, EPSG:25833) und "bev_als" (Österreich, ALS DTM/DSM 1 m,
50×50 km, EPSG:3035; Stichtag über "stand"). Ein Land ergänzt sein Schema dort.

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
            try:
                g.download_grids(open_license=True)       # pyproj ≥ 3.0
            except TypeError:
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
          "block_m": 1000 (Blockgrösse je Anfrage; bei gröberer Auflösung mit SCALEFACTOR entsprechend grösser),
          "format": "image/tiff" (GUGiK NMPT: "image/x-aaigrid", Multipart-Antwort → _wcs_payload)}
    Polen (GUGiK, EPSG:2180): axes ["x", "y"] = Ost, Nord; NMT als float32-TIFF (DigitalTerrainModelFormatTIFF),
    NMPT nur als ASCII-Grid 0,5 m (DigitalSurfaceModel, native_res 0.5 → SCALEFACTOR 0.5 für 1 m, ~50 s und 20 MB je km²).
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
                              ("CoverageId", cfg["coverage"]), ("format", cfg.get("format", "image/tiff")),
                              ("subset", f"{ax[0]}({be},{be + bm})"), ("subset", f"{ax[1]}({bn},{bn + bm})")]
                    if scale < 1:
                        params.append(("SCALEFACTOR", f"{scale:g}"))
                    r = http(cfg["url"], params=params, timeout=(30, cfg.get("read_timeout", 120)), pause=cfg.get("pause", 1.0))
                    if r is None or "xml" in r.headers.get("content-type", ""):
                        cf.with_suffix(".empty").write_text((r.text[:500] if r is not None else "404") + "\n")
                        continue
                    tmp = cf.with_suffix(".part")
                    tmp.write_bytes(_wcs_payload(r, cf, ncrs))
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


def _wcs_payload(r, cf, ncrs):
    """Antwort einer GetCoverage-Anfrage → GeoTIFF-Bytes. Multipart-Antworten (GUGiK NMPT: nur "image/x-aaigrid",
    Arc/Info-ASCII-Grid als Teil "coverage data") werden ausgepackt und als float32-GeoTIFF (System ncrs) abgelegt."""
    ct = r.headers.get("content-type", "")
    body = r.content
    if not ct.startswith("multipart/") and b"ncols" not in body[:200]:
        return body
    if ct.startswith("multipart/"):
        bnd = ct.split("boundary=")[-1].strip().strip('"').encode()
        for part in body.split(b"--" + bnd):
            head, sep, data = part.partition(b"\r\n\r\n")
            if not sep:
                head, sep, data = part.partition(b"\n\n")
            if b"aaigrid" in head or data.lstrip()[:5] == b"ncols":
                body = data.rstrip(b"\r\n-")
                break
    from rasterio.io import MemoryFile
    with MemoryFile(body, ext=".asc") as mf, mf.open() as src:
        z, tr, nod = src.read(1).astype(np.float32), src.transform, src.nodata
    if nod is not None:
        z[z == nod] = NODATA
    out = io.BytesIO()
    with rasterio.open(out, "w", driver="GTiff", width=z.shape[1], height=z.shape[0], count=1, dtype="float32",
                       crs=ncrs, transform=tr, nodata=NODATA, compress="deflate") as dst:
        dst.write(z, 1)
    return out.getvalue()


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


def bev_als_urls(bounds, area_crs, product="DTM", stand="20250915"):
    """BEV ALS-Höhenraster DTM/DSM (Österreich, 1 m, EPSG:3035/LAEA, COG je 50×50 km,
    ALS_<DTM|DSM>_CRS3035RES50000mN<N>E<E>.tif mit E/N = Südwestecke; CC BY 4.0, Stichtag `stand`)."""
    b = bounds_in(bounds, area_crs, "EPSG:3035", margin=10)
    es = range(int(b[0] // 50000), int(b[2] // 50000) + 1)
    ns = range(int(b[1] // 50000), int(b[3] // 50000) + 1)
    return [f"https://data.bev.gv.at/download/ALS/{product}/{stand}/ALS_{product}_CRS3035RES50000m"
            f"N{n * 50000}E{e * 50000}.tif" for e in es for n in ns]


def usgs_1m_urls(bounds, area_crs, product="MA_CentralEastern_2021_B21"):
    """USGS 3DEP 1-m-DEM (USA, gemeinfrei; COG je 10 × 10 km in NAD83/UTM der Zone, Höhen NAVD88 m) eines
    Lidar-Projekts `product` (Name wie in StagedProducts/Elevation/1m/Projects, z. B. "MA_CentralEastern_2021_B21"):
    USGS_1M_<zone>_x<X>y<Y>_<projekt>.tif mit X = E // 10 km (West), Y = ⌈N / 10 km⌉ (Nordrand). Welche Projekte es
    über einem Gebiet gibt, nennt die TNM-API (tnmaccess.nationalmap.gov/api/v1/products?datasets=Digital Elevation
    Model (DEM) 1 meter&bbox=…). Fehlende Kacheln (Projektrand) geben 404 und werden übersprungen."""
    zone = int(str(area_crs).split(":")[1]) - 26900
    if not 1 <= zone <= 23:
        raise SystemExit(f"usgs_1m: {area_crs} ist kein NAD83/UTM-System (EPSG:26901–26923)")
    xs = range(int(bounds[0] // 10000), int(bounds[2] // 10000) + 1)
    ys = range(int(math.ceil(bounds[1] / 10000)), int(math.ceil(bounds[3] / 10000)) + 1)
    return [f"https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/1m/Projects/{product}/TIFF/"
            f"USGS_1M_{zone}_x{x}y{y}_{product}.tif" for x in xs for y in ys]


TILE_SCHEMES = {"kartverket": kartverket_urls, "bev_als": bev_als_urls, "usgs_1m": usgs_1m_urls}


# ----------------------------------------------------------------------------- Lidar-Punktwolke (EPT) → DSM

def ept_dsm_tiles(cfg, bounds, area_crs, out_dir: Path, res=1.0, prefix="dsm", cache_dir: Path = None,
                  fill_dir: Path = None):
    """Oberflächenmodell (höchster Punkt je Zelle, „highest hit“) aus einer Lidar-Punktwolke im Entwine-Point-Tile-
    Format (EPT; USGS 3DEP: s3-us-west-2.amazonaws.com/usgs-lidar-public/<projekt>/ept.json, gemeinfrei), wo es kein
    fertiges DSM gibt (USA). cfg: {"url": ".../ept.json", "max_depth": 10, "skip_classes": [7, 18]}.

    EPT ist ein Oktalbaum: Tiefe d hat Knoten der Kantenlänge (Würfel)/2^d mit je etwa span² Punkten; alle Knoten bis
    max_depth zusammen geben eine gleichmässig ausgedünnte Wolke (USGS Massachusetts 2021: bis Tiefe 10 ≈ 5 Punkte/m²,
    voll ≈ 15/m²; für 1 m reicht 10). Geladen werden nur die Knoten über `bounds` (LAZ, Cache cache_dir), Punkte der
    Klassen skip_classes (Rauschen) und „withheld“ fallen weg, Brückendecks (Klasse 17) bleiben. Zellen ohne Punkt:
    Lücken bis 2 m schliesst der Nachbar-Höchstwert, der Rest (Wasser, Lidar-Schatten) kommt aus dem Geländemodell
    fill_dir (dtm_E-N.tif der gleichen Kacheln), sonst nodata. Höhen wie die Quelle (USGS: NAVD88 m, horizontal
    EPSG:3857 → Gebietssystem). Braucht laspy mit lazrs (in .venv). Ergebnis: <prefix>_E-N.tif je km-Kachel."""
    import laspy
    from pyproj import Transformer
    from scipy import ndimage
    out_dir = Path(out_dir)
    tiles = km_tiles(bounds)
    todo = [(te, tn) for te, tn in tiles if not (out_dir / f"{prefix}_{te}-{tn}.tif").exists()]
    if not todo:
        return [out_dir / f"{prefix}_{te}-{tn}.tif" for te, tn in tiles]
    e0 = min(t[0] for t in todo) * 1000
    n0 = min(t[1] for t in todo) * 1000
    g = Grid((e0, n0, (max(t[0] for t in todo) + 1) * 1000, (max(t[1] for t in todo) + 1) * 1000), res, area_crs)
    dsm = np.full(g.shape, -np.inf, np.float32)
    base = cfg["url"].rsplit("/", 1)[0] + "/"
    ept = http(cfg["url"]).json()
    srs = f"EPSG:{ept['srs'].get('horizontal', '3857')}"
    to_area = Transformer.from_crs(srs, area_crs, always_xy=True)
    bx0, by0, _, bx1, by1, _ = ept["bounds"]
    bb = bounds_in(g.bounds, area_crs, srs, margin=5)
    max_depth = int(cfg.get("max_depth", 10))
    skip = np.array(cfg.get("skip_classes", [7, 18]))
    cache_dir = Path(cache_dir or out_dir.parent / "ept_cache")
    hier = {}

    def hierarchy(key):
        f = cache_dir / "hierarchy" / f"{key}.json"
        if not f.exists():
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_text(http(base + f"ept-hierarchy/{key}.json").text)
        return json.loads(f.read_text())

    keys = []

    def walk(key, h):
        d, x, y, z = map(int, key.split("-"))
        s = (bx1 - bx0) / 2 ** d
        nx, ny = bx0 + x * s, by0 + y * s
        if d > max_depth or nx > bb[2] or nx + s < bb[0] or ny > bb[3] or ny + s < bb[1] or key not in h:
            return
        if h[key] == -1:
            h = hierarchy(key)
        if h[key] > 0:
            keys.append(key)
        for dx in (0, 1):
            for dy in (0, 1):
                for dz in (0, 1):
                    walk(f"{d + 1}-{2 * x + dx}-{2 * y + dy}-{2 * z + dz}", h)

    walk("0-0-0-0", hierarchy("0-0-0-0"))
    print(f"  EPT {base}: {len(keys)} Knoten bis Tiefe {max_depth}", flush=True)
    n_pts = 0
    for i, key in enumerate(keys):
        f = cache_dir / "data" / f"{key}.laz"
        if download(base + f"ept-data/{key}.laz", f, pause=0.05) is None:
            continue
        las = laspy.read(f)
        keep = ~np.isin(np.asarray(las.classification), skip)
        try:
            keep &= ~np.asarray(las.withheld, bool)
        except (AttributeError, ValueError):
            pass
        if not keep.any():
            continue
        e, n = to_area.transform(np.asarray(las.x)[keep], np.asarray(las.y)[keep])
        zz = np.asarray(las.z, np.float32)[keep]
        col = ((e - g.bounds[0]) / res).astype(np.int64)
        row = ((g.bounds[3] - n) / res).astype(np.int64)
        ok = (col >= 0) & (col < g.width) & (row >= 0) & (row < g.height)
        np.maximum.at(dsm, (row[ok], col[ok]), zz[ok])
        n_pts += int(ok.sum())
        if (i + 1) % 250 == 0:
            print(f"  EPT {i + 1}/{len(keys)} Knoten, {n_pts / 1e6:.0f} Mio. Punkte", flush=True)
    dsm[~np.isfinite(dsm)] = np.nan
    hole = np.isnan(dsm)
    near = ndimage.maximum_filter(np.where(hole, -np.inf, dsm), size=5)
    small = hole & np.isfinite(near) & ~ndimage.binary_opening(hole, np.ones((5, 5), bool))
    dsm[small] = near[small]
    print(f"  EPT: {n_pts / 1e6:.0f} Mio. Punkte, {n_pts / (g.width * g.height * res * res):.1f}/m², "
          f"Lücken {np.isnan(dsm).mean() * 100:.1f} % (Wasser, Schatten)", flush=True)
    files = []
    for te, tn in tiles:
        dest = out_dir / f"{prefix}_{te}-{tn}.tif"
        if (te, tn) in todo:
            tg = tile_grid(te, tn, res, area_crs)
            r0 = int(round((g.bounds[3] - tg.bounds[3]) / res))
            c0 = int(round((tg.bounds[0] - g.bounds[0]) / res))
            part = dsm[r0:r0 + tg.height, c0:c0 + tg.width].copy()
            ft = Path(fill_dir) / f"dtm_{te}-{tn}.tif" if fill_dir else None
            if ft is not None and ft.exists() and np.isnan(part).any():
                with rasterio.open(ft) as src:
                    dtm = src.read(1).astype(np.float32)
                    if src.nodata is not None:
                        dtm[dtm == src.nodata] = np.nan
                part = np.where(np.isnan(part), dtm, np.maximum(part, np.nan_to_num(dtm, nan=-1e9)))
            if np.isnan(part).all():
                continue
            write_tif(dest, np.where(np.isnan(part), NODATA, part).astype(np.float32), tg, nodata=NODATA)
        files.append(dest)
    return files


# ----------------------------------------------------------------------------- WMS GetMap (Höhen und Luftbild)

def _wms_get(cfg, layer, bb, w, h, fmt):
    if cfg.get("axis_order") == "ne":  # WMS 1.3.0 mit Achsfolge Nord, Ost (z. B. EPSG:2180 bei GUGiK)
        bb = (bb[1], bb[0], bb[3], bb[2])
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

def wfs_features(url, typename, bounds, crs, page=5000, pause=0.3, extra=None, native_crs=None):
    """Alle Objekte eines WFS-2.0-Layers im Ausschnitt als GeoJSON-Features (Koordinaten lon/lat, WGS84).
    BBOX in WGS84 (Achsfolge lat, lon nach EPSG:4326), seitenweise mit COUNT/STARTINDEX (sortiert nach Server-Vorgabe).
    Beispiel: data.geopf.fr/wfs/ows, typename "BDTOPO_V3:batiment".
    native_crs (z. B. "EPSG:28992" für 3D BAG): BBOX in diesem System (x, y), die Koordinaten der Antwort stehen dann
    ebenfalls darin (der Aufrufer rechnet um)."""
    if native_crs:
        x0, y0, x1, y1 = bounds_in(bounds, crs, native_crs)
        bbox = f"{x0:.2f},{y0:.2f},{x1:.2f},{y1:.2f}"
    else:
        lon0, lat0, lon1, lat1 = bounds_in(bounds, crs, "EPSG:4326")
        bbox = f"{lat0:.6f},{lon0:.6f},{lat1:.6f},{lon1:.6f}"
    feats, start = [], 0
    while True:
        params = {"SERVICE": "WFS", "VERSION": "2.0.0", "REQUEST": "GetFeature", "TYPENAMES": typename,
                  "OUTPUTFORMAT": "application/json", "BBOX": bbox,
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
    Grenzen: Höhen sind geschätzt; Gebüsch und Schilf am Ufer können als Kronen gelten, kahle Bäume fehlen.
    Mit "chm_osm_wood": true kommen Wald und Gebüsch aus OpenStreetMap dazu (natural=wood, landuse=forest,
    natural=scrub): ein synthetisches Kronendach (siehe _wood_canopy) – für synthetische Luftbilder, in denen der
    Wald eine glatte Textur ohne Kronenschatten ist (Rio de Janeiro: Mata Atlântica an den Hängen um die Lagoa)."""
    from scipy import ndimage
    crs = area["crs"]
    core = tuple(area["core_lv95"])
    G = Grid(core, res, crs)
    chm = np.zeros(G.shape, np.float32)
    n_tree = 0
    wood = _osm_wood(area, raw) if area.get("chm_osm_wood") else None
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
        if wood:
            h = np.maximum(h, _wood_canopy(wood, g, rng))
        r0 = int(round((core[3] - b[3]) / res)); c0 = int(round((b[0] - core[0]) / res))
        chm[r0:r0 + h.shape[0], c0:c0 + h.shape[1]] = h
        n_tree += int(tree.sum())
        del a, r, gg, bb, bright, exg, green, m1, sd, dist, noise, h
    write_tif(dest, chm, G)
    print(f"{dest}: aus dem Luftbild, Kronenfläche {n_tree * res * res / 1e4:.1f} ha", flush=True)


def _osm_wood(area, raw: Path):
    """Wald- und Gebüschflächen aus <data_dir>/osm/landcover.json → [(Polygon im Gebietssystem, "wood"|"scrub")]."""
    from shapely.geometry import Polygon
    from shapely.ops import unary_union
    from common import _rings, _xy, to_proj
    tr = to_proj(area)
    out = []
    for el in json.loads((raw / "osm" / "landcover.json").read_text())["elements"]:
        t = el.get("tags", {})
        kind = "wood" if t.get("natural") == "wood" or t.get("landuse") == "forest" else \
            ("scrub" if t.get("natural") == "scrub" else None)
        if kind is None:
            continue
        if el["type"] == "way" and "geometry" in el:
            pts = _xy(el["geometry"], tr)
            if len(pts) < 4 or pts[0] != pts[-1]:
                continue
            g = Polygon(pts).buffer(0)
        elif el["type"] == "relation":
            outer = [_xy(m["geometry"], tr) for m in el.get("members", []) if m.get("role") == "outer" and "geometry" in m]
            inner = [_xy(m["geometry"], tr) for m in el.get("members", []) if m.get("role") == "inner" and "geometry" in m]
            g = unary_union(_rings(outer)) if outer else None
            if g is None or g.is_empty:
                continue
            if inner:
                g = g.difference(unary_union(_rings(inner)))
            g = g.buffer(0)
        else:
            continue
        if not g.is_empty:
            out.append((g, kind))
    print(f"  OSM-Wald/Gebüsch: {sum(k == 'wood' for _, k in out)} / {sum(k == 'scrub' for _, k in out)} Flächen",
          flush=True)
    return out


def _wood_canopy(wood, g: Grid, rng):
    """Synthetisches Kronendach in OSM-Waldflächen: Kronen aus geglättetem Rauschen (~85 % Deckung, Lücken
    dazwischen), Höhe aus dem Abstand zum Lückenrand (Wald 7–18 m, Gebüsch 2–4 m) plus Rauschen (± 1,5 m, ~4 m),
    damit trees.py einzelne Kronen findet. Am Waldrand 6 m nach innen gestaffelt."""
    from rasterio.features import rasterize
    from scipy import ndimage
    from shapely.geometry import box, mapping
    bb = box(*g.bounds).buffer(10)
    out = np.zeros(g.shape, np.float32)
    res = g.res
    for kind, (lo, hi) in (("wood", (7.0, 18.0)), ("scrub", (2.0, 4.0))):
        shapes = [(mapping(p.intersection(bb)), 1) for p, k in wood if k == kind and p.intersects(bb)]
        if not shapes:
            continue
        m = rasterize(shapes, out_shape=g.shape, transform=g.transform, fill=0, dtype="uint8") > 0
        if not m.any():
            continue
        n1 = ndimage.gaussian_filter(rng.standard_normal(g.shape).astype(np.float32), 2.5 / res)
        n1 /= max(float(n1.std()), 1e-6)
        crown = m & (n1 > -1.05)
        crown = ndimage.binary_opening(crown, iterations=2)
        dist = ndimage.distance_transform_edt(crown).astype(np.float32) * res
        edge = ndimage.distance_transform_edt(m).astype(np.float32) * res
        n2 = ndimage.gaussian_filter(rng.standard_normal(g.shape).astype(np.float32), 4.0 / res)
        n2 *= 1.5 / max(float(n2.std()), 1e-6)
        base = lo + (hi - lo) * np.clip(dist / 6.0, 0, 1) * np.clip(0.6 + edge / 15.0, 0, 1)
        out = np.maximum(out, np.where(crown, np.clip(base + (n2 if kind == "wood" else 0.3 * n2), lo * 0.8, hi + 2),
                                       0).astype(np.float32))
    return out


# ----------------------------------------------------------------------------- Vektorkacheln (Mapbox Vector Tile)

def _pb_fields(buf):
    """Protobuf-Felder einer Nachricht: (Nummer, Typ, Wert) – Wert int (varint) oder bytes (Länge)."""
    i, n = 0, len(buf)

    def varint():
        nonlocal i
        r = s = 0
        while True:
            b = buf[i]; i += 1
            r |= (b & 0x7F) << s
            if b < 0x80:
                return r
            s += 7
    while i < n:
        key = varint()
        f, t = key >> 3, key & 7
        if t == 0:
            yield f, t, varint()
        elif t == 2:
            ln = varint(); yield f, t, buf[i:i + ln]; i += ln
        elif t == 1:
            yield f, t, buf[i:i + 8]; i += 8
        elif t == 5:
            yield f, t, buf[i:i + 4]; i += 4
        else:
            raise ValueError(f"protobuf: Typ {t}")


def _varints(buf):
    i, n = 0, len(buf)
    while i < n:
        r = s = 0
        while True:
            b = buf[i]; i += 1
            r |= (b & 0x7F) << s
            if b < 0x80:
                break
            s += 7
        yield r


def mvt_decode(data, layers=None):
    """Mapbox-Vector-Tile (Protobuf) ohne Zusatzpaket lesen → {Layer: [(Typ, [Ringe/Linien in Kachelkoordinaten],
    Eigenschaften)]}, Typ 1 Punkt, 2 Linie, 3 Fläche; Kachelkoordinaten 0…extent (y nach unten)."""
    out = {}
    for f, _, lay in _pb_fields(data):
        if f != 3:
            continue
        name, feats, keys, vals, extent = None, [], [], [], 4096
        for g, t, v in _pb_fields(lay):
            if g == 1:
                name = v.decode()
            elif g == 2:
                feats.append(v)
            elif g == 3:
                keys.append(v.decode())
            elif g == 4:
                val = None
                for h, tt, vv in _pb_fields(v):
                    if h == 1:
                        val = vv.decode()
                    elif h in (4, 5):
                        val = vv
                    elif h == 6:
                        val = (vv >> 1) ^ -(vv & 1)
                    elif h == 7:
                        val = bool(vv)
                    elif h == 3:
                        val = float(np.frombuffer(vv, "<f8")[0])
                    elif h == 2:
                        val = float(np.frombuffer(vv, "<f4")[0])
                vals.append(val)
            elif g == 5:
                extent = v
        if layers and name not in layers:
            continue
        res = []
        for fb in feats:
            typ, tags, geom = 0, [], []
            for g, t, v in _pb_fields(fb):
                if g == 2:
                    tags = list(_varints(v))
                elif g == 3:
                    typ = v
                elif g == 4:
                    geom = list(_varints(v))
            props = {keys[tags[k]]: vals[tags[k + 1]] for k in range(0, len(tags) - 1, 2)}
            parts, cur, x, y, k = [], [], 0, 0, 0
            while k < len(geom):
                cmd, cnt = geom[k] & 7, geom[k] >> 3
                k += 1
                if cmd == 7:
                    if cur:
                        cur.append(cur[0])
                    continue
                for _ in range(cnt):
                    dx, dy = geom[k], geom[k + 1]
                    k += 2
                    x += (dx >> 1) ^ -(dx & 1)
                    y += (dy >> 1) ^ -(dy & 1)
                    if cmd == 1:
                        if cur:
                            parts.append(cur)
                        cur = [(x, y)]
                    else:
                        cur.append((x, y))
            if cur:
                parts.append(cur)
            res.append((typ, parts, props, extent))
        out[name] = res
    return out


def gsi_buildings(bounds, crs, cache_dir: Path, zoom=16,
                  url="https://cyberjapandata.gsi.go.jp/xyz/experimental_bvmap/{z}/{x}/{y}.pbf", pause=0.2):
    """Gebäudeumrisse aus den GSI-Vektorkacheln (地理院地図Vector, Layer "building", aus 基盤地図情報) im Ausschnitt
    → Liste (Polygon im Gebietssystem, Eigenschaften). Ringe: äussere im Uhrzeigersinn (Kachel-y nach unten),
    Löcher gegenläufig; Gebäude über Kachelgrenzen werden zusammengefügt. Art aus ftCode: 3101 普通建物 → gsi_normal,
    3102 堅ろう建物 → gsi_sturdy, 3103 高層建物 → gsi_highrise, 3111/3112 無壁舎 → shed (Höhen: footprint_defaults)."""
    from pyproj import Transformer
    from shapely.geometry import Polygon
    from shapely.ops import unary_union
    lon0, lat0, lon1, lat1 = bounds_in(bounds, crs, "EPSG:4326")
    x0, y0 = _lonlat_to_tile(lon0, lat1, zoom)
    x1, y1 = _lonlat_to_tile(lon1, lat0, zoom)
    tr = Transformer.from_crs("EPSG:3857", crs, always_xy=True)
    size = 2 * math.pi * _R / 2 ** zoom
    polys, n_new = [], 0
    for x in range(int(x0), int(x1) + 1):
        for y in range(int(y0), int(y1) + 1):
            f = Path(cache_dir) / str(zoom) / str(x) / f"{y}.pbf"
            if not f.exists() and not f.with_suffix(".none").exists():
                r = http(url.format(z=zoom, x=x, y=y), pause=pause, timeout=(20, 60))
                f.parent.mkdir(parents=True, exist_ok=True)
                if r is None or not r.content:
                    f.with_suffix(".none").write_text("")
                    continue
                f.write_bytes(r.content); n_new += 1
            if not f.exists():
                continue
            ox, oy = -math.pi * _R + x * size, math.pi * _R - y * size
            for typ, parts, props, ext in mvt_decode(f.read_bytes(), {"building"}).get("building", []):
                if typ != 3:
                    continue
                cur = None
                for ring in parts:
                    if len(ring) < 4:
                        continue
                    a = np.array(ring, float)
                    mx, my = ox + a[:, 0] / ext * size, oy - a[:, 1] / ext * size
                    e, n = tr.transform(mx, my)
                    pg = Polygon(np.column_stack([e, n])).buffer(0)
                    s = sum((a[k + 1, 0] - a[k, 0]) * (a[k + 1, 1] + a[k, 1]) for k in range(len(a) - 1))
                    if s < 0 or cur is None:  # äusserer Ring (Uhrzeigersinn in Bildkoordinaten)
                        if cur is not None:
                            polys.append((cur, props))
                        cur = pg
                    else:
                        cur = cur.difference(pg)
                if cur is not None:
                    polys.append((cur, props))
    print(f"  GSI-Gebäude z{zoom}: {len(polys)} Teile ({n_new} Kacheln neu)", flush=True)
    # an Kachelgrenzen zerschnittene Gebäude wieder zusammenfügen, je Gebäudeart (ftCode)
    kinds = {3101: "gsi_normal", 3102: "gsi_sturdy", 3103: "gsi_highrise", 3111: "shed", 3112: "shed"}
    out = []
    for code in sorted({p.get("ftCode") for _, p in polys}, key=str):
        geoms = [g for g, p in polys if p.get("ftCode") == code and not g.is_empty]
        merged = unary_union([g.buffer(0.05) for g in geoms]).buffer(-0.05)
        out += [(g, {"kind": kinds.get(code, "yes"), "ftCode": code, "source": "gsi"})
                for g in getattr(merged, "geoms", [merged]) if g.area > 4]
    return out
