#!/usr/bin/env python3
"""Findet String-Literale in Swift-Dateien und ordnet sie ein (Hilfe für die Lokalisierung von RowCoach).

Aufruf (im Repo-Wurzelordner):
  python3 App/l10n/swift_strings.py report [Pfade …]   # verdächtige, nicht lokalisierte Literale (Zeile, Kontext)
  python3 App/l10n/swift_strings.py keys   [Pfade …]   # Schlüssel, wie Xcode sie extrahiert (JSON)
  python3 App/l10n/swift_strings.py exprs  [Pfade …]   # Schlüssel mit Interpolation und ihren Ausdrücken (Typ prüfen)
Standardpfade: App/RowCoach und App/RowCoachKit/Sources.

Lokalisiert gelten Literale direkt in Text(…), Label(…), Button(…), Toggle(…), Stepper(…), Picker(…),
LabeledContent(…), Section(…), navigationTitle(…), Link(…), Menu(…), ProgressView(…), TextField(…),
NavigationLink(…), GroupBox(…), DisclosureGroup(…), ContentUnavailableView(…), confirmationDialog(…),
accessibilityLabel/Hint/Value(…), accessibilityAction(named:), Tab(…) sowie String(localized: …).
Alles andere mit Buchstaben gilt als verdächtig, ausser Protokollzeilen (Logger, print), #Predicate,
Schlüsseln und Literalen nach systemImage:, forKey:, verbatim: usw.
Interpolationen werden wie bei Xcode zu %@ (Text), %lld (ganze Zahl) bzw. %lf (Kommazahl); der Typ wird aus dem
Ausdruck geraten – mit `exprs` prüfen und Abweichungen in build_catalog.py (KEY_FIX) eintragen.
Ternäre Ausdrücke wie Text(a ? "x" : "y") werden NICHT lokalisiert (Swift macht daraus String) und erscheinen im
Bericht; richtig ist a ? Text("x") : Text("y").
"""
import json
import re
import sys
from pathlib import Path

LOCALIZING = re.compile(r'(?:\bText|\bLabel|\bButton|\bToggle|\bStepper|\bPicker|\bLabeledContent|\bSection|'
                        r'navigationTitle|\bLink|\bMenu|\bProgressView|\bTextField|ContentUnavailableView|'
                        r'confirmationDialog|accessibilityLabel|accessibilityHint|accessibilityValue|'
                        r'\bTab|chartXAxisLabel|chartYAxisLabel|NavigationLink|GroupBox|DisclosureGroup|\bsection)'
                        r'\s*\(\s*$')
LOCALIZED_ARG = re.compile(r'(?:String\(localized:|LocalizedStringResource\(|accessibilityAction\(named:|'
                           r'Metric\(title:)\s*$')
SKIP_LINE = re.compile(r'Logger\(|\blog\.|healthLog\.|recoveryLog\.|checkpointLog\.|print\(|#Predicate|'
                       r'Key = "|static let \w*Key|precondition|fatalError|assert\(')
# Literal direkt nach einem dieser Parameter ist kein Anzeigetext
SKIP_BEFORE = re.compile(r'(systemImage:|systemName:|forKey:|Image\(|forResource:|subsystem:|category:|identifier:|'
                         r'withExtension:|dateFormat = |verbatim:|URL\(string:|CBUUID\(string:|forInfoDictionaryKey:|'
                         r'AppStorage\(|\.value\(|label: |of: |with: |hasPrefix\(|contains\(|==|'
                         r'\.tag\()\s*$')

# Ausdrücke, deren Typ ganze Zahl ist → %lld; Kommazahl → %lf; sonst Text → %@
INT_EXPR = re.compile(r'(^Int\(|\.count$|Count$|^n$|^hr$|^z$|^i$|^b$|^seconds$|^meters$|^effort$|^score$|^week$|'
                      r'^minutes$|^\$0$|lowerBound|upperBound|rides|weeks|goal|Sessions|sessions|lap\b|'
                      r'strokeRate$|calories|averagePower$|strokeCount$|dragFactor$|^m$|^m / 60$|^m % 60$|'
                      r'^t / 60$|^est$|^number$|^workNumber$|workCount$|rawValue \+ 1$|^openCount$|^hardWeek$|'
                      r'^pct$|^faster$|^weeklyGoal$|minimumSessions$|^v$|pauseCount$|^zone$|^Int\(m\)$)')
