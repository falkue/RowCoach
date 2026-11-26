#!/usr/bin/env python3
"""Erzeugt docs/plans-new/tests.json und tests.md (Familie tests, RowCoach)."""
import json, pathlib

OUT = pathlib.Path("/home/falkue/Projects/Software/RowCoach/docs/plans-new")

def S(title, publisher, url, published=None, zotero=None):
    return {"title": title, "publisher": publisher, "url": url, "published": published, "zotero": zotero}

C2_2K4 = S("Training for a 2K Rowing Ergometer Test - 4 Week Plan", "Concept2", "https://www.concept2.com/training/plans/2k-erg-test-4-week")
C2_2K12 = S("Training for a 2K Rowing Ergometer Test - 12 Week Plan", "Concept2", "https://www.concept2.com/training/plans/2k-erg-test-12-week")
C2_500 = S("Training for a 500m Rowing Ergometer Test", "Concept2", "https://www.concept2.com/training/plans/500m-erg-test")
C2_5K = S("Training for a 5K Rowing Ergometer Test", "Concept2", "https://www.concept2.com/training/plans/5k-erg-test")
C2_4MIN = S("Training for a 4 Minute Rowing Ergometer Test", "Concept2", "https://www.concept2.com/training/plans/4min-erg-test")
C2_RANK = S("Concept2 Online Ranking (RowErg events: 1 min, 4 min, 30 min, 60 min, 100 m to 100 000 m)", "Concept2", "https://log.concept2.com/rankings")
C2_PACE = S("How To Find Your 2k Race Pace", "Concept2", "https://www.concept2.com/training/articles/how-to-find-your-2k-pace")
C2_FLY = S("Fly and Die: Strategies for Pacing", "Concept2", "https://www.concept2.com/blog/fly-and-die-strategies-for-pacing", "2018-01-19")
C2_WARM = S("A First Class Warm-up", "Concept2 (Australia)", "https://www.concept2.com.au/blog/a-first-class-warmup", "2011-06-01")
WR_JENSEN = S("Using the indoor rower for testing: why do we test different distances? (K. Jensen: 60 min ~76 %, 6000 m ~85 %, 60 s ~153 %, 10 s/100 m ~173 % of 2000-m watts)", "World Rowing", "https://worldrowing.com/2019/11/26/using-the-indoor-rower-for-testing-why-test-different-distances/", "2019-11-26")
WR_HAY = S("Indoor rowing part 2 - ergo testing strategy (G. Hay)", "World Rowing", "https://worldrowing.com/2020/04/07/indoor-rowing-part-ergo-testing-strategy/", "2020-04-07")
PAUL = S("\"Paul's Law\" (double the distance, add about 5 s/500 m); forum thread, secondary source", "Concept2 Forum", "https://c2forum.com/viewtopic.php?p=100995", "2008-05-14")
GARLAND = S("An analysis of the pacing strategy adopted by elite competitors in 2000 m rowing (Garland), Br J Sports Med 39(1):39-42, doi:10.1136/bjsm.2003.010801", "BMJ", "https://pmc.ncbi.nlm.nih.gov/articles/PMC1725010", "2005-01")
KASS = S("The Effect of Sampling Time on Blood Lactate Concentration in Trained Rowers (Kass & Carpenter), incremental test 5 x 4 min, methods p. 3-4; repository manuscript", "University of Hertfordshire Research Archive", "https://uhra.herts.ac.uk/id/eprint/790/2/903972.pdf")
LIND = S("Differences in Physiological Responses During Rowing and Cycle Ergometry in Elite Male Rowers (Lindenthaler, Rice et al.), Front Physiol 9:1010, doi:10.3389/fphys.2018.01010", "Frontiers", "https://pmc.ncbi.nlm.nih.gov/articles/PMC6077239", "2018-07-30")
BOSQ = S("Effects of tapering on performance: a meta-analysis (Bosquet, Montpetit, Arvisais, Mujika), Med Sci Sports Exerc 39:1358-1365 (abstract)", "Lippincott Williams & Wilkins / ACSM", "https://pubmed.ncbi.nlm.nih.gov/17762369/", "2007")
USR = S("The Race (race phases: start, settle, sprint; head races)", "USRowing", "https://usrowing.org/learn-about-rowing/overview/the-race")
BR_WARM = S("Race-day warm-up for indoor rowing (British Rowing Plus, J. Brown); page redirected, only search excerpt read, secondary", "British Rowing", "https://plus.britishrowing.org/?p=7597")
WOLF = S("Erging (Wolfson College Boat Club training guide), sections 1.5-1.6; club guide, secondary source", "Wolfson College Boat Club, University of Cambridge", "https://www.wolfson.cam.ac.uk/sites/default/files/2019-11/wcbc_erging_0.pdf", "2019")

def L(de, en):
    return {"de": de, "en": en}

def ph(kind, de, en, *, t=None, d=None, spm=None, hr=None, pace=None, active=None):
    p = {"kind": kind}
    if t is not None: p["durationS"] = t
    if d is not None: p["distanceM"] = d
    if spm: p["spmMin"], p["spmMax"] = spm
    if hr: p["hrZone"] = hr
    if pace: p["paceOffsetMinS"], p["paceOffsetMaxS"] = pace
    if active is not None: p["activeRest"] = active
    p["label"] = L(de, en)
    return p

LEVEL = {"E": L("Einsteiger", "Beginner"), "F": L("Fortgeschritten", "Advanced"), "P": L("Leistung", "Performance")}
CAT = {"T": L("Test", "Test"), "W": L("Wettkampf", "Race preparation")}

def plan(id, name, summary, purpose, level, cat, tags, sources, evidence, phases):
    return {"id": id, "name": name, "summary": summary, "purpose": purpose, "level": LEVEL[level],
            "category": CAT[cat], "tags": tags, "sources": sources, "evidence": evidence, "phases": phases}

# Bausteine
def warm_long(t=480):
    return ph("warmup", f"Einrudern {t//60} min: locker beginnen, steigern, am Ende 3 kurze Antritte",
              f"Warm-up {t//60} min: start easy, build, 3 short bursts at the end", t=t, spm=(18, 26), hr=2)

def warm_short_test():
    return [ph("warmup", "Einrudern 8 min: locker beginnen, bis mittlere Intensität steigern",
               "Warm-up 8 min: start easy, build to moderate intensity", t=480, spm=(18, 24), hr=2),
            ph("warmup", "Antritte: 3 x 5-10 Schläge hart, dazwischen locker",
               "Bursts: 3 x 5-10 hard strokes, easy in between", t=120, spm=(20, 34), hr=3),
            ph("rest", "Pause vor dem Test: locker paddeln, Monitor einstellen",
               "Rest before the test: paddle easy, set up the monitor", t=120, spm=(16, 20), hr=1, active=True)]

