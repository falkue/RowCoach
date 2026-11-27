"""Erzeugt die 3D-Teile für Figur und Boot und schreibt sie als USDZ in die App (und als GLB für Android).

Aufruf (venv der coursebuilder, keine GPU):
    cd tools/avatars && ../coursebuilder/.venv/bin/python build.py [--glb]

Ergebnis:
    App/RowCoach/Resources/Avatars/rower_parts.usdz   Figur: alle Segmente, Frisuren, Accessoires, Trikotformen
    App/RowCoach/Resources/Avatars/boat_parts.usdz    Boot: Rumpf, Deck, Streifen, Ausleger-Arten, Skulls, Blätter
    App/RowCoach/Resources/Avatars/lite_parts.usdz    Detailstufe lite (ein Material, Palettentextur)
    App/RowCoach/Resources/Avatars/*.rcmesh           dieselben Teile im eigenen Binärformat – die App lädt diese
                                                      (USDZ bleibt für Werkzeuge und als Rückfall)
    App/RowCoach/Resources/Avatars/avatar_parts.json  Übersicht: Prim → Rahmen/Segment, Materialgruppe, Dreiecke
    dist/avatars/*.glb                                (mit --glb) dieselben Teile als glTF-Binärdatei

Aufbau jeder USDZ: /Parts (Xform) mit je einem Mesh-Prim pro Teil; Prim-Name `<teil>__<gruppe>` (z. B.
`forearm__skin`, `blade_macon_R__blade`). Punkte liegen im lokalen Rahmen des Segments (Ursprung = Gelenk, siehe
figure.py/boat.py), Normalen glatt (vertex), Flaggen und lite-Teile mit Texturkoordinaten `st`. Jedes Mesh ist an ein
Material seiner Gruppe gebunden (/Parts/Materials/<gruppe>, UsdPreviewSurface mit Vorschaufarbe); die App ersetzt
die Materialien zur Laufzeit je Erscheinung und nutzt nur die Meshes.
"""
from __future__ import annotations

import argparse
import json
import shutil
import tempfile
from pathlib import Path

import numpy as np
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdUtils, Vt

import boat as B
import figure as F
import lite as L
from geom import normals

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "App/RowCoach/Resources/Avatars"
GLB_OUT = ROOT / "dist/avatars"

