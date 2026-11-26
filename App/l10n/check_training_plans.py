#!/usr/bin/env python3
"""Prüft App/RowCoach/Resources/training_plans.json (Trainingspläne über mehrere Wochen) gegen plans.json.

Aufruf: python3 App/l10n/check_training_plans.py   (Exit-Code 1 bei Fehlern, Warnungen nur zur Info)

Geprüft wird:
- JSON gültig, Pflichtfelder, ids eindeutig, Texte de + en vorhanden (de ohne ß)
- jede planId existiert in plans.json; intensity passt zur Einstufung des Programms (Tags easy/moderate/hard/max)
- weeks == len(weeks_detail), Wochen fortlaufend 1..n, Slots fortlaufend 1..k
- Pflicht-Einheiten je Woche in sessionsPerWeek.min..max, mit freiwilligen höchstens max
- harte Einheiten (hard/max) nie in aufeinanderfolgenden Slots derselben Woche (inkl. freiwilliger);
  über die Wochengrenze nur Warnung (die App hält dort hardSessionsMinGapHours ein)
- höchstens 2 harte Pflicht-Einheiten pro Woche, höchstens 1 bei hardSessionsMinGapHours >= 72
- Deload-Wochen: geschätzte Minuten (Pflicht-Einheiten ohne Zieleinheit) mindestens 25 % unter der letzten
  normalen Woche davor
- Taper-Wochen: Minuten (ohne Zieleinheit) nehmen von Woche zu Woche nicht zu; letzte Taper-Woche mindestens 25 %
  unter dem Schnitt der letzten drei normalen Wochen vor dem Taper
- minutesPerWeek deckt die geschätzten Wochenminuten ab; retestWeek liegt im Plan
- Warnung, wenn weniger als 70 % der Pflichtzeit in Pulszone 1–2 liegen (Phasen-hrZone; Ziel etwa 75–80 %)
Dauer je Programm: Summe der Phasen, Distanzphasen grob mit 2:00/500 m geschätzt.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLANS = ROOT / "App/RowCoach/Resources/plans.json"
TRAINING = ROOT / "App/RowCoach/Resources/training_plans.json"

LEVELS = {("Einsteiger", "Beginner"), ("Fortgeschritten", "Advanced"), ("Leistung", "Performance")}
CATEGORIES = {"einstieg", "fitness", "grundlage", "test-2k", "langdistanz", "masters", "erhaltung", "wiedereinstieg", "wettkampf"}
POLICIES = {"shift", "skip", "replace-easy"}
INTENSITIES = ("easy", "moderate", "hard", "max")
HARD = {"hard", "max"}
I18N = ("name", "summary", "goal", "prerequisites")

errors, warnings = [], []


def err(pid, msg):
    errors.append(f"{pid}: {msg}")


def warn(pid, msg):
    warnings.append(f"{pid}: {msg}")


def minutes(prog):
    return sum(ph.get("durationS", ph.get("distanceM", 0) * 120 / 500) for ph in prog["phases"]) / 60


def prog_intensity(prog):
    return next((t for t in prog.get("tags", []) if t in INTENSITIES), "easy")


def check_text(pid, where, t):
    if not isinstance(t, dict) or not t.get("de") or not t.get("en"):
        err(pid, f"{where}: Text de/en fehlt")
        return
    if "ß" in t["de"]:
        err(pid, f"{where}: ß im deutschen Text (Schweizer Schreibung: ss)")


def main():
    progs = {p["id"]: p for p in json.loads(PLANS.read_text())}
    try:
        data = json.loads(TRAINING.read_text())
    except json.JSONDecodeError as e:
        print(f"FEHLER: training_plans.json ist kein gültiges JSON: {e}")
        return 1
    if data.get("version") != 1:
        err("datei", "version muss 1 sein")
    seen = set()
    for p in data.get("plans", []):
        pid = p.get("id", "?")
        if pid in seen:
            err(pid, "id doppelt")
        seen.add(pid)
        for k in I18N:
            check_text(pid, k, p.get(k))
        lv = p.get("level", {})
        if (lv.get("de"), lv.get("en")) not in LEVELS:
            err(pid, f"level ungültig: {lv}")
        if p.get("category") not in CATEGORIES:
            err(pid, f"category ungültig: {p.get('category')}")
        if p.get("season") not in (None, "winter"):
            err(pid, f"season ungültig: {p.get('season')}")
        if not p.get("sources"):
            err(pid, "keine Quellen")
        for s in p.get("sources", []):
            if not s.get("title") or not s.get("publisher") or not s.get("url"):
                err(pid, f"Quelle unvollständig: {s.get('title')}")
        ev = p.get("evidence", "")
        if not ev.split(":")[0].strip() in ("direkt", "angepasst", "abgeleitet"):
            err(pid, "evidence beginnt nicht mit direkt / angepasst / abgeleitet")

        spw = p["sessionsPerWeek"]
        rules = p["rules"]
        if rules.get("missedSessionPolicy") not in POLICIES:
            err(pid, f"missedSessionPolicy ungültig: {rules.get('missedSessionPolicy')}")
        gap72 = (rules.get("hardSessionsMinGapHours") or 48) >= 72
        weeks = p["weeks_detail"]
        if p["weeks"] != len(weeks):
            err(pid, f"weeks={p['weeks']}, aber {len(weeks)} Wochen in weeks_detail")
        rw = rules.get("retestWeek")
        if rw is not None and not 1 <= rw <= len(weeks):
            err(pid, f"retestWeek {rw} ausserhalb des Plans")

        req_min, full_min, train_min = [], [], []
        zone_lo = zone_all = 0.0
        prev_last_hard = False
        for wi, w in enumerate(weeks, 1):
            tag = f"Woche {wi}"
            if w.get("week") != wi:
                err(pid, f"{tag}: week={w.get('week')} (erwartet {wi})")
            check_text(pid, f"{tag} focus", w.get("focus"))
            sess = w.get("sessions", [])
            for si, s in enumerate(sess, 1):
                if s.get("slot") != si:
                    err(pid, f"{tag}: Slot {s.get('slot')} statt {si}")
                if s["planId"] not in progs:
                    err(pid, f"{tag}: planId {s['planId']} fehlt in plans.json")
                    continue
                exp = prog_intensity(progs[s["planId"]])
                if s.get("intensity") != exp:
                    err(pid, f"{tag} Slot {si}: intensity {s.get('intensity')} passt nicht zu {s['planId']} ({exp})")
                if "note" in s:
                    check_text(pid, f"{tag} Slot {si} note", s["note"])
            sess = [s for s in sess if s["planId"] in progs]
            req = [s for s in sess if not s.get("optional")]
            if not spw["min"] <= len(req) <= spw["max"]:
                err(pid, f"{tag}: {len(req)} Pflicht-Einheiten, erlaubt {spw['min']}..{spw['max']}")
            if len(sess) > spw["max"]:
                err(pid, f"{tag}: {len(sess)} Einheiten inkl. freiwilliger, höchstens {spw['max']}")
            hard = [s.get("intensity") in HARD for s in sess]
            for a, b in zip(hard, hard[1:]):
                if a and b:
                    err(pid, f"{tag}: zwei harte Einheiten in aufeinanderfolgenden Slots")
                    break
            if sess and prev_last_hard and hard[0]:
                warn(pid, f"{tag}: harte Einheit am Wochenanfang nach harter Einheit am Ende der Vorwoche (App verteilt mit {rules.get('hardSessionsMinGapHours')} h Abstand)")
            prev_last_hard = bool(sess) and hard[-1]
            n_hard = sum(1 for s in req if s.get("intensity") in HARD)
            if n_hard > (1 if gap72 else 2):
                err(pid, f"{tag}: {n_hard} harte Pflicht-Einheiten (höchstens {1 if gap72 else 2})")
            for s in req:
                for ph in progs[s["planId"]]["phases"]:
                    t = ph.get("durationS", ph.get("distanceM", 0) * 120 / 500)
                    zone_all += t
                    zone_lo += t if ph.get("hrZone", 2) <= 2 else 0
            req_min.append(sum(minutes(progs[s["planId"]]) for s in req))
            full_min.append(sum(minutes(progs[s["planId"]]) for s in sess))
            train_min.append(sum(minutes(progs[s["planId"]]) for s in req if not s.get("event")))

        # Deload
        for wi, w in enumerate(weeks):
            if not w.get("deload"):
                continue
            prev = [train_min[j] for j in range(wi - 1, -1, -1) if not weeks[j].get("deload") and not weeks[j].get("taper")]
            if not prev:
                err(pid, f"Woche {wi + 1}: Deload ohne normale Woche davor")
            elif train_min[wi] > 0.75 * prev[0]:
                err(pid, f"Woche {wi + 1}: Deload {train_min[wi]:.0f} min, nicht ≥ 25 % unter {prev[0]:.0f} min")
        # Taper
        tw = [i for i, w in enumerate(weeks) if w.get("taper")]
        if tw:
            for a, b in zip(tw, tw[1:]):
                if b == a + 1 and train_min[b] > train_min[a] + 0.5:
                    err(pid, f"Woche {b + 1}: Taper {train_min[b]:.0f} min > Vorwoche {train_min[a]:.0f} min")
            before = [train_min[j] for j in range(tw[0]) if not weeks[j].get("deload")][-3:]
            if before:
                ref = sum(before) / len(before)
                if train_min[tw[-1]] > 0.75 * ref:
                    err(pid, f"letzte Taper-Woche {train_min[tw[-1]]:.0f} min, nicht ≥ 25 % unter Schnitt {ref:.0f} min")
        if zone_all and zone_lo / zone_all < 0.70:
            warn(pid, f"nur {100 * zone_lo / zone_all:.0f} % der Pflichtzeit in Pulszone 1–2")
        mpw = p["minutesPerWeek"]
        if min(req_min) < mpw["min"] - 0.5 or max(full_min) > mpw["max"] + 0.5:
            err(pid, f"minutesPerWeek {mpw} deckt {min(req_min):.0f}..{max(full_min):.0f} min nicht ab")

    print(f"{len(data.get('plans', []))} Pläne geprüft: {len(errors)} Fehler, {len(warnings)} Warnungen")
    for e in errors:
        print("FEHLER:", e)
    for w in warnings:
        print("Warnung:", w)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