def cool(t=300):
    return ph("cooldown", f"Ausrudern {t//60} min: ganz locker", f"Cool-down {t//60} min: very easy", t=t, spm=(16, 20), hr=1)

def rest(t, de="Pause: locker weiterrudern", en="Rest: keep rowing easy", active=True):
    return ph("rest", de, en, t=t, spm=(16, 20) if active else None, hr=1, active=active)

P = []

# ---------- TESTS: Concept2-Ranglistenstücke ----------
P.append(plan("test-100m",
    L("Test 100 m", "100 m test"),
    L("Ein 100-m-Sprint auf Bestzeit nach gründlichem Einrudern mit Antritten.", "A 100 m all-out sprint for a best time after a thorough warm-up with bursts."),
    L("Test Maximalkraft und anaerobe Leistung, Concept2-Ranglistenstück (Pulszone 5; Puls steigt erst nach dem Sprint)", "Test of peak power and anaerobic power, Concept2 ranked piece (zone 5; heart rate peaks only after the sprint)"),
    "F", "T", ["max", "power", "anaerobic", "benchmark", "c2-ranked", "time-efficient"],
    [C2_RANK, WR_JENSEN, C2_500],
    "abgeleitet: Distanz direkt (Concept2-Rangliste, Jensen nennt 10 s/100 m als Standardtest); Tempo aus Jensen (~173 % der 2k-Watt) über Watt ~ 1/Pace^3; Einrudern nach Concept2-Plänen, Schlagzahl eigene Eingrenzung",
    warm_short_test() + [
        ph("work", "100 m Sprint: kurzer Start (halbe, halbe, dreiviertel Schlag), dann voll",
           "100 m sprint: short start (half, half, three-quarter stroke), then flat out", d=100, spm=(36, 46), hr=5, pace=(-23, -17)),
        cool(420)]))

P.append(plan("test-500m",
    L("Test 500 m", "500 m test"),
    L("500 m auf Bestzeit: nicht zu schnell starten, in der zweiten Hälfte zulegen.", "500 m for a best time: don't start too fast, pick it up over the second half."),
    L("Test anaerobe Kapazität, Concept2-Ranglistenstück (Pulszone 5)", "Test of anaerobic capacity, Concept2 ranked piece (zone 5)"),
    "F", "T", ["max", "anaerobic", "benchmark", "c2-ranked", "time-efficient"],
    [C2_500, C2_RANK, PAUL],
    "direkt: Concept2 500-m-Plan (500-m-Zeitfahren, Einrudern 5-10 min mit Antritten, Schlagzahl 26-36, nicht zu schnell starten, konstant oder negativer Split); Tempo abgeleitet aus Paul's Law (2k -10 s/500 m)",
    warm_short_test() + [
        ph("work", "500 m Bestzeit: erste 250 m kontrolliert, dann steigern",
           "500 m best time: first 250 m controlled, then build", d=500, spm=(30, 38), hr=5, pace=(-12, -8)),
        cool(420)]))

P.append(plan("test-1000m",
    L("Test 1000 m", "1000 m test"),
    L("1000 m auf Bestzeit, gleichmässig oder mit leicht negativem Split. Guter erster Maximaltest, weil kurz.", "1000 m for a best time, even or slightly negative split. A good first maximal test because it is short."),
    L("Test VO2max und anaerobe Kapazität, Concept2-Ranglistenstück (Pulszone 5)", "Test of VO2max and anaerobic capacity, Concept2 ranked piece (zone 5)"),
    "E", "T", ["max", "vo2max", "anaerobic", "benchmark", "c2-ranked", "time-efficient", "beginner-friendly"],
    [C2_RANK, C2_2K4, PAUL],
    "angepasst: Distanz aus der Concept2-Rangliste, Einrudern und Renntaktik aus den Concept2-Testplänen; Tempo abgeleitet aus Paul's Law (2k -5 s/500 m); Niveau Einsteiger eigene Einschätzung (kurze Belastung, ohne 2k-Bestzeit nach Gefühl rudern)",
    warm_short_test() + [
        ph("work", "1000 m Bestzeit: erste 250 m 1-2 s langsamer als Ziel, ab 500 m steigern",
           "1000 m best time: first 250 m 1-2 s slower than target, build from 500 m", d=1000, spm=(26, 34), hr=5, pace=(-7, -3)),
        cool(420)]))

P.append(plan("test-1min",
    L("Test 1 Minute", "1 minute test"),
    L("Eine Minute so weit wie möglich rudern; die Strecke ist das Ergebnis.", "Row as far as possible in one minute; the distance is the result."),
    L("Test anaerobe Kapazität, Concept2-Ranglistenstück (Pulszone 5)", "Test of anaerobic capacity, Concept2 ranked piece (zone 5)"),
    "F", "T", ["max", "anaerobic", "power", "benchmark", "c2-ranked", "time-efficient"],
    [C2_RANK, WR_JENSEN],
    "abgeleitet: Dauer direkt (Concept2-Rangliste, Jensen nennt 60 s als Standardtest); Tempo aus Jensen (~153 % der 2k-Watt) über Watt ~ 1/Pace^3; Einrudern nach Concept2-Plänen",
    warm_short_test() + [
        ph("work", "1 min auf maximale Strecke: kurzer Start, ab 30 s Tempo halten",
           "1 min for maximum distance: short start, hold the pace from 30 s", t=60, spm=(32, 42), hr=5, pace=(-18, -14)),
        cool(420)]))

P.append(plan("test-4min",
    L("Test 4 Minuten", "4 minute test"),
    L("Vier Minuten so weit wie möglich, mit kontrolliertem Beginn und Steigerung in der zweiten Hälfte.", "Four minutes as far as possible, with a controlled start and a build over the second half."),
    L("Test VO2max (maximale aerobe Leistung), Concept2-Ranglistenstück (Pulszone 5)", "Test of VO2max (maximal aerobic power), Concept2 ranked piece (zone 5)"),
    "F", "T", ["max", "vo2max", "benchmark", "c2-ranked", "time-efficient", "negative-split"],
    [C2_4MIN, C2_RANK, PAUL],
    "direkt: Concept2 4-min-Plan (4-min-Zeitfahren, Einrudern 5-10 min mit Antritten, Schlagzahl 26-36, zweite Hälfte schneller, negativer Split mit 1-2 s langsamerem Start); Tempo abgeleitet aus Paul's Law (rund 1000-1050 m, 2k -3..-5 s)",
    warm_short_test() + [
        ph("work", "4 min auf maximale Strecke: erste 2 min 1-2 s langsamer als Ziel, dann steigern",
           "4 min for maximum distance: first 2 min 1-2 s slower than target, then build", t=240, spm=(28, 34), hr=5, pace=(-6, -2)),
        cool(420)]))

