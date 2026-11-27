# Lizenzprüfung der Geodaten (Stand 26.11.2026, Österreich, USA, Norwegen, Island, Kanada, Amazonas, Niederlande und Italien 27.11.2026)

Auftrag Falk (26.11.2026): „Prüfe auf jeden Fall, ob wir die Geodaten so nutzen dürfen.“ Sorgfältige, belegte Prüfung je
Quelle anhand der Lizenztexte im Original, **keine Rechtsberatung**. Wo etwas offen ist, steht es als offen da.

Geprüfte Nutzung:

1. **Bundle**: abgeleitete 3D-Szenen (USDZ) der zwei Standardstrecken `rhein-basel` und `berlin-spree-mitte` werden mit
   der App ausgeliefert (App Store, iOS; später Android).
2. **Server**: weitere Strecken liegen öffentlich auf Firebase Hosting zum Download für alle Nutzer.
3. **Kommerziell**: Abo ca. 5 USD/Monat (Turniere, Strecken).
4. **Öffentliches Repo** (Apache-2.0): im Git liegen nur `course.json`, Vorschaubilder (`preview-*.jpg`, Renderings der
   Szene mit Luftbildtextur), Minikarte und Übersicht (`minimap.jpg`, `overview.jpg`, Ausschnitte aus dem Luftbild),
   keine Szenen und keine Rohdaten.
5. **Namensnennung** heute: Feld `attribution` in `course.json` (angezeigt in der Streckenansicht „Quellen: …“ und in
   Einstellungen → „Quellen und Lizenzen“) sowie `NOTICE`.

## Kurzfazit

- **Grundsätzlich ja.** Alle verwendeten Quellen erlauben Bearbeitung, Weitergabe und kommerzielle Nutzung, auch in einer
  Bezahl-App und auf einem öffentlichen Server. Keine Quelle verbietet die Nutzung als Textur oder 3D-Modell, keine
  verlangt Gebühren. Die Vorschaubilder und Minikarten dürfen im öffentlichen Repo liegen, sie stehen aber **nicht** unter
  Apache-2.0, sondern unter den Lizenzen der Quellen (das sagt `NOTICE` schon sinngemäss; deutlicher machen).
- **Rot: nichts.**
- **Gelb, bevor die App in den Store geht** (alles lösbar mit Text in der App, ohne Datenänderung):
  1. **Copernicus DEM** (Bundle-Strecke `rhein-basel`, Höhen ausserhalb der Schweiz; dazu fast alle Server-Strecken): Die Lizenz
     verlangt bei bearbeiteten Daten den Wortlaut „produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and ©
     Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved“
     **und** einen Haftungsausschluss-Satz in einer Lizenz- oder Rechtshinweisseite. Beides fehlt heute.
  2. **OpenStreetMap (ODbL)**: Die Szenen sind nach ODbL 4.5(b) ein „Produced Work“ (keine Share-Alike-Pflicht für die
     Szene selbst), brauchen aber einen Hinweis, dass die Daten von OpenStreetMap stammen **und unter der ODbL stehen**,
     mit auffindbarem Link auf openstreetmap.org/copyright. Heute steht nur „© OpenStreetMap contributors (ODbL)“ ohne
     Link. Wo wir OSM-Daten verändern und verknüpfen (Oxford: OSM-Gebäudeumrisse mit Höhen aus dem DSM; ausgeschnittene
     Wasserflächen), entsteht eine abgeleitete Datenbank: dann nach ODbL 4.6 die Datenbank **oder die Methode** anbieten.
     Das öffentliche Repo `tools/coursebuilder` erfüllt das, wenn wir in der App/NOTICE darauf hinweisen.
  3. **Datenlizenz Deutschland – Namensnennung (Brandenburg LGB, Hamburg LGV)**: Hinweis auf Bearbeitung („Daten
     geändert“/„bearbeitet“) und Verweis auf den Lizenztext fehlen bei LGB und LGV. Bundle-Strecke `berlin-spree-mitte`
     nennt LGB (DGM1) → betrifft das Bundle.
  4. **Japan (GSI, PLATEAU)**: Die Bedingungen verlangen neben dem Quellennachweis **zusätzlich** den Hinweis auf die
     Bearbeitung („…を加工して作成“). Fehlt heute.
  5. **Japan, GSI-Höhen (標高タイル = 基盤地図情報 数値標高モデル)**: Das ist ein Ergebnis der staatlichen
     Grundvermessung. Nach Survey Act Art. 30 kann für ein daraus erstelltes „anderes Produkt“ (die GSI-FAQ nennt
     ausdrücklich eine „立体的な地図“) eine **Nutzungsgenehmigung (使用承認申請)** nötig sein. Für 基盤地図情報 ist sie
     nach GSI-FAQ **kostenlos**. Betrifft nur die drei japanischen Server-Strecken. → Falk entscheiden: beim GSI anfragen
     bzw. Antrag stellen, oder bis dahin die japanischen Strecken nicht veröffentlichen.
- **Offen, klein**: Polen NMPT (Oberflächenmodell): Das Gesetz nennt beim kostenlosen Datenzugang nur das
  „numeryczny model terenu“; GUGiK gibt das NMPT aber ebenfalls frei zum Download. Kurz bei GUGiK bestätigen lassen.
- **Was Falk entscheiden/anfragen muss**: (a) GSI-Antrag oder Anfrage für die Höhen (Japan), (b) GUGiK-Bestätigung NMPT
  (optional), (c) ob die Quellenangaben auch in der Fahrt-Ansicht kurz erscheinen sollen (empfohlen, siehe To-dos).

## Ampel je Quelle und Szenario

Legende: 🟢 erlaubt, Bedingungen erfüllt · 🟡 erlaubt, aber Bedingung fehlt/offen · 🔴 nicht erlaubt · – nicht betroffen.
Spalte 5 bewertet die heutige Namensnennung.

