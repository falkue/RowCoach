import Foundation
import XCTest
@testable import RowCoachKit

// Dead Reckoning, seltenere Übersicht, Präzisionsmodus, kompakte Frames und die Messung über ein 300er-Rennen
// (docs/MULTIPLAYER.md, „Dead Reckoning“)

private func frame(_ id: String = "a", seq: Int, t: Double, d: Double, pace: Double = 120, spm: Int = 24,
                   finished: Bool = false, ft: Double? = nil) -> LiveFrame {
    LiveFrame(participantId: id, raceId: "r", seq: seq, sentAt: 0, raceTime: t, distance: d, pace: pace, strokeRate: spm,
              finished: finished, finishTime: ft)
}

final class RaceDeadReckoningUnitTests: XCTestCase {
    func testPrediction() {
        let f = frame(seq: 1, t: 10, d: 100, pace: 125)   // 4 m/s
        XCTAssertEqual(RaceDeadReckoning.predict(f, at: 15), 120, accuracy: 1e-9)
        XCTAssertEqual(RaceDeadReckoning.predict(f, at: 5), 100, accuracy: 1e-9)
        XCTAssertEqual(RaceDeadReckoning.predict(f, at: 100, finishDistance: 200), 200, accuracy: 1e-9)
        XCTAssertEqual(RaceDeadReckoning.predict(frame(seq: 1, t: 10, d: 2000, pace: 0, finished: true), at: 50), 2000)
    }

    func testPublisherRules() {
        var p = RaceDeadReckoningPublisher(threshold: 4, heartbeat: 8, finishDistance: 2000)
        XCTAssertTrue(p.shouldSend(frame(seq: 1, t: 0, d: 0), now: 0))
        // genau nach Voraussage: nichts bis zum Lebenszeichen
        XCTAssertFalse(p.shouldSend(frame(seq: 2, t: 5, d: 20.8), now: 5))
        XCTAssertTrue(p.shouldSend(frame(seq: 3, t: 8, d: 33.3), now: 8), "Lebenszeichen")
        // Abweichung > 4 m
        XCTAssertFalse(p.shouldSend(frame(seq: 4, t: 10, d: 33.3 + 8.3 + 3.9), now: 10))
        XCTAssertTrue(p.shouldSend(frame(seq: 5, t: 11, d: 33.3 + 12.5 + 4.5), now: 11))
        // Tempo- und Schlagzahlsprung
        XCTAssertTrue(p.shouldSend(frame(seq: 6, t: 12.5, d: p.predicted(at: 12.5)!, pace: 115), now: 12.5))
        XCTAssertTrue(p.shouldSend(frame(seq: 7, t: 14, d: p.predicted(at: 14)!, pace: 115, spm: 27), now: 14))
        // höchstens 1/s
        XCTAssertFalse(p.shouldSend(frame(seq: 8, t: 14.5, d: p.predicted(at: 14.5)! + 9, pace: 115, spm: 27), now: 14.5))
        // Präzision: spätestens jede Sekunde, bei kleiner Abweichung nach 0,5 s
        var q = p
        XCTAssertTrue(q.shouldSend(frame(seq: 9, t: 15, d: q.predicted(at: 15)!, pace: 115, spm: 27), now: 15, precision: true))
        XCTAssertTrue(q.shouldSend(frame(seq: 10, t: 15.5, d: q.predicted(at: 15.5)! + 0.6, pace: 115, spm: 27), now: 15.5, precision: true))
        // Ziel sofort, auch innerhalb der Mindestzeit, danach nichts mehr
        XCTAssertTrue(p.shouldSend(frame(seq: 11, t: 14.6, d: 2000, pace: 0, finished: true, ft: 14.55), now: 14.6))
        XCTAssertFalse(p.shouldSend(frame(seq: 12, t: 16, d: 2000, pace: 0, finished: true, ft: 14.55), now: 16))
        // Präzisionsentscheidung
        XCTAssertTrue(p.wantsPrecision(distanceToGo: 200, neighbours: [(gap: -20, closing: 0)]))
        XCTAssertFalse(p.wantsPrecision(distanceToGo: 300, neighbours: [(gap: -20, closing: 0)]))
        XCTAssertFalse(p.wantsPrecision(distanceToGo: 200, neighbours: [(gap: 40, closing: 0)]))
        XCTAssertFalse(p.wantsPrecision(distanceToGo: 900, neighbours: [(gap: 5, closing: 0.5)]), "knappes Überholen: Standard aus")
        var o = p; o.closeOvertakeRange = 10
        XCTAssertTrue(o.wantsPrecision(distanceToGo: 900, neighbours: [(gap: 5, closing: 0.5)]))
        XCTAssertFalse(o.wantsPrecision(distanceToGo: 900, neighbours: [(gap: 5, closing: -0.5)]))
    }