P.append(plan("test-5000m",
    L("Test 5000 m", "5000 m test"),
    L("5000 m auf Bestzeit im geplanten Renntempo; wer sich auf dem letzten Kilometer gut fühlt, legt zu.", "5000 m for a best time at the planned race pace; if you feel good over the last kilometre, push on."),
    L("Test aerobe Leistung nahe der Schwelle, Concept2-Ranglistenstück (Pulszone 4-5)", "Test of aerobic power near threshold, Concept2 ranked piece (zone 4-5)"),
    "F", "T", ["hard", "threshold", "vo2max", "benchmark", "c2-ranked"],
    [C2_5K, C2_RANK, PAUL, WR_HAY],
    "direkt: Concept2 5k-Plan (5k-Test im bekannten Renntempo, letzten Kilometer steigern, Schlagzahl 24-30, Einrudern 5-10 min); Tempo abgeleitet aus Paul's Law (2k +6-7 s)",
    [warm_long(600),
     ph("work", "Kilometer 1-4 im Renntempo: geduldig, nicht zu schnell beginnen",
        "Kilometres 1-4 at race pace: be patient, don't start too fast", d=4000, spm=(24, 30), hr=4, pace=(5, 8)),
     ph("work", "Letzter Kilometer: steigern, auf den letzten 250 m alles geben",
        "Last kilometre: build, empty the tank over the last 250 m", d=1000, spm=(26, 32), hr=5, pace=(3, 6)),
     cool(420)]))

P.append(plan("test-6000m",
    L("Test 6000 m (Wintertest)", "6000 m test (winter test)"),
    L("6000 m auf Bestzeit in gleichmässigem Tempo; klassischer Wintertest in Vereinen, auch bei Junioren und Masters.", "6000 m for a best time at an even pace; the classic winter test in clubs, also for juniors and masters."),
    L("Test aerobe Leistung, Concept2-Ranglistenstück (Pulszone 4-5)", "Test of aerobic power, Concept2 ranked piece (zone 4-5)"),
    "P", "T", ["hard", "threshold", "aerobic", "benchmark", "c2-ranked"],
    [WR_JENSEN, C2_RANK, WR_HAY, PAUL],
    "abgeleitet: Distanz direkt (Concept2-Rangliste; Jensen/World Rowing nennt 6000 m als Standardtest, Hay: Taktik wie 2000 m, Schlagzahl bewusst wählen); Tempo aus Jensen (~85 % der 2k-Watt, entspricht 2k +6-7 s) und Paul's Law (+8 s); 'Wintertest' Vereinsbrauch, nicht belegt",
    [warm_long(600),
     ph("work", "Erste 2000 m: Zieltempo halten, geduldig bleiben",
        "First 2000 m: hold target pace, stay patient", d=2000, spm=(24, 30), hr=4, pace=(6, 9)),
     ph("work", "2000-4000 m: Rhythmus halten, Schlagzahl nicht absinken lassen",
        "2000-4000 m: hold the rhythm, don't let the rate drop", d=2000, spm=(24, 30), hr=4, pace=(6, 9)),
     ph("work", "Letzte 2000 m: ab 5000 m steigern",
        "Last 2000 m: build from 5000 m", d=2000, spm=(26, 32), hr=5, pace=(4, 8)),
     cool(420)]))

P.append(plan("test-10000m",
    L("Test 10 000 m", "10 000 m test"),
    L("10 000 m auf Bestzeit in konstantem Tempo, mit Steigerung auf den letzten 2000 m.", "10 000 m for a best time at a constant pace, building over the last 2000 m."),
    L("Test aerobe Ausdauer an der Schwelle, Concept2-Ranglistenstück (Pulszone 4)", "Test of aerobic endurance at threshold, Concept2 ranked piece (zone 4)"),
    "P", "T", ["hard", "threshold", "aerobic", "benchmark", "c2-ranked"],
    [C2_RANK, C2_2K12, PAUL],
    "abgeleitet: Distanz aus der Concept2-Rangliste (10 000 m im 12-Wochen-Plan als konstantes Stück); Testfassung mit Tempo aus Paul's Law (2k +11-12 s); Schlagzahl eigene Eingrenzung",
    [warm_long(600),
     ph("work", "0-8000 m: konstantes Zieltempo, ruhiger Rhythmus",
        "0-8000 m: constant target pace, calm rhythm", d=8000, spm=(22, 28), hr=4, pace=(10, 13)),
     ph("work", "Letzte 2000 m: steigern, letzte 500 m Endspurt",
        "Last 2000 m: build, sprint the last 500 m", d=2000, spm=(24, 30), hr=5, pace=(7, 11)),
     cool(420)]))

P.append(plan("test-30min",
    L("Test 30 Minuten", "30 minute test"),
    L("30 Minuten so weit wie möglich in gleichmässigem Tempo; die Strecke ist das Ergebnis.", "30 minutes as far as possible at an even pace; the distance is the result."),
    L("Test Schwellenleistung, Concept2-Ranglistenstück (Pulszone 4)", "Test of threshold power, Concept2 ranked piece (zone 4)"),
    "F", "T", ["hard", "threshold", "benchmark", "c2-ranked"],
    [C2_RANK, WOLF, PAUL],
    "abgeleitet: Dauer aus der Concept2-Rangliste, Wolfson nennt 30 min (30r20) als üblichen Test; Tempo aus Paul's Law (rund 7-7,5 km, 2k +9-10 s); Schlagzahl eigene Eingrenzung",
    [warm_long(600),
     ph("work", "Minute 0-25: konstantes Zieltempo, Schlagzahl ruhig halten",
        "Minutes 0-25: constant target pace, keep the rate steady", t=1500, spm=(22, 28), hr=4, pace=(8, 11)),
     ph("work", "Letzte 5 min: steigern, letzte Minute Endspurt",
        "Last 5 min: build, sprint the final minute", t=300, spm=(24, 30), hr=5, pace=(5, 9)),
     cool(420)]))

P.append(plan("test-60min",
    L("Test 60 Minuten", "60 minute test"),
    L("Eine Stunde so weit wie möglich in konstantem Tempo, mit Steigerung in den letzten 10 Minuten.", "One hour as far as possible at a constant pace, building over the last 10 minutes."),
    L("Test aerobe Ausdauer knapp unter der Schwelle, Concept2-Ranglistenstück (Pulszone 3-4)", "Test of aerobic endurance just below threshold, Concept2 ranked piece (zone 3-4)"),
    "P", "T", ["hard", "aerobic", "threshold", "benchmark", "c2-ranked"],
    [WR_JENSEN, C2_RANK, PAUL],
    "abgeleitet: Dauer direkt (Concept2-Rangliste; Jensen nennt 60 min als Standardtest); Tempo aus Jensen (~76 % der 2k-Watt = 2k +11-12 s) und Paul's Law (+13-14 s)",
    [warm_long(600),
     ph("work", "Minute 0-50: konstantes Zieltempo, alle 10 min trinken erlaubt",
        "Minutes 0-50: constant target pace, drink every 10 min if needed", t=3000, spm=(20, 26), hr=4, pace=(11, 14)),
     ph("work", "Letzte 10 min: steigern, letzte 2 min Endspurt",
        "Last 10 min: build, sprint the last 2 min", t=600, spm=(22, 28), hr=4, pace=(8, 12)),
     cool(420)]))

