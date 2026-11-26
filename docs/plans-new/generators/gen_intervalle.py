#!/usr/bin/env python3
"""Generates docs/plans-new/intervalle.json and intervalle.md (RowCoach, family 'intervalle')."""
import json, sys
from pathlib import Path

ROOT = Path.home() / "Projects/Software/RowCoach/docs/plans-new"

def S(title, publisher, url, published=None):
    return {"title": title, "publisher": publisher, "url": url, "published": published, "zotero": None}

C2_500 = S("Training for a 500m Rowing Ergometer Test", "Concept2", "https://www.concept2.com/training/plans/500m-erg-test")
C2_2K12 = S("Training for a 2K Rowing Ergometer Test - 12 Week Plan", "Concept2", "https://www.concept2.com/training/plans/2k-erg-test-12-week")
C2_2K4 = S("Training for a 2K Rowing Ergometer Test - 4 Week Plan", "Concept2", "https://www.concept2.com/training/plans/2k-erg-test-4-week")
C2_BEST = S("The Best Rowing Machine Workouts", "Concept2", "https://www.concept2.com/blog/the-best-rowing-machine-workouts", "2018-07-02")
C2_2030 = S("20 x 30 Seconds Full Power with a CrossFit Champion", "Concept2", "https://www.concept2.com/blog/20-x-30-seconds-full-power-with-a-crossfit-champion", "2012-06-04")
C2_102030 = S("10-20-30 Training", "Concept2", "https://www.concept2.com/blog/102030-training", "2015-08-28")
C2_GLUCK = S("From the Archives: A Great Workout in 30 Minutes (L. Gluckman, 30 and Out, Concept2 Update, spring 1995)", "Concept2", "https://www.concept2.com/news/archives-great-workout-30-minutes", "2013-12-31")
C2_RATE = S("Rowing Stroke Rate Explained", "Concept2", "https://www.concept2.com/news/rowing-stroke-rate-explained", "2017-12-01")
C2_WOD = S("Workout of the Day (general guidance: intensity, stroke rate, warm-up)", "Concept2", "https://www.concept2.com/training/wod")
C2_START = S("Race starts and changing pace on the indoor rower (read via search excerpt only)", "Concept2 New Zealand", "https://www.concept2.co.nz/Blog/x_post/Race-starts-and-changing-pace-on-the-indoor-rower-00095.html")
C2_HR = S("Heart Rate Training with Your Concept2 Erg", "Concept2", "https://www.concept2.com/blog/heart-rate-training-with-your-concept2-erg", "2025-04-17")
PETE = S("The Pete Plan (author's site, schedule and FAQ pace targets)", "The Pete Plan (Pete Marston)", "https://thepeteplan.wordpress.com/the-pete-plan/")
WOLV = S("Wolverine Plan Discussion (compilation of Mike Caviston's posts); forum, secondary source", "Concept2 Forum", "https://c2forum.com/viewtopic.php?p=100")
WOLF = S("Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary source", "Wolfson College Boat Club, University of Cambridge", "https://www.wolfson.cam.ac.uk/sites/default/files/2019-11/wcbc_erging_0.pdf", "2019")
ACE = S("Reap the Benefits of Rowing With 3 Fast and Efficient Workouts (S. Thielen); fitness association blog, secondary source", "American Council on Exercise (ACE)", "https://www.acefitness.org/education-and-resources/lifestyle/blog/5881/reap-the-benefits-of-rowing-with-3-fast-and-efficient-workouts", "2016-03-28")
TABATA = S("Effects of moderate-intensity endurance and high-intensity intermittent training on anaerobic capacity and VO2max (Tabata et al.), Med Sci Sports Exerc 28(10):1327-30", "Medicine & Science in Sports & Exercise (ACSM)", "https://pubmed.ncbi.nlm.nih.gov/8897392/", "1996-10")
RONN = S("Superior performance improvements in elite cyclists following short-interval vs effort-matched long-interval training (Rønnestad et al.), Scand J Med Sci Sports 30(5):849-857", "Wiley", "https://pubmed.ncbi.nlm.nih.gov/31977120/", "2020-05")
BUCH = S("High-intensity interval training, solutions to the programming puzzle. Part I: cardiopulmonary emphasis (Buchheit & Laursen), Sports Med 43(5):313-38", "Springer", "https://pubmed.ncbi.nlm.nih.gov/23539308/", "2013-05")
GUNN = S("The 10-20-30 training concept improves performance and health profile in moderately trained runners (Gunnarsson & Bangsbo), J Appl Physiol 113(1):16-24", "American Physiological Society", "https://doi.org/10.1152/japplphysiol.00334.2012", "2012-07-01")

LV = {"E": ("Einsteiger", "Beginner"), "F": ("Fortgeschritten", "Advanced"), "L": ("Leistung", "Performance")}
CAT = {"I": ("Intervalle", "Intervals"), "S": ("Sprint", "Sprint")}

def L(de, en): return {"de": de, "en": en}

def ph(kind, de, en, *, t=None, d=None, spm=(16, 20), hr=1, pace=None, active=None):
    p = {"kind": kind}
    if t is not None: p["durationS"] = t
    else: p["distanceM"] = d
    if spm is not None:
        p["spmMin"], p["spmMax"] = spm
    p["hrZone"] = hr
    if pace is not None:
        p["paceOffsetMinS"], p["paceOffsetMaxS"] = pace
    if active is not None: p["activeRest"] = active
    p["label"] = L(de, en)
    return p

def warm(t=600, top=30, de=None, en=None):
    m = t // 60
    return ph("warmup", de or f"Einrudern {m} min: locker, steigernd, am Ende 3 kurze Antritte",
              en or f"Warm-up {m} min: easy, building, finish with 3 short bursts", t=t, spm=(18, top), hr=2)

def cool(t=300):
    return ph("cooldown", "Ausrudern: ganz locker", "Cool-down: very easy", t=t, spm=(16, 20), hr=1)

def rest(t=None, d=None, de="Pause: locker weiterrudern", en="Rest: keep paddling easy", active=True, spm=(16, 20), hr=1):
    if not active:
        de, en = de if de != "Pause: locker weiterrudern" else "Pause: stehen, Griff ablegen, durchatmen", \
                 en if en != "Rest: keep paddling easy" else "Rest: stop, handle down, breathe"
        spm = None
    return ph("rest", de, en, t=t, d=d, spm=spm, hr=hr, active=active)

def reps(n, work_fn, rest_fn=None):
    out = []
    for i in range(1, n + 1):
        out.append(work_fn(i, n))
        if rest_fn and i < n:
            out.append(rest_fn(i, n))
    return out