    func testTrackerBlendsCorrectionsWithoutJumps() {
        var t = RemoteRowerTracker.deadReckoning(finishDistance: 2000, maxCorrectionSpeed: 1, heartbeat: 8)
        t.receive(frame(seq: 1, t: 0, d: 0, pace: 125), receivedLocal: 0)
        XCTAssertEqual(t.position(atRaceTime: 10)!.distance, 40, accuracy: 1e-9, "ohne Verzögerung vorausgerechnet")
        // neuer Frame: in Wahrheit 5 m weiter → Anzeige holt mit 1 m/s auf
        t.receive(frame(seq: 2, t: 10, d: 45, pace: 125), receivedLocal: 10.2)
        XCTAssertEqual(t.position(atRaceTime: 10)!.distance, 40, accuracy: 1e-9)
        XCTAssertEqual(t.position(atRaceTime: 12)!.distance, 45 + 8 - 3, accuracy: 1e-9)
        XCTAssertEqual(t.position(atRaceTime: 20)!.distance, 45 + 40, accuracy: 1e-9)
        var prev = t.position(atRaceTime: 10)!.distance
        for k in 1...100 {
            let d = t.position(atRaceTime: 10 + Double(k) * 0.1)!.distance
            XCTAssertLessThanOrEqual(d - prev, 0.1 * (4 + 1) + 1e-9)
            XCTAssertGreaterThanOrEqual(d - prev, 0)
            prev = d
        }
        // grosse Abweichung springt
        t.receive(frame(seq: 3, t: 30, d: 200, pace: 125), receivedLocal: 30)
        XCTAssertEqual(t.position(atRaceTime: 30)!.distance, 200, accuracy: 1e-9)
        // an der Ziellinie warten, dann exakt im Ziel
        t.receive(frame(seq: 4, t: 400, d: 1990, pace: 125), receivedLocal: 400)
        XCTAssertEqual(t.position(atRaceTime: 410)!.distance, 2000, accuracy: 1e-9)
        t.receive(frame(seq: 5, t: 402.5, d: 2000, pace: 0, finished: true, ft: 402.5), receivedLocal: 402.7)
        XCTAssertEqual(t.position(atRaceTime: 420)!.distance, 2000)
        // veraltet erst nach 2 Lebenszeichen + 5 s
        XCTAssertFalse(t.isStale(local: 402.7 + 20))
        XCTAssertTrue(t.isStale(local: 402.7 + 22))
    }