# ---------- Stufentests ----------
WARM_STEP = ph("warmup", "Einrudern 10 min sehr locker, ohne Antritte (sonst verfälscht es Puls und Laktat der ersten Stufen)",
               "Warm-up 10 min very easy, no bursts (they would distort heart rate and lactate in the first steps)", t=600, spm=(18, 22), hr=1)
kass = [(60, 63, 1), (39, 43, 2), (25, 29, 2), (16, 20, 3), (9, 11, 4)]
ph_k = [WARM_STEP]
for i, (a, b, z) in enumerate(kass, 1):
    ph_k.append(ph("work", f"Stufe {i}/5: konstant 4 min" + ("" if i < 5 else " (oberste Stufe = 2k-Split +10 s)"),
                   f"Step {i}/5: steady 4 min" + ("" if i < 5 else " (top step = 2k split +10 s)"),
                   t=240, spm=(18 + 2 * (i - 1), 22 + 2 * (i - 1)), hr=z, pace=(a, b)))
    if i < 5:
        ph_k.append(rest(60, f"Pause 1 min stehen (Puls notieren) ({i}/4)", f"Rest 1 min stopped (note heart rate) ({i}/4)", active=False))
ph_k.append(cool(480))
P.append(plan("stufentest-5x4",
    L("Stufentest 5 x 4 min (submaximal)", "Step test 5 x 4 min (submaximal)"),
    L("Fünf Stufen zu 4 Minuten mit steigender Leistung und 1 Minute Pause; die oberste Stufe liegt 10 s/500 m über dem 2k-Tempo. Puls am Ende jeder Stufe notieren.", "Five 4-minute steps of rising power with 1 minute rest; the top step is 10 s/500 m slower than 2k pace. Note your heart rate at the end of each step."),
    L("Leistungsdiagnostik: Puls-Leistungs-Kurve und Schwelle (mit Laktat), Kontrolle der Pulszonen (Pulszone 1-4)", "Performance diagnostics: heart rate-power curve and threshold (with lactate), checking heart rate zones (zone 1-4)"),
    "F", "T", ["moderate", "threshold", "aerobic", "progressive", "ladder", "benchmark"],
    [KASS, LIND],
    "direkt: Kass & Carpenter (5 Stufen à 4 min, 1 min Pause, Stufe 5 = 2k-Split +10 s, darunter je -25 W, Einrudern 10 min sehr locker); Pace-Offsets abgeleitet aus Watt ~ 1/Pace^3 für Referenz 2:00/500 m (bei anderen Splits weichen die unteren Stufen ab); Schlagzahl eigene Eingrenzung",
    ph_k))

lind = [(52, 56, 1), (37, 41, 2), (27, 31, 3), (19, 22, 3), (12, 15, 4), (7, 9, 4)]
ph_l = [WARM_STEP]
for i, (a, b, z) in enumerate(lind, 1):
    ph_l.append(ph("work", f"Stufe {i}/7: konstant 4 min", f"Step {i}/7: steady 4 min",
                   t=240, spm=(18 + 2 * (i - 1), 22 + 2 * (i - 1)), hr=z, pace=(a, b)))
    ph_l.append(rest(60, f"Pause 1 min stehen (Puls/Laktat) ({i}/6)", f"Rest 1 min stopped (heart rate/lactate) ({i}/6)", active=False))
ph_l.append(ph("work", "Stufe 7/7: 4 min auf maximale Strecke", "Step 7/7: 4 min for maximum distance",
               t=240, spm=(28, 36), hr=5, pace=(-6, -2)))
ph_l.append(cool(480))
P.append(plan("stufentest-7x4",
    L("Stufentest 7 x 4 min mit Maximalstufe", "Step test 7 x 4 min with maximal step"),
    L("Sechs Stufen zu 4 Minuten mit steigender Leistung und 1 Minute Pause, als siebte Stufe 4 Minuten auf maximale Strecke.", "Six 4-minute steps of rising power with 1 minute rest, then a seventh step of 4 minutes for maximum distance."),
    L("Leistungsdiagnostik wie im Spitzenrudern: Schwellen, Puls-Leistungs-Kurve und maximale aerobe Leistung (Pulszone 1-5)", "Performance diagnostics as used in elite rowing: thresholds, heart rate-power curve and maximal aerobic power (zone 1-5)"),
    "P", "T", ["hard", "threshold", "vo2max", "progressive", "ladder", "benchmark"],
    [LIND, KASS, C2_4MIN],
    "angepasst: Lindenthaler/Rice et al. (7 Stufen à 4 min, 1 min Pause, Stufen 1-6 aus der 2k-Saisonbestzeit, Stufe 7 = 4-min-Zeitfahren); die Stufenleistungen nennt die Quelle nicht: hier oberste submaximale Stufe 2k-Split +8 s, darunter je -20 W (in Anlehnung an Kass & Carpenter), umgerechnet mit Watt ~ 1/Pace^3 für 2:00/500 m",
    ph_l))

P.append(plan("einsteiger-test-10min",
    L("Einsteiger-Test 10 Minuten", "Beginner test 10 minutes"),
    L("Zehn Minuten so weit wie möglich in einem Tempo, das man durchhält; die Strecke ist der Startwert für spätere Vergleiche.", "Ten minutes as far as possible at a pace you can sustain; the distance is your baseline for later comparisons."),
    L("Erster Leistungstest ohne 2k-Bestzeit, aerob bis Schwelle (Pulszone 3-4)", "First fitness test without a 2k best, aerobic to threshold (zone 3-4)"),
    "E", "T", ["moderate", "aerobic", "benchmark", "beginner-friendly", "time-efficient", "negative-split"],
    [C2_PACE, C2_2K4],
    "angepasst: Concept2 'How to find your 2k pace' (locker beginnen in einem Tempo, das man sicher halten kann, zweite Hälfte nur bei gutem Gefühl steigern, Test alle 1-2 Wochen wiederholen) und Concept2-Einrudern; 10 min als Dauer eigene Wahl (kein Ranglistenstück); bewusst ohne Tempovorgabe",
    [ph("warmup", "Einrudern 5 min: locker, steigernd", "Warm-up 5 min: easy, building", t=300, spm=(18, 22), hr=2),
     ph("rest", "Kurz locker paddeln, dann Test starten", "Paddle easy briefly, then start the test", t=60, spm=(16, 20), hr=1, active=True),
     ph("work", "Minute 0-5: ruhig beginnen, Tempo finden, das man halten kann", "Minutes 0-5: start calmly, find a pace you can hold", t=300, spm=(20, 26), hr=3),
     ph("work", "Minute 5-10: halten, ab Minute 8 steigern, wenn es geht", "Minutes 5-10: hold, build from minute 8 if you can", t=300, spm=(22, 28), hr=4),
     cool(300)]))

