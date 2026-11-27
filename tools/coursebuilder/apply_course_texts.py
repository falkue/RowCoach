#!/usr/bin/env python3
"""Übernimmt die Streckentexte ("course_texts": description, highlights, bridges) aus den Gebietsdateien
(tools/coursebuilder/areas/*.json, je Route) in courses/<route>/course.json und App/Courses/<route>/course.json,
ohne die Szene neu zu exportieren. export.py macht das seit 27.11.2026 selbst.

Aufruf (Repo-Wurzel): python3 tools/coursebuilder/apply_course_texts.py
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
n = 0
for area_file in sorted((ROOT / "tools/coursebuilder/areas").glob("*.json")):
    area = json.loads(area_file.read_text())
    for r in area.get("routes", []):
        texts = r.get("course_texts") or {}
        if not texts:
            continue
        for base in (ROOT / "courses", ROOT / "App/Courses"):
            cj = base / r["id"] / "course.json"
            if not cj.exists():
                continue
            raw = cj.read_text()
            d = json.loads(raw)
            changed = False
            for key in ("description", "highlights", "bridges"):
                if texts.get(key) and d.get(key) != texts[key]:
                    d[key] = texts[key]
                    changed = True
            if changed:
                cj.write_text(json.dumps(d, ensure_ascii=False) + ("\n" if raw.endswith("\n") else ""))
                print("Texte übernommen:", cj.relative_to(ROOT))
                n += 1
print(n, "Dateien")