PLANS = []
MD = {}

def plan(id, name, summary, purpose, lvl, cat, tags, sources, evidence, phases, md_note=""):
    PLANS.append({"id": id, "name": name, "summary": summary, "purpose": purpose,
                  "level": L(*LV[lvl]), "category": L(*CAT[cat]), "tags": tags,
                  "sources": sources, "evidence": evidence, "phases": phases})
    MD[id] = md_note

# ---------------------------------------------------------------- Einsteiger
plan("intervalle-einsteiger-6x1",
     L("Einstieg Intervalle 6 x 1 Minute", "Beginner intervals 6 x 1 minute"),
     L("Sechs Intervalle zu 1 Minute zügig bis hart mit je 1 Minute lockerer Pause. Erste Intervalle kontrolliert, nicht voll.",
       "Six 1-minute pieces, brisk to hard, with 1 minute easy rowing between. Keep the first ones controlled."),
     L("Einstieg in harte Intervalle / VO2max-Reiz mit kleinem Umfang (Puls am Ende ca. 85-90 % HFmax, Pulszone 4)",
       "First step into hard intervals / small VO2max stimulus (heart rate up to about 85-90 % of max, zone 4)"),
     "E", "I", ["hard", "vo2max", "beginner-friendly", "time-efficient"],
     [C2_2K12, BUCH, C2_WOD],
     "angepasst: Concept2 12-Wochen-2k-Plan nennt 12 x 1 min / 1 min Pause; hier auf 6 Wiederholungen halbiert und Tempo gedrosselt (2k +2..+6 s, eigene Eingrenzung)",
     [warm(480, 26)] + reps(6,
        lambda i, n: ph("work", f"Intervall 1 min zügig bis hart ({i}/{n})", f"Interval 1 min brisk to hard ({i}/{n})", t=60, spm=(24, 28), hr=4, pace=(2, 6)),
        lambda i, n: rest(t=60)) + [cool(300)])

plan("intervalle-einsteiger-10x200",
     L("Einstieg 10 x 200 m locker-hart", "Beginner 10 x 200 m easy-hard"),
     L("Zehnmal 200 m zügig bis hart, dazwischen je 1 Minute locker rudern. Gleichmässig, nicht das erste Stück überziehen.",
       "Ten 200 m pieces brisk to hard with 1 minute easy rowing between. Even pacing, don't overdo the first one."),
     L("Tempohärte und Technik bei höherem Tempo, kleiner VO2max-Reiz (Pulszone 4)",
       "Speed endurance and technique at higher pace, small VO2max stimulus (zone 4)"),
     "E", "I", ["hard", "vo2max", "beginner-friendly", "time-efficient"],
     [C2_500, ACE, C2_WOD],
     "angepasst: Concept2 500-m-Plan (kurze Distanzintervalle 250 m mit 1 min Pause, Schlagzahl 26-36) und ACE-Distanzpyramide (200 m mit 1:30 Pause, 24-28 spm); Distanz 200 m, Pause und Tempo (2k +2..+6 s) eigene Eingrenzung",
     [warm(480, 26)] + reps(10,
        lambda i, n: ph("work", f"200 m zügig bis hart ({i}/{n})", f"200 m brisk to hard ({i}/{n})", d=200, spm=(24, 28), hr=4, pace=(2, 6)),
        lambda i, n: rest(t=60)) + [cool(300)])

plan("intervalle-einsteiger-10-20-30",
     L("10-20-30 Intervalle", "10-20-30 intervals"),
     L("Zwei Blöcke zu 5 Minuten: jede Minute 30 s locker, 20 s mittel, 10 s Sprint. Zwischen den Blöcken 2 Minuten stehen.",
       "Two 5-minute blocks: each minute 30 s easy, 20 s moderate, 10 s sprint. Stand for 2 minutes between blocks."),
     L("Kurzer, abwechslungsreicher Intervallreiz für Fitness und Herz-Kreislauf (Puls steigt bis ca. 85-90 % HFmax, Pulszone 3-5)",
       "Short, varied interval stimulus for fitness and cardiovascular health (heart rate rises to about 85-90 % of max, zone 3-5)"),
     "E", "I", ["hard", "vo2max", "fartlek", "beginner-friendly", "time-efficient"],
     [C2_102030, GUNN],
     "direkt: Concept2 '10-20-30 Training' (5 x [30 s locker, 20 s mittel, 10 s Sprint], 2 min Pause stehen/gehen, 2 Blöcke, ca. 12 min); Ursprung Gunnarsson & Bangsbo 2012 (Läufer). Einrudern, Schlagzahl und Pace-Offsets eigene Eingrenzung",
     [warm(480, 24)] + [p for b in (1, 2) for p in (
        sum([[ph("rest", f"30 s locker (Block {b}, {i}/5)", f"30 s easy (block {b}, {i}/5)", t=30, spm=(18, 22), hr=3, active=True),
              ph("work", f"20 s mittel (Block {b}, {i}/5)", f"20 s moderate (block {b}, {i}/5)", t=20, spm=(22, 26), hr=4, pace=(4, 10)),
              ph("work", f"10 s Sprint (Block {b}, {i}/5)", f"10 s sprint (block {b}, {i}/5)", t=10, spm=(28, 34), hr=5, pace=(-10, -4))]
             for i in range(1, 6)], [])
        + ([rest(t=120, active=False, de="Pause 2 min: stehen oder ganz langsam", en="Rest 2 min: stand or move very slowly")] if b == 1 else [])
     )] + [cool(300)])

plan("intervalle-einsteiger-5x500",
     L("Einstieg 5 x 500 m", "Beginner 5 x 500 m"),
     L("Fünfmal 500 m zügig und gleichmässig mit je 2 Minuten lockerer Pause. Alle Stücke im gleichen Tempo.",
       "Five 500 m pieces, brisk and even, with 2 minutes easy rowing between. Same pace on every piece."),
     L("Tempohärte und Pacing-Gefühl, VO2max-Bereich (Pulszone 4-5)",
       "Speed endurance and pacing feel, VO2max range (zone 4-5)"),
     "E", "I", ["hard", "vo2max", "beginner-friendly"],
     [C2_500, C2_WOD],
     "angepasst: Concept2 500-m-Plan (Zyklus 1: 4-5 x 500 m mit 2 min Pause, Schlagzahl 26-36); Tempo für Einsteiger 2k +0..+4 s und Schlagzahl 24-30 eigene Eingrenzung",
     [warm(480, 28)] + reps(5,
        lambda i, n: ph("work", f"500 m zügig und gleichmässig ({i}/{n})", f"500 m brisk and even ({i}/{n})", d=500, spm=(24, 30), hr=4, pace=(0, 4)),
        lambda i, n: rest(t=120)) + [cool(300)])

