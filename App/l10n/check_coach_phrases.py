#!/usr/bin/env python3
"""Prüft App/RowCoach/Resources/coach_phrases.json gegen docs/coach/SPEC.md und docs/coach/PHRASES.md.

Prüfungen: gültiges JSON, alle Szenario-ids der SPEC vorhanden, je Stufe alle Stile (calm, motivating, cox) und
Sprachen (de, en), Mindestanzahlen (6, für Lob/Anfeuern/Countdown 10), Stufe 1 und 2 bei Eskalationsszenarien,
keine Duplikate, Variablen nur aus der SPEC-Liste und im Szenario deklariert, dynamische Szenarien mit genug
statischen Varianten, Länge (Rufe <= 6 Wörter, Vorbereitung/Info <= 15), TTS-Regeln (keine Ziffern, keine Emojis,
kein ß, keine Kürzel). Exit-Code 1 bei Fehlern, Warnungen nur zur Info.

Aufruf: python3 App/l10n/check_coach_phrases.py [pfad/zu/coach_phrases.json]
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PHRASES = ROOT / "App/RowCoach/Resources/coach_phrases.json"
SPEC = ROOT / "docs/coach/SPEC.md"

STYLES = ("calm", "motivating", "cox")
LANGS = ("de", "en")
SPEC_VARS = {"n", "of", "duration", "distance", "spm", "spm_min", "spm_max", "split", "delta"}
ONE_WORD_VARS = {"n", "of", "spm", "spm_min", "spm_max"}  # gesprochen ein Wort; die übrigen zählen als zwei

SCENARIOS = [
    "prep_hard", "go", "first_strokes", "phase_half", "last_quarter", "last_30s", "last_10s", "last_250m",
    "last_100m", "last_interval", "interval_done", "rest_recover", "rest_prepare", "workout_half",
    "workout_final", "workout_done", "fade_end", "fade_mid", "rate_low", "rate_high", "pace_on_target",
    "pace_too_fast_early", "pace_slow", "strong_finish", "consistent", "slower_than_prev", "best_interval",
    "hr_high_easy", "stopped", "rest_too_hard", "technique", "free_half", "free_500_left", "paceline_ahead",
    "paceline_behind", "post_ride",
]
ESCALATION = {"fade_end", "fade_mid", "pace_slow", "stopped", "rate_low", "rate_high"}
TWO_SITUATIONS = {"phase_half", "post_ride"}  # phase_half: 1 = im Ziel, 2 = hinter dem Ziel; post_ride: 1 = Dabeisein, 2 = Rekord
# Lob, Anfeuern, Endphase-Countdown, go, interval_done: mindestens 10 je Stil und Sprache (Auftrag 26.11.;
# nur Stufe 1, bei fade_end beide Stufen). Strukturansagen (last_quarter, last_250m …) brauchen nur 6.
MIN10 = {"go", "last_30s", "last_10s", "fade_end", "interval_done", "pace_on_target", "strong_finish",
         "pace_slow", "consistent", "best_interval", "workout_done", "post_ride"}
MIN10_LEVELS = {"fade_end": {"1", "2"}}
MIN10_STYLE_EXEMPT = set()  # (szenario, stil), falls ein Stil bewusst knapper sein soll
MIN = 6
MIN_STATIC_DYNAMIC = 6
# Rufe: höchstens 6 Wörter. Alle anderen (Vorbereitung, Information, Pause): höchstens 15.
SHORT = {"go", "last_30s", "last_10s", "last_250m", "last_100m", "fade_end", "fade_mid", "rate_low",
         "rate_high", "pace_on_target", "pace_slow", "strong_finish", "stopped", "phase_half", "last_quarter",
         "free_500_left", "workout_half"}
SHORT_MAX, LONG_MAX = 6, 15
SHORT_MAX_COX_CALM2 = 8  # Stufe 2 der Eskalation in calm darf etwas erklären

VAR_RE = re.compile(r"\{([a-z_]+)\}")
EMOJI_RE = re.compile("[\U0001F300-\U0001FAFF☀-➿]")
ABBREV_RE = re.compile(r"\b(SZ|HF|km/h|spm|bpm|s/500|\d+k)\b", re.I)


def words(text):
    n = 0
    for tok in text.replace("–", " ").replace("…", " ").split():
        m = VAR_RE.search(tok)
        if m:
            n += 1 if m.group(1) in ONE_WORD_VARS else 2
        elif re.search(r"\w", tok):
            n += 1
    return n


def spec_ids():
    text = SPEC.read_text(encoding="utf-8")
    part = text.split("## Szenarien", 1)[1].split("## Stile", 1)[0]
    return set(re.findall(r"`([a-z_0-9]+)`", part))


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else PHRASES
    errors, warnings = [], []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        print(f"FEHLER: kein gültiges JSON: {e}")
        return 1
    if data.get("version") != 1:
        errors.append("version muss 1 sein")
    scen = data.get("scenarios", {})

    ids = spec_ids()
    for missing in sorted(set(SCENARIOS) - ids):
        warnings.append(f"Szenario {missing} steht in der Prüfliste, aber nicht in der SPEC")
    for sid in sorted(ids | set(SCENARIOS)):
        if sid not in scen:
            errors.append(f"Szenario fehlt: {sid}")
    for sid in sorted(set(scen) - ids - set(SCENARIOS)):
        warnings.append(f"Szenario nicht in der SPEC: {sid}")

    totals = {s: 0 for s in STYLES}
    totals_lang = {lang: 0 for lang in LANGS}
    static_total = 0
    for sid, entry in scen.items():
        declared = set(entry.get("variables", []))
        if not declared <= SPEC_VARS:
            errors.append(f"{sid}: unbekannte Variablen deklariert {sorted(declared - SPEC_VARS)}")
        used_any = set()
        levels = entry.get("levels", {})
        need = {"1", "2"} if sid in ESCALATION | TWO_SITUATIONS else {"1"}
        for lv in sorted(need - set(levels)):
            errors.append(f"{sid}: Stufe {lv} fehlt")
        for lv, styles in levels.items():
            if lv not in {"1", "2"}:
                errors.append(f"{sid}: unbekannte Stufe {lv}")
            seen_level = {}
            for style in STYLES:
                if style not in styles:
                    errors.append(f"{sid}.{lv}: Stil {style} fehlt")
                    continue
                for lang in LANGS:
                    lst = styles[style].get(lang)
                    where = f"{sid}.{lv}.{style}.{lang}"
                    if not lst:
                        errors.append(f"{where}: fehlt oder leer")
                        continue
                    totals[style] += len(lst)
                    totals_lang[lang] += len(lst)
                    need_n = MIN
                    if sid in MIN10 and lv in MIN10_LEVELS.get(sid, {"1"}) and (sid, style) not in MIN10_STYLE_EXEMPT:
                        need_n = 10
                    if len(lst) < need_n:
                        errors.append(f"{where}: {len(lst)} Varianten, mindestens {need_n}")
                    norm = [re.sub(r"[^\w{}]+", " ", s.lower()).strip() for s in lst]
                    for s in set(norm):
                        if norm.count(s) > 1:
                            errors.append(f"{where}: Duplikat „{s}“")
                    statics = 0
                    for s in lst:
                        vs = set(VAR_RE.findall(s))
                        used_any |= vs
                        if not vs:
                            statics += 1
                        if vs - SPEC_VARS:
                            errors.append(f"{where}: Variable nicht in der SPEC {sorted(vs - SPEC_VARS)}: {s}")
                        elif vs - declared:
                            errors.append(f"{where}: Variable nicht deklariert {sorted(vs - declared)}: {s}")
                        if "{" in VAR_RE.sub("", s) or "}" in VAR_RE.sub("", s):
                            errors.append(f"{where}: kaputte Klammer: {s}")
                        if re.search(r"\d", VAR_RE.sub("", s)):
                            errors.append(f"{where}: Ziffer im Text (Zahlen als Variablen oder ausschreiben): {s}")
                        if EMOJI_RE.search(s):
                            errors.append(f"{where}: Emoji: {s}")
                        if ABBREV_RE.search(VAR_RE.sub("", s)):
                            errors.append(f"{where}: Abkürzung: {s}")
                        if lang == "de" and "ß" in s:
                            errors.append(f"{where}: ß statt ss: {s}")
                        if s != s.strip() or "  " in s:
                            errors.append(f"{where}: Leerzeichen: {s!r}")
                        limit = SHORT_MAX if sid in SHORT else LONG_MAX
                        if sid in SHORT and lv == "2" and style == "calm":
                            limit = SHORT_MAX_COX_CALM2
                        w = words(s)
                        if w > limit:
                            errors.append(f"{where}: {w} Wörter (max. {limit}): {s}")
                        key = (lang, s.lower())
                        if key in seen_level and seen_level[key] != style:
                            warnings.append(f"{sid}.{lv}.{lang}: gleiche Phrase in {seen_level[key]} und {style}: {s}")
                        seen_level.setdefault(key, style)
                    static_total += statics
                    if entry.get("dynamic") and statics < MIN_STATIC_DYNAMIC:
                        errors.append(f"{where}: nur {statics} statische Varianten (min. {MIN_STATIC_DYNAMIC})")
        if bool(used_any) != bool(entry.get("dynamic")):
            errors.append(f"{sid}: dynamic={entry.get('dynamic')} passt nicht zu den Variablen {sorted(used_any)}")
        if declared - used_any:
            warnings.append(f"{sid}: deklarierte, aber ungenutzte Variablen {sorted(declared - used_any)}")

    total = sum(totals.values())
    for w in warnings:
        print("WARNUNG:", w)
    for e in errors:
        print("FEHLER:", e)
    print(f"Szenarien: {len(scen)}  Phrasen gesamt: {total}  statisch: {static_total}  dynamisch: {total - static_total}")
    print("je Stil: " + ", ".join(f"{s} {n}" for s, n in totals.items())
          + "  je Sprache: " + ", ".join(f"{l} {n}" for l, n in totals_lang.items()))
    print("OK" if not errors else f"{len(errors)} Fehler")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
