#!/usr/bin/env python3
"""Ergänzt docs/plans-new/grundlage.json und grundlage.md um die Programme, die die Recherche zu den
Trainingsplänen (docs/trainingsplaene/RECHERCHE.md, Abschnitt 3.1) als fehlend gemeldet hat.

Aufruf (im Repo-Wurzelordner): python3 docs/plans-new/generators/gen_grundlage_ergaenzung.py
Idempotent: vorhandene Programme mit derselben id werden ersetzt, der Abschnitt in grundlage.md neu geschrieben.
Danach: python3 App/l10n/merge_plans.py
"""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
JSON = ROOT / "docs/plans-new/grundlage.json"
MD = ROOT / "docs/plans-new/grundlage.md"
MARK_START = "<!-- ergaenzung-trainingsplaene:start -->"
MARK_END = "<!-- ergaenzung-trainingsplaene:end -->"

progs = json.loads(JSON.read_text())
by_id = {p["id"]: p for p in progs}


def T(de, en):
    return {"de": de, "en": en}


def source_like(prog_id, prefix):
    """Quelle aus einem vorhandenen Programm übernehmen (gleicher Wortlaut wie dort)"""
    for s in by_id[prog_id]["sources"]:
        if s["title"].startswith(prefix):
            return copy.deepcopy(s)
    raise KeyError(f"{prog_id}: {prefix}")


SRC_C2_HM = source_like("grundlage-10000m-ut2", "Half Marathon Row Training Plan")
SRC_WOLFSON = source_like("langdistanz-ut2-90", "Erging (Wolfson")
SRC_SEILER = source_like("langdistanz-ut2-90", "Intervals, Thresholds")
SRC_C2_HR = source_like("langdistanz-ut2-90", "Heart Rate Training")
SRC_FASTER = source_like("grundlage-10000m-ut2", "How to Set Target Erg Splits")
SRC_C2_MAR = source_like("langdistanz-marathon", "Marathon Row Training Plan")
SRC_C2C = source_like("einsteiger-1-2-3-2-1", "Beginner's Training Plan")
SRC_PETE_BEG = source_like("grundlage-5000m-ut2", "Beginner Training (Beginner Pete Plan")
SRC_BR_BEG = {"title": "Go Row Indoor – Beginner Training Plan (8 weeks; week 1: 5 x 1 min and 2 x 5 min easy, rate 18-24, damper 4 or lower)",
              "publisher": "British Rowing",
              "url": "https://www.britishrowing.org/wp-content/uploads/2016/10/BR_Go_Row_A4_Beginners_Training_Plan_P3.pdf",
              "published": "2016-10", "zotero": None}

WARM = {"kind": "warmup", "durationS": 480, "spmMin": 18, "spmMax": 22, "hrZone": 2,
        "label": T("Einrudern: locker, steigernd, am Ende kurze Antritte", "Warm-up: easy, building, a few short bursts at the end")}
WARM5 = dict(WARM, durationS=300)
COOL = {"kind": "cooldown", "durationS": 300, "spmMin": 16, "spmMax": 20, "hrZone": 1,
        "label": T("Ausrudern: ganz locker", "Cool-down: very easy")}
DRINK = {"kind": "rest", "durationS": 60, "hrZone": 1, "activeRest": False,
         "label": T("Pause: stehen, trinken (und essen)", "Rest: stop, drink (and eat)")}
UT2 = {"spmMin": 18, "spmMax": 20, "hrZone": 2, "paceOffsetMinS": 25, "paceOffsetMaxS": 30}
UT2_DIST = {"spmMin": 18, "spmMax": 22, "hrZone": 2, "paceOffsetMinS": 25, "paceOffsetMaxS": 30}
PACE_NOTE = "Pace-Offset abgeleitet aus Concept2-Tabelle (relativ zum 5k-Tempo) und 5k = 2k + 7-8 s (Faster Masters)"


def blocks(n):
    out = [copy.deepcopy(WARM)]
    for i in range(1, n + 1):
        out.append(dict(kind="work", durationS=1800, **UT2,
                        label=T(f"Block UT2 30 min, Schlagzahl 18-20 ({i}/{n})", f"UT2 block 30 min, rate 18-20 ({i}/{n})")))
        if i < n:
            out.append(copy.deepcopy(DRINK))
    out.append(copy.deepcopy(COOL))
    return out