| Quelle (Lizenz) | 1 Bundle | 2 Server | 3 kommerziell | 4 Repo (JPG, course.json) | 5 Namensnennung heute |
|---|---|---|---|---|---|
| swisstopo (OGD-Nutzungsbedingungen) | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 |
| Geoportal Berlin (dl-de/zero-2-0) | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 (keine Pflicht) |
| LGB Brandenburg (dl-de/by-2-0) | 🟢 | 🟢 | 🟢 | 🟢 | 🟡 „Daten geändert“, Lizenzlink fehlen |
| LGV Hamburg (dl-de/by-2-0) | – | 🟢 | 🟢 | 🟢 | 🟡 „bearbeitet“, Lizenzlink fehlen |
| HVBG Hessen (dl-de/zero-2-0) | – | 🟢 | 🟢 | 🟢 | 🟢 |
| IGN France (Licence Ouverte 2.0) | – | 🟢 | 🟢 | 🟢 | 🟢 (Stand „2026“; besser Aktualisierungsdatum) |
| BEV Österreich ALS DTM/DSM (CC BY 4.0) | – | 🟢 | 🟢 | 🟢 | 🟢 („Datenquelle: BEV“, CC BY 4.0, bearbeitet) |
| basemap.at Orthofoto (CC BY 4.0) | – | 🟢 | 🟢 | 🟢 | 🟢 („Datenquelle: basemap.at“, CC BY 4.0, bearbeitet) |
| Kartverket Norwegen Høydedata DTM1/DOM1 (CC BY 4.0) | – | 🟢 | 🟢 | 🟢 | 🟢 („© Kartverket“, CC BY 4.0, bearbeitet) |
| Náttúrufræðistofnun Island ÍslandsDEM v1.0 (CC BY 4.0) | – | 🟢 | 🟢 | 🟢 | 🟢 („ÍslandsDEM v1.0, Náttúrufræðistofnun“, CC BY 4.0, bearbeitet) |
| NRCan Kanada HRDEM DTM/DSM (Open Government Licence – Canada 2.0) | – | 🟢 | 🟢 | 🟢 | 🟢 („Contains information licensed under the Open Government Licence – Canada“, bearbeitet) |
| USGS 3DEP DEM/Lidar (gemeinfrei) | – | 🟢 | 🟢 | 🟢 | 🟢 („U.S. Geological Survey, 3DEP“, freiwillig) |
| MassGIS Orthofoto 2023 (keine Einschränkungen) | – | 🟢 | 🟢 | 🟢 | 🟢 („MassGIS“, erbeten) |
| IPP Rio de Janeiro Edificações 2013 (CC BY 4.0) | – | 🟢 | 🟢 | 🟢 | 🟢 („Instituto Pereira Passos (IPP)“, CC BY 4.0, bearbeitet) |
| Microsoft Global ML Building Footprints (CDLA Permissive 2.0) | – | 🟢 | 🟢 | 🟢 | 🟢 (für Ergebnisse keine Pflicht; genannt) |
| Meta/WRI High Resolution Canopy Height Maps (CC BY 4.0) | – | 🟢 | 🟢 | 🟢 | 🟢 („Meta and World Resources Institute (WRI) – High Resolution Canopy Height Maps (2024)“, CC BY 4.0, Bildquelle © 2016 Maxar, bearbeitet) |
| AHN4 DTM/DSM (CC0 1.0), PDOK Luchtfoto Beeldmateriaal Nederland (CC BY 4.0), 3DBAG (CC BY 4.0) | – | 🟢 | 🟢 | 🟢 | 🟢 („AHN (CC0)“; „Beeldmateriaal Nederland (beeldmateriaal.nl), CC BY 4.0, bearbeitet“; „© 3DBAG by tudelft3d and 3DGI, CC BY 4.0, bearbeitet“) |
| GUGiK Polen (Pgik Art. 40a/40c) | – | 🟢 (NMPT 🟡) | 🟢 | 🟢 | 🟢 |
| GSI 写真 seamlessphoto (GSI-Bedingungen/PDL1.0) | – | 🟢 | 🟢 | 🟢 | 🟡 „加工して作成“ fehlt |
| GSI 標高タイル DEM5A/DEM10B (基盤地図情報, Survey Act) | – | 🟡 Genehmigung prüfen | 🟡 | 🟢 | 🟡 „加工して作成“ fehlt |
| GSI 地理院地図Vector Gebäude (GSI-Bedingungen) | – | 🟢 | 🟢 | 🟢 | 🟡 „加工して作成“ fehlt |
| MLIT PLATEAU (PDL1.0, CC-BY-kompatibel) | – | 🟢 | 🟢 | 🟢 | 🟡 Bearbeitungshinweis fehlt |
| Environment Agency (OGL v3) | – | 🟢 | 🟢 | 🟢 | 🟢 (Link auf OGL ergänzen) |
| Copernicus DEM GLO-30 (Copernicus WorldDEM-30-Lizenz) | 🟢 | 🟢 | 🟢 | 🟢 | 🟡 „produced using …“ + Haftungssatz fehlen |
| Copernicus Sentinel-2 (EU-Rechtshinweis) | – | 🟢 | 🟢 | 🟢 | 🟢 |
| OpenStreetMap (ODbL 1.0) | 🟢 | 🟢 | 🟢 | 🟢 | 🟡 Link/ODbL-Hinweis, 4.6-Angebot fehlen |
| Monk Skin Tone Scale (CC BY 4.0) | 🟢 | – | 🟢 | 🟢 | 🟢 (Link auf Lizenz ergänzen) |

Bundle-Strecken: `rhein-basel` (swisstopo, OSM, Copernicus DEM), `berlin-spree-mitte` (Geoportal Berlin, LGB DGM1, OSM).

## Je Quelle: Belege

### swisstopo – Open Government Data (swissALTI3D, SWISSIMAGE, swissBUILDINGS3D 3.0, swissSURFACE3D Raster, swissTLM3D)

- Lizenz: „Nutzungsbedingungen für kostenlose Geodaten und Geodienste von swisstopo“, Version 1.3.2021, veröffentlicht
  26.08.2022: https://www.swisstopo.admin.ch/de/nutzungsbedingungen-kostenlose-geodaten-und-geodienste
- Ziff. 2: „Die kostenlosen Geodaten und Geodienste von swisstopo dürfen genutzt, verbreitet und zugänglich gemacht
  werden. Weiter dürfen sie angereichert, bearbeitet sowie auch kommerziell genutzt werden.“
- Ziff. 2: „Eine Quellenangabe ist Pflicht.“ Zulässig u. a. „Bundesamt für Landestopografie swisstopo“ oder „©swisstopo“
  (andere Formulierung nur für swissALTIRegio und swissEO – nutzen wir nicht).
- Ziff. 3: Bei übermässiger Nutzung der Geodienste kann der Zugang eingeschränkt werden (betrifft Download, nicht die
  Weitergabe).
- Bewertung: alle Szenarien grün; „© swisstopo (…)“ steht in `attribution`. Kein Endorsement-Verbot im Text, trotzdem
  keine swisstopo-Logos verwenden.

### Geoportal Berlin – Datenlizenz Deutschland – Zero – 2.0 (TrueOrthophotos Sommer 2025, DGM1, LoD2, bDOM)

- Lizenz: https://www.govdata.de/dl-de/zero-2-0 – „Jede Nutzung ist ohne Einschränkungen oder Bedingungen zulässig.“
  Ausdrücklich auch kommerziell, verändert, an Dritte weitergegeben, in Produkte und Anwendungen integriert.