    func testAggregatorSendsDeltasAndFullOverviews() {
        let roster = RaceRosterIndex(participants: (0..<3).map { RaceParticipant(id: "p\($0)", displayName: "", lane: $0 + 1) })
        var agg = RaceFieldAggregator(interval: 5, fullEvery: 30, threshold: 5, finishDistance: 2000)
        agg.finishZoneInterval = nil
        for i in 0..<3 { agg.receive(frame("p\(i)", seq: 1, t: 0, d: Double(i) * 10)) }
        let s0 = agg.tick(raceId: "r", raceTime: 0, sentAt: 0, roster: roster)
        XCTAssertEqual(s0?.isDelta, false)
        XCTAssertEqual(s0?.entries.count, 3)
        XCTAssertNil(agg.tick(raceId: "r", raceTime: 3, sentAt: 0, roster: roster), "noch nicht fällig")
        XCTAssertNil(agg.tick(raceId: "r", raceTime: 5, sentAt: 0, roster: roster), "nichts geändert → kein Delta")
        agg.receive(frame("p1", seq: 2, t: 8, d: 10 + 8 * 4.1667 + 6))
        let s1 = agg.tick(raceId: "r", raceTime: 10, sentAt: 0, roster: roster)
        XCTAssertEqual(s1?.isDelta, true)
        XCTAssertEqual(s1?.entries.map(\.index), [roster.index(of: "p1")!])
        let s2 = agg.tick(raceId: "r", raceTime: 30, sentAt: 0, roster: roster)
        XCTAssertEqual(s2?.isDelta, false)
        XCTAssertEqual(s2?.entries.count, 3)
        // Gerät: volle Übersicht, dann Delta ergänzt
        var tr = RaceFieldTracker(participants: (0..<3).map { RaceParticipant(id: "p\($0)", displayName: "", lane: $0 + 1) })
        XCTAssertTrue(tr.receive(s0!, receivedLocal: 0))
        XCTAssertTrue(tr.receive(s1!, receivedLocal: 10))
        let st = Dictionary(uniqueKeysWithValues: tr.states(atRaceTime: 10).map { ($0.id, $0.distance) })
        XCTAssertEqual(st["p0"]!, 41.7, accuracy: 0.2)
        XCTAssertEqual(st["p1"]!, 10 + 10 * 4.1667 + 6, accuracy: 0.2)
        // Delta im Binärformat
        let b = s1!.encodeBinary()
        XCTAssertEqual(b[0], 2)
        XCTAssertEqual(RaceFieldSnapshot.decodeBinary(b, raceId: "r", sentAt: 0)?.isDelta, true)
    }

    func testCompactFrameRoundTrip() throws {
        let roster = RaceRosterIndex(participants: [RaceParticipant(id: "x", displayName: "", lane: 1),
                                                    RaceParticipant(id: "y", displayName: "", lane: 2)])
        let f = LiveFrame(participantId: "y", raceId: "r", seq: 77, sentAt: 0, raceTime: 123.456, distance: 987.65,
                          pace: 118.37, strokeRate: 31, heartRate: 171)
        let b = RaceCompactFrame.encode(f, index: 1)
        XCTAssertEqual(b.count, 18)
        XCTAssertEqual(Data(b).base64EncodedString().count, RaceCompactFrame.wireLength(finished: false))
        let d = try XCTUnwrap(RaceCompactFrame.decode(b, raceId: "r", roster: roster))
        XCTAssertEqual(d.participantId, "y")
        XCTAssertEqual(d.seq, 77)
        XCTAssertEqual(d.raceTime, 123.46, accuracy: 1e-9)
        XCTAssertEqual(d.distance, 987.7, accuracy: 1e-9)
        XCTAssertEqual(d.pace, 118.4, accuracy: 1e-9)
        XCTAssertEqual(d.strokeRate, 31)
        XCTAssertEqual(d.heartRate, 171)
        let fin = LiveFrame(participantId: "x", raceId: "r", seq: 78, sentAt: 0, raceTime: 400.1, distance: 2000, pace: 0,
                            strokeRate: 0, finished: true, finishTime: 399.987)
        let fb = RaceCompactFrame.encode(fin, index: 0)
        XCTAssertEqual(fb.count, 22)
        XCTAssertEqual(Data(fb).base64EncodedString().count, RaceCompactFrame.wireLength(finished: true))
        let fd = try XCTUnwrap(RaceCompactFrame.decode(fb, raceId: "r", roster: roster))
        XCTAssertEqual(fd.finishTime ?? 0, 399.987, accuracy: 1e-9, "Zielzeit auf die Millisekunde")
        XCTAssertNil(RaceCompactFrame.decode(Array(fb.prefix(19)), raceId: "r", roster: roster))
        let json = try JSONEncoder().encode(f)
        XCTAssertGreaterThan(json.count, 4 * b.count, "JSON ist mehr als viermal so gross")
    }

