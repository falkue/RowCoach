"""Sichtband als Zeitreihe auf der echten Strecke (course.json mit Ruderer-Bahnen), wie im Simulator."""
import json, math, sys
from pathlib import Path
from kit import *
from tests import hidden

REPO = Path(__file__).resolve().parents[2]

def load(cid):
    c = json.loads((REPO / 'App/Courses' / cid / 'course.json').read_text())
    course = dict(oneWayM=c['one_way_m'], turns=c['turns'], pathXZ=c['path_xz'])
    lanes = [dict(out=l['out_m'], back=l['back_m'], tout=l.get('turn_out_m', l['out_m']),
                  tback=l.get('turn_back_m', l['back_m']), obumps=l.get('out_bumps'), bbumps=l.get('back_bumps'))
             for l in c['traffic']['rower_lanes']]
    return course, lanes

def series(cid='zuerichsee-utoquai', density='normal', seed=2026, speed=4.0, minutes=20, window=30, verbose=False, far=30):
    course, lanes = load(cid)
    track = CourseTrack(course); laps = LapTrack(track)
    p = VirtualRowers(course, density, seed, lanes=lanes)
    win = []; cur = 0; total = 0; n = 0
    t = 0.0
    while t < minutes * 60:
        d = speed * t; x, z, h = laps.pose(d)
        own = dict(u=laps.split(d)[1], x=x, z=z, heading=h, speed=speed)
        p.update(t, own)
        fx, fz = -math.sin(h), -math.cos(h)
        inb = False
        for s in p.states(t, own):
            vx, vz = s['x'] - x, s['z'] - z; al = vx * fx + vz * fz; lat = abs(vx * fz - vz * fx)
            if 8 <= al + 4.5 <= far and math.atan2(lat, al + 4.5) <= math.radians(32): inb = True
        cur += inb; total += inb; n += 1
        if n % window == 0:
            win.append(cur / window); cur = 0
        t += 1
    return win, total / n

if __name__ == '__main__':
    dens = sys.argv[1] if len(sys.argv) > 1 else 'normal'
    for seed in (2026, 1, 2, 3):
        w, tot = series(density=dens, seed=seed)
        print(seed, f'gesamt {tot:.2f}', '5–20 min', f'{sum(w[10:]) / len(w[10:]):.2f}', ' '.join(f'{int(x*100):3d}' for x in w))