def beginner_first():
    out = [{"kind": "warmup", "durationS": 60, "spmMin": 16, "spmMax": 20, "hrZone": 1,
            "label": T("Einrudern (1 min): nur Arme und Körper, dann ganze Schläge", "Warm-up (1 min): arms and body only, then full strokes")}]
    for i in range(1, 6):
        out.append({"kind": "work", "durationS": 60, "spmMin": 18, "spmMax": 24, "hrZone": 2,
                    "label": T(f"1 min locker rudern ({i}/5)", f"1 min easy rowing ({i}/5)")})
        if i < 5:
            out.append({"kind": "rest", "durationS": 60, "hrZone": 1, "activeRest": False,
                        "label": T("Pause 1 min: stehen, durchatmen", "Rest 1 min: stop and breathe")})
    out.append({"kind": "rest", "durationS": 180, "hrZone": 1, "activeRest": False,
                "label": T("Pause 3 min: stehen, trinken", "Rest 3 min: stop, have a drink")})
    for i in (1, 2):
        out.append({"kind": "work", "durationS": 300, "spmMin": 18, "spmMax": 22, "hrZone": 2,
                    "label": T(f"5 min locker und gleichmässig ({i}/2)", f"5 min easy and even ({i}/2)")})
        if i == 1:
            out.append({"kind": "rest", "durationS": 180, "hrZone": 1, "activeRest": False,
                        "label": T("Pause 3 min: stehen, durchatmen", "Rest 3 min: stop and breathe")})
    out.append({"kind": "cooldown", "durationS": 120, "spmMin": 16, "spmMax": 20, "hrZone": 1,
                "label": T("Ausrudern: ganz locker", "Cool-down: very easy")})
    return out


def distance(m):
    de_m = f"{m:,}".replace(",", " ")
    en_m = f"{m:,}"
    return [copy.deepcopy(WARM5),
            dict(kind="work", distanceM=m, **UT2_DIST,
                 label=T(f"{de_m} m UT2, Schlagzahl 18-22, gleichmässig", f"{en_m} m UT2, rate 18-22, even")),
            copy.deepcopy(COOL)]