    func testCoordinatorWithDeadReckoningSendsRarelyAndFinishesExactly() {
        let race = Race(id: "r", courseId: "c", target: .distance(2000), lanes: 2)
        var c = RaceCoordinator(race: race, me: RaceParticipant(id: "me", displayName: "Ich", lane: 1),
                                tracker: .deadReckoning(finishDistance: 2000))
        c.deadReckoning = RaceDeadReckoningPublisher(threshold: 4, heartbeat: 20, finishDistance: 2000)
        var sent = 0
        var finishFrame: LiveFrame?
        var t = 0.0
        while t < 600 {
            let d = min(500.0 / 120 * t, 2000.4)
            if let f = c.updateLocal(raceTime: t, distance: d, pace: d >= 2000 ? 0 : 120, strokeRate: 26, local: t) {
                sent += 1
                if f.finished { finishFrame = f }
            }
            if finishFrame != nil { break }
            t += 0.1
        }
        XCTAssertLessThan(sent, 30, "≈ 480 s Rennen: Lebenszeichen alle 20 s")
        XCTAssertEqual(finishFrame?.finishTime ?? 0, 480, accuracy: 0.01, "Zielzeit exakt interpoliert")
    }
}

// MARK: - Messung über ein ganzes Rennen

/// Eine Variante des Netzverfahrens
struct NetVariant {
    var name: String
    var deadReckoning = true
    var threshold = 4.0
    var heartbeat: TimeInterval = 8
    /// bisheriger Plan: feste Rate
    var fixedInterval: TimeInterval = 0.4
    var k = 16
    var kFinish = 16
    var compact = false
    var fieldInterval: TimeInterval = 5
    var fullEvery: TimeInterval = 30
    var fieldThreshold = 5.0
    /// Schwelle der Übersicht in der Zielzone (nil = wie `fieldThreshold`)
    var fieldZoneThreshold: Double?
    var closeOvertake: Double?
    /// Schwelle ausserhalb der Zielzone (nil = `threshold` überall)
    var thresholdOutside: Double?
    /// Aggregator: Cloud Run 1 vCPU/0,5 GiB über das Rennen ± 2 min, oder 0,25 vCPU/0,25 GiB nur im Rennfenster
    var smallAggregator = false
}

struct NetResult {
    var variant: NetVariant
    var duration: Double
    var framesPerParticipantSecond: Double
    var deviceBytesPerSecond: Double
    var writesPerSecond: Double
    var responsesPerSecond: Double
    var totalDownload: Double
    var usdPerRace: Double
    var preciseOut: (mean: Double, p95: Double, max: Double)
    var preciseIn: (mean: Double, p95: Double, max: Double)
    var coarseOut: (mean: Double, p95: Double, max: Double)
    var coarseIn: (mean: Double, p95: Double, max: Double)
    var finishTimeMaxError: Double
    var zoneFramesPerSecond: Double
    /// davon Übersicht (Bytes/s je Gerät) und mittlere Einträge je Delta
    var fieldBytesPerSecond: Double
    var deltaEntries: Double
    /// Sendegründe (Dead Reckoning), Anteil
    var reasons: [String: Double]
}

