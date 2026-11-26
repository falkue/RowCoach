"""Holt offene Geodaten für Gebiete ausserhalb CH/DE nach dem Feld "fetch_world" der Gebietsdatei (Helfer: geofetch.py).

Das Gebiet rechnet in einem UTM-System ("crs", Regel siehe geofetch.py und docs/WELTWEIT.md); alles, was der Server
in einem anderen System liefert, wird hier umgerechnet. Ergebnis in data_dir: das Rohdaten-Layout der Pipeline
(dgm/, dgm_far/, bdom/, image_core/, image_far/, osm/, footprints/, copernicus/, fetch-log.json).

Gebietsdatei, Beispiel (Oxford, Grossbritannien):
  "crs": "EPSG:25830",
  "raster_dirs": {"alti_core": "dgm", "alti_far": "dgm_far"},
  "copernicus_tiles": [...]            (fehlt es, nennt fetch_world.py die passenden Namen)
  "fetch_world": {
    "dtm":     {"type": "wcs", "url": "...", "coverage": "...", "crs": "EPSG:27700", "nodata_below": -1e30,
                "source": "...", "licence": "..."},                       → dgm/dtm_E-N.tif (1 m, Kerngebiet)
    "dtm_far": {"type": "wcs", ... gleiche Quelle, "res": 4}            → dgm_far/ (4 m; ohne: nur Copernicus)
    "dsm":     {"type": "wcs", ...}                                      → bdom/dsm_E-N.tif (1 m, Kerngebiet)
    "ortho":   {"type": "synthetic"}                                     → später synth_ortho.py
               | {"type": "xyz", "url": ".../{z}/{x}/{y}.jpg", "zoom": 18, "res": 0.25}
               | {"type": "cog", "urls": [...], "res": 0.2}             → image_core/dop_E-N.tif
    "ortho_far": {"type": "sentinel2", "months": [6, 7, 5, 8], "years": [2025, 2024]}
               | {"type": "xyz", ..., "zoom": 15}                        → image_far/ (10 m bzw. 2 m)
    "buildings": {"type": "osm"}                                          → footprints/footprints.geojson
               | {"type": "arcgis", "url": ".../FeatureServer/0", "height_field": "ALTURA", "base_field": "BASE"}
               | {"type": "file", "path": "...gpkg", "layer": "batiment", "height_field": "HAUTEUR"}
               | {"type": "wfs", "url": ".../wfs/ows", "typename": "BDTOPO_V3:batiment", "height_field": "hauteur",
                  "levels_field": "nombre_d_etages", "where": {"etat_de_l_objet": "En service"},
                  "top_field": "altitude_maximale_toit", "base_field": "altitude_minimale_sol", "prefer_top": true,
                  "height_add_m": 2.0}
                 (BD TOPO: hauteur liegt im Median 2,3 m unter dem LiDAR-HD-First, Dach-max − Sol-min nur 0,2 m darüber
                  → prefer_top; ohne Dachhöhe hauteur + height_add_m; geprüft an 1595 Gebäuden in Vaires-sur-Marne)
  }
Frankreich (IGN Géoplateforme, Lambert-93 EPSG:2154 → UTM 31N EPSG:25831), Vorlage areas/vaires-sur-marne.json:
  "dtm"/"dsm"/"dtm_far": {"type": "wms", "url": "https://data.geopf.fr/wms-r/wms", "crs": "EPSG:2154",
                          "layer": "IGNF_LIDAR-HD_MNT_ELEVATION.ELEVATIONGRIDCOVERAGE.LAMB93" (bzw. _MNS_),
                          "fallback_layers": ["ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES"]}   (RGE ALTI 1 m, wo LiDAR HD fehlt)
  "ortho": {"type": "wms", "layer": "HR.ORTHOIMAGERY.ORTHOPHOTOS", "res": 0.2, ...}       → image_core/dop_E-N.tif
  "ortho_far": {"type": "wms", ... "res": 2}                                                → image_far/wms_E-N.tif
Höhenquellen ("dtm", "dtm_far", "dsm") gibt es als
  "wms"  (WMS 1.3.0 GetMap mit FORMAT image/geotiff, siehe geofetch.wms_tiles: url, layer, crs, fallback_layers),
  "wcs"  (WCS 2.0.1, siehe geofetch.wcs_tiles: url, coverage, crs, native_res, axes, block_m),
  "cog"  ("urls": [...] oder "scheme": "kartverket" mit "product": "DTM1"/"DOM1"),
  "xyz"  ("url", "zoom", "decode": "gsi_dem_png" | "terrarium" | "mapbox").
Jede Quelle trägt "source" (Name), "licence" (Text für die Namensnennung) und optional "url_info"; sie landen in
fetch-log.json. OpenStreetMap kommt immer dazu: osm/overpass.json (Wasser, Brücken, Stege; fetch.py) und
osm/landcover.json (Flächennutzung, Wege, Gebäude im Kerngebiet; für synth_ortho.py und buildings_footprints.py).

Aufruf:  .venv/bin/python fetch_world.py areas/<gebiet>.json
         .venv/bin/python fetch_world.py areas/<gebiet>.json --skip-osm       # nur Höhen/Luftbild/Gebäude (Overpass gestört)
         .venv/bin/python fetch_world.py areas/<gebiet>.json --trees-inputs   # nach prepare.py: chm.tif, ortho_core.tif
"""
import json
import sys
from pathlib import Path