# ---------- WETTKAMPF ----------
P.append(plan("rennsimulation-2000m-taktik",
    L("2000-m-Rennsimulation mit Taktik", "2000 m race simulation with tactics"),
    L("2000 m wie im Rennen: schneller Start über 250 m, auf Zieltempo setzen, drittes Viertel halten, Endspurt auf den letzten 500 m.", "2000 m as in a race: fast start over 250 m, settle to target pace, hold through the third quarter, sprint the last 500 m."),
    L("Renntaktik üben, Wettkampfleistung (Pulszone 5)", "Practise race tactics, race performance (zone 5)"),
    "P", "W", ["max", "vo2max", "anaerobic", "race-pace"],
    [GARLAND, C2_FLY, WR_HAY, C2_2K4],
    "angepasst: Garland (Ergometer: erste 500 m ~101,5 % der mittleren Geschwindigkeit, dann 99,8/99,0/99,7 %), Concept2 'Fly and Die' (kurze Startschläge, 10 harte Schläge, nach 10-15 Schlägen auf Zieltempo setzen bei 30-34 spm, drittes Viertel am härtesten, letzte 250 m steigern, letzte 100 m Power 10), Hay (Geduld auf den ersten 1000 m); Abschnittslängen und Offsets eigene Umsetzung. Ersetzt nicht den Test 2000 m (test-2000m), sondern übt den Ablauf",
    [ph("warmup", "Einrudern 10 min: steigernd, am Ende 3 Antritte", "Warm-up 10 min: building, 3 bursts at the end", t=600, spm=(18, 28), hr=2),
     ph("rest", "3 min locker, Startposition einnehmen", "3 min easy, get into start position", t=180, spm=(16, 20), hr=1, active=True),
     ph("work", "Start 250 m: halbe, halbe, dreiviertel Schlag, 10 harte Schläge, dann setzen", "Start 250 m: half, half, three-quarter stroke, 10 hard strokes, then settle", d=250, spm=(34, 40), hr=5, pace=(-5, -2)),
     ph("work", "250-1000 m: auf Zieltempo setzen, geduldig bleiben", "250-1000 m: settle to target pace, stay patient", d=750, spm=(30, 34), hr=5, pace=(-1, 1)),
     ph("work", "1000-1500 m: drittes Viertel, Tempo halten (der härteste Teil)", "1000-1500 m: third quarter, hold the pace (the hardest part)", d=500, spm=(30, 34), hr=5, pace=(0, 2)),
     ph("work", "1500-1750 m: Endspurt vorbereiten, Schlagzahl anheben", "1500-1750 m: set up the sprint, lift the rate", d=250, spm=(32, 36), hr=5, pace=(-2, 0)),
     ph("work", "Letzte 250 m: Endspurt, letzte 100 m Power 10", "Last 250 m: sprint, Power 10 over the last 100 m", d=250, spm=(34, 40), hr=5, pace=(-5, -2)),
     cool(600)]))

P.append(plan("renntempo-4x500-2000m",
    L("2000 m in 4 x 500 m mit Ziel-Splits", "2000 m as 4 x 500 m with target splits"),
    L("Die 2000 m in vier Stücke zu 500 m mit je 1 Minute Pause zerlegt; jedes Stück im Split des Rennplans.", "The 2000 m broken into four 500 m pieces with 1 minute rest each; every piece at the split of the race plan."),
    L("Renntempo und Rennplan einüben, Zieltempo für den 2000-m-Test festigen (Pulszone 5)", "Rehearse race pace and race plan, lock in the target pace for the 2000 m test (zone 5)"),
    "F", "W", ["hard", "vo2max", "race-pace", "time-efficient"],
    [C2_500, C2_2K4, GARLAND, C2_PACE],
    "angepasst: Concept2 500-m-Plan (4 x 500 m, 2 min Pause, Schlagzahl 26-36) mit 1 min Pause renn­näher gemacht; Splits nach Concept2-Rennplan (konstant bzw. 1-2 s langsamer beginnen, letzte 500 m zulegen) und Garland (Ergometerprofil)".replace("­", ""),
    [warm_long(480),
     ph("work", "500 m (1/4): wie Rennbeginn, Zielsplit halten", "500 m (1/4): like the race start, hold target split", d=500, spm=(30, 34), hr=5, pace=(-1, 1)),
     rest(60, "Pause 1 min: locker weiterrudern (1/3)", "Rest 1 min: keep rowing easy (1/3)"),
     ph("work", "500 m (2/4): Zielsplit, Rhythmus finden", "500 m (2/4): target split, find the rhythm", d=500, spm=(28, 32), hr=5, pace=(0, 2)),
     rest(60, "Pause 1 min: locker weiterrudern (2/3)", "Rest 1 min: keep rowing easy (2/3)"),
     ph("work", "500 m (3/4): Zielsplit halten, nicht nachlassen", "500 m (3/4): hold the target split, don't fade", d=500, spm=(28, 32), hr=5, pace=(0, 2)),
     rest(60, "Pause 1 min: locker weiterrudern (3/3)", "Rest 1 min: keep rowing easy (3/3)"),
     ph("work", "500 m (4/4): Endspurt, schneller als Zielsplit", "500 m (4/4): sprint, faster than target split", d=500, spm=(32, 38), hr=5, pace=(-4, -1)),
     cool(480)]))

ph_r = [warm_long(600)]
for i in range(1, 4):
    ph_r.append(ph("work", f"Start und erste 500 m ({i}/3): Startschläge, dann hoch im Renntempo",
                   f"Start and first 500 m ({i}/3): start strokes, then high at race pace", d=500, spm=(32, 36), hr=5, pace=(-3, -1)))
    ph_r.append(ph("work", f"Mittelstück 1000 m ({i}/3): Schlagzahl senken, Rhythmus halten",
                   f"Middle 1000 m ({i}/3): drop the rate, hold the rhythm", d=1000, spm=(28, 32), hr=5, pace=(1, 3)))
    if i < 3:
        ph_r.append(rest(300, f"Pause 5 min: locker weiterrudern ({i}/2)", f"Rest 5 min: keep rowing easy ({i}/2)"))