/// 300 Bots über 2000 m, 10 Schritte/s: Sender nach Variante, Laufzeit 0,2 s (Aggregator 0,1 s), Nachbarschaft der K
/// nächsten (alle 2 s neu, beim Abo kommt der aktuelle Stand einmal mit), Übersicht vom Aggregator. Gemessen: Frames,
/// Bytes je Gerät, Schreib- und Antwortvorgänge, Kosten, Positionsfehler beim Empfänger (je Paar Gerät–Nachbar, 1/s).
func simulateRace(_ v: NetVariant, count: Int = 300, seed: UInt64 = 11) -> NetResult {
    let field = RaceBotField(config: .init(count: count, referencePace: 120, finishDistance: 2000, seed: seed))
    let finish = 2000.0
    let roster = RaceRosterIndex(participants: field.participants)
    let cost = RaceCostModel()
    let n = count
    let dt = 0.1
    let latency = 0.2
    let jsonBytes = Double((try? JSONEncoder().encode(field.frame(of: 0, raceId: "race-1234", seq: 123, raceTime: 234.5,
                                                                  sentAt: 1_790_000_000.123)).count) ?? 130)
    func payload(_ f: LiveFrame) -> Double {
        v.compact ? Double(RaceCompactFrame.wireLength(finished: f.finished)) : jsonBytes + (f.finished ? 12 : 0)
    }
    var publishers = (0..<n).map { _ in RaceDeadReckoningPublisher(threshold: v.threshold, heartbeat: v.heartbeat, finishDistance: finish) }
    for i in publishers.indices { publishers[i].closeOvertakeRange = v.closeOvertake }
    let thresholdOutside = v.thresholdOutside ?? v.threshold
    var throttles = (0..<n).map { _ in RacePublishThrottle(minInterval: v.fixedInterval, minStrokeInterval: v.fixedInterval, heartbeat: 1) }
    var trackers = (0..<n).map { _ in
        v.deadReckoning ? RemoteRowerTracker.deadReckoning(finishDistance: finish, heartbeat: v.heartbeat) : RemoteRowerTracker()
    }
    var lastSent = [LiveFrame?](repeating: nil, count: n)
    var done = [Bool](repeating: false, count: n)
    var seq = [Int](repeating: 0, count: n)
    var agg = v.deadReckoning
        ? RaceFieldAggregator(interval: v.fieldInterval, fullEvery: v.fullEvery, threshold: v.fieldThreshold, finishDistance: finish)
        : RaceFieldAggregator(interval: 1, fullEvery: 1, threshold: 0, finishDistance: finish)
    agg.finishZoneThreshold = v.fieldZoneThreshold ?? agg.threshold
    agg.finishZoneInterval = v.fieldZoneThreshold == nil ? nil : 5
    var fieldTracker = RaceFieldTracker(participants: field.participants, finishDistance: finish)
    var frameQueue: [(at: Double, i: Int, f: LiveFrame)] = []
    var aggQueue: [(at: Double, f: LiveFrame)] = []
    var fieldQueue: [(at: Double, s: RaceFieldSnapshot)] = []
    var interest = [[Int]](repeating: [], count: n)
    var subscribers = [Int](repeating: 0, count: n)
    var frames = 0, zoneFrames = 0, writes = 0, responses = 0
    var deviceBytes = 0.0, aggregatorBytes = 0.0, fieldBytes = 0.0
    var deltas = 0, deltaEntryCount = 0
    var reasons: [String: Int] = [:]
    var errPreOut: [Double] = [], errPreIn: [Double] = [], errCoaOut: [Double] = [], errCoaIn: [Double] = []
    var finishErr = 0.0
    var t = 0.0
    var step = 0
    var lastFinish = 0.0
    var dist = [Double](repeating: 0, count: n), speed = [Double](repeating: 0, count: n)
    var fin = [Bool](repeating: false, count: n), ft = [Double?](repeating: nil, count: n)
    while t < 900 {
        for i in 0..<n {
            let p = field.position(of: i, at: t)
            dist[i] = p.distance; speed[i] = p.speed; fin[i] = p.finished; ft[i] = p.finishTime
        }
        let order = (0..<n).sorted { dist[$0] < dist[$1] }
        var rank = [Int](repeating: 0, count: n)
        for (r, i) in order.enumerated() { rank[i] = r }
        func neighbours(_ i: Int, within r: Double) -> [Int] {
            var out: [Int] = []
            var a = rank[i] - 1
            while a >= 0, dist[i] - dist[order[a]] <= r { out.append(order[a]); a -= 1 }
            var b = rank[i] + 1
            while b < n, dist[order[b]] - dist[i] <= r { out.append(order[b]); b += 1 }
            return out
        }
        // Nachbarschaft alle 2 s
        if step % 20 == 0 {
            var newSubs = [Int](repeating: 0, count: n)
            for i in 0..<n where !fin[i] {
                let k = finish - dist[i] <= 250 ? v.kFinish : v.k
                // Kandidaten: die 2K nächsten; bisherige zählen 20 m näher (Hysterese wie im Planer)
                var a = rank[i] - 1, b = rank[i] + 1
                var cand: [Int] = []
                while cand.count < 2 * k && (a >= 0 || b < n) {
                    let da = a >= 0 ? dist[i] - dist[order[a]] : .infinity
                    let db = b < n ? dist[order[b]] - dist[i] : .infinity
                    if da <= db { cand.append(order[a]); a -= 1 } else { cand.append(order[b]); b += 1 }
                }
                let old = Set(interest[i])
                let list = Array(cand.sorted { x, y in
                    let ex = abs(dist[x] - dist[i]) - (old.contains(x) ? 20 : 0)
                    let ey = abs(dist[y] - dist[i]) - (old.contains(y) ? 20 : 0)
                    return ex < ey
                }.prefix(k))
                for j in list where !old.contains(j) {
                    if let f = lastSent[j] { deviceBytes += payload(f) + cost.eventOverhead; responses += 1 }
                }
                interest[i] = list
                for j in list { newSubs[j] += 1 }
            }
            for i in 0..<n where fin[i] { interest[i] = [] }
            subscribers = newSubs
        }
        // Senden
        for i in 0..<n where !done[i] {
            let pace = speed[i] > 0 ? 500 / speed[i] : 0
            let f = LiveFrame(participantId: field.bots[i].participant.id, raceId: "r", seq: seq[i] + 1, sentAt: t,
                              raceTime: t, distance: dist[i], pace: fin[i] ? 0 : pace,
                              strokeRate: fin[i] ? 0 : field.strokeRate(of: i, at: t), finished: fin[i], finishTime: ft[i])
            var send: Bool
            var zone = false
            if v.deadReckoning {
                let range = max(30, v.closeOvertake ?? 0)
                let nb = neighbours(i, within: range).map { j -> (gap: Double, closing: Double) in
                    let gap = dist[j] - dist[i]
                    return (gap, gap >= 0 ? speed[i] - speed[j] : speed[j] - speed[i])
                }
                zone = publishers[i].wantsPrecision(distanceToGo: finish - dist[i], neighbours: nb)
                publishers[i].threshold = finish - dist[i] <= 250 ? v.threshold : thresholdOutside
                send = publishers[i].shouldSend(f, now: t, precision: zone)
            } else {
                send = fin[i] || throttles[i].shouldSend(now: t, distance: dist[i], finished: fin[i])
            }
            guard send else { continue }
            if v.deadReckoning, let r = publishers[i].lastReason { reasons[r.rawValue, default: 0] += 1 }
            seq[i] += 1
            frames += 1
            if zone { zoneFrames += 1 }
            writes += 1
            let bytes = payload(f) + cost.eventOverhead
            deviceBytes += Double(subscribers[i]) * bytes + cost.writeAck
            aggregatorBytes += bytes
            responses += subscribers[i] + 2
            lastSent[i] = f
            frameQueue.append((t + latency, i, f))
            aggQueue.append((t + latency / 2, f))
            if fin[i] {
                done[i] = true
                finishErr = max(finishErr, abs((f.finishTime ?? 0) - (ft[i] ?? 0)))
                lastFinish = max(lastFinish, t)
            }
        }
        // Zustellen
        while let q = aggQueue.first, q.at <= t + 1e-9 { agg.receive(q.f); aggQueue.removeFirst() }
        while let q = frameQueue.first, q.at <= t + 1e-9 { trackers[q.i].receive(q.f, receivedLocal: q.at); frameQueue.removeFirst() }
        if let s = agg.tick(raceId: "r", raceTime: t, sentAt: t, roster: roster) {
            writes += 1
            let bytes = Double(s.wireBytes) + 20 + cost.eventOverhead
            deviceBytes += Double(n) * bytes
            fieldBytes += Double(n) * bytes
            if s.isDelta { deltas += 1; deltaEntryCount += s.entries.count }
            aggregatorBytes += cost.writeAck
            responses += n + 1
            fieldQueue.append((t + latency, s))
        }
        while let q = fieldQueue.first, q.at <= t + 1e-9 { fieldTracker.receive(q.s, receivedLocal: q.at); fieldQueue.removeFirst() }
        // Fehler messen (1/s)
        if step % 10 == 5 {
            for i in 0..<n where !fin[i] {
                let inZone = finish - dist[i] <= 250
                for j in interest[i] where !fin[j] {
                    guard let p = trackers[j].position(atRaceTime: t) else { continue }
                    let e = abs(p.distance - dist[j])
                    if inZone && abs(dist[j] - dist[i]) <= 30 { errPreIn.append(e) } else { errPreOut.append(e) }
                }
            }
            for c in fieldTracker.states(atRaceTime: t) {
                guard let j = roster.index(of: c.id), !fin[j] else { continue }
                let e = abs(c.distance - dist[j])
                if finish - dist[j] <= 250 { errCoaIn.append(e) } else { errCoaOut.append(e) }
            }
        }
        if done.allSatisfy({ $0 }) && t > lastFinish + 1 { break }
        t += dt
        step += 1
    }
    func stats(_ a: [Double]) -> (Double, Double, Double) {
        guard !a.isEmpty else { return (0, 0, 0) }
        let s = a.sorted()
        return (s.reduce(0, +) / Double(s.count), s[Int(Double(s.count - 1) * 0.95)], s.last!)
    }
    let duration = t
    let total = deviceBytes + aggregatorBytes
    let aggregatorMinutes = duration / 60 + (v.smallAggregator ? 1 : 4)
    var aggCost = cost
    if v.smallAggregator { aggCost.aggregatorUSDPerMinute = RaceCostModel.aggregatorUSDPerMinute(vCPU: 0.25, GiB: 0.25) }
    return NetResult(variant: v, duration: duration, framesPerParticipantSecond: Double(frames) / Double(n) / duration,
                     deviceBytesPerSecond: deviceBytes / Double(n) / duration, writesPerSecond: Double(writes) / duration,
                     responsesPerSecond: Double(responses) / duration, totalDownload: total,
                     usdPerRace: aggCost.usd(downloadBytes: total, aggregatorMinutes: aggregatorMinutes),
                     preciseOut: stats(errPreOut), preciseIn: stats(errPreIn), coarseOut: stats(errCoaOut),
                     coarseIn: stats(errCoaIn), finishTimeMaxError: finishErr,
                     zoneFramesPerSecond: Double(zoneFrames) / Double(n) / duration,
                     fieldBytesPerSecond: fieldBytes / Double(n) / duration,
                     deltaEntries: deltas > 0 ? Double(deltaEntryCount) / Double(deltas) : 0,
                     reasons: reasons.mapValues { Double($0) / Double(max(frames, 1)) })
}