PREVIEW_COLOR = {"skin": "#D7BD96", "hair": "#3B2A20", "shirt": "#1A2F66", "shorts": "#2B2C30", "socks": "#F2F2EE",
                 "shoes": "#3A3C40", "eyes": "#1C1A1A", "accessory": "#1E1F22", "flag": "#FFFFFF",
                 "hull": "#F4F4F1", "deck": "#F4F4F1", "stripe": "#1F4E9C", "fin": "#26272B", "bowball": "#F4F4F1",
                 "fittings": "#2B2C30", "rigger": "#26272B", "shaft": "#1E1E1E", "blade": "#F0E442",
                 "sleeve": "#E8E8E4", "palette": "#BBBBBB"}


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def write_usdz(parts, path: Path, root_name="Parts"):
    tmp = Path(tempfile.mkdtemp(prefix="avatars-"))
    try:
        usdc = tmp / f"{path.stem}.usdc"
        stage = Usd.Stage.CreateNew(str(usdc))
        UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
        UsdGeom.SetStageMetersPerUnit(stage, 1.0)
        root = UsdGeom.Xform.Define(stage, f"/{root_name}")
        stage.SetDefaultPrim(root.GetPrim())
        UsdGeom.Scope.Define(stage, f"/{root_name}/Materials")
        mats = {}
        for name, (frame, group, part) in parts.items():
            if group not in mats:
                m = UsdShade.Material.Define(stage, f"/{root_name}/Materials/{group}")
                sh = UsdShade.Shader.Define(stage, f"/{root_name}/Materials/{group}/PBR")
                sh.CreateIdAttr("UsdPreviewSurface")
                sh.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(
                    Gf.Vec3f(*hex_rgb(PREVIEW_COLOR.get(group, "#888888"))))
                sh.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.6)
                sh.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0.0)
                m.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(), "surface")
                mats[group] = m
            mesh = UsdGeom.Mesh.Define(stage, f"/{root_name}/{name}")
            v = part.v.astype(np.float32)
            mesh.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(v))
            mesh.CreateFaceVertexCountsAttr(Vt.IntArray([3] * len(part.f)))
            mesh.CreateFaceVertexIndicesAttr(Vt.IntArray(part.f.reshape(-1).astype(int).tolist()))
            mesh.CreateNormalsAttr(Vt.Vec3fArray.FromNumpy(normals(part).astype(np.float32)))
            mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
            mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
            mesh.CreateDoubleSidedAttr(False)
            lo, hi = v.min(axis=0), v.max(axis=0)
            mesh.CreateExtentAttr(Vt.Vec3fArray([Gf.Vec3f(*lo.tolist()), Gf.Vec3f(*hi.tolist())]))
            if part.uv is not None:
                pv = UsdGeom.PrimvarsAPI(mesh).CreatePrimvar("st", Sdf.ValueTypeNames.TexCoord2fArray,
                                                             UsdGeom.Tokens.vertex)
                pv.Set(Vt.Vec2fArray.FromNumpy(part.uv.astype(np.float32)))
            prim = mesh.GetPrim()
            prim.SetCustomDataByKey("rowcoach:frame", frame)
            prim.SetCustomDataByKey("rowcoach:group", group)
            UsdShade.MaterialBindingAPI.Apply(prim).Bind(mats[group])
        stage.GetRootLayer().Save()
        if path.exists():
            path.unlink()
        ok = UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(usdc)), str(path))
        if not ok:
            raise RuntimeError(f"USDZ fehlgeschlagen: {path}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


RCMESH_MAGIC = b"RCMESH01"


def write_rcmesh(parts, path: Path):
    """Eigenes, einfaches Binärformat für die App (`AvatarMeshFile` im Kit liest es): die App baut die Meshes daraus
    selbst (MeshDescriptor) – unabhängig davon, wie RealityKit USD-Prims benennt oder zusammenfasst.
    Aufbau: 8 Byte Magie, UInt32 LE Länge des JSON-Kopfs, JSON-Kopf (Teile mit Name, Rahmen, Gruppe, Anzahlen und
    Byte-Versätzen im Datenblock), Datenblock (Float32 LE Punkte, Normalen, optional UV; UInt32 LE Indizes)."""
    blob = bytearray()
    header = {"version": 1, "parts": []}
    for name, (frame, group, part) in parts.items():
        v = part.v.astype("<f4")
        n = normals(part).astype("<f4")
        idx = part.f.reshape(-1).astype("<u4")
        entry = {"name": name, "frame": frame, "group": group, "vertices": int(len(v)), "indices": int(len(idx))}
        entry["positions"] = len(blob)
        blob += v.tobytes()
        entry["normals"] = len(blob)
        blob += n.tobytes()
        if part.uv is not None:
            entry["uv"] = len(blob)
            blob += part.uv.astype("<f4").tobytes()
        entry["indexOffset"] = len(blob)
        blob += idx.tobytes()
        header["parts"].append(entry)
    head = json.dumps(header, separators=(",", ":")).encode()
    path.write_bytes(RCMESH_MAGIC + len(head).to_bytes(4, "little") + head + bytes(blob))


def write_glb(parts, path: Path):
    import trimesh
    scene = trimesh.Scene()
    for name, (frame, group, part) in parts.items():
        tm = trimesh.Trimesh(vertices=part.v, faces=part.f, vertex_normals=normals(part), process=False)
        if part.uv is not None:
            tm.visual = trimesh.visual.TextureVisuals(uv=part.uv)
        tm.metadata["name"] = name
        scene.add_geometry(tm, node_name=name, geom_name=name)
    path.parent.mkdir(parents=True, exist_ok=True)
    scene.export(str(path), file_type="glb")


def check(parts, label):
    """Plausibilität: geschlossene Körper mit positivem Volumen, keine entarteten Punkte."""
    problems = []
    for name, (frame, group, part) in parts.items():
        if not np.isfinite(part.v).all():
            problems.append(f"{name}: ungültige Punkte")
        if part.f.max() >= len(part.v):
            problems.append(f"{name}: Index ausserhalb")
    if problems:
        raise SystemExit(f"{label}: " + "; ".join(problems))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", action="store_true", help="zusätzlich GLB nach dist/avatars/ (Android)")
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    sets = {"rower_parts": F.build_parts(), "boat_parts": B.build_parts(), "lite_parts": L.build_parts()}
    manifest = {"version": 1, "generator": "tools/avatars/build.py", "files": {}}
    for stem, parts in sets.items():
        check(parts, stem)
        path = OUT / f"{stem}.usdz"
        write_usdz(parts, path)
        write_rcmesh(parts, OUT / f"{stem}.rcmesh")
        manifest["files"][f"{stem}.usdz"] = {
            "bytes": path.stat().st_size,
            "parts": {n: {"frame": fr, "group": g, "triangles": int(p.tris)} for n, (fr, g, p) in parts.items()}}
        print(f"{path.relative_to(ROOT)}: {len(parts)} Teile, {sum(p.tris for _, _, p in parts.values())} Dreiecke, "
              f"{path.stat().st_size / 1024:.0f} KB")
        if args.glb:
            g = GLB_OUT / f"{stem}.glb"
            write_glb(parts, g)
            print(f"  {g.relative_to(ROOT)}: {g.stat().st_size / 1024:.0f} KB")
    manifest["palette"] = L.PALETTE
    (OUT / "avatar_parts.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