import numpy as np
from shapely.geometry import mapping

import geofetch as gf
from geofetch import Grid, log_source


def landcover_query(area):
    b = gf.bounds_in(area.get("buildings_lv95", area["core_lv95"]), area["crs"], "EPSG:4326")
    c = gf.bounds_in(area["core_lv95"], area["crs"], "EPSG:4326")
    bb = f"{b[1]:.5f},{b[0]:.5f},{b[3]:.5f},{b[2]:.5f}"
    cb = f"{c[1]:.5f},{c[0]:.5f},{c[3]:.5f},{c[2]:.5f}"
    return f"""[out:json][timeout:300];
(
  way["building"]({bb}); relation["building"]({bb});
  nwr["landuse"]({cb}); nwr["natural"]({cb}); nwr["leisure"]({cb});
  nwr["amenity"~"^(parking|school|university|college|grave_yard|marketplace|boat_rental)$"]({cb});
  way["highway"]({cb}); way["area:highway"]({cb}); way["railway"]({cb}); way["waterway"]({cb});
  nwr["man_made"~"^(pier|bridge|quay|breakwater|wastewater_plant|works)$"]({cb});
  way["barrier"~"^(wall|hedge|retaining_wall)$"]({cb});
  nwr["place"~"^(islet|island)$"]({cb});
);
out geom;"""


def osm_footprints(area, root):
    """Gebäudeumrisse aus osm/landcover.json → Liste (Polygon im Gebietssystem, Eigenschaften)."""
    from shapely.ops import unary_union
    from common import _rings, _xy, to_proj
    from shapely.geometry import Polygon
    tr = to_proj(area)
    els = json.loads((root / "osm" / "landcover.json").read_text())["elements"]
    out = []
    for el in els:
        t = el.get("tags", {})
        if "building" not in t or t.get("building") in ("no", "roof", "bridge", "construction") or \
                t.get("location") == "underground":
            continue
        if el["type"] == "way" and "geometry" in el:
            pts = _xy(el["geometry"], tr)
            if len(pts) < 4 or pts[0] != pts[-1]:
                continue
            g = Polygon(pts).buffer(0)
        elif el["type"] == "relation":
            outer = [_xy(m["geometry"], tr) for m in el.get("members", []) if m.get("role") == "outer" and
                     "geometry" in m]
            inner = [_xy(m["geometry"], tr) for m in el.get("members", []) if m.get("role") == "inner" and
                     "geometry" in m]
            g = unary_union(_rings(outer)) if outer else None
            if g is None or g.is_empty:
                continue
            if inner:
                g = g.difference(unary_union(_rings(inner)))
            g = g.buffer(0)
        else:
            continue
        out.append((g, {"osm": f"{el['type']}/{el['id']}", "kind": t.get("building"), "height": t.get("height"),
                        "levels": t.get("building:levels"), "min_height": t.get("min_height"),
                        "roof_shape": t.get("roof:shape"), "roof_levels": t.get("roof:levels"),
                        "roof_colour": t.get("roof:colour"), "source": "osm"}))
    return out


