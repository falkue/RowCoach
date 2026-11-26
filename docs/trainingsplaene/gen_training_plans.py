#!/usr/bin/env python3
"""Erzeugt App/RowCoach/Resources/training_plans.json (Planbibliothek aus Programmen in plans.json).

Schreibt ausserdem docs/trainingsplaene/PLAENE.md (lesbare Übersicht). Aufruf: python3 docs/trainingsplaene/gen_training_plans.py
Danach: python3 App/l10n/check_training_plans.py
Kurzform je Woche: (focus_de, focus_en, flags, [sessions]); session = "id" oder
("id", {"opt": True, "de": "Notiz", "en": "note"}). flags: "D" = Deload, "T" = Taper.
"""
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PROGS = {p["id"]: p for p in json.loads((REPO / "App/RowCoach/Resources/plans.json").read_text())}


def intensity(pid):
    for t in PROGS[pid]["tags"]:
        if t in ("easy", "moderate", "hard", "max"):
            return t
    return "easy"


# ---------------------------------------------------------------- Quellen
S = {
    "C2_C2C": dict(title="Beginner's Training Plan (Couch to Consistency)", publisher="Concept2",
                   url="https://www.concept2.com/training/plans/couch-to-consistency", published=None),
    "BR_BEG": dict(title="Go Row Indoor – Beginner Training Plan (8 weeks)", publisher="British Rowing",
                   url="https://www.britishrowing.org/wp-content/uploads/2016/10/BR_Go_Row_A4_Beginners_Training_Plan_P3.pdf",
                   published="2016-10"),
    "NHS_C25K": dict(title="Couch to 5K running plan", publisher="NHS (UK National Health Service)",
                     url="https://www.nhs.uk/better-health/get-active/get-running-with-couch-to-5k/couch-to-5k-running-plan",
                     published=None),
    "ACSM": dict(title="Garber et al.: Quantity and quality of exercise for developing and maintaining cardiorespiratory, musculoskeletal, and neuromotor fitness (ACSM Position Stand), Med Sci Sports Exerc 43(7):1334-1359",
                 publisher="American College of Sports Medicine / Wolters Kluwer",
                 url="https://pubmed.ncbi.nlm.nih.gov/21694556/", published="2011-07"),
    "C2_2K4": dict(title="Training for a 2K Rowing Ergometer Test – 4 Week Plan", publisher="Concept2",
                   url="https://www.concept2.com/training/plans/2k-erg-test-4-week", published=None),
    "C2_2K12": dict(title="Training for a 2K Rowing Ergometer Test – 12 Week Plan", publisher="Concept2",
                    url="https://www.concept2.com/training/plans/2k-erg-test-12-week", published=None),
    "C2_5K": dict(title="Training for a 5K Rowing Ergometer Test (8 or 12 weeks)", publisher="Concept2",
                  url="https://www.concept2.com/training/plans/5k-erg-test", published=None),
    "C2_HM": dict(title="Half Marathon Row Training Plan (10 weeks, 4 sessions/week)", publisher="Concept2",
                  url="https://www.concept2.com/training/plans/half-marathon-row-training-plan", published=None),
    "C2_MAR": dict(title="Marathon Row Training Plan (16 weeks, 4 sessions/week)", publisher="Concept2",
                   url="https://www.concept2.com/training/plans/marathon-row-training-plan", published=None),
    "PETE": dict(title="The Pete Plan (3-week cycle, FAQ)", publisher="The Pete Plan (Pete Marston)",
                 url="https://thepeteplan.wordpress.com/the-pete-plan/", published=None),
    "PETE_BEG": dict(title="Beginner Pete Plan (24 weeks, 3 core + 2 optional sessions)", publisher="The Pete Plan (Pete Marston)",
                     url="https://thepeteplan.wordpress.com/beginner-training/", published=None),
    "WOLFSON": dict(title="Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary source",
                    publisher="Wolfson College Boat Club, University of Cambridge",
                    url="https://www.wolfson.cam.ac.uk/sites/default/files/2019-11/wcbc_erging_0.pdf", published="2019"),
    "SEILER2009": dict(title="Seiler & Tønnessen: Intervals, Thresholds, and Long Slow Distance: the Role of Intensity and Duration in Endurance Training, Sportscience 13:32-53",
                       publisher="Sportscience (sportsci.org)", url="https://sportsci.org/2009/ss.htm", published="2009"),
    "SEILER2006": dict(title="Seiler & Kjerland: Quantifying training intensity distribution in elite endurance athletes, Scand J Med Sci Sports 16:49-56",
                       publisher="Wiley", url="https://pubmed.ncbi.nlm.nih.gov/16430681/", published="2006"),
    "STOGGL2014": dict(title="Stöggl & Sperlich: Polarized training has greater impact on key endurance variables than threshold, high intensity, or high volume training, Front Physiol 5:33",
                       publisher="Frontiers", url="https://doi.org/10.3389/fphys.2014.00033", published="2014"),
    "TREFF2017": dict(title="Treff et al.: Eleven-week preparation involving polarized intensity distribution is not superior to pyramidal distribution in national elite rowers, Front Physiol 8:515",
                      publisher="Frontiers", url="https://doi.org/10.3389/fphys.2017.00515", published="2017-08"),
    "FISK2004": dict(title="Fiskerstrand & Seiler: Training and performance characteristics among Norwegian international rowers 1970-2001, Scand J Med Sci Sports 14(5):303-310",
                     publisher="Wiley", url="https://pubmed.ncbi.nlm.nih.gov/15387804/", published="2004"),
    "GUELLICH2009": dict(title="Güllich, Seiler & Emrich: Training methods and intensity distribution of young world-class rowers, Int J Sports Physiol Perform 4(4):448-460",
                         publisher="Human Kinetics", url="https://pubmed.ncbi.nlm.nih.gov/20029096/", published="2009"),
    "BOSQUET2007": dict(title="Bosquet et al.: Effects of tapering on performance: a meta-analysis, Med Sci Sports Exerc 39(8):1358-1365",
                        publisher="Lippincott Williams & Wilkins", url="https://pubmed.ncbi.nlm.nih.gov/17762369/", published="2007"),
    "MUJIKA2000": dict(title="Mujika & Padilla: Detraining: loss of training-induced physiological and performance adaptations. Part I: short term insufficient training stimulus, Sports Med 30(2):79-87",
                       publisher="Springer (Adis)", url="https://pubmed.ncbi.nlm.nih.gov/10966148/", published="2000"),
    "MUJIKA2001": dict(title="Mujika & Padilla: Cardiorespiratory and metabolic characteristics of detraining in humans, Med Sci Sports Exerc 33(3):413-421",
                       publisher="Lippincott Williams & Wilkins", url="https://pubmed.ncbi.nlm.nih.gov/11252068/", published="2001"),
    "SPIERING2021": dict(title="Spiering et al.: Maintaining physical performance: the minimal dose of exercise needed to preserve endurance and strength over time, J Strength Cond Res 35(5):1449-1458",
                         publisher="Lippincott Williams & Wilkins", url="https://pubmed.ncbi.nlm.nih.gov/33629972/", published="2021"),
    "FELL2008": dict(title="Fell & Williams: The effect of aging on skeletal-muscle recovery from exercise: possible implications for aging athletes, J Aging Phys Act 16(1):97-115",
                     publisher="Human Kinetics", url="https://pubmed.ncbi.nlm.nih.gov/18268815/", published="2008"),
    "BORGES2016": dict(title="Borges, Reaburn, Driller & Argus: Age-related changes in performance and recovery kinetics in masters athletes: a narrative review, J Aging Phys Act 24(1):149-157",
                       publisher="Human Kinetics", url="https://researchcommons.waikato.ac.nz/entities/publication/43c52ed0-3e7e-4f32-98fa-ccd16580054b",
                       published="2016"),
    "ISSURIN2010": dict(title="Issurin: New horizons for the methodology and physiology of training periodization, Sports Med 40(3):189-206",
                        publisher="Springer (Adis)", url="https://pubmed.ncbi.nlm.nih.gov/20199119/", published="2010"),
    "BR_HMHO": dict(title="How Much How Often (rower development levels: sessions per week, session length, hours)",
                    publisher="British Rowing", url="https://www.britishrowing.org/wp-content/uploads/2019/03/How-Much-How-Often-210219.pdf",
                    published="2019-02-21"),
}


def src(*keys):
    return [dict(S[k], zotero=None) for k in keys]


def T(de, en):
    return {"de": de, "en": en}


LEVEL = {"E": T("Einsteiger", "Beginner"), "F": T("Fortgeschritten", "Advanced"), "L": T("Leistung", "Performance")}

# häufige Notizen
N_TEST2K = ("Test: das Ergebnis setzt die Tempoziele für die nächsten Wochen.", "Test: the result sets your pace targets for the coming weeks.")
N_BASE = ("Startwert: gleichmässig rudern, nicht zu schnell anfangen.", "Baseline: row evenly, don't start too fast.")
N_LONG = ("Lange Fahrt der Woche: ruhig, Gesprächstempo.", "Long row of the week: calm, conversational pace.")
N_OPT = ("Freiwillig: nur wenn du dich frisch fühlst.", "Optional: only if you feel fresh.")
N_TAPER = ("Kurz und locker mit ein paar Schlägen im Renntempo, 1–2 Tage vor dem Test.", "Short and easy with a few strokes at race pace, 1–2 days before the test.")
N_RACE = ("Vor dem Test: festes Einrudern.", "Before the test: fixed warm-up routine.")


def o(pid, note=None):
    """optionale Einheit"""
    d = {"opt": True}
    n = note or N_OPT
    d["de"], d["en"] = n
    return (pid, d)


def n(pid, note):
    return (pid, {"de": note[0], "en": note[1]})


def ev(pid, note):
    """Zieleinheit (Test oder Rennen, auf das der Plan hinführt)"""
    return (pid, {"de": note[0], "en": note[1], "event": True})


