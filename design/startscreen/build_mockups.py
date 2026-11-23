#!/usr/bin/env python3
"""Entwurf Startbildschirm RowCoach: zeichnet Varianten A und B (iPad quer, iPhone hoch) als SVG
und rendert sie mit cairosvg in doppelter Aufloesung.

Aufruf: tools/coursebuilder/.venv/bin/python design/startscreen/build_mockups.py
"""
import base64
import io
import json
from pathlib import Path

import cairosvg
from PIL import Image, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
FONT = "/home/falkue/.local/share/fonts/firn/Inter.ttf"

# ---------------------------------------------------------------- Farben
BG = "#07111C"          # Nachtblau, tief
NAVY = "#0B1F3A"        # Nachtblau Logo
PANEL = "#0E1B2C"
TXT = "#F2F5F8"
SEC = "#9AA6B4"         # Sekundaertext (ca. 62 % Weiss auf Nachtblau)
DIM = "#5E6B7A"
ORANGE = "#F29A4A"      # Abendorange
SEE = "#5BB8EC"         # Seeblau
GELB = "#F5C518"        # Ruderblatt
LEICHT = "#4DA6F2"      # Zone 2
MITTEL = "#4DCC73"      # Zone 3
HART = "#FAA633"        # Zone 4
GRUEN = "#4CD97B"

# ---------------------------------------------------------------- Text messen
_fonts = {}


def font(size, bold=False):
    key = (size, bold)
    if key not in _fonts:
        f = ImageFont.truetype(FONT, size * 4)
        f.set_variation_by_name("Bold" if bold else "Regular")
        _fonts[key] = f
    return _fonts[key]


def tw(s, size, bold=False, ls=0):
    return font(size, bold).getlength(s) / 4 + ls * len(s)


WARN = []


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def text(x, y, s, size, color=TXT, bold=False, anchor="start", maxw=None, ls=0, opacity=1, tag=""):
    w = tw(s, size, bold, ls)
    if maxw is not None and w > maxw:
        WARN.append(f"{tag} Text zu breit ({w:.0f} > {maxw}): {s}")
    weight = 700 if bold else 400
    extra = f' letter-spacing="{ls}"' if ls else ""
    op = f' fill-opacity="{opacity}"' if opacity != 1 else ""
    return (f'<text x="{x:.1f}" y="{y:.1f}" font-family="Inter" font-size="{size}" font-weight="{weight}" '
            f'fill="{color}"{op} text-anchor="{anchor}"{extra}>{esc(s)}</text>')


def rect(x, y, w, h, r=0, fill="none", stroke=None, sw=1, opacity=1, extra=""):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
    op = f' fill-opacity="{opacity}"' if opacity != 1 else ""
    return f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{r}" fill="{fill}"{op}{s} {extra}/>'


# ---------------------------------------------------------------- Bilder
_imgcache = {}


def b64_jpeg(path, size=None, quality=82, bright=1.0):
    key = (str(path), size, bright)
    if key not in _imgcache:
        im = Image.open(path).convert("RGB")
        if bright != 1.0:
            from PIL import ImageEnhance
            im = ImageEnhance.Brightness(im).enhance(bright)
            im = ImageEnhance.Color(im).enhance(1.15)
        if size:
            im = im.resize((size, size), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=quality)
        _imgcache[key] = "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
    return _imgcache[key]


