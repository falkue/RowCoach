"""Zusammensetzen von Figur und Boot zu einer Stellung – dieselbe Rechnung wie `RowerFigure.apply` / `BoatModel.apply`
in der App (App/RowCoach/Scene3D/RowerFigure.swift). Dient den Vorschaubildern und als Referenz für die Gelenke.

Alle Ergebnisse im boat-Rahmen (Bug = −z). Erscheinung als dict aus appearance.json (Figurtyp + Boot).
"""
from __future__ import annotations

import math

import numpy as np

import boat as B
import figure as F
from geom import basis_y, rot_x, rot_y

BUILD_THICK = {"slim": 0.90, "athletic": 1.0, "broad": 1.12}
HEAD_COUNTER = 0.6


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)


def ease(x):
    return 0.5 - 0.5 * math.cos(math.pi * min(max(x, 0), 1))


def stroke_pose(phase, drive_share=0.40):
    """Wie BoatRig.StrokePose.at(phase:strokeRate:) (Anteil Durchzug fest)."""
    p = phase - math.floor(phase)
    in_water = feather = 0.0
    if p < drive_share:
        u = p / drive_share
        f = ease(u)
        in_water = smoothstep(0, 0.08, u) * (1 - smoothstep(0.92, 1, u))
    else:
        u = (p - drive_share) / (1 - drive_share)
        f = 1 - ease(u)
        feather = min(smoothstep(0, 0.12, u), 1 - smoothstep(0.75, 0.95, u))
    return dict(sweep=58 + (-38 - 58) * f, blade=in_water, feather=feather, slide=smoothstep(0, 0.6, f),
                lean=25 + (-15 - 25) * smoothstep(0.3, 0.9, f))


REST = dict(sweep=-20, blade=0.75, feather=1, slide=0.9, lean=-5)


def two_bone(a, b, l1, l2, pole, max_stretch=1.08):
    """Gelenk zwischen a und b (Längen l1, l2), auf der Seite von `pole`. Liefert (Gelenk, Streckfaktor)."""
    d = b - a
    dist = float(np.linalg.norm(d))
    k = 1.0
    if dist > (l1 + l2) * 0.999:
        k = min(dist / ((l1 + l2) * 0.999), max_stretch)
    l1s, l2s = l1 * k, l2 * k
    dist_c = min(dist, (l1s + l2s) * 0.999)
    u = d / max(dist, 1e-6)
    x = (l1s * l1s - l2s * l2s + dist_c * dist_c) / (2 * dist_c)
    h = math.sqrt(max(l1s * l1s - x * x, 0))
    pp = pole - u * np.dot(pole, u)
    pp = pp / max(np.linalg.norm(pp), 1e-6)
    return a + u * x + pp * h, k