NEW = [
    {
        "id": "einsteiger-5x1-2x5",
        "name": T("Erste Einheit: 5 x 1 und 2 x 5 Minuten", "First session: 5 x 1 and 2 x 5 minutes"),
        "summary": T("Die allererste Einheit: fünfmal 1 Minute locker rudern mit 1 Minute Pause, danach zweimal 5 Minuten locker mit 3 Minuten Pause. Rund 15 Minuten Rudern.",
                     "The very first session: five times 1 minute of easy rowing with 1 minute rest, then twice 5 minutes easy with 3 minutes rest. About 15 minutes of rowing."),
        "purpose": T("Gewöhnung an Gerät und Bewegung, sehr leicht (Puls ca. 50-70 % HFmax, Pulszone 1-2); Dämpfer auf 4 oder tiefer",
                     "Getting used to the rower and the movement, very easy (heart rate about 50-70 % of max, zones 1-2); damper at 4 or lower"),
        "level": T("Einsteiger", "Beginner"),
        "category": T("Grundlage", "Steady state"),
        "tags": ["easy", "aerobic", "beginner-friendly", "time-efficient"],
        "sources": [SRC_BR_BEG, SRC_C2C],
        "evidence": "angepasst: British Rowing Go Row Indoor Beginner, Woche 1 (5 x 1 min und 2 x 5 min locker, Schlagzahl 18-24, Dämpfer höchstens 4); Pausen 1 bzw. 3 min wie im Vorschlag der Plan-Recherche (RECHERCHE.md 3.1); Ein- und Ausrudern auf je 1-2 min gekürzt (kein langes Einrudern in der ersten Einheit)",
        "phases": beginner_first(),
    },
    {
        "id": "grundlage-locker-45",
        "name": T("Lockere Grundlage 45 Minuten", "Easy steady state 45 minutes"),
        "summary": T("45 Minuten gleichmässig im Gesprächstempo bei niedriger Schlagzahl, mit Ein- und Ausrudern.",
                     "45 minutes at an even, conversational pace at a low stroke rate, with warm-up and cool-down."),
        "purpose": T("UT2 / aerobe Grundlage, Gesprächstempo (Puls ca. 60-70 % HFmax, Pulszone 2)",
                     "UT2 / aerobic base, conversational pace (heart rate about 60-70 % of max, zone 2)"),
        "level": T("Fortgeschritten", "Advanced"),
        "category": T("Grundlage", "Steady state"),
        "tags": ["easy", "aerobic"],
        "sources": [SRC_WOLFSON, SRC_C2_HR, SRC_C2_HM, SRC_FASTER],
        "evidence": "angepasst: Wolfson (Ausdauereinheiten 60-90 min in Blöcken von 20-30 min, UT2 18-20 spm) als kürzere Form; Aufbau wie Lockere Grundlage 30 (5 min Ein-, 5 min Ausrudern); schliesst die Lücke zwischen 40 und 60 min. " + PACE_NOTE,
        "phases": [copy.deepcopy(WARM5),
                   dict(kind="work", durationS=2100, spmMin=18, spmMax=20, hrZone=2, paceOffsetMinS=25, paceOffsetMaxS=30,
                        label=T("Grundlage UT2 35 min, Gesprächstempo, Schlagzahl 18-20", "UT2 steady 35 min, conversational, rate 18-20")),
                   copy.deepcopy(COOL)],
    },
    {
        "id": "grundlage-6000m-ut2",
        "name": T("Grundlage 6000 m", "Steady 6,000 m"),
        "summary": T("6 km ruhig im UT2 bei Schlagzahl 18-22; Zwischenstufe zwischen 5000 und 8000 m.",
                     "6 km calmly at UT2 at rate 18-22; a step between 5,000 and 8,000 m."),
        "purpose": T("UT2 / aerobe Grundlage, Gesprächstempo (Puls ca. 60-70 % HFmax, Pulszone 2)",
                     "UT2 / aerobic base, conversational pace (heart rate about 60-70 % of max, zone 2)"),
        "level": T("Einsteiger", "Beginner"),
        "category": T("Grundlage", "Steady state"),
        "tags": ["easy", "aerobic", "c2-ranked"],
        "sources": [SRC_PETE_BEG, SRC_C2_HM, SRC_WOLFSON, SRC_FASTER],
        "evidence": "angepasst: Beginner Pete Plan (Grundlagenfahrt wächst um 500 m pro Woche von 5000 m an); Distanzstufe 6000 m statt frei wählbarer Distanz, Schlagzahl und Tempo wie Grundlage 10 000 m. " + PACE_NOTE,
        "phases": distance(6000),
    },
    {
        "id": "grundlage-12000m-ut2",
        "name": T("Grundlage 12 000 m", "Steady 12,000 m"),
        "summary": T("12 km ruhig im UT2 bei Schlagzahl 18-22; die längste Grundlagenfahrt im Beginner Pete Plan.",
                     "12 km calmly at UT2 at rate 18-22; the longest steady row in the Beginner Pete Plan."),
        "purpose": T("UT2 / aerobe Grundlage, Gesprächstempo (Puls ca. 60-70 % HFmax, Pulszone 2)",
                     "UT2 / aerobic base, conversational pace (heart rate about 60-70 % of max, zone 2)"),
        "level": T("Fortgeschritten", "Advanced"),
        "category": T("Grundlage", "Steady state"),
        "tags": ["easy", "aerobic"],
        "sources": [SRC_PETE_BEG, SRC_C2_HM, SRC_WOLFSON, SRC_FASTER],
        "evidence": "angepasst: Beginner Pete Plan (Grundlage 5000 m, +500 m pro Woche bis 12 000 m); Schlagzahl und Tempo wie Grundlage 10 000 m. " + PACE_NOTE,
        "phases": distance(12000),
    },
    {
        "id": "langdistanz-ut2-120",
        "name": T("Lange Grundlage 2 Stunden (4 x 30)", "Long steady state 2 hours (4 x 30)"),
        "summary": T("Zwei Stunden UT2 in vier Blöcken zu 30 Minuten bei Schlagzahl 18-20, kurze Trink- und Esspausen dazwischen (rund 24-26 km).",
                     "Two hours of UT2 in four 30-minute blocks at rate 18-20, with short breaks to drink and eat (about 24-26 km)."),
        "purpose": T("Lange aerobe Grundlage für Marathon und Langdistanz, Verpflegung üben (Puls ca. 60-70 % HFmax, Pulszone 2)",
                     "Long aerobic base for the marathon and long distance, practise fuelling (heart rate about 60-70 % of max, zone 2)"),
        "level": T("Leistung", "Performance"),
        "category": T("Langdistanz", "Long distance"),
        "tags": ["easy", "aerobic"],
        "sources": [SRC_C2_MAR, SRC_WOLFSON, SRC_SEILER, SRC_C2_HR, SRC_FASTER],
        "evidence": "angepasst: Concept2 Marathonplan (lange UT2-Fahrt wächst bis 28-34 km in den Wochen 9-12, UT2 = 5k-Tempo +18-22 s); Blöcke zu 30 min wie Wolfson (20-30-min-Blöcke); Pausen 1 min eigene Annahme. " + PACE_NOTE,
        "phases": blocks(4),
    },
    {
        "id": "langdistanz-ut2-150",
        "name": T("Lange Grundlage 2,5 Stunden (5 x 30)", "Long steady state 2.5 hours (5 x 30)"),
        "summary": T("Zweieinhalb Stunden UT2 in fünf Blöcken zu 30 Minuten bei Schlagzahl 18-20, Trink- und Esspausen dazwischen (rund 30-32 km). Längste Vorbereitungsfahrt vor dem Marathon.",
                     "Two and a half hours of UT2 in five 30-minute blocks at rate 18-20, with breaks to drink and eat (about 30-32 km). The longest preparation row before a marathon."),
        "purpose": T("Längste aerobe Einheit der Marathonvorbereitung, Verpflegung und Sitzen über lange Zeit üben (Puls ca. 60-70 % HFmax, Pulszone 2)",
                     "Longest aerobic session of marathon preparation, practise fuelling and sitting for a long time (heart rate about 60-70 % of max, zone 2)"),
        "level": T("Leistung", "Performance"),
        "category": T("Langdistanz", "Long distance"),
        "tags": ["easy", "aerobic"],
        "sources": [SRC_C2_MAR, SRC_WOLFSON, SRC_SEILER, SRC_C2_HR, SRC_FASTER],
        "evidence": "angepasst: Concept2 Marathonplan (längste Fahrten 32-34 km in den Wochen 11-12); Blöcke zu 30 min wie Wolfson; Pausen 1 min eigene Annahme. " + PACE_NOTE,
        "phases": blocks(5),
    },
    {
        "id": "langdistanz-hmp-50",
        "name": T("Halbmarathon-Tempo 50 Minuten", "Half marathon pace 50 minutes"),
        "summary": T("50 Minuten am Stück im angestrebten Halbmarathon- bzw. Marathontempo, mit Ein- und Ausrudern.",
                     "50 minutes continuously at your target half marathon or marathon pace, with warm-up and cool-down."),
        "purpose": T("Renntempo über lange Zeit halten, obere Grundlage bis knapp unter Schwelle (Puls ca. 75-85 % HFmax, Pulszone 3)",
                     "Hold race pace for a long time, upper aerobic range just below threshold (heart rate about 75-85 % of max, zone 3)"),
        "level": T("Fortgeschritten", "Advanced"),
        "category": T("Langdistanz", "Long distance"),
        "tags": ["moderate", "aerobic", "race-pace"],
        "sources": [SRC_C2_HM, SRC_C2_MAR, SRC_FASTER, SRC_C2_HR],
        "evidence": "direkt: Concept2 Halbmarathonplan (50 min im Halbmarathon-Tempo in der zweiten Planhälfte, HMP = 5k +8..12 s, 75-85 % HFmax) und Marathonplan (50 min im Marathontempo); Schlagzahl 22-26 wie Halbmarathon-Tempo 2 x 20; Pace-Offset abgeleitet mit 5k = 2k + 7-8 s",
        "phases": [copy.deepcopy(WARM),
                   {"kind": "work", "durationS": 3000, "spmMin": 22, "spmMax": 26, "hrZone": 3, "paceOffsetMinS": 15, "paceOffsetMaxS": 20,
                    "label": T("50 min im Halbmarathon-Tempo, Schlagzahl 22-26, gleichmässig", "50 min at half marathon pace, rate 22-26, even")},
                   dict(copy.deepcopy(COOL), durationS=360)],
    },
]