- Datensätze: Metadaten der GDI Berlin nennen dl-de/zero-2-0 u. a. für die LoD2-Gebäudemodelle
  (https://gdi.berlin.de/geonetwork/srv/api/records/3c7c49af-00a4-3bcd-bc00-20e7f0f1b7bf) und die Orthophotos 2025;
  `tools/coursebuilder/fetch_de.py` führt alle vier Berliner Produkte unter Zero 2.0. Achtung: Andere Berliner
  Geobasisdaten (ALKIS, DTK) stehen unter dl-de/by-2-0 – bei neuen Berliner Produkten je Datensatz prüfen.
- Bewertung: grün; Quellenangabe freiwillig (wir nennen sie trotzdem).

### LGB Brandenburg – Datenlizenz Deutschland – Namensnennung – 2.0 (DGM1, DOP20 WMS; laut fetch_de.py auch LoD2, bDOM)

- Lizenz: https://www.govdata.de/dl-de/by-2-0 – jede Nutzung zulässig, auch kommerziell, Veränderung, Weitergabe,
  Integration in Produkte und Anwendungen. Bedingungen: Quellenvermerk mit (1) Bereitsteller, (2) „Datenlizenz
  Deutschland – Namensnennung – Version 2.0“ oder „dl-de/by-2-0“ mit Verweis auf den Lizenztext, (3) Verweis auf den
  Datensatz (URI), soweit der Bereitsteller diese Angaben macht. „Veränderungen, Bearbeitungen, neue Gestaltungen oder
  sonstige Abwandlungen sind im Quellenvermerk mit dem Hinweis zu versehen, dass die Daten geändert wurden.“
- LGB-Vorgabe (Nutzungsbedingungen Stand 15.01.2020, Ziff. 6.1, über OSM-Community und INSPIRE-Metadaten belegt,
  aktuelle LGB-Seite nicht erreichbar): „© GeoBasis-DE/LGB (Jahr), dl-de/by-2-0, Daten geändert“.
- Heute: „© GeoBasis-DE/LGB (DGM1), dl-de/by-2-0“ – **„Daten geändert“ fehlt**, kein Link. Prüfen, ob in Grünau/Wannsee
  auch LGB-LoD2/bDOM verbaut sind; dann diese Produkte nennen.
- Bewertung: Nutzung grün, Namensnennung gelb (betrifft Bundle `berlin-spree-mitte`).

### LGV Hamburg – Datenlizenz Deutschland – Namensnennung – 2.0 (DOP 2024, DGM1 2022, bDOM 2022, LoD2-DE 2026)

- Lizenz wie oben (dl-de/by-2-0). Quellenvermerk laut Metadaten: „Freie und Hansestadt Hamburg, Landesbetrieb
  Geoinformation und Vermessung (LGV)“. Der LGV hat gegenüber der OSM-Community erklärt, wichtig sei, dass erkennbar
  ist, dass die Daten vom LGV stammen und aus welchem Jahr
  (https://wiki.openstreetmap.org/wiki/DE:Permissions/LGV_Hamburg_2021).
- Heute: Bereitsteller, Lizenzname und Jahre stehen da; **„bearbeitet“ fehlt**, kein Link auf den Lizenztext.
- Bewertung: Nutzung grün, Namensnennung gelb.

### HVBG Hessen – Datenlizenz Deutschland – Zero – 2.0 (DOP20, DGM1, DOM1, LoD2)

- Metadaten DOP20/DGM1 nennen „dl-zero-de/2.0“ (Geodatenkatalog
  https://gdk.gdi-de.org/geonetwork/srv/api/records/0b30f537-3bd0-44d4-83b0-e3c1542ca265); Downloadcenter
  https://gds.hessen.de/: „kosten- und lizenzfreier Download“, Geobasisdaten „können privat oder auch gewerblich genutzt
  werden“.
- Bewertung: grün; die Angabe „bearbeitet“ ist freiwillig und schon da.

### IGN France – Licence Ouverte / Open Licence 2.0 (BD ORTHO®, LiDAR HD, RGE ALTI®, BD TOPO®)

- Lizenz: Etalab, Licence Ouverte 2.0 (April 2017):
  https://static.data.gouv.fr/resources/licence-ouverte-2-0/20260909-072646/etalab-licence-ouverte-v2.0.pdf
- Rechte: „droit non exclusif et gratuit de libre « Réutilisation » … à des fins commerciales ou non“; reproduire,
  „l'adapter, la modifier, l'extraire et la transformer, pour créer des « Informations dérivées », des produits ou des
  services“, redistribuer, „l'exploiter à titre commercial … en l'incluant dans son propre produit ou application“.
- Bedingung: „mentionner la paternité de l'« Information » : sa source (au moins le nom du « Concédant ») et la date de
  dernière mise à jour de l'« Information » réutilisée“, z. B. per Link. Die Nennung darf keine „reconnaissance ou
  caution“ durch IGN suggerieren. Kompatibel mit CC BY und ODC-BY.
- Heute: „Source : IGN – … (2026), Licence Ouverte Etalab 2.0, données modifiées“ – genügt; besser das
  Aktualisierungsdatum je Produkt (Monat/Jahr) statt nur „2026“, Link auf die Lizenz auf der Lizenzseite.
- Bewertung: grün.

### GUGiK Polen – Prawo geodezyjne i kartograficzne (Ortofotomapa, NMT/NMPT, BDOT10k Budynki)

- Gesetzestext (Tekst jednolity Dz. U. 2023 poz. 1752, https://api.sejm.gov.pl/eli/acts/DU/2023/1752/text.html):
  - Art. 40a ust. 2 pkt 1: „Nie pobiera się opłaty za: 1) udostępnianie zbiorów danych: … d) numerycznego modelu terenu,
    e) ortofotomapy, … h) obiektów topograficznych o szczegółowości zapewniającej tworzenie standardowych opracowań
    kartograficznych w skalach 1:10 000-1:100 000“ (= BDOT10k).
  - Art. 40c ust. 1: Die Nutzungsrechte bestimmt sonst eine Lizenz des Bereitstellers; **ust. 5**: „Licencji nie wydaje
    się … w przypadku udostępnienia materiałów zasobu, o których mowa w art. 40a ust. 2 pkt 1 i 3.“ → Für diese Daten
    gibt es keine Lizenz und damit keine lizenzvertragliche Einschränkung (auch nicht kommerziell).
  - Art. 40c ust. 3: „Podmioty, które wykorzystują materiały zasobu, zamieszczają w publikowanych opracowaniach
    informacje o źródle pochodzenia użytego materiału.“ → Quellenangabe Pflicht.