ph_r.append(cool(600))
P.append(plan("rennvorbereitung-3x-start-1000",
    L("Rennvorbereitung 3 x (Start + 1000 m)", "Race prep 3 x (start + 1000 m)"),
    L("Dreimal 500 m mit Start im Renntempo, direkt gefolgt von 1000 m Mittelstück knapp unter Renntempo; 5 Minuten Pause zwischen den Runden.", "Three rounds of a 500 m start piece at race pace flowing straight into a 1000 m middle section just below race pace; 5 minutes rest between rounds."),
    L("Übergang vom Start ins Mittelstück üben, Renntempo-Ausdauer (Pulszone 5)", "Practise the transition from start to middle section, race-pace endurance (zone 5)"),
    "P", "W", ["max", "vo2max", "anaerobic", "race-pace"],
    [C2_500, WR_HAY, C2_FLY, USR],
    "abgeleitet: Aufbau eigene Umsetzung der Rennphasen Start - Setzen - Mittelstück (USRowing; Concept2 'Fly and Die': nach 10-15 Schlägen setzen bei 30-34 spm; Hay: Geduld auf den ersten 1000 m); Pausenlänge angelehnt an Concept2 3 x 1000 m mit 3 min Pause, hier 5 min wegen 1500 m Belastung",
    ph_r))

P.append(plan("renntempo-2x1000",
    L("Renntempo 2 x 1000 m", "Race pace 2 x 1000 m"),
    L("Zweimal 1000 m im Zieltempo für das 2000-m-Rennen, 5 Minuten lockere Pause.", "Two 1000 m pieces at your target 2000 m race pace, 5 minutes easy rest."),
    L("Renntempo festigen, Tempogefühl für den 2000-m-Test (Pulszone 5)", "Lock in race pace, pace feel for the 2000 m test (zone 5)"),
    "F", "W", ["hard", "vo2max", "race-pace", "time-efficient"],
    [C2_500, C2_2K4, C2_PACE],
    "angepasst: Concept2 500-m- und 2k-Pläne (3 x 1000 m mit 3 min Pause, Schlagzahl 24-34; Zieltempo aus dem eigenen Durchschnittstempo); auf 2 Stücke mit 5 min Pause gekürzt, Tempo auf 2k-Zieltempo gesetzt",
    [warm_long(480),
     ph("work", "1000 m im 2k-Zieltempo (1/2): gleichmässig", "1000 m at 2k target pace (1/2): even", d=1000, spm=(28, 32), hr=5, pace=(-1, 1)),
     rest(300, "Pause 5 min: locker weiterrudern (1/1)", "Rest 5 min: keep rowing easy (1/1)"),
     ph("work", "1000 m im 2k-Zieltempo (2/2): letzte 250 m steigern", "1000 m at 2k target pace (2/2): build over the last 250 m", d=1000, spm=(28, 34), hr=5, pace=(-1, 1)),
     cool(420)]))

ph_t = [warm_long(480),
        ph("work", "10 min ruhig im Grundlagentempo", "10 min steady at base pace", t=600, spm=(18, 22), hr=2, pace=(18, 24))]
for i in range(1, 4):
    ph_t.append(ph("work", f"1 min im Renntempo ({i}/3)", f"1 min at race pace ({i}/3)", t=60, spm=(28, 32), hr=4, pace=(-1, 1)))
    ph_t.append(rest(120, f"Pause 2 min: locker weiterrudern ({i}/3)", f"Rest 2 min: keep rowing easy ({i}/3)"))
for i in range(1, 3):
    ph_t.append(ph("work", f"Startübung 15 s: halbe, halbe, dreiviertel Schlag, dann 5 volle ({i}/2)",
                   f"Start practice 15 s: half, half, three-quarter stroke, then 5 full ({i}/2)", t=15, spm=(34, 40), hr=4, pace=(-6, -3)))
    ph_t.append(rest(105, f"Pause: locker weiterrudern ({i}/2)", f"Rest: keep rowing easy ({i}/2)"))
ph_t.append(cool(300))
P.append(plan("tapering-vor-test",
    L("Tapering-Einheit vor Test oder Rennen", "Taper session before a test or race"),
    L("Kurze, lockere Einheit für die letzten 1-2 Tage vor einem Test: wenig Umfang, aber ein paar Minuten im Renntempo und zwei Startübungen.", "A short, easy session for the last 1-2 days before a test: little volume, but a few minutes at race pace and two start drills."),
    L("Frisch werden und Renntempo wachhalten (Umfang runter, Intensität halten; Pulszone 2-4)", "Freshen up and keep race pace sharp (volume down, intensity kept; zone 2-4)"),
    "F", "W", ["easy", "recovery", "race-pace"],
    [BOSQ, C2_2K4, C2_FLY],
    "abgeleitet: Bosquet et al. (Tapering wirkt am besten mit ca. 2 Wochen und 41-60 % weniger Umfang bei gleicher Intensität und Häufigkeit) als Prinzip; konkrete Einheit eigene Umsetzung mit Concept2-Einrudern und Startschlägen nach 'Fly and Die'. Die Concept2-Pläne selbst sehen kein Tapering vor",
    ph_t))

ph_e = [ph("warmup", "5 min ganz locker", "5 min very easy", t=300, spm=(18, 20), hr=1),
        ph("warmup", "5 min steigernd bis zügig", "5 min building to brisk", t=300, spm=(20, 24), hr=3)]
pieces = [(40, "20 kräftige Schläge", "20 strong strokes", (28, 30), (2, 5), 4),
          (40, "20 kräftige Schläge", "20 strong strokes", (28, 30), (1, 3), 4),
          (40, "20 Schläge nahe Renntempo", "20 strokes near race pace", (30, 32), (0, 2), 4),
          (20, "10 Schläge im Renntempo", "10 strokes at race pace", (30, 34), (-1, 1), 5),
          (20, "10 Schläge Start: halbe, halbe, dreiviertel, dann voll", "10 strokes start: half, half, three-quarter, then full", (34, 40), (-5, -2), 5),
          (20, "10 Schläge Start wie im Rennen", "10 strokes race start", (34, 40), (-5, -2), 5),
          (20, "10 Schläge im Renntempo: lang und rhythmisch", "10 strokes at race pace: long and rhythmic", (30, 34), (-1, 1), 5)]
for i, (t, de, en, spm, pace, z) in enumerate(pieces, 1):
    ph_e.append(ph("work", f"{de} ({i}/7)", f"{en} ({i}/7)", t=t, spm=spm, hr=z, pace=pace))
    if i < 7:
        ph_e.append(rest(90 if t == 40 else 70, f"Pause: locker paddeln ({i}/6)", f"Rest: paddle easy ({i}/6)"))
