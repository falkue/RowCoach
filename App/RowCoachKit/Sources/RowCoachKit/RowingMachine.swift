import Foundation

/// Welches Protokoll das verbundene Rudergerät spricht.
/// - pm5: Concept2-PM5-Protokoll (CE06…): bevorzugt, auch wenn ein Gerät zusätzlich FTMS anbietet (mehr Daten:
///   Schlagzustand, Durchzugs-/Freilaufzeit, Widerstandsfaktor).
/// - ftms: Bluetooth Fitness Machine Service, Rower Data 0x2AD1 (WaterRower mit ComModule, FDF, Merach u. a.).
///   Mit echter Hardware ungetestet (Beta).
public enum RowingMachineKind: String, Codable, Sendable, CaseIterable {
    case pm5, ftms
}

/// Macht aus den FTMS-Rower-Data-Paketen denselben `RowingSnapshot` wie der PM5-Pfad.
///
/// - Teilpakete („More Data“) und Geräte, die Felder auf mehrere Notifications verteilen: jedes Feld behält seinen
///   letzten Wert (`merged`), jedes Paket aktualisiert den Snapshot.
/// - Schläge: aus dem Wechsel des Stroke Count (Überlauf bei 65 535 beachtet); ohne Stroke Count aus der Schlagzahl
///   hochgerechnet.
/// - Fehlende Werte: Tempo aus der Distanzänderung, Distanz aus dem Tempo, Zeit aus der eigenen Uhr; Watt fehlen
///   dann im Snapshot (power = 0) und `RowingSnapshot.displayPower` schätzt sie aus dem Tempo
///   (`isPowerEstimated`).
/// - Schlagzahl in ganzen statt halben Schlägen: manche Konsolen senden die Schlagzahl ohne den Faktor 0,5 der
///   Spezifikation. Liegt der gemeldete Wert über mehrere Prüfungen bei etwa der Hälfte der aus dem Stroke Count
///   gemessenen Schlagzahl, wird er verdoppelt (`strokeRateScale`).
public struct FTMSRowerTracker: Sendable {
    /// Letzter bekannter Wert je Feld
    public private(set) var merged = FTMSRowerData()
    /// Schläge seit Verbindungsbeginn (monoton, unabhängig von Rücksetzungen am Gerät)
    public private(set) var strokeTotal = 0
    /// Faktor für die gemeldete Schlagzahl (1 oder 2, siehe oben)
    public private(set) var strokeRateScale = 1.0
    /// Herkunft der Werte, für Diagnose und Doku
    public private(set) var paceDerived = false
    public private(set) var distanceDerived = false
    public private(set) var strokesDerived = false

    private var lastStrokeCount: Int?
    private var strokeTimes: [TimeInterval] = []
    private var halfRateVotes = 0
    private var distanceHistory: [(t: TimeInterval, d: Double)] = []
    private var ownDistance = 0.0
    private var firstActivity: TimeInterval?
    private var ownElapsed: TimeInterval = 0
    private var lastTime: TimeInterval?
    private var strokePhaseAccumulator = 0.0
    private var sawStrokeCount = false
    private var sawDistance = false

    public init() {}