plan("intervalle-einsteiger-pyramide-200-500",
     L("Einstieg Distanzpyramide 200-500-200 m", "Beginner distance pyramid 200-500-200 m"),
     L("Pyramide 200, 300, 400, 500, 400, 300, 200 m mit lockeren Pausen von 1:30 bis 3:00 Minuten (je länger das Stück, desto länger die Pause).",
       "Pyramid of 200, 300, 400, 500, 400, 300, 200 m with easy rests of 1:30 to 3:00 (longer piece, longer rest)."),
     L("Abwechslungsreiche Intervalle im Bereich Schwelle bis VO2max (Pulszone 4)",
       "Varied intervals between threshold and VO2max (zone 4)"),
     "E", "I", ["hard", "vo2max", "pyramid", "beginner-friendly"],
     [ACE, C2_WOD],
     "direkt: ACE 'Pyramid Workout #1: By Meters' (200/300/400/500/400/300/200 m, Pausen 1:30/2:00/2:30/3:00 locker, 24-28 spm, 5 min Einrudern, 3-5 min Ausrudern); Pace-Offset eigene Eingrenzung (2k +3..+8 s)",
     [warm(420, 26)] + [p for i, (dist, r) in enumerate([(200, 90), (300, 120), (400, 150), (500, 180), (400, 150), (300, 120), (200, None)], 1) for p in
        [ph("work", f"Pyramide {dist} m (Stufe {i}/7)", f"Pyramid {dist} m (step {i}/7)", d=dist, spm=(24, 28), hr=4, pace=(3, 8))]
        + ([rest(t=r, de=f"Pause {r // 60}:{r % 60:02d} min: locker weiterrudern", en=f"Rest {r // 60}:{r % 60:02d} min: keep paddling easy")] if r else [])] + [cool(300)])

plan("sprint-einsteiger-8x20s",
     L("Antritte 8 x 20 Sekunden alle 2 Minuten", "Bursts 8 x 20 seconds every 2 minutes"),
     L("Alle 2 Minuten ein schneller Antritt über 20 Sekunden, dazwischen 1:40 Minuten ganz locker. Schnell, aber sauber rudern.",
       "Every 2 minutes a fast 20-second burst, then 1:40 very easy. Fast but clean strokes."),
     L("Schnelligkeit und Kraft bei voller Erholung, wenig Laktat (Puls bleibt meist unter Zone 5)",
       "Speed and power with full recovery, little lactate (heart rate mostly stays below zone 5)"),
     "E", "S", ["hard", "power", "beginner-friendly", "time-efficient"],
     [C2_GLUCK, BUCH, C2_RATE],
     "abgeleitet: Gluckman (Concept2) nennt 20 x 20 s / 40 s im Tempo 2k -7..-10 s; hier 8 Antritte mit langer Pause (1:5) für Einsteiger; Pausendauer, Schlagzahl (Concept2: 30-36 spm für kurze Stücke) und Pace-Offset eigene Ableitung",
     [warm(480, 28)] + reps(8,
        lambda i, n: ph("work", f"Antritt 20 s schnell ({i}/{n})", f"Burst 20 s fast ({i}/{n})", t=20, spm=(28, 34), hr=4, pace=(-8, -3)),
        lambda i, n: rest(t=100, de="Pause 1:40 min: ganz locker", en="Rest 1:40 min: very easy")) + [cool(300)])

# ---------------------------------------------------------------- Fortgeschritten
plan("intervalle-12x1",
     L("Intervalle 12 x 1 Minute", "Intervals 12 x 1 minute"),
     L("Zwölf Intervalle zu 1 Minute etwas schneller als 2000-m-Tempo mit je 1 Minute lockerer Pause.",
       "Twelve 1-minute pieces slightly faster than 2000 m pace with 1 minute easy rest each."),
     L("VO2max / Sauerstoffaufnahme (Puls gegen Ende 90 % HFmax und mehr, Pulszone 5)",
       "VO2max / oxygen uptake (heart rate 90 % of max and above towards the end, zone 5)"),
     "F", "I", ["hard", "vo2max"],
     [C2_2K12, BUCH],
     "direkt: Concept2 12-Wochen-2k-Plan, Woche 7 Tag 3 (12 x 1 min / 1 min Pause, Schlagzahl 24-34, Pause = sehr locker rudern); Pace-Offset 2k -4..-1 s abgeleitet (kürzer als 2 min im 2k-Tempo)",
     [warm(600, 30)] + reps(12,
        lambda i, n: ph("work", f"Intervall 1 min schneller als 2000-m-Tempo ({i}/{n})", f"Interval 1 min faster than 2000 m pace ({i}/{n})", t=60, spm=(28, 32), hr=5, pace=(-4, -1)),
        lambda i, n: rest(t=60)) + [cool(300)])

plan("intervalle-6x3",
     L("Intervalle 6 x 3 Minuten", "Intervals 6 x 3 minutes"),
     L("Sechs Intervalle zu 3 Minuten knapp langsamer als 2000-m-Tempo mit je 2 Minuten lockerer Pause.",
       "Six 3-minute pieces just slower than 2000 m pace with 2 minutes easy rest each."),
     L("VO2max / Sauerstofftransport TR (Puls 85-95 % HFmax, Pulszone 4-5)",
       "VO2max / oxygen transport TR (heart rate 85-95 % of max, zone 4-5)"),
     "F", "I", ["hard", "vo2max"],
     [C2_2K12, WOLF, BUCH],
     "direkt: Concept2 12-Wochen-2k-Plan, Woche 7 Tag 1 (6 x 3 min / 2 min Pause, Schlagzahl 24-34); Pace-Offset 2k +1..+4 s abgeleitet (zwischen 4 x 4 min im 2k-Tempo und Schwelle)",
     [warm(600, 30)] + reps(6,
        lambda i, n: ph("work", f"Intervall 3 min knapp unter 2000-m-Tempo ({i}/{n})", f"Interval 3 min just slower than 2000 m pace ({i}/{n})", t=180, spm=(26, 30), hr=5, pace=(1, 4)),
        lambda i, n: rest(t=120)) + [cool(300)])