ph_e.append(ph("cooldown", "10 min bis zum Start: locker paddeln oder stehen, trinken, Monitor einstellen",
               "10 min to the start: paddle easy or stand, drink, set up the monitor", t=600, spm=(14, 18), hr=1))
P.append(plan("einrudern-rennen",
    L("Einrudern vor dem Rennen", "Pre-race warm-up"),
    L("Festes Einrudern-Protokoll vor einem Test oder Indoor-Rennen: 10 min steigernd, dann rund 100 harte Schläge in Stücken zu 20 und 10 mit Startübungen; das letzte Stück endet 10 Minuten vor dem Start.", "A fixed warm-up routine before a test or indoor race: 10 min building, then about 100 hard strokes in pieces of 20 and 10 with start drills; the last piece ends 10 minutes before the start."),
    L("Körper und Puls auf Rennbelastung vorbereiten, Startablauf einüben (Pulszone 1-5)", "Prepare body and heart rate for race effort, rehearse the start (zone 1-5)"),
    "E", "W", ["moderate", "power", "race-pace", "beginner-friendly"],
    [C2_WARM, BR_WARM, C2_2K4],
    "angepasst: Concept2 'A First Class Warm-up' (mindestens 100 harte Schläge in 10ern und 20ern mit lockerem Rudern dazwischen, letztes Stück 10 min vor dem Start, am liebsten 10 lange Schläge im Renntempo); British Rowing (nur Suchauszug: Einrudern am Renntag insgesamt rund 45 min, viel aerober Anteil, Routine vorher üben) und Concept2 2k-Plan (5-10 min steigernd mit Antritten); Schlagdauern bei 28-34 spm in Sekunden umgerechnet; für Indoor auf rund 30 min gekürzt",
    ph_e))

P.append(plan("head-race-5000m",
    L("Head-Race-Simulation 5000 m", "Head race simulation 5000 m"),
    L("5000 m wie ein Langstreckenrennen: fliegender Start mit hoher Schlagzahl, dann setzen und gleichmässig nahe der Schwelle, letzter Kilometer steigernd, letzte 500 m Endspurt.", "5000 m like a head race: flying start at a high rate, then settle and row evenly near threshold, build over the last kilometre, sprint the last 500 m."),
    L("Langstreckenrennen üben, Leistung an der Schwelle (Pulszone 4-5)", "Practise head racing, power at threshold (zone 4-5)"),
    "P", "W", ["hard", "threshold", "race-pace"],
    [USR, C2_5K, WR_HAY, PAUL],
    "abgeleitet: Rennphasen Start - Setzen - Endspurt und Head-Race-Format (USRowing, ca. 2,5-3 Meilen, Einzelstart), Taktik und Schlagzahl wie 2000 m nur bewusster gewählt (Hay), Concept2 5k-Plan (Renntempo halten, letzten Kilometer steigern, 24-30 spm); Tempo aus Paul's Law (5k = 2k +6-7 s); Abschnitte eigene Umsetzung",
    [warm_long(600),
     ph("rest", "2 min locker, dann fliegender Start", "2 min easy, then a flying start", t=120, spm=(18, 22), hr=2, active=True),
     ph("work", "Start 250 m: hoch und hart, nach rund 30 Schlägen setzen", "Start 250 m: high and hard, settle after about 30 strokes", d=250, spm=(30, 34), hr=4, pace=(1, 4)),
     ph("work", "250-2000 m: Grundtempo, lang und ruhig", "250-2000 m: base pace, long and calm", d=1750, spm=(26, 30), hr=4, pace=(5, 8)),
     ph("work", "2000-3500 m: Grundtempo halten, alle 500 m 10 Schläge Druck", "2000-3500 m: hold base pace, 10 strokes of pressure every 500 m", d=1500, spm=(26, 30), hr=4, pace=(5, 8)),
     ph("work", "3500-4500 m: steigern, Schlagzahl anheben", "3500-4500 m: build, lift the rate", d=1000, spm=(28, 32), hr=5, pace=(3, 6)),
     ph("work", "Letzte 500 m: Endspurt", "Last 500 m: sprint", d=500, spm=(30, 36), hr=5, pace=(0, 3)),
     cool(480)]))

# ---------- Prüfung ----------
TAGS = {"easy", "moderate", "hard", "max", "aerobic", "threshold", "vo2max", "anaerobic", "power", "technique", "recovery",
        "pyramid", "ladder", "rate-ladder", "rate-cap", "progressive", "negative-split", "fartlek", "over-under", "race-pace",
        "benchmark", "c2-ranked", "beginner-friendly", "time-efficient"}
ids = set()
for p in P:
    assert p["id"] not in ids, p["id"]; ids.add(p["id"])
    assert set(p["tags"]) <= TAGS, (p["id"], set(p["tags"]) - TAGS)
    assert sum(t in p["tags"] for t in ("easy", "moderate", "hard", "max")) == 1, p["id"]
    for f in p["phases"]:
        assert ("durationS" in f) != ("distanceM" in f), (p["id"], f)

def est(p, ref=120.0):
    """grobe Dauer in s: Distanzphasen mit Referenzsplit + Offset (Mitte), ohne Offset +20 s."""
    s = 0
    for f in p["phases"]:
        if "durationS" in f: s += f["durationS"]
        else:
            off = (f.get("paceOffsetMinS", 20) + f.get("paceOffsetMaxS", 20)) / 2
            s += f["distanceM"] / 500 * (ref + off)
    return s

# time-efficient check
for p in P:
    m = est(p) / 60
    print("TE", p["id"], round(m,1)) if ("time-efficient" in p["tags"]) != (m <= 30.5) else None

OUT.joinpath("tests.json").write_text(json.dumps(P, ensure_ascii=False, indent=1) + "\n")

# ---------- Markdown ----------
def fmt_t(s):
    return f"{int(s)//60}:{int(s)%60:02d} min"
def pace(f):
    if "paceOffsetMinS" not in f: return "-"
    a, b = f["paceOffsetMinS"], f["paceOffsetMaxS"]
    sg = lambda x: f"+{x}" if x > 0 else str(x)
    return f"2k {sg(a)}..{sg(b)} s/500 m"

md = []
md.append("# Familie `tests`: Test- und Wettkampfprogramme für RowCoach\n")
md.append("Stand 26.11.2026. 20 neue Programme in den Kategorien Test (13) und Wettkampf (7), Datei `tests.json`. "
          "Ergänzt `test-2000m` (nicht gedoppelt; die Rennsimulation mit Taktik und die 4 x 500 m üben den Ablauf, sie ersetzen den Test nicht).\n")