ids = {p["id"] for p in NEW}
progs = [p for p in progs if p["id"] not in ids] + NEW
JSON.write_text(json.dumps(progs, ensure_ascii=False, indent=2) + "\n")


# ---------------------------------------------------------------- grundlage.md
def fmt_len(ph):
    if "durationS" in ph:
        s = ph["durationS"]
        return f"{s // 60}:{s % 60:02d} min"
    return f"{ph['distanceM']:,} m".replace(",", " ")


def minutes(p):
    return sum(ph.get("durationS", ph.get("distanceM", 0) * 120 / 500) for ph in p["phases"]) / 60


lines = [MARK_START, "", "## Ergänzung 26.11.2026: Programme für die Trainingspläne", "",
         "Nachgetragen, weil die Plan-Recherche (`docs/trainingsplaene/RECHERCHE.md`, Abschnitt 3.1) diese Bausteine "
         "vermisst hat. Erzeugt mit `docs/plans-new/generators/gen_grundlage_ergaenzung.py`. Statt einer frei wählbaren "
         "Distanz (`grundlage-distanz`) gibt es die festen Stufen 6000 und 12 000 m (5000, 8000 und 10 000 m bestehen schon).", ""]
for p in NEW:
    lines += [f"### {p['name']['de']} (`{p['id']}`)", "",
              f"- Erklärung: {p['summary']['de']}",
              f"- Zweck/Bereich: {p['purpose']['de']}",
              f"- Niveau: {p['level']['de']} · Kategorie: {p['category']['de']} · Tags: {', '.join(p['tags'])}",
              f"- Belegstatus: {p['evidence']}",
              "- Quellen: " + "; ".join(f"{s['publisher']} - {s['title']}" for s in p["sources"]),
              f"- Geschätzte Dauer: ca. {minutes(p):.0f} min (Distanzphasen mit 2:00/500 m geschätzt)", "",
              "| Typ | Dauer/Distanz | spm | Pulszone | Tempo | Pause | Beschreibung |",
              "|---|---|---|---|---|---|---|"]
    for ph in p["phases"]:
        spm = f"{ph['spmMin']}-{ph['spmMax']}" if "spmMin" in ph else "-"
        pace = f"2k +{ph['paceOffsetMinS']}..+{ph['paceOffsetMaxS']} s/500 m" if "paceOffsetMinS" in ph else "-"
        rest = ("aktiv" if ph.get("activeRest") else "stehen") if ph["kind"] == "rest" else "-"
        lines.append(f"| {ph['kind']} | {fmt_len(ph)} | {spm} | {ph.get('hrZone', '-')} | {pace} | {rest} | {ph['label']['de']} |")
    lines.append("")
lines.append(MARK_END)
block = "\n".join(lines)

md = MD.read_text()
if MARK_START in md:
    a = md.index(MARK_START)
    b = md.index(MARK_END) + len(MARK_END)
    md = md[:a] + block + md[b:]
else:
    anchor = "## Quellenliste"
    md = md.replace(anchor, block + "\n\n" + anchor, 1)
if "Go Row Indoor" not in md.split("## Quellenliste")[-1]:
    md = md.rstrip("\n") + "\n- British Rowing: " + SRC_BR_BEG["title"] + ". " + SRC_BR_BEG["url"] + " (2016-10)\n"
MD.write_text(md)
print(f"{len(NEW)} Programme ergänzt: {', '.join(p['id'] for p in NEW)}")