plan("intervalle-40-20",
     L("40/20 Intervalle, 10 Minuten", "40/20 intervals, 10 minutes"),
     L("Zehn Minuten im Wechsel 40 Sekunden hart und 20 Sekunden locker. Kurz, intensiv, mit 5 Minuten Ein- und Ausrudern.",
       "Ten minutes alternating 40 seconds hard and 20 seconds easy. Short and intense, with 5 minutes warm-up and cool-down."),
     L("VO2max mit kurzen Pausen, Puls bleibt hoch (Pulszone 4-5)",
       "VO2max with short recoveries, heart rate stays high (zone 4-5)"),
     "F", "I", ["hard", "vo2max", "time-efficient"],
     [C2_BEST, BUCH],
     "direkt: Concept2 'The Best Rowing Machine Workouts' (5 min Einrudern, 10 min 40 s hart / 20 s locker, 5 min Ausrudern); Einrudern hier 6 min; Schlagzahl und Pace-Offset (2k -2..+2 s) eigene Eingrenzung",
     [warm(360, 28)] + reps(10,
        lambda i, n: ph("work", f"40 s hart ({i}/{n})", f"40 s hard ({i}/{n})", t=40, spm=(26, 32), hr=5, pace=(-2, 2)),
        lambda i, n: rest(t=20, de="20 s locker", en="20 s easy")) + [cool(300)])

plan("intervalle-6x500-r1",
     L("6 x 500 m mit 1 Minute Pause", "6 x 500 m with 1 minute rest"),
     L("Sechsmal 500 m im 2000-m-Tempo bei Schlagzahl 30+ mit nur 1 Minute Pause. Gleiches Tempo halten, das letzte Stück voll.",
       "Six 500 m pieces at 2000 m pace, rate 30+, with only 1 minute rest. Hold the same pace, go all out on the last one."),
     L("Renntempo-Härte / VO2max, gilt als Prognose für die 2000 m (Pulszone 5)",
       "Race-pace endurance / VO2max, often used as a 2000 m predictor (zone 5)"),
     "F", "I", ["hard", "vo2max", "race-pace"],
     [WOLF, C2_2K4],
     "direkt: Wolfson-Leitfaden (6 x 500 m, Schlagzahl 30+, 1 min Pause, gleicher Split, letztes Stück voll; Split nahe am 2k-Bestwert); Concept2 4-Wochen-2k-Plan nennt 6 x 500 m mit 2 min; Pace-Offset 2k -1..+1 s abgeleitet",
     [warm(600, 32)] + reps(6,
        lambda i, n: ph("work", (f"500 m im 2000-m-Tempo ({i}/{n})" if i < n else f"500 m, letztes Stück voll ({i}/{n})"),
                        (f"500 m at 2000 m pace ({i}/{n})" if i < n else f"500 m, last piece all out ({i}/{n})"),
                        d=500, spm=(30, 34), hr=5, pace=(-1, 1) if i < n else (-4, -1)),
        lambda i, n: rest(t=60)) + [cool(360)])

plan("intervalle-3x1000-r3",
     L("3 x 1000 m mit 3 Minuten Pause", "3 x 1000 m with 3 minutes rest"),
     L("Dreimal 1000 m knapp am 2000-m-Tempo mit je 3 Minuten lockerer Pause. Gleichmässig, kein schneller Start.",
       "Three 1000 m pieces close to 2000 m pace with 3 minutes easy rest each. Even pacing, no fast start."),
     L("VO2max / Renntempo-Härte (Pulszone 5)", "VO2max / race-pace endurance (zone 5)"),
     "F", "I", ["hard", "vo2max", "race-pace"],
     [C2_500, C2_2K4, WOLF],
     "direkt: Concept2 500-m-Plan (Zyklus 1: 3 x 1000 m / 3 min) und 4-Wochen-2k-Plan (3 x 1000 m / 3 min), Wolfson (3 x 1000 m r30+, 2 min, gleicher Split); Pace-Offset 2k -1..+2 s abgeleitet",
     [warm(600, 32)] + reps(3,
        lambda i, n: ph("work", f"1000 m knapp am 2000-m-Tempo ({i}/{n})", f"1000 m close to 2000 m pace ({i}/{n})", d=1000, spm=(28, 32), hr=5, pace=(-1, 2)),
        lambda i, n: rest(t=180)) + [cool(360)])

plan("intervalle-schlagzahlleiter-24-32",
     L("Schlagzahl-Leiter 24-32 in harten Intervallen", "Rate ladder 24-32 in hard intervals"),
     L("Zwei Runden mit je fünf Intervallen zu 2 Minuten bei Schlagzahl 24, 26, 28, 30, 32; das Tempo wird mit jeder Stufe schneller. 1 Minute Pause, 4 Minuten zwischen den Runden.",
       "Two rounds of five 2-minute pieces at rate 24, 26, 28, 30, 32; pace gets faster with each step. 1 minute rest, 4 minutes between rounds."),
     L("Schwelle bis VO2max, Übergang zu höheren Schlagzahlen ohne Längenverlust (Pulszone 4-5)",
       "Threshold to VO2max, moving up the rate without losing length (zone 4-5)"),
     "F", "I", ["hard", "vo2max", "rate-ladder", "progressive"],
     [C2_RATE, C2_2K12, WOLF],
     "abgeleitet: Concept2 (24-28 spm für längere Arbeit, 30-36 spm für Strecken bis 2000 m) und 2k-Plan-Fenster 24-34 spm; Leiterform, Dauern und Pace-Offsets (von 2k +8 s bei r24 bis 2k -2 s bei r32) eigene Konstruktion, keine Primärquelle für genau diese Einheit",
     [warm(600, 30)] + [p for rnd in (1, 2) for p in (
        sum([[ph("work", f"2 min bei Schlagzahl {r} (Runde {rnd}, Stufe {k}/5)", f"2 min at rate {r} (round {rnd}, step {k}/5)", t=120, spm=(r - 1, r + 1), hr=4 if r < 28 else 5, pace=pc)]
             + ([rest(t=60)] if k < 5 else [])
             for k, (r, pc) in enumerate([(24, (6, 9)), (26, (3, 6)), (28, (1, 3)), (30, (-1, 1)), (32, (-3, -1))], 1)], [])
        + ([rest(t=240, de="Pause 4 min zwischen den Runden: locker", en="Rest 4 min between rounds: easy")] if rnd == 1 else []))] + [cool(360)])