class Pose:
    """Transformationen aller Segmente (crew-Rahmen) für Figur-Parameter und Schlagstellung."""

    def __init__(self, ch, pose):
        hs = ch.get("heightScale", 1.0)
        ss = ch.get("shoulderScale", 1.0)
        th = BUILD_THICK.get(ch.get("build", "athletic"), 1.0)
        self.T = {}
        hip_z = 0.05 + 0.45 * pose["slide"]
        hip = np.array([0, F.HIP_Y, hip_z])
        lean = math.radians(pose["lean"])
        Rl = rot_x(-lean)
        torso_scale = np.array([th * ss, hs, th * (1.1 if ch.get("build") == "broad" else 1.0)])
        self.T["pelvis"] = (Rl @ np.diag(torso_scale), hip)
        head_s = (hs ** 0.5)
        # Kopf bleibt aufrechter als der Oberkörper (Blick zum Heck): 60 % der Neigung zurückgedreht
        Rh = rot_x(-lean * (1 - HEAD_COUNTER))
        self.T["head"] = (Rh @ np.diag([head_s] * 3), hip + Rl @ np.array([0, F.TORSO_TOP * hs, 0]))
        self.T["seat"] = (np.eye(3), np.array([0, F.HIP_Y - 0.10, hip_z]))
        # Skulls
        sweep = math.radians(pose["sweep"])
        air, water = 0.18, -0.06
        blade_c = B.OUTBOARD - 0.23
        blade_y = air + (water - air) * pose["blade"]
        roll = math.asin(max(-1, min(1, (blade_y - B.PIN_Y) / blade_c)))
        self.oars = []
        handles = []
        for s in (1, -1):
            yaw = (0 if s > 0 else math.pi) - s * sweep
            q = rot_y(yaw) @ np.array([[math.cos(roll), -math.sin(roll), 0], [math.sin(roll), math.cos(roll), 0],
                                        [0, 0, 1]])
            pin = np.array([s * B.PIN_X, B.PIN_Y, B.PIN_Z])
            spin = rot_x(s * pose["feather"] * math.pi / 2)
            self.oars.append((s, q @ spin, pin))
            handles.append(pin + q @ np.array([-B.INBOARD + 0.07, 0, 0]) + np.array([0, s * 0.02, 0]))
        # Arme
        limb = np.array([th, 1.0, th])
        for i, s in enumerate((1, -1)):
            sh = hip + Rl @ np.array([s * F.SHOULDER_HALF * ss, F.SHOULDER_Y * hs, 0])
            l1, l2 = F.UPPER_ARM * hs, F.FOREARM * hs
            elbow, k = two_bone(sh, handles[i], l1, l2, np.array([s * 0.75, -0.35, 0.55]))
            hand = elbow + (handles[i] - elbow) / max(np.linalg.norm(handles[i] - elbow), 1e-6) * l2 * k
            side = "R" if s > 0 else "L"
            self.T[f"upperarm_{side}"] = (basis_y(elbow - sh, [s, 0, 0]) @ np.diag(limb * [1, hs * k, 1]), sh)
            self.T[f"forearm_{side}"] = (basis_y(hand - elbow, [s, 0, 0]) @ np.diag(limb * [1, hs * k, 1]), elbow)
        # Beine
        for s in (1, -1):
            h = np.array([s * F.HIP_HALF, F.HIP_Y, hip_z])
            foot = np.array([s * F.FOOT_HALF, F.FOOT_Y, F.FOOT_Z])
            knee, k = two_bone(h, foot, F.THIGH, F.SHIN, np.array([s * 0.12, 1, 0]))
            side = "R" if s > 0 else "L"
            self.T[f"thigh_{side}"] = (basis_y(knee - h, [s, 0, 0]) @ np.diag(limb * [1, k, 1]), h)
            self.T[f"shin_{side}"] = (basis_y(foot - knee, [s, 0, 0]) @ np.diag(limb * [1, k, 1]), knee)
            self.T[f"foot_{side}"] = (np.diag([th, 1, 1]), foot)


CREW = rot_y(math.pi)


CAP_HAIR = {"short", "buzz", "curly", "afro", "headband", "cap"}   # unter der Cap: kurze Haarkappe