/// Der gewählte Satz (Standard im Kit): Dead Reckoning 4 m / 20 s, K 8 (16 in der Zielzone), Binärframes, Übersicht
/// 10 s Delta (8 m) bzw. 5 s (1 m) in der Zielzone, voll beim Beitritt und alle 300 s, kleiner Aggregator
func chosenVariant() -> NetVariant {
    var v = NetVariant(name: "gewählter Satz")
    v.heartbeat = 20; v.k = 8; v.compact = true
    v.fieldInterval = 10; v.fullEvery = 300; v.fieldThreshold = 8; v.fieldZoneThreshold = 1
    v.smallAggregator = true
    return v
}

final class RaceNetworkMeasurementTests: XCTestCase {
    /// Kosten je Teilnehmer und Rennen und je Abonnent im Monat (15 Rennen) für Feldgrössen 10, 50, 300
    func testCostPerSubscriberByFieldSize() {
        for n in [10, 50, 300] {
            let r = simulateRace(chosenVariant(), count: n)
            let perRace = r.usdPerRace / Double(n)
            print("KOSTEN | \(n) | \(String(format: "%.0f", r.deviceBytesPerSecond)) B/s | \(String(format: "%.1f", r.writesPerSecond)) Schreiben/s | \(String(format: "%.0f", r.responsesPerSecond)) Antworten/s | Download \(String(format: "%.4f", r.totalDownload / 1e9)) GB | USD/Rennen \(String(format: "%.4f", r.usdPerRace)) | USD/Teiln. \(String(format: "%.6f", perRace)) | USD/Abo-Monat \(String(format: "%.5f", perRace * 15)) | Dauer \(Int(r.duration)) s")
            XCTAssertLessThan(perRace * 15, 0.05, "Rennkosten je Abonnent und Monat weit unter 1 % von 5 USD")
            XCTAssertLessThan(r.finishTimeMaxError, 0.001)
        }
    }


