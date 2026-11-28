# Amazonas-Strecken: Vorgaben (Falk, 27.11.2026)

Strecken (Vorschlag, im Bau prüfen):
1. Encontro das Águas bei Manaus – entlang der Grenze zwischen schwarzem Rio Negro und braunem Solimões.
2. Anavilhanas-Archipel (Rio Negro) – Inseln und Kanäle.
3. Igapó (Überschwemmungswald am Rio Negro) – zwischen Baumkronen rudern.
4. Iquitos (Peru) oder Leticia (Kolumbien) – Stadtufer mit Pfahlbauten.

## Was Falk ausdrücklich will
- **Igapó: Baumkronen müssen wirklich zu sehen sein**, eindrucksvoll nachgebaut, sodass es Spass macht, dort zu rudern:
  Bäume stehen IM Wasser (Stämme ragen aus dem Wasser, Kronen darüber), dicht, unterschiedlich hoch, einzelne
  Urwaldriesen; die Strecke führt zwischen ihnen hindurch. Grundlage: Meta/WRI Global Canopy Height (1 m, CC BY 4.0)
  bzw. synthetisches Kronendach; im überfluteten Bereich Bäume ausdrücklich auf der Wasserfläche platzieren
  (heute filtert die Pipeline Bäume im Wasser heraus – hier umkehren).
- **Pfahlbauten (Palafitas) ordentlich sichtbar**: eigene Gebäudeart – Holzhaus auf Pfählen über dem Wasser bzw. am
  Ufer, Stege, Wellblech-/Palmdach, bunte Fassaden; nicht als Klötze aus Grundriss + Höhe.
- **Nah vorbeirudern**: Es ist eine Simulation – keine realen Sicherheitsabstände. Strecke bewusst nah an Bäumen,
  Pfahlbauten, Ufern und Inseln führen (z. B. 3–6 m statt üblicher Abstände); routes.py/lanes.py dafür per Feld in
  der Gebietsdatei lockern (nur für diese Strecken).
- Encontro das Águas: zwei Wasserfarben in einer Szene (schwarz/braun mit sichtbarer Grenzlinie und leichter
  Durchmischung) – heute gibt es nur eine Wasserfarbe pro Szene; Erweiterung nötig.

## Technik
- Gelände Copernicus GLO-30 (flach), Wasserstand je Strecke fest (Hochwasser für Igapó).
- Luftbild synthetisch (OSM + Sentinel-2-Mosaik über mehrere Aufnahmen wegen Wolken).
- Lizenzen in LIZENZEN-GEODATEN.md und NOTICE (Meta/WRI CC BY 4.0, Copernicus, OSM, Sentinel-2).
- Performance auf dem A12X beachten: dichter Wald mit Instancing/LOD, Budget ~1 Mio. Dreiecke.

## Umsetzung (27.11.2026)

Werkzeug `tools/coursebuilder/amazonas.py` (Docstring) mit Haken in common.py (`flood_lv95`), trees.py (`synth_forest`),
export.py (Pfahlbauten, Wasserfarbe), lanes.py (`lane_rules`, Hindernisse), bake.py (Gebiete ohne Gebäude) und
preview.py (halbdurchsichtige Wasserfarbe). Alles nur mit den Gebietsfeldern aktiv. Technik: docs/WELTWEIT.md
Abschnitt 22, Felder: BUILD.md.

| Strecke | Gebiet | Form | Länge | Kern | standard / hoch |
|---|---|---|---|---|---|
| `manaus-encontro` | Encontro das Águas, Manaus (BR, EPSG:31981) | hin und zurück | 2 × 2,84 km | Farbgrenze aus Sentinel-2 (50-%-Isolinie) | 0,15 Mio. Dreiecke, 8 MB / 0,48 Mio., 16 MB |
| `anavilhanas-kanal` | Arquipélago de Anavilhanas, Novo Airão (BR, EPSG:31980) | hin und zurück | 2 × 2,35 km | Kanal zwischen zwei Inseln, 10 m vor dem überfluteten Waldrand, Rückfahrt durch die Randbäume | Gebiet: 0,85 Mio., 29 MB / 1,68 Mio., 54 MB |
| `anavilhanas-igapo` | dto. | hin und zurück | 2 × 1,99 km | mitten durch einen überfluteten Waldstreifen (Igapó), 3 m um die Stämme frei | dto. |
| `iquitos-belen` | Río Itaya, Iquitos (PE, EPSG:31978) | hin und zurück | 2 × 2,84 km | von Norden an den Pfahlbauten der Stadtkante und von Belén Bajo vorbei, Häuser rechts | 0,54 Mio. (Pfahlbauten 0,25 Mio.), 42 MB / 0,82 Mio., 58 MB |

