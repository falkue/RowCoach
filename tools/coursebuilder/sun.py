"""Sonnenstand nach dem NOAA-Verfahren (Meeus, vereinfacht), wie RowCoachKit/SolarPosition.swift.

Für Vorschauen zu Tageszeiten (preview.py --time) und als Gegenprobe der Swift-Tests. Beide Fassungen rechnen
dieselben Formeln; ändert sich eine, die andere nachziehen.

  azimut: Grad ab Nord im Uhrzeigersinn, hoehe: Grad über dem Horizont (mit Refraktion)

Tageszeiten der App (SunPreset in RowCoachKit): Sommersonnenwende (21. Juni) des laufenden Jahres, relativ zum
wahren Mittag am Ort: Morgen −5,5 h, Mittag 0 h, Abend +7,25 h; "nachmittag" ist die feste Bake-Sonne 235°/48°.

Aufruf zum Prüfen: .venv/bin/python sun.py 47.3769 8.5417 2026-06-21T11:28:00Z
"""
import math
import sys
from datetime import datetime, timedelta, timezone

PRESET_OFFSET_H = {"morgen": -5.5, "mittag": 0.0, "abend": 7.25}
FIXED_AFTERNOON = (235.0, 48.0)
MIN_SCENE_ELEVATION = 2.0


def _jd(dt):
    return dt.timestamp() / 86400.0 + 2440587.5


def _core(dt):
    """(Deklination in rad, Zeitgleichung in Minuten)"""
    T = (_jd(dt) - 2451545.0) / 36525.0
    L0 = (280.46646 + T * (36000.76983 + T * 0.0003032)) % 360.0
    M = 357.52911 + T * (35999.05029 - 0.0001537 * T)
    e = 0.016708634 - T * (0.000042037 + 0.0000001267 * T)
    Mr = math.radians(M)
    C = (math.sin(Mr) * (1.914602 - T * (0.004817 + 0.000014 * T)) + math.sin(2 * Mr) * (0.019993 - 0.000101 * T)
         + math.sin(3 * Mr) * 0.000289)
    om = math.radians(125.04 - 1934.136 * T)
    lam = math.radians(L0 + C - 0.00569 - 0.00478 * math.sin(om))
    eps0 = 23 + (26 + (21.448 - T * (46.815 + T * (0.00059 - T * 0.001813))) / 60) / 60
    eps = math.radians(eps0 + 0.00256 * math.cos(om))
    decl = math.asin(math.sin(eps) * math.sin(lam))
    y = math.tan(eps / 2) ** 2
    L0r = math.radians(L0)
    eot = 4 * math.degrees(y * math.sin(2 * L0r) - 2 * e * math.sin(Mr) + 4 * e * y * math.sin(Mr) * math.cos(2 * L0r)
                           - 0.5 * y * y * math.sin(4 * L0r) - 1.25 * e * e * math.sin(2 * Mr))
    return decl, eot


def refraction(el):
    if el > 85:
        return 0.0
    t = math.tan(math.radians(el))
    if el > 5:
        r = 58.1 / t - 0.07 / t ** 3 + 0.000086 / t ** 5
    elif el > -0.575:
        r = 1735 + el * (-518.2 + el * (103.4 + el * (-12.79 + el * 0.711)))
    else:
        r = -20.772 / t
    return r / 3600.0


def position(dt, lat, lon, refract=True):
    """(Azimut, Höhe) in Grad für einen Zeitpunkt (datetime mit Zeitzone)."""
    dt = dt.astimezone(timezone.utc)
    decl, eot = _core(dt)
    minutes = dt.hour * 60 + dt.minute + dt.second / 60 + dt.microsecond / 6e7
    tst = minutes + eot + 4 * lon
    ha = math.radians(tst / 4 - 180)
    la = math.radians(lat)
    cz = math.sin(la) * math.sin(decl) + math.cos(la) * math.cos(decl) * math.cos(ha)
    zen = math.acos(max(-1.0, min(1.0, cz)))
    el = 90 - math.degrees(zen)
    az = (math.degrees(math.atan2(math.sin(ha), math.cos(ha) * math.sin(la) - math.tan(decl) * math.cos(la)))
          + 180) % 360
    if refract:
        el += refraction(el)
    return az, el


def solar_noon(dt, lon):
    """Wahrer Mittag (UTC) des wahren Sonnentags am Ort, der dt enthält."""
    dt = dt.astimezone(timezone.utc)
    solar = dt + timedelta(seconds=lon * 240)
    day0 = datetime(solar.year, solar.month, solar.day, tzinfo=timezone.utc) - timedelta(seconds=lon * 240)
    noon = day0 + timedelta(hours=12)
    for _ in range(2):
        _, eot = _core(noon)
        noon = day0 + timedelta(minutes=720 - eot)
    return noon


def preset_time(name, lon, year):
    noon = solar_noon(datetime(year, 6, 21, 12, tzinfo=timezone.utc), lon)
    return noon + timedelta(hours=PRESET_OFFSET_H[name])


def preset_position(name, lat, lon, year=2026):
    if name == "nachmittag":
        return FIXED_AFTERNOON
    return position(preset_time(name, lon, year), lat, lon)


def lv95_to_wgs84(e, n):
    """swisstopo-Näherung wie SwissProjection in RowCoachKit (Genauigkeit ~1 m)."""
    y = (e - 2_600_000) / 1e6
    x = (n - 1_200_000) / 1e6
    lam = 2.6779094 + 4.728982 * y + 0.791484 * y * x + 0.1306 * y * x * x - 0.0436 * y ** 3
    phi = 16.9023892 + 3.238272 * x - 0.270978 * y * y - 0.002528 * x * x - 0.0447 * y * y * x - 0.0140 * x ** 3
    return phi * 100 / 36, lam * 100 / 36


if __name__ == "__main__":
    lat, lon = float(sys.argv[1]), float(sys.argv[2])
    if len(sys.argv) > 3:
        t = datetime.fromisoformat(sys.argv[3].replace("Z", "+00:00"))
        print("Azimut %.3f°, Höhe %.3f°" % position(t, lat, lon))
    for p in ("morgen", "mittag", "abend"):
        t = preset_time(p, lon, 2026)
        print(p, t.isoformat(), "Azimut %.1f°, Höhe %.1f°" % position(t, lat, lon))
