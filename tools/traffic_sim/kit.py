"""1:1-Nachbau von RowCoachKit (Course.straight, CourseTrack, LapTrack, Centerline, RowerLane, VirtualRowers)."""
import math
M64 = (1 << 64) - 1
G = 0x9E3779B97F4A7C15
def rnd_swift(x):  # Swift .rounded() (to nearest, ties away from zero)
    return math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5)

class TrafficRandom:
    def __init__(self, seed): self.state = (seed + G) & M64
    def next(self):
        self.state = (self.state + G) & M64
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
        return z ^ (z >> 31)
    def unit(self): return (self.next() >> 11) / float(1 << 53)
    def uniform(self, a, b): return a + (b - a) * self.unit()
    def int(self, n): return self.next() % n if n > 0 else 0

def straight_course(one_way=2000.0, heading=0.0):
    n = max(int(rnd_swift(one_way / 2)), 1)
    dx, dz = -math.sin(heading), -math.cos(heading)
    pts = [[dx * one_way * i / n, dz * one_way * i / n] for i in range(n + 1)]
    return dict(oneWayM=one_way, turns=1, pathXZ=pts)

class CourseTrack:
    def __init__(self, course, returnOffset=12.0, turnBlend=40.0):
        self.course = course; self.returnOffset = returnOffset; self.turnBlend = turnBlend
        p = [tuple(q) for q in course['pathXZ']]
        c = [0.0]
        for i in range(1, len(p)): c.append(c[-1] + math.hypot(p[i][0]-p[i-1][0], p[i][1]-p[i-1][1]))
        self.pts, self.cum, self.geo = p, c, c[-1]
        seg = []
        for i in range(1, len(p)):
            dx, dz = p[i][0]-p[i-1][0], p[i][1]-p[i-1][1]; l = math.hypot(dx, dz)
            seg.append((dx/l, dz/l) if l > 1e-9 else (seg[-1] if seg else (0, -1)))
        t = []
        for i in range(len(p)):
            a, b = seg[max(i-1, 0)], seg[min(i, len(seg)-1)]
            sx, sz = a[0]+b[0], a[1]+b[1]; l = math.hypot(sx, sz)
            t.append((sx/l, sz/l) if l > 1e-9 else b)
        self.tangents = t
        L = course['oneWayM'] if course['oneWayM'] > 0 else self.geo
        self.oneWayLength = L
        self.hasTurn = course['turns'] > 0
        self.totalLength = 2*L if self.hasTurn else L
        D = abs(returnOffset)
        def alpha(r): return math.acos(min(1, max(-1, (D/(2*r)+1)/2))) if r > 0 else 0
        def half(r): return r*(math.pi+4*alpha(r))/2
        r = D/2
        if self.hasTurn and turnBlend > half(r):
            lo, hi = r, max(r, 1)
            while half(hi) < turnBlend: hi *= 2
            for _ in range(60):
                mid = (lo+hi)/2
                if half(mid) < turnBlend: lo = mid
                else: hi = mid
            r = (lo+hi)/2
        self.turnRadius = r; self.turnAlpha = alpha(r)
        self.turnHalf = min(half(r), L) if self.hasTurn else 0
    def sample(self, s):
        g = min(max(s, 0), self.oneWayLength) * self.geo / self.oneWayLength
        lo, hi = 0, len(self.cum)-1
        while hi - lo > 1:
            mid = (lo+hi)//2
            if self.cum[mid] <= g: lo = mid
            else: hi = mid
        segLen = self.cum[hi]-self.cum[lo]; u = (g-self.cum[lo])/segLen if segLen > 0 else 0
        a, b = self.pts[lo], self.pts[hi]; ta, tb = self.tangents[lo], self.tangents[hi]
        tx, tz = ta[0]+(tb[0]-ta[0])*u, ta[1]+(tb[1]-ta[1])*u; l = math.hypot(tx, tz)
        if l > 1e-9: tx /= l; tz /= l
        else: tx, tz = tb
        return (a[0]+(b[0]-a[0])*u, a[1]+(b[1]-a[1])*u), (tx, tz)
    def returnSide(self, t):
        sign = -1 if self.returnOffset < 0 else 1
        return (t[1]*sign, -t[0]*sign)
    def geometry(self, dd):
        L = self.oneWayLength; th = self.turnHalf
        if not self.hasTurn:
            return self.sample(dd)
        D = abs(self.returnOffset)
        if dd <= L - th or (th <= 0 and dd <= L): return self.sample(dd)
        if dd >= L + th:
            p, t = self.sample(self.totalLength - dd); n = self.returnSide(t)
            return (p[0]+n[0]*D, p[1]+n[1]*D), (-t[0], -t[1])
        p0, t0 = self.sample(L - th); n0 = self.returnSide(t0)
        R, al = self.turnRadius, self.turnAlpha
        arc = R*(math.pi+4*al); q = (dd-(L-th))/(2*th)*arc
        if q <= R*al:
            phi = q/R; psi = -phi; a = R*math.sin(phi); l = -R+R*math.cos(phi)
        elif q <= R*(math.pi+3*al):
            psi = -al+(q-R*al)/R; a = 2*R*math.sin(al)+R*math.sin(psi); l = R*(2*math.cos(al)-1)-R*math.cos(psi)
        else:
            psi = math.pi+al-(q-R*(math.pi+3*al))/R; a = -R*math.sin(psi); l = R*(4*math.cos(al)-1)+R*math.cos(psi)
        p = (p0[0]+a*t0[0]+l*n0[0], p0[1]+a*t0[1]+l*n0[1])
        d = (math.cos(psi)*t0[0]+math.sin(psi)*n0[0], math.cos(psi)*t0[1]+math.sin(psi)*n0[1])
        return p, d
    def pose(self, d):
        dd = min(max(d, 0), self.totalLength)
        p, g = self.geometry(dd)
        return p[0], p[1], math.atan2(-g[0], -g[1])