plan("intervalle-kraft-10x1-r20",
     L("Kraftausdauer 10 x 1 Minute bei Schlagzahl 20", "Power endurance 10 x 1 minute at rate 20"),
     L("Zehnmal 1 Minute mit maximalem Druck bei nur Schlagzahl 20, danach 1 Minute ganz leicht bei gleicher Schlagzahl.",
       "Ten times 1 minute with maximum pressure at only rate 20, then 1 minute very light at the same rate."),
     L("Kraftausdauer / Druck pro Schlag, AT bis TR (Pulszone 4)",
       "Power endurance / force per stroke, AT to TR (zone 4)"),
     "F", "I", ["hard", "power", "rate-cap"],
     [WOLF, C2_RATE],
     "direkt: Wolfson-Leitfaden, Power-Einheit '10x(1min on, 1min off), rate 20', in der Belastung all-out bei Schlagzahl 20, in der Pause sehr leicht bei gleicher Schlagzahl; Pace-Offset 2k +2..+8 s abgeleitet (Schlagzahl begrenzt das Tempo)",
     [warm(600, 26)] + reps(10,
        lambda i, n: ph("work", f"1 min maximaler Druck, Schlagzahl 20 ({i}/{n})", f"1 min maximum pressure, rate 20 ({i}/{n})", t=60, spm=(19, 21), hr=4, pace=(2, 8)),
        lambda i, n: rest(t=60, de="1 min ganz leicht, Schlagzahl 20 halten", en="1 min very light, keep rate 20", spm=(19, 21), hr=2)) + [cool(300)])

plan("intervalle-kraft-6x3-r18",
     L("Kraftausdauer 6 x 3 Minuten bei Schlagzahl 16-18", "Power endurance 6 x 3 minutes at rate 16-18"),
     L("Sechsmal 3 Minuten mit hohem Druck bei tiefer Schlagzahl 16-18 (lange, kräftige Schläge), je 2 Minuten locker.",
       "Six 3-minute pieces with high pressure at a low rate of 16-18 (long, strong strokes), 2 minutes easy between."),
     L("Kraftausdauer und Durchzug, Schwelle AT (Puls ca. 80-88 % HFmax, Pulszone 4)",
       "Power endurance and drive, threshold AT (heart rate about 80-88 % of max, zone 4)"),
     "F", "I", ["hard", "power", "rate-cap"],
     [WOLF, C2_RATE],
     "angepasst: Wolfson (Power-Einheiten bei tiefer Schlagzahl, z. B. r20 mit hohem Druck, 'close to a high-weight squat'), Concept2 (18-22 spm fühlt sich eher wie Krafttraining an, keine langen harten Einheiten in diesem Bereich); Schlagzahl 16-18, Dauer und Pace-Offset (2k +6..+12 s) eigene Eingrenzung",
     [warm(600, 24)] + reps(6,
        lambda i, n: ph("work", f"3 min hoher Druck, Schlagzahl 16-18 ({i}/{n})", f"3 min high pressure, rate 16-18 ({i}/{n})", t=180, spm=(16, 18), hr=4, pace=(6, 12)),
        lambda i, n: rest(t=120)) + [cool(300)])

plan("sprint-20x20-40",
     L("Sprint 20 x 20 Sekunden", "Sprint 20 x 20 seconds"),
     L("Zwanzig schnelle Stücke zu 20 Sekunden, 7-10 s pro 500 m schneller als 2000-m-Tempo, mit je 40 Sekunden lockerer Pause.",
       "Twenty fast 20-second pieces, 7-10 s per 500 m faster than 2000 m pace, with 40 seconds easy rest each."),
     L("Anaerobe Kapazität und VO2max (Pulszone 5)", "Anaerobic capacity and VO2max (zone 5)"),
     "F", "S", ["hard", "anaerobic", "vo2max"],
     [C2_GLUCK, BUCH],
     "direkt: Gluckman '30 and Out' (Concept2): 20 x 20 s im Tempo 2k -7..-10 s mit 40 s lockerem Paddeln; Warm-up dort 24/28/32 spm; Schlagzahl eigene Eingrenzung",
     [warm(600, 32, "Einrudern 10 min: steigernd, je 10 Schläge bei 24, 28, 32", "Warm-up 10 min: building, 10 strokes each at 24, 28, 32")] + reps(20,
        lambda i, n: ph("work", f"20 s schnell ({i}/{n})", f"20 s fast ({i}/{n})", t=20, spm=(30, 36), hr=5, pace=(-10, -7)),
        lambda i, n: rest(t=40, de="40 s locker", en="40 s easy")) + [cool(300)])

plan("sprint-startuebungen-6x",
     L("Startübungen 6 x Start", "Race starts 6 x"),
     L("Sechs Rennstarts aus dem Stand: 5 halbe Schläge zum Anrudern, dann 10 hohe, schnelle Schläge. Dazwischen 2 Minuten locker und kurz stoppen.",
       "Six race starts from a standstill: 5 half-slide strokes to get the flywheel going, then 10 high, fast strokes. 2 minutes easy and a short stop between."),
     L("Startschnelligkeit und Kraft, Technik unter Tempo (kurz Pulszone 4-5)",
       "Start speed and power, technique at speed (briefly zone 4-5)"),
     "F", "S", ["max", "power", "technique", "time-efficient"],
     [C2_START, C2_RATE, WOLF],
     "angepasst: Concept2 Neuseeland (erster Schlag mit 1/2-3/4 Rollweg, Zieltempo in den ersten 5 Schlägen erreichen; nur über Suchauszug gelesen), Concept2 (30-36 spm und mehr für kurze Strecken); Zählweise 5 halbe + 10 hohe Schläge ist eine übliche Variante, nicht einheitlich belegt; Dauer 30 s und Pausen eigene Eingrenzung",
     [warm(600, 30)] + reps(6,
        lambda i, n: ph("work", f"Start: 5 halbe Schläge, dann 10 hohe Schläge ({i}/{n})", f"Start: 5 half-slide strokes, then 10 high strokes ({i}/{n})", t=30, spm=(34, 40), hr=5, pace=(-12, -6)),
        lambda i, n: rest(t=120, de="Pause 2 min: locker, am Ende kurz anhalten für den nächsten Start", en="Rest 2 min: easy, stop briefly at the end for the next start")) + [cool(360)])