def save_footprints(root, items, crs, source):
    feats = []
    for g, p in items:
        for part in (g.geoms if g.geom_type == "MultiPolygon" else [g]):
            if part.is_empty or part.area < 4:
                continue
            feats.append({"type": "Feature", "properties": p, "geometry": mapping(part)})
    f = root / "footprints" / "footprints.geojson"
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(json.dumps({"type": "FeatureCollection", "crs_area": crs, "source": source, "features": feats}))
    print(f"footprints: {len(feats)} Umrisse ({source}) → {f}", flush=True)


def ext_footprints(area, cfg):
    """Umrisse aus ArcGIS oder Datei (GeoPackage/GML/GeoJSON) mit Höhenfeldern → Gebietssystem."""
    import shapely
    from pyproj import Transformer
    from shapely.ops import transform as stransform
    bounds = area.get("buildings_lv95", area["core_lv95"])
    crs = area["crs"]
    hf, bf, tf, lf = cfg.get("height_field"), cfg.get("base_field"), cfg.get("top_field"), cfg.get("levels_field")
    items = []
    if cfg["type"] in ("arcgis", "wfs"):
        if cfg["type"] == "arcgis":
            feats = gf.arcgis_features(cfg["url"], bounds, crs, where=cfg.get("where", "1=1"))
        else:
            feats = gf.wfs_features(cfg["url"], cfg["typename"], bounds, crs)
            for k, v in (cfg.get("where") or {}).items():
                feats = [f for f in feats if (f.get("properties") or {}).get(k) == v]
        tr = Transformer.from_crs(4326, crs, always_xy=True)
        for f in feats:
            if not f.get("geometry"):
                continue
            g = stransform(tr.transform, shapely.force_2d(shapely.geometry.shape(f["geometry"]))).buffer(0)
            items.append((g, f.get("properties") or {}))
    else:
        import pyogrio
        info = pyogrio.read_info(cfg["path"], layer=cfg.get("layer"))
        src_crs = cfg.get("crs") or info["crs"]
        b = gf.bounds_in(bounds, crs, src_crs)
        meta, _, geom, fields = pyogrio.raw.read(cfg["path"], layer=cfg.get("layer"), bbox=b)
        names = list(meta["fields"])
        tr = Transformer.from_crs(src_crs, crs, always_xy=True)
        for i, w in enumerate(geom):
            g = shapely.from_wkb(w)
            g = shapely.force_2d(g)
            g = stransform(tr.transform, g).buffer(0)
            items.append((g, {n: (fields[k][i].item() if hasattr(fields[k][i], "item") else fields[k][i])
                              for k, n in enumerate(names)}))
    out = []
    for g, p in items:
        def num(k):
            try:
                return float(p[k]) if k and p.get(k) not in (None, "") else None
            except (TypeError, ValueError):
                return None
        h = num(hf)
        top = num(tf) - num(bf) if tf and bf and num(tf) is not None and num(bf) is not None else None
        if cfg.get("prefer_top") and top is not None and top > 1.0:
            h = top  # z. B. BD TOPO: altitude_maximale_toit − altitude_minimale_sol = First (hauteur ≈ Traufe)
        elif h is not None:
            h += float(cfg.get("height_add_m", 0.0))
        elif top is not None:
            h = top
        out.append((g, {"height": h, "levels": num(lf), "kind": p.get(cfg.get("kind_field", "")) or "yes",
                        "source": cfg["type"], **{k: p.get(k) for k in cfg.get("keep_fields", [])}}))
    return out