class LapTrack:
    def __init__(self, track):
        self.track = track
        L = track.oneWayLength; D = abs(track.returnOffset); R = track.turnRadius
        a = math.acos(min(1, max(-1, (D/(2*R)+1)/2))) if R > 0 else 0
        self.radius, self.alpha = R, a
        half = min(R*(math.pi+4*a)/2, L)
        self.loops = track.course['turns'] > 0 and R > 0 and half > 0 and L >= 2*half and track.totalLength > 0
        self.turnHalf = half if self.loops else 0
        x, z, h = track.pose(track.totalLength - (half if self.loops else 0))
        self.sx, self.sz = x, z
        dx, dz = -math.sin(h), -math.cos(h); self.tx, self.tz = dx, dz
        sign = -1 if track.returnOffset < 0 else 1
        self.nx, self.nz = dz*sign, -dx*sign
        self.lapLength = track.totalLength
    def split(self, d):
        if not (d > 0): return 0, 0.0
        lap = int(math.floor(d / self.lapLength)); s = d - lap*self.lapLength
        return lap, min(max(s, 0), self.lapLength)
    def pose(self, d):
        L2 = self.lapLength; lap, s = self.split(d)
        if self.loops:
            if lap >= 1 and s < self.turnHalf: return self.startTurn(self.turnHalf + s)
            if s > L2 - self.turnHalf: return self.startTurn(s - (L2 - self.turnHalf))
        return self.track.pose(s)
    def startTurn(self, rowQ):
        R, al = self.radius, self.alpha; arc = R*(math.pi+4*al)
        q = min(max(rowQ, 0), 2*self.turnHalf)/(2*self.turnHalf)*arc
        if q <= R*al:
            phi = q/R; psi = -phi; a = R*math.sin(phi); l = -R+R*math.cos(phi)
        elif q <= R*(math.pi+3*al):
            psi = -al+(q-R*al)/R; a = 2*R*math.sin(al)+R*math.sin(psi); l = R*(2*math.cos(al)-1)-R*math.cos(psi)
        else:
            psi = math.pi+al-(q-R*(math.pi+3*al))/R; a = -R*math.sin(psi); l = R*(4*math.cos(al)-1)+R*math.cos(psi)
        x = self.sx + a*self.tx + l*self.nx; z = self.sz + a*self.tz + l*self.nz
        dx = math.cos(psi)*self.tx + math.sin(psi)*self.nx; dz = math.cos(psi)*self.tz + math.sin(psi)*self.nz
        return x, z, math.atan2(-dx, -dz)