DOUBLE_EXPR = re.compile(r'^(pauseAfter)$')
STRING_HINT = re.compile(r'Format\.|formatted|String\(|localizedDescription|\.title\b|\?\?')


def literals(src):
    """Liefert (start, end, inhalt, interpolationen) für jedes einfache String-Literal."""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if src.startswith('/*', i):
            j = src.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        if src.startswith('#"', i):
            j = src.find('"#', i + 2)
            i = n if j < 0 else j + 2
            continue
        if src.startswith('"""', i):
            j = src.find('"""', i + 3)
            i = n if j < 0 else j + 3
            continue
        if c == '"':
            start = i
            i += 1
            parts, interps = [], []
            while i < n and src[i] != '"':
                if src[i] == '\\' and i + 1 < n and src[i + 1] == '(':
                    depth, j = 1, i + 2
                    while j < n and depth:
                        if src[j] == '(':
                            depth += 1
                        elif src[j] == ')':
                            depth -= 1
                        elif src[j] == '"':
                            k = j + 1
                            while k < n and src[k] != '"':
                                k += 2 if src[k] == '\\' else 1
                            j = k
                        j += 1
                    interps.append(src[i + 2:j - 1])
                    parts.append('\0')
                    i = j
                    continue
                if src[i] == '\\':
                    parts.append(src[i:i + 2])
                    i += 2
                    continue
                if src[i] == '\n':
                    break
                parts.append(src[i])
                i += 1
            yield start, i + 1, ''.join(parts), interps
            i += 1
            continue
        i += 1


def spec(expr):
    e = expr.split(', privacy')[0].strip()
    if DOUBLE_EXPR.search(e):
        return '%lf'
    if INT_EXPR.search(e) and not STRING_HINT.search(e):
        return '%lld'
    return '%@'


def key_of(content, interps):
    out, k = [], 0
    for ch in re.split(r'(\0)', content):
        if ch == '\0':
            out.append(spec(interps[k]))
            k += 1
        else:
            out.append(ch.replace('%', '%%') if interps else ch)
    s = ''.join(out)
    return s.replace('\\"', '"').replace('\\n', '\n').replace('\\\\', '\\')


def classify(src, start):
    line_start = src.rfind('\n', 0, start) + 1
    line_end = src.find('\n', start)
    line = src[line_start:line_end if line_end >= 0 else None]
    before = src[max(0, start - 200):start]
    if SKIP_LINE.search(line) or SKIP_BEFORE.search(before):
        return 'skip', line
    if LOCALIZING.search(before) or LOCALIZED_ARG.search(before):
        return 'localized', line
    return 'plain', line


def has_words(s):
    letters = re.sub(r'\0|\\.', '', s)
    # auch kurze Einheiten wie „m ü. M.“ oder „%lld s“ (Formatangaben selbst zählen nicht)
    letters = re.sub(r'%(lld|ld|d|@|lf|f|%)', '', letters)
    return re.search(r'[A-Za-zÄÖÜäöüß]', letters) is not None


def scan(paths):
    for p in paths:
        src = Path(p).read_text(encoding='utf-8')
        for start, end, content, interps in literals(src):
            if not has_words(content):
                continue
            kind, line = classify(src, start)
            lineno = src.count('\n', 0, start) + 1
            yield str(p), lineno, kind, key_of(content, interps), interps, line.strip()


def files(args):
    roots = args or ['App/RowCoach', 'App/RowCoachKit/Sources']
    out = []
    for r in roots:
        rp = Path(r)
        out += sorted(rp.rglob('*.swift')) if rp.is_dir() else [rp]
    return out


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'report'
    fs = files(sys.argv[2:])
    if mode == 'exprs':
        for p, ln, kind, key, interps, line in scan(fs):
            if kind == 'localized' and interps:
                print(f'{key!r:70} <- {interps}   [{p}:{ln}]')
    elif mode == 'keys':
        keys = {}
        for p, ln, kind, key, interps, line in scan(fs):
            if kind == 'localized':
                keys.setdefault(key, f'{p}:{ln}')
        print(json.dumps(keys, ensure_ascii=False, indent=1))
    else:
        n = 0
        for p, ln, kind, key, interps, line in scan(fs):
            if kind == 'plain':
                n += 1
                print(f'{p}:{ln}: {key!r}    | {line[:110]}')
        print(f'\n{n} verdächtige Literale (nicht lokalisiert)', file=sys.stderr)


if __name__ == '__main__':
    main()