def fetch_height(name, cfg, area, root, bounds, res, out_dir, prefix):
    crs = area["crs"]
    t = cfg["type"]
    if t == "wcs":
        files = gf.wcs_tiles(cfg, bounds, crs, root / out_dir, res, prefix)
    elif t == "wms":
        files = gf.wms_tiles(cfg, bounds, crs, root / out_dir, res, prefix)
    elif t == "cog":
        urls = cfg.get("urls") or gf.TILE_SCHEMES[cfg["scheme"]](bounds, crs, cfg.get("product", "DTM1"))
        files = gf.cog_tiles(urls, bounds, crs, root / out_dir, res, prefix, nodata=cfg.get("nodata"))
    elif t == "xyz":
        files = []
        tile = 1000 if res <= 1.0 else 4000
        for te, tn in gf.km_tiles(bounds, tile):
            dest = root / out_dir / f"{prefix}_{te}-{tn}.tif"
            if not dest.exists():
                g = gf.tile_grid(te, tn, res, crs, tile)
                z = gf.xyz_read(cfg["url"], cfg["zoom"], g, root / "xyz_cache" / name, decode=cfg["decode"])
                gf.write_tif(dest, np.where(np.isnan(z), gf.NODATA, z).astype(np.float32), g, nodata=gf.NODATA)
            files.append(dest)
    else:
        raise SystemExit(f"{name}: unbekannter Typ {t}")
    log_source(root, {"source": cfg.get("source", name), "role": name, "url": cfg.get("url_info", cfg.get("url")),
                      "licence": cfg.get("licence", "?"), "res_m": res, "tiles": len(files)})
    print(f"{name}: {len(files)} Kacheln → {root / out_dir}", flush=True)