    /// Übernimmt ein Paket zum Zeitpunkt t (Sekunden, monotone Uhr) und schreibt den Stand in `s`.
    /// Gibt die Zahl der neuen Schläge seit dem letzten Paket zurück (für die Schlagphase der Figur).
    @discardableResult
    public mutating func ingest(_ d: FTMSRowerData, at t: TimeInterval, into s: inout RowingSnapshot) -> Int {
        let dt = lastTime.map { min(max(t - $0, 0), 5) } ?? 0
        lastTime = t
        merged.merge(d)
        var newStrokes = 0

        // Schläge
        if let count = d.strokeCount {
            sawStrokeCount = true
            strokesDerived = false
            if let last = lastStrokeCount {
                var delta = count - last
                if delta < 0, last > 65_000, count < 1_000 { delta += 65_536 }   // Überlauf uint16
                // Rücksetzen am Gerät (negativ) oder unplausibler Sprung: nur neue Grundlinie
                if delta > 0 && delta <= 5 { newStrokes = delta }
            }
            lastStrokeCount = count
        } else if !sawStrokeCount, let rate = merged.strokeRate, rate > 0, dt > 0 {
            // Gerät ohne Stroke Count: Schläge aus der Schlagzahl
            strokesDerived = true
            strokePhaseAccumulator += rate * strokeRateScale / 60 * dt
            while strokePhaseAccumulator >= 1 { strokePhaseAccumulator -= 1; newStrokes += 1 }
        }
        if newStrokes > 0 {
            strokeTotal += newStrokes
            for _ in 0..<newStrokes { strokeTimes.append(t) }
            strokeTimes.removeAll { t - $0 > 30 }
            if sawStrokeCount { checkStrokeRateScale() }
        }

        // Distanz
        if let dist = d.totalDistance {
            sawDistance = true
            distanceDerived = false
            s.distance = Double(dist)
        } else if !sawDistance, s.pace > 0, dt > 0 {
            distanceDerived = true
            ownDistance += 500 / s.pace * dt
            s.distance = ownDistance
        }
        if sawDistance {
            distanceHistory.append((t, s.distance))
            distanceHistory.removeAll { t - $0.t > 8 }
        }

        // Aktivität und Zeit
        let recentStroke = strokeTimes.last.map { t - $0 < 6 } ?? false
        let paceValid = merged.instantaneousPace.map { $0 > 0 && $0 < 0xFFFF } ?? false
        let moving = recentStroke || (paceValid && (merged.instantaneousPower ?? 1) > 0)
        if moving {
            if firstActivity == nil { firstActivity = t }
            ownElapsed += dt
        }
        if let e = merged.elapsedTime { s.elapsedTime = TimeInterval(e) } else { s.elapsedTime = ownElapsed }
        s.rowingState = moving ? .active : .inactive

        // Schlagzahl
        var rate = merged.strokeRate.map { $0 * strokeRateScale } ?? measuredStrokeRate(at: t) ?? 0
        // Mit Schlagzähler: 6 s ohne neuen Schlag = Pause, auch wenn das Gerät noch die alte Schlagzahl meldet
        if sawStrokeCount && !recentStroke { rate = 0 }
        s.strokeRate = Int(rate.rounded())
        s.strokeCount = strokeTotal

        // Tempo
        if let p = merged.instantaneousPace, p > 0, p < 0xFFFF, p < 3600 {
            paceDerived = false
            s.pace = TimeInterval(p)
        } else if let p = derivedPace() {
            paceDerived = true
            s.pace = p
        } else if merged.instantaneousPace != nil || !moving {
            s.pace = 0
        }
        s.speed = s.pace > 0 ? 500 / s.pace : 0
        if let p = merged.averagePace, p > 0, p < 0xFFFF {
            s.averagePace = TimeInterval(p)
        } else {
            s.averagePace = s.distance > 1 && s.elapsedTime > 0 ? s.elapsedTime / s.distance * 500 : 0
        }

        // Leistung: nur echte Gerätewerte; sonst schätzt displayPower aus dem Tempo
        s.power = max(merged.instantaneousPower ?? 0, 0)
        s.averagePower = max(merged.averagePower ?? 0, 0)
        if let e = merged.totalEnergy { s.calories = e }

        // Puls vom Gerät nur, wenn kein Gurt verbunden ist
        if s.heartRateSource != .strap, let h = merged.heartRate, h > 0, d.heartRate != nil {
            s.heartRate = h; s.heartRateSource = .machine
        }
        return newStrokes
    }

    /// Mittlere Dauer eines Schlags über die letzten (bis zu 4) Schläge (s), für die Schlagphase der Figur.
    /// Mehrere Schläge in einem Paket haben denselben Zeitstempel; der Mittelwert gleicht das aus.
    public var lastStrokeInterval: TimeInterval? {
        let k = min(strokeTimes.count, 4)
        guard k >= 2, let last = strokeTimes.last else { return nil }
        let i = (last - strokeTimes[strokeTimes.count - k]) / Double(k - 1)
        return i > 0.8 && i < 6 ? i : nil
    }

    // MARK: intern

    private func measuredStrokeRate(at t: TimeInterval) -> Double? {
        guard strokeTimes.count >= 3, let first = strokeTimes.first, let last = strokeTimes.last, last > first,
              t - last < 6 else { return nil }
        return Double(strokeTimes.count - 1) / (last - first) * 60
    }

