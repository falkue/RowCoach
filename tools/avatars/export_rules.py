"""Schreibt die Sichtbarkeitsregel der Figurteile (rig.figure_prims) für alle Vorlagen und Varianten als Fixture für
den Kit-Test (AvatarPartRules muss genau dieselben Teile liefern).

Aufruf: ../coursebuilder/.venv/bin/python export_rules.py
Ergebnis: tools/avatars/figure_parts_expected.json (liest AvatarTests im Kit)
"""
from __future__ import annotations

import json
from pathlib import Path

import rig

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "App/RowCoach/Resources/appearance.json"
OUT = ROOT / "tools/avatars/figure_parts_expected.json"


def shape(ch):
    return {"hairStyle": ch.get("hairStyle", "short"), "shirtStyle": ch.get("shirtStyle", "tank"),
            "legStyle": ch.get("legStyle", "short"), "beard": ch.get("beard", "none"),
            "accessories": list(ch.get("accessories", []))}


def main():
    cat = json.loads(CATALOG.read_text())
    cases = []
    for ch in cat["characters"]:
        cases.append({"name": ch["id"], "shape": shape(ch)})
    base = shape(cat["characters"][0])
    variants = {
        "hijab-long-hair": dict(hairStyle="long", accessories=["hijab"]),
        "patka-bun-beard": dict(hairStyle="bun", beard="full", accessories=["patka", "watch"]),
        "cap-afro": dict(hairStyle="afro", accessories=["cap", "sunglasses"]),
        "cap-ponytail": dict(hairStyle="ponytail", accessories=["cap"]),
        "headband-curly": dict(hairStyle="curly", accessories=["headband"]),
        "legacy-cap-style": dict(hairStyle="cap", accessories=[]),
        "legacy-headband-style": dict(hairStyle="headband", accessories=[]),
        "bald-short-beard": dict(hairStyle="bald", beard="short"),
        "longsleeve-long-legs": dict(shirtStyle="longsleeve", legStyle="long"),
        "tee-sunglasses-watch": dict(shirtStyle="tee", accessories=["sunglasses", "watch"]),
        "unknown-values": dict(hairStyle="mohawk", shirtStyle="poncho", beard="goatee", accessories=["scarf"]),
    }
    for name, v in variants.items():
        s = dict(base)
        s.update(v)
        cases.append({"name": name, "shape": s})
    for c in cases:
        c["parts"] = [{"prim": p, "segment": seg, "color": col} for p, seg, col in rig.figure_prims(c["shape"])]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"generator": "tools/avatars/export_rules.py", "cases": cases}, indent=1) + "\n")
    print(OUT, len(cases))


if __name__ == "__main__":
    main()