def main(area_file, skip_osm=False):
    area = json.loads(Path(area_file).read_text())
    crs = area["crs"]
    root = (Path.cwd() / area["data_dir"]).resolve()
    root.mkdir(parents=True, exist_ok=True)
    cfg = area.get("fetch_world", {})
    core, far = tuple(area["core_lv95"]), tuple(area["far_lv95"])

    # Copernicus GLO-30 (Lücken im Höhenmodell, Umgebung)
    want = gf.copernicus_tiles(gf.bounds_in(far, crs, "EPSG:4326"))
    if sorted(area.get("copernicus_tiles", [])) != sorted(want):
        print(f"Hinweis: \"copernicus_tiles\": {json.dumps(want)} in die Gebietsdatei (prepare.py liest sie dort)")
    for t in want:
        new = gf.download(gf.COPERNICUS.format(t=t), root / "copernicus" / f"{t}.tif")
        print(f"copernicus {t}: {'neu' if new else ('fehlt (Meer)' if new is None else 'vorhanden')}", flush=True)
    log_source(root, {"source": "Copernicus DEM GLO-30 (AWS Open Data)", "tiles": want,
                      "url": "https://registry.opendata.aws/copernicus-dem/", "licence": gf.LIC_COPERNICUS_DEM})

    # OpenStreetMap: Wasser/Brücken/Stege wie fetch.py, dazu Flächennutzung und Gebäude
    import fetch as fetch_mod
    for k in range(0 if skip_osm else 6):
        fetch_mod.OVERPASS = gf.OVERPASS_MIRRORS[k % len(gf.OVERPASS_MIRRORS)]
        fetch_mod.UA = gf.UA
        try:
            fetch_mod.fetch_osm(area, root)
            break
        except Exception as ex:  # noqa: BLE001
            print(f"osm: {ex} – neuer Versuch", flush=True)
            import time
            time.sleep(30 * (k + 1))
    if not skip_osm:
        gf.overpass(landcover_query(area), root / "osm" / "landcover.json")
    log_source(root, {"source": "OpenStreetMap (Overpass API)", "url": "https://www.openstreetmap.org/copyright",
                      "licence": gf.LIC_OSM})

    if "dtm" in cfg:
        fetch_height("dtm", cfg["dtm"], area, root, core, 1.0, "dgm", "dtm")
    if "dsm" in cfg:
        fetch_height("dsm", cfg["dsm"], area, root, core, 1.0, "bdom", "dsm")

    of = cfg.get("ortho_far", {"type": "sentinel2"})
    dest = root / "image_far" / ("s2_far.tif" if of["type"] == "sentinel2" else "xyz_far.tif")
    if of["type"] == "wms":
        res = float(of.get("res", 2.0))
        files = gf.wms_tiles(of, far, crs, root / "image_far", res, "wms", rgb=True)
        log_source(root, {"source": of.get("source", "wms"), "role": "ortho_far", "url": of.get("url_info", of["url"]),
                          "licence": of.get("licence", "?"), "res_m": res, "tiles": len(files)})
        print(f"image_far: {len(files)} Blöcke", flush=True)
    elif not dest.exists():
        if of["type"] == "sentinel2":
            g = Grid(far, 10.0, crs)
            rgb, used = gf.s2_far(g, root / "s2_cache", months=tuple(of.get("months", (6, 7, 5, 8))),
                                  years=of.get("years"))
            gf.write_tif(dest, rgb, g)
            log_source(root, {"source": "Sentinel-2 L2A (Copernicus, Earth Search STAC sentinel-2-c1-l2a)",
                              "role": "ortho_far", "scenes": used, "url": gf.STAC_SEARCH,
                              "licence": f"Contains modified Copernicus Sentinel data {used[0]['datetime'][:4]}"})
        else:
            g = Grid(far, float(of.get("res", 2.0)), crs)
            gf.write_tif(dest, gf.xyz_read(of["url"], of["zoom"], g, root / "xyz_cache" / "ortho_far"), g)
            log_source(root, {"source": of.get("source", "xyz"), "role": "ortho_far", "url": of["url"],
                              "licence": of.get("licence", "?")})
        print(f"image_far: {dest}", flush=True)

    if "dtm_far" in cfg:
        c = {**cfg["dtm"], **cfg["dtm_far"]} if cfg["dtm_far"].get("same_as_dtm", True) and "dtm" in cfg \
            else cfg["dtm_far"]
        fetch_height("dtm_far", c, area, root, far, float(cfg["dtm_far"].get("res", 4.0)), "dgm_far", "dtm")

    oc = cfg.get("ortho", {"type": "synthetic"})
    if oc["type"] == "wms":
        res = float(oc.get("res", 0.2))
        files = gf.wms_tiles(oc, core, crs, root / "image_core", res, "dop", rgb=True, tile=1000)
        log_source(root, {"source": oc.get("source", "wms"), "role": "ortho", "url": oc.get("url_info", oc["url"]),
                          "licence": oc.get("licence", "?"), "res_m": res, "tiles": len(files)})
        print(f"image_core: {len(files)} km-Kacheln", flush=True)
    elif oc["type"] in ("xyz", "cog"):
        res = float(oc.get("res", 0.25))
        n = 0
        for te, tn in gf.km_tiles(core):
            d = root / "image_core" / f"dop_{te}-{tn}.tif"
            if d.exists():
                continue
            g = gf.tile_grid(te, tn, res, crs)
            if oc["type"] == "xyz":
                img = gf.xyz_read(oc["url"], oc["zoom"], g, root / "xyz_cache" / "ortho")
            else:
                img = np.zeros((3, *g.shape), np.uint8)
                for u in oc["urls"]:
                    part = gf.cog_read(u, g, bands=[1, 2, 3], dtype=np.uint8)
                    m = (img.max(axis=0) == 0) & (part.max(axis=0) > 0)
                    img[:, m] = part[:, m]
            gf.write_tif(d, img, g, rgb_jpeg=True)
            n += 1
        log_source(root, {"source": oc.get("source", oc["type"]), "role": "ortho", "url": oc.get("url_info"),
                          "licence": oc.get("licence", "?"), "res_m": res})
        print(f"image_core: {n} neue km-Kacheln", flush=True)
    else:
        print("image_core: synthetisch – nach buildings_footprints.py: synth_ortho.py", flush=True)

    bc = cfg.get("buildings", {"type": "osm"})
    if not (root / "footprints" / "footprints.geojson").exists():
        if bc["type"] == "osm":
            save_footprints(root, osm_footprints(area, root), crs, "OpenStreetMap")
        else:
            save_footprints(root, ext_footprints(area, bc), crs, bc.get("source", bc["type"]))
            log_source(root, {"source": bc.get("source", bc["type"]), "role": "buildings",
                              "url": bc.get("url_info", bc.get("url")), "licence": bc.get("licence", "?")})


if __name__ == "__main__":
    a = sys.argv[1]
    if "--trees-inputs" in sys.argv:
        gf.trees_inputs(json.loads(Path(a).read_text()))
    else:
        main(a, skip_osm="--skip-osm" in sys.argv)