    func testMeasureVariantsOver2000mWith300Bots() {
        let old = NetVariant(name: "bisheriger Plan (2,5/s, K 16, Übersicht 1/s)", deadReckoning: false, fieldInterval: 1, fullEvery: 1)
        let dr = NetVariant(name: "Dead Reckoning (4 m, 8 s, K 16, Übersicht 5 s Delta / 30 s voll)")
        var drOvertake = dr; drOvertake.name = "DR + dichter beim knappen Überholen (< 10 m)"; drOvertake.closeOvertake = 10
        var k8 = dr; k8.name = "DR + K 8 ausserhalb der Zielzone"; k8.k = 8
        var compact = k8; compact.name = "… + Binärframes (24 statt ≈ 130 Byte)"; compact.compact = true
        var hb = compact; hb.name = "… + Lebenszeichen 20 s"; hb.heartbeat = 20
        var fieldSlow = hb; fieldSlow.name = "… + Übersicht 10 s Delta (8 m), voll nur beim Beitritt und alle 300 s"
        fieldSlow.fieldInterval = 10; fieldSlow.fullEvery = 300; fieldSlow.fieldThreshold = 8
        var zoneField = fieldSlow; zoneField.name = "… + Übersicht in der Zielzone alle 5 s mit 1 m Schwelle"; zoneField.fieldZoneThreshold = 1
        var thr6 = zoneField; thr6.name = "… + Schwelle 6 m ausserhalb der Zielzone"; thr6.thresholdOutside = 6
        var small = thr6; small.name = "… + kleiner Aggregator (0,25 vCPU, nur Rennfenster)"; small.smallAggregator = true
        let variants = [old, dr, drOvertake, k8, compact, hb, fieldSlow, zoneField, thr6, small]
        var results: [NetResult] = []
        for v in variants { results.append(simulateRace(v)) }
        func f(_ x: Double, _ d: Int = 2) -> String { String(format: "%.\(d)f", x) }
        print("MESS | Variante | Frames/Teiln./s | Bytes/s je Gerät | Schreiben/s | Antworten/s | Download GB | USD je Rennen | USD je Teiln. | Fehler nah aussen Mittel/95%/max | Fehler nah Zielzone | Übersicht aussen | Übersicht Zielzone | Zielzeitfehler | Dauer")
        for r in results {
            print("MESS | \(r.variant.name) | \(f(r.framesPerParticipantSecond, 3)) | \(f(r.deviceBytesPerSecond, 0)) | \(f(r.writesPerSecond, 0)) | \(f(r.responsesPerSecond, 0)) | \(f(r.totalDownload / 1e9, 3)) | \(f(r.usdPerRace, 3)) | \(f(r.usdPerRace / 300, 5)) | \(f(r.preciseOut.mean))/\(f(r.preciseOut.p95))/\(f(r.preciseOut.max)) | \(f(r.preciseIn.mean))/\(f(r.preciseIn.p95))/\(f(r.preciseIn.max)) | \(f(r.coarseOut.mean))/\(f(r.coarseOut.p95))/\(f(r.coarseOut.max)) | \(f(r.coarseIn.mean))/\(f(r.coarseIn.p95))/\(f(r.coarseIn.max)) | \(f(r.finishTimeMaxError, 4)) | \(f(r.duration, 0)) s | Zone-Frames/Teiln./s \(f(r.zoneFramesPerSecond, 3)) | Übersicht B/s \(f(r.fieldBytesPerSecond, 0)), Einträge je Delta \(f(r.deltaEntries, 1)) | Gründe \(r.reasons.sorted { $0.value > $1.value }.map { "\($0.key) \(Int(($0.value * 100).rounded())) %" }.joined(separator: ", "))")
        }
        let o = results[0], d = results[1], best = results.last!
        XCTAssertLessThan(d.deviceBytesPerSecond, o.deviceBytesPerSecond / 5, "Dead Reckoning spart Download")
        XCTAssertLessThan(d.framesPerParticipantSecond, 0.5)
        XCTAssertLessThanOrEqual(best.usdPerRace, d.usdPerRace / 3, "Hebel: ≤ 1/3 der Dead-Reckoning-Kosten")
        for r in results {
            XCTAssertLessThan(r.finishTimeMaxError, 0.001, "Zielzeit exakt")
            XCTAssertLessThan(r.writesPerSecond, 1000)
            XCTAssertLessThan(r.responsesPerSecond, 100_000)
        }
        // Zieleinlauf nicht schlechter als mit Dead Reckoning allein (nahe Boote voll, fernere aus der Übersicht)
        XCTAssertLessThanOrEqual(best.preciseIn.p95, d.preciseIn.p95 + 0.05)
        XCTAssertLessThanOrEqual(best.coarseIn.p95, d.coarseIn.p95 + 0.25)
        XCTAssertLessThan(d.preciseIn.p95, 1.5)
        XCTAssertLessThan(d.preciseOut.p95, 5)
    }
}