class Centerline:
    def __init__(self, course):
        self.ct = CourseTrack(course)  # gleiche Abtastung
        self.length = self.ct.oneWayLength
    def sample(self, s):
        if s < 0 or s > self.length:
            (x, z), (tx, tz) = self.sample_in(min(max(s, 0), self.length))
            e = s if s < 0 else s - self.length
            return (x+tx*e, z+tz*e), (tx, tz)
        return self.sample_in(s)
    def sample_in(self, s): return self.ct.sample(s)
    def point(self, s, lateral):
        (x, z), (tx, tz) = self.sample(s)
        return x + tz*lateral, z - tx*lateral

def mod(a, m):
    if not (m > 0) or not math.isfinite(a): return 0.0
    r = math.fmod(a, m)
    return r + m if r < 0 else r

START_BEHIND = 10.0
class RowerLane:
    def __init__(self, spec, track):
        out, back = spec['out'], spec['back']
        tOut = spec.get('tout', out); tBack = spec.get('tback', back)
        L = track.oneWayLength; D = abs(track.returnOffset); R = track.turnRadius
        al = math.acos(min(1, max(-1, (D/(2*R)+1)/2)))
        h = min(R*(math.pi+4*al)/2, L)
        self.spec = spec; self.oneWay = L; self.line = Centerline(track.course)
        self.half = h; self.ac = 2*R*math.sin(al)
        self.turnOut, self.turnBack = tOut, tBack
        self.rho = (tBack - tOut)/2; self.lc = (tBack + tOut)/2
        self.straight = L - 2*h; self.ramp = min(80, self.straight/2)
        self.loop = 2*self.ac + math.pi*self.rho
        self.startApproach = h + START_BEHIND
        self.startLoop = 2*self.startApproach + math.pi*self.rho
        self.loopLength = 2*self.straight + self.loop + self.startLoop
    def w_from_u(self, uIn):
        L, h = self.oneWay, self.half; u = mod(uIn, 2*L)
        a = self.startLoop/2; b = a+self.straight; c = b+self.loop; d = c+self.straight
        if u < h: return a*(u/h)
        if u < L-h: return a+(u-h)
        if u < L+h: return b+self.loop*(u-(L-h))/(2*h)
        if u < 2*L-h: return c+(u-(L+h))
        return d+self.startLoop/2*(u-(2*L-h))/h
    def u_from_w(self, wIn):
        L, h = self.oneWay, self.half; w = mod(wIn, self.loopLength)
        a = self.startLoop/2; b = a+self.straight; c = b+self.loop; d = c+self.straight
        if w < a: return h*w/a
        if w < b: return h+(w-a)
        if w < c: return (L-h)+2*h*(w-b)/self.loop
        if w < d: return (L+h)+(w-c)
        return (2*L-h)+h*(w-d)/(self.loopLength-d)
    def w_for_out_s(self, s):
        """Bahnparameter auf der Hinfahrt bei s (auch im letzten Stück der Startschlaufe, s ≥ half − startApproach)."""
        if s >= self.half: return self.w_from_u(s)
        return self.startLoop/2 + (s - self.half)
    def lateral(self, s, out):
        L, h = self.oneWay, self.half
        d = min(s-h, (L-h)-s)
        x = min(max(d/self.ramp, 0), 1) if self.ramp > 0 else 1
        wgt = 1 - x*x*(3-2*x)
        return self.spec['out']+(self.turnOut-self.spec['out'])*wgt if out else self.spec['back']+(self.turnBack-self.spec['back'])*wgt
    def straightPose(self, s, out):
        p = self.line.point(s, self.lateral(s, out))
        p0 = self.line.point(s-0.5, self.lateral(s-0.5, out)); p1 = self.line.point(s+0.5, self.lateral(s+0.5, out))
        dx, dz = p1[0]-p0[0], p1[1]-p0[1]; l = math.hypot(dx, dz)
        dx, dz = dx/l, dz/l
        return (p[0], p[1], dx, dz) if out else (p[0], p[1], -dx, -dz)
    def pose(self, wIn):
        L, h = self.oneWay, self.half; w = mod(wIn, self.loopLength)
        a = self.startLoop/2; b = a+self.straight; c = b+self.loop; d = c+self.straight
        if w < a or w >= d:
            g = a+w if w < a else w-d
            r = self.startArc(g, self.line.sample(h))
        elif w < b: r = self.straightPose(h+(w-a), True)
        elif w < c: r = self.turnLoop(w-b, self.line.sample(L-h))
        else: r = self.straightPose((L-h)-(w-c), False)
        return r[0], r[1], math.atan2(-r[2], -r[3])
    def turnLoop(self, g, f):
        (fx, fz), (tx, tz) = f; nx, nz = tz, -tx; ac, rho = self.ac, self.rho
        if g < ac: al, l, dx, dz = g, self.turnOut, tx, tz
        elif g < ac+math.pi*rho:
            th = (g-ac)/rho; al = ac+rho*math.sin(th); l = self.lc-rho*math.cos(th)
            dx = math.cos(th)*tx+math.sin(th)*nx; dz = math.cos(th)*tz+math.sin(th)*nz
        else: al, l, dx, dz = ac-(g-ac-math.pi*rho), self.turnBack, -tx, -tz
        return fx+tx*al+nx*l, fz+tz*al+nz*l, dx, dz
    def startArc(self, g, f):
        (fx, fz), (tx, tz) = f; nx, nz = tz, -tx; A, rho = self.startApproach, self.rho
        if g < A: al, l, dx, dz = -g, self.turnBack, -tx, -tz
        elif g < A+math.pi*rho:
            th = (g-A)/rho; al = -A-rho*math.sin(th); l = self.lc+rho*math.cos(th)
            dx = -math.cos(th)*tx-math.sin(th)*nx; dz = -math.cos(th)*tz-math.sin(th)*nz
        else: al, l, dx, dz = -A+(g-A-math.pi*rho), self.turnOut, tx, tz
        return fx+tx*al+nx*l, fz+tz*al+nz*l, dx, dz

