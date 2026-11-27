#!/usr/bin/env python3
"""Erzeugt App/RowCoachKit/Sources/RowCoachKit/VirtualRowers/VirtualRowerNames.swift (Vornamen je Land für die
virtuellen Teilnehmenden, docs/MULTIPLAYER.md „Virtuelle Teilnehmende“).

Quelle: sigpwned/popular-names-by-country-dataset, Datei common-forenames-by-country.csv, Stand Commit
eb62e13d4d62dd96cdfae79d293a02066352205f (Lizenz CC0 1.0; Daten aus den Wikipedia-Listen „List of most popular
given names“, Juli 2023). Ergänzt um Schweden (fehlt im Datensatz): häufigste Vornamen Neugeborener 2024 laut
Skatteverket (Statistikportal, vorläufig). Vornamen allein sind Fakten, keine Werke; Herkunft in NOTICE.

Aufruf: python3 tools/virtualrowers/make_names.py [<pfad zur csv>]
Ohne Pfad wird die CSV in der festen Fassung heruntergeladen. Ändert sich die Ausgabe, ändert sich nicht der
mitgelieferte Pool (der trägt die Namen selbst), nur ein künftiger Pool v2.
"""
import csv
import io
import sys
import urllib.request
from pathlib import Path

COMMIT = 'eb62e13d4d62dd96cdfae79d293a02066352205f'
URL = f'https://raw.githubusercontent.com/sigpwned/popular-names-by-country-dataset/{COMMIT}/common-forenames-by-country.csv'
OUT = Path(__file__).resolve().parents[2] / 'App/RowCoachKit/Sources/RowCoachKit/VirtualRowers/VirtualRowerNames.swift'

SUPPLEMENT = {
    # Skatteverket, Namn på nyfödda 2024 (vorläufig), je zehn häufigste
    'SE': (['Alma', 'Alice', 'Olivia', 'Elsa', 'Vera', 'Saga', 'Selma', 'Astrid', 'Ella', 'Signe'],
           ['Noah', 'William', 'Hugo', 'Liam', 'Adam', 'August', 'Nils', 'Leo', 'Oliver', 'Sam']),
}


def load(path):
    if path:
        text = Path(path).read_text(encoding='utf-8-sig')
    else:
        with urllib.request.urlopen(URL, timeout=60) as r:
            text = r.read().decode('utf-8-sig')
    return list(csv.DictReader(io.StringIO(text)))


def main():
    rows = load(sys.argv[1] if len(sys.argv) > 1 else None)
    names = {}
    for x in rows:
        n = x['Romanized Name'].strip() or x['Localized Name'].strip()
        if not n or ',' in n or '|' in n or len(n) > 16:
            continue
        f, m = names.setdefault(x['Country'].strip().upper(), ([], []))
        lst = f if x['Gender'] == 'F' else m
        if n not in lst:
            lst.append(n)
    for cc, (f, m) in SUPPLEMENT.items():
        names[cc] = (list(f), list(m))
    lines = []
    for cc in sorted(names):
        f, m = names[cc]
        lines.append(f'        "{cc}": ("{",".join(f)}", "{",".join(m)}"),')
    body = '\n'.join(lines)
    OUT.write_text(f'''import Foundation

// ERZEUGT von tools/virtualrowers/make_names.py – nicht von Hand ändern.
// Vornamen je Land (ISO 3166-1 alpha-2): weiblich, männlich (durch Komma getrennt, lateinische Umschrift).
// Quelle: sigpwned/popular-names-by-country-dataset (CC0 1.0, Commit {COMMIT[:7]}, aus Wikipedia „List of most
// popular given names“, Juli 2023); Schweden: Skatteverket, Namn på nyfödda 2024. Siehe NOTICE.

enum VirtualRowerNames {{
    static let raw: [String: (female: String, male: String)] = [
{body}
    ]

    /// Namen eines Landes, nil ohne Liste
    static func names(_ country: String) -> (female: [String], male: [String])? {{
        guard let r = raw[country.uppercased()] else {{ return nil }}
        func split(_ s: String) -> [String] {{ s.split(separator: ",").map(String.init) }}
        return (split(r.female), split(r.male))
    }}
}}
''', encoding='utf-8')
    print(f'{len(names)} Länder → {OUT}')


if __name__ == '__main__':
    main()