def build_weeks(spec):
    weeks = []
    for i, (fde, fen, flags, sess) in enumerate(spec, 1):
        out = []
        for slot, s in enumerate(sess, 1):
            if isinstance(s, str):
                pid, meta = s, {}
            else:
                pid, meta = s
            assert pid in PROGS, pid
            e = {"slot": slot, "planId": pid, "optional": bool(meta.get("opt")), "intensity": intensity(pid)}
            if "de" in meta:
                e["note"] = T(meta["de"], meta["en"])
            if meta.get("event"):
                e["event"] = True
            out.append(e)
        w = {"week": i, "focus": T(fde, fen), "deload": "D" in flags, "sessions": out}
        if "T" in flags:
            w["taper"] = True
        weeks.append(w)
    return weeks


def minutes(pid):
    return sum(ph.get("durationS", ph.get("distanceM", 0) * 120 / 500) for ph in PROGS[pid]["phases"]) / 60


def plan(pid, name, summary, goal, level, category, spw, season, prereq, rules, spec, sources, evidence):
    weeks = build_weeks(spec)
    req = [sum(minutes(s["planId"]) for s in w["sessions"] if not s["optional"]) for w in weeks]
    full = [sum(minutes(s["planId"]) for s in w["sessions"]) for w in weeks]
    normal = [m for m, w in zip(req, weeks) if not w["deload"] and not w.get("taper")] or req
    mpw = {"min": int(5 * (min(req) // 5)), "max": int(5 * -(-max(full) // 5))}
    r = {"deloadEvery": None, "maxConsecutiveDays": 2, "hardSessionsMinGapHours": 48,
         "missedSessionPolicy": "shift", "retestWeek": None}
    r.update(rules)
    return {"id": pid, "name": T(*name), "summary": T(*summary), "goal": T(*goal), "level": LEVEL[level],
            "category": category, "weeks": len(weeks), "sessionsPerWeek": {"min": spw[0], "max": spw[1]},
            "minutesPerWeek": mpw, "season": season, "prerequisites": T(*prereq), "rules": r,
            "weeks_detail": weeks, "sources": sources, "evidence": evidence}


P = []

# 1 ------------------------------------------------------------- Einstieg 4 Wochen
P.append(plan(
    "einstieg-4-wochen",
    ("Einstieg in 4 Wochen", "Getting started in 4 weeks"),
    ("Drei kurze Einheiten pro Woche: Gerät und Technik kennenlernen, dann Schritt für Schritt länger rudern, bis 30 Minuten locker gehen.",
     "Three short sessions a week: get to know the rower and the technique, then row a little longer each week until 30 easy minutes feel fine."),
    ("30 Minuten am Stück locker rudern und eine erste Referenz (10-Minuten-Test) haben.",
     "Row 30 minutes continuously at an easy pace and set a first benchmark (10-minute test)."),
    "E", "einstieg", (3, 3), None,
    ("Keine. Gesund und ohne Beschwerden; wer lange nicht trainiert hat oder Vorerkrankungen hat, klärt das vorher ärztlich ab.",
     "None. Healthy and pain-free; if you haven't exercised for a long time or have a medical condition, check with a doctor first."),
    {"maxConsecutiveDays": 1, "missedSessionPolicy": "shift", "repeatWeekIfMissed": 2},
    [
        ("Gerät kennenlernen: kurze Stücke, Ablauf Beine–Rücken–Arme", "Get to know the rower: short pieces, sequence legs–body–arms", "",
         ["einsteiger-5x1-2x5", "einsteiger-90-30", "technik-locker-25"]),
        ("Etwas länger, ruhiger Rhythmus", "A little longer, calm rhythm", "",
         ["einsteiger-90-30", "technik-pausendrill", "grundlage-ut2-20"]),
        ("Erste zügigere Minuten, 30 Minuten locker", "First brisker minutes, 30 easy minutes", "",
         ["grundlage-locker-30", "schwelle-einsteiger-3x5", "technik-schlagzahl-zehner"]),
        ("5000 m locker und erste Referenz", "5000 m easy and a first benchmark", "",
         ["frequenzleiter-18-24", "grundlage-5000m-ut2",
          ev("einsteiger-test-10min", ("Erste Referenz: die Strecke ist dein Startwert für später.", "First benchmark: the distance is your starting value for later."))]),
    ],
    src("C2_C2C", "BR_BEG", "NHS_C25K", "ACSM", "BR_HMHO"),
    "angepasst: Ablauf nach Concept2 Couch to Consistency (Woche 1: 13 min, 15 min am Stück; Woche 3: 4000 m) und British Rowing Go Row Beginner (kurze Stücke, Schlagzahl 18–24); Ruhetag zwischen den Einheiten und Woche wiederholen nach NHS Couch to 5K; erste Einheit wie British Rowing Woche 1 (5 × 1 min und 2 × 5 min locker, Programm einsteiger-5x1-2x5); übrige Einheiten auf vorhandene Programme abgebildet.",
))

# 2 ------------------------------------------------------------- Einstieg 8 Wochen bis 5000 m
P.append(plan(
    "einstieg-8-wochen-5000m",
    ("In 8 Wochen zu 5000 m am Stück", "5000 m continuous in 8 weeks"),
    ("Aufbau von kurzen Stücken bis zu 5000 m ohne Pause; ab Woche 3 eine zügigere Einheit pro Woche, ab Woche 6 kurze harte Stücke.",
     "Build up from short pieces to 5000 m without stopping; from week 3 one brisker session a week, from week 6 short hard pieces."),
    ("5000 m am Stück in gleichmässigem Tempo rudern.", "Row 5000 m continuously at an even pace."),
    "E", "einstieg", (3, 4), None,
    ("Keine; ideal nach „Einstieg in 4 Wochen“, aber auch direkt möglich.", "None; ideal after “Getting started in 4 weeks”, but you can start here too."),
    {"deloadEvery": 4, "maxConsecutiveDays": 1, "missedSessionPolicy": "shift", "repeatWeekIfMissed": 2, "retestWeek": 8},
    [
        ("Gerät und Technik kennenlernen", "Get to know the rower and the technique", "",
         ["einsteiger-5x1-2x5", "einsteiger-90-30", "technik-locker-25"]),
        ("Länger rudern, ruhiger Rhythmus", "Row longer, calm rhythm", "",
         ["einsteiger-90-30", "technik-pausendrill", "grundlage-ut2-20"]),
        ("Erste zügigere Blöcke", "First brisker blocks", "",
         ["grundlage-locker-30", "schwelle-einsteiger-3x5", "grundlage-ut2-20", o("technik-pick-drill")]),
        ("Leichtere Woche: festigen", "Lighter week: consolidate", "D",
         ["regeneration-20", "einsteiger-1-2-3-2-1", "technik-locker-25"]),
        ("Länger im Gesprächstempo", "Longer at conversational pace", "",
         ["grundlage-locker-30", "schwelle-einsteiger-3x5", "grundlage-3x10-r20", o("technik-schlagzahl-zehner")]),
        ("Erste harte Minuten", "First hard minutes", "",
         ["intervalle-einsteiger-6x1", "grundlage-locker-30", "schwelle-2x10", o("technik-ratio-1-3")]),
        ("40 Minuten mit tiefer Schlagzahl", "40 minutes at a low stroke rate", "",
         ["grundlage-3x10-r20", "intervalle-einsteiger-5x500", "grundlage-rate-cap-r18", o("frequenzleiter-18-24")]),
        ("Ziel: 5000 m am Stück", "Goal: 5000 m continuous", "",
         ["frequenzleiter-18-24", "schwelle-einsteiger-3x1500",
          ev("grundlage-5000m-ut2", ("Ziel der 8 Wochen: 5000 m ohne Pause, gleichmässig.", "Goal of the 8 weeks: 5000 m without stopping, evenly.")),
          o("regeneration-20")]),
    ],
    src("C2_C2C", "BR_BEG", "NHS_C25K", "ACSM", "SEILER2009"),
    "angepasst: Progression nach Concept2 Couch to Consistency (2000 m → 4000 m in Woche 3 → 5000 m in Woche 6) und British Rowing Go Row Beginner (8 Wochen, harte 1-Minuten-Stücke ab Woche 6, Ziel 2000 m); 9-Wochen-Logik und „Woche wiederholen ist in Ordnung“ aus NHS Couch to 5K; erste Einheit wie British Rowing Woche 1 (einsteiger-5x1-2x5); leichtere Woche 4 abgeleitet (3:1-Rhythmus, Praxisregel).",
))

# 3 ------------------------------------------------------------- Fitness 3x/Woche
P.append(plan(
    "fitness-3x-12-wochen",
    ("Fitness und Gesundheit: 3-mal pro Woche", "Fitness and health: 3 times a week"),
    ("Pro Woche eine lockere, eine zügige und eine kurze harte Einheit, jede vierte Woche leichter. Nach 12 Wochen läuft der Plan ab Woche 5 weiter.",
     "Each week one easy, one brisk and one short hard session, every fourth week lighter. After 12 weeks the plan continues from week 5."),
    ("Ausdauer verbessern und die Empfehlung von rund 150 Minuten Bewegung pro Woche mit Rudern gut abdecken.",
     "Improve endurance and cover a good part of the recommended ~150 minutes of activity a week by rowing."),
    "E", "fitness", (3, 4), None,
    ("30 Minuten locker rudern geht ohne Mühe (z. B. nach einem Einstiegsplan).", "You can row 30 easy minutes comfortably (e.g. after a starter plan)."),
    {"deloadEvery": 4, "missedSessionPolicy": "replace-easy", "retestWeek": 12, "repeatFrom": 5},
    [
        ("Startwert und lockere Grundlage", "Baseline and easy base", "",
         ["grundlage-locker-30", n("einsteiger-test-10min", N_BASE), "grundlage-3x10-r20"]),
        ("Kurze harte Minuten", "Short hard minutes", "",
         ["intervalle-einsteiger-6x1", "grundlage-locker-30", "schwelle-einsteiger-3x5", o("technik-locker-25")]),
        ("Zügige Blöcke", "Brisk blocks", "",
         ["schwelle-2x10", "grundlage-3x10-r20", "intervalle-einsteiger-10-20-30", o("technik-pick-drill")]),
        ("Leichtere Woche", "Lighter week", "D",
         ["technik-locker-25", "schwelle-einsteiger-3x5", "regeneration-20"]),
        ("Etwas länger", "A little longer", "",
         ["intervalle-einsteiger-5x500", "grundlage-rate-cap-r18", "schwelle-30-progressiv", o("technik-ratio-1-3")]),
        ("Mehr Abwechslung", "More variety", "",
         ["grundlage-frequenzwechsel-22-26", "intervalle-einsteiger-10x200", "grundlage-3x10-r20", o("frequenzleiter-18-24")]),
        ("Längste Woche dieses Blocks", "Longest week of this block", "",
         ["schwelle-einsteiger-3x1500", "grundlage-5000m-ut2", "intervalle-einsteiger-pyramide-200-500", o("technik-schlagzahl-zehner")]),
        ("Leichtere Woche", "Lighter week", "D",
         ["grundlage-ut2-20", "technik-locker-25", "regeneration-20"]),
        ("Neuer Block: etwas mehr Druck", "New block: a little more pressure", "",
         ["kurzintervalle-8x2", "grundlage-rate-cap-r18", "schwelle-2x10", o("technik-pausendrill")]),
        ("Länger im Gesprächstempo", "Longer at conversational pace", "",
         ["schwelle-30-progressiv", "grundlage-3x10-r20", "intervalle-einsteiger-6x1", o("technik-locker-25")]),
        ("Höhepunkt des Blocks", "Peak of the block", "",
         ["langintervalle-4x4", "grundlage-locker-45", "schwelle-einsteiger-3x1500", o("frequenzleiter-18-24")]),
        ("Leichter und Vergleich mit Woche 1", "Lighter, and compare with week 1", "D",
         ["technik-locker-25", "grundlage-ut2-20", ev("einsteiger-test-10min", ("Vergleich mit Woche 1: gleiche Einteilung, mehr Meter?", "Compare with week 1: same pacing, more metres?"))]),
    ],
    src("ACSM", "C2_C2C", "BR_BEG", "SEILER2009", "STOGGL2014"),
    "abgeleitet: Umfang aus ACSM 2011 (≥150 min moderat oder ≥75 min intensiv pro Woche, 3–5 Tage); Wochenmuster leicht–zügig–hart nach Concept2 Couch to Consistency „Going Forward“ (mindestens zwei gute harte Reize pro Woche, Intensität variieren), hier bewusst nur ein harter Reiz für Einsteiger; leichtere Woche alle 4 Wochen als Praxisregel.",
))

# 4 ------------------------------------------------------------- Erhaltung 2x/Woche
P.append(plan(
    "erhaltung-2x",
    ("Form halten mit 2 Einheiten", "Keep fit with 2 sessions"),
    ("Für volle Wochen: eine kurze harte und eine längere lockere Einheit. Der Plan läuft ohne Ende weiter.",
     "For busy weeks: one short hard and one longer easy session. The plan runs on with no end date."),
    ("Ausdauer und 2000-m-Form über Wochen mit wenig Zeit halten.", "Hold endurance and 2000 m form through weeks with little time."),
    "F", "erhaltung", (2, 3), None,
    ("Mindestens 8 Wochen regelmässiges Training mit 3 oder mehr Einheiten pro Woche.", "At least 8 weeks of regular training with 3 or more sessions a week."),
    {"missedSessionPolicy": "shift", "retestWeek": 8, "repeatFrom": 1},
    [
        ("Intensität halten", "Keep the intensity", "", ["langintervalle-4x4", "grundlage-3x10-r20", o("technik-locker-25")]),
        ("Intensität halten", "Keep the intensity", "", ["schwelle-4x6", "grundlage-8000m-steady-r22", o("technik-locker-25")]),
        ("Intensität halten", "Keep the intensity", "", ["kurzintervalle-8x2", "grundlage-rate-cap-r18", o("regeneration-20")]),
        ("Intensität halten", "Keep the intensity", "", ["pyramide-1-2-3-4-3-2-1", "grundlage-10000m-ut2", o("technik-locker-25")]),
        ("Intensität halten", "Keep the intensity", "", ["intervalle-40-20", "grundlage-3x10-r20", o("technik-locker-25")]),
        ("Intensität halten", "Keep the intensity", "", ["schwelle-3x10", "grundlage-8000m-steady-r22", o("regeneration-20")]),
        ("Intensität halten", "Keep the intensity", "", ["intervalle-6x500-r1", "grundlage-rate-cap-r18", o("technik-locker-25")]),
        ("Standortbestimmung", "Check where you stand", "",
         [ev("test-2000m", ("Alle 8 Wochen: zeigt, ob die Form hält.", "Every 8 weeks: shows whether your form holds.")), "grundlage-10000m-ut2", o("technik-locker-25")]),
    ],
    src("SPIERING2021", "MUJIKA2000", "SEILER2009"),
    "abgeleitet: Spiering et al. 2021 – Ausdauerleistung blieb bis zu 15 Wochen erhalten mit nur 2 Einheiten pro Woche oder 33–66 % weniger Umfang, solange die Intensität gehalten wurde (Grundlage v. a. Studien von Hickson, nicht an Ruderern); deshalb jede Woche ein harter Reiz.",
))

# 5 ------------------------------------------------------------- Wiedereinstieg 3 Wochen
P.append(plan(
    "wiedereinstieg-3-wochen",
    ("Wiedereinstieg nach einer Pause", "Coming back after a break"),
    ("Drei Wochen zurück in den Rhythmus: erst nur locker, dann eine zügige Einheit, zuletzt wieder ein harter Reiz.",
     "Three weeks back into rhythm: easy only at first, then one brisk session, and finally a hard session again."),
    ("Nach 2–8 Wochen Pause (Ferien, Krankheit, Arbeit) ohne Rückschlag zum alten Plan zurückfinden.",
     "Return to your previous plan after 2–8 weeks off (holidays, illness, work) without a setback."),
    "E", "wiedereinstieg", (3, 3), None,
    ("Frühere Trainingserfahrung. Nach Krankheit erst beschwerdefrei sein; nach Fieber oder Corona länger nur locker.",
     "Previous training experience. After illness, be symptom-free first; after a fever or COVID stay easy for longer."),
    {"maxConsecutiveDays": 2, "missedSessionPolicy": "skip", "retestWeek": None},
    [
        ("Nur locker, Technik auffrischen", "Easy only, refresh technique", "",
         ["grundlage-locker-30", "technik-locker-25", "grundlage-3x10-r20"]),
        ("Eine zügige Einheit", "One brisk session", "",
         ["grundlage-3x10-r20", "schwelle-2x10", "grundlage-5000m-ut2"]),
        ("Erster harter Reiz", "First hard session", "",
         ["kurzintervalle-8x2", "grundlage-locker-30",
          n("schwelle-30-progressiv", ("Danach zurück in den eigentlichen Plan.", "Afterwards, return to your main plan."))]),
    ],
    src("MUJIKA2000", "MUJIKA2001", "PETE", "NHS_C25K"),
    "abgeleitet: Mujika & Padilla 2000/2001 – bei weniger als 4 Wochen ohne Training sinkt die VO2max bei Trainierten rasch, bei kürzlich Trainierten gehen die Zugewinne nach mehr als 4 Wochen weitgehend verloren; Stufung leicht → zügig → hart als Praxisregel; Tempoziele nach Pete-Plan-FAQ um 1 s/500 m pro verpasster Woche senken.",
))

# 6 ------------------------------------------------------------- Grundlage Winter 12 Wochen
P.append(plan(
    "grundlage-winter-12-wochen",
    ("Wintergrundlage 12 Wochen", "Winter base 12 weeks"),
    ("Viel ruhige Grundlage mit tiefer Schlagzahl, eine Schwellen- oder Intervalleinheit pro Woche, jede vierte Woche leichter. Start- und Schlusstest über 5000 m.",
     "Lots of calm base work at low stroke rates, one threshold or interval session a week, every fourth week lighter. 5000 m test at the start and end."),
    ("Die aerobe Grundlage für die Saison aufbauen (rund 80 % locker) und den 5000-m-Wert verbessern.",
     "Build the aerobic base for the season (about 80 % easy) and improve your 5000 m."),
    "F", "grundlage", (3, 4), "winter",
    ("Regelmässig 3 Einheiten pro Woche, 45 Minuten locker am Stück sind kein Problem.", "Regularly 3 sessions a week; 45 easy minutes in one go are no problem."),
    {"deloadEvery": 4, "missedSessionPolicy": "replace-easy", "retestWeek": 12},
    [
        ("Startwert 5000 m", "5000 m baseline", "",
         ["grundlage-3x10-r20", n("test-5000m", N_BASE), "grundlage-rate-cap-r18", o("technik-ratio-1-3")]),
        ("Grundlage mit tiefer Schlagzahl", "Base at low stroke rate", "",
         ["grundlage-8000m-steady-r22", "schwelle-4x6", "grundlage-3x20-r20", o("technik-feet-out")]),
        ("Grundlage verlängern", "Extend the base", "",
         ["grundlage-10000m-ut2", "schwelle-3x10", "grundlage-2x30-r18", o("grundlage-antritte-40")]),
        ("Leichtere Woche", "Lighter week", "D",
         ["grundlage-3x10-r20", "schwelle-2x10", "technik-locker-25"]),
        ("UT1 dazu", "Add UT1", "",
         ["grundlage-ut1-3x15", "grundlage-3x20-r20", "langintervalle-4x4", o("grundlage-8000m-steady-r22")]),
        ("Längere Schwelle", "Longer threshold", "",
         ["grundlage-2x30-r18", "schwelle-2x15", "grundlage-10000m-ut2", o("technik-ratio-1-3")]),
        ("Höchster Umfang im Block", "Highest volume of the block", "",
         [n("langdistanz-60min", N_LONG), "schwelle-frequenzstufen-3x9", "grundlage-3x20-r20", o("grundlage-antritte-40")]),
        ("Leichtere Woche", "Lighter week", "D",
         ["grundlage-8000m-steady-r22", "kurzintervalle-8x2", "regeneration-20"]),
        ("Schwelle über Strecke", "Threshold over distance", "",
         ["grundlage-3x20-r20", "schwelle-3x2000", "grundlage-2x30-r18", o("technik-feet-out")]),
        ("Progressiv", "Progressive", "",
         ["grundlage-progressiv-4x10", "grundlage-10000m-ut2", "intervalle-6x3", o("grundlage-8000m-steady-r22")]),
        ("Letzte volle Woche", "Last full week", "",
         [n("langdistanz-60min", N_LONG), "schwelle-2x3000", "grundlage-3x20-r20", o("technik-ratio-1-3")]),
        ("Leichter und Schlusstest 5000 m", "Lighter, and final 5000 m test", "D",
         ["grundlage-3x10-r20", "technik-locker-25", ev("test-5000m", ("Schlusstest: Vergleich mit Woche 1.", "Final test: compare with week 1."))]),
    ],
    src("SEILER2009", "FISK2004", "GUELLICH2009", "WOLFSON", "C2_5K", "ISSURIN2010"),
    "angepasst: Intensitätsverteilung nach Seiler & Tønnessen 2009 und Fiskerstrand & Seiler 2004 (≥75–80 % deutlich unter der Schwelle, im Winter mehr Grundlage); Grundlage bei Schlagzahl 18–20 in 20–30-Minuten-Blöcken nach Wolfson-Leitfaden; Start- und Schlusstest 5000 m wie im Concept2-5k-Plan; 3+1-Wochen-Blöcke als Praxisregel.",
))

# 7 ------------------------------------------------------------- 2k Einsteiger 8 Wochen
P.append(plan(
    "test-2000m-8-wochen-einsteiger",
    ("Erster 2000-m-Test in 8 Wochen", "First 2000 m test in 8 weeks"),
    ("Drei Einheiten pro Woche mit kurzen Intervallen im späteren 2000-m-Tempo, ruhiger Grundlage und einer leichteren Woche; am Ende der erste 2000-m-Test.",
     "Three sessions a week with short intervals at your future 2000 m pace, calm base work and one lighter week; ending with your first 2000 m test."),
    ("Einen 2000-m-Test gut eingeteilt fahren und eine erste Bestzeit setzen.", "Row a well-paced 2000 m test and set your first best time."),
    "E", "test-2k", (3, 4), None,
    ("5000 m locker am Stück (z. B. nach „In 8 Wochen zu 5000 m am Stück“).", "5000 m easy and continuous (e.g. after “5000 m continuous in 8 weeks”)."),
    {"deloadEvery": 4, "missedSessionPolicy": "replace-easy", "retestWeek": 8},
    [
        ("Startwert 1000 m", "1000 m baseline", "",
         ["grundlage-locker-30", n("test-1000m", N_BASE), "grundlage-3x10-r20"]),
        ("Tempo kennenlernen", "Get to know the pace", "",
         ["intervalle-einsteiger-5x500", "grundlage-locker-30", "schwelle-einsteiger-3x5", o("technik-locker-25")]),
        ("Mehr Arbeit im Tempo", "More work at pace", "",
         ["intervalle-einsteiger-6x1", "grundlage-3x10-r20", "schwelle-2x10", o("technik-pick-drill")]),
        ("Leichtere Woche", "Lighter week", "D",
         ["intervalle-einsteiger-6x1", "regeneration-20", "technik-locker-25"]),
        ("Längere Intervalle", "Longer intervals", "",
         ["kurzintervalle-8x2", "grundlage-5000m-ut2", "schwelle-einsteiger-3x1500", o("frequenzleiter-18-24")]),
        ("2000-m-Tempo üben", "Practise 2000 m pace", "",
         ["langintervalle-4x4", "grundlage-3x10-r20", "intervalle-einsteiger-pyramide-200-500", o("technik-ratio-1-3")]),
        ("Rennplan üben", "Practise the race plan", "",
         ["renntempo-4x500-2000m", "grundlage-rate-cap-r18", "schwelle-2x10", o("technik-locker-25")]),
        ("Weniger Umfang, dann Test", "Less volume, then the test", "T",
         ["intervalle-einsteiger-10x200", n("tapering-vor-test", N_TAPER), ev("test-2000m", N_TEST2K)]),
    ],
    src("BR_BEG", "C2_2K4", "C2_2K12", "BOSQUET2007", "C2_C2C"),
    "angepasst: Inhalte aus Concept2 2k-Plan (4×4 min, 6–8×2 min, 4–6×500 m, Schlagzahl 24–34) für Einsteiger gekürzt; Aufbau und Zielsetzung „2000 m sicher rudern“ nach British Rowing Go Row Beginner; Testwoche mit weniger Umfang nach Bosquet 2007 (verkürzt auf eine Woche).",
))

# 8 ------------------------------------------------------------- 2k Fortgeschritten 8 Wochen
P.append(plan(
    "test-2000m-8-wochen-fortgeschritten",
    ("2000 m schneller in 8 Wochen", "Faster 2000 m in 8 weeks"),
    ("Zwei harte Einheiten pro Woche (Langintervalle, 500er, 1000er) und lockere Grundlage dazwischen; leichtere Woche 4, Test in Woche 8.",
     "Two hard sessions a week (long intervals, 500s, 1000s) with easy base in between; lighter week 4, test in week 8."),
    ("Die eigene 2000-m-Bestzeit verbessern.", "Improve your 2000 m best time."),
    "F", "test-2k", (3, 4), None,
    ("Ein 2000-m-Ergebnis der letzten 3 Monate und regelmässig 3 Einheiten pro Woche.", "A 2000 m result from the last 3 months and regularly 3 sessions a week."),
    {"deloadEvery": 4, "missedSessionPolicy": "replace-easy", "retestWeek": 8},
    [
        ("Arbeit im 2000-m-Tempo", "Work at 2000 m pace", "",
         ["langintervalle-4x4", "grundlage-8000m-steady-r22", "kurzintervalle-8x2", o("grundlage-3x10-r20")]),
        ("Mehr Wiederholungen", "More repetitions", "",
         ["intervalle-6x500-r1", "grundlage-3x20-r20", "schwelle-4x6", o("technik-locker-25")]),
        ("Längere Stücke", "Longer pieces", "",
         ["intervalle-3x1000-r3", "grundlage-10000m-ut2", "intervalle-6x3", o("grundlage-8000m-steady-r22")]),
        ("Leichtere Woche", "Lighter week", "D",
         ["kurzintervalle-8x2", "grundlage-locker-30", "technik-locker-25"]),
        ("Renntempo", "Race pace", "",
         ["renntempo-2x1000", "grundlage-8000m-steady-r22", "pyramide-1-2-3-4-3-2-1", o("grundlage-3x10-r20")]),
        ("Renntempo und Schwelle", "Race pace and threshold", "",
         ["intervalle-6x750", "grundlage-3x20-r20", "schwelle-3x2000", o("technik-locker-25")]),
        ("Rennplan üben", "Practise the race plan", "",
         ["renntempo-4x500-2000m", "grundlage-10000m-ut2", "intervalle-6x500-r1", o("grundlage-3x10-r20")]),
        ("Weniger Umfang, dann Test", "Less volume, then the test", "T",
         ["langintervalle-4x4", "grundlage-ut2-20", n("tapering-vor-test", N_TAPER), ev("test-2000m", N_TEST2K)]),
    ],
    src("C2_2K4", "C2_2K12", "WOLFSON", "BOSQUET2007", "SEILER2009"),
    "angepasst: Concept2 2k-Pläne (4×4 min/2 min, 6–8×2 min, 6×500 m/2 min, 3×1000 m/3 min, Grundlage 3000–8000 m; 3 Einheiten plus freiwillige vierte) auf 8 Wochen gestreckt; Testwoche mit reduziertem Umfang bei gleicher Intensität nach Bosquet 2007.",
))

# 9 ------------------------------------------------------------- 2k Fortgeschritten 12 Wochen
P.append(plan(
    "test-2000m-12-wochen-fortgeschritten",
    ("2000 m in 12 Wochen", "2000 m in 12 weeks"),
    ("Drei Blöcke: erst Grundlage und Schwelle, dann längere Intervalle, zuletzt Renntempo. Zwischentest in Woche 6, zwei Wochen Tapering vor dem Schlusstest.",
     "Three blocks: base and threshold first, then longer intervals, finally race pace. Interim test in week 6, two weeks of tapering before the final test."),
    ("Die 2000-m-Bestzeit deutlich verbessern.", "Clearly improve your 2000 m best time."),
    "F", "test-2k", (3, 4), None,
    ("Ein 2000-m-Ergebnis und mindestens 8 Wochen regelmässiges Training.", "A 2000 m result and at least 8 weeks of regular training."),
    {"deloadEvery": 4, "missedSessionPolicy": "replace-easy", "retestWeek": 12, "interimTestWeek": 6},
    [
        ("Grundlage und Schwelle", "Base and threshold", "",
         ["schwelle-4x6", "grundlage-8000m-steady-r22", "kurzintervalle-8x2", o("grundlage-3x10-r20")]),
        ("Grundlage und Schwelle", "Base and threshold", "",
         ["langintervalle-4x4", "grundlage-3x20-r20", "schwelle-3x10", o("technik-locker-25")]),
        ("Mehr Arbeitszeit", "More work time", "",
         ["intervalle-6x3", "grundlage-10000m-ut2", "schwelle-2x15", o("grundlage-8000m-steady-r22")]),
        ("Leichtere Woche", "Lighter week", "D",
         ["kurzintervalle-8x2", "grundlage-3x10-r20", "technik-locker-25"]),
        ("Längere Intervalle", "Longer intervals", "",
         ["intervalle-4x8", "grundlage-3x20-r20", "intervalle-12x1", o("grundlage-3x10-r20")]),
        ("Zwischentest", "Interim test", "",
         ["kurzintervalle-8x2", "grundlage-8000m-steady-r22", n("test-2000m", ("Zwischentest: neue Tempoziele für den zweiten Teil.", "Interim test: new pace targets for the second half.")), o("technik-locker-25")]),
        ("Schwelle über Strecke", "Threshold over distance", "",
         ["schwelle-3x2000", "grundlage-10000m-ut2", "intervalle-3x1000-r3", o("grundlage-8000m-steady-r22")]),
        ("Leichtere Woche", "Lighter week", "D",
         ["langintervalle-4x4", "grundlage-3x10-r20", "regeneration-20"]),
        ("Renntempo", "Race pace", "",
         ["intervalle-6x500-r1", "grundlage-3x20-r20", "schwelle-4x2000-progressiv", o("technik-locker-25")]),
        ("Renntempo", "Race pace", "",
         ["intervalle-6x750", "grundlage-10000m-ut2", "renntempo-2x1000", o("grundlage-3x10-r20")]),
        ("Tapering 1: Umfang runter, Tempo bleibt", "Taper 1: less volume, same intensity", "T",
         ["renntempo-2x1000", "grundlage-3x10-r20", "langintervalle-4x4", o("technik-locker-25")]),
        ("Tapering 2 und Test", "Taper 2 and test", "T",
         ["renntempo-4x500-2000m", "regeneration-20", n("tapering-vor-test", N_TAPER), ev("test-2000m", N_TEST2K)]),
    ],
    src("C2_2K12", "BOSQUET2007", "ISSURIN2010", "SEILER2009", "WOLFSON"),
    "angepasst: Intervallformen aus dem Concept2 12-Wochen-2k-Plan (4×4, 5–6×4, 6–10×2, 12×1, 6×3, 3–4×6, 4×5 min); Abfolge Grundlage → Intervalle → Renntempo als Blockfolge nach Issurin 2010 (Akkumulation, Transmutation, Realisation); zwei Wochen Tapering mit 40–60 % weniger Umfang bei gleicher Intensität und Häufigkeit nach Bosquet 2007.",
))

# 10 ------------------------------------------------------------ 2k Leistung 12 Wochen
P.append(plan(
    "test-2000m-12-wochen-leistung",
    ("2000 m Leistung 12 Wochen", "2000 m performance 12 weeks"),
    ("Fünf Einheiten pro Woche mit den Pete-Plan-Klassikern (8×500 m, Pyramide, 4×1000 m, 5×1500 m, 4×2000 m), viel Grundlage dazwischen und zwei Wochen Tapering.",
     "Five sessions a week with the Pete Plan classics (8×500 m, pyramid, 4×1000 m, 5×1500 m, 4×2000 m), plenty of base in between and two weeks of tapering."),
    ("Neue 2000-m-Bestzeit auf hohem Niveau.", "A new 2000 m best time at a high level."),
    "L", "test-2k", (4, 5), None,
    ("Mindestens 6 Monate strukturiertes Training mit 4 oder mehr Einheiten pro Woche, aktuelles 2000-m-Ergebnis.", "At least 6 months of structured training with 4 or more sessions a week and a recent 2000 m result."),
    {"deloadEvery": 4, "missedSessionPolicy": "replace-easy", "retestWeek": 12, "interimTestWeek": 6},
    [
        ("Zyklus A: Tempo und Ausdauer", "Cycle A: speed and endurance", "",
         ["intervalle-8x500-pete", "grundlage-10000m-ut2", "schwelle-5x1500", "grundlage-3x20-r20", o("grundlage-8000m-steady-r22")]),
        ("Zyklus B", "Cycle B", "",
         ["intervalle-pyramide-250-1000", "grundlage-2x30-r18", "schwelle-4x2000", "grundlage-10000m-ut2", o("grundlage-8000m-steady-r22")]),
        ("Zyklus C", "Cycle C", "",
         ["intervalle-4x1000-pete", "grundlage-3x20-r20", "schwelle-3000-2500-2000", "langdistanz-60min", o("grundlage-8000m-steady-r22")]),
        ("Leichtere Woche", "Lighter week", "D",
         ["langintervalle-4x4", "grundlage-3x10-r20", "schwelle-4x6", "technik-locker-25"]),
        ("Zyklus A, schneller als vor 4 Wochen", "Cycle A, faster than 4 weeks ago", "",
         ["intervalle-8x500-pete", "grundlage-2x30-r18", "schwelle-5x1500", "grundlage-10000m-ut2", o("grundlage-8000m-steady-r22")]),
        ("Zwischentest", "Interim test", "",
         ["intervalle-pyramide-250-1000", "grundlage-3x20-r20", "grundlage-8000m-steady-r22", n("test-2000m", ("Zwischentest: neue Tempoziele.", "Interim test: new pace targets.")), o("grundlage-3x10-r20")]),
        ("Zyklus C", "Cycle C", "",
         ["intervalle-4x1000-pete", "grundlage-10000m-ut2", "schwelle-3000-2500-2000", "langdistanz-60min", o("grundlage-8000m-steady-r22")]),
        ("Leichtere Woche", "Lighter week", "D",
         ["kurzintervalle-8x2", "grundlage-3x10-r20", "schwelle-3x10", "regeneration-20"]),
        ("Renntempo", "Race pace", "",
         ["intervalle-6x500-r1", "grundlage-2x30-r18", "schwelle-4x2000", "grundlage-10000m-ut2", o("grundlage-3x10-r20")]),
        ("Renntempo", "Race pace", "",
         ["rennvorbereitung-3x-start-1000", "grundlage-3x20-r20", "intervalle-6x750", "grundlage-10000m-ut2", o("grundlage-8000m-steady-r22")]),
        ("Tapering 1", "Taper 1", "T",
         ["renntempo-2x1000", "grundlage-locker-30", "renntempo-4x500-2000m", "grundlage-3x10-r20"]),
        ("Tapering 2 und Test", "Taper 2 and test", "T",
         ["intervalle-einsteiger-5x500", "grundlage-ut2-20", n("tapering-vor-test", N_TAPER), ev("test-2000m", N_TEST2K)]),
    ],
    src("PETE", "C2_2K12", "BOSQUET2007", "SEILER2009", "GUELLICH2009"),
    "angepasst: Intervallsätze und 3-Wochen-Zyklus aus dem Pete Plan (Tempo-Intervalle 8×500/Pyramide/4×1000, Ausdauer-Intervalle 5×1500/4×2000/3k-2,5k-2k, dazu Grundlage 8–15 km bei Schlagzahl 22–25 und ein Ruhetag); Pete Plan hat 6 Einheiten, hier 4+1; leichtere Wochen und Tapering (Bosquet 2007) ergänzt.",
))

# 11 ------------------------------------------------------------ 5k/6k 8 Wochen
P.append(plan(
    "langdistanz-5000m-8-wochen",
    ("5000 m und 6000 m in 8 Wochen", "5000 m and 6000 m in 8 weeks"),
    ("Nach dem Concept2-5k-Plan: eine lange Fahrt, ein Intervall- und ein Schwellentag pro Woche; Test zu Beginn, Zwischentest in Woche 4 und Schlusstest.",
     "Based on the Concept2 5k plan: one long row, one interval day and one threshold day a week; test at the start, interim test in week 4 and final test."),
    ("Die 5000-m-Zeit verbessern (6000 m als Alternative für den Schlusstest).", "Improve your 5000 m time (6000 m as an alternative for the final test)."),
    "F", "langdistanz", (3, 4), None,
    ("Regelmässig 3 Einheiten pro Woche, 8000 m locker am Stück.", "Regularly 3 sessions a week, 8000 m easy in one go."),
    {"deloadEvery": 4, "missedSessionPolicy": "replace-easy", "retestWeek": 8, "interimTestWeek": 4},
    [
        ("Startwert 5000 m", "5000 m baseline", "",
         [n("test-5000m", N_BASE), "grundlage-3x10-r20", "intervalle-12x1", o("grundlage-locker-30")]),
        ("Länger und Intervalle", "Longer, and intervals", "",
         ["grundlage-8000m-steady-r22", "kurzintervalle-8x2", "grundlage-3x10-r20", "schwelle-3x2000"]),
        ("Lange Fahrt 8–10 km", "Long row 8–10 km", "",
         ["grundlage-10000m-ut2", "intervalle-8x500-pete", "grundlage-locker-30", "schwelle-2x3000"]),
        ("Leichtere Woche, Zwischentest", "Lighter week, interim test", "D",
         ["grundlage-3x10-r20", n("test-5000m", ("Zwischentest: Ziel aus dem Schnitt der 2×3000 m.", "Interim test: target from your 2×3000 m average.")), "technik-locker-25"]),
        ("Zweiter Zyklus: jedes Stück schneller", "Second cycle: every piece faster", "",
         ["grundlage-8000m-steady-r22", "intervalle-3x1000-r3", "grundlage-3x10-r20", "schwelle-2x15"]),
        ("Lange Fahrt und Schwelle", "Long row and threshold", "",
         ["grundlage-10000m-ut2", "intervalle-6x3", "grundlage-locker-30", "schwelle-2x5000"]),
        ("Letzte volle Woche", "Last full week", "",
         ["grundlage-3x20-r20", "intervalle-8x500-pete", "grundlage-3x10-r20", "schwelle-6000-negativ"]),
        ("Weniger Umfang, Schlusstest", "Less volume, final test", "T",
         ["schwelle-4x6", "grundlage-locker-30",
          ev("test-5000m", ("Schlusstest 5000 m (oder 6000 m): Rennplan halten, auf dem letzten Kilometer zulegen, wenn es gut geht.", "Final test 5000 m (or 6000 m): hold your race plan, push on the last kilometre if you feel good."))]),
    ],
    src("C2_5K", "SEILER2009", "BOSQUET2007"),
    "angepasst: Concept2-5k-Plan in der 8-Wochen-Fassung (Zyklus 1 + Zyklus 2; je Woche lange Fahrt 5–10 km, Intervalle 15×1 min/5×1000/8×400/8×500, Schwelle 2×2000/2×3000, 5k-Test in Woche 1 und 4, freiwilliger 30-min-Tag; Schlagzahl 24–30); Programme der App statt exakter Distanzen; leichtere Testwoche 4 und Schlusswoche mit weniger Umfang ergänzt.",
))

# 12 ------------------------------------------------------------ Halbmarathon 12 Wochen
P.append(plan(
    "halbmarathon-12-wochen",
    ("Halbmarathon in 12 Wochen", "Half marathon in 12 weeks"),
    ("Vier Einheiten pro Woche: eine wachsende lange Fahrt, ein UT1- oder Schwellentag und lockere Kilometer; Halbmarathontempo ab Woche 8, Tapering in Woche 12.",
     "Four sessions a week: a growing long row, one UT1 or threshold day and easy kilometres; half-marathon pace from week 8, taper in week 12."),
    ("Einen Halbmarathon (21 097 m) gleichmässig zu Ende rudern.", "Row a half marathon (21,097 m) evenly to the finish."),
    "F", "langdistanz", (4, 4), None,
    ("Regelmässig 3–4 Einheiten pro Woche, 10 km locker am Stück, ein 5000-m-Ergebnis für die Tempoziele.", "Regularly 3–4 sessions a week, 10 km easy in one go, a 5000 m result for the pace targets."),
    {"deloadEvery": 4, "missedSessionPolicy": "replace-easy", "retestWeek": None},
    [
        ("Grundlage", "Base", "", ["grundlage-8000m-steady-r22", "grundlage-ut1-3x15", "grundlage-3x10-r20", "grundlage-8000m-steady-r22"]),
        ("Grundlage", "Base", "", ["grundlage-10000m-ut2", "schwelle-4x6", "grundlage-3x10-r20", "grundlage-8000m-steady-r22"]),
        ("Lange Fahrt wächst", "Long row grows", "", [n("grundlage-3x20-r20", N_LONG), "grundlage-ut1-3x15", "grundlage-10000m-ut2", "grundlage-8000m-steady-r22"]),
        ("Leichtere Woche", "Lighter week", "D", ["grundlage-8000m-steady-r22", "schwelle-3x10", "technik-locker-25", "grundlage-3x10-r20"]),
        ("Aerober Aufbau", "Aerobic build", "", [n("grundlage-2x30-r18", N_LONG), "schwelle-2x15", "grundlage-10000m-ut2", "grundlage-8000m-steady-r22"]),
        ("Aerober Aufbau", "Aerobic build", "", [n("grundlage-3x20-r20", N_LONG), "intervalle-wolverine-8x5", "grundlage-10000m-ut2", "schwelle-3x10"]),
        ("Eine Stunde am Stück", "One hour in one go", "", [n("langdistanz-60min", N_LONG), "grundlage-8000m-steady-r22", "schwelle-2x20-r22", "grundlage-10000m-ut2"]),
        ("Leichtere Woche", "Lighter week", "D", ["grundlage-10000m-ut2", "schwelle-3x10", "grundlage-3x10-r20", "regeneration-20"]),
        ("Halbmarathontempo", "Half-marathon pace", "", [n("langdistanz-ut2-90", N_LONG), "langdistanz-hmp-2x20", "grundlage-8000m-steady-r22", "schwelle-2x15"]),
        ("Halbmarathontempo", "Half-marathon pace", "", [n("grundlage-2x30-r18", N_LONG), "langdistanz-hmp-2x20", "grundlage-10000m-ut2", "intervalle-wolverine-8x5"]),
        ("Längste Fahrt", "Longest row", "", [n("langdistanz-ut2-90", ("Längste Fahrt vor dem Ziel: trinken und essen üben.", "Longest row before the goal: practise drinking and eating.")), "langdistanz-hmp-50", "grundlage-8000m-steady-r22", "grundlage-10000m-ut2"]),
        ("Tapering und Halbmarathon", "Taper and half marathon", "T",
         ["grundlage-5000m-ut2", "langdistanz-hmp-2x20", "grundlage-locker-30",
          ev("langdistanz-halbmarathon", ("Ziel: gleichmässig, im Halbmarathontempo (5000-m-Tempo plus 8–12 s/500 m).", "Goal: evenly, at half-marathon pace (5000 m pace plus 8–12 s/500 m)."))]),
    ],
    src("C2_HM", "C2_MAR", "SEILER2009", "BOSQUET2007", "WOLFSON"),
    "angepasst: Concept2-Halbmarathonplan (10 Wochen, 4 Einheiten; lange Fahrt 8 → 16 km, UT1 3×10/3×15/2×30 min, AT 4×8/3×10/3×12/5×8/2×20 min, HMP 2×20 min und 50 min ab Woche 7, Tapering in Woche 10; Tempi relativ zum 5000-m-Tempo: UT2 +18–22 s, UT1 +14–18 s, HMP +8–12 s, AT +6–10 s) um zwei Grundlagenwochen und leichtere Wochen auf 12 Wochen erweitert.",
))

# 13 ------------------------------------------------------------ Marathon 16 Wochen
P.append(plan(
    "marathon-16-wochen",
    ("Marathon in 16 Wochen", "Marathon in 16 weeks"),
    ("Vier Blöcke wie im Concept2-Marathonplan: Grundlage, aerober Aufbau, marathonspezifisch, Tapering. Die lange Fahrt wächst bis 2,5 Stunden (rund 30 km).",
     "Four blocks as in the Concept2 marathon plan: base, aerobic build, marathon-specific, taper. The long row grows to 2.5 hours (about 30 km)."),
    ("Einen Marathon (42 195 m) rudern.", "Row a marathon (42,195 m)."),
    "L", "langdistanz", (4, 4), None,
    ("Halbmarathon schon einmal gerudert oder 90 Minuten locker am Stück; 4 Einheiten pro Woche möglich; ein 5000-m-Ergebnis.", "You have rowed a half marathon or 90 easy minutes in one go; 4 sessions a week possible; a 5000 m result."),
    {"deloadEvery": 4, "missedSessionPolicy": "replace-easy", "retestWeek": None},
    [
        ("Grundlage", "Base", "", [n("grundlage-10000m-ut2", N_LONG), "grundlage-ut1-3x15", "grundlage-8000m-steady-r22", "schwelle-4x6"]),
        ("Grundlage", "Base", "", [n("grundlage-3x20-r20", N_LONG), "schwelle-3x10", "grundlage-10000m-ut2", "grundlage-8000m-steady-r22"]),
        ("Grundlage", "Base", "", [n("grundlage-2x30-r18", N_LONG), "grundlage-ut1-3x15", "grundlage-10000m-ut2", "schwelle-2x15"]),
        ("Leichtere Woche", "Lighter week", "D", ["grundlage-10000m-ut2", "schwelle-3x10", "grundlage-3x10-r20", "technik-locker-25"]),
        ("Aerober Aufbau", "Aerobic build", "", [n("langdistanz-60min", N_LONG), "intervalle-wolverine-8x5", "grundlage-10000m-ut2", "grundlage-3x20-r20"]),
        ("Aerober Aufbau", "Aerobic build", "", [n("langdistanz-ut2-90", N_LONG), "grundlage-2x30-r18", "grundlage-10000m-ut2", "schwelle-2x15"]),
        ("Aerober Aufbau", "Aerobic build", "", [n("langdistanz-ut2-90", N_LONG), "schwelle-2x20-r22", "grundlage-3x20-r20", "grundlage-10000m-ut2"]),
        ("Leichtere Woche", "Lighter week", "D", ["grundlage-3x20-r20", "langdistanz-hmp-2x20", "grundlage-8000m-steady-r22", "regeneration-20"]),
        ("Marathonspezifisch", "Marathon-specific", "", [n("langdistanz-ut2-120", ("Lange Fahrt: Verpflegung üben (essen und trinken alle 20–30 Minuten).", "Long row: practise fuelling (eat and drink every 20–30 minutes).")), "schwelle-2x15", "grundlage-10000m-ut2", "grundlage-3x20-r20"]),
        ("Marathontempo", "Marathon pace", "", [n("langdistanz-halbmarathon", N_LONG), "langdistanz-mp-3x25", "grundlage-10000m-ut2", "grundlage-8000m-steady-r22"]),
        ("Marathonspezifisch", "Marathon-specific", "", [n("langdistanz-ut2-150", ("Lange Fahrt: Verpflegung üben (essen und trinken alle 20–30 Minuten).", "Long row: practise fuelling (eat and drink every 20–30 minutes).")), "schwelle-2x20-r22", "grundlage-2x30-r18", "grundlage-10000m-ut2"]),
        ("Höchster Umfang", "Highest volume", "",
         [n("langdistanz-ut2-150", ("Längste Fahrt: Verpflegung wie am Marathontag (essen und trinken alle 20–30 Minuten).", "Longest row: fuel as on marathon day (eat and drink every 20–30 minutes).")), "langdistanz-hmp-50", "grundlage-3x20-r20", "grundlage-10000m-ut2"]),
        ("Tapering 1", "Taper 1", "T", [n("langdistanz-ut2-120", N_LONG), "schwelle-3x10", "grundlage-10000m-ut2", "grundlage-3x10-r20"]),
        ("Tapering 2", "Taper 2", "T", [n("grundlage-3x20-r20", N_LONG), "langdistanz-hmp-2x20", "grundlage-8000m-steady-r22", "grundlage-locker-30"]),
        ("Tapering 3", "Taper 3", "T", ["grundlage-10000m-ut2", "schwelle-4x6", "grundlage-locker-30", "grundlage-5000m-ut2"]),
        ("Marathonwoche", "Marathon week", "T",
         ["grundlage-locker-30", "schwelle-einsteiger-3x5", "regeneration-20",
          ev("langdistanz-marathon", ("Ziel: Marathon im Marathontempo (5000-m-Tempo plus 10–14 s/500 m), Verpflegung wie geübt.", "Goal: marathon at marathon pace (5000 m pace plus 10–14 s/500 m), fuel as practised."))]),
    ],
    src("C2_MAR", "SEILER2009", "BOSQUET2007", "WOLFSON"),
    "angepasst: Blockstruktur und Wochenmuster des Concept2-Marathonplans (16 Wochen, 4 Einheiten; lange UT2-Fahrt 12 → 34 km bis Woche 12, MP 3×25 und 50 min, Tapering ab Woche 13). Lange Fahrten ab Woche 9 mit den Programmen langdistanz-ut2-120 (2 h, rund 24–26 km) und langdistanz-ut2-150 (2,5 h, rund 30–32 km), 50 min im Renntempo in Woche 12 (langdistanz-hmp-50). Abweichung: längste Fahrt rund 30–32 km statt 34 km; Tapering auf vier Wochen wie im Original.",
))

# 14 ------------------------------------------------------------ Masters 50+ 12 Wochen
P.append(plan(
    "masters-50plus-12-wochen",
    ("Masters 50+: 12 Wochen", "Masters 50+: 12 weeks"),
    ("Drei Einheiten pro Woche mit einer harten, einer zügigen und einer lockeren Einheit, mehr Erholung zwischen harten Tagen und jede dritte Woche leichter.",
     "Three sessions a week with one hard, one brisk and one easy session, more recovery between hard days and every third week lighter."),
    ("Ausdauer und 2000-m-Form verbessern, ohne die Erholung zu überfordern.", "Improve endurance and 2000 m form without overloading recovery."),
    "F", "masters", (3, 4), None,
    ("Regelmässiges Training seit mindestens 3 Monaten; bei Herz-Kreislauf-Risiken ärztliche Abklärung.", "Regular training for at least 3 months; medical check if you have cardiovascular risk factors."),
    {"deloadEvery": 3, "hardSessionsMinGapHours": 72, "maxConsecutiveDays": 2, "missedSessionPolicy": "skip", "retestWeek": 12},
    [
        ("Startwert und Technik", "Baseline and technique", "", ["grundlage-3x10-r20", n("test-1000m", N_BASE), "technik-ratio-1-3"]),
        ("Zügig und locker", "Brisk and easy", "", ["schwelle-4x6", "grundlage-rate-cap-r18", "technik-pick-drill", o("regeneration-20")]),
        ("Leichtere Woche", "Lighter week", "D", ["grundlage-ut2-20", "frequenzleiter-18-24", "technik-locker-25"]),
        ("Kurze harte Stücke", "Short hard pieces", "", ["kurzintervalle-8x2", "grundlage-3x10-r20", "schwelle-2x10", o("technik-locker-25")]),
        ("Länger locker", "Longer easy", "", ["langintervalle-4x4", "grundlage-8000m-steady-r22", "schwelle-30-progressiv", o("regeneration-20")]),
        ("Leichtere Woche", "Lighter week", "D", ["grundlage-ut2-20", "schwelle-einsteiger-3x5", "technik-locker-25"]),
        ("Kraft bei tiefer Schlagzahl", "Power at low stroke rate", "", ["intervalle-kraft-10x1-r20", "grundlage-rate-cap-r18", "schwelle-2x10", o("technik-ratio-1-3")]),
        ("Schwelle", "Threshold", "", ["pyramide-1-2-3-4-3-2-1", "grundlage-locker-45", "schwelle-30-progressiv", o("regeneration-20")]),
        ("Leichtere Woche", "Lighter week", "D", ["grundlage-locker-30", "frequenzleiter-18-24", "technik-locker-25"]),
        ("Renntempo kennenlernen", "Get to know race pace", "", ["intervalle-6x500-r1", "grundlage-10000m-ut2", "schwelle-einsteiger-3x1500", o("technik-locker-25")]),
        ("Letzte volle Woche", "Last full week", "", ["langintervalle-4x4", "grundlage-3x20-r20", "schwelle-6000-negativ", o("regeneration-20")]),
        ("Leichter und Vergleich mit Woche 1", "Lighter, and compare with week 1", "D",
         ["grundlage-ut2-20", "technik-locker-25", ev("test-1000m", ("Vergleich mit Woche 1.", "Compare with week 1."))]),
    ],
    src("FELL2008", "BORGES2016", "BR_HMHO", "SEILER2009", "ACSM"),
    "abgeleitet: Fell & Williams 2008 und Borges et al. 2016 – Erholung im Alter möglicherweise langsamer, der Effekt ist aber kleiner als oft angenommen und hängt stark vom Aktivitätsniveau ab; daher nur ein harter Reiz pro Woche, 72 h zwischen harten Einheiten und leichtere Woche alle 3 Wochen (Praxisregel, nicht direkt belegt); Technik und tiefe Schlagzahl nach British Rowing (Qualität vor Umfang, Verletzungsrisiko bei Ermüdung).",
))

# 15 ------------------------------------------------------------ Polarisiert 80/20 10 Wochen
P.append(plan(
    "polarisiert-80-20-10-wochen",
    ("Polarisiert 80/20 in 10 Wochen", "Polarised 80/20 in 10 weeks"),
    ("Rund 80 % der Zeit ganz locker, zwei harte Intervalltage pro Woche, kaum etwas dazwischen; 2000-m-Test zu Beginn und am Ende.",
     "About 80 % of the time very easy, two hard interval days a week, little in between; 2000 m test at the start and end."),
    ("VO2max und 2000-m-Leistung mit einem klaren Hart-locker-Muster verbessern.", "Improve VO2max and 2000 m performance with a clear hard–easy pattern."),
    "F", "grundlage", (4, 5), None,
    ("Regelmässig 4 Einheiten pro Woche, 60 Minuten locker am Stück, ein Pulsgurt hilft beim Lockerbleiben.", "Regularly 4 sessions a week, 60 easy minutes in one go; a heart-rate strap helps you keep easy days easy."),
    {"deloadEvery": 4, "missedSessionPolicy": "replace-easy", "retestWeek": 10},
    [
        ("Startwert 2000 m", "2000 m baseline", "",
         [n("test-2000m", N_BASE), "grundlage-3x20-r20", "grundlage-8000m-steady-r22", "langintervalle-4x4", o("grundlage-3x10-r20")]),
        ("Polarisiert", "Polarised", "",
         ["intervalle-4x8", "grundlage-10000m-ut2", "intervalle-30-15", "grundlage-2x30-r18", o("grundlage-3x10-r20")]),
        ("Polarisiert", "Polarised", "",
         ["intervalle-6x3", "grundlage-3x20-r20", "intervalle-4x8", "grundlage-10000m-ut2", o("grundlage-8000m-steady-r22")]),
        ("Leichtere Woche", "Lighter week", "D",
         ["langintervalle-4x4", "grundlage-3x10-r20", "grundlage-8000m-steady-r22", "technik-locker-25"]),
        ("Polarisiert", "Polarised", "",
         ["intervalle-30-15", "grundlage-2x30-r18", "intervalle-4x8", "grundlage-10000m-ut2", o("grundlage-3x10-r20")]),
        ("Polarisiert", "Polarised", "",
         ["intervalle-6x3", "langdistanz-60min", "intervalle-2x10x1", "grundlage-3x20-r20", o("grundlage-8000m-steady-r22")]),
        ("Polarisiert, höchster Umfang", "Polarised, highest volume", "",
         ["intervalle-4x8", "grundlage-2x30-r18", "intervalle-30-15", "langdistanz-60min", o("grundlage-3x10-r20")]),
        ("Leichtere Woche", "Lighter week", "D",
         ["kurzintervalle-8x2", "grundlage-3x10-r20", "grundlage-8000m-steady-r22", "regeneration-20"]),
        ("Polarisiert", "Polarised", "",
         ["intervalle-6x3", "grundlage-3x20-r20", "intervalle-4x8", "grundlage-10000m-ut2", o("grundlage-8000m-steady-r22")]),
        ("Weniger Umfang, Test", "Less volume, test", "T",
         ["langintervalle-4x4", "grundlage-8000m-steady-r22", n("tapering-vor-test", N_TAPER), ev("test-2000m", ("Vergleich mit Woche 1.", "Compare with week 1."))]),
    ],
    src("STOGGL2014", "TREFF2017", "SEILER2009", "SEILER2006", "FISK2004", "GUELLICH2009"),
    "angepasst: Stöggl & Sperlich 2014 (9 Wochen, polarisiert ≈ 80 % locker / ≈ 20 % hart mit grösstem VO2max-Zuwachs, +11,7 %, bei gut trainierten Ausdauersportlern – nicht Ruderern); Intervallformen 4×8 min und 30/15 nach Seiler 2009 bzw. Rønnestad. Einschränkung: Treff et al. 2017 fanden bei nationalen Elite-Ruderern über 11 Wochen keinen Vorteil gegenüber pyramidaler Verteilung (beide ≈ 93 % Zone 1). Der Plan ist sinnvoll, aber kein bewiesener Vorteil für Ruderer.",
))

# 16 ------------------------------------------------------------ Pete-Plan-artig 24 Wochen
pete = []
steady = (["grundlage-5000m-ut2"] * 3 + ["grundlage-rate-cap-r18", "grundlage-6000m-ut2", "grundlage-6000m-ut2"] + ["grundlage-8000m-steady-r22"] * 4
          + ["grundlage-10000m-ut2"] * 6 + ["grundlage-3x20-r20"] * 4 + ["grundlage-12000m-ut2", "grundlage-3x20-r20", "grundlage-12000m-ut2", "grundlage-3x20-r20"])
day2 = {1: "intervalle-einsteiger-5x500", 2: "intervalle-6x750", 3: "schwelle-3x2000", 5: "intervalle-3x1000-r3", 6: "schwelle-3x2000",
        7: "intervalle-6x500-r1", 9: "intervalle-4x1000-pete", 10: "schwelle-3x2000", 11: "intervalle-8x500-pete", 13: "intervalle-4x1000-pete",
        14: "schwelle-4x2000", 15: "intervalle-6x750", 17: "intervalle-8x500-pete", 18: "schwelle-4x2000", 19: "intervalle-pyramide-250-1000",
        21: "intervalle-4x1000-pete", 22: "schwelle-4x2000", 23: "intervalle-8x500-pete"}
day3 = {1: "grundlage-5000m-ut2", 2: "grundlage-5000m-ut2", 3: "grundlage-rate-cap-r18", 5: "grundlage-rate-cap-r18", 6: "grundlage-8000m-steady-r22",
        7: "grundlage-8000m-steady-r22", 9: "grundlage-8000m-steady-r22", 10: "grundlage-8000m-steady-r22", 11: "grundlage-8000m-steady-r22",
        13: "schwelle-2x15", 14: "intervalle-4x8", 15: "schwelle-3x10", 17: "schwelle-2x15", 18: "schwelle-30-r20", 19: "schwelle-3x10",
        21: "intervalle-4x8", 22: "schwelle-30-r20", 23: "schwelle-2x15"}
optA = ["grundlage-locker-30", "grundlage-3x10-r20", "grundlage-5000m-ut2"]
for w in range(1, 25):
    if w in (4, 8, 12, 16, 20):
        pete.append(("Leichtere Woche", "Lighter week", "D",
                     ["kurzintervalle-8x2" if w < 12 else "langintervalle-4x4", "grundlage-ut2-20", "regeneration-20"]))
        continue
    if w == 24:
        pete.append(("Abschluss: 2000-m-Test", "Finish: 2000 m test", "T",
                     ["intervalle-einsteiger-5x500", "grundlage-locker-30", n("tapering-vor-test", N_TAPER), ev("test-2000m", N_TEST2K)]))
        continue
    second_half = w >= 13
    if second_half:
        # Intervall – Grundlage – Tempo-Stück
        s = [n(day2[w], ("Ziel: Schnitt vom letzten Mal halten oder 1–2 s/500 m schneller.", "Target: match last time's average or 1–2 s/500 m faster.")),
             steady[w - 1], day3[w], o(optA[w % 3])]
        focus = ("Zweite Hälfte: zwei Qualitätstage", "Second half: two quality days")
    else:
        s = [steady[w - 1], n(day2[w], ("Ziel: Schnitt vom letzten Mal halten oder 1–2 s/500 m schneller.", "Target: match last time's average or 1–2 s/500 m faster.")),
             day3[w], o(optA[w % 3])]
        focus = ("Grundlage wächst, ein Intervalltag", "Base grows, one interval day")
    pete.append((focus[0], focus[1], "", s))

P.append(plan(
    "pete-artig-24-wochen",
    ("Langer Aufbau 24 Wochen (nach Pete Plan)", "Long build 24 weeks (after the Pete Plan)"),
    ("Drei Kerneinheiten plus eine freiwillige: die Grundlagenfahrt wird Woche für Woche länger, dazu ein Intervalltag, ab Woche 13 ein zweiter Qualitätstag. Ziele kommen immer aus der letzten gleichen Einheit.",
     "Three core sessions plus one optional: the steady row gets longer week by week, plus one interval day, and from week 13 a second quality day. Targets always come from the last identical session."),
    ("Über ein halbes Jahr stetig schneller werden und mit einem 2000-m-Test abschliessen.", "Get steadily faster over half a year and finish with a 2000 m test."),
    "F", "test-2k", (3, 4), None,
    ("5000 m locker am Stück und erste Erfahrung mit Intervallen.", "5000 m easy in one go and some experience with intervals."),
    {"deloadEvery": 4, "missedSessionPolicy": "shift", "retestWeek": 24},
    pete,
    src("PETE_BEG", "PETE", "SEILER2009"),
    "angepasst: eigene Umsetzung nach dem Beginner Pete Plan (24 Wochen, 3 Kern- + 2 freiwillige Einheiten; Grundlage 5000 → 12 000 m, Intervalle 6×500 bis 5×1500/4×2000, ab Woche 12 Zeitstücke 3×10/2×15/4×8/30 min; Ziel = Schnitt der letzten gleichen Einheit, gleich oder 1–2 s schneller). Abweichungen: Distanzen auf vorhandene Programme gerundet (5000/6000/8000/10 000/12 000 m, 40 und 72 min), leichtere Woche alle 4 Wochen und Schlusstest ergänzt (im Original nicht vorgesehen).",
))

# 17 ------------------------------------------------------------ Wettkampf mit Tapering 3 Wochen
P.append(plan(
    "wettkampf-tapering-3-wochen",
    ("Wettkampfvorbereitung mit Tapering", "Race preparation with taper"),
    ("Eine letzte volle Woche mit Renntempo, dann zwei Wochen mit deutlich weniger Umfang bei gleicher Intensität und gleicher Zahl Einheiten; am Ende Rennen oder Test über 2000 m.",
     "One last full week with race pace, then two weeks with clearly less volume at the same intensity and the same number of sessions; ending with a 2000 m race or test."),
    ("Am Wettkampftag (Indoor-Rennen oder 2000-m-Test) frisch und schnell sein.", "Be fresh and fast on race day (indoor race or 2000 m test)."),
    "L", "wettkampf", (4, 4), None,
    ("Mindestens 8 Wochen Training auf das Rennen hin (z. B. ein 2000-m-Plan), aktuelle Tempoziele.", "At least 8 weeks of training for the race (e.g. a 2000 m plan) and current pace targets."),
    {"missedSessionPolicy": "skip", "retestWeek": 3},
    [
        ("Letzte volle Woche", "Last full week", "",
         ["intervalle-6x750", "grundlage-10000m-ut2", "rennsimulation-2000m-taktik", "grundlage-3x20-r20"]),
        ("Tapering: Umfang rund 40 % runter, Tempo bleibt", "Taper: volume down about 40 %, intensity stays", "T",
         ["renntempo-2x1000", "grundlage-locker-30", "renntempo-4x500-2000m", "grundlage-3x10-r20"]),
        ("Rennwoche: Umfang rund 60 % runter", "Race week: volume down about 60 %", "T",
         ["intervalle-einsteiger-5x500", "grundlage-ut2-20", n("tapering-vor-test", N_TAPER),
          ev("test-2000m", ("Rennen oder Test: vorher festes Einrudern (Programm „Einrudern vor dem Rennen“).", "Race or test: fixed warm-up first (program “Pre-race warm-up”)."))]),
    ],
    src("BOSQUET2007", "C2_2K12", "C2_HM"),
    "direkt: Bosquet et al. 2007 (Metaanalyse, 27 Studien) – am wirksamsten ist ein Tapering von rund 2 Wochen mit 41–60 % weniger Umfang, exponentiell abnehmend, ohne Intensität oder Häufigkeit zu senken (Effektstärke 0,72); Inhalte (Renntempo, Rennsimulation) aus den Concept2-Plänen.",
))

def write_plaene_md(data, progs, path, stand="26.11.2026"):
    ilabel = {"easy": "leicht", "moderate": "mittel", "hard": "hart", "max": "maximal"}
    L = ["# Trainingspläne RowCoach: Übersicht", "",
         f"Lesbare Fassung von `App/RowCoach/Resources/training_plans.json` (erzeugt aus den Daten, Stand {stand}). Regeln, Belege und Format: `RECHERCHE.md`.",
         "Legende: Reihenfolge = empfohlene Abfolge in der Woche, *kursiv* = freiwillig, **fett** = Zieleinheit; D = leichtere Woche (Deload), T = Tapering.", "",
         "| id | Ziel | Niveau | Wochen | Einheiten/Woche | Minuten/Woche | Beleg |", "|---|---|---|---|---|---|---|"]
    for p in data["plans"]:
        L.append(f"| `{p['id']}` | {p['goal']['de']} | {p['level']['de']} | {p['weeks']} | {p['sessionsPerWeek']['min']}–{p['sessionsPerWeek']['max']} | "
                 f"{p['minutesPerWeek']['min']}–{p['minutesPerWeek']['max']} | {p['evidence'].split(':')[0]} |")
    for p in data["plans"]:
        rules = ", ".join(f"{k}={v}" for k, v in p["rules"].items() if v is not None)
        quellen = "; ".join(f"[{s['publisher']}: {s['title'][:90]}]({s['url']})" for s in p["sources"])
        L += ["", f"## {p['name']['de']} (`{p['id']}`)", "", p["summary"]["de"], "",
              f"- Ziel: {p['goal']['de']}",
              f"- Niveau: {p['level']['de']}, Kategorie `{p['category']}`" + (", Saison: Winter (Nordhalbkugel Okt.–Apr.)" if p.get("season") == "winter" else ""),
              f"- Voraussetzung: {p['prerequisites']['de']}",
              f"- Regeln: {rules}",
              f"- Beleg: {p['evidence']}",
              f"- Quellen: {quellen}", "",
              "| Woche | Fokus | Einheiten |", "|---|---|---|"]
        for w in p["weeks_detail"]:
            flag = " D" if w.get("deload") else (" T" if w.get("taper") else "")
            parts = []
            for s in w["sessions"]:
                t = f"{progs[s['planId']]['name']['de']} ({ilabel[s['intensity']]})"
                if s.get("event"):
                    t = f"**{t}**"
                elif s.get("optional"):
                    t = f"*{t}*"
                parts.append(t)
            L.append(f"| {w['week']}{flag} | {w['focus']['de']} | {' → '.join(parts)} |")
    path.write_text("\n".join(L) + "\n")


out = {"version": 1, "plans": P}
(REPO / "App/RowCoach/Resources/training_plans.json").write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n")
write_plaene_md(out, PROGS, REPO / "docs/trainingsplaene/PLAENE.md")

for p in P:
    req = []
    for w in p["weeks_detail"]:
        m = sum(minutes(s["planId"]) for s in w["sessions"] if not s["optional"])
        req.append(f'{w["week"]}{"D" if w["deload"] else ""}{"T" if w.get("taper") else ""}:{m:.0f}')
    print(p["id"], p["minutesPerWeek"], " ".join(req))