class Polyline:
    def __init__(self, pts):
        self.xs = [p[0] for p in pts]; self.zs = [p[1] for p in pts]
        c = [0.0]
        for i in range(1, len(pts)): c.append(c[-1]+math.hypot(pts[i][0]-pts[i-1][0], pts[i][1]-pts[i-1][1]))
        self.cum = c; self.length = c[-1]
    def pose(self, sIn):
        s = min(max(sIn, 0), self.length); lo, hi = 0, len(self.cum)-1
        while hi-lo > 1:
            mid = (lo+hi)//2
            if self.cum[mid] <= s: lo = mid
            else: hi = mid
        seg = self.cum[hi]-self.cum[lo]; u = (s-self.cum[lo])/seg if seg > 0 else 0
        dx, dz = self.xs[hi]-self.xs[lo], self.zs[hi]-self.zs[lo]
        return self.xs[lo]+dx*u, self.zs[lo]+dz*u, math.atan2(-dx, -dz)

def hidden_from_camera(x, z, own, min_dist=15, cos_max=-0.3):
    """Ausser Sicht: weiter als 450 m oder hinter der Kamera (4,5 m hinter dem Boot; mehr als ca. 107° von der
    Blickrichtung und mindestens 15 m von der Kamera)."""
    fx, fz = -math.sin(own['heading']), -math.cos(own['heading'])
    cx, cz = own['x'] - fx*4.5, own['z'] - fz*4.5
    vx, vz = x-cx, z-cz; d = math.hypot(vx, vz)
    if math.hypot(x-own['x'], z-own['z']) >= 450: return True
    return d >= min_dist and (vx*fx + vz*fz)/d < cos_max