- Igapó: Bäume aus der Meta/WRI-Kronenhöhe (Wald nur, wo es ihn gibt), im Wasser stehend mit sichtbaren Stämmen,
  dunklem Wasserrand und schiefem Wuchs, Unterholz, 2,5 % Urwaldriesen bis 44 m mit Schirmkrone; Hochwasser 4 m über
  dem Waldboden. Kronen ragen über die Bahn. standard ≈ 18 000 Bäume (0,52 Mio. Dreiecke), hoch alle.
- Pfahlbauten: eigene Gebäudeart (Pfähle, Boden, Veranda mit Geländer, Bretterwände bunt mit Tür/Fenstern, Wellblech
  mit Rost oder Palmdach, Stege, Kanus), aus den OSM-Umrissen von Iquitos (~1 300 Häuser in der Várzea), vorgerechnetes
  Licht. Strecke 5–25 m an den Häusern vorbei.
- Zwei Wasserfarben: halbdurchsichtige Fläche über dem App-Wasser, keine App-Änderung. Anavilhanas mit
  Schwarzwasserton, Iquitos mit Weisswasserton.
- Offen: Darstellung der Deckkraft (opacity) in RealityKit auf dem iPad prüfen; Kronen sind Low-Poly-Formen (keine
  Blatttexturen); Pfahlbauten nur aus OSM-Umrissen (Lage/Grösse), Fassaden zufällig.
- Texturen standard: Encontro 14 Mpx, Anavilhanas 33 Mpx, Iquitos 63 Mpx (Pfahlbau-Atlanten 36 Mpx) – Iquitos auf dem
  A12X beobachten; hoch 150 Mpx je Gebiet (Gelände-Standard der Stufe hoch).

## Umsetzung, 2. Runde (28.11.2026)

- Igapó (Vergleich: igapo-vorher-nachher.png): `forest_variety` in amazonas.py – Dickichte und Lücken (Stammdichte nach
  Rauschen 45/14 m), Palmen (Açaí in Büscheln mit Stelzwurzeln, Buriti einzeln mit Fächerkrone, Wedel hängend), säulige
  und flache Schirmkronen, unregelmässige Kronen (Rauschen 0,16–0,48), Stelzwurzeln an grossen Stämmen, Lianen unter
  hohen Kronen, dichte Büsche knapp über dem Wasser am Waldrand und in Dickichten, 16 Grüntöne mit stärkerer Fleckung;
  Dunst in der Tiefe des Waldes als Farbverlauf zur Dunstfarbe ab 35 m von der Strecke (eingebacken, keine App-Änderung
  – echter Nebel bräuchte die App); Schwarzwasser dunkler (Deckkraft 0,86) und spiegelnder (roughness 0,08).
  Kein echtes Instancing (RealityKit-USDZ der Pipeline: Meshes je km-Zelle), dafür drei Formstufen und Budget.
  anavilhanas standard 0,90 Mio. Dreiecke (Bäume 0,57 Mio.)/30 MB, hoch 2,47 Mio./82 MB.
- Mitruderer: `traffic.follow_lane` (lanes.py) – findet sich neben der eigenen Bahn kein Platz, fahren die Ruderer auf
  derselben Linie (Hinfahrt 0 m, Rückfahrt 12 m); im Igapó und in Iquitos aktiv, Kanal behält seine zwei Bahnen.
- Iquitos: Strecke 5,5 m vor der Hülle der Hauskörper (Pfahlbauten und Stadtkante, Lücken < 22 m geschlossen), Veranden
  der Häuser bis 22 m von der Bahn zur Strecke gedreht (`veranda_to_route_m`) → Hausfronten meist 3,5–4 m entfernt;
  Kanus liegen auf der abgewandten Seite, Stege nur zwischen Häusern und nie über die Bahn.
- Encontro unverändert.