- GUGiK selbst: BDOT10k „free of charge and can be used for any purpose“
  (https://www.geoportal.gov.pl/en/data/topographic-objects-database-bdot10k/).
- Offen: Das NMPT (Oberflächenmodell) ist im Gesetzeswortlaut nicht eigens genannt; GUGiK gibt es aber frei über
  Geoportal/WCS heraus. Kurz bei GUGiK bestätigen lassen. Die Nutzungsbedingungen (Regulamin) des Geoportals für
  automatisierte WMS/WCS-Abrufe wurden nicht geprüft.
- Heute: „Źródło: Główny Urząd Geodezji i Kartografii (GUGiK, geoportal.gov.pl) – …; dane udostępniane bez opłat,
  przetworzone“ – erfüllt Art. 40c ust. 3.
- Bewertung: grün, NMPT gelb (klein).

### Österreich – BEV ALS-Höhenraster und basemap.at Orthofoto (CC BY 4.0), Stand 27.11.2026

- BEV „ALS DTM/DSM Höhenraster 1m Stichtag 15.09.2025“ (COG je 50 × 50 km, data.bev.gv.at): Metadaten
  (https://data.bev.gv.at/geonetwork/srv/api/records/ec12896e-1ecd-47ad-8d48-44d236e383cc) „Für dieses Produkt gilt die
  Standardlizenz CC-BY-4.0“ und „Der öffentliche Zugang zu diesem Produkt unterliegt keinen Einschränkungen“.
  Kooperationsprodukt von Bund und Ländern, vom BEV unter CC BY 4.0 abgegeben.
- basemap.at (Verwaltungsgrundkarte der Länder, Betrieb Stadt Wien), Layer `bmaporthofoto30cm`: basemap.at „ist gemäß
  der Open Government Data Österreich Lizenz CC-BY 4.0 sowohl für private als auch kommerzielle Zwecke frei sowie
  entgeltfrei nutzbar“ (https://basemap.at/); WMTS-Capabilities: Fees none, AccessConstraints → basemap.at.
- CC BY 4.0: Namensnennung, Lizenzlink, Hinweis auf Änderungen. Heute: „Datenquelle: BEV – Bundesamt für Eich- und
  Vermessungswesen, ALS-Höhenraster DTM/DSM 1 m (Stichtag 15.09.2025), CC BY 4.0, bearbeitet; Orthofoto: basemap.at,
  CC BY 4.0, bearbeitet“ – erfüllt (Lizenzlink auf der Lizenzseite der App, To-do 1).
- Nicht verwendet: Stadt Wien Orthofoto/Baukörpermodell (CC BY 4.0, wäre zulässig), DORIS Oberösterreich (Gebäude
  aus OSM-Umrissen mit Höhe aus BEV DSM − DTM).
- Bewertung: grün.

### Norwegen – Kartverket Høydedata DTM1/DOM1 (CC BY 4.0), Stand 27.11.2026

- Kartverket „Høyde DTM1“ und „Høyde DOM1“ (nationales 1-m-Gelände- und Oberflächenmodell aus Laserdaten,
  hoydedata.no; COG je 15 × 15 km unter nedlasting.geonorge.no/hoydedata, EPSG:25833): Datenkatalog data.norge.no
  (https://data.norge.no/en/datasets/1a7327eb-1fa5-3432-8dea-fc198a5ede13/hoyde-dtm1, DOM1
  https://data.norge.no/en/datasets/235ee40f-2eab-3715-bc4e-c7f9152f771e/hoyde-dom1) nennt für die Verteilung
  „Creative Commons Attribution 4.0 International“, „Open license“; Geonorge-Metadaten
  https://kartkatalog.geonorge.no/Metadata/uuid/0442c622-6639-4024-86be-846de8c15bb2.
- Kartverket, Vilkår for bruk (https://www.kartverket.no/api-og-data/vilkar-for-bruk): „Kartverkets gratisprodukt er
  lisensierte etter Creative Commons Navngivelse 4.0 international (CC BY 4.0)“, „frigitt for gratis bruk til både
  kommersielle og ikkje-kommersielle føremål“; Namensnennung „© Kartverket“, wo möglich mit Link. Die Einschränkung für
  Geovekst-Daten betrifft nur die WMS-/Cache-Kartendienste (Zoom 12–20), die wir nicht nutzen.
- Luftbild: Norge i bilder (Geovekst) ist **nicht** offen → nicht verwendet; Bodenbild synthetisch aus Sentinel-2 + OSM
  wie in Grossbritannien. Gebäude: OSM-Umrisse mit Höhe aus DOM1 − DTM1 (FKB-Bygning ist Geovekst, nicht offen).
- Frühere Angabe „NLOD 2.0“ (WELTWEIT.md, NOTICE) ist überholt; Kartverket gibt die Höhendaten unter CC BY 4.0 ab.
- Heute: „Höhen: © Kartverket, Høydedata DTM1 und DOM1 1 m (hoydedata.no), CC BY 4.0, bearbeitet“ – erfüllt
  (Lizenzlink auf der Lizenzseite der App, To-do 1). Strecken `oslo-frognerkilen`, `naeroyfjord-gudvangen`.
- Bewertung: grün.

### Island – ÍslandsDEM v1.0 (CC BY 4.0), Stand 27.11.2026

- ÍslandsDEM v1.0 (landesweites Höhenmodell aus ArcticDEM-Stereomodellen und Lidar, Landmælingar Íslands mit dem Polar
  Geospatial Center; seit 2025 Teil der Náttúrufræðistofnun, Bereich Landmælingar og landupplýsingar), heruntergeladen
  als GeoTIFF 10 m (`https://ftp.natt.is/gisdata/raster/IslandsDEMv1.0_10x10m_isn2016_zmasl.tif`, ISN2016/Lambert
  EPSG:8088, 512er-Blöcke, zstd). Metadaten (Lýsigagnagátt,
  https://gatt.lmi.is/geonetwork/srv/api/records/e6712430-a63c-4ae5-9158-c89d16da6361): Zugang „no limitations to
  public access“, Nutzung „Attribution 4.0 International (CC BY 4.0)“.
- Náttúrufræðistofnun, „Open data“ (https://www.natt.is/en/resources/open-data): „The open data of the Natural Science
  Institute of Iceland is published under the CC BY 4.0“ (nach Gesetz 45/2018 über die Weiterverwendung öffentlicher
  Informationen); Beispiel der Namensnennung „‚IS 50V Vatnafar‘ by Náttúrufræðistofnun is licensed under CC BY 4.0“.
  Die alte LMÍ-Lizenzseite (OGL-ähnlich) leitet nicht mehr weiter (404).
- Luftbild: das LMÍ-Orthofoto im WMS (`grunnkort-loftmynd`) hat keine offene Lizenz → nicht verwendet; Bodenbild
  synthetisch aus Sentinel-2 + OSM. Kein offenes Oberflächenmodell (ArcticDEM wäre offen, misst aber Höhen über dem
  Ellipsoid, Geoid in Island ~65 m) → Gebäude aus OSM-Umrissen mit Voreinstellungshöhen.
- Heute: „Höhen: ÍslandsDEM v1.0 10 m, Náttúrufræðistofnun (vormals Landmælingar Íslands), CC BY 4.0
  (https://creativecommons.org/licenses/by/4.0/), bearbeitet“ – erfüllt. Strecken `thingvellir-thingvallavatn`,
  `reykjavik-fossvogur`.
- Bewertung: grün.

### Kanada – NRCan HRDEM (Open Government Licence – Canada 2.0), Stand 27.11.2026

- High Resolution Digital Elevation Model Mosaic (HRDEM Mosaic, CanElevation Series, Natural Resources Canada): 1-m-DTM
  und -DSM aus Lidar, COG je 500 × 500 km in EPSG:3979 (CGVD2013) auf AWS Open Data
  (`canelevation-dem.s3.ca-central-1.amazonaws.com/hrdem-mosaic-1m/<kachel>-mosaic-1m-dtm|dsm.tif`, Übersicht über den
  STAC-Katalog `datacube.services.geo.ca`, Lizenzfeld „OGL-Canada-2.0“). Datensatz im Open-Government-Portal:
  https://open.canada.ca/data/en/dataset/0fe65119-e96e-4a57-8bfe-9d9245fba06b.
- Open Government Licence – Canada 2.0 (https://open.canada.ca/en/open-government-licence-canada): weltweit,
  unentgeltlich, unbefristet; „Copy, modify, publish, translate, adapt, distribute“, „including for commercial purposes“;
  Bedingung: Nennung mit der Angabe des Anbieters, sonst „Contains information licensed under the Open Government
  Licence – Canada.“, wo möglich mit Link auf die Lizenz.
- Luftbild: keine offene Quelle für die Region Niagara (Ortho 2023 der Region nur gegen Gebühr; Ontario-Imagery für
  Niagara nicht offen; für Vancouver und Victoria nicht weiter geprüft) → Bodenbild synthetisch aus Sentinel-2 + OSM. Gebäude: OSM-Umrisse
  mit Höhe aus DSM − DTM.
- Heute: „Höhen: Natural Resources Canada, High Resolution Digital Elevation Model (HRDEM, CanElevation) DTM/DSM 1 m,
  Contains information licensed under the Open Government Licence – Canada, bearbeitet“ – erfüllt (Lizenzlink auf der
  Lizenzseite der App, To-do 1). Strecken `stcatharines-henley`, `vancouver-coal-harbour`,
  `victoria-elk-lake`.
- Bewertung: grün.

### USA – USGS 3DEP (gemeinfrei) und MassGIS Orthofoto (ohne Einschränkungen), Stand 27.11.2026

- USGS 3D Elevation Program: 1-m-DEM `MA_CentralEastern_2021_B21` (COG, prd-tnm.s3.amazonaws.com) und die Lidar-Punktwolke
  `MA_CentralEastern_1_2021` (Entwine Point Tiles, AWS Open Data „usgs-lidar-public“), daraus unser DSM (höchster Punkt
  je 1-m-Zelle). USGS-Richtlinie „Copyrights and Credits“
  (https://www.usgs.gov/information-policies-and-instructions/copyrights-and-credits): „USGS-authored or produced data and
  information are in the public domain“ (U.S. Government Work, 17 U.S.C. § 105); Nennung erbeten („Credit: U.S.
  Geological Survey“), kein Anschein einer Billigung. NOAA-InPort-Eintrag 69417 (Punktwolke): „Access Constraints: None“,
  Use Constraints nur Haftungshinweis.
- MassGIS (Bureau of Geographic Information, Commonwealth of Massachusetts), Luftbild Frühjahr 2023 (15 cm, laubfrei),
  Kacheldienst `orthos2023` auf ArcGIS Online: Lizenzfeld des Elements „2023 Color Orthos“ (Besitzer MassEOEEA): „No
  restrictions apply to these data. … Acknowledgement of MassGIS would be appreciated for products derived from these
  data.“ Copyright-Feld des Dienstes: „MassGIS“.
- Heute: „Höhen: U.S. Geological Survey, 3D Elevation Program (3DEP) … (gemeinfrei/public domain), bearbeitet;
  Orthofoto: MassGIS (Bureau of Geographic Information), Commonwealth of Massachusetts, Luftbild Frühjahr 2023,
  bearbeitet“ – erfüllt beide (Nennung freiwillig).
- Nicht verwendet: Cambridge GIS / BPDA-3D-Gebäudemodelle (Lizenz nicht eindeutig), MassGIS-Gebäudegrundrisse (wären
  zulässig; OSM ist in Boston/Cambridge vollständig). Gebäude aus OSM-Umrissen mit Höhe aus dem USGS-DSM − DTM.
- Bewertung: grün.

### Südamerika – IPP Rio de Janeiro (CC BY 4.0) und Microsoft Global ML Building Footprints (CDLA Permissive 2.0), Stand 27.11.2026

- Rio de Janeiro, Gebäude: ArcGIS-Item „Edificações (2013)“ des Kontos PrefeituraRio
  (https://www.arcgis.com/home/item.html?id=124f1607b57d4292af5c0dfc2ff8572c), accessInformation „Instituto Pereira
  Passos, PCRJ“, licenseInfo „This work is licensed under a Creative Commons Attribution 4.0 International License“.
  Restitution 1 : 2000 aus Bildern 2013 mit Höhen (ALTURA, BASE, TOPO). CC BY 4.0 erlaubt Bearbeitung und kommerzielle
  Nutzung mit Namensnennung, Lizenzhinweis und Bearbeitungsvermerk. Heute: „Gebäude: Instituto Pereira Passos (IPP),
  Prefeitura da Cidade do Rio de Janeiro – Edificações (2013), CC BY 4.0 (Link), bearbeitet“ – erfüllt.
- Rio, Luftbild: Die IPP-Mosaike (z. B. „Mosaico 2019“) tragen „Uso público, citadas as fontes e mantidas as
  informações originais“ – Veränderungen nicht erlaubt bzw. unklar → **nicht verwendet**; Bodenbild synthetisch aus
  Sentinel-2 + OSM. Ein offenes Geländemodell des IPP mit klarer Lizenz wurde nicht gefunden → Copernicus GLO-30.
- Tigre (Argentinien), Gebäude: Microsoft Global ML Building Footprints
  (https://github.com/microsoft/GlobalMLBuildingFootprints): „This data is licensed by Microsoft under the CDLA
  Permissive 2.0“ (https://cdla.dev/permissive-2-0/; früher ODbL). § 3.1: „This agreement does not impose any
  restriction or obligations with respect to the use, modification, or sharing of Results“ – die Szene ist ein
  Ergebnis; wer die Daten selbst weitergibt, muss den Lizenztext beilegen (§ 2.1; tun wir nicht, Rohdaten nicht im
  Repo). Genannt wird Microsoft trotzdem in `attribution`.
- Übrige Quellen beider Strecken: Copernicus DEM GLO-30, Sentinel-2, OSM (wie oben).
- Bewertung: grün.

### Amazonas – Meta/WRI High Resolution Canopy Height Maps (CC BY 4.0), Stand 27.11.2026

- Quelle: AWS Open Data Registry „High Resolution Canopy Height Maps by WRI and Meta“
  (https://registry.opendata.aws/dataforgood-fb-forests/), verwaltet von Meta (Data for Good); Lizenz laut Registry
  https://creativecommons.org/licenses/by/4.0/ (CC BY 4.0); erbetene Zitierung „Meta and World Resources Institude (WRI)
  - 2024. High Resolution Canopy Height Maps (CHM)“ (Schreibweise im Original) und Bildquelle „© 2016 Maxar“.
  Fachlich: Tolan et al. (2024), Remote Sensing of Environment 300, 113888.
- Daten: S3 `dataforgood-fb-data/forests/v1/alsgedi_global_v6_float/chm/<quadkey>.tif` (Stufe 9, EPSG:3857,
  ~1,2 m, uint8 m); amazonas.py liest nur den Ausschnitt des Kerngebiets (/vsicurl) und legt daraus prozedural
  Bäume an (Lage, Höhe; bearbeitet). CC BY 4.0 erlaubt Bearbeitung und kommerzielle Nutzung mit Namensnennung,
  Lizenzlink und Bearbeitungsvermerk. Heute in `attribution` der Amazonas-Gebiete: „Wald: Meta and World Resources
  Institute (WRI) – High Resolution Canopy Height Maps (2024), CC BY 4.0, Bildquelle © 2016 Maxar, bearbeitet“ – erfüllt;
  NOTICE ergänzt.
- Gebiete: anavilhanas (Brasilien), iquitos-belen (Peru). Übrige Quellen: Copernicus DEM GLO-30, Sentinel-2, OSM.
- Bewertung: grün.

### Niederlande – AHN (CC0), PDOK Luchtfoto Beeldmateriaal Nederland (CC BY 4.0), 3DBAG (CC BY 4.0), Stand 27.11.2026

- AHN4 DTM/DSM 0,5 m über PDOK-WCS `service.pdok.nl/rws/ahn/wcs/v1_0`: GetCapabilities nennt
  „AccessConstraints: otherRestrictions; Geen beperkingen; http://creativecommons.org/publicdomain/zero/1.0/“ (CC0 1.0).
  Keine Pflicht zur Namensnennung; genannt als „AHN – Actueel Hoogtebestand Nederland (CC0 1.0)“.
- Luchtfoto RGB (Actueel_orthoHR 8 cm, Actueel_ortho25) über PDOK-WMS `service.pdok.nl/hwh/luchtfotorgb/wms/v1_0`:
  Datensätze der Jahrgänge 2024/2026 auf data.overheid.nl mit Lizenz CC BY 4.0, Namensnennung „Beeldmateriaal
  Nederland“ (beeldmateriaal.nl). Ältere Jahrgänge (vor 2021) hatten teils keine CC-BY-Angabe; verwendet wird nur
  „Actueel“ (2025/2026). In `attribution`: „Beeldmateriaal Nederland (beeldmateriaal.nl, via PDOK), CC BY 4.0, bearbeitet“.
- 3DBAG (tudelft3d / 3DGI), WFS `data.3dbag.nl/api/BAG3D/wfs`, Layer lod22 (Grundrisse mit Höhenattributen):
  docs.3dbag.nl/en/copyright: CC BY 4.0, verlangte Nennung „© 3DBAG by tudelft3d and 3DGI“ mit Link (digital),
  Lizenz und Änderungsvermerk. In `attribution`: „© 3DBAG by tudelft3d and 3DGI (3dbag.nl), CC BY 4.0, bearbeitet“.
- Gebiet: amsterdam-amstel-grachten. Übrige Quellen: Copernicus DEM GLO-30, OSM.
- Bewertung: grün.

### Italien (Venedig) – nur Copernicus, Sentinel-2 und OSM, Stand 27.11.2026

- Regione Veneto stellt LiDAR-DTM/DSM unter IODL 2.0 bereit, aber ohne auffindbaren WCS/Download für die Altstadt;
  das nationale LiDAR des Piano Straordinario di Telerilevamento hat je Datensatz eigene Lizenzen (teils CC BY 4.0)
  und für die Lagune keinen gefundenen Dienst. Deshalb für `venezia-canal-grande` nur Copernicus DEM GLO-30
  (eingeebnet), synthetisches Luftbild aus Sentinel-2 und OSM, Gebäude aus OSM-Umrissen mit Voreinstellungshöhen.
- Bewertung: grün (keine neuen Quellen).

### GSI Japan – 国土地理院コンテンツ利用規約 / PDL1.0 (地理院タイル 写真, 標高タイル, 地理院地図Vector)

- Bedingungen: 国土地理院コンテンツ利用規約 (令和7年11月20日改正), https://www.gsi.go.jp/kikakuchousei/kikakuchousei40182.html
  – Grundlage ist 公共データ利用規約（第1.0版）(PDL1.0, https://www.digital.go.jp/resources/open_data/public_data_license_v1.0):
  „複製、公衆送信、翻訳・変形等の翻案等、自由に利用できます。商用利用も可能です。“; CC BY 4.0-kompatibel (1.7.3).
- Pflichten (GSI-Bedingungen): „コンテンツを利用する際は、出典を記載してください。“ und
  „コンテンツを編集・加工等して利用する場合は、上記出典とは別に、編集・加工等を行ったことを記載してください。“
  Beispiel: „地理院タイル （標高タイル（基盤地図情報数値標高モデル））を加工して作成“. Bearbeitetes darf nicht so
  erscheinen, als habe es das GSI erstellt.
- **写真 (seamlessphoto)**: Laut Kachelliste (https://maps.gsi.go.jp/development/ichiran.html) in der Gruppe „基本測量成果
  以外で出典の記載のみで利用可能なもの … 申請なくご利用いただけます“ → nur Quellenangabe, kein Antrag. Wo Kacheln
  GRUS-Satellitenbilder enthalten, zusätzlich „GRUS画像（© Axelspace）“ (für unsere Gebiete Tokio/Toda/Ōtsu bei z18
  unwahrscheinlich, bei Gelegenheit prüfen).
- **地理院地図Vector (Gebäude Ōtsu)**: laut https://www.gsi.go.jp/LAW/2930-index.html kein Gegenstand des
  Survey-Act-Antrags, sondern nur der Nutzungsbedingungen → grün mit Bearbeitungshinweis.
- **標高タイル (DEM5A/DEM10B = 基盤地図情報 数値標高モデル)**: Ergebnis der Grundvermessung (基本測量成果). GSI-FAQ
  (https://www.gsi.go.jp/LAW/2930-qa.html): Q2-4 – wer aus 基盤地図情報（数値標高モデル） eine „立体的な地図“ erstellt,
  braucht einen „測量成果の使用承認申請書“ nach Art. 30; Q5-4 – 基盤地図情報 wird „営利・非営利に関わらず … 無償で
  承認“; Q1-12 – nur das Echtzeit-Einbinden von Kacheln vom GSI-Server ist ohne Antrag möglich (das tun wir nicht, wir
  backen die Höhen in die Szene); Q5-2 – eine Genehmigungsnummer müsste dann sichtbar angezeigt werden. Ob unsere
  3D-Szene unter Art. 30 fällt, ist nicht sicher (Spiel-Landschaft, keine Karte), aber nach Q2-4 naheliegend.
- Bewertung: Foto und Vector grün, Höhen gelb; Namensnennung gelb (Bearbeitungshinweis fehlt).

### MLIT Project PLATEAU – PDL1.0 (Toda 2022, Itabashi/Sumida/Taitō/Chūō/Kōtō 2025)

- Site Policy https://www.mlit.go.jp/plateau/site-policy/: Nutzung nach PDL1.0, „クリエイティブ・コモンズ・ライセンス
  の表示4.0 国際ライセンス … と互換性があります“; Urheberrecht an den 3D-Stadtmodellen bei den jeweiligen Gemeinden.
- Datensatz Toda (G空間情報センター, `package_show?id=plateau-11224-toda-shi-2022`): „商用利用も含め、どなたでも無償で
  自由にご利用いただけます。“
- Pflichten: Quellenangabe („出典：…（国土交通省）…“) und gesondert „編集・加工等を行ったこと“; nicht als MLIT-Werk
  ausgeben. Hinweis der Site Policy auf Survey Act für öffentliche Vermessungsergebnisse: die PLATEAU-Daten sind
  bereits genehmigt erstellt; nach GSI-FAQ Q1-24 braucht die weitere Nutzung genehmigter Ergebnisse keinen neuen Antrag.
- Bewertung: grün; Namensnennung gelb (Bearbeitungshinweis fehlt).

### Environment Agency (UK) – Open Government Licence v3.0 (LIDAR Composite DTM, First Return DSM)

- Lizenz: https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/ – „You are free to: copy, publish,
  distribute and transmit the Information; adapt the Information; exploit the Information commercially and
  non-commercially … by including it in your own product or application.“ Pflicht: „acknowledge the source of the
  Information in your product or application by including or linking to any attribution statement specified by the
  Information Provider(s) and, where possible, provide a link to this licence“. Kein Anschein offizieller Billigung.
- Heute: „© Environment Agency copyright and/or database right 2025, Open Government Licence v3.0“ – genügt; Link auf
  die OGL in der Lizenzseite ergänzen.
- Bewertung: grün.

### Copernicus DEM GLO-30 (COP-DEM-GLO-30-F „Full, Free & Open“)

- Lizenz: „Licence for the use of the Copernicus WorldDEM-30“
  (https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf).
- Art. 2: „General Public“ = „any natural or legal person“. Art. 4: Rechte zu „(a) reproduction; (b) distribution;
  (c) communication to the General Public; (d) adaptation, modification and combination with other data and
  information“. Art. 5: „free of charge“. Keine Einschränkung auf nicht-kommerzielle Nutzung. Art. 3: weltweit, zeitlich
  unbegrenzt.
- Art. 6 (Pflichten):
  - (a) unverändert: „© DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the
    European Union and ESA; all rights reserved.“
  - **(b) bearbeitet** (unser Fall): „produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and
    Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved“.
  - **(c)** in einer Lizenz oder einem Rechtshinweis zur Weitergabe der Satz (oder Übersetzung): „The organisations in
    charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus
    WorldDEM-30“.
  - (d) kein Eindruck offizieller Billigung; Marken „Copernicus“/„WorldDEM“ nicht als Logo verwenden.
- Heute: Übersetzung von (a) ohne „produced using“ und ohne „all rights reserved“; Satz (c) fehlt ganz.
- Bewertung: Nutzung grün in allen Szenarien, Namensnennung gelb – betrifft das Bundle (`rhein-basel`).

### Copernicus Sentinel-2 (synthetisches Luftbild Oxford, Umgebungsfarben)

- „Legal notice on the use of Copernicus Sentinel Data and Service Information“ (EU-Kommission, nach VO (EU) 377/2014 und
  Delegierter VO 1159/2013; https://sentinels.copernicus.eu/documents/247904/690755/Sentinel_Data_Legal_Notice): freier
  Zugang für „(a) reproduction; (b) distribution; (c) communication to the public; (d) adaptation, modification and
  combination with other data and information“; bearbeitet: „Contains modified Copernicus Sentinel data [Year]“.
- Heute: „Contains modified Copernicus Sentinel data 2025“ – erfüllt.
- Bewertung: grün.

### OpenStreetMap – Open Database License 1.0 (Wasserflächen, Stege, Brückenumrisse, Gebäudeumrisse, Oxford-Bodenbild)

- Lizenz: https://opendatacommons.org/licenses/odbl/1-0/
  - Def. „Produced Work“: ein Werk „resulting from using the whole or a Substantial part of the Contents“.
  - 4.3: „if You Publicly Use a Produced Work, You must include a notice associated with the Produced Work reasonably
    calculated to make any Person … aware that Content was obtained from the Database … and that it is available under
    this License.“
  - 4.5(b): „Using this Database, a Derivative of this Database, or a Substantial part of the Contents, in a Produced Work
    does not create a Derivative Database for purposes of Section 4.4.“ → **Kein Share-Alike für die Szenen.**
  - 4.6: „If You Publicly Use a Derivative Database or a Produced Work from a Derivative Database, You must also offer to
    recipients of the Derivative Database or Produced Work a copy in a machine readable form of: a. The entire Derivative
    Database; or b. A file containing all of the alterations made to the Database or the method of making the alterations
    to the Database …“ (über das Internet kostenlos).
- Einordnung der USDZ-Szene: Nach der OSMF-Richtlinie „Produced Work“
  (https://osmfoundation.org/wiki/Licence/Community_Guidelines/Produced_Work_-_Guideline) ist ein Ergebnis eine Datenbank,
  wenn es „intended for the extraction of the original data“ ist; Bilder und Renderings sind typischerweise Produced Works.
  Eine 3D-Szene für ein Ruderspiel ist nicht zum Herausziehen von Geodaten gedacht → **Produced Work** (3D ist in der
  Richtlinie nicht ausdrücklich behandelt; vertretbare, übliche Auslegung).
- Abgeleitete Datenbank im Hintergrund: Wo OSM-Objekte verändert oder mit anderen Daten **desselben Objekttyps** verknüpft
  werden (Oxford: OSM-Gebäudeumrisse + Höhen aus dem EA-DSM; Wasserflächen mit ausgeschnittenen Stegen/Pfeilern), ist das
  nach der „Horizontal Map Layers“-Richtlinie keine blosse Sammlung mehr → abgeleitete Datenbank → 4.6. Das „method of
  making the alterations“ ist der Code in `tools/coursebuilder` (öffentlich, Apache-2.0). Reicht, wenn wir in App und NOTICE
  darauf verweisen.
- Namensnennung in Apps (OSMF Attribution Guidelines, vom Vorstand angenommen 25.06.2021,
  https://osmfoundation.org/wiki/Licence/Attribution_Guidelines): Nennung „OpenStreetMap“, klar machen, dass die Daten
  unter der ODbL stehen, z. B. Link auf openstreetmap.org/copyright; „© OpenStreetMap contributors“ ist zulässig. Für
  Spiele: „splash screen on application startup, in the game view, during gameplay“ oder „on the credits page, in the menu“;
  die Lizenzinformation muss auffindbar sein.
- Öffentliches Repo: `course.json` enthält die Streckenlinie `path_xz` (Uferlinie mit festem Abstand, bei `water_source:
  osm` aus OSM abgeleitet). Eine einzelne geglättete Linie je Strecke liegt weit unter der Schwelle der
  OSMF-Richtlinie „Substantial“ („Less than 100 Features“ ist unwesentlich;
  https://osmfoundation.org/wiki/Licence/Community_Guidelines/Substantial_-_Guideline) → keine ODbL-Pflichten für das Repo.
- Kommerziell / App Store: Die ODbL unterscheidet nicht nach kommerziell; Produced Works dürfen in eine Bezahl-App.
- Heute: „© OpenStreetMap contributors (ODbL)“ in Streckenansicht und Einstellungen, ohne Link, ohne Hinweis auf 4.6.
- Bewertung: Nutzung grün, Namensnennung gelb.

### Monk Skin Tone Scale – CC BY 4.0 (nebenbei)

- CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/): kommerziell und bearbeitet erlaubt, Namensnennung mit Link
  auf die Lizenz. Die CC-BY-Angabe stammt aus Sekundärquellen (Wikipedia, Google-Blog); die Seite skintone.google liess
  sich nicht automatisch lesen – Wortlaut einmal von Hand prüfen.
- Heute in der App: „Monk Skin Tone Scale von Dr. Ellis Monk, CC BY 4.0“ – genügt, Link ergänzen.

## To-dos

**Vor dem Store-Start (Bundle)**

1. **Lizenzseite in der App** (Einstellungen → „Quellen und Lizenzen“ → „Lizenzen der Geodaten“): je Quelle Wortlaut,
   Lizenzname **mit Link** auf den Lizenztext (dl-de/by-2-0, dl-de/zero-2-0, Licence Ouverte 2.0, OGL v3, ODbL, PDL1.0,
   CC BY 4.0, Copernicus-Lizenz, swisstopo-Bedingungen).
2. **Copernicus DEM** in allen `attribution`-Feldern (und NOTICE) auf den Art.-6(b)-Wortlaut umstellen: „produced using
   Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by
   the European Union and ESA; all rights reserved“ (den Vermerk im englischen Original lassen; für den Haftungssatz
   erlaubt die Lizenz ausdrücklich eine Übersetzung). Auf der Lizenzseite den Satz: „The organisations in charge of the Copernicus
   programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30.“
3. **OSM**: „© OpenStreetMap contributors, ODbL“ mit Link auf https://www.openstreetmap.org/copyright; auf der Lizenzseite
   und in NOTICE: „Teile der Szenen beruhen auf veränderten OSM-Daten; das Verfahren der Veränderung ist der öffentliche
   Code unter tools/coursebuilder (<Repo-URL>)“ (ODbL 4.6 b).
4. **LGB Brandenburg**: „© GeoBasis-DE/LGB (<Jahr>), dl-de/by-2-0, Daten geändert“; prüfen, welche LGB-Produkte in
   Grünau/Wannsee/Spree-Mitte tatsächlich verbaut sind (DGM1, DOP20, LoD2, bDOM) und alle nennen.
5. **Quellen auch in der Fahrt sichtbar**: kurze Einblendung beim Laden/Start einer Strecke (z. B. 5 s unten in der Ecke)
   – entspricht den OSM-Richtlinien für Spiele und macht die übrigen Nennungen robuster. Die Streckenansicht allein ist
   vertretbar, aber knapp.

**Vor dem Veröffentlichen der Server-Strecken**

6. **LGV Hamburg**: „…, Datenlizenz Deutschland – Namensnennung – 2.0, bearbeitet“.
7. **Japan**: Bearbeitungshinweise ergänzen, z. B. „地理院タイル（全国最新写真（シームレス）、標高タイル）を加工して作成“,
   „地理院地図Vector（基盤地図情報）を加工して作成“, „3D都市モデル（Project PLATEAU）<Stadt>（<Jahr>年度）（国土交通省）を
   加工して作成“; Link auf die GSI-Kachelliste.
8. **Japan, GSI-Höhen**: Falk entscheidet: über „地図の利用手続ナビ“/Anfrageformular beim GSI klären oder den (kostenlosen)
   使用承認申請 für 基盤地図情報 数値標高モデル stellen; bis dahin Toda, Tokio-Sumida und Ōtsu nicht öffentlich
   ausliefern. Eine allfällige Genehmigungsnummer in `attribution` aufnehmen (Q5-2).
9. **Polen**: GUGiK kurz bestätigen lassen, dass das NMPT unter Art. 40a ust. 2 pkt 1 fällt (oder auf NMT + Gebäudehöhen
   aus BDOT10k ausweichen).
10. **IGN**: statt „(2026)“ das Aktualisierungsdatum der verwendeten Ausgabe je Produkt nennen.

**Repo und NOTICE**

11. In `NOTICE` (und kurz in `README.md`) ausdrücklich: „Files under `courses/` other than code – preview, minimap and
    overview images and the geodata in course.json – are not licensed under Apache-2.0; they are subject to the source
    licences listed in each course.json and below.“
12. NOTICE nachziehen: Copernicus-Wortlaut (To-do 2), OSM-4.6-Hinweis (To-do 3), Japan-Bearbeitungshinweis, Link je Lizenz.
13. Bei jeder neuen Quelle: Lizenz und genauen Wortlaut je Datensatz prüfen (Berlin z. B. hat Produkte unter Zero und
    unter Namensnennung) und in `docs/WELTWEIT.md` Tabelle „Namensnennung“ eintragen.

## Nicht geprüft

- Apple- und Google-Store-Bedingungen selbst (keine Konflikte mit den offenen Lizenzen bekannt; die ODbL-Klausel 4.7 zu
  technischen Schutzmassnahmen betrifft die Weitergabe von Datenbanken, nicht Produced Works).
- Nutzungsbedingungen der Download-Dienste (Geoportal-Regulamin Polen, Overpass-API, Earth Search) – betreffen den Abruf,
  nicht die Weitergabe.
- Marken- und Persönlichkeitsrechte an Gebäuden/Bootshäusern in den Szenen (Panoramafreiheit) – ausserhalb des Auftrags.