# ---------------------------------------------------------------- Leistung
plan("intervalle-8x500-pete",
     L("8 x 500 m (Pete Plan)", "8 x 500 m (Pete Plan)"),
     L("Achtmal 500 m etwa 3 s pro 500 m schneller als 2000-m-Bestzeit-Tempo mit je 3:30 Minuten Pause. Alle bis auf das letzte gleich, das letzte voll.",
       "Eight 500 m pieces about 3 s per 500 m faster than 2000 m best pace with 3:30 rest each. All but the last at the same pace, the last one all out."),
     L("Tempohärte über dem 2000-m-Tempo, VO2max und anaerob (Pulszone 5)",
       "Speed endurance above 2000 m pace, VO2max and anaerobic (zone 5)"),
     "L", "I", ["hard", "vo2max", "anaerobic"],
     [PETE, WOLV],
     "direkt: Pete Plan Woche 1 (8 x 500 m, 3:30 Pause; FAQ: 3 s schneller als 2k-Bestzeit-Tempo; alle bis auf das letzte im Zieltempo, das letzte so schnell wie möglich); auch Wolverine-Plan Stufe 1 (Caviston). Schlagzahl eigene Eingrenzung",
     [warm(600, 32)] + reps(8,
        lambda i, n: ph("work", (f"500 m, 3 s schneller als 2000-m-Tempo ({i}/{n})" if i < n else f"500 m, letztes Stück voll ({i}/{n})"),
                        (f"500 m, 3 s faster than 2000 m pace ({i}/{n})" if i < n else f"500 m, last piece all out ({i}/{n})"),
                        d=500, spm=(30, 34), hr=5, pace=(-4, -2) if i < n else (-7, -3)),
        lambda i, n: rest(t=210, de="Pause 3:30 min: locker weiterrudern", en="Rest 3:30 min: keep paddling easy")) + [cool(360)])

plan("intervalle-6x750",
     L("6 x 750 m im 2000-m-Tempo", "6 x 750 m at 2000 m pace"),
     L("Sechsmal 750 m im 2000-m-Tempo mit je 2:30 Minuten lockerer Pause. Zusammen 4500 m Renntempo.",
       "Six 750 m pieces at 2000 m pace with 2:30 easy rest each. 4500 m of race pace in total."),
     L("Renntempo-Härte / VO2max (Pulszone 5)", "Race-pace endurance / VO2max (zone 5)"),
     "L", "I", ["hard", "vo2max", "race-pace"],
     [PETE, C2_500, BUCH],
     "abgeleitet: Zwischenform aus Pete Plan 8 x 500 m (2k -3 s, 3:30) und 4 x 1000 m (2k +1 s, 5 min) sowie Concept2-Distanzintervallen; Distanz 750 m, Pause 2:30 und Pace-Offset (2k -1..+1 s) eigene Konstruktion, keine Primärquelle für genau diese Einheit",
     [warm(600, 32)] + reps(6,
        lambda i, n: ph("work", f"750 m im 2000-m-Tempo ({i}/{n})", f"750 m at 2000 m pace ({i}/{n})", d=750, spm=(28, 32), hr=5, pace=(-1, 1)),
        lambda i, n: rest(t=150, de="Pause 2:30 min: locker weiterrudern", en="Rest 2:30 min: keep paddling easy")) + [cool(360)])

plan("intervalle-4x1000-pete",
     L("4 x 1000 m (Pete Plan)", "4 x 1000 m (Pete Plan)"),
     L("Viermal 1000 m etwa 1 s pro 500 m langsamer als 2000-m-Bestzeit-Tempo mit je 5 Minuten Pause; das letzte Stück voll.",
       "Four 1000 m pieces about 1 s per 500 m slower than 2000 m best pace with 5 minutes rest each; last piece all out."),
     L("VO2max / Renntempo-Härte (Pulszone 5)", "VO2max / race-pace endurance (zone 5)"),
     "L", "I", ["hard", "vo2max", "race-pace"],
     [PETE, C2_500],
     "direkt: Pete Plan Woche 3 (4 x 1000 m, 5 min Pause; FAQ: 1 s langsamer als 2k-Bestzeit-Tempo); Concept2 500-m-Plan Zyklus 2 nennt 4 x 1000 m mit 3 min; Schlagzahl eigene Eingrenzung",
     [warm(600, 32)] + reps(4,
        lambda i, n: ph("work", (f"1000 m, 1 s langsamer als 2000-m-Tempo ({i}/{n})" if i < n else f"1000 m, letztes Stück voll ({i}/{n})"),
                        (f"1000 m, 1 s slower than 2000 m pace ({i}/{n})" if i < n else f"1000 m, last piece all out ({i}/{n})"),
                        d=1000, spm=(28, 32), hr=5, pace=(0, 2) if i < n else (-3, 0)),
        lambda i, n: rest(t=300, de="Pause 5 min: locker weiterrudern", en="Rest 5 min: keep paddling easy")) + [cool(420)])