HARE_TARGET = (17, 22)

DENS = {
 'low': dict(per4=4, guest=(420, 720), maxg=1, hare=(120, 240), pace=(60, 150)),
 'normal': dict(per4=6, guest=(240, 480), maxg=1, hare=(10, 25), pace=(90, 240)),
 'dense': dict(per4=9, guest=(90, 180), maxg=2, hare=(5, 15), pace=(120, 300)),
}
DEFAULT_LANES = [dict(out=-9, back=22, tout=-16, tback=28), dict(out=-18, back=31, tout=-24, tback=36),
                 dict(out=-27, back=40, tout=-32, tback=44)]

class Rower:
    __slots__ = ('id','lane','factor','wobble','wobblePeriod','wobblePhase','colorIndex','planned','phase','dock','w','rowed','strokePhase','hare')
    def speedFactor(self, t):
        if self.hare is not None: return self.hare['current']
        return self.factor*(1+self.wobble*math.sin(2*math.pi/self.wobblePeriod*t+self.wobblePhase))
    def strokeRate(self, speed):
        return min(max(int(rnd_swift(18+(speed-3)*6)) + self.id % 3 - 1, 18), 32)
    @property
    def isGuest(self): return self.planned is not None

class VirtualRowers:
    visibleRange = 450.0; dockClearOwn = 250.0; dockClearRowers = 80.0; dockLaneGap = 120.0
    def __init__(self, course, density, seed, lanes=None, docks=None):
        tr = CourseTrack(course)
        specs = lanes if lanes is not None else DEFAULT_LANES
        self.lanes = [RowerLane(s, tr) for s in specs]
        self.docks = []
        for d in (docks or []):
            self.docks.append(dict(spec=d, enter=Polyline(d['enter']), exit=Polyline(d['exit'])))
        self.density = density; self.dp = DENS[density]
        rnd = TrafficRandom(seed)
        D = abs(tr.returnOffset)
        def closeness(l): return min(min(abs(v), abs(v-D)) for v in (l.spec['out'], l.spec['back']))
        order = sorted(range(len(self.lanes)), key=lambda i: closeness(self.lanes[i]))
        bands = [(0.90, 0.96), (1.08, 1.16), (0.80, 0.86), (0.96, 1.04), (1.16, 1.24)]
        f = [1.0]*len(self.lanes)
        for rank, li in enumerate(order): f[li] = rnd.uniform(*bands[min(rank, len(bands)-1)])
        self.laneFactors = f; self.innerLane = order[0] if order else None
        self.residentCount = 0 if not self.lanes else min(max(int(rnd_swift(self.dp['per4']*2*tr.oneWayLength/4000)), 2), 12)
        self.random = rnd; self.rowers = []; self.lastTime = None; self.lastBase = 1.2
        self.nextGuest = None; self.nextHare = None; self.nextId = 1
    def update(self, t, own):
        if not self.lanes: return
        base = max(own['speed'], 1.2)
        if self.lastTime is None:
            self.placeInitial(own, t); self.lastTime = t; self.lastBase = base
            self.nextGuest = t + self.random.uniform(*((20, 60) if self.density == 'dense' else (60, 150)))
            self.nextHare = t + self.random.uniform(*((5, 15) if self.density == 'dense' else (20, 60)))
            return
        dt = min(max(t - self.lastTime, 0), 5); self.lastTime = t; self.lastBase = base
        finished = set()
        for r in self.rowers:
            v = base*r.speedFactor(t)
            r.strokePhase += dt*r.strokeRate(v)/60; r.strokePhase -= math.floor(r.strokePhase)
            if r.phase == 'lane':
                lane = self.lanes[r.lane]; uBefore = lane.u_from_w(r.w)
                if r.hare is not None:
                    h = r.hare; L2 = 2*lane.oneWay
                    ahead = mod(uBefore - own['u'] + lane.oneWay, L2) - lane.oneWay
                    slow = h['paceFactor'] < 0.98
                    if h['phase'] != 'leave' and not slow and self.turnAhead(own['u'], lane, 60):
                        h['phase'] = 'leave'
                    # rechtzeitig vom Aufholtempo auf das Mitfahrtempo gehen: der Rest der Verzögerung (Zeitkonstante
                    # 6 s) trägt ihn noch (current − paceFactor) · Tempo · 6 m weiter
                    if h['phase'] == 'approach' and ahead + (h['current'] - h['paceFactor'])*base*6 >= h['target']:
                        h['phase'] = 'pace'; h['until'] = t + h['paceSeconds']
                    if h['phase'] == 'pace' and not slow and h['until'] is not None and t >= h['until']: h['phase'] = 'leave'
                    if h['phase'] == 'leave' and not h.get('handed'):
                        h['handed'] = True; self.handOver(t)
                    goal = h['paceFactor'] if h['phase'] == 'pace' else 1.35
                    h['current'] += (goal - h['current'])*min(dt/6, 1)
                    gone = (h['phase'] == 'leave' and ahead > self.visibleRange+20) or t - h['since'] > 900
                    # überholt (Mitfahrer oder langsamer): hinter dem Boot und ausser Sicht → sofort aus dem Spiel
                    # (nicht während der eigenen Wende bzw. Startkehre: dort dreht die Kamera schnell)
                    behind = h['phase'] != 'approach' and ahead < 0 and not self.nearTurn(own['u'], lane, 0)
                v = base*r.speedFactor(t)
                r.w += v*dt; r.rowed += v*dt
                if r.hare is not None:
                    # aus dem Spiel nur ausser Sicht, geprüft an der neuen Lage (gleiche Zeit wie das eigene Boot)
                    hx, hz, _ = lane.pose(r.w)
                    if (gone and hidden_from_camera(hx, hz, own, 20, -0.5)) or (behind and hidden_from_camera(hx, hz, own, 0, -0.26)):
                        finished.add(r.id)
                        if not r.hare.get('handed'): self.handOver(t)
                if r.planned is not None and r.rowed >= r.planned:
                    d = self.exitDock(r, uBefore, lane.u_from_w(r.w), own)
                    if d is not None:
                        ex = self.docks[d]['spec'].get('exitU', self.docks[d]['spec']['joinU'])
                        over = mod(lane.u_from_w(r.w) - ex, 2*lane.oneWay)
                        r.phase = 'leaving'; r.dock = d; r.w = min(over, 5)
            elif r.phase == 'entering':
                d = self.docks[r.dock]; r.w += 0.7*v*dt
                if r.w >= d['enter'].length:
                    r.phase = 'lane'; r.w = self.lanes[r.lane].w_from_u(d['spec']['joinU']) + (r.w - d['enter'].length)
            else:
                d = self.docks[r.dock]; r.w += 0.7*v*dt
                if r.w >= d['exit'].length: finished.add(r.id)
        if finished: self.rowers = [r for r in self.rowers if r.id not in finished]
        if self.nextHare is not None and t >= self.nextHare:
            if self.spawnHare(t, own): self.nextHare = t + 30
            else: self.nextHare = t + self.random.uniform(3, 6)
        if self.nextGuest is not None and t >= self.nextGuest:
            if self.spawnGuest(t, own): self.nextGuest = t + self.random.uniform(*self.dp['guest'])
            else: self.nextGuest = t + self.random.uniform(20, 40)
    def states(self, t, own):
        dt = max(t - (self.lastTime if self.lastTime is not None else t), 0); out = []
        for r in self.rowers:
            v = self.lastBase*r.speedFactor(t)
            if r.phase == 'lane': p = self.lanes[r.lane].pose(r.w + v*dt)
            elif r.phase == 'entering': p = self.docks[r.dock]['enter'].pose(r.w + 0.7*v*dt)
            else: p = self.docks[r.dock]['exit'].pose(r.w + 0.7*v*dt)
            out.append(dict(id=r.id, x=p[0], z=p[1], heading=p[2], distance=math.hypot(p[0]-own['x'], p[1]-own['z'])))
        return out
    def placeInitial(self, own, t):
        k = len(self.lanes); counts = [0]*k; inner = self.innerLane or 0
        if k == 1: counts[0] = self.residentCount
        else:
            others = [i for i in range(k) if i != inner]
            for i in range(self.residentCount): counts[others[i % len(others)]] += 1
        for rank, li in enumerate([inner] + [i for i in range(k) if i != inner]):
            cnt = counts[li]
            if cnt <= 0: continue
            lane = self.lanes[li]
            if rank <= 1:
                au = own['u'] + (self.random.uniform(20, 40) if rank == 0 else self.random.uniform(20, 80))
                anchor = lane.w_for_out_s(au) if au < 2*lane.oneWay - lane.half and au < lane.oneWay else lane.w_from_u(au)
            else:
                anchor = lane.w_from_u(self.random.uniform(0, 2*lane.oneWay))
            for j in range(cnt):
                self.rowers.append(self.makeRower(li, anchor + j*lane.loopLength/cnt, 'lane', None))
        if k > 1:
            # innerste Bahn: gleich zu Beginn ein Hase 20–40 m voraus, der schon mitfährt
            lane = self.lanes[inner]
            au = own['u'] + self.random.uniform(20, 25)    # am Start liegt die Bahn noch weiter aussen (Übergang)
            w = lane.w_for_out_s(au) if au < lane.oneWay else lane.w_from_u(au)
            r = self.makeRower(inner, w, 'lane', None); r.hare = self.newHare(t, pacing=True)
            self.rowers.append(r)
    def handOver(self, t):
        """Der Hase zieht davon oder ist überholt: der nächste kommt bald (normal 10–25 s, dense 5–15 s)."""
        self.nextHare = min(self.nextHare if self.nextHare is not None else 1e18, t + self.random.uniform(*self.dp['hare']))
    def turnAhead(self, u, lane, before):
        """Wende bzw. Startkehre liegt höchstens `before` m voraus oder das Boot ist darin (nicht: kurz nach dem Start)."""
        L, h = lane.oneWay, lane.half
        return (L - h - before <= u <= L + h) or u >= 2*L - h - before
    def nearTurn(self, u, lane, before):
        L, h = lane.oneWay, lane.half
        return (L - h - before <= u <= L + h + 40) or u >= 2*L - h - before or u <= h + 40
    def hiddenFrom(self, x, z, own):
        return hidden_from_camera(x, z, own)
    def spawnHare(self, t, own):
        li = self.innerLane
        if li is None: return False
        if any(r.hare is not None and r.hare['phase'] != 'leave' for r in self.rowers): return False
        lane = self.lanes[li]; L = lane.oneWay
        if self.nearTurn(own['u'], lane, 300): return False
        w0 = lane.w_from_u(own['u'] - self.random.uniform(50, 80))
        for r in self.rowers:
            if r.lane == li and r.phase == 'lane':
                if r.hare is None and len(self.lanes) > 1:
                    continue
                if r.hare is None:
                    if mod(r.w - (w0 - 30), lane.loopLength) <= 960: return False
                else:
                    dw = mod(r.w - w0, lane.loopLength)
                    if dw < 60 or dw > lane.loopLength - 1000: return False
        rower = self.makeRower(li, w0, 'lane', None)
        rower.hare = self.newHare(t)
        self.rowers.append(rower); return True
    def newHare(self, t, pacing=False):
        slow = self.random.unit() < (0.15 if self.density == 'dense' else 0.25) and not pacing
        h = dict(phase='approach', target=self.random.uniform(*HARE_TARGET), paceSeconds=self.random.uniform(*self.dp['pace']),
                 paceFactor=self.random.uniform(0.86, 0.92) if slow else self.random.uniform(0.995, 1.005),
                 current=1.35, until=None, since=t)
        if pacing:
            h['phase'] = 'pace'; h['current'] = h['paceFactor']; h['until'] = t + h['paceSeconds']
        return h
    def makeRower(self, lane, w, phase, planned):
        used = {r.colorIndex for r in self.rowers}
        free = [c for c in range(12) if c not in used]
        color = free[0] if free else self.random.int(12)
        r = Rower(); r.id = self.nextId; r.lane = lane; r.factor = self.laneFactors[lane]
        r.wobble = self.random.uniform(0.015, 0.03); r.wobblePeriod = self.random.uniform(40, 90)
        r.wobblePhase = self.random.uniform(0, 2*math.pi); r.colorIndex = color; r.planned = planned
        r.phase = phase; r.dock = None; r.w = w; r.rowed = 0.0; r.strokePhase = self.random.unit(); r.hare = None
        self.nextId += 1; return r
    def spawnGuest(self, t, own):
        if not self.docks or sum(1 for r in self.rowers if r.isGuest) >= self.dp['maxg']: return False
        d = self.random.int(len(self.docks))
        if not self.dockIsClear(d, own, entering=True): return False
        laps = self.random.uniform(1, 3); lane = self.docks[d]['spec']['lane']
        r = self.makeRower(lane, 0, 'entering', laps*self.lanes[lane].loopLength); r.dock = d
        self.rowers.append(r); return True
    def exitDock(self, r, uBefore, uAfter, own):
        L2 = 2*self.lanes[r.lane].oneWay; step = mod(uAfter - uBefore, L2)
        for i, d in enumerate(self.docks):
            if d['spec']['lane'] != r.lane: continue
            if mod(d['spec'].get('exitU', d['spec']['joinU']) - uBefore, L2) > step: continue
            if self.dockIsClear(i, own, ignoring=r.id): return i
        return None
    def dockIsClear(self, index, own, ignoring=None, entering=False):
        dock = self.docks[index]; lane = self.lanes[dock['spec']['lane']]; L2 = 2*lane.oneWay
        def gap(a, b):
            d = mod(a - b, L2); return min(d, L2 - d)
        pts = [dock['spec']['joinU'], L2 - dock['spec']['joinU']]
        for p in pts:
            if gap(p, own['u']) < self.dockClearOwn: return False
        if dock['spec']['lane'] == self.innerLane and any(r.hare is not None and r.id != ignoring for r in self.rowers): return False
        joinW = lane.w_from_u(dock['spec']['joinU'])
        for r in self.rowers:
            if r.id == ignoring: continue
            if r.phase in ('entering', 'leaving'):
                if self.docks[r.dock]['spec']['id'] == dock['spec']['id']: return False
            else:
                if r.lane != dock['spec']['lane'] and gap(dock['spec']['joinU'], self.lanes[r.lane].u_from_w(r.w)) < self.dockClearRowers: return False
                if r.lane == dock['spec']['lane']:
                    ahead = dock['enter'].length/0.7 if entering else 0
                    dw = mod(r.w + ahead - joinW, lane.loopLength)
                    if min(dw, lane.loopLength - dw) < self.dockLaneGap: return False
        return True