    private mutating func checkStrokeRateScale() {
        guard strokeRateScale == 1, strokeTimes.count >= 8, let reported = merged.strokeRate, reported > 0,
              let t = strokeTimes.last, let measured = measuredStrokeRate(at: t), measured > 8 else { return }
        let ratio = reported / measured
        if ratio > 0.4 && ratio < 0.6 { halfRateVotes += 1 } else { halfRateVotes = 0 }
        if halfRateVotes >= 5 { strokeRateScale = 2 }
    }

    private func derivedPace() -> TimeInterval? {
        guard let first = distanceHistory.first, let last = distanceHistory.last, last.t - first.t >= 2 else {
            return nil
        }
        let speed = (last.d - first.d) / (last.t - first.t)
        guard speed > 0.3 else { return nil }
        return 500 / speed
    }
}

extension RowingSnapshot {
    /// Leistung ist geschätzt (Gerät liefert keine Watt; `displayPower` rechnet aus dem Tempo)
    public var isPowerEstimated: Bool { power <= 0 && displayPower > 0 }
}

// MARK: - FTMS-Simulator

/// Simuliertes FTMS-Rudergerät für Tests ohne Hardware: dieselbe Physik wie `ErgSimulator`, aber als
/// Rower-Data-Pakete. Jede Sekunde ein Datensatz, aufgeteilt wie bei echten Geräten mit kleiner MTU:
/// erst ein Teilpaket mit „More Data“ (ohne Schlagwerte), dann das Paket mit Schlagzahl und -zähler.
/// - `minimal`: ein karges Gerät nur mit Schlagzahl, Schlagzähler und Distanz (Tempo und Watt leitet die App ab).
public struct FTMSRowerSimulator: Sendable {
    public var sim: ErgSimulator
    public var minimal: Bool
    private var sinceSend: TimeInterval = 1

    public init(settings: ErgSimulator.Settings = .init(), startDistance: Double = 0, minimal: Bool = false) {
        self.sim = ErgSimulator(settings: settings, startDistance: startDistance)
        self.minimal = minimal
    }

    public struct Output: Equatable, Sendable {
        /// Rower-Data-Notifications in Sendereihenfolge
        public var rowerData: [[UInt8]]
        /// Bytes des Pulsgurts (0x2A37), wie beim PM5-Simulator
        public var heartRate: [UInt8]?
    }

    public mutating func step(dt: TimeInterval) -> Output {
        let o = sim.step(dt: dt)
        var out = Output(rowerData: [], heartRate: o.heartRate)
        sinceSend += dt
        guard sinceSend >= 1 else { return out }
        sinceSend = 0
        let rate = sim.settings.rowing && sim.speed > 0 ? Double(sim.settings.strokeRate) : 0
        if minimal {
            var d = FTMSRowerData()
            d.strokeRate = rate; d.strokeCount = sim.strokeCount; d.totalDistance = Int(sim.distance)
            out.rowerData = [FTMSRowerDataEncoder.encode(d)]
            return out
        }
        var a = FTMSRowerData()
        a.totalDistance = Int(sim.distance)
        a.instantaneousPace = sim.currentPace > 0 ? Int(sim.currentPace.rounded()) : 0
        a.averagePace = sim.distance > 1 && sim.elapsed > 0 ? Int((sim.elapsed / sim.distance * 500).rounded()) : 0
        a.instantaneousPower = sim.power
        a.averagePower = sim.elapsed > 0 ? Int((sim.energy / sim.elapsed).rounded()) : 0
        a.totalEnergy = Int(sim.calories)
        a.energyPerHour = sim.power > 0 ? 4 * sim.power + 300 : 0
        a.energyPerMinute = sim.power > 0 ? (4 * sim.power + 300) / 60 : 0
        a.heartRate = Int(sim.heartRate.rounded())
        a.elapsedTime = Int(sim.elapsed)
        var b = FTMSRowerData()
        b.strokeRate = rate; b.strokeCount = sim.strokeCount; b.averageStrokeRate = rate
        out.rowerData = [FTMSRowerDataEncoder.encode(a), FTMSRowerDataEncoder.encode(b)]
        return out
    }

    public mutating func resetMonitor() { sim.resetMonitor() }
}
