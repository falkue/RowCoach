import Foundation

/// Schätzung der Schwelle aus normalen Fahrten (docs/schwelle/SPEC.md, Abschnitt 5): Leistungs-Dauer-Kurve je
/// Fahrt, Maximalität, Kandidat Zeitfahren (8–60 min), Kandidat Critical Power, Vorschlag „Neue Schwelle erkannt“.
/// Senkt nie automatisch.
public enum ThresholdDetector {
    /// Dauern der Leistungs-Dauer-Kurve (s)
    public static let durations: [Double] = [180, 300, 480, 600, 720, 1200, 1800, 2400, 3600]
    /// Zeitraum der Fahrten (Tage)
    public static let lookbackDays = 42.0

    /// Eine Fahrt für die Schätzung
    public struct Ride: Sendable {
        public var workoutId: UUID
        public var date: Date
        public var samples: [WorkoutSample]
        /// Programm der Kategorie Test
        public var isTest: Bool
        /// eigene Belastung 1–10
        public var userScore: Int?
        /// Untergrenze Pulszone 4 (bpm); nil ohne Pulsmodell
        public var zone4LowerBound: Int?
        /// Simulatorfahrt (zählt nie)
        public var simulated: Bool

        public init(workoutId: UUID = UUID(), date: Date, samples: [WorkoutSample], isTest: Bool = false,
                    userScore: Int? = nil, zone4LowerBound: Int? = nil, simulated: Bool = false) {
            self.workoutId = workoutId
            self.date = date
            self.samples = samples
            self.isTest = isTest
            self.userScore = userScore
            self.zone4LowerBound = zone4LowerBound
            self.simulated = simulated
        }
    }

    /// Bestwert einer Fahrt über eine Dauer
    public struct Effort: Equatable, Sendable {
        public var workoutId: UUID
        public var date: Date
        public var duration: Double
        public var power: Double
        /// Beginn des Fensters (s seit Start der Fahrt)
        public var start: Double
        /// Maximalität nur aus dem Puls erkannt (σ + 2 %)
        public var fromHeartRate: Bool
    }

    /// Leistungs-Dauer-Kurve einer Fahrt; zusätzlich die Dauer der ganzen Fahrt (8–60 min), damit eine durchgehende
    /// Belastung als Ganzes zählt. Nur maximale Efforts (Test, Belastung ≥ 8 oder Puls ≥ Zone 4 über ≥ 8 min).
    public static func maximalEfforts(_ ride: Ride) -> [Effort] {
        guard !ride.simulated, !ride.samples.isEmpty else { return [] }
        let series = ThresholdSeries(samples: ride.samples)
        let length = series.endTime - series.startTime
        var ds = durations
        let whole = (length / 10).rounded(.down) * 10
        if whole >= 480, whole <= 3600, !ds.contains(whole) { ds.append(whole) }
        let maximalByRide = ride.isTest || (ride.userScore ?? 0) >= 8
        var out: [Effort] = []
        for d in ds.sorted() {
            guard let m = series.maxMeanPower(duration: d), m.power > 0 else { continue }
            var fromHR = false
            if !maximalByRide {
                guard d >= 480, let z4 = ride.zone4LowerBound else { continue }
                let hr = series.heartRate(from: m.start, to: m.start + d)
                guard hr.covered >= 0.8 * d, hr.mean >= Double(z4) else { continue }
                fromHR = true
            }
            out.append(Effort(workoutId: ride.workoutId, date: ride.date, duration: d, power: m.power, start: m.start,
                              fromHeartRate: fromHR))
        }
        return out
    }

    /// Kandidat aus Fahrten
    public struct Candidate: Equatable, Sendable {
        public var estimate: ThresholdEstimate
        /// Effort, aus dem er stammt (für „aus deiner Fahrt vom 20.11.: 24 min mit 175 W“)
        public var effort: Effort?
    }

    /// Kandidat Zeitfahren: für t ≥ 480 s T_t = MMP(t) · (t/1800)^b; höchster Wert der letzten 42 Tage
    public static func timeTrialCandidate(efforts: [Effort], b: Double) -> Candidate? {
        let best = efforts.filter { $0.duration >= 480 }.max { a, c in
            ThresholdMath.thresholdFromEffort(power: a.power, duration: a.duration, b: b)
                < ThresholdMath.thresholdFromEffort(power: c.power, duration: c.duration, b: b)
        }
        guard let e = best else { return nil }
        let t = ThresholdMath.thresholdFromEffort(power: e.power, duration: e.duration, b: b)
        var est = ThresholdEstimate(kind: .ridesAuto, date: e.date, powerW: t, sigmaPct: e.fromHeartRate ? 8 : 6,
                                    workoutId: e.workoutId, details: ["p": e.power, "t": e.duration, "b": b],
                                    notes: e.fromHeartRate ? [.maximalFromHeartRate] : [])
        est.status = ThresholdEstimate.Status.candidate.rawValue
        return Candidate(estimate: est, effort: e)
    }

    /// Critical Power aus 2–3 maximalen Efforts (Arbeit W = P · t; CP = Steigung von W über t, W′ = Achsenabschnitt).
    /// Plausibel nur bei CP > 0 und 5 kJ ≤ W′ ≤ 40 kJ.
    public static func criticalPower(_ efforts: [(duration: Double, power: Double)]) -> (cp: Double, wPrime: Double)? {
        guard efforts.count >= 2 else { return nil }
        let x = efforts.map(\.duration), y = efforts.map { $0.power * $0.duration }
        guard let fit = LinearFit(x: x, y: y) else { return nil }
        let cp = fit.slope, wp = fit.intercept
        guard cp > 0, (5000...40000).contains(wp) else { return nil }
        return (cp, wp)
    }