plan("intervalle-pyramide-250-1000",
     L("Speed-Pyramide 250-1000-250 m (Pete Plan)", "Speed pyramid 250-1000-250 m (Pete Plan)"),
     L("Pyramide 250, 500, 750, 1000, 750, 500, 250 m im 2000-m-Tempo; Pause je 1:30 Minuten pro 250 m des vorherigen Stücks.",
       "Pyramid of 250, 500, 750, 1000, 750, 500, 250 m at 2000 m pace; rest 1:30 per 250 m of the previous piece."),
     L("VO2max und Renntempo, 4000 m Arbeit (Pulszone 5)", "VO2max and race pace, 4000 m of work (zone 5)"),
     "L", "I", ["hard", "vo2max", "pyramid", "race-pace"],
     [PETE, WOLV],
     "direkt: Pete Plan Woche 2 (250/500/750/1000/750/500/250 m, 1:30 Pause pro vorherige 250 m; FAQ: 2k-Bestzeit-Tempo); Caviston nennt dieselbe Pyramide als Wolverine-Stufe-1-Einheit (500er etwa im 8x500-Tempo, gleich- oder negativ gesplittet). Schlagzahl eigene Eingrenzung",
     [warm(600, 32)] + [p for i, dist in enumerate([250, 500, 750, 1000, 750, 500, 250], 1) for p in
        [ph("work", f"Pyramide {dist} m im 2000-m-Tempo (Stufe {i}/7)", f"Pyramid {dist} m at 2000 m pace (step {i}/7)", d=dist, spm=(28, 34), hr=5, pace=(-2, 1) if dist <= 500 else (-1, 1))]
        + ([rest(t=dist // 250 * 90, de=f"Pause {dist // 250 * 90 // 60}:{dist // 250 * 90 % 60:02d} min: locker weiterrudern", en=f"Rest {dist // 250 * 90 // 60}:{dist // 250 * 90 % 60:02d} min: keep paddling easy")] if i < 7 else [])] + [cool(420)])

plan("intervalle-2x10x1",
     L("Intervalle 2 x 10 x 1 Minute", "Intervals 2 x 10 x 1 minute"),
     L("Zwei Blöcke mit je zehn Intervallen 1 Minute hart / 1 Minute locker, 4 Minuten Pause zwischen den Blöcken.",
       "Two blocks of ten 1-minute hard / 1-minute easy pieces, 4 minutes rest between blocks."),
     L("VO2max mit grossem Umfang an Zeit nahe der maximalen Sauerstoffaufnahme (Pulszone 5)",
       "VO2max with a large volume of time near maximal oxygen uptake (zone 5)"),
     "L", "I", ["hard", "vo2max"],
     [C2_2K12, BUCH],
     "angepasst: Concept2 12-Wochen-2k-Plan (12 x 1 min / 1 min); auf 20 Wiederholungen in 2 Blöcken erweitert, gestützt auf Buchheit & Laursen (Ziel: mehrere Minuten pro Einheit über 90 % VO2max; Serien mit Blockpausen als Steuergrösse); Blockpause und Pace-Offset (2k -3..0 s) eigene Eingrenzung",
     [warm(600, 30)] + [p for b in (1, 2) for p in (
        reps(10, lambda i, n, b=b: ph("work", f"1 min hart (Block {b}, {i}/{n})", f"1 min hard (block {b}, {i}/{n})", t=60, spm=(28, 32), hr=5, pace=(-3, 0)),
             lambda i, n: rest(t=60))
        + ([rest(t=240, de="Pause 4 min zwischen den Blöcken: locker", en="Rest 4 min between blocks: easy")] if b == 1 else []))] + [cool(420)])

plan("intervalle-30-15",
     L("30/15 Intervalle 3 x 13 (Rønnestad)", "30/15 intervals 3 x 13 (Rønnestad)"),
     L("Drei Serien mit je 13 x 30 Sekunden hart / 15 Sekunden locker, 3 Minuten Pause zwischen den Serien. So hart, wie es sich über alle Serien gleichmässig halten lässt.",
       "Three sets of 13 x 30 seconds hard / 15 seconds easy, 3 minutes rest between sets. As hard as you can hold evenly across all sets."),
     L("VO2max und Leistung an der Schwelle, kurze Intervalle mit kurzer Pause (Pulszone 4-5)",
       "VO2max and power at threshold, short intervals with short recoveries (zone 4-5)"),
     "L", "I", ["hard", "vo2max", "threshold"],
     [RONN, BUCH],
     "angepasst: Rønnestad et al. 2020 (Radfahrer, Elite): 3 Serien x 13 x 30 s / 15 s Erholung, 3 min zwischen den Serien, Intensität nach maximal gleichmässig haltbarer Anstrengung; Übertragung aufs Rudern sowie Schlagzahl und Pace-Offset (2k -3..+1 s) eigene Ableitung",
     [warm(600, 30)] + [p for s in (1, 2, 3) for p in (
        reps(13, lambda i, n, s=s: ph("work", f"30 s hart (Serie {s}, {i}/{n})", f"30 s hard (set {s}, {i}/{n})", t=30, spm=(28, 32), hr=5, pace=(-3, 1)),
             lambda i, n: rest(t=15, de="15 s locker", en="15 s easy"))
        + ([rest(t=180, de="Pause 3 min zwischen den Serien: locker", en="Rest 3 min between sets: easy")] if s < 3 else []))] + [cool(420)])

plan("intervalle-30-30-x20",
     L("20 x 30 Sekunden volle Kraft", "20 x 30 seconds full power"),
     L("Zwanzigmal 30 Sekunden mit voller Kraft, je 30 Sekunden locker. Sehr fordernd, Tempo über alle 20 möglichst halten.",
       "Twenty times 30 seconds at full power, 30 seconds easy between. Very demanding; try to hold the pace across all 20."),
     L("VO2max und anaerobe Kapazität (Pulszone 5)", "VO2max and anaerobic capacity (zone 5)"),
     "L", "I", ["max", "vo2max", "anaerobic"],
     [C2_2030, BUCH],
     "direkt: Concept2 '20 x 30 Seconds Full Power with a CrossFit Champion' (20 x 30 s volle Kraft / 30 s Pause); Einrudern, Schlagzahl und Pace-Offset (2k -8..-3 s) eigene Eingrenzung",
     [warm(600, 32)] + reps(20,
        lambda i, n: ph("work", f"30 s volle Kraft ({i}/{n})", f"30 s full power ({i}/{n})", t=30, spm=(30, 36), hr=5, pace=(-8, -3)),
        lambda i, n: rest(t=30, de="30 s locker", en="30 s easy")) + [cool(300)])

plan("sprint-tabata-8x20-10",
     L("Tabata 8 x 20/10 Sekunden", "Tabata 8 x 20/10 seconds"),
     L("Acht Runden 20 Sekunden maximal / 10 Sekunden locker (4 Minuten). Nur nach gründlichem Einrudern und für Gesunde mit Erfahrung in harten Einheiten.",
       "Eight rounds of 20 seconds maximal / 10 seconds easy (4 minutes). Only after a thorough warm-up and for healthy rowers used to hard sessions."),
     L("Anaerobe Kapazität und VO2max, sehr hohe Belastung (Pulszone 5)",
       "Anaerobic capacity and VO2max, very high strain (zone 5)"),
     "L", "S", ["max", "anaerobic", "vo2max", "time-efficient"],
     [C2_BEST, TABATA],
     "direkt: Concept2 'The Best Rowing Machine Workouts' (10 min Einrudern, 8 x 20 s maximal / 10 s locker, 5 min Ausrudern; optional nach 2 min ein zweiter Satz); Ursprung Tabata et al. 1996 (Fahrradergometer, 7-8 x 20 s bei ca. 170 % VO2max, 10 s Pause, bis zur Erschöpfung). Pace-Offset (2k -12..-4 s, fällt über die Runden ab) und Schlagzahl eigene Eingrenzung",
     [warm(600, 32)] + reps(8,
        lambda i, n: ph("work", f"20 s maximal ({i}/{n})", f"20 s maximal ({i}/{n})", t=20, spm=(32, 38), hr=5, pace=(-12, -4)),
        lambda i, n: rest(t=10, de="10 s locker", en="10 s easy")) + [cool(480)])

plan("sprint-10x100",
     L("Sprint 10 x 100 m", "Sprint 10 x 100 m"),
     L("Zehn Sprints über 100 m bei hoher Schlagzahl mit je 1:30 Minuten lockerer Pause. Jeder Sprint voll, sauberer Start.",
       "Ten 100 m sprints at a high rate with 1:30 easy rest each. Every sprint all out, clean start."),
     L("Schnelligkeit und Maximalkraft, anaerob-alaktazid (Pulszone 4-5)",
       "Speed and peak power, anaerobic alactic (zone 4-5)"),
     "L", "S", ["max", "anaerobic", "power"],
     [C2_RATE, WOLF, BUCH],
     "abgeleitet: Concept2 (30-36 spm und mehr für kurze Strecken) und Wolfson (Sprints 6-10 kurze Stücke bei 30-36 spm, all-out); Distanz 100 m (Concept2-Ranglistenstrecke), Pause 1:30 und Pace-Offset (2k -14..-8 s) eigene Konstruktion",
     [warm(600, 34)] + reps(10,
        lambda i, n: ph("work", f"Sprint 100 m voll ({i}/{n})", f"Sprint 100 m all out ({i}/{n})", d=100, spm=(34, 42), hr=5, pace=(-14, -8)),
        lambda i, n: rest(t=90, de="Pause 1:30 min: locker weiterrudern", en="Rest 1:30 min: keep paddling easy")) + [cool(360)])

plan("sprint-6x1min",
     L("Sprint 6 x 1 Minute", "Sprint 6 x 1 minute"),
     L("Sechsmal 1 Minute sehr hart (deutlich schneller als 2000-m-Tempo) mit je 3 Minuten lockerer Pause.",
       "Six times 1 minute very hard (well faster than 2000 m pace) with 3 minutes easy rest each."),
     L("Anaerobe Kapazität / Laktattoleranz (Pulszone 5)", "Anaerobic capacity / lactate tolerance (zone 5)"),
     "L", "S", ["max", "anaerobic"],
     [C2_500, C2_RATE, BUCH],
     "abgeleitet: Concept2 500-m-Plan (kurze harte Stücke mit langen Pausen, 26-36 spm) und Gluckman (500 m 2k -2..-6 s, 20 s 2k -7..-10 s); 1 min mit 1:3-Pause und Pace-Offset (2k -8..-4 s) eigene Konstruktion",
     [warm(600, 32)] + reps(6,
        lambda i, n: ph("work", f"1 min sehr hart ({i}/{n})", f"1 min very hard ({i}/{n})", t=60, spm=(30, 36), hr=5, pace=(-8, -4)),
        lambda i, n: rest(t=180, de="Pause 3 min: locker weiterrudern", en="Rest 3 min: keep paddling easy")) + [cool(420)])

# ---------------------------------------------------------------- checks and output
def dur(p, ref=120.0):
    """approx seconds: distance phases at 2k ref pace + offset (or +20 s/500 m for rest)."""
    if "durationS" in p: return p["durationS"]
    off = (p.get("paceOffsetMinS", 20) + p.get("paceOffsetMaxS", 20)) / 2
    return p["distanceM"] / 500 * (ref + off)

def fmt_t(s):
    s = int(round(s)); return f"{s // 60}:{s % 60:02d} min"

existing = {"grundlage-locker-30", "grundlage-3x10-r20", "schwelle-4x6", "kurzintervalle-8x2", "langintervalle-4x4",
            "pyramide-1-2-3-4-3-2-1", "frequenzleiter-18-24", "sprint-8x250", "test-2000m", "technik-locker-25"}
ids = [p["id"] for p in PLANS]
assert len(ids) == len(set(ids)) and not (set(ids) & existing)
for p in PLANS:
    for q in p["phases"]:
        assert ("durationS" in q) ^ ("distanceM" in q), (p["id"], q)
        assert q.get("spmMin", 0) <= q.get("spmMax", 0)
    if p["phases"][0]["kind"] != "warmup" or p["phases"][-1]["kind"] != "cooldown":
        sys.exit(f"warmup/cooldown missing: {p['id']}")
    total = sum(dur(q) for q in p["phases"])
    if "time-efficient" in p["tags"] and total > 30 * 60 + 30:
        print(f"WARN time-efficient but {total / 60:.1f} min: {p['id']}")

(ROOT / "intervalle.json").write_text(json.dumps(PLANS, ensure_ascii=False, indent=2) + "\n")

# ---- markdown
def pace_s(q):
    if "paceOffsetMinS" not in q: return "-"
    a, b = q["paceOffsetMinS"], q["paceOffsetMaxS"]
    f = lambda x: f"+{x}" if x > 0 else str(x)
    return f"2k {f(a)}..{f(b)} s/500 m"

out = [open(Path(__file__).with_name("md_head.md")).read().rstrip() + "\n"]
for p in PLANS:
    tsec = sum(q.get("durationS", 0) for q in p["phases"])
    dist = sum(q.get("distanceM", 0) for q in p["phases"])
    approx = sum(dur(q) for q in p["phases"])
    out.append(f"\n## {p['name']['de']} (`{p['id']}`)\n")
    out.append(f"- Erklärung: {p['summary']['de']}")
    out.append(f"- Zweck/Bereich: {p['purpose']['de']}")
    out.append(f"- Niveau: {p['level']['de']} · Kategorie: {p['category']['de']} · Tags: {', '.join(p['tags'])}")
    out.append(f"- Belegstatus: {p['evidence']}")
    out.append("- Quellen: " + "; ".join(f"{s['publisher']} - {s['title']}" for s in p["sources"]))
    extra = f" + {dist} m in Distanzphasen" if dist else ""
    out.append(f"- Umfang: zeitbasierte Phasen {fmt_t(tsec)}{extra}; Gesamtdauer ca. {round(approx / 60)} min (Bezug 2:00/500 m)")
    if MD[p["id"]]: out.append(f"- Hinweis: {MD[p['id']]}")
    out.append("\n| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |\n|---|---|---|---|---|---|---|")
    for q in p["phases"]:
        dd = fmt_t(q["durationS"]) if "durationS" in q else f"{q['distanceM']} m"
        spm = f"{q['spmMin']}-{q['spmMax']}" if "spmMin" in q else "-"
        pause = ("aktiv" if q.get("activeRest") else "stehen") if q["kind"] == "rest" else "-"
        out.append(f"| {q['kind']} | {dd} | {spm} | {q['hrZone']} | {pace_s(q)} | {pause} | {q['label']['de']} |")
out.append("\n" + open(Path(__file__).with_name("md_tail.md")).read().rstrip() + "\n")
(ROOT / "intervalle.md").write_text("\n".join(out))

for p in PLANS:
    approx = sum(dur(q) for q in p["phases"])
    work = [q for q in p["phases"] if q["kind"] == "work"]
    print(f"{p['id']} | {p['name']['de']} | {p['category']['de']} | {p['level']['de']} | {'Distanz' if any('distanceM' in q for q in work) else 'Zeit'} | ~{round(approx / 60)} min | {len(p['phases'])} Phasen")
print(len(PLANS))