def b64_png(path, size):
    im = Image.open(path).convert("RGBA").resize((size, size), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


COURSES = {}
for cid in ["zuerichsee-utoquai", "zuerichsee-mythenquai", "rhein-basel", "rhein-stein", "luzern-nationalquai"]:
    d = json.loads((ROOT / "courses" / cid / "course.json").read_text())
    b = d["overview"]["bounds_xz"]
    pts = [((x - b[0]) / (b[2] - b[0]), (z - b[1]) / (b[3] - b[1])) for x, z in d["path_xz"]]
    pts = pts[::4]
    one = int(len(pts) * d["one_way_m"] / d["total_m"]) if d["turns"] else len(pts) - 1
    COURSES[cid] = {"img": ROOT / "courses" / cid / "overview.jpg", "pts": pts, "turn": pts[-1]}

_clip = [0]


def aerial(cid, x, y, w, h, r, focus=(0.5, 0.5), scale=None, at=(0.5, 0.5), route=True, rw=3.5,
           imgsize=900, dots=True, image=True, bright=1.0):
    """Luftbild in einem abgerundeten Rahmen. focus = Bildpunkt (0..1), der bei at (Anteil des Rahmens) liegt.
    scale = gezeigte Bildbreite in pt (Standard: Rahmen voll gedeckt)."""
    _clip[0] += 1
    cidn = f"clip{_clip[0]}"
    c = COURSES[cid]
    S = scale or max(w, h)
    S = max(S, w, h)
    ox = x + at[0] * w - focus[0] * S
    oy = y + at[1] * h - focus[1] * S
    ox = min(x, max(x + w - S, ox))
    oy = min(y, max(y + h - S, oy))
    out = [f'<clipPath id="{cidn}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}"/></clipPath>',
           f'<g clip-path="url(#{cidn})">',
           (f'<image x="{ox:.1f}" y="{oy:.1f}" width="{S:.1f}" height="{S:.1f}" preserveAspectRatio="none" '
            f'href="{b64_jpeg(c["img"], imgsize, bright=bright)}"/>') if image else ""]
    if route:
        P = " ".join(f"{ox + u * S:.1f},{oy + v * S:.1f}" for u, v in c["pts"])
        out.append(f'<polyline points="{P}" fill="none" stroke="#000" stroke-opacity="0.35" stroke-width="{rw + 3}" '
                   f'stroke-linecap="round" stroke-linejoin="round"/>')
        out.append(f'<polyline points="{P}" fill="none" stroke="#fff" stroke-width="{rw}" stroke-linecap="round" '
                   f'stroke-linejoin="round"/>')
        if dots:
            su, sv = c["pts"][0]
            tu, tv = c["turn"]
            dr = max(3.5, rw * 1.6)
            out.append(f'<circle cx="{ox + tu * S:.1f}" cy="{oy + tv * S:.1f}" r="{dr:.1f}" fill="{ORANGE}" stroke="#fff" stroke-width="1.5"/>')
            out.append(f'<circle cx="{ox + su * S:.1f}" cy="{oy + sv * S:.1f}" r="{dr:.1f}" fill="{GRUEN}" stroke="#fff" stroke-width="1.5"/>')
    out.append("</g>")
    return "\n".join(out)


def route_center(cid):
    p = COURSES[cid]["pts"]
    us = [a for a, _ in p]
    vs = [b for _, b in p]
    return ((min(us) + max(us)) / 2, (min(vs) + max(vs)) / 2), (max(us) - min(us), max(vs) - min(vs))


LOGO = b64_png(ROOT / "design/logo/rowcoach-logo-1024.png", 160)

DEFS = f"""
<defs>
  <linearGradient id="heroL" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="{BG}" stop-opacity="0.94"/>
    <stop offset="0.48" stop-color="{BG}" stop-opacity="0.78"/>
    <stop offset="0.80" stop-color="{BG}" stop-opacity="0.15"/>
    <stop offset="1" stop-color="{BG}" stop-opacity="0.05"/>
  </linearGradient>
  <linearGradient id="heroB" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="{BG}" stop-opacity="0"/>
    <stop offset="0.55" stop-color="{BG}" stop-opacity="0.0"/>
    <stop offset="1" stop-color="{BG}" stop-opacity="0.85"/>
  </linearGradient>
  <linearGradient id="phoneHero" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="{BG}" stop-opacity="0.15"/>
    <stop offset="0.35" stop-color="{BG}" stop-opacity="0.55"/>
    <stop offset="1" stop-color="{BG}" stop-opacity="0.94"/>
  </linearGradient>
  <linearGradient id="fullTop" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="{BG}" stop-opacity="0.80"/>
    <stop offset="0.16" stop-color="{BG}" stop-opacity="0.30"/>
    <stop offset="0.50" stop-color="{BG}" stop-opacity="0.12"/>
    <stop offset="0.66" stop-color="{BG}" stop-opacity="0.75"/>
    <stop offset="1" stop-color="{BG}" stop-opacity="0.96"/>
  </linearGradient>
  <linearGradient id="fullLeft" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="{BG}" stop-opacity="0.85"/>
    <stop offset="0.45" stop-color="{BG}" stop-opacity="0.45"/>
    <stop offset="0.62" stop-color="{BG}" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="phoneFull" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="{BG}" stop-opacity="0.75"/>
    <stop offset="0.18" stop-color="{BG}" stop-opacity="0.2"/>
    <stop offset="0.45" stop-color="{BG}" stop-opacity="0.35"/>
    <stop offset="0.80" stop-color="{BG}" stop-opacity="0.92"/>
    <stop offset="1" stop-color="{BG}" stop-opacity="1"/>
  </linearGradient>
  <filter id="shadow" x="-10%" y="-10%" width="120%" height="130%">
    <feDropShadow dx="0" dy="8" stdDeviation="14" flood-color="#000" flood-opacity="0.45"/>
  </filter>
</defs>
"""

# ---------------------------------------------------------------- Beispieldaten
# Heute = Di 24.11.2026. Letzte Fahrt = Falks echte Fahrt vom Mo 23.11.2026.
TODAY = "Dienstag, 24. November"
SUG = {
    "eyebrow": "VORSCHLAG FÜR HEUTE",
    "title1": "Zeit-Pyramide",
    "title2": "1-2-3-4-3-2-1",
    "course": "rhein-basel",
    "sub": "Rhein Basel – Rheinweg  ·  32 min  ·  Intervalle",
    "targets": [("TEMPO", "1:51–1:57", "/500 m"), ("SCHLAGZAHL", "22–28", "/min"), ("PULS", "Zone 4", "")],
    "why1": "Letzte harte Einheit vor 7 Tagen – Zeit für einen Reiz.",
    "why2": "Zuletzt Schwelle 4 × 6, heute die Pyramide.",
}
# Phasen der Pyramide (Minuten, Art)
PHASES = [(5, "warm"), (1, "work"), (1, "rest"), (2, "work"), (1, "rest"), (3, "work"), (1, "rest"), (4, "work"),
          (1, "rest"), (3, "work"), (1, "rest"), (2, "work"), (1, "rest"), (1, "work"), (5, "cool")]
PH_COL = {"work": "#FA7330", "rest": "#4DB8FF", "warm": "#CCE05A", "cool": "#8C8CFA"}
PH_H = {"work": 1.0, "rest": 0.3, "warm": 0.55, "cool": 0.55}

WEEK = [("Mo", "leicht"), ("Di", "heute"), ("Mi", None), ("Do", None), ("Fr", None), ("Sa", None), ("So", None)]
DIST28 = [(79, LEICHT, "leicht"), (6, MITTEL, "mittel"), (15, HART, "hart")]

PASS = [  # Seen-Pass: Strecke, Kurzname, Gewaesser, Zeile 1, Zeile 2, Abzeichen
    ("zuerichsee-utoquai", "Utoquai – Seefeld", "Zürichsee", "6 Fahrten · 24 km", "Bestzeit 18:51", "Gestern"),
    ("zuerichsee-mythenquai", "Mythenquai – Enge", "Zürichsee", "3 Fahrten · 12 km", "Bestzeit 19:10", None),
    ("rhein-basel", "Rhein Basel", "Rheinknie", "2 Fahrten · 6,2 km", "Bestzeit 15:02", "Heute"),
    ("luzern-nationalquai", "Luzern Nationalquai", "Vierwaldstättersee", "1 Fahrt · 3,8 km", "Bestzeit 17:58", None),
    ("rhein-stein", "Stein am Rhein", "Rhein", "noch offen", "3,8 km Strecke", None),
]


# ---------------------------------------------------------------- Bausteine
def heart(x, y, s, color):
    # Herz, Mittelpunkt x,y, Breite ~ 2s
    return (f'<path d="M{x},{y + s * 0.85} C{x - s * 1.4},{y - s * 0.1} {x - s * 0.9},{y - s * 1.2} {x},{y - s * 0.45} '
            f'C{x + s * 0.9},{y - s * 1.2} {x + s * 1.4},{y - s * 0.1} {x},{y + s * 0.85} Z" fill="{color}"/>')


def statusbar_ipad(label):
    o = [text(24, 18, "18:05   Di 24. Nov.", 14, TXT, bold=True)]
    o.append(text(1194 / 2, 18, label, 12, ORANGE, bold=True, anchor="middle", ls=1.2))
    o.append(text(1128, 18, "100 %", 14, TXT, bold=True, anchor="end"))
    o.append(rect(1136, 7, 26, 13, 4, "none", TXT, 1.3, extra='stroke-opacity="0.6"'))
    o.append(rect(1138.5, 9.5, 21, 8, 2, TXT))
    o.append(rect(1163, 11, 2, 5, 1, TXT, opacity=0.6))
    return "\n".join(o)


def header_ipad(glass=False):
    o = []
    o.append(f'<clipPath id="logoclip"><rect x="32" y="38" width="38" height="38" rx="10"/></clipPath>')
    o.append(f'<image x="32" y="38" width="38" height="38" href="{LOGO}" clip-path="url(#logoclip)"/>')
    o.append(text(80, 63, "RowCoach", 19, TXT, bold=True))
    # Tabs
    tabs = ["Rudern", "Verlauf", "Geräte", "Einstellungen"]
    pad = 20
    widths = [tw(t, 16, i == 0) + 2 * pad for i, t in enumerate(tabs)]
    total = sum(widths) + 8
    x0 = (1194 - total) / 2
    o.append(rect(x0, 36, total, 44, 22, "#FFFFFF", opacity=0.10 if not glass else 0.14,
                  extra='stroke="#FFFFFF" stroke-opacity="0.10"'))
    x = x0 + 4
    for i, (t, w) in enumerate(zip(tabs, widths)):
        if i == 0:
            o.append(rect(x, 40, w, 36, 18, "#FFFFFF", opacity=0.16))
        o.append(text(x + w / 2, 63.5, t, 16, TXT if i == 0 else SEC if not glass else "#C9D2DC", bold=(i == 0), anchor="middle"))
        x += w
    # Geraete
    chips = [("PM5 bereit", "dot"), ("64", "heart")]
    xr = 1162
    for label, kind in reversed(chips):
        w = tw(label, 15, True) + 44
        xr -= w
        o.append(rect(xr, 40, w, 36, 18, "#FFFFFF", opacity=0.10 if not glass else 0.14))
        if kind == "dot":
            o.append(f'<circle cx="{xr + 20}" cy="58" r="5" fill="{GRUEN}"/>')
        else:
            o.append(heart(xr + 20, 58, 6, "#FF5A6A"))
        o.append(text(xr + 34, 63.5, label, 15, TXT, bold=True))
        xr -= 10
    return "\n".join(o)


def phase_bar(x, y, w, h):
    total = sum(m for m, _ in PHASES)
    o = []
    cx = x
    gap = 2
    for m, k in PHASES:
        bw = w * m / total - gap
        bh = h * PH_H[k]
        o.append(rect(cx, y + h - bh, max(bw, 1.5), bh, 2, PH_COL[k]))
        cx += w * m / total
    return "\n".join(o)


def pill_button(x, y, w, h, label, primary=True, size=24):
    o = []
    if primary:
        o.append(rect(x, y, w, h, h / 2, ORANGE))
        # Play-Dreieck
        tx = x + w / 2 - tw(label, size, True) / 2 - 14
        cy = y + h / 2
        s = size * 0.42
        o.append(f'<path d="M{tx - s * 0.6},{cy - s} L{tx + s * 0.9},{cy} L{tx - s * 0.6},{cy + s} Z" fill="{NAVY}"/>')
        o.append(text(x + w / 2 + 10, y + h / 2 + size * 0.36, label, size, NAVY, bold=True, anchor="middle"))
    else:
        o.append(rect(x, y, w, h, h / 2, "#FFFFFF", opacity=0.14, extra='stroke="#FFFFFF" stroke-opacity="0.22"'))
        o.append(text(x + w / 2, y + h / 2 + size * 0.36, label, size, TXT, bold=True, anchor="middle"))
    return "\n".join(o)


def chip(x, y, label, size=15, h=34, fill_op=0.10, color=TXT, bold=False):
    w = tw(label, size, bold) + 28
    return rect(x, y, w, h, h / 2, "#FFFFFF", opacity=fill_op, extra='stroke="#FFFFFF" stroke-opacity="0.16"') + \
        text(x + 14, y + h / 2 + size * 0.36, label, size, color, bold=bold), w


def week_dots(x, y, w, r=14, labsize=14):
    o = []
    step = w / 7
    for i, (d, s) in enumerate(WEEK):
        cx = x + step * i + step / 2
        if s == "leicht":
            o.append(f'<circle cx="{cx:.1f}" cy="{y}" r="{r}" fill="{LEICHT}"/>')
        elif s == "heute":
            o.append(f'<circle cx="{cx:.1f}" cy="{y}" r="{r - 1}" fill="none" stroke="{TXT}" stroke-width="2" stroke-dasharray="4 3.2"/>')
        else:
            o.append(f'<circle cx="{cx:.1f}" cy="{y}" r="{r - 1}" fill="none" stroke="#FFFFFF" stroke-opacity="0.16" stroke-width="2"/>')
        o.append(text(cx, y + r + labsize + 6, d, labsize, TXT if s == "heute" else SEC, bold=(s == "heute"), anchor="middle"))
    return "\n".join(o)


def dist_bar(x, y, w, h):
    o = []
    cx = x
    _clip[0] += 1
    cid = f"clip{_clip[0]}"
    o.append(f'<clipPath id="{cid}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{h / 2}"/></clipPath><g clip-path="url(#{cid})">')
    for p, col, _ in DIST28:
        bw = w * p / 100
        o.append(rect(cx, y, bw - 2 if cx + bw < x + w - 1 else bw, h, 0, col))
        cx += bw
    o.append("</g>")
    return "\n".join(o)


def dist_legend(x, y, size=14):
    o = []
    cx = x
    for p, col, name in DIST28:
        o.append(f'<circle cx="{cx + 5}" cy="{y - size * 0.35}" r="5" fill="{col}"/>')
        s = f"{p} % {name}"
        o.append(text(cx + 15, y, s, size, TXT))
        cx += 15 + tw(s, size) + 16
    return "\n".join(o), cx - x


def svg_doc(w, h, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            f'width="{w}" height="{h}" viewBox="0 0 {w} {h}">{DEFS}\n{body}\n</svg>')


# ================================================================ Variante A iPad
def variante_a_ipad():
    W, H = 1194, 834
    o = [rect(0, 0, W, H, 0, BG)]
    o.append(statusbar_ipad("ENTWURF  ·  VARIANTE A „HEUTE-KARTE“  ·  BEISPIELDATEN"))
    o.append(header_ipad())

    # ---- Heute-Karte
    hx, hy, hw, hh = 32, 100, 744, 702
    (fu, fv), _ = route_center(SUG["course"])
    o.append(f'<g filter="url(#shadow)">{rect(hx, hy, hw, hh, 28, PANEL)}</g>')
    o.append(aerial(SUG["course"], hx, hy, hw, hh, 28, focus=(fu, fv), scale=1300, at=(0.83, 0.40), route=False,
                    imgsize=900, bright=1.15))
    o.append(rect(hx, hy, hw, hh, 28, "url(#heroL)"))
    o.append(rect(hx, hy, hw, hh, 28, "url(#heroB)"))
    o.append(aerial(SUG["course"], hx, hy, hw, hh, 28, focus=(fu, fv), scale=1300, at=(0.83, 0.40), rw=4.5, image=False))
    o.append(rect(hx, hy, hw, hh, 28, "none", "#FFFFFF", 1, extra='stroke-opacity="0.08"'))
    L = hx + 44
    maxw = 440
    o.append(text(L, 158, SUG["eyebrow"], 15, ORANGE, bold=True, ls=2, maxw=maxw, tag="A"))
    o.append(text(L, 214, SUG["title1"], 50, TXT, bold=True, maxw=maxw, tag="A"))
    o.append(text(L, 268, SUG["title2"], 50, TXT, bold=True, maxw=maxw, tag="A"))
    o.append(text(L, 308, SUG["sub"], 19, "#C9D2DC", maxw=480, tag="A"))
    o.append(phase_bar(L, 334, 400, 52))
    o.append(text(L, 408, "Einrudern", 12, SEC))
    o.append(text(L + 400, 408, "Ausrudern", 12, SEC, anchor="end"))
    # Zielwerte
    tx = L
    for lab, val, unit in SUG["targets"]:
        o.append(text(tx, 452, lab, 13, SEC, bold=True, ls=1.2))
        o.append(text(tx, 488, val, 30, TXT, bold=True))
        vw = tw(val, 30, True)
        if unit:
            o.append(text(tx + vw + 6, 488, unit, 15, SEC))
        tx += max(vw + (tw(unit, 15) + 6 if unit else 0), tw(lab, 13, True, 1.2)) + 40
    if tx - L > 640:
        WARN.append("A Zielwerte zu breit")
    # Begruendung
    o.append(rect(L, 516, 520, 66, 14, "#FFFFFF", opacity=0.07))
    o.append(rect(L, 516, 4, 66, 2, ORANGE))
    o.append(text(L + 20, 543, SUG["why1"], 17, TXT, maxw=490, tag="A"))
    o.append(text(L + 20, 568, SUG["why2"], 17, "#C9D2DC", maxw=490, tag="A"))
    # Tasten
    o.append(pill_button(L, 614, 210, 68, "Los", True, 26))
    o.append(pill_button(L + 226, 614, 200, 68, "Anders wählen", False, 19))
    # Alternativen
    o.append(text(L, 734, "Oder:", 15, SEC))
    cx = L + 52
    for lab in ["Lockere Grundlage 30 min", "Frei rudern · Utoquai"]:
        c, w = chip(cx, 711, lab, 15)
        o.append(c)
        cx += w + 10
    o.append(text(L, 776, "Vorschlag aus deinen letzten Fahrten. Fühlst du dich anders, wähle frei.", 13, SEC, maxw=650, tag="A"))

    # ---- rechte Spalte: Diese Woche
    rx, rw_ = 796, 366
    o.append(rect(rx, 100, rw_, 446, 24, PANEL, extra='stroke="#FFFFFF" stroke-opacity="0.07"'))
    P = rx + 26
    IW = rw_ - 52
    o.append(text(P, 140, "Diese Woche", 22, TXT, bold=True))
    o.append(text(rx + rw_ - 26, 140, "KW 48", 15, SEC, anchor="end"))
    o.append(week_dots(P - 4, 182, IW + 8, r=15, labsize=14))
    o.append(text(P, 278, "19", 46, TXT, bold=True))
    o.append(text(P + tw("19", 46, True) + 8, 278, "min", 20, SEC, bold=True))
    o.append(text(P + 150, 278, "4,0 km", 20, TXT, bold=True))
    o.append(text(P, 306, "Ø der 4 Wochen davor: 112 min pro Woche", 15, SEC, maxw=IW, tag="A"))
    # Serie
    o.append(rect(P, 324, IW, 44, 12, GELB, opacity=0.10))
    o.append(f'<path d="M{P + 22},{335} l3.2,6.6 7.2,1 -5.2,5 1.3,7.2 -6.5,-3.4 -6.5,3.4 1.3,-7.2 -5.2,-5 7.2,-1 z" fill="{GELB}"/>')
    o.append(text(P + 42, 351, "7 Wochen in Folge mit 3 Fahrten", 15, TXT, bold=True, maxw=IW - 50, tag="A"))
    o.append(f'<line x1="{P}" y1="392" x2="{P + IW}" y2="392" stroke="#FFFFFF" stroke-opacity="0.08"/>')
    o.append(text(P, 424, "Leicht und hart", 17, TXT, bold=True))
    o.append(text(rx + rw_ - 26, 424, "letzte 28 Tage", 14, SEC, anchor="end"))
    o.append(dist_bar(P, 442, IW, 14))
    leg, lw = dist_legend(P, 486, 14)
    if lw > IW + 16:
        WARN.append(f"A Legende zu breit {lw}")
    o.append(leg)
    o.append(text(P, 516, "3 von 12 Einheiten hart · Ziel etwa 80/20", 14, SEC, maxw=IW, tag="A"))

    # ---- Letzte Fahrt
    ly = 562
    o.append(rect(rx, ly, rw_, 240, 24, PANEL, extra='stroke="#FFFFFF" stroke-opacity="0.07"'))
    (uu, uv), (du, dv) = route_center("zuerichsee-utoquai")
    o.append(aerial("zuerichsee-utoquai", P, ly + 24, 92, 92, 14, focus=(uu, uv), scale=92 / (dv * 1.25), rw=2.5))
    o.append(text(P + 110, ly + 46, "LETZTE FAHRT", 13, SEC, bold=True, ls=1.2))
    o.append(text(P + 110, ly + 75, "Gestern, 11:27", 21, TXT, bold=True))
    o.append(text(P + 110, ly + 99, "Utoquai – Seefeld · frei", 15, SEC, maxw=IW - 110, tag="A"))
    vals = [("4000", "m"), ("18:51", ""), ("2:21", "/500 m"), ("117", "bpm")]
    labs = ["Distanz", "Zeit", "Tempo", "Ø Puls"]
    ws = [tw(v, 23, True) + (tw(u, 12) + 3 if u else 0) for v, u in vals]
    g = (IW - sum(ws)) / 3
    colw = [w_ + g for w_ in ws]
    cx = P
    for (v, u), l, cw in zip(vals, labs, colw):
        o.append(text(cx, ly + 160, v, 23, TXT, bold=True))
        if u:
            o.append(text(cx + tw(v, 23, True) + 3, ly + 160, u, 12, SEC))
        o.append(text(cx, ly + 182, l, 13, SEC))
        cx += cw
    if cx - g - P > IW + 1:
        WARN.append(f"A Metriken zu breit {cx - P}")
    o.append(f'<path d="M{P + 7},{ly + 205} l2.4,5 5.4,0.8 -3.9,3.8 0.9,5.4 -4.8,-2.6 -4.8,2.6 0.9,-5.4 -3.9,-3.8 5.4,-0.8 z" fill="{GELB}"/>')
    o.append(text(P + 22, ly + 218, "Bestzeit auf dieser Strecke, 33 s schneller", 14, TXT, maxw=IW - 22, tag="A"))
    return svg_doc(W, H, "\n".join(o))


# ================================================================ Variante B iPad
def variante_b_ipad():
    W, H = 1194, 834
    o = [rect(0, 0, W, H, 0, BG)]
    (fu, fv), _ = route_center(SUG["course"])
    # Vollbild-Landschaft: Route liegt rechts oben im Bild
    S = 1500
    o.append(aerial(SUG["course"], 0, 0, W, H, 0, focus=(fu, fv), scale=S, at=(744 / W, 312 / H), route=False,
                    imgsize=900, bright=1.35))
    o.append(rect(0, 0, W, H, 0, "url(#fullTop)"))
    o.append(rect(0, 0, W, H, 0, "url(#fullLeft)"))
    o.append(aerial(SUG["course"], 0, 0, W, H, 0, focus=(fu, fv), scale=S, at=(744 / W, 312 / H), rw=5, image=False))
    o.append(statusbar_ipad("ENTWURF  ·  VARIANTE B „LANDSCHAFT ALS BÜHNE“  ·  BEISPIELDATEN"))
    o.append(header_ipad(glass=True))

    L = 48
    o.append(text(L, 150, "HEUTE · " + TODAY.upper(), 15, ORANGE, bold=True, ls=2))
    o.append(text(L, 210, "Pyramide", 52, TXT, bold=True, maxw=560, tag="B"))
    o.append(text(L, 268, "am Rheinknie", 52, TXT, bold=True, maxw=560, tag="B"))
    o.append(text(L, 306, "Zeit-Pyramide 1-2-3-4-3-2-1  ·  32 min  ·  Rhein Basel", 18, "#D5DCE4", maxw=560, tag="B"))
    # Ziele als Chips
    cx = L
    for lab in ["1:51–1:57 /500 m", "Schlagzahl 22–28", "Zone 4"]:
        c, w = chip(cx, 326, lab, 16, 36, 0.14, TXT, True)
        o.append(c)
        cx += w + 10
    o.append(text(L, 396, "Letzte harte Einheit vor 7 Tagen – heute ein Reiz.", 16, "#D5DCE4", maxw=560, tag="B"))
    o.append(pill_button(L, 420, 200, 64, "Los", True, 25))
    o.append(pill_button(L + 214, 420, 190, 64, "Anders wählen", False, 18))
    o.append(text(L + 420, 458, "oder frei rudern", 16, "#D5DCE4"))
    o.append(f'<line x1="{L + 420}" y1="462" x2="{L + 420 + tw("oder frei rudern", 16)}" y2="462" stroke="#D5DCE4" stroke-opacity="0.5"/>')

    # Schwebende Karte: Deine Woche
    kx, ky, kw, kh = 852, 104, 310, 360
    o.append(f'<g filter="url(#shadow)">{rect(kx, ky, kw, kh, 24, PANEL, opacity=0.86)}</g>')
    o.append(rect(kx, ky, kw, kh, 24, "none", "#FFFFFF", 1, extra='stroke-opacity="0.12"'))
    P = kx + 24
    IW = kw - 48
    o.append(text(P, ky + 40, "Diese Woche", 20, TXT, bold=True))
    o.append(text(kx + kw - 24, ky + 40, "KW 48", 14, SEC, anchor="end"))
    o.append(week_dots(P - 4, ky + 78, IW + 8, r=13, labsize=13))
    o.append(text(P, ky + 164, "19", 40, TXT, bold=True))
    o.append(text(P + tw("19", 40, True) + 7, ky + 164, "min", 18, SEC, bold=True))
    o.append(text(P + 128, ky + 164, "4,0 km", 18, TXT, bold=True))
    o.append(text(P, ky + 190, "Ø 4 Vorwochen: 112 min pro Woche", 13, SEC, maxw=IW, tag="B"))
    o.append(dist_bar(P, ky + 208, IW, 10))
    o.append(text(P, ky + 238, "28 Tage: 79 % leicht · 15 % hart", 13, SEC, maxw=IW, tag="B"))
    o.append(f'<line x1="{P}" y1="{ky + 258}" x2="{P + IW}" y2="{ky + 258}" stroke="#FFFFFF" stroke-opacity="0.10"/>')
    o.append(text(P, ky + 284, "LETZTE FAHRT · GESTERN", 12, SEC, bold=True, ls=1.2))
    o.append(text(P, ky + 312, "Utoquai · 4000 m in 18:51", 18, TXT, bold=True, maxw=IW, tag="B"))
    o.append(text(P, ky + 338, "2:21 /500 m · 25 /min · Ø 117 bpm", 15, SEC, maxw=IW, tag="B"))

    # Seen-Pass
    o.append(text(L, 560, "Deine Strecken", 20, TXT, bold=True))
    o.append(text(L + tw("Deine Strecken", 20, True) + 14, 560, "Tippen wählt die Strecke für den Vorschlag", 15, SEC))
    n = 5
    gap = 16
    cw = (W - 2 * L - gap * (n - 1)) / n
    cy0, ch = 580, 222
    for i, (cid, name, water, l1, l2, badge) in enumerate(PASS):
        x = L + i * (cw + gap)
        sel = badge == "Heute"
        o.append(f'<g filter="url(#shadow)">{rect(x, cy0, cw, ch, 18, PANEL, opacity=0.92)}</g>')
        (u, v), (du, dv) = route_center(cid)
        sc = max(cw / (max(du, dv) * 1.35), cw)
        o.append(aerial(cid, x, cy0, cw, 112, 18, focus=(u, v), scale=sc, rw=2.5))
        o.append(rect(x, cy0 + 100, cw, 12, 0, PANEL, opacity=0.92))
        o.append(text(x + 16, cy0 + 140, name, 16, TXT, bold=True, maxw=cw - 28, tag="B"))
        o.append(text(x + 16, cy0 + 161, water, 13, SEC, maxw=cw - 28, tag="B"))
        open_ = l1 == "noch offen"
        o.append(text(x + 16, cy0 + 190, l1, 14, SEE if open_ else TXT, bold=open_, maxw=cw - 28, tag="B"))
        o.append(text(x + 16, cy0 + 209, l2, 13, SEC, maxw=cw - 28, tag="B"))
        if sel:
            o.append(rect(x - 1.5, cy0 - 1.5, cw + 3, ch + 3, 19.5, "none", ORANGE, 3))
        if badge:
            bw_ = tw(badge, 12, True) + 20
            o.append(rect(x + 10, cy0 + 10, bw_, 24, 12, ORANGE if sel else "#0B1F3A", opacity=1 if sel else 0.85))
            o.append(text(x + 10 + bw_ / 2, cy0 + 26.5, badge, 12, NAVY if sel else TXT, bold=True, anchor="middle"))
    return svg_doc(W, H, "\n".join(o))


# ================================================================ iPhone
def statusbar_phone(label):
    o = [text(46, 34, "18:05", 17, TXT, bold=True, anchor="middle")]
    o.append(rect(134, 11, 125, 37, 18.5, "#000"))
    o.append(rect(318, 23, 25, 12, 3.5, "none", TXT, 1.2, extra='stroke-opacity="0.6"'))
    o.append(rect(320, 25, 21, 8, 2, TXT))
    lw = tw(label, 10, True, 1) + 20
    o.append(rect(196.5 - lw / 2, 52, lw, 17, 8.5, BG, opacity=0.7))
    o.append(text(196.5, 64, label, 10, ORANGE, bold=True, anchor="middle", ls=1))
    return "\n".join(o)


def tabbar_phone():
    o = [rect(0, 768, 393, 84, 0, "#0A1522", opacity=0.96),
         f'<line x1="0" y1="768" x2="393" y2="768" stroke="#FFFFFF" stroke-opacity="0.08"/>']
    tabs = ["Rudern", "Verlauf", "Geräte", "Einstellungen"]
    for i, t in enumerate(tabs):
        cx = 393 / 8 * (2 * i + 1)
        col = SEE if i == 0 else SEC
        # einfache Symbole
        if i == 0:
            o.append(f'<path d="M{cx - 11},796 h22 M{cx - 7},790 l10,-6 M{cx + 4},781 a3.5,3.5 0 1,1 0.1,0" stroke="{col}" stroke-width="2.4" fill="none" stroke-linecap="round"/>')
        elif i == 1:
            o.append(f'<path d="M{cx - 10},796 v-6 M{cx - 3},796 v-12 M{cx + 4},796 v-9 M{cx + 11},796 v-15" stroke="{col}" stroke-width="3" stroke-linecap="round"/>')
        elif i == 2:
            o.append(rect(cx - 8, 779, 16, 18, 3, "none", col, 2.2))
        else:
            o.append(f'<circle cx="{cx}" cy="788" r="8" fill="none" stroke="{col}" stroke-width="2.4"/><circle cx="{cx}" cy="788" r="2.5" fill="{col}"/>')
        o.append(text(cx, 815, t, 10, col, bold=(i == 0), anchor="middle"))
    o.append(rect(130, 838, 133, 5, 2.5, TXT))
    return "\n".join(o)


def phone_header(y=76):
    o = [f'<clipPath id="plogo"><rect x="16" y="{y}" width="30" height="30" rx="8"/></clipPath>',
         f'<image x="16" y="{y}" width="30" height="30" href="{LOGO}" clip-path="url(#plogo)"/>',
         text(54, y + 21, "RowCoach", 17, TXT, bold=True)]
    # Gerätestatus kompakt
    o.append(rect(263, y + 1, 114, 28, 14, "#FFFFFF", opacity=0.10))
    o.append(f'<circle cx="278" cy="{y + 15}" r="4.5" fill="{GRUEN}"/>')
    o.append(text(288, y + 20, "PM5", 13, TXT, bold=True))
    o.append(heart(332, y + 15, 5, "#FF5A6A"))
    o.append(text(342, y + 20, "64", 13, TXT, bold=True))
    return "\n".join(o)


def variante_a_iphone():
    W, H = 393, 852
    o = [rect(0, 0, W, H, 0, BG), statusbar_phone("ENTWURF · VARIANTE A · BEISPIELDATEN"), phone_header()]
    hx, hy, hw, hh = 16, 120, 361, 440
    (fu, fv), _ = route_center(SUG["course"])
    kw_ = dict(focus=(fu, fv), scale=700, at=(0.68, 122 / 440))
    o.append(aerial(SUG["course"], hx, hy, hw, hh, 24, route=False, bright=1.15, **kw_))
    o.append(rect(hx, hy, hw, hh, 24, "url(#phoneHero)"))
    o.append(aerial(SUG["course"], hx, hy, hw, hh, 24, rw=3.5, image=False, **kw_))
    L = hx + 20
    IW = hw - 40
    o.append(text(L, hy + 150, SUG["eyebrow"], 12, ORANGE, bold=True, ls=1.6))
    o.append(text(L, hy + 186, SUG["title1"], 30, TXT, bold=True, maxw=IW, tag="Ai"))
    o.append(text(L, hy + 220, SUG["title2"], 30, TXT, bold=True, maxw=IW, tag="Ai"))
    o.append(text(L, hy + 246, "Rhein Basel – Rheinweg · 32 min", 15, "#C9D2DC", maxw=IW, tag="Ai"))
    o.append(phase_bar(L, hy + 262, IW, 28))
    cx = L
    for lab, val, unit in SUG["targets"]:
        o.append(text(cx, hy + 316, lab, 10, SEC, bold=True, ls=1))
        o.append(text(cx, hy + 340, val, 20, TXT, bold=True))
        cx += [128, 104, 90][SUG["targets"].index((lab, val, unit))]
    o.append(text(L, hy + 366, "Letzte harte Einheit vor 7 Tagen.", 13, "#C9D2DC", maxw=IW, tag="Ai"))
    o.append(pill_button(L, hy + 380, 190, 48, "Los", True, 20))
    o.append(pill_button(L + 200, hy + 380, IW - 200, 48, "Anders", False, 16))
    # Woche
    wy = 576
    o.append(rect(16, wy, 361, 112, 20, PANEL, extra='stroke="#FFFFFF" stroke-opacity="0.07"'))
    o.append(text(36, wy + 30, "Diese Woche", 16, TXT, bold=True))
    o.append(text(357, wy + 30, "19 min · Ø 112", 14, SEC, anchor="end"))
    o.append(week_dots(28, wy + 56, 337, r=10, labsize=11))
    o.append(dist_bar(36, wy + 96, 321, 6))
    # Letzte Fahrt
    ly = 700
    o.append(rect(16, ly, 361, 60, 18, PANEL, extra='stroke="#FFFFFF" stroke-opacity="0.07"'))
    (uu, uv), (du, dv) = route_center("zuerichsee-utoquai")
    o.append(aerial("zuerichsee-utoquai", 26, ly + 8, 44, 44, 10, focus=(uu, uv), scale=44 / (dv * 1.2), rw=1.6, dots=False))
    o.append(text(82, ly + 26, "Gestern · Utoquai – Seefeld", 14, TXT, bold=True, maxw=280, tag="Ai"))
    o.append(text(82, ly + 46, "4000 m · 18:51 · 2:21 /500 m · Ø 117", 13, SEC, maxw=280, tag="Ai"))
    o.append(tabbar_phone())
    return svg_doc(W, H, "\n".join(o))


def variante_b_iphone():
    W, H = 393, 852
    o = [rect(0, 0, W, H, 0, BG)]
    (fu, fv), _ = route_center(SUG["course"])
    kw_ = dict(focus=(fu, fv), scale=800, at=(260 / W, 200 / 470))
    o.append(aerial(SUG["course"], 0, 0, W, 470, 0, route=False, bright=1.3, **kw_))
    o.append(rect(0, 0, W, 470, 0, "url(#phoneFull)"))
    o.append(aerial(SUG["course"], 0, 0, W, 470, 0, rw=4, image=False, **kw_))
    o.append(statusbar_phone("ENTWURF · VARIANTE B · BEISPIELDATEN"))
    o.append(phone_header())
    L = 20
    o.append(text(L, 290, "HEUTE · DIENSTAG", 12, ORANGE, bold=True, ls=1.6))
    o.append(text(L, 326, "Pyramide", 31, TXT, bold=True, maxw=353, tag="Bi"))
    o.append(text(L, 362, "am Rheinknie", 31, TXT, bold=True, maxw=353, tag="Bi"))
    o.append(text(L, 390, "1-2-3-4-3-2-1 · 32 min · Zone 4 · 1:51–1:57", 14, "#D5DCE4", maxw=353, tag="Bi"))
    o.append(pill_button(L, 408, 200, 50, "Los", True, 20))
    o.append(pill_button(L + 212, 408, 141, 50, "Anders", False, 16))
    # Woche kompakt
    wy = 476
    o.append(rect(16, wy, 361, 92, 20, PANEL, extra='stroke="#FFFFFF" stroke-opacity="0.07"'))
    o.append(text(36, wy + 28, "Diese Woche", 15, TXT, bold=True))
    o.append(text(357, wy + 28, "19 min · 7 Wochen in Folge", 13, SEC, anchor="end"))
    o.append(week_dots(28, wy + 52, 337, r=9, labsize=10))
    # Strecken
    o.append(text(20, 594, "Deine Strecken", 16, TXT, bold=True))
    o.append(text(373, 594, "Alle 5", 14, SEE, bold=True, anchor="end"))
    cw, ch, cy0 = 172, 144, 610
    for i, idx in enumerate([2, 0]):
        cid, name, water, l1, l2, badge = PASS[idx]
        x = 16 + i * (cw + 17)
        sel = badge == "Heute"
        o.append(rect(x, cy0, cw, ch, 16, PANEL))
        (u, v), (du, dv) = route_center(cid)
        o.append(aerial(cid, x, cy0, cw, 82, 16, focus=(u, v), scale=max(cw / (max(du, dv) * 1.35), cw), rw=2))
        o.append(rect(x, cy0 + 70, cw, 12, 0, PANEL))
        o.append(text(x + 12, cy0 + 102, name, 14, TXT, bold=True, maxw=cw - 20, tag="Bi"))
        o.append(text(x + 12, cy0 + 120, l1, 12, TXT, maxw=cw - 20, tag="Bi"))
        o.append(text(x + 12, cy0 + 136, l2, 12, SEC, maxw=cw - 20, tag="Bi"))
        if sel:
            o.append(rect(x - 1.5, cy0 - 1.5, cw + 3, ch + 3, 17.5, "none", ORANGE, 2.5))
        bw_ = tw(badge, 11, True) + 16
        o.append(rect(x + 8, cy0 + 8, bw_, 20, 10, ORANGE if sel else NAVY, opacity=1 if sel else 0.85))
        o.append(text(x + 8 + bw_ / 2, cy0 + 22, badge, 11, NAVY if sel else TXT, bold=True, anchor="middle"))
    o.append(tabbar_phone())
    return svg_doc(W, H, "\n".join(o))


def render(name, svg, w, h):
    (OUT / f"{name}.svg").write_text(svg)
    cairosvg.svg2png(bytestring=svg.encode(), write_to=str(OUT / f"{name}.png"), output_width=w * 2, output_height=h * 2)


if __name__ == "__main__":
    render("variante-a-ipad", variante_a_ipad(), 1194, 834)
    render("variante-b-ipad", variante_b_ipad(), 1194, 834)
    render("variante-a-iphone", variante_a_iphone(), 393, 852)
    render("variante-b-iphone", variante_b_iphone(), 393, 852)
    for w in WARN:
        print("WARNUNG:", w)
    print("fertig")