md.append("## Methode\n")
md.append("- Recherche-Reihenfolge Zotero → Fundus → Web. **Zotero**: `zrag search` lieferte nur unbetitelte Transkript-Notizen ohne Bezug; danach war der Zotero-MCP-Server nicht erreichbar (Connection refused auf :8000), `zrag semantic` brach ab. Kein Zotero-Beleg. "
          "**Fundus** (Projekt `rowcoach`): vorhanden waren Concept2-4-Wochen-2k-Plan, Wolfson-Zonen, Seiler/Tønnessen, 30-and-Out; zu Tests, Stufentests, Tapering, Renneinrudern nichts. **Web**: Primärquellen Concept2 (Testpläne 500 m, 4 min, 5k, 2k, Rangliste, Pacing-Artikel), World Rowing (Jensen, Hay), USRowing, Studien (Garland 2005, Kass & Carpenter, Lindenthaler/Rice 2018, Bosquet 2007).\n"
          "- **Tempo der Tests**: Prognose aus der 2k-Bestzeit auf zwei Wegen: (a) Jensen/World Rowing: mittlere Watt in % der 2000-m-Watt (60 min ~76 %, 6000 m ~85 %, 60 s ~153 %, 10 s/100 m ~173 %), umgerechnet mit Watt ~ 1/Pace^3 bei Referenz 2:00/500 m; (b) Paul's Law (Concept2-Forum, Sekundärquelle): pro Verdopplung der Strecke +5 s/500 m, d. h. Offset = 5 · log2(Strecke/2000). Das Fenster liegt jeweils rund ±1,5 s um den Prognosewert. Im Forum wird betont, dass die Konstante individuell 3-7 s beträgt (Sprinter mehr, Ausdauertypen weniger); die Werte sind also Zielhilfen, kein Muss. Bei Zeittests (1 min, 4 min, 30 min, 60 min) gibt es keine Obergrenze: die Strecke ist das Ergebnis, der Tempokorridor nur Orientierung.\n"
          "- **Stufentests**: Kass & Carpenter geben das Schema genau an (oberste Stufe 2k-Split +10 s, darunter je -25 W). Feste Watt-Abstände ergeben je nach Leistungsniveau andere Pace-Abstände; die Offsets gelten für einen 2k-Split von 2:00. Eine spätere App-Version sollte die Stufen in Watt rechnen.\n"
          "- **Einrudern**: Concept2 (alle Testpläne): 5-10 min locker beginnen, bis mittlere Intensität steigern, am Ende ein paar kurze Antritte. Kurztests (bis 4 min) haben hier zusätzlich eine 2-min-Antrittsphase und 2 min Pause vor dem Start, lange Tests 10 min Einrudern.\n"
          "- Lokales Modell nicht benutzt (Texte direkt geschrieben).\n")
md.append("## Pulszonen\n")
md.append("Concept2-5-Zonen-Modell in % HFmax wie im BRIEF: 1 < 65 (Regeneration), 2 65-75 (UT2), 3 75-80/85 (UT1), 4 80/85-90 (AT/Schwelle), 5 > 90 (TR/AN). "
          "Bei sehr kurzen Tests (100 m, 1 min) steht Zone 5 für die Belastungsart; der Puls erreicht sie erst gegen Ende oder danach.\n")
md.append("## Nicht abrufbar / Unsicherheiten\n")
md.append("- British Rowing (britishrowing.org, plus.britishrowing.org): 403 bzw. Weiterleitung auf die Startseite. Das Renn-Einrudern (J. Brown) und 'The science behind the perfect 2k test' konnten nicht gelesen werden; British Rowing ist beim Einrudern nur mit einem Suchauszug belegt (als solcher gekennzeichnet). Einen offiziellen British-Rowing-Stufentest mit 3-min-Stufen habe ich nicht gefunden; belegt sind 4-min-Stufen (Kass & Carpenter; Lindenthaler/Rice, AIS-Umfeld).\n"
          "- Concept2-Rangliste: die RowErg-Auswahl auf log.concept2.com/rankings enthält 1000 m; die Concept2-FAQ (laut Suchauszug) listet 1000 m nicht für RowErg. Ich folge der Ranglistenseite.\n"
          "- Faster Masters (Head-Race-Rennpläne) war im Wartungsmodus; die Head-Race-Simulation stützt sich deshalb auf USRowing, Concept2 und World Rowing und ist als 'abgeleitet' markiert.\n"
          "- '6000 m als Wintertest bei Junioren und Masters' ist Vereinsbrauch und nicht belegt; belegt ist 6000 m als Standardtest (Jensen) und Ranglistenstück.\n"
          "- Halbmarathon und Marathon nicht als Test aufgenommen (Überschneidung mit der Familie `grundlage`).\n"
          "- Lindenthaler/Rice nennen die Leistung der Stufen 1-6 nicht; `stufentest-7x4` setzt sie nach dem Kass-Schema (dort als 'angepasst' vermerkt).\n")

for p in P:
    md.append(f"## {p['name']['de']} (`{p['id']}`)\n")
    md.append(f"- Erklärung: {p['summary']['de']}")
    md.append(f"- Zweck/Bereich: {p['purpose']['de']}")
    md.append(f"- Kategorie: {p['category']['de']}; Niveau: {p['level']['de']}; Tags: {', '.join(p['tags'])}")
    md.append(f"- Belegstatus: {p['evidence']}")
    md.append("- Quellen: " + "; ".join(f"{s['publisher']} - {s['title']}" for s in p["sources"]))
    md.append(f"- Ungefähre Dauer: {round(est(p)/60)} min (Distanzphasen mit 2:00/500 m Referenz geschätzt)\n")
    md.append("| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |")
    md.append("|---|---|---|---|---|---|---|")
    for f in p["phases"]:
        dd = fmt_t(f["durationS"]) if "durationS" in f else f"{f['distanceM']} m"
        spm = f"{f['spmMin']}-{f['spmMax']}" if "spmMin" in f else "-"
        pa = "-" if f["kind"] != "rest" else ("aktiv" if f.get("activeRest") else "stehen")
        md.append(f"| {f['kind']} | {dd} | {spm} | {f.get('hrZone','-')} | {pace(f)} | {pa} | {f['label']['de']} |")
    md.append("")

md.append("## Quellenliste\n")
seen = {}
for p in P:
    for s in p["sources"]:
        seen.setdefault(s["url"], s)
for s in seen.values():
    md.append(f"- {s['publisher']}: {s['title']}. {s['url']} ({s['published'] or 'ohne Datum auf der Seite'})")
OUT.joinpath("tests.md").write_text("\n".join(md) + "\n")

for p in P:
    kinds = "Zeit" if all("durationS" in f for f in p["phases"] if f["kind"] == "work") else ("Distanz" if all("distanceM" in f for f in p["phases"] if f["kind"] == "work") else "gemischt")
    print(f"{p['id']} | {p['name']['de']} | {p['category']['de']} | {p['level']['de']} | {kinds} | {round(est(p)/60)} min")