def figure_prims(ch):
    """Sichtbare Figur-Prims für eine aufgelöste Erscheinung → Liste (prim, segment-Instanz, Farbschlüssel).
    Dieselbe Regel wie `AvatarPartRules.figureParts` im Kit (die App nutzt nur diese); Gleichheit prüft der Kit-Test
    mit tools/avatars/figure_parts_expected.json (export_rules.py)."""
    style = ch.get("shirtStyle", "tank")
    legs_long = ch.get("legStyle", "short") == "long"
    hair = ch.get("hairStyle", "short")
    acc = set(ch.get("accessories", []))
    if hair == "cap":
        acc.add("cap")
    if hair == "headband":
        acc.add("headband")
    covered = "hijab" in acc or "patka" in acc
    torso = {"tee": ["torso_tee__shirt"], "longsleeve": ["torso_tee__shirt"],
             "tank": ["torso_tank__skin", "torso_tank__shirt"],
             "unisuit": ["torso_unisuit__skin", "torso_unisuit__shirt"]}.get(style, ["torso_tank__skin",
                                                                                     "torso_tank__shirt"])
    out = [("hips__shorts", "pelvis", "shorts")] + [(t, "pelvis", t.split("__")[1]) for t in torso]
    out += [("head__skin", "head", "skin")]
    if "sunglasses" not in acc:
        out += [("eyes__eyes", "head", "eyes"), ("eyes_white__eyes_hl", "head", "eyes_hl")]
    if hair != "bald" and not covered:
        h = "cap" if "cap" in acc and hair in CAP_HAIR else hair
        out.append((f"hair_{h}__hair", "head", "hair"))
    beard = ch.get("beard", "none")
    if beard in ("short", "full"):
        out.append((f"beard_{beard}__hair", "head", "beard"))
    if "hijab" in acc:
        out.append(("acc_hijab__headwear", "head", "headwear"))
    elif "patka" in acc:
        out.append(("acc_patka__headwear", "head", "headwear"))
    elif "cap" in acc:
        out.append(("acc_cap__accessory", "head", "cap"))
    elif "headband" in acc:
        out.append(("acc_headband__accessory", "head", "headband"))
    if "sunglasses" in acc:
        out.append(("acc_sunglasses__accessory", "head", "sunglasses"))
    for side in ("R", "L"):
        if style == "tee":
            out += [("upperarm_tee__shirt", f"upperarm_{side}", "shirt"),
                    ("upperarm_tee__skin", f"upperarm_{side}", "skin")]
            out += [("forearm__skin", f"forearm_{side}", "skin")]
        elif style == "longsleeve":
            out += [("upperarm_bare__skin", f"upperarm_{side}", "shirt"),
                    ("forearm_long__shirt", f"forearm_{side}", "shirt"),
                    ("forearm_long__skin", f"forearm_{side}", "skin")]
        else:
            out += [("upperarm_bare__skin", f"upperarm_{side}", "skin"), ("forearm__skin", f"forearm_{side}", "skin")]
        leg = "shorts" if legs_long else "skin"
        out += [("thigh__shorts", f"thigh_{side}", "shorts"), ("thigh__skin", f"thigh_{side}", leg),
                ("shin__skin", f"shin_{side}", leg), ("shin__socks", f"shin_{side}", "socks"),
                ("foot__shoes", f"foot_{side}", "shoes")]
    if "watch" in acc:
        out.append(("acc_watch__accessory", "forearm_L", "watch"))
    return out


def boat_prims(bs, flag=False):
    rig = bs.get("riggerType", "wing")
    blade = bs.get("bladeShape", "bigblade")
    out = [("hull__hull", "boat"), ("hull_stripe__stripe", "boat"), ("deck__deck", "boat"),
           ("hull_tips__tips", "boat"), ("deck_tips__tips", "boat"),
           ("cockpit__fittings", "boat"), ("fin__fin", "boat"), ("seat__fittings", "seat"),
           ("tracks__fittings", "crew"), ("stretcher__fittings", "crew"), ("gates__fittings", "crew"),
           (f"rigger_{rig}__rigger", "crew")]
    if bs.get("bowBall", True):
        out.append(("bowball__bowball", "boat"))
    for side in ("R", "L"):
        out += [("oar_shaft__shaft", f"oar_{side}"), ("oar_grip__fittings", f"oar_{side}"),
                ("oar_sleeve__sleeve", f"oar_{side}"), (f"blade_{blade}_{side}__blade", f"oar_{side}")]
    if flag:
        out += [("flag_side_R__flag", "boat"), ("flag_side_L__flag", "boat"), ("flag_deck__flag", "boat"),
                (f"flag_rigger_{rig}__flag", "crew")]
    return out


def place(part, M, t):
    """Part mit Matrix M (inkl. Skalierung) und Verschiebung t, dann crew → boat."""
    return part.transformed(M, t)
