# Python-Nachbau der Ruderer-Planung aus RowCoachKit (Traffic.swift, VirtualRowers.swift, Course.swift, Laps.swift) und der
# Ruderer-Tests aus TrafficTests.swift, damit sich die Logik auf der Spark (ohne Swift) prüfen lässt.
# Aufruf: python3 tests.py [cont|res|dens|guest|band|all] [Toleranzfaktor Stetigkeit, z. B. 1.01]
import math, sys
from kit import *
course = straight_course(2000)
track = CourseTrack(course)

def hidden(x, z, own):
    return hidden_from_camera(x, z, own)

def simulate(seed, density='normal', minutes=60, speed=4.0, docks=None, verbose=False):
    p = VirtualRowers(course, density, seed, lanes=DEFAULT_LANES, docks=docks)
    laps = LapTrack(track)
    run = dict(ids=set(), minOwn=1e9, minPair=1e9, minPairInfo=None, nearAtStart=0, near=0, steps=0, over=0, first={}, last={}, band=0, pops=[])
    lastAlong = {}; previous = {}; guestEver = set()
    t = 0.0
    while t < minutes*60:
        d = speed*t; x, z, h = laps.pose(d)
        own = dict(u=laps.split(d)[1], x=x, z=z, heading=h, speed=speed)
        p.update(t, own)
        st = p.states(t, own)
        if t == 0: run['nearAtStart'] = sum(1 for s in st if s['distance'] <= 150)
        fx, fz = -math.sin(h), -math.cos(h)
        near = False; inb = False
        guestIds = {r.id for r in p.rowers if r.isGuest}
        for i, s in enumerate(st):
            run['ids'].add(s['id'])
            if s['id'] not in run['first']:
                run['first'][s['id']] = (s['x'], s['z'])
                if t > 0 and s['id'] not in guestIds and not hidden(s['x'], s['z'], own): run['pops'].append(('auf', s['id'], t, s['distance']))
            previous[s['id']] = (s['x'], s['z'], own)
            run['last'][s['id']] = (s['x'], s['z'])
            run['minOwn'] = min(run['minOwn'], s['distance'])
            if s['distance'] <= 60: near = True
            for o in st[i+1:]:
                dd = math.hypot(o['x']-s['x'], o['z']-s['z'])
                if dd < run['minPair']:
                    run['minPair'] = dd; run['minPairInfo'] = (t, s['id'], o['id'], round(s['x'],1), round(s['z'],1))
            vx, vz = s['x']-x, s['z']-z; al = vx*fx+vz*fz; lat = abs(vx*fz-vz*fx)
            if 8 <= al+4.5 <= 30 and math.atan2(lat, al+4.5) <= math.radians(32): inb = True
            same = math.cos(s['heading']-h) > 0.5
            pr = lastAlong.get(s['id'])
            if same and lat < 80 and pr is not None and abs(al) < 40 and (pr < 0) != (al < 0): run['over'] += 1
            lastAlong[s['id']] = al if (same and lat < 80) else None
        if near: run['near'] += 1
        if inb: run['band'] += 1
        now = {s['id'] for s in st}
        for i_, pv in list(previous.items()):
            if i_ not in now:
                if not hidden(pv[0], pv[1], pv[2]) and i_ not in guestEver: run['pops'].append(('weg', i_, t))
                del previous[i_]
        guestEver |= guestIds
        run['guestEver'] = guestEver
        run['steps'] += 1; t += 1
    return run, p

def bezier(a, c, b):
    return [[(1-t)**2*a[0]+2*(1-t)*t*c[0]+t*t*b[0], (1-t)**2*a[1]+2*(1-t)*t*c[1]+t*t*b[1]] for t in [i/12 for i in range(13)]]

def test_continuity():
    fails = 0; worst = 0
    for spec in DEFAULT_LANES + [dict(out=-48, back=-16), dict(out=30, back=50)]:
        lane = RowerLane(spec, track); prev = lane.pose(0); w = 0.5
        while w <= lane.loopLength + 0.5:
            pp = lane.pose(w); dd = math.hypot(pp[0]-prev[0], pp[1]-prev[1]); worst = max(worst, dd)
            if dd >= 0.5 * TOL + 1e-6: fails += 1
            hd = math.atan2(math.sin(pp[2]-prev[2]), math.cos(pp[2]-prev[2]))
            if abs(hd) >= 0.1: fails += 1
            prev = pp; w += 0.5
        for u in range(0, 4000, 37):
            if abs(lane.u_from_w(lane.w_from_u(u)) - u) > 1e-6: fails += 1
    return fails, worst

def test_resident():
    res = []; over = 0
    for seed in (1, 7, 42, 2026):
        run, p = simulate(seed)
        ok = (p.residentCount == 6 and set(range(1, 7)) <= {r.id for r in p.rowers} and
              all(not any(r.id == i and r.hare is None for r in p.rowers) for i in run['ids'] - set(range(1, 7))) and
              not run['pops'] and run['minOwn'] >= 8 and run['minPair'] >= 7.99 and run['nearAtStart'] >= 1 and run['near']/run['steps'] >= 0.3)
        over += run['over']
        res.append((seed, ok, round(run['minOwn'],1), round(run['minPair'],2), run['minPairInfo'], run['pops'][:3], run['nearAtStart'], round(run['near']/run['steps'],2), round(run['band']/run['steps'],2)))
    return res, over

def test_density():
    out = []
    lowN = denseN = 0; ok = True
    for seed in range(1, 7):
        lo, _ = simulate(seed, 'low'); de, _ = simulate(seed, 'dense')
        lowN += lo['near']; denseN += de['near']
        if de['minPair'] < 7.99: ok = False; out.append((seed, de['minPair'], de['minPairInfo']))
    return ok and lowN < denseN, lowN, denseN, out

def test_band():
    lo = no = de = 0
    for seed in (1, 2, 3, 4):
        lo += simulate(seed, 'low')[0]['band']/3600; no += simulate(seed, 'normal')[0]['band']/3600; de += simulate(seed, 'dense')[0]['band']/3600
    return round(lo/4,3), round(no/4,3), round(de/4,3)

def test_guests():
    dock = dict(id='steg', lane=2, joinU=1050, enter=bezier([80, -1000], [27, -1010], [27, -1050]), exit=bezier([27, -1050], [27, -1090], [80, -1110]))
    run, p = simulate(4, 'dense', 120, docks=[dock])
    guests = run['guestEver']
    bad = []; left = 0
    for g in guests:
        f = run['first'][g]
        if math.hypot(f[0]-80, f[1]+1000) >= 8: bad.append(('start', g, f))
        if not any(r.id == g for r in p.rowers):
            left += 1; l = run['last'][g]
            if math.hypot(l[0]-80, l[1]+1110) >= 12: bad.append(('ende', g, l))
    return len(guests), left, bad, round(run['minOwn'],1), round(run['minPair'],2), run['minPairInfo']

TOL = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
if __name__ == '__main__':
    which = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if which in ('all', 'cont'): print('Stetigkeit', test_continuity())
    if which in ('all', 'res'): print('Residenten', test_resident())
    if which in ('all', 'dens'): print('Dichte', test_density())
    if which in ('all', 'guest'): print('Gäste', test_guests())
    if which in ('all', 'band'): print('Sichtband', test_band())