    /// Kandidat CP: zwei Efforts 120 s ≤ t₁ < t₂ ≤ 1200 s mit t₂/t₁ ≥ 2,5 (aus verschiedenen Fahrten oder ohne
    /// Überlappen aus derselben); T = 0,88 · CP
    public static func criticalPowerCandidate(efforts: [Effort]) -> Candidate? {
        let short = efforts.filter { (120...300).contains($0.duration) }
        let long = efforts.filter { $0.duration > 300 && $0.duration <= 1200 }
        var best: (Double, Double, Effort, Effort)?
        for a in short {
            for c in long where c.duration / a.duration >= 2.5 {
                if a.workoutId == c.workoutId {
                    let overlap = a.start < c.start + c.duration && c.start < a.start + a.duration
                    if overlap { continue }
                }
                guard let r = criticalPower([(a.duration, a.power), (c.duration, c.power)]) else { continue }
                if best == nil || r.cp > best!.0 { best = (r.cp, r.wPrime, a, c) }
            }
        }
        guard let bst = best else { return nil }
        let (cp, wp, a, c) = bst
        var est = ThresholdEstimate(kind: .criticalPowerFit, date: max(a.date, c.date), powerW: 0.88 * cp, sigmaPct: 6,
                                    workoutId: c.workoutId,
                                    details: ["cp": cp, "wPrime": wp, "t1": a.duration, "p1": a.power,
                                              "t2": c.duration, "p2": c.power])
        est.status = ThresholdEstimate.Status.candidate.rawValue
        return Candidate(estimate: est, effort: c)
    }

    /// Bester Kandidat aus den Fahrten der letzten 42 Tage (Zeitfahren vor CP bei gleicher Höhe)
    public static func candidate(rides: [Ride], now: Date, b: Double) -> Candidate? {
        let recent = rides.filter { !$0.simulated && now.timeIntervalSince($0.date) <= lookbackDays * 86400 && $0.date <= now }
        let efforts = recent.flatMap(maximalEfforts)
        let cands = [timeTrialCandidate(efforts: efforts, b: b), criticalPowerCandidate(efforts: efforts)].compactMap { $0 }
        return cands.max { $0.estimate.powerW < $1.estimate.powerW }
    }

    /// Vorschlag „Neue Schwelle erkannt“: Kandidat ≥ aktive T · 1,03 und ≥ T + 5 W; ein abgelehnter Wert erst ab
    /// weiteren + 2 % wieder; höchstens ein Vorschlag je 7 Tage.
    public static func proposal(_ c: Candidate, profile: ThresholdProfile, now: Date) -> Candidate? {
        guard let t = profile.thresholdW else { return c }
        guard c.estimate.powerW >= t * 1.03, c.estimate.powerW >= t + 5 else { return nil }
        if let rejected = profile.lastRideProposalW, c.estimate.powerW < rejected * 1.02 { return nil }
        if let last = profile.lastRideProposalDate, now.timeIntervalSince(last) < 7 * 86400 { return nil }
        // schon vorhanden (gleiche Fahrt, gleiche Art)
        if profile.estimates.contains(where: {
            $0.workoutId == c.estimate.workoutId && $0.kind == c.estimate.kind && $0.statusValue != .candidate
        }) { return nil }
        return c
    }

    // MARK: Entkopplung (nur Information)

    public enum Decoupling: String, Sendable {
        /// < 5 %: „Grundlage trägt“
        case stable
        /// 5–10 %: „Grundlage begrenzt“
        case limited
        /// > 10 %: „vermutlich über der aeroben Schwelle“
        case aboveAerobic

        public var title: String {
            switch self {
            case .stable: return String(localized: "Grundlage trägt")
            case .limited: return String(localized: "Grundlage begrenzt")
            case .aboveAerobic: return String(localized: "vermutlich über der aeroben Schwelle")
            }
        }
    }

    /// Entkopplung Leistung zu Puls bei gleichmässigen Fahrten ≥ 40 min: EF = Leistung / Puls je Hälfte (erste 10 %
    /// ohne Einrudern); Entkopplung = (EF₁ − EF₂)/EF₁. nil, wenn zu kurz oder ohne Puls.
    public static func decoupling(samples: [WorkoutSample]) -> (value: Double, verdict: Decoupling)? {
        let s = ThresholdSeries(samples: samples)
        let len = s.endTime - s.startTime
        guard len >= 2400 else { return nil }
        let a = s.startTime + 0.1 * len, m = a + (s.endTime - a) / 2, e = s.endTime
        let h1 = s.heartRate(from: a, to: m), h2 = s.heartRate(from: m, to: e)
        guard h1.covered >= 0.8 * (m - a), h2.covered >= 0.8 * (e - m), h1.mean > 0, h2.mean > 0,
              let p1 = s.meanPower(from: a, to: m), let p2 = s.meanPower(from: m, to: e), p1 > 0 else { return nil }
        let ef1 = p1 / h1.mean, ef2 = p2 / h2.mean
        let d = (ef1 - ef2) / ef1
        let v: Decoupling = d < 0.05 ? .stable : (d <= 0.10 ? .limited : .aboveAerobic)
        return (d, v)
    }

    /// Gemessener Maximalpuls: höchster 5-s-Mittelwert der Fahrten der letzten 12 Monate; Vorschlag, wenn er ≥ 3 bpm
    /// über dem gespeicherten liegt.
    public static func measuredMaxHR(rides: [Ride], now: Date, stored: Int?) -> Int? {
        let peak = rides.filter { !$0.simulated && now.timeIntervalSince($0.date) <= 365 * 86400 }
            .compactMap { ThresholdSeries(samples: $0.samples).peakHeartRate5s() }.max()
        guard let p = peak, p >= (stored ?? 0) + 3 else { return nil }
        return p
    }
}
