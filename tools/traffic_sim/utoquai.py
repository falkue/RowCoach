"""Sichtband als Zeitreihe auf einer echten Strecke (course.json mit Ruderer-Bahnen), wie im Simulator.
Aufruf: python3 utoquai.py [Dichte] [Strecke] [Minuten] [Tempo m/s]
  Strecke: Kennung (courses/<id>/course.json, sonst App/Courses/<id>/course.json), Standard zuerichsee-utoquai.
  Sichtband: Ruderer 8–30 m vor der Kamera (4,5 m hinter dem Boot) bei ≤ 32° Peilung; auf Strecken, deren Linien nur
  den Hasen gehören (keine Bahnruderer), 8–45 m. Dazu: kleinster Abstand zum eigenen Boot und zwischen Ruderern,
  Auftauchen/Verschwinden im Bild (ohne Rundenwechsel auf one_way-Strecken und ohne Verschwinden ab 440 m)."""
import json, math, sys
from pathlib import Path
from kit import *
from tests import hidden

REPO = Path(__file__).resolve().parents[2]

def load(cid):
    f = REPO / 'courses' / cid / 'course.json'
    if not f.exists(): f = REPO / 'App/Courses' / cid / 'course.json'
    c = json.loads(f.read_text())
    course = dict(oneWayM=c['one_way_m'], turns=c['turns'], pathXZ=c['path_xz'], loop=bool(c.get('loop')))
    lanes = [dict(out=l['out_m'], back=l['back_m'], tout=l.get('turn_out_m', l['out_m']),
                  tback=l.get('turn_back_m', l['back_m']), obumps=l.get('out_bumps'), bbumps=l.get('back_bumps'),
                  open=l.get('open', False), reverse=l.get('reverse', False))
             for l in c['traffic']['rower_lanes']]
    return course, lanes

def series(cid='zuerichsee-utoquai', density='normal', seed=2026, speed=4.0, minutes=20, window=30, verbose=False, far=None):
    course, lanes = load(cid)
    track = CourseTrack(course); laps = LapTrack(track)
    p = VirtualRowers(course, density, seed, lanes=lanes)
    if far is None: far = 45 if p.residentCount == 0 else 30
    win = []; cur = 0; total = 0; n = 0
    stats = dict(minOwn=1e9, minPair=1e9, pops=0, far=far, residents=p.residentCount)
    prev = {}; lastLap = 0
    t = 0.0
    while t < minutes * 60:
        d = speed * t; x, z, h = laps.pose(d); lap, u = laps.split(d)
        own = dict(u=u, x=x, z=z, heading=h, speed=speed)
        p.update(t, own)
        fx, fz = -math.sin(h), -math.cos(h)
        inb = False
        st = p.states(t, own)
        restart = lap != lastLap and course['turns'] == 0 and not course.get('loop'); lastLap = lap
        now = {}
        for i, s in enumerate(st):
            vx, vz = s['x'] - x, s['z'] - z; al = vx * fx + vz * fz; lat = abs(vx * fz - vz * fx)
            if 8 <= al + 4.5 <= far and math.atan2(lat, al + 4.5) <= math.radians(32): inb = True
            stats['minOwn'] = min(stats['minOwn'], s['distance'])
            for o in st[i+1:]: stats['minPair'] = min(stats['minPair'], math.hypot(o['x']-s['x'], o['z']-s['z']))
            now[s['id']] = (s['x'], s['z'])
            if s['id'] not in prev and t > 0 and not restart and not hidden(s['x'], s['z'], own):
                stats['pops'] += 1
                if verbose: print('auf', t, s['id'], round(s['distance']))
        for i_, (px, pz, po) in prev.items():
            # schon fast 450 m weg: dort wird er ohnehin geparkt (verschwindet nicht im Bild)
            parked = math.hypot(px - po['x'], pz - po['z']) >= VirtualRowers.visibleRange - 10
            if i_ not in now and not restart and not parked and not hidden(px, pz, po):
                stats['pops'] += 1
                if verbose: print('weg', t, i_)
        prev = {k: (v[0], v[1], own) for k, v in now.items()}
        cur += inb; total += inb; n += 1
        if n % window == 0:
            win.append(cur / window); cur = 0
        t += 1
    return win, total / n, stats

if __name__ == '__main__':
    dens = sys.argv[1] if len(sys.argv) > 1 else 'normal'
    cid = sys.argv[2] if len(sys.argv) > 2 else 'zuerichsee-utoquai'
    minutes = float(sys.argv[3]) if len(sys.argv) > 3 else 20
    speed = float(sys.argv[4]) if len(sys.argv) > 4 else 4.0
    tots = []
    for seed in (2026, 1, 2, 3):
        w, tot, st = series(cid, density=dens, seed=seed, minutes=minutes, speed=speed)
        tots.append(tot)
        print(seed, f'gesamt {tot:.2f}', '5 min bis Ende', f'{sum(w[10:]) / max(len(w[10:]), 1):.2f}',
              f"Band 8–{st['far']} m, Bahnruderer {st['residents']}, min. Abstand eigenes Boot {st['minOwn']:.1f} m, "
              f"zwischen Ruderern {st['minPair']:.1f} m, im Bild auf/weg {st['pops']}")
        print('   ', ' '.join(f'{int(x*100):3d}' for x in w))
    print(f'Mittel {sum(tots)/len(tots):.3f}')
